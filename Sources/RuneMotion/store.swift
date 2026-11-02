// Ported from: crates/rune-motion/src/store.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

let noneIndex: UInt32 = .max
/// Most additive layers a lane keeps before it collapses them into one merged segment.
private let maxAdditive: Int = 8

/// A generational handle to one track.
public struct TrackId: Sendable, Equatable, Hashable {
    var index: UInt32
    var generation: UInt32

    init(index: UInt32, generation: UInt32) {
        self.index = index
        self.generation = generation
    }

    @inline(__always)
    func indexInt() -> Int {
        Int(index)
    }
}

/// What happened during a tick (or since the last one).
public enum MotionEvent: Sendable, Equatable {
    /// The track reached `(target, 0)` and went dormant.
    case settled(track: TrackId, node: NodeId, prop: PropId)
    /// An animation started with `.completion(token)` finished (`finished`), or was replaced by a
    /// newer animation before it did (`!finished`).
    case completed(token: UInt64, node: NodeId, prop: PropId, finished: Bool)
}

/// How a released gesture continues.
public enum Release<T: Animatable>: Sendable {
    /// Spring to a target, starting from the release velocity.
    case spring(target: T, spring: Spring)
    /// Coast with exponential decay to the projected rest point.
    case decay(Decay)
    /// Coast, but if the projection leaves `[min, max]`, spring onto the bound with the velocity
    /// the value has when it reaches it (scroll views). If it is already out of bounds
    /// (rubber-banded), spring straight back.
    case decayClamped(decay: Decay, min: T, max: T, spring: Spring)
}

struct Extra: Sendable {
    var layer: Layer
    var next: UInt32
}

struct Pending: Sendable {
    var at: Double
    var target: Float
    /// NaN: inherit.
    var velocity: Float
    var curve: Curve
    var blend: Blend
    var next: UInt32
}

struct Meta: Sendable {
    var node: NodeId
    var prop: PropId
    var `class`: PropClass
    var generation: UInt32
    var alive: Bool
    var epoch: UInt32
    var token: UInt64
    var logicalAt: Double
    var nodeNext: UInt32

    init(
        node: NodeId,
        prop: PropId,
        class propClass: PropClass,
        generation: UInt32,
        nodeNext: UInt32
    ) {
        self.node = node
        self.prop = prop
        self.class = propClass
        self.generation = generation
        self.alive = true
        self.epoch = 0
        self.token = 0
        self.logicalAt = -.infinity
        self.nodeNext = nodeNext
    }
}

/// A fast, unkeyed hasher for small fixed-size keys (ids, glyph keys) that no input chooses.
public struct Fx: Sendable {
    private var state: UInt64 = 0

    public init() {}

    @inline(__always)
    private mutating func add(_ i: UInt64) {
        let rotated = (state << 5) | (state >> 59)
        state = (rotated ^ i) &* 0x517c_c1b7_2722_0a95
    }

    public mutating func write(_ bytes: [UInt8]) {
        for b in bytes {
            add(UInt64(b))
        }
    }

    public mutating func write(_ bytes: UnsafeRawBufferPointer) {
        for b in bytes {
            add(UInt64(b))
        }
    }

    public mutating func write(_ string: String) {
        for b in string.utf8 {
            add(UInt64(b))
        }
    }

    public mutating func writeU8(_ i: UInt8) {
        add(UInt64(i))
    }

    public mutating func writeU16(_ i: UInt16) {
        add(UInt64(i))
    }

    public mutating func writeU32(_ i: UInt32) {
        add(UInt64(i))
    }

    public mutating func writeU64(_ i: UInt64) {
        add(i)
    }

    public mutating func writeUsize(_ i: Int) {
        add(UInt64(bitPattern: Int64(i)))
    }

    public func finish() -> UInt64 {
        state
    }
}

struct NodePropKey: Hashable, Sendable {
    let node: UInt64
    let prop: UInt16

    init(_ node: UInt64, _ prop: UInt16) {
        self.node = node
        self.prop = prop
    }
}

/// A clock some nodes' tracks run on instead of the store's: it advances by `dt × scale` each
/// time the store's time moves. Nodes at the same scale share one; `nodes == 0` marks it free.
struct SubClock: Sendable {
    var time: Double
    var scale: Float
    var nodes: UInt32
}

/// Optional diagnostics for inherited spatial spring retargets (points per second).
public struct RetargetAudit: Sendable, Equatable {
    public var lanes: UInt64
    public var maxVelocityError: Float

