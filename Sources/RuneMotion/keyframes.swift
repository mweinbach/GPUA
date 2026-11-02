// Ported from: crates/rune-motion/src/keyframes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// One keyframe: where to be at the end of its slot and how to get there.
public enum Keyframe<T: Animatable>: Sendable {
    /// `LinearKeyframe`: interpolate from the previous value with `easing` (linear by default).
    case linear(value: T, duration: Float, easing: Easing)
    /// `SpringKeyframe`: spring toward `value` for `duration` seconds, then hand the exact
    /// position and velocity to the next keyframe (it needn't have arrived).
    case spring(value: T, duration: Float, spring: Spring)
    /// `CubicKeyframe`: a Catmull-Rom spline through consecutive cubic keyframes. Velocity is
    /// continuous across keyframes.
    case cubic(value: T, duration: Float)
    /// `MoveKeyframe`: jump to `value` with no duration.
    case move(value: T)

    public func value() -> T {
        switch self {
        case .linear(let value, _, _),
            .spring(let value, _, _),
            .cubic(let value, _),
            .move(let value):
            return value
        }
    }

    public func duration() -> Float {
        switch self {
        case .linear(_, let duration, _),
            .spring(_, let duration, _),
            .cubic(_, let duration):
            return max(duration, 0.0)
        case .move:
            return 0.0
        }
    }
}

/// An ordered keyframe track for one property (`KeyframeTrack`).
public struct Keyframes<T: Animatable>: Sendable {
    fileprivate var _frames: [Keyframe<T>]
    fileprivate var _delay: Float
    fileprivate var _repeat: UInt32

    /// Starts from the property's current value.
    public init() {
        self._frames = []
        self._delay = 0.0
        self._repeat = 1
    }

    public static func new() -> Keyframes<T> {
        Keyframes<T>()
    }

    public func linear(_ value: T, _ duration: Float) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.linear(value: value, duration: duration, easing: .linear))
        return copy
    }

    public func eased(_ value: T, _ duration: Float, _ easing: Easing) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.linear(value: value, duration: duration, easing: easing))
        return copy
    }

    /// A spring keyframe lasting the spring's own duration.
    public func spring(_ value: T, _ spring: Spring) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.spring(value: value, duration: spring.duration, spring: spring))
        return copy
    }

    public func springFor(_ value: T, _ duration: Float, _ spring: Spring) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.spring(value: value, duration: duration, spring: spring))
        return copy
    }

    public func cubic(_ value: T, _ duration: Float) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.cubic(value: value, duration: duration))
        return copy
    }

    public func moveTo(_ value: T) -> Keyframes<T> {
        var copy = self
        copy._frames.append(.move(value: value))
        return copy
    }

    public func delay(_ seconds: Float) -> Keyframes<T> {
        var copy = self
        copy._delay = seconds
        return copy
    }

    /// Plays the whole track `times` times (≥ 1). Endless loops belong to ``PhaseAnimator``.
    public func `repeat`(_ times: UInt32) -> Keyframes<T> {
        var copy = self
        copy._repeat = max(times, 1)
        return copy
    }

    /// One pass, in seconds.
    public func duration() -> Float {
        var sum: Float = 0.0
        for f in _frames {
            sum += f.duration()
        }
        return sum
    }

    public func frames() -> [Keyframe<T>] {
        _frames
    }

    fileprivate func lastValue() -> T? {
        _frames.last?.value()
    }
}

extension AnimationStore {
    /// Plays `keyframes` on a property from its current value (cancels anything scheduled on it).
    /// Under Reduce Motion, spatial tracks jump to the final value and fades take the short fade.
    @discardableResult
    public func playKeyframes<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ kf: Keyframes<T>
    ) -> TrackId {
        guard let last = kf.lastValue() else {
            guard let existing = trackId(node, prop) else {
                preconditionFailure("empty keyframes on a new property")
            }
            return existing
        }
        let first = kf._frames[0].value()
        let startValue = has(node, prop) ? sample(node, prop)! : first
        let initLanes = lanes(startValue)
        let n = T.lanes
        let t = initLanes.withBuffer(count: n) { Int(ensure(node, prop.id, prop.class, $0)) }
        if reducedMotion() && prop.class.reduce(.spring(.smooth)) != .spring(.smooth) {
            let targetLanes = lanes(last)
            let anim = Anim(curve: .spring(.smooth), delay: kf._delay)
            targetLanes.withBuffer(count: n) { buf in
                _ = animateRaw(t, buf, anim, nil)
            }
            return idOf(t)
        }
        cancelTrackPending(t)
        var at = timeOf(t) + Double(kf._delay)
        var prev = initLanes
        let frames = kf._frames
        for _ in 0..<kf._repeat {
            for (k, frame) in frames.enumerated() {
                let v = lanes(frame.value())
                let dur = frame.duration()
                for i in 0..<n {
                    let curve: Curve
                    let vel: Float?
                    switch frame {
                    case .linear(_, let duration, let easing):
                        curve = .tween(duration: duration, easing: easing)
                        vel = 0.0
                    case .spring(_, _, let spring):
                        curve = .spring(spring)
                        vel = nil
                    case .move:
                        curve = .instant
                        vel = nil
                    case .cubic(_, let duration):
                        // Catmull-Rom tangent at this keyframe's end, if the next one is cubic too.
                        let nextFrame: Keyframe<T>?
                        if k + 1 < frames.count {
                            nextFrame = frames[k + 1]
                        } else if kf._repeat > 1 {
                            nextFrame = frames.first
                        } else {
                            nextFrame = nil
                        }
                        let m: Float
                        if case .cubic(let nextVal, let d2)? = nextFrame {
                            let nv = lanes(nextVal)
                            m = (nv[i] - prev[i]) / max(duration + d2, 1e-6)
                        } else {
                            m = 0.0
                        }
                        curve = .hermite(duration: duration, endVelocity: m)
                        vel = nil
                    }
                    schedule(t, i, at, v[i], curve, .merge, vel)
                }
                at += Double(dur)
                prev = v
            }
        }
        // Final segment: a spring keyframe may not have arrived when its slot ends; let it finish.
        commitScheduled(t, at, 0)
        return idOf(t)
    }
}
