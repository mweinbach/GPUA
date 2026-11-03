// Ported from: crates/rune/src/gpu/metal/resource.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `MetalBuffer`, `MetalTexture`, `MetalView`, and `MetalSampler` resources in `gpu/metal`.
//!
//! New textures are zero-filled through the device's pending blit upload buffer so unwritten
//! layers and mip levels read back as zero (`new_textures_read_as_zero`), matching WebGPU's
//! zero-initialization guarantee.

#if canImport(Metal)
import Metal
#endif
#if !os(WASI)
import Foundation
#endif
import CWebGPU

#if canImport(Metal)
public func metalPixelFormat(for format: WGPUTextureFormat) -> MTLPixelFormat {
    switch format {
    case WGPUTextureFormat_R8Unorm:
        return .r8Unorm
    case WGPUTextureFormat_RG8Unorm:
        return .rg8Unorm
    case WGPUTextureFormat_RGBA8Unorm:
        return .rgba8Unorm
    case WGPUTextureFormat_RGBA8UnormSrgb:
        return .rgba8Unorm_srgb
    case WGPUTextureFormat_BGRA8Unorm:
        return .bgra8Unorm
    case WGPUTextureFormat_BGRA8UnormSrgb:
        return .bgra8Unorm_srgb
    case WGPUTextureFormat_RGB10A2Unorm:
        return .rgb10a2Unorm
    case WGPUTextureFormat_RGBA16Float:
        return .rgba16Float
    case WGPUTextureFormat_R32Float:
        return .r32Float
    case WGPUTextureFormat_RGBA32Float:
        return .rgba32Float
    default:
        return .rgba8Unorm
    }
}
#endif

public func metalFormatBytesPerPixel(_ format: WGPUTextureFormat) -> Int {
    switch format {
    case WGPUTextureFormat_R8Unorm: return 1
    case WGPUTextureFormat_RG8Unorm: return 2
    case WGPUTextureFormat_RGBA16Float: return 8
    case WGPUTextureFormat_RGBA32Float: return 16
    default: return 4
    }
}

/// GPU buffer backed by `MetalBufferStore` (`MTLStorageModeShared` on Apple platforms).
// PORT NOTE: Thread-safe handle synchronized via `MetalBufferStore` and `mapLock`.
public final class MetalBuffer: @unchecked Sendable {
    public let shared: MetalShared
    public let size: Int
    public let label: String?
    public let store: MetalBufferStore
    private let mapLock = LiveLock()
    private var mappedRange: Range<Int>? = nil

    public init(shared: MetalShared, size: Int, label: String? = nil) {
        self.shared = shared
        self.size = size
        self.label = label
        #if canImport(Metal)
        self.store = MetalBufferStore(
            device: shared.mtlDevice,
            length: size,
            label: label,
            onAllocate: { [weak shared] in shared?.incrementLiveBuffers() },
            onFree: { [weak shared] in shared?.decrementLiveBuffers() }
        )
        #else
        self.store = MetalBufferStore(
            length: size,
            label: label,
            onAllocate: { [weak shared] in shared?.incrementLiveBuffers() },
            onFree: { [weak shared] in shared?.decrementLiveBuffers() }
        )
        #endif
    }

    public func writeInPlace(offset: UInt64, data: [UInt8]) -> Bool {
        data.withUnsafeBytes { raw in
            store.writeInPlace(offset: Int(offset), bytes: raw, completedSubmission: shared.completedSubmission)
        }
    }

    public func mapAsync(range: Range<Int>? = nil, callback: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        let r = range ?? (0..<size)
        mapLock.withLock { mappedRange = r }
        shared.enqueueCallback(.map(callback))
    }

    public func getMappedRange(_ range: Range<Int>? = nil) -> [UInt8] {
        let r = range ?? mapLock.withLock { mappedRange } ?? (0..<size)
        return store.readBytes(r)
    }

    public func unmap() {
        mapLock.withLock { mappedRange = nil }
    }
}

/// Underlying `MTLTexture` + optional external lifetime owner (e.g. `CVPixelBuffer` / `IOSurface`).
// PORT NOTE: Wraps an immutable `MTLTexture` descriptor and optional lifetime `owner`, safe to share across threads.
public final class MetalTextureRaw: @unchecked Sendable {
    public let format: WGPUTextureFormat
    public let width: UInt32
    public let height: UInt32
    public let arrayLayers: UInt32
    public let mipLevelCount: UInt32
    public let usage: UInt32
    public let owner: AnyObject?
    #if canImport(Metal)
    public let mtlTexture: (any MTLTexture)?
    #endif
    let hostLock = LiveLock()
    var hostSlices: [[[UInt8]]] // [layer][mip]

