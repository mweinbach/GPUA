// Ported from: crates/rune/src/window/frame.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Frame clock, first-frame hold, hidden poll pacing, and timer wake deadlines (`crates/rune/src/window/frame.rs`).

#if !os(WASI)
import Foundation
#endif
import RuneMotion

// MARK: - Window Frame Geometry & Spring Animation (`crates/rune/src/window/frame.rs`)

/// What handlers asked of their window's frame, merged across a commit (`crates/rune/src/window/frame.rs`).
struct WindowFrameRequest: Sendable, Equatable {
    var size: (Float, Float)?
    var animate: Bool
    var spring: Spring?
    var center: Bool

    init(
        size: (Float, Float)? = nil,
        animate: Bool = false,
        spring: Spring? = nil,
        center: Bool = false
    ) {
        self.size = size
        self.animate = animate
        self.spring = spring
        self.center = center
    }

    func merge(_ later: WindowFrameRequest) -> WindowFrameRequest {
        let resolvedSize: (Float, Float)?
        let resolvedAnimate: Bool
        let resolvedSpring: Spring?
        if later.size != nil {
            resolvedSize = later.size
            resolvedAnimate = later.animate
            resolvedSpring = later.spring
        } else {
            resolvedSize = self.size
            resolvedAnimate = self.animate
            resolvedSpring = self.spring
        }
        return WindowFrameRequest(
            size: resolvedSize,
            animate: resolvedAnimate,
            spring: resolvedSpring,
            center: self.center || later.center
        )
    }

    static func == (lhs: WindowFrameRequest, rhs: WindowFrameRequest) -> Bool {
        let sameSize: Bool
        switch (lhs.size, rhs.size) {
        case (nil, nil): sameSize = true
        case (let a?, let b?): sameSize = a.0 == b.0 && a.1 == b.1
        default: sameSize = false
        }
        return sameSize
            && lhs.animate == rhs.animate
            && lhs.spring == rhs.spring
            && lhs.center == rhs.center
    }
}

// PORT NOTE: Synchronized via `LiveLock` so `Tx` copies share pending window-frame resize/center requests without touching `Sources/Rune/el/el_tx.swift`.
final class WindowFrameRequestBox: @unchecked Sendable {
    private let lock = LiveLock()
    private var request: WindowFrameRequest?

    init(_ request: WindowFrameRequest) {
        self.request = request
    }

    func take() -> WindowFrameRequest? {
        lock.withLock {
            let r = request
            request = nil
            return r
        }
    }
}

extension Tx {
    mutating func hostResizeWindow(_ size: (Float, Float)) {
        appendSidecar(WindowFrameRequestBox(WindowFrameRequest(size: size, animate: true, spring: nil, center: false)))
    }

    mutating func hostResizeWindowInstant(_ size: (Float, Float)) {
        appendSidecar(WindowFrameRequestBox(WindowFrameRequest(size: size, animate: false, spring: nil, center: false)))
    }

    mutating func hostCenterWindow() {
        appendSidecar(WindowFrameRequestBox(WindowFrameRequest(size: nil, animate: false, spring: nil, center: true)))
    }
}

/// Computes target window `[x, y, w, h]` in top-down screen points (`crates/rune/src/window/frame.rs`).
func windowFrameTarget(
    _ current: [Float],
    _ outer: (Float, Float)?,
    _ center: Bool,
    _ visible: [Float]
) -> [Float] {
    let w = outer?.0 ?? current[2]
    let h = outer?.1 ?? current[3]
    let vx = visible[0]
    let vy = visible[1]
    let vw = visible[2]
    let vh = visible[3]
    var x = current[0]
    var y = current[1]
    if center {
        x = vx + ((vw - w) / 2.0).rounded(.down)
        y = vy + ((vh - h) / 4.0).rounded(.down)
    }
    let left = center ? vx : min(current[0], vx)
    let top = center ? vy : min(current[1], vy)
    let right = center ? (vx + vw) : max(current[0] + current[2], vx + vw)
    let bottom = center ? (vy + vh) : max(current[1] + current[3], vy + vh)
    x = max(min(x, right - w), left)
    y = max(min(y, bottom - h), top)
    return [x, y, w, h]
}

private let WINDOW_FRAME_EPSILON: Float = 0.25