    public init(lanes: UInt64 = 0, maxVelocityError: Float = 0.0) {
        self.lanes = lanes
        self.maxVelocityError = maxVelocityError
    }
}

/// All animated properties, sampled together at one presentation time.
// PORT NOTE: `AnimationStore` is a stateful engine object owned and mutated on a single render
// thread (matching Rust's `&mut AnimationStore`), so it is a `final class` marked `@unchecked Sendable`.
public final class AnimationStore: @unchecked Sendable {
    var _now: Double = 0.0
    var _pixelScale: Float = 2.0
    var _reducedMotion: Bool = false

    var lTarget: [Float] = []
    var lValue: [Float] = []
    var lVel: [Float] = []
    var lLayer: [Layer] = []
    var lMore: [UInt32] = []
    var lPending: [UInt32] = []
    var lCurve: [Curve] = []
    var laneFree: [[UInt32]] = Array(repeating: [], count: maxLanes + 1)

    var tLane0: [UInt32] = []
    var tN: [UInt8] = []
    var tSettleAt: [Double] = []
    var tNextDue: [Double] = []
    var tSlot: [UInt32] = []
    var tMeta: [Meta] = []
    /// The track's clock: 0 is the store's own, otherwise an index into `clocks`.
    var tClock: [UInt32] = []
    /// On a stopped clock and already sampled where it holds, so `tick` skips it.
    var tHeld: [Bool] = []
    var trackFree: [UInt32] = []

    /// Index 0 stands for the store's own clock and is never read.
    var clocks: [SubClock] = []
    var clockFree: [UInt32] = []
    var nodeClock: [UInt64: UInt32] = [:]

    var activeIndices: [UInt32] = []
    /// With the generation they had, so a track freed (or its slot reused) since drops out
    /// where these are read, and freeing a track never scans them.
    var touchedList: [TrackId] = []
    var setTouchedList: [TrackId] = []

    var extra: [Extra] = []
    var extraFree: UInt32 = noneIndex
    var pending: [Pending] = []
    var pendingFree: UInt32 = noneIndex

    var index: [NodePropKey: UInt32] = [:]
    var nodeHead: [UInt64: UInt32] = [:]

    var _events: [MotionEvent] = []
    var eventsSeen: Int = 0
    var retargetAudit: RetargetAudit? = nil

    public init() {}

    public static func new() -> AnimationStore {
        AnimationStore()
    }

    /// Pre-sizes for `tracks` tracks of about `lanesPerTrack` lanes, so even the first frames
    /// don't allocate.
    public static func withCapacity(_ tracks: Int, _ lanesPerTrack: Int) -> AnimationStore {
        let s = AnimationStore()
        let totalLanes = tracks * lanesPerTrack
        s.lTarget.reserveCapacity(totalLanes)
        s.lValue.reserveCapacity(totalLanes)
        s.lVel.reserveCapacity(totalLanes)
        s.lLayer.reserveCapacity(totalLanes)
        s.lMore.reserveCapacity(totalLanes)
        s.lPending.reserveCapacity(totalLanes)
        s.lCurve.reserveCapacity(totalLanes)
        s.tLane0.reserveCapacity(tracks)
        s.tN.reserveCapacity(tracks)
        s.tSettleAt.reserveCapacity(tracks)
        s.tNextDue.reserveCapacity(tracks)
        s.tSlot.reserveCapacity(tracks)
        s.tMeta.reserveCapacity(tracks)
        s.tClock.reserveCapacity(tracks)
        s.tHeld.reserveCapacity(tracks)
        s.activeIndices.reserveCapacity(tracks)
        s.touchedList.reserveCapacity(tracks)
        s._events.reserveCapacity(tracks * 2)
        s.index.reserveCapacity(tracks)
        s.nodeHead.reserveCapacity(tracks)
        return s
    }

    // ------------------------------------------------------------------------------------------
    // Time and policy

    /// The presentation time animations are applied at and sampled for (seconds, from a ``Clock``).
    public func now() -> Double {
        _now
    }

    /// Opt-in trace diagnostics; disabled in normal rendering. Measures inherited spatial
    /// spring velocity at actual retarget boundaries, excluding deliberate instant cuts.
    public func auditRetargets(_ enabled: Bool) {
        retargetAudit = enabled ? RetargetAudit() : nil
    }

    public func takeRetargetAudit() -> RetargetAudit {
        guard let current = retargetAudit else {
            return RetargetAudit()
        }
        retargetAudit = RetargetAudit()
        return current
    }

