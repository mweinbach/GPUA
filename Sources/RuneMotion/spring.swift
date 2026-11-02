// Ported from: crates/rune-motion/src/spring.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// A critically/under/over-damped spring with mass 1, described the way people tune it.
///
/// `Spring(duration, bounce)` maps exactly like SwiftUI's `Spring(duration:bounce:)`,
/// Flutter's `SpringDescription.withDurationAndBounce`, knobs and `kit_motion.rs`:
///
/// ```text
/// ω = 2π / duration          stiffness k = ω²   (mass 1)
/// ζ = 1 − bounce             (bounce ≥ 0)       damping   c = 2ζω
/// ζ = 1 / (1 + bounce)       (bounce < 0, overdamped)
/// ```
///
/// Motion (motion.dev) uses a *different* number for the same feel: its `visualDuration` is this
/// duration ÷ 1.2. Use ``Spring/fromMotion(_:_:)`` / ``Spring/motionVisualDuration()`` at that boundary.
public struct Spring: Sendable, Equatable, Hashable, Codable {
    /// Perceptual duration in seconds (SwiftUI `duration`, the undamped period).
    public var duration: Float
    /// −1 < bounce < 1. 0 is critically damped (Kit's default), > 0 overshoots, < 0 is overdamped.
    public var bounce: Float

    // PORT NOTE: Swift `Float.pi` rounds toward zero (`0x40490fda`), whereas Rust `f32::consts::TAU`
    // is IEEE-754 round-to-nearest `2π` (`0x40c90fdb`). Use the exact nearest literal for bit parity.
    private static let tau: Float = 6.28318530717958647692528676655900577

    /// `Spring(duration:bounce:)`. Traps on a non-positive duration or a bounce outside (−1, 1).
    public init(_ duration: Float, _ bounce: Float) {
        precondition(duration > 0.0 && duration < 1e4, "spring duration must be positive seconds")
        precondition(bounce > -1.0 && bounce < 1.0, "spring bounce must be in (-1, 1)")
        self.duration = duration
        self.bounce = bounce
    }

    public init(duration: Float, bounce: Float) {
        self.init(duration, bounce)
    }

    public static func new(_ duration: Float, _ bounce: Float) -> Spring {
        Spring(duration, bounce)
    }

    /// SwiftUI `.spring(response:dampingFraction:)`: ω = 2π/response, ζ = dampingFraction.
    public static func fromResponse(_ response: Float, _ dampingFraction: Float) -> Spring {
        Spring.fromOmegaZeta(tau / response, dampingFraction)
    }

    /// From angular frequency ω (rad/s) and damping ratio ζ (> 0).
    public static func fromOmegaZeta(_ omega: Float, _ zeta: Float) -> Spring {
        precondition(omega > 0.0 && zeta > 0.0, "omega and zeta must be positive")
        let b: Float = zeta <= 1.0 ? (1.0 - zeta) : (1.0 / zeta - 1.0)
        let clamped = min(max(b, -0.999), 0.999)
        return Spring(tau / omega, clamped)
    }

    /// SwiftUI `Spring(mass:stiffness:damping:)` / CSS-physics / Motion `{ stiffness, damping, mass }`.
    public static func fromStiffnessDamping(_ stiffness: Float, _ damping: Float, _ mass: Float) -> Spring {
        let omega = (stiffness / mass).squareRoot()
        let zeta = damping / (2.0 * (stiffness * mass).squareRoot())
        return Spring.fromOmegaZeta(omega, zeta)
    }

    /// Motion's `{ visualDuration, bounce }`: Motion uses ω = 2π / (1.2 · visualDuration).
    /// So Motion `visualDuration: 0.45` is `Spring(0.54, ..)`. Psychopomp's
    /// `SpringPlan::visual(d, b)` uses the same 1.2 factor.
    public static func fromMotion(_ visualDuration: Float, _ bounce: Float) -> Spring {
        Spring(visualDuration * 1.2, bounce)
    }

    /// The `visualDuration` to hand Motion for the same physical spring.
    public func motionVisualDuration() -> Float {
        duration / 1.2
    }

    /// Angular frequency ω = 2π / duration (rad/s).
    @inline(__always)
    public func omega() -> Float {
        Self.tau / duration
    }

    /// Damping ratio ζ.
    @inline(__always)
    public func zeta() -> Float {
        if bounce >= 0.0 {
            return 1.0 - bounce
        } else {
            return 1.0 / (1.0 + bounce)
        }
    }

    /// k = ω² (mass 1).
    public func stiffness() -> Float {
        let w = omega()
        return w * w
    }

    /// c = 2ζω (mass 1).
    public func damping() -> Float {
        2.0 * zeta() * omega()
    }

    /// SwiftUI's `response` (the same number as `duration`).
    public func response() -> Float {
        duration
    }

    /// A copy with a different duration (keeps bounce).
    public func withDuration(_ duration: Float) -> Spring {
        Spring(duration, bounce)
    }

