// Ported from: crates/rune-motion/src/gesture.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// iOS `UIScrollView` deceleration rates, per millisecond.
public enum deceleration {
    public static let normal: Float = 0.998
    public static let fast: Float = 0.99
}

/// Where a fling released at `x` with velocity `v` (units/s) comes to rest under UIKit's
/// per-millisecond deceleration `rate` (WWDC18 "Designing Fluid Interfaces"):
/// `x + (v / 1000) · rate / (1 − rate)`.
public func project(_ x: Float, _ v: Float, _ rate: Float) -> Float {
    x + (v / 1000.0) * rate / (1.0 - rate)
}

/// iOS rubber-band: how far content moves when dragged `overshoot` points past its edge, in a
/// viewport `dimension` points long. `f(x) = (1 − 1 / (x·c/d + 1)) · d`, c = 0.55.
public func rubberBand(_ overshoot: Float, _ dimension: Float) -> Float {
    rubberBandWith(overshoot, dimension, 0.55)
}

/// ``rubberBand(_:_:)`` with an explicit constant `c`. Odd in `overshoot`, so it works both ways.
public func rubberBandWith(_ overshoot: Float, _ dimension: Float, _ c: Float) -> Float {
    if dimension <= 0.0 {
        return 0.0
    }
    let x = abs(overshoot)
    let y = (1.0 - 1.0 / (x * c / dimension + 1.0)) * dimension
    return Float(signOf: overshoot, magnitudeOf: y)
}

/// Maps a raw drag position into `[min, max]`, rubber-banding whatever lies outside.
public func rubberBandClamp(_ x: Float, _ minVal: Float, _ maxVal: Float, _ dimension: Float) -> Float {
    if x < minVal {
        return minVal + rubberBand(x - minVal, dimension)
    } else if x > maxVal {
        return maxVal + rubberBand(x - maxVal, dimension)
    } else {
        return x
    }
}

private let trackerSamples: Int = 20

private struct Sample4: Sendable {
    var l0: Float = 0.0
    var l1: Float = 0.0
    var l2: Float = 0.0
    var l3: Float = 0.0

    @inline(__always)
    subscript(_ lane: Int) -> Float {
        switch lane {
        case 0: return l0
        case 1: return l1
        case 2: return l2
        case 3: return l3
        default: preconditionFailure("Sample4 lane out of bounds")
        }
    }
}

/// Least-squares velocity over the last 100 ms of samples (at most 20), using the platform
/// event timestamps. 40 ms without movement counts as stopped (Flutter `VelocityTracker`).
public struct VelocityTracker<T: Animatable>: Sendable {
    private static var horizon: Double { 0.100 }
    private static var stopGap: Double { 0.040 }

    private var t: [Double]
    private var x: [Sample4]
    private var len: Int
    private var head: Int

    public init() {
        precondition(T.lanes <= 4, "VelocityTracker supports values of up to 4 lanes")
        self.t = Array(repeating: 0.0, count: trackerSamples)
        self.x = Array(repeating: Sample4(), count: trackerSamples)
        self.len = 0
        self.head = 0
    }

    public static func new() -> VelocityTracker<T> {
        VelocityTracker<T>()
    }

    /// Records a position at event time `t` (seconds).
    public mutating func add(_ sampleTime: Double, _ value: T) {
        let l = lanes(value)
        t[head] = sampleTime
        x[head] = Sample4(l0: l[0], l1: l[1], l2: l[2], l3: l[3])
        head = (head + 1) % trackerSamples
        len = min(len + 1, trackerSamples)
    }

    public mutating func reset() {
        len = 0
    }

    /// Velocity in units per second at the newest sample.
    public func velocity() -> T {
        var out = LaneStorage()
        if len >= 2 {
            let newest = (head + trackerSamples - 1) % trackerSamples
            let tNew = t[newest]
            // Count samples within the horizon, stopping at a long pause.
            var n = 0
            var prevT = tNew
            for k in 0..<len {
                let i = (newest + trackerSamples - k) % trackerSamples
                let ti = t[i]
                if tNew - ti > Self.horizon || prevT - ti > Self.stopGap {
                    break
                }
                n += 1
                prevT = ti
            }
            if n >= 2 {
                var sumDt = 0.0
                for k in 0..<n {
                    let i = (newest + trackerSamples - k) % trackerSamples
                    sumDt += t[i] - tNew
                }
                let meanT = sumDt / Double(n)
                var variance = 0.0
                for k in 0..<n {
                    let i = (newest + trackerSamples - k) % trackerSamples
                    let dt = t[i] - tNew - meanT
                    variance += dt * dt
                }
                if variance > 1e-12 {
                    for lane in 0..<T.lanes {
                        var sumX = 0.0
                        for k in 0..<n {
                            let i = (newest + trackerSamples - k) % trackerSamples
                            sumX += Double(x[i][lane])
                        }
                        let meanX = sumX / Double(n)
                        var cov = 0.0
                        for k in 0..<n {
                            let i = (newest + trackerSamples - k) % trackerSamples
                            cov += (t[i] - tNew - meanT) * (Double(x[i][lane]) - meanX)
                        }
                        out[lane] = Float(cov / variance)
                    }
                }
            }
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }
}
