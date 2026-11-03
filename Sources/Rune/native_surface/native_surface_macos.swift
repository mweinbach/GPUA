// Ported from: crates/rune/src/native_surface/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import CoreVideo
import Foundation
import IOSurface
import Metal
import CWebGPU

//! CoreVideo ownership boundary. Decoder output must be complete and immutable before handoff.

/// A retained, immutable `CVPixelBuffer`, normally supplied by VideoToolbox / `AVPlayerItemVideoOutput`.
// PORT NOTE: CoreVideo retain/release and read-only buffer access are thread-safe once decoding/writes
// have completed, matching `unsafe impl Send + Sync for PixelBuffer` in `native_surface/macos.rs`.
public final class PixelBuffer: @unchecked Sendable {
    public let cvBuffer: CVPixelBuffer

    public init(_ cvBuffer: CVPixelBuffer) {
        self.cvBuffer = cvBuffer
    }

    /// Retain a borrowed `CVPixelBufferRef` (does not consume the caller's retain).
    public static func fromRaw(_ raw: UnsafeMutableRawPointer?) -> Result<PixelBuffer, SurfaceError> {
        guard let raw else {
            return .failure(SurfaceError("null CVPixelBuffer"))
        }
        let retained = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeUnretainedValue()
        return .success(PixelBuffer(retained))
    }