    /// Sets the frame's target presentation time. Apply this frame's commits after this, then `tick`.
    public func setTime(_ t: Double) {
        let dt = t - _now
        _now = t
        if clocks.count > 1 {
            for idx in 1..<clocks.count {
                if clocks[idx].nodes > 0 && clocks[idx].scale != 0.0 {
                    clocks[idx].time += dt * Double(clocks[idx].scale)
                }
            }
        }
    }

    /// `setTime(t)` then `tick()`.
    public func tickAt(_ t: Double) {
        setTime(t)
        tick()
    }

    // ------------------------------------------------------------------------------------------
    // Per-node time

    /// Runs every track of `node`, and any it creates later, at `scale` times the store's speed:
    /// each `setTime` advances them by `dt × scale`. At 0 they hold exactly where they are,
    /// pending delays included, and ``running()`` ignores them. Changing the scale
    /// keeps every running animation at its exact place. 1 is the store's own clock.
    public func setNodeTimeScale(_ node: NodeId, _ scale: Float) {
        let resolvedScale: Float = scale.isFinite ? max(scale, 0.0) : 1.0
        let old = nodeClock[node.rawValue] ?? 0
        if clockScale(old) == resolvedScale {
            return
        }
        let newClock: UInt32 = resolvedScale == 1.0 ? 0 : clockAt(resolvedScale)
        let delta = clockTime(newClock) - clockTime(old)
        if newClock == 0 {
            nodeClock.removeValue(forKey: node.rawValue)
        } else {
            clocks[Int(newClock)].nodes += 1
            nodeClock[node.rawValue] = newClock
        }
        var t = nodeHead[node.rawValue] ?? noneIndex
        while t != noneIndex {
            let ti = Int(t)
            rebase(ti, delta)
            tClock[ti] = newClock
            tHeld[ti] = false
            t = tMeta[ti].nodeNext
        }
        releaseClock(old)
    }

    /// The scale `node`'s tracks run at relative to the store's (1 unless set).
    public func nodeTimeScale(_ node: NodeId) -> Float {
        if nodeClock.isEmpty {
            return 1.0
        }
        return clockScale(nodeClock[node.rawValue] ?? 0)
    }

    /// The time `node`'s tracks are sampled at: `now()` unless its time is scaled.
    public func nodeTime(_ node: NodeId) -> Double {
        if nodeClock.isEmpty {
            return _now
        }
        return clockTime(nodeClock[node.rawValue] ?? 0)
    }

    /// The live clock running at `scale`, or a new one reading `now`.
    private func clockAt(_ scale: Float) -> UInt32 {
        if clocks.count > 1 {
            for idx in 1..<clocks.count {
                if clocks[idx].nodes > 0 && clocks[idx].scale == scale {
                    return UInt32(idx)
                }
            }
        }
        if clocks.isEmpty {
            clocks.append(SubClock(time: 0.0, scale: 1.0, nodes: 0))
        }
        let clock = SubClock(time: _now, scale: scale, nodes: 0)
        if let freeIdx = clockFree.popLast() {
            clocks[Int(freeIdx)] = clock
            return freeIdx
        } else {
            clocks.append(clock)
            return UInt32(clocks.count - 1)
        }
    }

    func releaseClock(_ c: UInt32) {
        if c == 0 {
            return
        }
        let idx = Int(c)
        clocks[idx].nodes -= 1
        if clocks[idx].nodes == 0 {
            clockFree.append(c)
        }
    }

    func clockScale(_ c: UInt32) -> Float {
        c == 0 ? 1.0 : clocks[Int(c)].scale
    }

    func clockTime(_ c: UInt32) -> Double {
        c == 0 ? _now : clocks[Int(c)].time
    }

    @inline(__always)
    func timeOf(_ t: Int) -> Double {
        clockTime(tClock[t])
    }

    @inline(__always)
    func frozen(_ t: Int) -> Bool {
        let c = tClock[t]
        return c != 0 && clocks[Int(c)].scale == 0.0
    }

    /// Shifts every absolute time of track `t` by `delta`.
    private func rebase(_ t: Int, _ delta: Double) {
        if delta == 0.0 {
            return
        }
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        for l in l0..<(l0 + n) {
            lLayer[l].t0 += delta
            lLayer[l].end += delta
            var m = lMore[l]
            while m != noneIndex {
                let mi = Int(m)
                extra[mi].layer.t0 += delta
                extra[mi].layer.end += delta
                m = extra[mi].next
            }
            var p = lPending[l]
            while p != noneIndex {
                let pi = Int(p)
                pending[pi].at += delta
                p = pending[pi].next
            }
        }
        tSettleAt[t] += delta
        tNextDue[t] += delta
        tMeta[t].logicalAt += delta
    }

