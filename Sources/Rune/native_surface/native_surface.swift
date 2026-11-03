// Ported from: crates/rune/src/native_surface/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Latest-wins video frames. macOS imports IOSurface-backed CoreVideo buffers without a copy.
//! CPU byte frames provide a portable source and a reference for headless verification.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

public enum SurfaceFit: Sendable, Equatable, Hashable {
    case fit
    case fill

    public static let Fit: SurfaceFit = .fit
    public static let Fill: SurfaceFit = .fill
}

public enum SurfaceMatrix: Sendable, Equatable, Hashable {
    case bt601
    case bt709

    public static let Bt601: SurfaceMatrix = .bt601
    public static let Bt709: SurfaceMatrix = .bt709
}

public enum SurfaceTransfer: Sendable, Equatable, Hashable {
    case srgb
    case bt709

    public static let Srgb: SurfaceTransfer = .srgb
    public static let Bt709: SurfaceTransfer = .bt709
}

public enum SurfaceFormat: Sendable, Equatable, Hashable {
    case bgra
    case nv12Video
    case nv12Full

    public static let Bgra: SurfaceFormat = .bgra
    public static let Nv12Video: SurfaceFormat = .nv12Video
    public static let Nv12Full: SurfaceFormat = .nv12Full
}

public struct ColorInfo: Sendable, Equatable, Hashable {
    public var matrix: SurfaceMatrix
    public var transfer: SurfaceTransfer

    public init(matrix: SurfaceMatrix = .bt709, transfer: SurfaceTransfer = .srgb) {
        self.matrix = matrix
        self.transfer = transfer
    }

    public static func `default`() -> ColorInfo {
        ColorInfo()
    }
}

/// Immutable packed planes. NV12 plane 0 is Y, plane 1 is interleaved CbCr.
public struct ByteFrame: Sendable, Equatable {
    public var width: UInt32
    public var height: UInt32
    public var format: SurfaceFormat
    public var color: ColorInfo
    public var planes: [[UInt8]]

    public init(
        width: UInt32,
        height: UInt32,
        format: SurfaceFormat,
        color: ColorInfo = ColorInfo(),
        planes: [[UInt8]]
    ) {
        self.width = width
        self.height = height
        self.format = format
        self.color = color
        self.planes = planes
    }
}

enum SurfaceSource: Sendable {
    case bytes(ByteFrame)
    #if os(macOS)
    case pixelBuffer(PixelBuffer)
    #endif
}

/// How a frame's buffer turns into its upright picture: a quarter-turn rotation and/or flip,
/// applied while sampling. The matrix maps centred upright coordinates to centred buffer
/// coordinates: `buffer = [m0 m1; m2 m3] * upright`.
public struct SurfaceOrient: Sendable, Equatable, Hashable {
    public var matrix: [Int8]

    public static let UP = SurfaceOrient([1, 0, 0, 1])

    public init(_ matrix: [Int8] = [1, 0, 0, 1]) {
        precondition(matrix.count == 4, "SurfaceOrient requires 4 elements")
        self.matrix = matrix
    }

    /// From an affine transform taking buffer to upright coordinates (`x' = a x + c y`,
    /// `y' = b x + d y`), such as AVFoundation's `preferredTransform`. Anything but a quarter
    /// turn or flip is drawn upright as is.
    public static func fromTransform(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> SurfaceOrient {
        let raw = [a, b, c, d]
        let m = raw.map { $0.rounded() }
        let unit = m.allSatisfy { abs($0) <= 1.0 } && zip(m, raw).allSatisfy { abs($0 - $1) < 1e-3 }
        let quarter = (m[0] != 0.0 && m[3] != 0.0 && m[1] == 0.0 && m[2] == 0.0)
            || (m[0] == 0.0 && m[3] == 0.0 && m[1] != 0.0 && m[2] != 0.0)
        // Orthogonal, so the inverse is the transpose: [a b; c d].
        if unit && quarter {
            return SurfaceOrient(m.map { Int8($0) })
        }
        return .UP
    }

    /// Whether width and height trade places.
    public func swaps() -> Bool {
        matrix[0] == 0
    }

    /// The upright size of a buffer of `size`.
    public func upright(_ size: [UInt32]) -> [UInt32] {
        if swaps() {
            return [size[1], size[0]]
        }
        return [size[0], size[1]]
    }
}

/// Reference-counted immutable frame stored in a `NativeSurface` mailbox.
final class SurfaceFrame: Sendable {
    let id: UInt64
    let source: SurfaceSource
    /// Buffer size, before `orient`.
    let size: [UInt32]
    let format: SurfaceFormat
    let color: ColorInfo
    let orient: SurfaceOrient

