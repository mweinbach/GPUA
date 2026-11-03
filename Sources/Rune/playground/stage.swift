// Ported from: crates/rune/src/playground/stage.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The stage: triggers and their steps on the logical clock, and the state handlers, keys and
//! polls reach while the playground is open.

#if !os(WASI)
import Foundation
#endif
import RuneMotion

/// A step a trigger runs, now or later on the logical clock: see ``Play/after(_:_:)``.
public typealias Step<X> = (inout X, Play<X>) -> Void

/// How the stage lays a story out, from ``Story/stage(_:)`` or ``Playground/stage(_:_:)``.
public enum Stage: Sendable, Equatable, Hashable {
    /// Sized as a window sizes its root, to the stage or the size picked beside it, in the
    /// stage's middle.
    case center
    /// For content taller than the stage: laid out at the stage's width inside a 24 pt margin,
    /// at its own height, from the top, and the stage scrolls.
    case scroll
    /// Edge to edge across the whole stage, whatever size is picked beside it.
    case fill

    public static let Center: Stage = .center
    public static let Scroll: Stage = .scroll
    public static let Fill: Stage = .fill
}

/// ``Stage/scroll``'s margin.
let PLAYGROUND_SCROLL_MARGIN: Float = 24.0

/// How far past the clock a step can be due and still run on this frame, in seconds.
private let PLAYGROUND_DUE_SLACK: Double = 1e-6

/// What a trigger's steps get beside their state: the frame's ``Tx`` and ``Play/after(_:_:)``
/// for the steps that follow.
// PORT NOTE: In Rust `Play` implements `DerefMut<Target = Tx>`. In Swift `Play` exposes `tx` plus
// convenience forwarding methods for `Tx` mutations so trigger closures read identically.
public final class Play<X> {
    public var tx: Tx
    var script: [(Double, (inout X, Play<X>) -> Void)]
    private let dueTime: Double

    init(
        tx: Tx,
        script: [(Double, (inout X, Play<X>) -> Void)],
        now: Double
    ) {
        self.tx = tx
        self.script = script
        self.dueTime = now
    }

    /// Runs `step` `secs` after this one, on the runtime's logical clock.
    public func after(_ secs: Double, _ step: @escaping (inout X, Play<X>) -> Void) {
        script.append((dueTime + max(secs, 0.0), step))
    }

    /// Drops every step still queued on this stage, a loop's next one included; steps queued
    /// after it in this step still run.
    public func clear() {
        script.removeAll()
    }

    /// When this step was due, on the runtime's clock.
    public func now() -> Double {
        dueTime
    }

    // `DerefMut<Target = Tx>` conveniences:
    public func instant() { tx.instant() }
    public func animated() { tx.animated() }
    public func motion(_ spring: Spring) { tx.motion(spring) }
    public func motionCurve(_ anim: Anim) { tx.motionCurve(anim) }
    public func settle() { tx.settle() }
    public func relayout() { tx.relayout() }
    public func wakeAfter(_ seconds: Double) { tx.wakeAfter(seconds) }
    public func focus(_ key: String) { tx.focus(key) }
    public func blur() { tx.blur() }
    public func scrollIntoView(_ key: String) { tx.scrollIntoView(key) }
    public func scrollCenter(_ key: String) { tx.scrollCenter(key) }
    public func scrollToBottom(_ key: String, animated: Bool = true) { tx.scrollToBottom(key, animated: animated) }
    public func scrollTo(_ key: String, _ y: Float, animated: Bool = true) { tx.scrollTo(key, y, animated: animated) }
}

/// A trigger: a step on a single-letter key, shown as a button in the side column.
struct PlaygroundTrigger<X> {
    let key: Character
    let label: String
    let run: (inout X, Play<X>) -> Void

    func queued() -> (inout X, Play<X>) -> Void {
        let fn = run
        return { state, play in fn(&state, play) }
    }
}

func makePlaygroundTrigger<X>(
    _ key: Character,
    _ label: String,
    _ run: @escaping (inout X, Play<X>) -> Void
) -> PlaygroundTrigger<X> {
    let lower = Character(String(key).lowercased())
    precondition(
        lower != "j" && lower != "k",
        "J and K move between stories; give the \(label.debugDescription) trigger another key"
    )
    return PlaygroundTrigger(key: lower, label: label, run: run)
}

func makePlaygroundTriggerTx<X>(
    _ key: Character,
    _ label: String,
    _ run: @escaping (inout X, inout Tx) -> Void
) -> PlaygroundTrigger<X> {
    makePlaygroundTrigger(key, label) { state, play in
        run(&state, &play.tx)
    }
}

func playgroundCall<X>(_ view: (X, Cx<X>) -> El, _ state: X, _ cx: Cx<X>) -> El {
    view(state, cx)
}