    /// Device pixels per point; sets settle thresholds below the 1/64 px snap quantum.
    public func setPixelScale(_ scale: Float) {
        _pixelScale = max(scale, 1.0)
    }

    public func pixelScale() -> Float {
        _pixelScale
    }

    /// The OS Reduce Motion setting. Applied per property class to every new animation.
    public func setReducedMotion(_ on: Bool) {
        _reducedMotion = on
    }

    public func reducedMotion() -> Bool {
        _reducedMotion
    }

    // ------------------------------------------------------------------------------------------
    // The frame

    /// Samples every active track at `now()`, applies due delayed animations, settles finished
    /// tracks. Allocation-free once buffers have grown to the working-set size.
    public func tick() {
        if eventsSeen > 0 {
            if eventsSeen == _events.count {
                _events.removeAll(keepingCapacity: true)
            } else {
                _events.removeSubrange(0..<eventsSeen)
            }
        }
        touchedList.removeAll(keepingCapacity: true)
        for id in setTouchedList {
            let ti = Int(id.index)
            if tMeta[ti].alive && tMeta[ti].generation == id.generation {
                touchedList.append(id)
            }
        }
        setTouchedList.removeAll(keepingCapacity: true)
        let clocked = !nodeClock.isEmpty
        var i = 0
        while i < activeIndices.count {
            let t = Int(activeIndices[i])
            let now = clocked ? timeOf(t) : _now
            // Nothing moves on a stopped clock, or on a track that only waits for a delayed
            // start: once sampled where it holds, it isn't touched again until it moves.
            let held = (clocked && frozen(t)) || (now >= tSettleAt[t] && tNextDue[t] > now)
            if held && tHeld[t] {
                i += 1
                continue
            }
            tHeld[t] = held
            touchedList.append(TrackId(index: UInt32(t), generation: tMeta[t].generation))
            if tNextDue[t] <= now {
                applyDue(t, now)
            }
            let l0 = Int(tLane0[t])
            let n = Int(tN[t])
            var stacked = false
            for k in 0..<n {
                let l = l0 + k
                let (o, v) = lLayer[l].sample(now)
                lValue[l] = lTarget[l] + o
                lVel[l] = v
                if lMore[l] != noneIndex {
                    stacked = true
                }
            }
            if stacked {
                for l in l0..<(l0 + n) {
                    if lMore[l] != noneIndex {
                        let (o2, v2) = sampleExtra(l, now)
                        lValue[l] += o2
                        lVel[l] += v2
                    }
                }
            }
            if now >= tSettleAt[t] && tNextDue[t] == .infinity {
                settle(t)
                deactivate(t, i)
                continue
            }
            i += 1
        }
        eventsSeen = _events.count
    }

    /// Events since the previous tick (settles, completions).
    public func events() -> [MotionEvent] {
        _events
    }

    /// The values presented at the last tick for a track, as raw lanes.
    public func valuesOf(_ id: TrackId) -> [Float]? {
        guard contains(id) else { return nil }
        let t = Int(id.index)
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        return Array(lValue[l0..<(l0 + n)])
    }

    /// Zero-allocation read of presented lanes for internal callers (`Scene`).
    @inline(__always)
    func withValuesOf<R>(_ id: TrackId, _ body: (UnsafeBufferPointer<Float>) -> R) -> R? {
        guard contains(id) else { return nil }
        let t = Int(id.index)
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        return lValue.withUnsafeBufferPointer { buf in
            body(UnsafeBufferPointer(rebasing: buf[l0..<(l0 + n)]))
        }
    }

    /// Where each lane of a track comes to rest (its latest target, delayed ones included),
    /// into `out`. False when the track is gone.
    func targetsOf(_ id: TrackId, _ out: inout LaneStorage) -> Bool {
        guard contains(id) else {
            return false
        }
        let t = Int(id.index)
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        for k in 0..<n {
            out[k] = finalTarget(l0 + k)
        }
        return true
    }

    /// The velocities at the last tick for a track, as raw lanes.
    public func velocitiesOf(_ id: TrackId) -> [Float]? {
        guard contains(id) else { return nil }
        let t = Int(id.index)
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        return Array(lVel[l0..<(l0 + n)])
    }