    init(
        id: UInt64,
        source: SurfaceSource,
        size: [UInt32],
        format: SurfaceFormat,
        color: ColorInfo,
        orient: SurfaceOrient
    ) {
        self.id = id
        self.source = source
        self.size = size
        self.format = format
        self.color = color
        self.orient = orient
    }
}

/// Submit is a CPU monotonic timestamp. Completion is callback-observed CPU time;
/// GPU start/end are render-pass timestamp-query seconds on the GPU clock, not `Instant`
/// or display time. Their difference is GPU duration; the epoch is backend-specific.
public struct FrameTiming: Sendable, Equatable {
    public var frameId: UInt64
    public var submittedAt: RuneInstant
    public var completedAt: RuneInstant?
    public var gpuStartSeconds: Double?
    public var gpuEndSeconds: Double?

    public init(
        frameId: UInt64,
        submittedAt: RuneInstant,
        completedAt: RuneInstant? = nil,
        gpuStartSeconds: Double? = nil,
        gpuEndSeconds: Double? = nil
    ) {
        self.frameId = frameId
        self.submittedAt = submittedAt
        self.completedAt = completedAt
        self.gpuStartSeconds = gpuStartSeconds
        self.gpuEndSeconds = gpuEndSeconds
    }
}

public typealias FrameObserver = @Sendable (FrameTiming) -> Void

// PORT NOTE: Shared mailbox state synchronized by `LiveLock`, allowing multiple `NativeSurface`
// handles (including `placed(...)` clones) to share the exact same bounded latest-wins slot.
final class NativeSurfaceBox: @unchecked Sendable {
    let lock = LiveLock()
    var latest: SurfaceFrame? = nil
    var waker: Waker? = nil
    var observer: FrameObserver? = nil
    var timing: FrameTiming? = nil
    var submitted: UInt64 = 0
    var completed: UInt64 = 0
    var error: String? = nil
    var mirrored: Bool = false
    /// The player feeding this surface, pulled once per frame that draws it.
    var video: VideoShared? = nil
}

/// Clones share a single bounded slot; pushing never queues frames behind the decoder.
public final class NativeSurface: Sendable, CustomDebugStringConvertible {
    let box: NativeSurfaceBox
    let surfacePlace: SurfacePlace

    public init() {
        self.box = NativeSurfaceBox()
        self.surfacePlace = .CENTRED
    }

    init(box: NativeSurfaceBox, place: SurfacePlace) {
        self.box = box
        self.surfacePlace = place
    }

    public static func new() -> NativeSurface {
        NativeSurface()
    }

    public func clone() -> NativeSurface {
        NativeSurface(box: box, place: surfacePlace)
    }

    public var debugDescription: String {
        "NativeSurface(\(key()))"
    }

    /// A handle to the same frames that draws with `place`; the element sets it per draw.
    public func placed(_ place: SurfacePlace) -> NativeSurface {
        NativeSurface(box: box, place: place)
    }

    public func place() -> SurfacePlace {
        surfacePlace
    }

    static func withVideo(_ video: VideoShared) -> NativeSurface {
        let surface = NativeSurface()
        surface.box.lock.withLock {
            surface.box.video = video
        }
        return surface
    }

    func video() -> VideoShared? {
        box.lock.withLock { box.video }
    }

    /// Pull this frame's picture from the surface's video, if it has one.
    func pullVideo(_ clock: VideoClock, _ wake: LiveWake) -> VideoPulled? {
        guard let v = video() else { return nil }
        return v.pull(self, clock, wake)
    }

    /// Latest upright frame dimensions `(width, height)`, or `(0, 0)` when empty.
    public func size() -> (UInt32, UInt32) {
        box.lock.withLock {
            guard let f = box.latest else { return (0, 0) }
            let up = f.orient.upright(f.size)
            return (up[0], up[1])
        }
    }

    public func setWaker(_ waker: @escaping Waker) {
        box.lock.withLock {
            box.waker = waker
        }
    }

    public func setObserver(_ observer: @escaping FrameObserver) {
        box.lock.withLock {
            box.observer = observer
        }
    }

    public func timing() -> FrameTiming? {
        box.lock.withLock { box.timing }
    }

    /// Counts draws submitted/completed (the same source frame may be drawn more than once).
    public func counts() -> (UInt64, UInt64) {
        box.lock.withLock { (box.submitted, box.completed) }
    }

    public func lastError() -> String? {
        box.lock.withLock { box.error }
    }

    func setLastError(_ err: String?) {
        box.lock.withLock { box.error = err }
    }

    public func clear() {
        let (old, wake): (SurfaceFrame?, Waker?) = box.lock.withLock {
            let prev = box.latest
            box.latest = nil
            return (prev, box.waker)
        }
        _ = old // Released outside lock
        wake?()
    }