/// Closed-form 4-track spring animation for window `[x, y, w, h]` (`crates/rune/src/window/frame.rs`).
struct WindowFrameAnim: Sendable, Equatable {
    var spring: Spring?
    private var start: Double
    private var from: [Float]
    private var velocity: [Float]
    var to: [Float]
    private var end: Double

    static func new(
        _ spring: Spring?,
        _ now: Double,
        _ from: [Float],
        _ velocity: [Float],
        _ to: [Float]
    ) -> WindowFrameAnim {
        let settling: Float
        if let s = spring {
            var maxDur: Float = 0.0
            for i in 0..<4 {
                maxDur = max(maxDur, s.settlingDurationFrom(from[i], velocity[i], to[i], WINDOW_FRAME_EPSILON))
            }
            settling = maxDur
        } else {
            settling = 0.0
        }
        return WindowFrameAnim(
            spring: spring,
            start: now,
            from: from,
            velocity: velocity,
            to: to,
            end: now + Double(settling)
        )
    }

    static func retarget(
        _ previous: WindowFrameAnim?,
        _ spring: Spring?,
        _ now: Double,
        _ from: [Float],
        _ to: [Float]
    ) -> WindowFrameAnim {
        let (curFrom, curVel) = previous?.sample(now) ?? (from, [0.0, 0.0, 0.0, 0.0])
        return WindowFrameAnim.new(
            spring,
            now,
            curFrom,
            spring != nil ? curVel : [0.0, 0.0, 0.0, 0.0],
            to
        )
    }

    func sample(_ now: Double) -> ([Float], [Float]) {
        guard let s = spring, now < end else {
            return (to, [0.0, 0.0, 0.0, 0.0])
        }
        let t = Float(max(now - start, 0.0))
        var at: [Float] = [0.0, 0.0, 0.0, 0.0]
        var vel: [Float] = [0.0, 0.0, 0.0, 0.0]
        for i in 0..<4 {
            let (p, v) = s.sample(from[i], velocity[i], to[i], t)
            at[i] = p
            vel[i] = v
        }
        return (at, vel)
    }

    func done(_ now: Double) -> Bool {
        spring == nil || now >= end
    }

    mutating func shift(_ dx: Float, _ dy: Float) {
        from[0] += dx
        from[1] += dy
        to[0] += dx
        to[1] += dy
    }
}

/// Clamps requested content size inside `(min, max)` (`crates/rune/src/window/frame.rs`).
func clampWindowSize(
    _ size: (Float, Float),
    _ minSize: (Float, Float),
    _ maxSize: (Float, Float)?
) -> (Float, Float) {
    let maxW = maxSize?.0 ?? .infinity
    let maxH = maxSize?.1 ?? .infinity
    return (min(max(size.0, minSize.0), maxW), min(max(size.1, minSize.1), maxH))
}

/// Rounds a window frame to whole device pixels (`crates/rune/src/window/frame.rs`).
func snapWindowFrame(_ rect: [Float], _ scale: Float) -> [Float] {
    rect.map { ($0 * scale).rounded() / scale }
}

let HIDDEN_REFRESH: Duration = .milliseconds(500)
let FIRST_FRAME_BUDGET: Duration = .milliseconds(16)
let FIRST_FRAME_HOLD: Duration = .milliseconds(250)
let TIMER_FRAME: Double = 1.0 / 60.0

let HOST_RESUME_STEP: Double = 1.0 / 60.0
let HOST_MAX_GAP: Double = 0.1

/// Result of advancing `HostFrameClock` (`crates/rune/src/frame/clock.rs`).
// PORT NOTE: Prefixed `HostFrameStep` to avoid colliding with `Sources/Rune/frame/clock.swift` owned by a sibling Wave 2 worker.
struct HostFrameStep: Sendable, Equatable {
    var dt: Double
    var capped: Bool
}

/// Monotonic wall-clock delta tracker with pause/resume clamping (`crates/rune/src/frame/clock.rs`).
// PORT NOTE: Prefixed `HostFrameClock` to avoid colliding with `Sources/Rune/frame/clock.swift` owned by a sibling Wave 2 worker.
struct HostFrameClock: Sendable {
    private var last: RuneInstant? = nil

    init() {}

    var isRunning: Bool {
        last != nil
    }

    mutating func pause() {
        last = nil
    }

