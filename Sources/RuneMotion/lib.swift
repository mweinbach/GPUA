// Ported from: crates/rune-motion/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// # RuneMotion
///
/// Rune's animation runtime: pure math and data structures the render thread drives once per
/// frame. App code states targets; this module turns them into presented values with no app work
/// per frame (PLAN.md §3, §4.9; research 06).
///
/// - ``Spring``: SwiftUI's `Spring(duration:bounce:)`, closed form for every damping regime.
/// - ``Curve``: springs, CSS tweens (``Easing``), decay (fling), keyframes.
/// - ``Animatable``: `Float`, ``Vec2``, ``Rect`` (as edges), ``Color`` (premultiplied OKLab),
///   ``Corners``, ``Transform``, ``Blur``, pairs, triples, arrays.
/// - ``AnimationStore``: struct-of-arrays tracks, retargeting that keeps position and velocity,
///   merge or additive blending, delays, settle events, zero allocation per frame.
/// - ``Scene``: presence (exits that stay mounted), ``Transition``s incl. blur-replace, layout
///   animation by edges, screen-space travel, matched geometry, per-frame ``Presented`` output.
/// - ``Choreography``, ``Stagger``, ``PhaseAnimator``, ``Keyframes``; ``Clock``; motion-lint
///   ``MotionTrace``s.
///
/// ```swift
/// import RuneMotion
///
/// let store = AnimationStore()
/// let card = NodeId(1)
/// store.set(card, prop.opacity, 0.0)
/// store.animate(card, prop.opacity, 1.0, motion.settle)
/// store.tickAt(0.15)
/// let o = store.get(card, prop.opacity)!
/// assert(o > 0.5 && o < 1.0)
/// ```
// PORT NOTE: Swift modules export all `public` declarations across files in `RuneMotion` directly,
// so Rust's `pub use` re-exports and `pub mod prelude` are directly available via `import RuneMotion`.
// `pub use tokens as motion` is provided as a public `typealias`.
public typealias motion = tokens
