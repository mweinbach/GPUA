// Ported from: crates/rune-motion/src/store/typed.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

extension AnimationStore {
    /// Sets a value immediately: direct manipulation, no animation, cancels anything running.
    /// The first `set` or `animate` of a property creates its track.
    @discardableResult
    public func set<T: Animatable>(_ node: NodeId, _ prop: Prop<T>, _ value: T) -> TrackId {
        setChanged(node, prop, value).0
    }

    /// ``set(_:_:_:)``, and whether it changed anything: setting a track already at rest on
    /// `value` leaves it, and what it last presented, as they are.
    func setChanged<T: Animatable>(_ node: NodeId, _ prop: Prop<T>, _ value: T) -> (TrackId, Bool) {
        let v = lanes(value)
        return v.withBuffer(count: T.lanes) { buf in
            let key = NodePropKey(node.rawValue, prop.id.rawValue)
            if let t = index[key] {
                let ti = Int(t)
                checkLanes(ti, T.lanes)
                if atRestOn(ti, buf) {
                    return (idOf(ti), false)
                }
            }
            let t = ensure(node, prop.id, prop.class, buf)
            setRaw(t, buf)
            return (idOf(Int(t)), true)
        }
    }

    /// Track `t` is settled exactly on `v`: nothing running, scheduled or stacked on any lane.
    private func atRestOn(_ t: Int, _ v: UnsafeBufferPointer<Float>) -> Bool {
        if tSlot[t] != noneIndex || tMeta[t].token != 0 {
            return false
        }
        let l0 = Int(tLane0[t])
        for i in 0..<v.count {
            let l = l0 + i
            let x = v[i]
            if lTarget[l] != x
                || lValue[l] != x
                || lVel[l] != 0.0
                || lPending[l] != noneIndex
                || lMore[l] != noneIndex
                || lLayer[l].kind != .rest
            {
                return false
            }
        }
        return true
    }

