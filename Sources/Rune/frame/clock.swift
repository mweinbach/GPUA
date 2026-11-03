// Ported from: crates/rune/src/frame/clock.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! How far each presented frame moves animation time. Windows, overlays and the headless hosts
//! share this rule so they can't drift apart.
//!
//! Like Core Animation, a late frame never loses time: motion already running advances by the
//! real gap between this frame's target presentation time and the previous frame's, so after
//! a 49 ms hitch it is where an unbroken cadence would have it. Motion that starts or is
//! retargeted on the frame starts at the frame's time and shows one small step, so it never
//! jumps by the gap. Both happen in one runtime pass (`Runtime.frameSplit`).

/// The most a frame steps motion it starts. Its first frame shows one 120 Hz frame of movement,
/// instead of repeating its start pose or jumping ahead by a late frame's gap or the time
/// spent idle.
let RESUME_STEP: Double = 1.0 / 120.0

/// The longest gap, in seconds, charged to running motion. A hitch someone sees lasts a few
/// frames; 250 ms is 30 frames at 120 Hz, past any hitch worth keeping time through and still
/// shorter than a typical spring takes to settle. A longer gap means the host was suspended
/// (App Nap, a debugger, sleep, a stalled main thread), hidden or occluded, so running motion
/// moves at most this far rather than teleporting to its end.
let MAX_GAP: Double = 0.25

/// A single frame's animation time split into catch-up for running motion and the new-motion step.
struct FrameStep: Sendable, Equatable {
    /// Charged only to motion already running, before this frame's commits.
    var catchUp: Double
    /// This frame's step for all motion, including what its commits start.
    var dt: Double

    init(catchUp: Double, dt: Double) {
        self.catchUp = catchUp
        self.dt = dt
    }

    func total() -> Double {
        catchUp + dt
    }
}

/// The step for a frame `gap` seconds after the last. `running`: motion was still running
/// after the previous frame. Running motion gets the whole gap, at most `MAX_GAP`; what
/// starts on the frame gets at most `RESUME_STEP` of it. With nothing running the frame
/// steps `RESUME_STEP`, so motion it starts moves one frame, however long the idle.
func frameSplit(_ gap: Double, _ running: Bool) -> FrameStep {
    if !running {
        return FrameStep(catchUp: 0.0, dt: RESUME_STEP)
    }
    let total = min(max(gap, 0.0), MAX_GAP)
    let dt = min(total, RESUME_STEP)
    return FrameStep(catchUp: total - dt, dt: dt)
}

/// Steps `rt` by a frame `gap` seconds after the last, for hosts without presentation times
/// (the hot loop). Without a wall clock, timers and poll still see the whole gap.
@discardableResult
func frameAdvanceBy<S>(_ rt: Runtime<S>, _ gap: Double, running: Bool = false) -> Bool {
    let step = frameSplit(gap, running)
    rt.clock += max(gap - step.total(), 0.0)
    if step.catchUp > 0.0 {
        rt.clock += step.catchUp
        rt.t += step.catchUp * Double(rt.timeScale)
        rt.scene.setTime(rt.t)
    }
    _ = rt.frame(step.dt)
    return rt.scene.frame().animating
}

/// Presentation-time frame clock shared across windows, overlays, and headless hosts.
struct FrameClock: Sendable, Equatable {
    private var lastTarget: RuneInstant

    init(_ now: RuneInstant) {
        self.lastTarget = now
    }

    static func new(_ now: RuneInstant) -> FrameClock {
        FrameClock(now)
    }

    /// The target time of the last frame the clock stepped to.
    func last() -> RuneInstant {
        lastTarget
    }

    /// A frame at `at` that steps no time (prewarm, hidden), or one that caught motion up to
    /// `at`. Display-link targets run ahead of `RuneInstant.now()`, so the clock never goes back.
    mutating func hold(_ at: RuneInstant) {
        if at > lastTarget {
            lastTarget = at
        }
    }

    /// The step for a frame presented at `at`. See `frameSplit`.
    mutating func step(_ at: RuneInstant, _ running: Bool) -> FrameStep {
        let d = at.durationSince(lastTarget)
        let gap = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
        hold(at)
        return frameSplit(gap, running)
    }

    /// Steps `rt` to the frame presented at `at`, in one runtime pass. `compositing`: a
    /// compositor's own animation was still running after the previous frame. Returns whether
    /// anything still animates and the seconds stepped.
    @discardableResult
    mutating func advance<S>(
        _ rt: Runtime<S>,
        _ at: RuneInstant,
        _ compositing: Bool,
        running: Bool = false
    ) -> (Bool, Double) {
        let s = step(at, running || compositing)
        if s.catchUp > 0.0 {
            rt.clock += s.catchUp
            rt.t += s.catchUp * Double(rt.timeScale)
            rt.scene.setTime(rt.t)
        }
        _ = rt.frame(s.dt)
        return (rt.scene.frame().animating, s.total())
    }
}