    /// Is the track currently animating?
    public func isActive(_ id: TrackId) -> Bool {
        contains(id) && tSlot[Int(id.index)] != noneIndex
    }

    /// Exact `(value, velocity)` lanes of a track at `now()`, into `x` and `v`.
    func sampleExact(_ id: TrackId, _ x: inout LaneStorage, _ v: inout LaneStorage) -> Bool {
        guard contains(id) else {
            return false
        }
        let t = Int(id.index)
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        let now = timeOf(t)
        for i in 0..<n {
            let (a, b) = sampleLane(l0 + i, now)
            x[i] = a
            v[i] = b
        }
        return true
    }

    public func activeLen() -> Int {
        activeIndices.count
    }

    /// Some track is animating on a clock that moves. Tracks held by a stopped clock don't count.
    public func running() -> Bool {
        if nodeClock.isEmpty {
            return !activeIndices.isEmpty
        }
        return activeIndices.contains { !frozen(Int($0)) }
    }

    public func trackLen() -> Int {
        var count = 0
        for m in tMeta where m.alive {
            count += 1
        }
        return count
    }

    // ------------------------------------------------------------------------------------------
    // Untyped core (used by the scene, keyframes and choreography)

    func ensure(
        _ node: NodeId,
        _ prop: PropId,
        _ propClass: PropClass,
        _ initialValues: UnsafeBufferPointer<Float>
    ) -> UInt32 {
        let key = NodePropKey(node.rawValue, prop.rawValue)
        if let t = index[key] {
            checkLanes(Int(t), initialValues.count)
            return t
        }
        let n = initialValues.count
        precondition(n > 0 && n <= maxLanes)
        let l0: UInt32
        if let reused = laneFree[n].popLast() {
            l0 = reused
        } else {
            let start = lTarget.count
            for _ in 0..<n {
                lTarget.append(0.0)
                lValue.append(0.0)
                lVel.append(0.0)
                lLayer.append(.rest)
                lMore.append(noneIndex)
                lPending.append(noneIndex)
                lCurve.append(.instant)
            }
            l0 = UInt32(start)
        }
        for i in 0..<n {
            let l = Int(l0) + i
            let x = initialValues[i]
            lTarget[l] = x
            lValue[l] = x
            lVel[l] = 0.0
            lLayer[l] = .rest
            lMore[l] = noneIndex
            lPending[l] = noneIndex
            lCurve[l] = .instant
        }
        let head = nodeHead[node.rawValue] ?? noneIndex
        let clock: UInt32 = nodeClock.isEmpty ? 0 : (nodeClock[node.rawValue] ?? 0)
        let t: UInt32
        if let freeTrack = trackFree.popLast() {
            let ti = Int(freeTrack)
            let gen = tMeta[ti].generation &+ 1
            tMeta[ti] = Meta(node: node, prop: prop, class: propClass, generation: gen, nodeNext: head)
            tLane0[ti] = l0
            tN[ti] = UInt8(n)
            tSettleAt[ti] = -.infinity
            tNextDue[ti] = .infinity
            tSlot[ti] = noneIndex
            tClock[ti] = clock
            tHeld[ti] = false
            t = freeTrack
        } else {
            tMeta.append(Meta(node: node, prop: prop, class: propClass, generation: 0, nodeNext: head))
            tLane0.append(l0)
            tN.append(UInt8(n))
            tSettleAt.append(-.infinity)
            tNextDue.append(.infinity)
            tSlot.append(noneIndex)
            tClock.append(clock)
            tHeld.append(false)
            t = UInt32(tMeta.count - 1)
        }
        index[key] = t
        nodeHead[node.rawValue] = t
        return t
    }

    @inline(__always)
    func idOf(_ t: Int) -> TrackId {
        TrackId(index: UInt32(t), generation: tMeta[t].generation)
    }

    func checkLanes(_ t: Int, _ n: Int) {
        precondition(
            Int(tN[t]) == n,
            "property \(tMeta[t].prop) of \(tMeta[t].node) was created with \(tN[t]) lanes, used with \(n)"
        )
    }

    func laneTargets4(_ t: Int) -> (Float, Float, Float, Float) {
        let l0 = Int(tLane0[t])
        return (
            finalTarget(l0),
            finalTarget(l0 + 1),
            finalTarget(l0 + 2),
            finalTarget(l0 + 3)
        )
    }

