// Ported from: crates/rune/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rune: keyed element tree from plain view functions, Taffy layout, analytic
//! spring tracks, an instanced uber-quad renderer with shaped text, pointer and keyboard
//! input, scroll viewports, growth stacks, streaming reveals, themes as data, and headless agent
//! tooling.

#if !os(WASI)
import Foundation
#endif
import RuneMotion

// MARK: - RuneMotion Re-exports (`pub use rune_motion::*`)

public typealias Anim = RuneMotion.Anim
public typealias AnimExt = RuneMotion.AnimExt
public typealias Beat = RuneMotion.Beat
public typealias MotionBlend = RuneMotion.Blend
public typealias Clock = RuneMotion.Clock
public typealias CubicBezier = RuneMotion.CubicBezier
public typealias Curve = RuneMotion.Curve
public typealias Cycle = RuneMotion.Cycle
public typealias Decay = RuneMotion.Decay
public typealias Easing = RuneMotion.Easing
public typealias Edge = RuneMotion.Edge
public typealias Effect = RuneMotion.Effect
public typealias LayoutAnim = RuneMotion.LayoutAnim
public typealias LoopKind = RuneMotion.LoopKind
public typealias LoopSpec = RuneMotion.LoopSpec
public typealias NodeId = RuneMotion.NodeId
public typealias PresencePhase = RuneMotion.Phase
public typealias Presented = RuneMotion.Presented
public typealias Reveal = RuneMotion.Reveal
public typealias Sequence = RuneMotion.Sequence
public typealias Spring = RuneMotion.Spring
public typealias SpringPair = RuneMotion.SpringPair
public typealias Stagger = RuneMotion.Stagger
public typealias StaggerFrom = RuneMotion.StaggerFrom
public typealias StepPosition = RuneMotion.StepPosition
public typealias Transition = RuneMotion.Transition
public typealias Travel = RuneMotion.Travel
public typealias Vec2 = RuneMotion.Vec2
public typealias Velocity = RuneMotion.Velocity

// MARK: - SceneClock (`crates/rune/src/lib.rs:318-354`)

/// The logical clock a scene fn (`AppSpec.scenes`) builds its state against. `--scene` starts at time zero.
public struct SceneClock: Sendable, Equatable {
    public var now: Double
    public var dt: Double

    public init(now: Double = 0.0, dt: Double = 0.0) {
        self.now = now
        self.dt = dt
    }
}

#if os(WASI)
// PORT NOTE: WASI (`wasm32-unknown-wasip1`) is single-threaded; `sceneClockWasi` is accessed on the sole execution thread.
nonisolated(unsafe) private var sceneClockWasi = SceneClock()
#endif
private let sceneClockThreadKey = "gpua.rune.sceneClock"

/// Readable from scene fns, `AppSpec.init` and `AppSpec.setup`; zero anywhere else.
public func sceneClock() -> SceneClock {
    #if os(WASI)
    return sceneClockWasi
    #else
    if let val = Thread.current.threadDictionary[sceneClockThreadKey] as? SceneClock {
        return val
    }
    return SceneClock()
    #endif
}

/// Runs `f` (a scene fn or `init`) with `clock` as the scene clock.
public func withSceneClock<T>(_ clock: SceneClock, _ f: () throws -> T) rethrows -> T {
    let before = sceneClock()
    #if os(WASI)
    sceneClockWasi = clock
    defer { sceneClockWasi = before }
    #else
    Thread.current.threadDictionary[sceneClockThreadKey] = clock
    defer { Thread.current.threadDictionary[sceneClockThreadKey] = before }
    #endif
    return try f()
}

/// An XDG activation token from the latest pointer press on a Wayland overlay; nil off Wayland or before any press.
public func pressActivationToken(_ appId: String? = nil) -> String? {
    _ = appId
    return nil
}
