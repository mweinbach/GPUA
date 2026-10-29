// Swift-only: Offscreen texture readback helper for deterministic headless CI testing

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import CWebGPU

public enum WgpuError: Error, CustomStringConvertible, Sendable {
    case bufferCreationFailed
    case encoderCreationFailed
    case commandBufferCreationFailed
    case mapBufferFailed(UInt32, String)
    case getMappedRangeFailed
    case textureCreationFailed
    case textureViewCreationFailed
    case shaderCompilationFailed(String)
    case pipelineCreationFailed(String)
    case surfaceCreationFailed
    case noCompatibleAdapter
    case deviceLost

    public var description: String {
        switch self {
        case .bufferCreationFailed:
            return "WgpuError: Failed to create buffer"
        case .encoderCreationFailed:
            return "WgpuError: Failed to create command encoder"
        case .commandBufferCreationFailed:
            return "WgpuError: Failed to create command buffer"
        case .mapBufferFailed(let status, let msg):
            return "WgpuError: Failed to map buffer (status: \(status), message: \(msg))"
        case .getMappedRangeFailed:
            return "WgpuError: Failed to get mapped range"
        case .textureCreationFailed:
            return "WgpuError: Failed to create texture"
        case .textureViewCreationFailed:
            return "WgpuError: Failed to create texture view"
        case .shaderCompilationFailed(let msg):
            return "WgpuError: Shader compilation failed: \(msg)"
        case .pipelineCreationFailed(let msg):
            return "WgpuError: Pipeline creation failed: \(msg)"
        case .surfaceCreationFailed:
            return "WgpuError: Failed to create surface"
        case .noCompatibleAdapter:
            return "WgpuError: No compatible GPU adapter found"
        case .deviceLost:
            return "WgpuError: GPU device was lost"
        }
    }
}

/// Helper for copying offscreen render targets into host CPU memory for headless verification.
public struct OffscreenTextureReadbackHelper: Sendable {
    /// WebGPU requirement: bytesPerRow for texture copies must be a multiple of 256.
    public static let copyBytesPerRowAlignment: Int = 256