    /// Position and velocity at `t` seconds after leaving `x0` with velocity `v0` toward `target`.
    /// Closed form for every damping regime; exact at any `t`, so it can be sampled at the display
    /// link's target timestamp and retargeted from there.
    public func sample(_ x0: Float, _ v0: Float, _ target: Float, _ t: Float) -> (Float, Float) {
        let layer = Layer.springUnbounded(self, 0.0, x0 - target, v0)
        let (o, v) = layer.sample(Double(t))
        return (target + o, v)
    }

    /// Seconds until a unit step (0 → 1 from rest) stays within `epsilon` of the target, in both
    /// position and velocity (velocity threshold `10·epsilon` per second).
    public func settlingDuration(_ epsilon: Float) -> Float {
        let layer = Layer.spring(self, 0.0, -1.0, 0.0, Eps(pos: epsilon, vel: epsilon * 10.0))
        return Float(layer.end)
    }

    /// Tail bound for an arbitrary retarget, using the same thresholds and 120 s cap as the store.
    public func settlingDurationFrom(_ from: Float, _ velocity: Float, _ target: Float, _ epsilon: Float) -> Float {
        precondition(epsilon.isFinite && epsilon > 0.0)
        let layer = Layer.spring(self, 0.0, from - target, velocity, Eps(pos: epsilon, vel: epsilon * 10.0))
        return Float(max(layer.end, 0.0))
    }

    /// Bakes the unit step response into a CSS `linear()` easing plus its duration in ms,
    /// like knobs' `springEasing`. For web backends that offload to WAAPI.
    public func cssLinear() -> (String, UInt32) {
        let total = max(settlingDuration(0.002), 1.0 / 60.0)
        let n = min(max(Int(ceil(total * 60.0)), 2), 240)
        var s = "linear(0"
        for i in 1..<n {
            let t = total * Float(i) / Float(n)
            let (x, _) = sample(0.0, 0.0, 1.0, t)
            let rounded = (x * 1000.0).rounded(.toNearestOrAwayFromZero) / 1000.0
            if rounded == rounded.rounded(.towardZero) {
                s += ",\(Int(rounded))"
            } else {
                s += ",\(rounded)"
            }
        }
        s += ",1)"
        return (s, UInt32((total * 1000.0).rounded(.toNearestOrAwayFromZero)))
    }

    /// No motion: as a ``Curve`` or ``Anim`` (a transition's presence, a layout change) it is
    /// `Curve.instant`, which Reduce Motion leaves instant where it turns a short spring into a
    /// fade. ``SpringPair/none`` and ``Transition/none()`` build on it.
    public static let none = Spring(1e-6, 0.0)

    // SwiftUI's named springs (iOS 17+). Duration 0.5 by default.

    /// SwiftUI `.smooth`: duration 0.5, bounce 0.
    public static let smooth = Spring(0.5, 0.0)
    /// SwiftUI `.snappy`: duration 0.5, bounce 0.15.
    public static let snappy = Spring(0.5, 0.15)
    /// SwiftUI `.bouncy`: duration 0.5, bounce 0.3.
    public static let bouncy = Spring(0.5, 0.3)
    /// SwiftUI `.spring` (the iOS 17 default): duration 0.5, bounce 0.
    public static let `default` = Spring(0.5, 0.0)

    /// SwiftUI `.smooth(duration:extraBounce:)`.
    public static func smooth(_ duration: Float, _ extraBounce: Float) -> Spring {
        Spring(duration, extraBounce)
    }

    /// SwiftUI `.snappy(duration:extraBounce:)`.
    public static func snappy(_ duration: Float, _ extraBounce: Float) -> Spring {
        Spring(duration, 0.15 + extraBounce)
    }

    /// SwiftUI `.bouncy(duration:extraBounce:)`.
    public static func bouncy(_ duration: Float, _ extraBounce: Float) -> Spring {
        Spring(duration, 0.3 + extraBounce)
    }

    /// SwiftUI `.interactiveSpring()`: response 0.15, damping fraction 0.86.
    public static func interactive() -> Spring {
        Spring.fromResponse(0.15, 0.86)
    }
}

/// An enter/exit pair. Exits run 10–25 % shorter (Kit rule 4); presence and `open → closed`
/// toggles use `exit`, everything else `enter`.
public struct SpringPair: Sendable, Equatable, Hashable, Codable {
    public var enter: Spring
    public var exit: Spring

    public init(_ enter: Spring, _ exit: Spring) {
        self.enter = enter
        self.exit = exit
    }

    public init(enter: Spring, exit: Spring) {
        self.enter = enter
        self.exit = exit
    }

    public static func new(_ enter: Spring, _ exit: Spring) -> SpringPair {
        SpringPair(enter, exit)
    }

    /// ``Spring/none`` both ways: enters and leaves in the frame it starts.
    public static let none = SpringPair(.none, .none)

    /// A pair whose exit is `enter` shortened by `ratio` (Kit: 0.75–0.9).
    public static func withExitRatio(_ enter: Spring, _ ratio: Float) -> SpringPair {
        SpringPair(enter, Spring(enter.duration * ratio, enter.bounce * 0.5))
    }
}
