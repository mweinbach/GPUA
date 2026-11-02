// Ported from: crates/rune-motion/src/curve.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// Anything that converts into a ``Curve`` (Swift counterpart to `impl Into<Curve>`).
public protocol CurveConvertible: Sendable {
    func intoCurve() -> Curve
}

/// The shape of one animation segment.
public enum Curve: Sendable, Equatable {
    /// Physics. Retargets merge (SwiftUI): the new spring starts from the exact position and velocity.
    case spring(Spring)
    /// A fixed-duration eased tween (CSS transition). Retargets add (Core Animation).
    case tween(duration: Float, easing: Easing)
    /// Fling inertia: velocity decays exponentially toward the projected rest point.
    case decay(Decay)
    /// Jump to the target this frame.
    case instant
    /// Internal: a cubic Hermite keyframe segment. Built by ``Keyframes``.
    case hermite(duration: Float, endVelocity: Float)
}

extension Curve: CurveConvertible {
    @inline(__always)
    public func intoCurve() -> Curve {
        self
    }
}

extension Spring: CurveConvertible {
    /// ``Spring/none`` is ``Curve/instant``.
    @inline(__always)
    public func intoCurve() -> Curve {
        self == .none ? .instant : .spring(self)
    }
}

extension Curve {
    /// `From<Spring> for Curve`: ``Spring/none`` is ``Curve/instant``.
    public init(_ s: Spring) {
        self = s.intoCurve()
    }

    public static func tween(_ duration: Float, _ easing: Easing) -> Curve {
        .tween(duration: duration, easing: easing)
    }

    public static func linear(_ duration: Float) -> Curve {
        .tween(duration: duration, easing: .linear)
    }

    public static func easeInOut(_ duration: Float) -> Curve {
        .tween(duration: duration, easing: .easeInOut)
    }

    /// When the animation "logically" completes (SwiftUI `.logicallyComplete`): a spring's
    /// perceptual duration, a tween's duration. Choreography cues on this, not on physical rest.
    public func logicalDuration() -> Float {
        switch self {
        case .spring(let s):
            return s.duration
        case .tween(let duration, _), .hermite(let duration, _):
            return duration
        case .decay(let d):
            return 1.0 / d.k()
        case .instant:
            return 0.0
        }
    }

    func defaultBlend() -> Blend {
        switch self {
        case .tween:
            return .additive
        default:
            return .merge
        }
    }
}

/// Exponential velocity decay, `v(t) = v0 · e^{−k t}`; the value comes to rest at `x0 + v0 / k`.
public struct Decay: Sendable, Equatable, Hashable {
    /// Rate constant k in 1/s.
    public var rate: Float

    public init(_ rate: Float) {
        self.rate = rate
    }

    public init(rate: Float) {
        self.rate = rate
    }

    /// iOS `UIScrollView.DecelerationRate.normal`: 0.998 per ms (k ≈ 2.002/s).
    public static let iosNormal = Decay(rate: 2.002_002)
    /// iOS `UIScrollView.DecelerationRate.fast`: 0.99 per ms (k ≈ 10.05/s).
    public static let iosFast = Decay(rate: 10.050_336)

    /// From a per-millisecond deceleration rate `r` (UIKit): k = −1000 · ln r.
    public static func perMs(_ r: Float) -> Decay {
        precondition(r > 0.0 && r < 1.0, "deceleration rate must be in (0, 1)")
        return Decay(rate: -1000.0 * logf(r))
    }

    @inline(__always)
    func k() -> Float {
        max(rate, 1e-3)
    }
}

/// How a new animation combines with what's already moving on the same value.
public enum Blend: Sendable, Equatable, Hashable {
    /// Springs, decay and keyframes merge; tweens add.
    case auto
    /// Sample `(x, v)` now and start one new segment from there (SwiftUI spring merging,
    /// Compose `animateTo`). One segment per lane, O(1) sampling.
    case merge
    /// Keep running segments and add a new one that animates the target delta to 0
    /// (Core Animation additive animations). Each curve keeps its own shape.
    case additive

    public init() {
        self = .auto
    }
}

/// Starting velocity for a new segment.
public enum Velocity: Sendable, Equatable {
    /// Keep the current velocity (the default: interruptible motion).
    case inherit
    /// Start from rest.
    case zero
    /// The same velocity on every lane, in property units per second.
    case uniform(Float)

    public init() {
        self = .inherit
    }
}

/// A curve plus how and when to apply it: what `animate` takes.
public struct Anim: Sendable, Equatable {
    public var curve: Curve
    /// Seconds before the new target takes effect. A newer animate on the same value cancels it.
    public var delay: Float
    public var blend: Blend
    public var velocity: Velocity
    /// Non-zero: a `MotionEvent.completed(node:prop:token:finished:)` fires when this animation
    /// settles (or is replaced, with `finished: false`). SwiftUI's `withAnimation(_:completion:)`.
    public var token: UInt64

    public init(
        curve: Curve,
        delay: Float = 0.0,
        blend: Blend = .auto,
        velocity: Velocity = .inherit,
        token: UInt64 = 0
    ) {
        self.curve = curve
        self.delay = delay
        self.blend = blend
        self.velocity = velocity
        self.token = token
    }

    public init(_ curve: Curve) {
        self.init(curve: curve)
    }

    public init(_ spring: Spring) {
        self.init(curve: spring.intoCurve())
    }

    /// A pair used where no direction is known animates on `enter`.
    public init(_ pair: SpringPair) {
        self.init(curve: pair.enter.intoCurve())
    }

    public static func new(_ curve: Curve) -> Anim {
        Anim(curve: curve)
    }

    public static let instant = Anim(curve: .instant)

    func resolvedBlend() -> Blend {
        switch blend {
        case .auto:
            return curve.defaultBlend()
        case let b:
            return b
        }
    }
}

/// Builder methods on anything that converts to an ``Anim``: `motion.settle.delay(0.05)`.
public protocol AnimExt: Sendable {
    func intoAnim() -> Anim
}

extension AnimExt {
    public func delay(_ seconds: Float) -> Anim {
        var a = intoAnim()
        a.delay = seconds
        return a
    }

    public func blend(_ blend: Blend) -> Anim {
        var a = intoAnim()
        a.blend = blend
        return a
    }

    public func additive() -> Anim {
        blend(.additive)
    }

    public func merge() -> Anim {
        blend(.merge)
    }

    public func velocity(_ velocity: Velocity) -> Anim {
        var a = intoAnim()
        a.velocity = velocity
        return a
    }

    public func completion(_ token: UInt64) -> Anim {
        var a = intoAnim()
        a.token = token
        return a
    }
}

extension Anim: AnimExt {
    @inline(__always)
    public func intoAnim() -> Anim {
        self
    }
}

extension Curve: AnimExt {
    @inline(__always)
    public func intoAnim() -> Anim {
        Anim(curve: self)
    }
}

extension Spring: AnimExt {
    @inline(__always)
    public func intoAnim() -> Anim {
        Anim(self)
    }
}

extension SpringPair: AnimExt {
    @inline(__always)
    public func intoAnim() -> Anim {
        Anim(self)
    }
}