    mutating func advance(_ now: RuneInstant = .now()) -> HostFrameStep {
        guard let prev = last else {
            last = now
            return HostFrameStep(dt: HOST_RESUME_STEP, capped: false)
        }
        last = now
        let delta = now.durationSince(prev)
        let raw = max(Double(delta.components.seconds) + Double(delta.components.attoseconds) * 1e-18, 0.0)
        if raw > HOST_MAX_GAP {
            return HostFrameStep(dt: HOST_MAX_GAP, capped: true)
        }
        return HostFrameStep(dt: raw, capped: false)
    }
}

/// Encoded frame summary reported to `App.onFrameEncoded` (`crates/rune/src/frame/encoded.rs`).
// PORT NOTE: Prefixed `WindowFrameEncoded` to avoid colliding with `Sources/Rune/frame/encoded.swift` owned by a sibling Wave 2 worker.
public struct WindowFrameEncoded: Sendable, Equatable {
    public var size: (UInt32, UInt32)
    public var scale: Float
    public var dt: Double
    public var instances: Int
    public var layers: Int
    public var animating: Bool

    public init(
        size: (UInt32, UInt32) = (0, 0),
        scale: Float = 1.0,
        dt: Double = 0.0,
        instances: Int = 0,
        layers: Int = 0,
        animating: Bool = false
    ) {
        self.size = size
        self.scale = scale
        self.dt = dt
        self.instances = instances
        self.layers = layers
        self.animating = animating
    }

    public static func == (lhs: WindowFrameEncoded, rhs: WindowFrameEncoded) -> Bool {
        lhs.size.0 == rhs.size.0
            && lhs.size.1 == rhs.size.1
            && lhs.scale == rhs.scale
            && lhs.dt == rhs.dt
            && lhs.instances == rhs.instances
            && lhs.layers == rhs.layers
            && lhs.animating == rhs.animating
    }
}

/// Swapchain presentation outcome reported to `App.onFrameDrawn` (`crates/rune/src/frame/encoded.rs`).
// PORT NOTE: Prefixed `WindowFrameOutcome` to avoid colliding with `Sources/Rune/frame/encoded.swift` owned by a sibling Wave 2 worker.
public enum WindowFrameOutcome: Sendable, Equatable {
    case presented(suboptimal: Bool)
    case skipped
    case missed(String)
}

// PORT NOTE: Prefixed `WindowFrameReports` to avoid colliding with `Sources/Rune/frame/encoded.swift` owned by a sibling Wave 2 worker.
struct WindowFrameReports<S> {
    var encoded: ((inout S, WindowFrameEncoded) -> Void)? = nil
    var drawn: ((inout S, WindowFrameOutcome) -> Void)? = nil
    var drawnRuntime: ((Runtime<S>) -> Void)? = nil
    var devStats: Bool = false

    init() {}
}

/// Custom GPU compositor frame context (`crates/rune/src/compose.rs`).
// PORT NOTE: Prefixed `HostCompositorFrame` to avoid colliding with `Sources/Rune/compose.swift` owned by a sibling Wave 2 worker.
public struct HostCompositorFrame {
    public var size: (UInt32, UInt32)
    public var scale: Float
    public var time: Double
    public var effectSlots: [(UInt32, [Float])]

    public init(
        size: (UInt32, UInt32) = (0, 0),
        scale: Float = 1.0,
        time: Double = 0.0,
        effectSlots: [(UInt32, [Float])] = []
    ) {
        self.size = size
        self.scale = scale
        self.time = time
        self.effectSlots = effectSlots
    }
}

/// Custom GPU compositor hook (`crates/rune/src/compose.rs`).
// PORT NOTE: Prefixed `HostCompositorProtocol` to avoid colliding with `Sources/Rune/compose.swift` owned by a sibling Wave 2 worker.
public protocol HostCompositorProtocol {
    mutating func compose(_ frame: HostCompositorFrame)
}

/// GPU backend selection (`crates/rune/src/gpu/backend.rs`).
// PORT NOTE: Prefixed `HostGpuBackend` to avoid colliding with `Sources/Rune/gpu/backend.swift` owned by a sibling Wave 2 worker.
public enum HostGpuBackend: Sendable, Equatable, Hashable {
    case auto
    case metal
    case wgpu
}

