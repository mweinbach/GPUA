// Ported from: crates/rune-motion/src/choreo.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Where a stagger ripples from (Motion's `stagger(gap, { from })`).
public enum StaggerFrom: Sendable, Equatable, Hashable {
    case first
    case last
    case center
    case index(Int)
}

/// Delays for a ripple across `count` items.
public struct Stagger: Sendable, Equatable {
    public var gap: Float
    public var from: StaggerFrom
    public var start: Float
    /// Optional easing of delays across the ripple (Motion's `ease` option).
    public var ease: Easing?

    public init(_ gap: Float) {
        self.gap = gap
        self.from = .first
        self.start = 0.0
        self.ease = nil
    }

    public static func new(_ gap: Float) -> Stagger {
        Stagger(gap)
    }

    public func from(_ from: StaggerFrom) -> Stagger {
        var copy = self
        copy.from = from
        return copy
    }

    public func start(_ seconds: Float) -> Stagger {
        var copy = self
        copy.start = seconds
        return copy
    }

    public func ease(_ easing: Easing) -> Stagger {
        var copy = self
        copy.ease = easing
        return copy
    }

    /// The delay of item `index` out of `count`.
    public func delay(_ index: Int, _ count: Int) -> Float {
        let c = max(count, 1)
        let origin: Float
        switch from {
        case .first:
            origin = 0.0
        case .last:
            origin = Float(c - 1)
        case .center:
            origin = Float(c - 1) / 2.0
        case .index(let i):
            origin = Float(min(i, c - 1))
        }
        let distance = abs(Float(index) - origin)
        var maxDist: Float = 0.0
        for i in 0..<c {
            maxDist = max(maxDist, abs(Float(i) - origin))
        }
        let d: Float
        if let e = ease, maxDist > 0.0 {
            d = e.eval(distance / maxDist) * maxDist
        } else {
            d = distance
        }
        return start + d * gap
    }
}

/// Shorthand for ``Stagger/delay(_:_:)``.
public func stagger(_ index: Int, _ count: Int, _ gap: Float, _ from: StaggerFrom) -> Float {
    Stagger(gap).from(from).delay(index, count)
}

/// A handle to a step of a ``Choreography``.
public struct StepId: Sendable, Equatable, Hashable {
    let rawValue: UInt32

    init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// What a cue waits for on another step.
public enum When: Sendable, Equatable, Hashable {
    /// The step started.
    case started
    /// The step's animations logically completed (springs: their duration; tweens: their end).
    case arrived
    /// Every track the step animated is physically at rest (or was taken over).
    case settled
}

/// When a step may start.
public struct Cue: Sendable, Equatable {
    fileprivate var afterStep: StepId?
    fileprivate var afterWhen: When?
    fileprivate var delay: Float
    fileprivate var notBeforeTime: Float

    /// As soon as the choreography starts.
    public static func now() -> Cue {
        Cue(afterStep: nil, afterWhen: nil, delay: 0.0, notBeforeTime: 0.0)
    }

    /// `t` seconds after the choreography starts.
    public static func at(_ t: Float) -> Cue {
        Cue(afterStep: nil, afterWhen: nil, delay: t, notBeforeTime: 0.0)
    }

    public static func started(_ step: StepId) -> Cue {
        Cue(afterStep: step, afterWhen: .started, delay: 0.0, notBeforeTime: 0.0)
    }

    public static func arrived(_ step: StepId) -> Cue {
        Cue(afterStep: step, afterWhen: .arrived, delay: 0.0, notBeforeTime: 0.0)
    }

    public static func settled(_ step: StepId) -> Cue {
        Cue(afterStep: step, afterWhen: .settled, delay: 0.0, notBeforeTime: 0.0)
    }

    /// Wait a further `seconds` after the cue.
    public func after(_ seconds: Float) -> Cue {
        var copy = self
        copy.delay += seconds
        return copy
    }

    /// Never earlier than `t` seconds after the choreography starts (a causal guard).
    public func notBefore(_ t: Float) -> Cue {
        var copy = self
        copy.notBeforeTime = max(copy.notBeforeTime, t)
        return copy
    }
}

private struct Op: Sendable {
    var node: NodeId
    var prop: PropId
    var `class`: PropClass
    var first: UInt32
    var lanes: UInt8
    var anim: Anim
}

/// A list of property animations, recorded typed and applied untyped.
public struct Ops: Sendable {
    private var ops: [Op] = []
    private var targets: [Float] = []

    public init() {}