    #if canImport(Metal)
    public init(
        shared: MetalShared,
        label: String?,
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        arrayLayers: UInt32,
        mipLevelCount: UInt32,
        usage: UInt32,
        existingTexture: (any MTLTexture)? = nil,
        owner: AnyObject? = nil
    ) {
        self.format = format
        self.width = width
        self.height = height
        self.arrayLayers = max(1, arrayLayers)
        self.mipLevelCount = max(1, mipLevelCount)
        self.usage = usage == 0 ? 0x1F : usage
        self.owner = owner

        if let existingTexture {
            self.mtlTexture = existingTexture
            self.hostSlices = []
            return
        }

        if let dev = shared.mtlDevice {
            let desc = MTLTextureDescriptor()
            desc.textureType = arrayLayers > 1 ? .type2DArray : .type2D
            desc.pixelFormat = metalPixelFormat(for: format)
            desc.width = Int(max(1, width))
            desc.height = Int(max(1, height))
            desc.arrayLength = Int(max(1, arrayLayers))
            desc.mipmapLevelCount = Int(max(1, mipLevelCount))
            desc.storageMode = .private
            desc.usage = [.shaderRead, .shaderWrite, .renderTarget, .pixelFormatView]
            let tex = dev.makeTexture(descriptor: desc)
            if let label, let tex { tex.label = label }
            self.mtlTexture = tex
            self.hostSlices = []

            // Zero-fill every layer and mip level on the next submit (`new_textures_read_as_zero`
            // and `a_frame_is_one_command_buffer_and_writes_land`).
            if let tex {
                let bpp = metalFormatBytesPerPixel(format)
                var maxSliceBytes = 0
                for mip in 0..<Int(self.mipLevelCount) {
                    let mw = max(1, Int(width) >> mip)
                    let mh = max(1, Int(height) >> mip)
                    maxSliceBytes = max(maxSliceBytes, mw * mh * bpp)
                }
                if maxSliceBytes > 0, let zeroBuf = dev.makeBuffer(length: maxSliceBytes, options: .storageModeShared) {
                    memset(zeroBuf.contents(), 0, maxSliceBytes)
                    shared.enqueueBlitUpload(keepObjects: [tex, zeroBuf]) { blit in
                        for layer in 0..<Int(self.arrayLayers) {
                            for mip in 0..<Int(self.mipLevelCount) {
                                let mw = max(1, Int(width) >> mip)
                                let mh = max(1, Int(height) >> mip)
                                blit.copy(
                                    from: zeroBuf,
                                    sourceOffset: 0,
                                    sourceBytesPerRow: mw * bpp,
                                    sourceBytesPerImage: mw * mh * bpp,
                                    sourceSize: MTLSize(width: mw, height: mh, depth: 1),
                                    to: tex,
                                    destinationSlice: layer,
                                    destinationLevel: mip,
                                    destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
                                )
                            }
                        }
                    }
                }
            }
        } else {
            self.mtlTexture = nil
            self.hostSlices = Self.allocateHostZeroes(
                format: format,
                width: width,
                height: height,
                layers: self.arrayLayers,
                mips: self.mipLevelCount
            )
            shared.enqueueHostUpload {}
        }
    }
    #else
    public init(
        shared: MetalShared,
        label: String?,
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        arrayLayers: UInt32,
        mipLevelCount: UInt32,
        usage: UInt32,
        owner: AnyObject? = nil
    ) {
        _ = label
        self.format = format
        self.width = width
        self.height = height
        self.arrayLayers = max(1, arrayLayers)
        self.mipLevelCount = max(1, mipLevelCount)
        self.usage = usage == 0 ? 0x1F : usage
        self.owner = owner
        self.hostSlices = Self.allocateHostZeroes(
            format: format,
            width: width,
            height: height,
            layers: self.arrayLayers,
            mips: self.mipLevelCount
        )
        shared.enqueueHostUpload {}
    }
    #endif

    private static func allocateHostZeroes(
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        layers: UInt32,
        mips: UInt32
    ) -> [[[UInt8]]] {
        let bpp = metalFormatBytesPerPixel(format)
        var out: [[[UInt8]]] = []
        for _ in 0..<layers {
            var layerMips: [[UInt8]] = []
            for mip in 0..<mips {
                let mw = max(1, Int(width) >> Int(mip))
                let mh = max(1, Int(height) >> Int(mip))
                layerMips.append([UInt8](repeating: 0, count: mw * mh * bpp))
            }
            out.append(layerMips)
        }
        return out
    }
}

/// Logical texture in Rune's Metal backend.
public final class MetalTexture: Sendable {
    public let raw: MetalTextureRaw

    public init(raw: MetalTextureRaw) {
        self.raw = raw
    }

    public init(
        shared: MetalShared,
        label: String? = nil,
        format: WGPUTextureFormat,
        width: UInt32,
        height: UInt32,
        arrayLayers: UInt32 = 1,
        mipLevelCount: UInt32 = 1,
        usage: UInt32 = 0
    ) {
        self.raw = MetalTextureRaw(
            shared: shared,
            label: label,
            format: format,
            width: width,
            height: height,
            arrayLayers: arrayLayers,
            mipLevelCount: mipLevelCount,
            usage: usage
        )
    }