    /// Flip the image horizontally at draw time, about its centre, for a front-camera preview.
    public func setMirrored(_ mirrored: Bool) {
        let wake: Waker? = box.lock.withLock {
            if box.mirrored == mirrored {
                return nil
            }
            box.mirrored = mirrored
            return box.waker
        }
        wake?()
    }

    public func isMirrored() -> Bool {
        box.lock.withLock { box.mirrored }
    }

    @discardableResult
    public func pushBytes(_ frame: ByteFrame, _ frameId: UInt64) -> Result<Void, SurfaceError> {
        pushBytesOriented(frame, frameId, .UP)
    }

    @discardableResult
    func pushBytesOriented(_ frame: ByteFrame, _ frameId: UInt64, _ orient: SurfaceOrient) -> Result<Void, SurfaceError> {
        let w = frame.width
        let h = frame.height
        if w == 0 || h == 0 || w > 16384 || h > 16384 {
            return .failure(SurfaceError("video size must be 1..16384"))
        }
        let n = Int(w) * Int(h)
        let sizes: (Int, Int)
        switch frame.format {
        case .bgra:
            sizes = (n * 4, 0)
        case .nv12Video, .nv12Full:
            if w % 2 != 0 || h % 2 != 0 {
                return .failure(SurfaceError("NV12 requires even dimensions"))
            }
            sizes = (n, n / 2)
        }
        guard frame.planes.count == 2,
              frame.planes[0].count == sizes.0,
              frame.planes[1].count == sizes.1
        else {
            return .failure(SurfaceError("video plane length does not match dimensions"))
        }
        replace(SurfaceFrame(
            id: frameId,
            source: .bytes(frame),
            size: [w, h],
            format: frame.format,
            color: frame.color,
            orient: orient
        ))
        return .success(())
    }

    #if os(macOS)
    @discardableResult
    public func push(_ buffer: PixelBuffer, _ frameId: UInt64) -> Result<Void, SurfaceError> {
        pushOriented(buffer, frameId, .UP)
    }

    @discardableResult
    func pushOriented(_ buffer: PixelBuffer, _ frameId: UInt64, _ orient: SurfaceOrient) -> Result<Void, SurfaceError> {
        switch buffer.info() {
        case .failure(let err):
            return .failure(err)
        case .success(let (size, format, color)):
            replace(SurfaceFrame(
                id: frameId,
                source: .pixelBuffer(buffer),
                size: size,
                format: format,
                color: color,
                orient: orient
            ))
            return .success(())
        }
    }
    #endif

    private func replace(_ frame: SurfaceFrame) {
        let (old, wake): (SurfaceFrame?, Waker?) = box.lock.withLock {
            let prev = box.latest
            box.latest = frame
            return (prev, box.waker)
        }
        _ = old // CoreVideo release never runs under the mailbox lock.
        wake?()
    }

    func latest() -> SurfaceFrame? {
        box.lock.withLock { box.latest }
    }

    func latestMirrored() -> (SurfaceFrame, Bool)? {
        box.lock.withLock {
            guard let f = box.latest else { return nil }
            return (f, box.mirrored)
        }
    }

    public func key() -> Int {
        Int(bitPattern: Unmanaged.passUnretained(box).toOpaque())
    }

    func report(_ timing: FrameTiming) {
        let observer: FrameObserver? = box.lock.withLock {
            if timing.completedAt != nil {
                box.completed += 1
            } else {
                box.submitted += 1
            }
            if let old = box.timing {
                if old.submittedAt <= timing.submittedAt {
                    box.timing = timing
                }
            } else {
                box.timing = timing
            }
            return box.observer
        }
        observer?(timing)
    }
}

/// Error description returned by `NativeSurface` and `PixelBuffer` validation.
public struct SurfaceError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// A node's video draw in painter order. Geometry is already in device pixels.
public struct SurfaceDraw: Sendable {
    public var surface: NativeSurface
    public var fit: SurfaceFit
    public var beforeInstance: UInt32
    public var rect: [Float]
    public var radii: [Float]
    public var clip: [Float]
    /// Packed as `render.Instance.fade`.
    public var fade: [UInt32]
    public var opacity: Float