    func setRaw(_ t: UInt32, _ values: UnsafeBufferPointer<Float>) {
        let ti = Int(t)
        let l0 = Int(tLane0[ti])
        for i in 0..<values.count {
            let l = l0 + i
            let x = values[i]
            cancelPending(l)
            freeExtra(l)
            lLayer[l] = .rest
            lTarget[l] = x
            lValue[l] = x
            lVel[l] = 0.0
            lCurve[l] = .instant
        }
        tNextDue[ti] = .infinity
        tSettleAt[ti] = -.infinity
        takeToken(ti, false)
        tMeta[ti].epoch &+= 1
        if tSlot[ti] != noneIndex {
            let slot = Int(tSlot[ti])
            deactivate(ti, slot)
        }
        setTouchedList.append(TrackId(index: t, generation: tMeta[ti].generation))
    }

    /// Animates lanes of track `t` toward `targets`. `laneVel` overrides per-lane start velocity.
    /// False when no lane's target changed, so nothing moves.
    @discardableResult
    func animateRaw(
        _ t: Int,
        _ targets: UnsafeBufferPointer<Float>,
        _ animIn: Anim,
        _ laneVel: UnsafeBufferPointer<Float>?
    ) -> Bool {
        let now = timeOf(t)
        if tNextDue[t] <= now {
            applyDue(t, now)
        }
        var anim = animIn
        let propClass = tMeta[t].class
        if _reducedMotion {
            anim.curve = propClass.reduce(anim.curve)
        }
        let eps = propClass.eps(_pixelScale)
        let blend = anim.resolvedBlend()
        let l0 = Int(tLane0[t])
        var changed = false
        let isDecay: Bool
        if case .decay = anim.curve { isDecay = true } else { isDecay = false }
        let isSpring: Bool
        if case .spring = anim.curve { isSpring = true } else { isSpring = false }

        for i in 0..<targets.count {
            let target = targets[i]
            let l = l0 + i
            let vel: Float?
            if let vBuf = laneVel {
                vel = vBuf[i]
            } else {
                switch anim.velocity {
                case .inherit: vel = nil
                case .zero: vel = 0.0
                case .uniform(let u): vel = u
                }
            }
            if vel == nil && !isDecay && finalTarget(l) == target {
                continue // unchanged target: keep the running trajectory and any pending due time
            }
            changed = true
            cancelPending(l)
            if anim.delay > 0.0 {
                pushPending(
                    l,
                    Pending(
                        at: now + Double(anim.delay),
                        target: target,
                        velocity: vel ?? .nan,
                        curve: anim.curve,
                        blend: blend,
                        next: noneIndex
                    )
                )
            } else {
                let before: Float?
                if retargetAudit != nil
                    && propClass == .spatial
                    && isSpring
                    && vel == nil
                    && lLayer[l].end > now
                {
                    before = sampleLane(l, now).1
                } else {
                    before = nil
                }
                startLane(l, now, target, anim.curve, blend, vel, eps)
                if let b = before {
                    let err = abs(sampleLane(l, now).1 - b)
                    retargetAudit!.lanes += 1
                    retargetAudit!.maxVelocityError = max(retargetAudit!.maxVelocityError, err)
                }
            }
        }
        if changed {
            let end = now + Double(anim.delay) + Double(anim.curve.logicalDuration())
            commitScheduled(t, end, anim.token)
        } else if anim.token != 0 {
            if tSlot[t] == noneIndex {
                let m = tMeta[t]
                _events.append(.completed(token: anim.token, node: m.node, prop: m.prop, finished: true))
            } else {
                takeToken(t, false)
                tMeta[t].token = anim.token
            }
        }
        return changed
    }

    /// Starts a new segment on lane `l` at time `at` from its exact state there.
    func startLane(
        _ l: Int,
        _ at: Double,
        _ target: Float,
        _ curve: Curve,
        _ blend: Blend,
        _ vel: Float?,
        _ eps: Eps
    ) {
        let (x, v) = sampleLane(l, at)
        lCurve[l] = curve
        switch curve {
        case .instant:
            freeExtra(l)
            lLayer[l] = .rest
            lTarget[l] = target
        case .decay(let d):
            let v0 = vel ?? v
            freeExtra(l)
            lTarget[l] = x + v0 / d.k()
            lLayer[l] = Layer.decay(d.k(), at, v0, eps)
        default:
            if blend == .additive {
                let old = lTarget[l]
                lTarget[l] = target
                let carryVel: Float = vel.map { $0 - v } ?? 0.0
                let layer = Layer.start(curve, at, old - target, carryVel, eps)
                pushLayer(l, layer, at)
            } else {
                freeExtra(l)
                lTarget[l] = target
                lLayer[l] = Layer.start(curve, at, x - target, vel ?? v, eps)
            }
        }
    }