    #if canImport(Metal)
    public init(rawTexture: any MTLTexture, format: WGPUTextureFormat, shared: MetalShared, owner: AnyObject? = nil) {
        self.raw = MetalTextureRaw(
            shared: shared,
            label: rawTexture.label,
            format: format,
            width: UInt32(rawTexture.width),
            height: UInt32(rawTexture.height),
            arrayLayers: UInt32(rawTexture.arrayLength),
            mipLevelCount: UInt32(rawTexture.mipmapLevelCount),
            usage: 0,
            existingTexture: rawTexture,
            owner: owner
        )
    }
    #endif

    public var width: UInt32 { raw.width }
    public var height: UInt32 { raw.height }
    public var format: WGPUTextureFormat { raw.format }
    public var usage: UInt32 { raw.usage }

    public func createView(
        format: WGPUTextureFormat? = nil,
        baseMipLevel: UInt32 = 0,
        mipLevelCount: UInt32? = nil,
        baseArrayLayer: UInt32 = 0,
        arrayLayerCount: UInt32? = nil
    ) -> MetalView {
        MetalView(
            texture: raw,
            format: format,
            baseMipLevel: baseMipLevel,
            mipLevelCount: mipLevelCount ?? (raw.mipLevelCount - baseMipLevel),
            baseArrayLayer: baseArrayLayer,
            arrayLayerCount: arrayLayerCount ?? (raw.arrayLayers - baseArrayLayer)
        )
    }
}

/// Texture view retaining its parent `MetalTextureRaw` (and any external `owner`).
// PORT NOTE: Immutable view wrapper around `MTLTexture` slice/mip subrange.
public final class MetalView: @unchecked Sendable, Equatable {
    public static func == (lhs: MetalView, rhs: MetalView) -> Bool {
        lhs === rhs
    }

    public let raw: MetalTextureRaw
    public let viewFormat: WGPUTextureFormat
    public let baseMipLevel: UInt32
    public let mipLevelCount: UInt32
    public let baseArrayLayer: UInt32
    public let arrayLayerCount: UInt32
    #if canImport(Metal)
    public let mtlTexture: (any MTLTexture)?
    #endif

    public init(
        texture: MetalTextureRaw,
        format: WGPUTextureFormat? = nil,
        baseMipLevel: UInt32 = 0,
        mipLevelCount: UInt32 = 1,
        baseArrayLayer: UInt32 = 0,
        arrayLayerCount: UInt32 = 1
    ) {
        let resolvedFormat = format ?? texture.format
        self.raw = texture
        self.viewFormat = resolvedFormat
        self.baseMipLevel = baseMipLevel
        self.mipLevelCount = mipLevelCount
        self.baseArrayLayer = baseArrayLayer
        self.arrayLayerCount = arrayLayerCount
        #if canImport(Metal)
        if let baseTex = texture.mtlTexture {
            let targetPixelFormat = metalPixelFormat(for: resolvedFormat)
            if targetPixelFormat == baseTex.pixelFormat &&
               baseMipLevel == 0 && mipLevelCount == texture.mipLevelCount &&
               baseArrayLayer == 0 && arrayLayerCount == texture.arrayLayers &&
               texture.arrayLayers == 1 {
                self.mtlTexture = baseTex
            } else {
                let targetType: MTLTextureType = arrayLayerCount > 1 ? .type2DArray : .type2D
                self.mtlTexture = baseTex.makeTextureView(
                    pixelFormat: targetPixelFormat,
                    textureType: targetType,
                    levels: Int(baseMipLevel)..<Int(baseMipLevel + mipLevelCount),
                    slices: Int(baseArrayLayer)..<Int(baseArrayLayer + arrayLayerCount)
                ) ?? baseTex
            }
        } else {
            self.mtlTexture = nil
        }
        #endif
    }
}

/// Texture sampler state in Rune's Metal backend.
// PORT NOTE: Immutable `MTLSamplerState` wrapper, thread-safe on Metal.
public final class MetalSampler: @unchecked Sendable {
    public let linear: Bool
    #if canImport(Metal)
    public let mtlSampler: (any MTLSamplerState)?
    #endif

    public init(shared: MetalShared, linear: Bool = false) {
        self.linear = linear
        #if canImport(Metal)
        if let dev = shared.mtlDevice {
            let desc = MTLSamplerDescriptor()
            let mode: MTLSamplerMinMagFilter = linear ? .linear : .nearest
            desc.minFilter = mode
            desc.magFilter = mode
            desc.mipFilter = linear ? .linear : .notMipmapped
            desc.sAddressMode = .clampToEdge
            desc.tAddressMode = .clampToEdge
            self.mtlSampler = dev.makeSamplerState(descriptor: desc)
        } else {
            self.mtlSampler = nil
        }
        #else
        _ = shared
        #endif
    }
}