    /// Wrap an `IOSurfaceRef` without copying. The new `CVPixelBuffer` retains the surface.
    public static func fromIOSurface(_ raw: UnsafeMutableRawPointer?, _ color: ColorInfo) -> Result<PixelBuffer, SurfaceError> {
        guard let raw else {
            return .failure(SurfaceError("null IOSurface"))
        }
        let surface = Unmanaged<IOSurfaceRef>.fromOpaque(raw).takeUnretainedValue()
        var out: Unmanaged<CVPixelBuffer>? = nil
        let status = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, nil, &out)
        if status != kCVReturnSuccess {
            return .failure(SurfaceError("CVPixelBufferCreateWithIOSurface: CoreVideo status \(status)"))
        }
        guard let created = out?.takeRetainedValue() else {
            return .failure(SurfaceError("null pixel buffer"))
        }
        let buffer = PixelBuffer(created)
        buffer.setColor(color)
        switch buffer.info() {
        case .failure(let err): return .failure(err)
        case .success: return .success(buffer)
        }
    }

    private func setColor(_ color: ColorInfo) {
        let matrixVal: CFString = switch color.matrix {
        case .bt601: kCVImageBufferYCbCrMatrix_ITU_R_601_4
        case .bt709: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        }
        CVBufferSetAttachment(cvBuffer, kCVImageBufferYCbCrMatrixKey, matrixVal, .shouldPropagate)

        let transferVal: CFString = switch color.transfer {
        case .srgb: kCVImageBufferTransferFunction_sRGB
        case .bt709: kCVImageBufferTransferFunction_ITU_R_709_2
        }
        CVBufferSetAttachment(cvBuffer, kCVImageBufferTransferFunctionKey, transferVal, .shouldPropagate)
    }

    func info() -> Result<([UInt32], SurfaceFormat, ColorInfo), SurfaceError> {
        let pf = CVPixelBufferGetPixelFormatType(cvBuffer)
        let format: SurfaceFormat
        switch pf {
        case kCVPixelFormatType_32BGRA:
            format = .bgra
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            format = .nv12Video
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            format = .nv12Full
        default:
            return .failure(SurfaceError(String(format: "unsupported CVPixelBuffer format 0x%x; use BGRA, 420v or 420f", pf)))
        }

        let w = UInt32(CVPixelBufferGetWidth(cvBuffer))
        let h = UInt32(CVPixelBufferGetHeight(cvBuffer))
        if w == 0 || h == 0 || w > 16384 || h > 16384 {
            return .failure(SurfaceError("invalid video dimensions"))
        }
        if format != .bgra && (w % 2 != 0 || h % 2 != 0 || CVPixelBufferGetPlaneCount(cvBuffer) != 2) {
            return .failure(SurfaceError("NV12 requires two planes and even dimensions"))
        }

        let matrixAttachment = CVBufferCopyAttachment(cvBuffer, kCVImageBufferYCbCrMatrixKey, nil)
        let matrix: SurfaceMatrix
        if let m = matrixAttachment {
            if CFEqual(m, kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
                matrix = .bt601
            } else if CFEqual(m, kCVImageBufferYCbCrMatrix_ITU_R_709_2) {
                matrix = .bt709
            } else {
                return .failure(SurfaceError("unsupported YCbCr matrix; use BT.601 or BT.709"))
            }
        } else {
            matrix = (h <= 576) ? .bt601 : .bt709
        }

        let transferAttachment = CVBufferCopyAttachment(cvBuffer, kCVImageBufferTransferFunctionKey, nil)
        let transfer: SurfaceTransfer
        if let t = transferAttachment {
            if CFEqual(t, kCVImageBufferTransferFunction_sRGB) {
                transfer = .srgb
            } else if CFEqual(t, kCVImageBufferTransferFunction_ITU_R_709_2) {
                transfer = .bt709
            } else {
                return .failure(SurfaceError("unsupported transfer function; use sRGB or BT.709 (HDR is not supported)"))
            }
        } else {
            transfer = (format == .bgra) ? .srgb : .bt709
        }

        return .success(([w, h], format, ColorInfo(matrix: matrix, transfer: transfer)))
    }

    /// Test source only: create a Metal-compatible IOSurface-backed `CVPixelBuffer` and fill it before publishing.
    public static func fromBytes(_ frame: ByteFrame) -> Result<PixelBuffer, SurfaceError> {
        let w = Int(frame.width)
        let h = Int(frame.height)
        if w == 0 || h == 0 || w > 16384 || h > 16384 {
            return .failure(SurfaceError("invalid dimensions"))
        }
        let nv12 = frame.format != .bgra
        if nv12 && (w % 2 != 0 || h % 2 != 0) {
            return .failure(SurfaceError("odd NV12 dimensions"))
        }
        guard frame.planes.count == 2,
              frame.planes[0].count == w * h * (nv12 ? 1 : 4),
              frame.planes[1].count == (nv12 ? (w * h / 2) : 0)
        else {
            return .failure(SurfaceError("invalid plane length"))
        }

        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        let pf: OSType = switch frame.format {
        case .bgra: kCVPixelFormatType_32BGRA
        case .nv12Video: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        case .nv12Full: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }

        var raw: CVPixelBuffer? = nil
        let status = CVPixelBufferCreate(kCFAllocatorDefault, w, h, pf, attrs as CFDictionary, &raw)
        if status != kCVReturnSuccess {
            return .failure(SurfaceError("CVPixelBufferCreate: CoreVideo status \(status)"))
        }
        guard let created = raw else {
            return .failure(SurfaceError("null created pixel buffer"))
        }

        let lockStatus = CVPixelBufferLockBaseAddress(created, [])
        if lockStatus != kCVReturnSuccess {
            return .failure(SurfaceError("lock synthetic buffer: CoreVideo status \(lockStatus)"))
        }
        defer {
            CVPixelBufferUnlockBaseAddress(created, [])
        }

        let planeCount = nv12 ? 2 : 1
        for plane in 0..<planeCount {
            let dstPtr: UnsafeMutableRawPointer?
            let dstStride: Int
            if nv12 {
                dstPtr = CVPixelBufferGetBaseAddressOfPlane(created, plane)
                dstStride = CVPixelBufferGetBytesPerRowOfPlane(created, plane)
            } else {
                dstPtr = CVPixelBufferGetBaseAddress(created)
                dstStride = CVPixelBufferGetBytesPerRow(created)
            }
            guard let dstBase = dstPtr else {
                return .failure(SurfaceError("null CVPixelBuffer plane base address"))
            }
            let rowBytes = nv12 ? w : (w * 4)
            let rows = (plane == 1) ? (h / 2) : h
            frame.planes[plane].withUnsafeBytes { srcBuf in
                guard let srcBase = srcBuf.baseAddress else { return }
                for row in 0..<rows {
                    dstBase.advanced(by: row * dstStride)
                        .copyMemory(from: srcBase.advanced(by: row * rowBytes), byteCount: rowBytes)
                }
            }
        }

        let buffer = PixelBuffer(created)
        buffer.setColor(frame.color)
        return .success(buffer)
    }
}