    /// Animate `prop` of `node` to `target`. (If the property has never been set, it is set:
    /// set starting values with `store.set` first.)
    public mutating func animate<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ target: T,
        _ anim: some AnimExt
    ) {
        let l = lanes(target)
        let first = UInt32(targets.count)
        for i in 0..<T.lanes {
            targets.append(l[i])
        }
        ops.append(
            Op(
                node: node,
                prop: prop.id,
                class: prop.class,
                first: first,
                lanes: UInt8(T.lanes),
                anim: anim.intoAnim()
            )
        )
    }

    fileprivate func apply(
        _ store: AnimationStore,
        _ delay: Float,
        _ setImmediate: Bool,
        _ out: inout [(TrackId, UInt32)]
    ) {
        targets.withUnsafeBufferPointer { targetBuf in
            for op in ops {
                let start = Int(op.first)
                let end = start + Int(op.lanes)
                let slice = UnsafeBufferPointer(rebasing: targetBuf[start..<end])
                let t = Int(store.ensure(op.node, op.prop, op.class, slice))
                if setImmediate {
                    store.setRaw(UInt32(t), slice)
                } else {
                    // `delay` is store time; the op's node may run on a scaled clock.
                    let k = store.nodeTimeScale(op.node)
                    let scaledDelay = k > 0.0 ? (delay * k) : delay
                    var a = op.anim
                    a.delay += scaledDelay
                    store.animateRaw(t, slice, a, nil)
                }
                let id = store.idOf(t)
                out.append((id, store.epoch(id) ?? 0))
            }
        }
    }
}

private enum StepState: Sendable, Equatable {
    case waiting
    /// Started (possibly with a scheduled delay) at absolute `start`; its tracks are `tracks`.
    case running(start: Double, first: UInt32, count: UInt32)
}

private struct Step: Sendable {
    var cue: Cue
    var ops: Ops
    var state: StepState
}

/// A set of steps that start on cues. Call ``tick(_:)`` each frame after setting the
/// store's time and before `store.tick()`.
public struct Choreography: Sendable {
    private var steps: [Step] = []
    private var tracks: [(TrackId, UInt32)] = []
    private var t0: Double? = nil

    public init() {}

    public static func new() -> Choreography {
        Choreography()
    }

    /// Adds a step: `c.step(Cue.arrived(a).after(0.05)) { s in s.animate(id, prop.opacity, 1.0, motion.settle) }`.
    @discardableResult
    public mutating func step(_ cue: Cue, _ build: (inout Ops) -> Void) -> StepId {
        var ops = Ops()
        build(&ops)
        steps.append(Step(cue: cue, ops: ops, state: .waiting))
        return StepId(UInt32(steps.count - 1))
    }

    /// A ripple: one step per item, each `stagger.delay(i, n)` after `cue`. Returns the steps.
    @discardableResult
    public mutating func stagger<C: Collection>(
        _ cue: Cue,
        _ stagger: Stagger,
        _ items: C,
        _ each: (inout Ops, C.Element) -> Void
    ) -> [StepId] {
        let n = items.count
        var ids: [StepId] = []
        ids.reserveCapacity(n)
        for (i, item) in items.enumerated() {
            let c = cue.after(stagger.delay(i, n))
            ids.append(step(c) { ops in each(&ops, item) })
        }
        return ids
    }

    /// When a step started (or will start, if scheduled with a delay).
    public func startTime(_ step: StepId) -> Double? {
        let idx = Int(step.rawValue)
        guard idx >= 0 && idx < steps.count else { return nil }
        switch steps[idx].state {
        case .running(let start, _, _):
            return start
        case .waiting:
            return nil
        }
    }

    /// Every step started and every track it animated has settled.
    public func isDone(_ store: AnimationStore) -> Bool {
        for s in steps {
            if case .waiting = s.state {
                return false
            }
        }
        return allSettled(store, tracks[...])
    }

    /// Starts every step whose cue is due or now known. Cheap when nothing is waiting.
    public mutating func tick(_ store: AnimationStore) {
        let now = store.now()
        let startOrigin: Double
        if let existing = t0 {
            startOrigin = existing
        } else {
            t0 = now
            startOrigin = now
        }
        while true {
            var progressed = false
            for k in 0..<steps.count {
                if steps[k].state != .waiting {
                    continue
                }
                let cue = steps[k].cue
                let base: Double?
                if let s = cue.afterStep, let w = cue.afterWhen {
                    base = cueTime(store, s, w, now)
                } else {
                    base = startOrigin
                }
                guard let resolvedBase = base else { continue }
                let at = max(resolvedBase + Double(cue.delay), startOrigin + Double(cue.notBeforeTime))
                let delay = Float(max(at - now, 0.0))
                let first = UInt32(tracks.count)
                steps[k].ops.apply(store, delay, false, &tracks)
                let count = UInt32(tracks.count) - first
                steps[k].state = .running(start: now + Double(delay), first: first, count: count)
                progressed = true
            }
            if !progressed {
                break
            }
        }
    }

