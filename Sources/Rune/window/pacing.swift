// Ported from: crates/rune/src/window/pacing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Surface acquire/configure pacing and `SurfaceStats` tracking (`crates/rune/src/window/pacing.rs`).

#if !os(WASI)
import Foundation
#endif

let OCCLUDED_RETRY: Duration = .milliseconds(16)
let OCCLUDED_MAX: Duration = .milliseconds(250)
let TIMEOUT_RETRY: Duration = .milliseconds(4)

/// Surface outcome counts (`crates/rune/src/frame/surface_stats.rs`).
// PORT NOTE: Prefixed `WindowSurfaceCounts` to avoid colliding with `Sources/Rune/frame/surface_stats.swift` owned by a sibling Wave 2 worker.
public struct WindowSurfaceCounts: Sendable, Equatable {
    public var presented: UInt64 = 0
    public var suboptimal: UInt64 = 0
    public var timeout: UInt64 = 0
    public var outdated: UInt64 = 0
    public var lost: UInt64 = 0
    public var occluded: UInt64 = 0
    public var other: UInt64 = 0
    public var reconfigured: UInt64 = 0

    public init() {}

    public func missed() -> UInt64 {
        timeout + outdated + lost + occluded + other
    }
}

/// Swapchain pacing mode (`crates/rune/src/frame/surface_stats.rs`).
// PORT NOTE: Prefixed `WindowPacing` to avoid colliding with `Sources/Rune/frame/surface_stats.swift` owned by a sibling Wave 2 worker.
public enum WindowPacing: Sendable, Equatable {
    case displayLink
    case presentWait
    case unpaced
}

/// Surface statistics snapshot (`crates/rune/src/frame/surface_stats.rs`).
// PORT NOTE: Prefixed `WindowSurfaceStats` to avoid colliding with `Sources/Rune/frame/surface_stats.swift` owned by a sibling Wave 2 worker.
public struct WindowSurfaceStats: Sendable, Equatable {
    public var counts: WindowSurfaceCounts = WindowSurfaceCounts()
    public var pacing: WindowPacing = .unpaced
    public var desiredLatency: UInt32 = 2
    public var formatSrgb: Bool = true
    public var alphaPremultiplied: Bool = false

    public init() {}

    public func missed() -> UInt64 {
        counts.missed()
    }
}

/// Rolling surface outcome meter (`crates/rune/src/frame/surface_stats.rs`).
// PORT NOTE: Prefixed `WindowSurfaceMeter` to avoid colliding with `Sources/Rune/frame/surface_stats.swift` owned by a sibling Wave 2 worker.
struct WindowSurfaceMeter: Sendable {
    private var statsValue = WindowSurfaceStats()
    private var windowValue = WindowSurfaceCounts()

    init() {}

    mutating func configured(
        pacing: WindowPacing,
        desiredLatency: UInt32,
        formatSrgb: Bool,
        alphaPremultiplied: Bool
    ) {
        statsValue.pacing = pacing
        statsValue.desiredLatency = desiredLatency
        statsValue.formatSrgb = formatSrgb
        statsValue.alphaPremultiplied = alphaPremultiplied
    }

    mutating func reconfigured() {
        statsValue.counts.reconfigured &+= 1
        windowValue.reconfigured &+= 1
    }

    mutating func presented(_ suboptimal: Bool) {
        statsValue.counts.presented &+= 1
        windowValue.presented &+= 1
        if suboptimal {
            statsValue.counts.suboptimal &+= 1
            windowValue.suboptimal &+= 1
        }
    }

    mutating func timeout() {
        statsValue.counts.timeout &+= 1
        windowValue.timeout &+= 1
    }

    mutating func outdated() {
        statsValue.counts.outdated &+= 1
        windowValue.outdated &+= 1
    }

    mutating func lost() {
        statsValue.counts.lost &+= 1
        windowValue.lost &+= 1
    }

    mutating func occluded() {
        statsValue.counts.occluded &+= 1
        windowValue.occluded &+= 1
    }

    mutating func other() {
        statsValue.counts.other &+= 1
        windowValue.other &+= 1
    }

    func snapshot() -> WindowSurfaceStats {
        statsValue
    }