    private func pushLayer(_ l: Int, _ layer: Layer, _ at: Double) {
        if layer.kind == .rest {
            return
        }
        if lLayer[l].kind == .rest || lLayer[l].end <= at {
            lLayer[l] = layer
            return
        }
        var count = 1
        var m = lMore[l]
        while m != noneIndex {
            count += 1
            m = extra[Int(m)].next
        }
        if count >= maxAdditive {
            // Too many stacked layers: collapse into one merged segment on the new curve. Exact in
            // position and velocity at `at`.
            // The lane's target already moved; the new layer carries the difference.
            let (x0, v0) = sampleLane(l, at)
            let (o, ov) = layer.sample(at)
            let x = x0 + o
            let v = v0 + ov
            freeExtra(l)
            let target = lTarget[l]
            let curve = lCurve[l]
            lLayer[l] = Layer.start(curve, at, x - target, v, Eps(pos: 1e-4, vel: 1e-3))
            return
        }
        let idx = allocExtra(Extra(layer: layer, next: lMore[l]))
        lMore[l] = idx
    }

    @inline(__always)
    func sampleLane(_ l: Int, _ at: Double) -> (Float, Float) {
        var (o, v) = lLayer[l].sample(at)
        var m = lMore[l]
        while m != noneIndex {
            let e = extra[Int(m)]
            let (a, b) = e.layer.sample(at)
            o += a
            v += b
            m = e.next
        }
        return (lTarget[l] + o, v)
    }

    /// Sums extra layers and frees the ones that have ended.
    private func sampleExtra(_ l: Int, _ now: Double) -> (Float, Float) {
        var o: Float = 0.0
        var v: Float = 0.0
        var prev = noneIndex
        var m = lMore[l]
        while m != noneIndex {
            let mi = Int(m)
            let e = extra[mi]
            if now >= e.layer.end {
                if prev == noneIndex {
                    lMore[l] = e.next
                } else {
                    extra[Int(prev)].next = e.next
                }
                extra[mi].next = extraFree
                extraFree = m
            } else {
                let (a, b) = e.layer.sample(now)
                o += a
                v += b
                prev = m
            }
            m = e.next
        }
        return (o, v)
    }

    func finalTarget(_ l: Int) -> Float {
        var p = lPending[l]
        var target = lTarget[l]
        while p != noneIndex {
            let pi = Int(p)
            target = pending[pi].target
            p = pending[pi].next
        }
        return target
    }

    private func applyDue(_ t: Int, _ now: Double) {
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        let eps = tMeta[t].class.eps(_pixelScale)
        for l in l0..<(l0 + n) {
            while true {
                let p = lPending[l]
                if p == noneIndex || pending[Int(p)].at > now {
                    break
                }
                let pi = Int(p)
                let ev = pending[pi]
                lPending[l] = ev.next
                pending[pi].next = pendingFree
                pendingFree = p
                let vel: Float? = ev.velocity.isNaN ? nil : ev.velocity
                startLane(l, ev.at, ev.target, ev.curve, ev.blend, vel, eps)
            }
        }
        recompute(t)
    }

    /// Recomputes the track's next due time and settle time from its lanes.
    func recompute(_ t: Int) {
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        var due = Double.infinity
        var settle = -Double.infinity
        for l in l0..<(l0 + n) {
            let p = lPending[l]
            if p != noneIndex {
                due = min(due, pending[Int(p)].at)
            }
            if lLayer[l].kind != .rest {
                settle = max(settle, lLayer[l].end)
            }
            var m = lMore[l]
            while m != noneIndex {
                let mi = Int(m)
                settle = max(settle, extra[mi].layer.end)
                m = extra[mi].next
            }
        }
        tNextDue[t] = due
        tSettleAt[t] = settle
    }

    private func settle(_ t: Int) {
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        for l in l0..<(l0 + n) {
            freeExtra(l)
            lLayer[l] = .rest
            lValue[l] = lTarget[l]
            lVel[l] = 0.0
        }
        let m = tMeta[t]
        _events.append(.settled(track: idOf(t), node: m.node, prop: m.prop))
        takeToken(t, true)
    }

    func takeToken(_ t: Int, _ finished: Bool) {
        let token = tMeta[t].token
        if token != 0 {
            tMeta[t].token = 0
            let m = tMeta[t]
            _events.append(.completed(token: token, node: m.node, prop: m.prop, finished: finished))
        }
    }