    public init(
        surface: NativeSurface,
        fit: SurfaceFit = .fit,
        beforeInstance: UInt32 = 0,
        rect: [Float],
        radii: [Float] = [0, 0, 0, 0],
        clip: [Float] = NO_CLIP,
        fade: [UInt32] = [0, 0, 0, 0],
        opacity: Float = 1.0
    ) {
        self.surface = surface
        self.fit = fit
        self.beforeInstance = beforeInstance
        self.rect = rect
        self.radii = radii
        self.clip = clip
        self.fade = fade
        self.opacity = opacity
    }
}

/// Independent scalar colour oracle: encoded YCbCr -> linear RGB.
public func nv12Reference(
    _ y: UInt8,
    _ cb: UInt8,
    _ cr: UInt8,
    _ format: SurfaceFormat,
    _ color: ColorInfo
) -> [Float] {
    let yNorm: Float
    let uNorm: Float
    let vNorm: Float
    if format == .nv12Video {
        yNorm = (Float(y) - 16.0) / 219.0
        uNorm = (Float(cb) - 128.0) / 224.0
        vNorm = (Float(cr) - 128.0) / 224.0
    } else {
        yNorm = Float(y) / 255.0
        uNorm = (Float(cb) - 128.0) / 255.0
        vNorm = (Float(cr) - 128.0) / 255.0
    }
    let (kr, kb): (Float, Float) = switch color.matrix {
    case .bt601: (0.299, 0.114)
    case .bt709: (0.2126, 0.0722)
    }
    let r = yNorm + 2.0 * (1.0 - kr) * vNorm
    let b = yNorm + 2.0 * (1.0 - kb) * uNorm
    let g = (yNorm - kr * r - kb * b) / (1.0 - kr - kb)
    return [r, g, b].map { surfaceLinear(min(max($0, 0.0), 1.0), color.transfer) }
}

public func surfaceLinear(_ x: Float, _ transfer: SurfaceTransfer) -> Float {
    switch transfer {
    case .srgb:
        if x <= 0.04045 {
            return x / 12.92
        } else {
            return Float(pow(Double((x + 0.055) / 1.055), 2.4))
        }
    case .bt709:
        if x < 0.081 {
            return x / 4.5
        } else {
            return Float(pow(Double((x + 0.099) / 1.099), 1.0 / 0.45))
        }
    }
}

/// Synthetic bars, gradient and one-pixel text-like strokes. No decoded content is copied by import.
public func syntheticSurfaceFrame(_ width: UInt32, _ height: UInt32, _ phase: UInt64) -> ByteFrame {
    precondition(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0)
    let bars: [[UInt8]] = [
        [235, 128, 128],
        [210, 16, 146],
        [170, 166, 16],
        [145, 54, 34],
        [106, 202, 222],
        [81, 90, 240],
        [41, 240, 110],
        [16, 128, 128],
    ]
    var y = [UInt8](repeating: 0, count: Int(width * height))
    var uv = [UInt8](repeating: 128, count: Int(width * height / 2))
    for row in 0..<height {
        for x in 0..<width {
            let val: UInt8
            if row < height / 3 {
                val = bars[Int(x * 8 / width)][0]
            } else if row < 2 * height / 3 {
                val = UInt8(16 + x * 219 / width)
            } else if (x &+ UInt32(truncatingIfNeeded: phase)) % 8 == 0 || row % 9 == 0 {
                val = 235
            } else {
                val = 16
            }
            y[Int(row * width + x)] = val
        }
    }
    for row in 0..<(height / 6) {
        for x in 0..<(width / 2) {
            let bar = bars[Int(x * 16 / width)]
            let i = Int(row * width + x * 2)
            uv[i] = bar[1]
            uv[i + 1] = bar[2]
        }
    }
    return ByteFrame(
        width: width,
        height: height,
        format: .nv12Video,
        color: ColorInfo(matrix: .bt709, transfer: .bt709),
        planes: [y, uv]
    )
}

/// Namespace mirroring `rune::native_surface::*`.
public enum native_surface {
    public typealias SurfaceFit = Rune.SurfaceFit
    public typealias Matrix = Rune.SurfaceMatrix
    public typealias Transfer = Rune.SurfaceTransfer
    public typealias Format = Rune.SurfaceFormat
    public typealias ColorInfo = Rune.ColorInfo
    public typealias ByteFrame = Rune.ByteFrame
    public typealias Orient = Rune.SurfaceOrient
    public typealias FrameTiming = Rune.FrameTiming
    public typealias FrameObserver = Rune.FrameObserver
    public typealias NativeSurface = Rune.NativeSurface
    public typealias SurfaceDraw = Rune.SurfaceDraw
    public typealias SurfaceRenderer = Rune.SurfaceRenderer

    public static func nv12Reference(
        _ y: UInt8,
        _ cb: UInt8,
        _ cr: UInt8,
        _ format: SurfaceFormat,
        _ color: ColorInfo
    ) -> [Float] {
        Rune.nv12Reference(y, cb, cr, format, color)
    }

    public static func linear(_ x: Float, _ transfer: SurfaceTransfer) -> Float {
        Rune.surfaceLinear(x, transfer)
    }

    public static func synthetic(_ width: UInt32, _ height: UInt32, _ phase: UInt64) -> ByteFrame {
        Rune.syntheticSurfaceFrame(width, height, phase)
    }

    #if os(macOS)
    public enum macos {
        public typealias PixelBuffer = Rune.PixelBuffer
    }
    #endif
}