/// A stage's state and its triggers' queued steps.
final class PlaygroundStaged<X> {
    var state: X
    var script: [(Double, (inout X, Play<X>) -> Void)] = []

    init(_ state: X) {
        self.state = state
    }

    /// Runs the steps due by `t`, earliest first, each seeing the time it was due.
    func run(_ t: Double, _ tx: inout Tx) -> Bool {
        let deadline = t + PLAYGROUND_DUE_SLACK
        var ran = false
        for _ in 0..<64 {
            var earliestIdx: Int? = nil
            var earliestAt = Double.infinity
            for (idx, entry) in script.enumerated() where entry.0 <= deadline {
                if entry.0 < earliestAt {
                    earliestAt = entry.0
                    earliestIdx = idx
                }
            }
            guard let idx = earliestIdx else { break }
            let (at, step) = script.remove(at: idx)
            let play = Play<X>(tx: tx, script: script, now: at)
            step(&state, play)
            tx = play.tx
            script = play.script
            ran = true
        }
        if let next = script.map(\.0).min() {
            tx.wakeAfter(max(next - deadline, 0.0))
        }
        return ran
    }
}

extension PlaygroundLive {
    /// Runs `body` against the active stage state (or `app` when closed / on a live page) plus
    /// `controls`, writing any mutations back.
    func withStates<R>(_ app: inout S, _ body: (States) -> R) -> R {
        if !open {
            var cBox = controls
            let states = States.two(app, cBox)
            let result = body(states)
            if let updated = states.app as? S { app = updated }
            if let updatedC = states.extra as? PlaygroundControls { cBox = updatedC; controls = cBox }
            return result
        }
        if let scene {
            var cBox = controls
            let states = States.two(scene.state, cBox)
            let result = body(states)
            if let updated = states.app as? S { scene.state = updated }
            if let updatedC = states.extra as? PlaygroundControls { cBox = updatedC; controls = cBox }
            return result
        }
        if let (pageIdx, page) = currentPage(),
           case .own(let own) = page.kind,
           let stageBox = owned[pageIdx]
        {
            var cBox = controls
            let states = States.two(own.stateValue(stageBox), cBox)
            let result = body(states)
            own.writeBackState(stageBox, from: states.app)
            if let updatedC = states.extra as? PlaygroundControls { cBox = updatedC; controls = cBox }
            return result
        }
        var cBox = controls
        let states = States.two(app, cBox)
        let result = body(states)
        if let updated = states.app as? S { app = updated }
        if let updatedC = states.extra as? PlaygroundControls { cBox = updatedC; controls = cBox }
        return result
    }

    func statesRef(_ app: S) -> StatesRef {
        if !open {
            return StatesRef.two(app, controls)
        }
        if let scene {
            return StatesRef.two(scene.state, controls)
        }
        if let (own, stageBox) = own() {
            return StatesRef.two(own.stateValue(stageBox), controls)
        }
        return StatesRef.two(app, controls)
    }

    /// Whether the stage's `App.onIme` hears the input method now.
    func stageHears(_ app: S) -> Bool {
        !open || currentRegion == .stage || isTyping(app)
    }

    /// Runs `f` on the state `AppSpec.onKey` gets: the stage's when it's an app state, none on
    /// a story with its own.
    func withKeyState<R>(_ app: inout S, _ f: (inout S) -> R) -> R? {
        if !open {
            return f(&app)
        }
        if let (_, page) = currentPage(), case .own = page.kind {
            return nil
        }
        if let scene {
            return f(&scene.state)
        }
        return f(&app)
    }

    /// Whether ``Playground/typing(_:)`` gives the stage's `onKey` every key first.
    func isTyping(_ app: S) -> Bool {
        guard open, let typingFn = typing else { return false }
        if let scene {
            return typingFn(scene.state)
        }
        if let (_, page) = currentPage(), case .own = page.kind {
            return false
        }
        return typingFn(app)
    }

    func polls() -> Bool {
        guard open else { return false }
        if let scene {
            return poll != nil || !scene.script.isEmpty
        }
        if let (own, stageBox) = own() {
            return own.polls(stageBox)
        }
        return false
    }

    /// Polls the stage's state after the app's own poll: its due steps, then `AppSpec.poll`
    /// for a scene or the story's own.
    func pollStage(_ t: Double, _ tx: inout Tx) -> Bool {
        now = t
        guard open else { return false }
        if let scene {
            let ran = scene.run(t, &tx)
            let polled = poll?(&scene.state, t, &tx) ?? false
            return polled || ran
        }
        if let (pageIdx, page) = currentPage(),
           case .own(let own) = page.kind,
           let stageBox = owned[pageIdx]
        {
            return own.poll(stageBox, t, &tx)
        }
        return false
    }
}