    private func activate(_ t: Int) {
        if tSlot[t] == noneIndex {
            tSlot[t] = UInt32(activeIndices.count)
            activeIndices.append(UInt32(t))
        }
    }

    private func deactivate(_ t: Int, _ slot: Int) {
        let lastIdx = activeIndices.count - 1
        if slot != lastIdx {
            let moved = activeIndices[lastIdx]
            activeIndices[slot] = moved
            tSlot[Int(moved)] = UInt32(slot)
        }
        activeIndices.removeLast()
        tSlot[t] = noneIndex
    }

    func pushPending(_ l: Int, _ evIn: Pending) {
        var ev = evIn
        // Keep the lane's list sorted by time.
        var prev = noneIndex
        var cur = lPending[l]
        while cur != noneIndex && pending[Int(cur)].at <= ev.at {
            prev = cur
            cur = pending[Int(cur)].next
        }
        ev.next = cur
        let idx: UInt32
        if pendingFree != noneIndex {
            let i = pendingFree
            pendingFree = pending[Int(i)].next
            pending[Int(i)] = ev
            idx = i
        } else {
            pending.append(ev)
            idx = UInt32(pending.count - 1)
        }
        if prev == noneIndex {
            lPending[l] = idx
        } else {
            pending[Int(prev)].next = idx
        }
    }

    func schedule(
        _ t: Int,
        _ lane: Int,
        _ at: Double,
        _ target: Float,
        _ curve: Curve,
        _ blend: Blend,
        _ velocity: Float?
    ) {
        let l = Int(tLane0[t]) + lane
        pushPending(
            l,
            Pending(
                at: at,
                target: target,
                velocity: velocity ?? .nan,
                curve: curve,
                blend: blend,
                next: noneIndex
            )
        )
    }

    func cancelTrackPending(_ t: Int) {
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        for l in l0..<(l0 + n) {
            cancelPending(l)
        }
    }

    /// After `schedule` calls: recompute timing and wake the track.
    func commitScheduled(_ t: Int, _ logicalAt: Double, _ token: UInt64) {
        takeToken(t, false)
        tMeta[t].token = token
        tMeta[t].logicalAt = logicalAt
        tMeta[t].epoch &+= 1
        tHeld[t] = false
        recompute(t)
        activate(t)
    }

    func cancelPending(_ l: Int) {
        var p = lPending[l]
        while p != noneIndex {
            let pi = Int(p)
            let next = pending[pi].next
            pending[pi].next = pendingFree
            pendingFree = p
            p = next
        }
        lPending[l] = noneIndex
    }

    private func allocExtra(_ e: Extra) -> UInt32 {
        if extraFree != noneIndex {
            let i = extraFree
            extraFree = extra[Int(i)].next
            extra[Int(i)] = e
            return i
        } else {
            extra.append(e)
            return UInt32(extra.count - 1)
        }
    }

    private func freeExtra(_ l: Int) {
        var m = lMore[l]
        while m != noneIndex {
            let mi = Int(m)
            let next = extra[mi].next
            extra[mi].next = extraFree
            extraFree = m
            m = next
        }
        lMore[l] = noneIndex
    }

    func unlinkNode(_ node: NodeId, _ t: UInt32) {
        let head = nodeHead[node.rawValue] ?? noneIndex
        if head == t {
            let next = tMeta[Int(t)].nodeNext
            if next == noneIndex {
                nodeHead.removeValue(forKey: node.rawValue)
            } else {
                nodeHead[node.rawValue] = next
            }
            return
        }
        var cur = head
        while cur != noneIndex {
            let ci = Int(cur)
            let next = tMeta[ci].nodeNext
            if next == t {
                tMeta[ci].nodeNext = tMeta[Int(t)].nodeNext
                return
            }
            cur = next
        }
    }

    func freeTrack(_ t: Int) {
        if !tMeta[t].alive {
            return
        }
        let l0 = Int(tLane0[t])
        let n = Int(tN[t])
        for l in l0..<(l0 + n) {
            cancelPending(l)
            freeExtra(l)
        }
        if tSlot[t] != noneIndex {
            let slot = Int(tSlot[t])
            deactivate(t, slot)
        }
        let m = tMeta[t]
        index.removeValue(forKey: NodePropKey(m.node.rawValue, m.prop.rawValue))
        laneFree[n].append(UInt32(l0))
        // Removal cancels the animation: whoever waits on its completion hears so.
        takeToken(t, false)
        tMeta[t].alive = false
        trackFree.append(UInt32(t))
    }
}
