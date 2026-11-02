// Ported from: crates/rune-motion/src/looping.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Periodic and finite motion kinds driven by ``LoopTrack``.
public enum LoopKind: Sendable, Equatable {
    case opacity(low: Float, high: Float)
    /// Piecewise-linear, wall-clock opacity with a bounded frame rate.
    case opacityCycle(Cycle)
    /// Finite opacity/scale choreography; holds its last pose at rest.
    case sequence(Sequence)
    case rotation
    /// An eased one-way sweep that wraps, in fractions of the node's own size (an
    /// indeterminate progress segment). Descendants and hit tests follow it.
    case slide(from: [Float], to: [Float])
    /// A `slide` swept along `easing` instead of ease-in-out (``LoopSpec/easing(_:)``).
    case slideEased(from: [Float], to: [Float], easing: Easing)
}

public struct LoopSpec: Sendable, Equatable {
    public var period: Double
    public var delay: Double
    public var kind: LoopKind

    public init(period: Double, delay: Double, kind: LoopKind) {
        self.period = period
        self.delay = delay
        self.kind = kind
    }

    public static func sequence(_ frames: Sequence) -> LoopSpec {
        LoopSpec(period: frames.duration(), delay: frames.delaySeconds, kind: .sequence(frames))
    }

    public static func cycle(_ cycle: Cycle) -> LoopSpec {
        LoopSpec(period: Double(cycle.period), delay: 0.0, kind: .opacityCycle(cycle))
    }

    public static func opacity(_ period: Double, _ delay: Double, _ low: Float, _ high: Float) -> LoopSpec {
        LoopSpec(period: period, delay: delay, kind: .opacity(low: low, high: high))
    }

    public static func rotation(_ period: Double) -> LoopSpec {
        LoopSpec(period: period, delay: 0.0, kind: .rotation)
    }

    /// Reduced motion holds the sweep's midpoint; removal cools it back to no offset.
    public static func slide(_ period: Double, _ from: [Float], _ to: [Float]) -> LoopSpec {
        LoopSpec(period: period, delay: 0.0, kind: .slide(from: from, to: to))
    }

    /// The curve a slide sweeps along each period, ease-in-out by default; `Easing.linear`
    /// sweeps at a constant speed (a shimmer). Only slides take a curve; other kinds keep theirs.
    public func easing(_ easing: Easing) -> LoopSpec {
        var copy = self
        switch copy.kind {
        case .slide(let from, let to), .slideEased(let from, let to, _):
            copy.kind = .slideEased(from: from, to: to, easing: easing)
        default:
            break
        }
        return copy
    }
}

public struct LoopTrack: Sendable {
    private var spec: LoopSpec
    private var epoch: Double
    private var phase0: Double
    private var amplitude: Animated<Float>
    private var finished: Bool

    public init(_ spec: LoopSpec, _ now: Double) {
        precondition(spec.period.isFinite && spec.period > 0.0)
        precondition(spec.delay.isFinite && spec.delay >= 0.0)
        self.spec = spec
        self.epoch = now + spec.delay
        self.phase0 = 0.0
        self.amplitude = Animated(1.0).withClass(.opacity)
        self.finished = false
    }

    public static func new(_ spec: LoopSpec, _ now: Double) -> LoopTrack {
        LoopTrack(spec, now)
    }

    private var isSequence: Bool {
        if case .sequence = spec.kind { return true }
        return false
    }

    public func phase(_ now: Double) -> Double {
        if isSequence {
            if finished {
                return 1.0
            }
            return min(max((now - epoch) / spec.period, 0.0), 1.0)
        }
        return remEuclid(phase0 + max(now - epoch, 0.0) / spec.period, 1.0)
    }

    /// Preserve the presented phase when changing speed. An unchanged spec is a no-op.
    public mutating func retime(_ spec: LoopSpec, _ now: Double) {
        precondition(spec.period.isFinite && spec.period > 0.0)
        if self.spec == spec {
            return
        }
        let nextIsSeq: Bool
        if case .sequence = spec.kind { nextIsSeq = true } else { nextIsSeq = false }
        if isSequence || nextIsSeq {
            self = LoopTrack(spec, now)
            return
        }
        phase0 = phase(now)
        epoch = max(now, epoch)
        self.spec = spec
    }