    mutating func takeWindow() -> WindowSurfaceCounts {
        let out = windowValue
        windowValue = WindowSurfaceCounts()
        return out
    }
}

/// Why a swapchain acquire missed (`crates/rune/src/window/pacing.rs`).
enum WindowMissed: Error, Sendable, Equatable {
    case timeout
    case occluded
    case reconfigured
    case skip
}

/// Simulated/abstract swapchain acquire status used by `acquireSurface` and `occluded_surface_tests`.
enum SurfaceAcquireStatus: Sendable, Equatable {
    case good
    case suboptimal
    case timeout
    case outdated
    case lost
    case occluded
    case other
}

struct WindowSurfaceConfig: Sendable, Equatable {
    var width: UInt32
    var height: UInt32
    var transparent: Bool
    var srgb: Bool
    var pacing: WindowPacing
    var desiredMaximumFrameLatency: UInt32

    init(
        width: UInt32 = 800,
        height: UInt32 = 600,
        transparent: Bool = false,
        srgb: Bool = true,
        pacing: WindowPacing = .displayLink,
        desiredMaximumFrameLatency: UInt32 = 1
    ) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.transparent = transparent
        self.srgb = srgb
        self.pacing = pacing
        self.desiredMaximumFrameLatency = desiredMaximumFrameLatency
    }
}

func makeSurfaceConfig(
    size: (UInt32, UInt32),
    transparent: Bool,
    srgb: Bool,
    displayLink: Bool
) -> WindowSurfaceConfig {
    let latency: UInt32 = displayLink ? 1 : 2
    let pacing: WindowPacing = displayLink ? .displayLink : .presentWait
    return WindowSurfaceConfig(
        width: max(size.0, 1),
        height: max(size.1, 1),
        transparent: transparent,
        srgb: srgb,
        pacing: pacing,
        desiredMaximumFrameLatency: latency
    )
}

func configureWindowSurface(
    _ config: inout WindowSurfaceConfig,
    _ meter: inout WindowSurfaceMeter
) {
    meter.configured(
        pacing: config.pacing,
        desiredLatency: config.desiredMaximumFrameLatency,
        formatSrgb: config.srgb,
        alphaPremultiplied: config.transparent
    )
}

func resolveSurfaceAcquire(
    _ firstStatus: SurfaceAcquireStatus,
    retryAcquire: () -> SurfaceAcquireStatus,
    reconfigure: () -> Void,
    meter: inout WindowSurfaceMeter
) -> Result<Bool, WindowMissed> {
    switch firstStatus {
    case .good:
        return .success(false)
    case .suboptimal:
        reconfigure()
        meter.reconfigured()
        switch retryAcquire() {
        case .good:
            return .success(false)
        case .suboptimal:
            return .success(true)
        case .occluded:
            meter.occluded()
            return .failure(.occluded)
        case .timeout:
            meter.timeout()
            return .failure(.timeout)
        case .outdated:
            meter.outdated()
            return .failure(.reconfigured)
        case .lost:
            meter.lost()
            return .failure(.reconfigured)
        case .other:
            meter.other()
            return .failure(.skip)
        }
    case .outdated:
        meter.outdated()
        reconfigure()
        meter.reconfigured()
        return .failure(.reconfigured)
    case .lost:
        meter.lost()
        reconfigure()
        meter.reconfigured()
        return .failure(.reconfigured)
    case .timeout:
        meter.timeout()
        return .failure(.timeout)
    case .occluded:
        meter.occluded()
        return .failure(.occluded)
    case .other:
        meter.other()
        return .failure(.skip)
    }
}

func nextOccludedRetry(_ current: inout Duration?) -> Duration {
    let d = current ?? OCCLUDED_RETRY
    let doubledNanos = (Double(d.components.seconds) * 1e9 + Double(d.components.attoseconds) * 1e-9) * 2.0
    let maxNanos = Double(OCCLUDED_MAX.components.seconds) * 1e9 + Double(OCCLUDED_MAX.components.attoseconds) * 1e-9
    let clamped = min(doubledNanos, maxNanos)
    current = .nanoseconds(Int64(clamped.rounded()))
    return d
}
