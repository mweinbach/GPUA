// Ported from: crates/rune-motion/src/cycle.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

@inline(__always)
func remEuclid(_ x: Double, _ rhs: Double) -> Double {
    let r = x.truncatingRemainder(dividingBy: rhs)
    return r < 0.0 ? r + abs(rhs) : r
}

/// A looping opacity curve sampled from the wall clock: `stops` are (loop fraction 0–1, opacity)
/// pairs interpolated linearly; this element is at `frac(t / period - phase)`. Every cycle with
/// the same period stays in phase. Reduced motion holds `still`. While only cycles move, the
/// window wakes at `fps` instead of every display frame.
public struct Cycle: Sendable, Equatable {
    public var period: Float
    public var phase: Float
    // PORT NOTE: `[(Float, Float)]` replaces Rust `&'static [(f32, f32)]` with value-type array storage.
    public var stops: [(Float, Float)]
    public var still: Float
    public var fps: Float

    public init(
        period: Float,
        phase: Float,
        stops: [(Float, Float)],
        still: Float,
        fps: Float
    ) {
        self.period = period
        self.phase = phase
        self.stops = stops
        self.still = still
        self.fps = fps
    }

    public static func == (lhs: Cycle, rhs: Cycle) -> Bool {
        guard lhs.period == rhs.period,
            lhs.phase == rhs.phase,
            lhs.still == rhs.still,
            lhs.fps == rhs.fps,
            lhs.stops.count == rhs.stops.count
        else {
            return false
        }
        for i in 0..<lhs.stops.count {
            if lhs.stops[i].0 != rhs.stops[i].0 || lhs.stops[i].1 != rhs.stops[i].1 {
                return false
            }
        }
        return true
    }

    public func sample(_ t: Double) -> Float {
        let x = Float(remEuclid(t / Double(period) - Double(phase), 1.0))
        let s = stops
        guard let k = s.firstIndex(where: { $0.0 >= x }) else {
            return s.last?.1 ?? 1.0
        }
        if k == 0 {
            return s[0].1
        }
        let (x0, v0) = s[k - 1]
        let (x1, v1) = s[k]
        return v0 + (v1 - v0) * (x - x0) / max(x1 - x0, 1e-6)
    }
}