    private func cueTime(_ store: AnimationStore, _ s: StepId, _ when: When, _ now: Double) -> Double? {
        let idx = Int(s.rawValue)
        guard idx >= 0 && idx < steps.count else { return nil }
        guard case .running(let start, let first, let count) = steps[idx].state else {
            return nil
        }
        let slice = tracks[Int(first)..<Int(first + count)]
        switch when {
        case .started:
            return start
        case .arrived:
            // A frozen step hasn't a known arrival yet: keep waiting.
            let t = arrival(store, slice, start)
            return t.isFinite ? t : nil
        case .settled:
            return allSettled(store, slice) ? now : nil
        }
    }
}

/// Every track is at rest, or was taken over (its epoch moved on).
private func allSettled(_ store: AnimationStore, _ tracks: ArraySlice<(TrackId, UInt32)>) -> Bool {
    for (t, epoch) in tracks {
        if !store.isSettled(t) && store.epoch(t) == epoch {
            return false
        }
    }
    return true
}

/// The latest logical end among `tracks`, and never before `from`.
private func arrival(
    _ store: AnimationStore,
    _ tracks: ArraySlice<(TrackId, UInt32)>,
    _ from: Double
) -> Double {
    var latest = from
    for (t, _) in tracks {
        if let end = store.logicalEnd(t) {
            latest = max(latest, end)
        }
    }
    return latest
}

/// SwiftUI `PhaseAnimator`: cycles through phases, animating each from wherever the last one is,
/// advancing when the current phase arrives (or settles). The first phase is the resting pose and
/// is shown without animation. Under Reduce Motion it holds that pose.
public struct PhaseAnimator: Sendable {
    private var phases: [Ops] = []
    private var currentIdx: Int = 0
    private var advance: When = .arrived
    private var repeatLoop: Bool = true
    private var holdTime: Float = 0.0
    private var tracks: [(TrackId, UInt32)] = []
    private var started: Bool = false
    private var nextAt: Double? = nil

    public init() {}

    public static func new() -> PhaseAnimator {
        PhaseAnimator()
    }

    public func phase(_ build: (inout Ops) -> Void) -> PhaseAnimator {
        var copy = self
        var ops = Ops()
        build(&ops)
        copy.phases.append(ops)
        return copy
    }

    /// Advance on `When.arrived` (default) or `When.settled`.
    public func advanceOn(_ when: When) -> PhaseAnimator {
        var copy = self
        copy.advance = when
        return copy
    }

    /// Pause on each phase for `seconds` after it arrives.
    public func hold(_ seconds: Float) -> PhaseAnimator {
        var copy = self
        copy.holdTime = seconds
        return copy
    }

    /// Stop after the last phase instead of cycling back to the first.
    public func once() -> PhaseAnimator {
        var copy = self
        copy.repeatLoop = false
        return copy
    }

    public func current() -> Int {
        currentIdx
    }

    public mutating func tick(_ store: AnimationStore) {
        if phases.isEmpty {
            return
        }
        let now = store.now()
        if !started {
            started = true
            tracks.removeAll(keepingCapacity: true)
            phases[0].apply(store, 0.0, true, &tracks)
            nextAt = now
        }
        if store.reducedMotion() {
            return
        }
        guard var at = nextAt else {
            // Waiting for a settle.
            if allSettled(store, tracks[...]) {
                nextAt = now + Double(holdTime)
            }
            return
        }
        if at == .infinity {
            // The phase was frozen when it started (`setNodeTimeScale(_, 0.0)`): ask again.
            at = arrival(store, tracks[...], now) + Double(holdTime)
            nextAt = at
        }
        if now < at {
            return
        }
        let next = currentIdx + 1
        if next >= phases.count && !repeatLoop {
            return
        }
        currentIdx = next % phases.count
        tracks.removeAll(keepingCapacity: true)
        phases[currentIdx].apply(store, 0.0, false, &tracks)
        switch advance {
        case .arrived, .started:
            nextAt = arrival(store, tracks[...], now) + Double(holdTime)
        case .settled:
            nextAt = nil
        }
    }
}