/// Holds reveal of a newly created window until its first frame is drawn (or `FIRST_FRAME_HOLD` expires).
enum FirstFrame: Sendable, Equatable {
    case waiting(since: RuneInstant, holdUntil: RuneInstant)
    case ready

    init(deferred: Bool, now: RuneInstant = .now()) {
        if deferred {
            self = .waiting(since: now, holdUntil: now.adding(FIRST_FRAME_HOLD))
        } else {
            self = .ready
        }
    }

    var isWaiting: Bool {
        if case .waiting = self { return true }
        return false
    }

    func deadline() -> RuneInstant? {
        switch self {
        case .waiting(_, let holdUntil):
            return holdUntil
        case .ready:
            return nil
        }
    }

    mutating func markReady() -> Bool {
        switch self {
        case .waiting:
            self = .ready
            return true
        case .ready:
            return false
        }
    }

    mutating func expireIfPast(_ now: RuneInstant) -> Bool {
        switch self {
        case .waiting(_, let holdUntil) where now >= holdUntil:
            self = .ready
            return true
        default:
            return false
        }
    }
}

/// Polls hidden/occluded windows at `HIDDEN_REFRESH` (`500 ms`) when `poll` is present.
struct HiddenPace: Sendable, Equatable {
    private var nextAt: RuneInstant? = nil

    init() {}

    mutating func reset() {
        nextAt = nil
    }

    mutating func scheduleFrom(_ now: RuneInstant) {
        nextAt = now.adding(HIDDEN_REFRESH)
    }

    mutating func deadline(now: RuneInstant, hasPoll: Bool) -> RuneInstant? {
        guard hasPoll else {
            nextAt = nil
            return nil
        }
        if let existing = nextAt {
            return existing
        }
        let target = now.adding(HIDDEN_REFRESH)
        nextAt = target
        return target
    }

    mutating func takeDue(now: RuneInstant, hasPoll: Bool) -> Bool {
        guard hasPoll else {
            nextAt = nil
            return false
        }
        guard let target = nextAt else {
            nextAt = now.adding(HIDDEN_REFRESH)
            return true
        }
        if now >= target {
            nextAt = now.adding(HIDDEN_REFRESH)
            return true
        }
        return false
    }
}

/// Computes `dt` for a frame, consuming a timer-triggered `TIMER_FRAME` (`1/60s`) when armed.
func drainFrame<S>(
    clock: inout HostFrameClock,
    rt: Runtime<S>,
    now: RuneInstant = .now()
) -> Double {
    if rt.hostCancelTimerFrame() {
        clock.pause()
        return TIMER_FRAME
    }
    return clock.advance(now).dt
}

/// Converts `rt.hostWakeDeadline()` (on `rt.clock`) to a wall-clock `RuneInstant`.
func wallWakeDeadline<S>(
    rt: Runtime<S>,
    now: RuneInstant = .now()
) -> RuneInstant? {
    guard let wakeClock = rt.hostWakeDeadline() else {
        return nil
    }
    let remaining = max(wakeClock - rt.clock, 0.0)
    return now.adding(.nanoseconds(Int64((remaining * 1_000_000_000.0).rounded())))
}

/// Earliest timer deadline for a window/overlay (explicit `wakeAfter` timers or hidden poll refresh).
func timerDeadline<S>(
    rt: Runtime<S>,
    now: RuneInstant,
    covered: Bool,
    hiddenPace: inout HiddenPace
) -> RuneInstant? {
    var earliest = wallWakeDeadline(rt: rt, now: now)
    if covered {
        if let hiddenNext = hiddenPace.deadline(now: now, hasPoll: rt.poll != nil) {
            if let cur = earliest {
                earliest = min(cur, hiddenNext)
            } else {
                earliest = hiddenNext
            }
        }
    } else {
        hiddenPace.reset()
    }
    return earliest
}

/// Checks whether a resting timer wake has matured at `now` and arms a `TIMER_FRAME` step if so.
func timerWantsFrame<S>(
    rt: Runtime<S>,
    now: RuneInstant = .now()
) -> Bool {
    guard let wakeAt = wallWakeDeadline(rt: rt, now: now) else {
        return false
    }
    if now >= wakeAt {
        rt.hostArmTimerFrame()
        return true
    }
    return false
}