    // PORT NOTE: Synchronous texture readback helper for headless testing and pixel assertions.
    public static func readbackRGBA(
        device: WGPUDevice,
        queue: WGPUQueue,
        texture: WGPUTexture,
        width: Int,
        height: Int
    ) throws -> [UInt8] {
        guard width > 0 && height > 0 else {
            return []
        }

        #if os(Linux)
        let unalignedBytesPerRow = width * 4
        let alignedBytesPerRow = (unalignedBytesPerRow + copyBytesPerRowAlignment - 1) & ~(copyBytesPerRowAlignment - 1)
        let bufferSize = alignedBytesPerRow * height

        // 1. Create staging readback buffer
        var bufferDesc = WGPUBufferDescriptor()
        bufferDesc.label = WGPUStringView(data: nil, length: 0)
        bufferDesc.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst
        bufferDesc.size = UInt64(bufferSize)
        bufferDesc.mappedAtCreation = 0
        guard let stagingBuffer = wgpuDeviceCreateBuffer(device, &bufferDesc) else {
            throw WgpuError.bufferCreationFailed
        }
        defer { wgpuBufferRelease(stagingBuffer) }

        // 2. Encode texture copy to buffer
        var encoderDesc = WGPUCommandEncoderDescriptor()
        encoderDesc.label = WGPUStringView(data: nil, length: 0)
        guard let encoder = wgpuDeviceCreateCommandEncoder(device, &encoderDesc) else {
            throw WgpuError.encoderCreationFailed
        }

        var sourceCopy = WGPUTexelCopyTextureInfo()
        sourceCopy.texture = texture
        sourceCopy.mipLevel = 0
        sourceCopy.origin = WGPUOrigin3D(x: 0, y: 0, z: 0)
        sourceCopy.aspect = WGPUTextureAspect_All

        var destCopy = WGPUTexelCopyBufferInfo()
        destCopy.buffer = stagingBuffer
        destCopy.layout = WGPUTexelCopyBufferLayout(
            offset: 0,
            bytesPerRow: UInt32(alignedBytesPerRow),
            rowsPerImage: UInt32(height)
        )

        var copyExtent = WGPUExtent3D(width: UInt32(width), height: UInt32(height), depthOrArrayLayers: 1)
        wgpuCommandEncoderCopyTextureToBuffer(encoder, &sourceCopy, &destCopy, &copyExtent)

        var cmdDesc = WGPUCommandBufferDescriptor()
        cmdDesc.label = WGPUStringView(data: nil, length: 0)
        guard let cmdBuffer = wgpuCommandEncoderFinish(encoder, &cmdDesc) else {
            wgpuCommandEncoderRelease(encoder)
            throw WgpuError.commandBufferCreationFailed
        }
        defer { wgpuCommandBufferRelease(cmdBuffer) }
        wgpuCommandEncoderRelease(encoder)

        // 3. Submit work to GPU queue
        var commands: [WGPUCommandBuffer?] = [cmdBuffer]
        wgpuQueueSubmit(queue, 1, &commands)

        // 4. Map buffer asynchronously & synchronize
        // PORT NOTE: MapContext is an internal asynchronous completion context synchronized via synchronous device polling.
        final class MapContext: @unchecked Sendable {
            var completed = false
            var status: WGPUMapAsyncStatus = WGPUMapAsyncStatus_Unknown
            var message: String = ""
        }
        let mapContext = MapContext()
        let unmanaged = Unmanaged.passRetained(mapContext)

        var callbackInfo = WGPUBufferMapCallbackInfo()
        callbackInfo.mode = WGPUCallbackMode_AllowProcessEvents
        callbackInfo.userdata1 = unmanaged.toOpaque()
        callbackInfo.callback = { status, msg, u1, _ in
            guard let u1 = u1 else { return }
            let ctx = Unmanaged<MapContext>.fromOpaque(u1).takeRetainedValue()
            ctx.status = status
            if let ptr = msg.data, msg.length > 0 {
                let buf = UnsafeRawBufferPointer(start: ptr, count: Int(msg.length))
                ctx.message = String(decoding: buf, as: UTF8.self)
            }
            ctx.completed = true
        }

        _ = wgpuBufferMapAsync(stagingBuffer, WGPUMapMode_Read, 0, bufferSize, callbackInfo)

        // Poll device until buffer mapping completes
        while !mapContext.completed {
            _ = wgpuDevicePoll(device, 1, nil)
        }

        guard mapContext.status == WGPUMapAsyncStatus_Success else {
            throw WgpuError.mapBufferFailed(mapContext.status.rawValue, mapContext.message)
        }

        // 5. Extract mapped pixels and unpack rows
        guard let mappedPtr = wgpuBufferGetConstMappedRange(stagingBuffer, 0, bufferSize) else {
            throw WgpuError.getMappedRangeFailed
        }

        var result = [UInt8](repeating: 0, count: width * height * 4)
        result.withUnsafeMutableBytes { dstBytes in
            guard let dstBase = dstBytes.baseAddress else { return }
            for row in 0..<height {
                let srcRowPtr = mappedPtr.advanced(by: row * alignedBytesPerRow)
                let dstRowPtr = dstBase.advanced(by: row * width * 4)
                memcpy(dstRowPtr, srcRowPtr, width * 4)
            }
        }

        wgpuBufferUnmap(stagingBuffer)
        return result
        #else
        // PORT NOTE: WebGPU C runtime calls are gated on os(Linux) because libwgpu_native is linked on Linux, while Windows uses D3D11 in GPUIWindows and Android/WASI backends are deferred per R3.
        throw WgpuError.noCompatibleAdapter
        #endif
    }
}
#endif