    /// Cool to rest without stopping or resetting phase. Reversal inherits envelope velocity.
    public mutating func enabled(_ enabled: Bool, _ now: Double) {
        if isSequence {
            if enabled && amplitude.target() == 0.0 {
                epoch = now + spec.delay
                finished = false
            } else if !enabled {
                finished = true
            }
        }
        amplitude.animateTo(enabled ? 1.0 : 0.0, Spring(0.18, 0.0), now)
    }

    /// Moves the track onto a clock reading `delta` more, at the same place.
    public mutating func shift(_ delta: Double) {
        epoch += delta
        amplitude.shift(delta)
    }

    /// Moves a periodic loop `dt` further along its rhythm, for time its clock didn't see; a
    /// loop still waiting starts `dt` sooner. Finite sequences keep their place.
    public mutating func advance(_ dt: Double) {
        if !isSequence {
            epoch -= dt
        }
    }

    /// Explicit settle/reduced motion lands finite sequences; periodic loops keep their phase.
    public mutating func finish() {
        if isSequence {
            finished = true
        }
    }

    public func active(_ now: Double) -> Bool {
        if isSequence {
            return !finished && now >= epoch && now < epoch + spec.period
        }
        return (amplitude.target() > 0.0 && now >= epoch) || !amplitude.isSettled(now)
    }

    /// The animation-clock instant to wake at; no frames are needed before it.
    public func pendingStart(_ now: Double) -> Double? {
        (!finished && amplitude.target() > 0.0 && now < epoch) ? epoch : nil
    }

    /// Wall-clock cycles retain their cadence even when animation time is paused.
    public func frameInterval() -> Double? {
        if case .opacityCycle(let c) = spec.kind {
            return Double(Float(1.0) / max(c.fps, 1.0))
        }
        return nil
    }

    /// Opacity multiplier or clockwise radians. Reduced motion uses the calm first pose.
    public func sample(_ now: Double, _ reduced: Bool) -> Float {
        sampleAt(now, now, reduced)
    }

    public func sampleAt(_ now: Double, _ wall: Double, _ reduced: Bool) -> Float {
        let ph: Float = reduced ? 0.0 : Float(phase(now))
        switch spec.kind {
        case .sequence:
            return pose(now, reduced)!.opacity
        case .opacityCycle(let c):
            return reduced ? c.still : c.sample(wall)
        case .rotation:
            return ph * 6.28318530717958647692528676655900577
        case .slide, .slideEased:
            return 1.0
        case .opacity(let low, let high):
            let triangle: Float = ph < 0.5 ? (ph * 2.0) : ((1.0 - ph) * 2.0)
            return low + (high - low) * Easing.easeInOut.eval(triangle) * amplitude.sample(now)
        }
    }

    /// A `slide`'s offset in fractions of the node's own size.
    public func offset(_ now: Double, _ reduced: Bool) -> [Float]? {
        let from: [Float]
        let to: [Float]
        let easing: Easing
        switch spec.kind {
        case .slide(let f, let t):
            from = f
            to = t
            easing = .easeInOut
        case .slideEased(let f, let t, let e):
            from = f
            to = t
            easing = e
        default:
            return nil
        }
        let t: Float = reduced ? 0.5 : easing.eval(Float(phase(now)))
        let a = amplitude.sample(now)
        return [
            (from[0] + (to[0] - from[0]) * t) * a,
            (from[1] + (to[1] - from[1]) * t) * a,
        ]
    }

    public func pose(_ now: Double, _ reduced: Bool) -> Beat? {
        guard case .sequence(let frames) = spec.kind else {
            return nil
        }
        let elapsed = (reduced || finished) ? frames.duration() : (phase(now) * frames.duration())
        return frames.sample(elapsed)
    }
}
