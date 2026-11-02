// Ported from: crates/rune/src/native_surface/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public enum SurfaceFit: Sendable, Equatable, Hashable {
    case fit
    case fill

    public static let Fit: SurfaceFit = .fit
    public static let Fill: SurfaceFit = .fill
}

// PORT NOTE: Reference-counted handle synchronized via `LiveLock` for cross-thread video/surface frame publication.
public final class NativeSurface: @unchecked Sendable {
    private let lock = LiveLock()
    private var frameSize: (UInt32, UInt32) = (0, 0)

    public init() {}

    public static func new() -> NativeSurface {
        NativeSurface()
    }

    public func size() -> (UInt32, UInt32) {
        lock.withLock { frameSize }
    }
}

struct SurfaceDraw: Sendable {
    var rect: [Float]
    var clip: [Float]
    var fade: [UInt32]
}