    /// Animates a property to `target`. Retargets from the exact current position and velocity.
    /// The first time a property is seen it is *set* instead: nothing animates on first mount.
    /// An unchanged target is a no-op (the running trajectory is kept).
    @discardableResult
    public func animate<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ target: T,
        _ anim: some AnimExt
    ) -> TrackId {
        animateChanged(node, prop, target, anim.intoAnim()).0
    }

    /// ``animate(_:_:_:_:)``, and whether it changed anything (an unchanged target doesn't).
    func animateChanged<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ target: T,
        _ anim: Anim
    ) -> (TrackId, Bool) {
        let key = NodePropKey(node.rawValue, prop.id.rawValue)
        guard let t = index[key] else {
            return setChanged(node, prop, target)
        }
        let ti = Int(t)
        checkLanes(ti, T.lanes)
        let v = lanes(target)
        let changed = v.withBuffer(count: T.lanes) { buf in
            animateRaw(ti, buf, anim, nil)
        }
        return (idOf(ti), changed)
    }

    /// Sets `from` immediately, then animates to `to` (an explicit entrance).
    @discardableResult
    public func animateFrom<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ from: T,
        _ to: T,
        _ anim: some AnimExt
    ) -> TrackId {
        set(node, prop, from)
        return animate(node, prop, to, anim)
    }

    /// Animates with an explicit per-lane starting velocity (gesture handoff).
    @discardableResult
    public func animateWithVelocity<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ target: T,
        _ velocity: T,
        _ anim: some AnimExt
    ) -> TrackId {
        let v = lanes(target)
        let vel = lanes(velocity)
        let a = anim.intoAnim()
        return v.withBuffer(count: T.lanes) { vBuf in
            vel.withBuffer(count: T.lanes) { velBuf in
                let t = Int(ensure(node, prop.id, prop.class, vBuf))
                animateRaw(t, vBuf, a, velBuf)
                return idOf(t)
            }
        }
    }

    /// Hands a released gesture to physics, from its current value and the given velocity.
    @discardableResult
    public func release<T: Animatable>(
        _ node: NodeId,
        _ prop: Prop<T>,
        _ velocity: T,
        _ how: Release<T>
    ) -> TrackId {
        let vel = lanes(velocity)
        guard let sampled = sample(node, prop) else {
            preconditionFailure("release: set the value before releasing it")
        }
        let cur = lanes(sampled)
        let t = Int(index[NodePropKey(node.rawValue, prop.id.rawValue)]!)
        let n = T.lanes
        switch how {
        case .spring(let target, let spring):
            let tg = lanes(target)
            tg.withBuffer(count: n) { tgBuf in
                vel.withBuffer(count: n) { velBuf in
                    _ = animateRaw(t, tgBuf, Anim(curve: .spring(spring)), velBuf)
                }
            }
        case .decay(let d):
            // The decay's target is computed per lane from (x, v); pass the current values.
            cur.withBuffer(count: n) { curBuf in
                vel.withBuffer(count: n) { velBuf in
                    _ = animateRaw(t, curBuf, Anim(curve: .decay(d)), velBuf)
                }
            }
        case .decayClamped(let decay, let minVal, let maxVal, let spring):
            let lo = lanes(minVal)
            let hi = lanes(maxVal)
            let k = decay.k()
            let l0 = Int(tLane0[t])
            let now = timeOf(t)
            let eps = tMeta[t].class.eps(_pixelScale)
            for i in 0..<n {
                let l = l0 + i
                let x = cur[i]
                let v = vel[i]
                cancelPending(l)
                if x < lo[i] || x > hi[i] {
                    let bound = min(max(x, lo[i]), hi[i])
                    startLane(l, now, bound, .spring(spring), .merge, v, eps)
                    continue
                }
                let proj = x + v / k
                startLane(l, now, x, .decay(decay), .merge, v, eps)
                let bound: Float?
                if proj > hi[i] {
                    bound = hi[i]
                } else if proj < lo[i] {
                    bound = lo[i]
                } else {
                    bound = nil
                }
                if let b = bound {
                    // x + (v/k)(1 − e^{−kτ}) = b  →  τ = −ln(1 − (b − x)k/v) / k
                    let tau = -log(Double(1.0 - (b - x) * k / v)) / Double(k)
                    pushPending(
                        l,
                        Pending(
                            at: now + max(tau, 0.0),
                            target: b,
                            velocity: .nan,
                            curve: .spring(spring),
                            blend: .merge,
                            next: noneIndex
                        )
                    )
                }
            }
            commitScheduled(t, now, 0)
        }
        return idOf(t)
    }

    /// The value presented at the last `tick` (what's on screen).
    public func get<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> T? {
        guard let tRaw = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        let t = Int(tRaw)
        let l0 = Int(tLane0[t])
        return lValue.withUnsafeBufferPointer { buf in
            T.readLanes(UnsafeBufferPointer(rebasing: buf[l0..<(l0 + T.lanes)]))
        }
    }

    /// The velocity at the last `tick`, in units per second.
    public func velocity<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> T? {
        guard let tRaw = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        let t = Int(tRaw)
        let l0 = Int(tLane0[t])
        return lVel.withUnsafeBufferPointer { buf in
            T.readLanes(UnsafeBufferPointer(rebasing: buf[l0..<(l0 + T.lanes)]))
        }
    }

    /// The exact value at the current `now()` (may be between ticks).
    public func sample<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> T? {
        guard let tRaw = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        let t = Int(tRaw)
        var out = LaneStorage()
        let l0 = Int(tLane0[t])
        let now = timeOf(t)
        for i in 0..<T.lanes {
            out[i] = sampleLane(l0 + i, now).0
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    /// The exact velocity at the current `now()`.
    public func sampleVelocity<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> T? {
        guard let tRaw = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        let t = Int(tRaw)
        var out = LaneStorage()
        let l0 = Int(tLane0[t])
        let now = timeOf(t)
        for i in 0..<T.lanes {
            out[i] = sampleLane(l0 + i, now).1
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    /// Where the property is going (the latest target, including delayed ones).
    public func target<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> T? {
        guard let tRaw = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        let t = Int(tRaw)
        let l0 = Int(tLane0[t])
        var out = LaneStorage()
        for i in 0..<T.lanes {
            out[i] = finalTarget(l0 + i)
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    public func has<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> Bool {
        index[NodePropKey(node.rawValue, prop.id.rawValue)] != nil
    }

    public func isAnimating<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> Bool {
        guard let t = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return false
        }
        return tSlot[Int(t)] != noneIndex
    }

    /// True when any property track on `node` is currently active.
    public func isNodeAnimating(_ node: NodeId) -> Bool {
        var t = nodeHead[node.rawValue] ?? noneIndex
        while t != noneIndex {
            let ti = Int(t)
            if tSlot[ti] != noneIndex {
                return true
            }
            t = tMeta[ti].nodeNext
        }
        return false
    }

    public func trackId<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) -> TrackId? {
        guard let t = index[NodePropKey(node.rawValue, prop.id.rawValue)] else {
            return nil
        }
        return idOf(Int(t))
    }

    /// Is this exact track (not a reused slot) alive?
    public func contains(_ id: TrackId) -> Bool {
        let ti = Int(id.index)
        guard ti >= 0 && ti < tMeta.count else {
            return false
        }
        let m = tMeta[ti]
        return m.alive && m.generation == id.generation
    }

    /// True once the track is at rest (or gone).
    public func isSettled(_ id: TrackId) -> Bool {
        !contains(id) || tSlot[Int(id.index)] == noneIndex
    }

    /// Bumps every time the track gets a new animation; choreography uses it to tell whether a
    /// track it started was taken over by something else.
    public func epoch(_ id: TrackId) -> UInt32? {
        guard contains(id) else { return nil }
        return tMeta[Int(id.index)].epoch
    }

    /// When the track's latest animation logically completes (SwiftUI `.logicallyComplete`), in
    /// the store's time. On a scaled clock it's projected at the clock's current scale; a stopped
    /// clock never gets there.
    public func logicalEnd(_ id: TrackId) -> Double? {
        guard contains(id) else { return nil }
        let t = Int(id.index)
        let at = tMeta[t].logicalAt
        let c = tClock[t]
        if c == 0 {
            return at
        }
        let rem = at - timeOf(t)
        let sc = Double(clocks[Int(c)].scale)
        if rem <= 0.0 {
            return _now + rem
        } else if sc == 0.0 {
            return .infinity
        } else {
            return _now + rem / sc
        }
    }

    /// The node and property a track belongs to.
    public func owner(_ id: TrackId) -> (NodeId, PropId)? {
        guard contains(id) else { return nil }
        let m = tMeta[Int(id.index)]
        return (m.node, m.prop)
    }

    /// Removes one property's track.
    public func remove<T: Animatable>(_ node: NodeId, _ prop: Prop<T>) {
        if let t = index[NodePropKey(node.rawValue, prop.id.rawValue)] {
            unlinkNode(node, t)
            freeTrack(Int(t))
        }
    }

    /// Removes every track of a node.
    public func removeNode(_ node: NodeId) {
        if let c = nodeClock.removeValue(forKey: node.rawValue) {
            releaseClock(c)
        }
        var t = nodeHead.removeValue(forKey: node.rawValue) ?? noneIndex
        while t != noneIndex {
            let ti = Int(t)
            let next = tMeta[ti].nodeNext
            freeTrack(ti)
            t = next
        }
    }

    /// Live tuning: every lane currently springing on `old` re-springs on `new` from where it is,
    /// at the same target (research 06 §2.6). Smooth because the swap keeps `(x, v)`.
    public func retune(_ old: Spring, _ new: Spring) {
        for i in 0..<activeIndices.count {
            let t = Int(activeIndices[i])
            let now = timeOf(t)
            let l0 = Int(tLane0[t])
            let n = Int(tN[t])
            let eps = tMeta[t].class.eps(_pixelScale)
            var hit = false
            for l in l0..<(l0 + n) {
                if lCurve[l] == .spring(old) {
                    let target = lTarget[l]
                    startLane(l, now, target, .spring(new), .merge, nil, eps)
                    hit = true
                }
            }
            if hit {
                recompute(t)
            }
        }
    }
}