// PORT NOTE: Thread-safe live plane counter used to verify `CVMetalTexture` / `IOSurface` retention across GPU submissions.
final class ImportedPlaneCounter: @unchecked Sendable {
    private let lock = LiveLock()
    private var count: Int = 0

    func increment() {
        lock.withLock { count += 1 }
    }

    func decrement() {
        lock.withLock { count -= 1 }
    }

    func load() -> Int {
        lock.withLock { count }
    }
}

// PORT NOTE: Retains the `CVMetalTexture` and `PixelBuffer` until all GPU bind groups and command buffers referencing the plane finish.
private final class ImportedPlaneOwner: @unchecked Sendable {
    let cvTexture: CVMetalTexture
    let buffer: PixelBuffer
    let counter: ImportedPlaneCounter

    init(cvTexture: CVMetalTexture, buffer: PixelBuffer, counter: ImportedPlaneCounter) {
        self.cvTexture = cvTexture
        self.buffer = buffer
        self.counter = counter
        counter.increment()
    }

    deinit {
        counter.decrement()
    }
}

// PORT NOTE: Wraps `CVMetalTextureCache` tied to the renderer's `MetalDevice` for zero-copy plane import.
final class SurfaceImporter: @unchecked Sendable {
    private let cache: CVMetalTextureCache
    private let device: MetalDevice
    let livePlanes = ImportedPlaneCounter()

    init(device: MetalDevice) throws {
        guard let mtlDevice = device.shared.mtlDevice else {
            throw SurfaceError("NativeSurface needs a Metal device")
        }
        var rawCache: CVMetalTextureCache? = nil
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, mtlDevice, nil, &rawCache)
        if status != kCVReturnSuccess {
            throw SurfaceError("CVMetalTextureCacheCreate: CoreVideo status \(status)")
        }
        guard let created = rawCache else {
            throw SurfaceError("null texture cache")
        }
        self.cache = created
        self.device = device
    }

    func flush() {
        CVMetalTextureCacheFlush(cache, 0)
    }

    func `import`(_ buffer: PixelBuffer, _ format: SurfaceFormat, _ size: [UInt32]) -> Result<[MetalTexture], SurfaceError> {
        func importPlane(
            _ index: Int,
            _ width: UInt32,
            _ height: UInt32,
            _ metalFormat: MTLPixelFormat,
            _ wgpuFormat: WGPUTextureFormat
        ) -> Result<MetalTexture, SurfaceError> {
            var rawCvTex: CVMetalTexture? = nil
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                buffer.cvBuffer,
                nil,
                metalFormat,
                Int(width),
                Int(height),
                index,
                &rawCvTex
            )
            if status != kCVReturnSuccess {
                return .failure(SurfaceError("CVMetalTextureCacheCreateTextureFromImage (buffer must be IOSurface-backed): CoreVideo status \(status)"))
            }
            guard let cvTex = rawCvTex else {
                return .failure(SurfaceError("null CVMetalTexture"))
            }
            guard let mtlTex = CVMetalTextureGetTexture(cvTex) else {
                return .failure(SurfaceError("null MTLTexture"))
            }
            let owner = ImportedPlaneOwner(cvTexture: cvTex, buffer: buffer, counter: livePlanes)
            return .success(MetalTexture(rawTexture: mtlTex, format: wgpuFormat, shared: device.shared, owner: owner))
        }

        return autoreleasepool {
            if format == .bgra {
                switch importPlane(0, size[0], size[1], .bgra8Unorm, WGPUTextureFormat_BGRA8Unorm) {
                case .failure(let e): return .failure(e)
                case .success(let tex): return .success([tex, tex])
                }
            } else {
                switch importPlane(0, size[0], size[1], .r8Unorm, WGPUTextureFormat_R8Unorm) {
                case .failure(let e):
                    return .failure(e)
                case .success(let yTex):
                    switch importPlane(1, size[0] / 2, size[1] / 2, .rg8Unorm, WGPUTextureFormat_RG8Unorm) {
                    case .failure(let e): return .failure(e)
                    case .success(let uvTex): return .success([yTex, uvTex])
                    }
                }
            }
        }
    }
}
#endif
