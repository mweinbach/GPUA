// Ported from: crates/rune-motion/src/scene/props.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

extension Scene {
    /// Animates one of the node's properties (`prop.opacity`, `prop.radius`, …, or a custom one).
    /// The first animation starts from the node's base value, so `.opacity(1)` → `animate(0)`
    /// fades.
    public func animate<T: Animatable>(
        _ id: NodeId,
        _ prop: Prop<T>,
        _ target: T,
        _ anim: some AnimExt
    ) {
        guard let i = slot(id) else { return }
        let a = anim.intoAnim()
        if !atBase(i, prop, target) {
            ensureProp(i, prop)
            trackAnimate(i, prop, target, a)
        }
        let bits = Intent.forProp(prop.id)
        intent(id, bits, a.curve.logicalDuration())
    }

    /// Sets a property immediately (direct manipulation).
    public func set<T: Animatable>(_ id: NodeId, _ prop: Prop<T>, _ value: T) {
        if inFlightTo(id, prop, value) {
            return
        }
        if let i = slot(id), !atBase(i, prop, value) {
            trackSet(i, prop, value)
        }
    }

    /// The property's presented value (last frame), falling back to the node's base value.
    public func get<T: Animatable>(_ id: NodeId, _ prop: Prop<T>) -> T? {
        guard let i = slot(id) else { return nil }
        return _store.get(id, prop) ?? base(i, prop.id)
    }

    func ensureProp<T: Animatable>(_ i: Int, _ p: Prop<T>) {
        if !hasTrack(i, p), let b: T = base(i, p.id) {
            trackSet(i, p, b)
        }
    }

    private func hasTrack<T: Animatable>(_ i: Int, _ p: Prop<T>) -> Bool {
        let idx = Int(p.id.rawValue)
        if idx < prop.builtinCount, nodes[i].tracks[idx] != nil {
            return true
        }
        return _store.has(nodes[i].id, p)
    }

    /// The property has no track and `value` is its base value: it shows `value` already, and
    /// a node that never moves keeps no track for it.
    func atBase<T: Animatable>(_ i: Int, _ p: Prop<T>, _ value: T) -> Bool {
        if hasTrack(i, p) {
            return false
        }
        guard let b: T = base(i, p.id) else {
            return false
        }
        let lb = lanes(b)
        let lv = lanes(value)
        for k in 0..<T.lanes {
            if lb[k] != lv[k] {
                return false
            }
        }
        return true
    }

    func base<T: Animatable>(_ i: Int, _ p: PropId) -> T? {
        let n = nodes[i]
        var l = LaneStorage()
        if p == prop.opacity.id {
            l[0] = n.opacity
        } else if p == prop.scale.id || p == prop.presence.id {
            l[0] = 1.0
        } else if p == prop.frame.id {
            let e = n.frame.edgesTuple()
            l[0] = e.0
            l[1] = e.1
            l[2] = e.2
            l[3] = e.3
        } else if p == prop.radius.id {
            l[0] = n.radius.c0
            l[1] = n.radius.c1
            l[2] = n.radius.c2
            l[3] = n.radius.c3
        } else if p == prop.fill.id {
            l = lanes(n.fill)
        } else if p == prop.offset.id || p == prop.rotation.id || p == prop.blur.id || p == prop.mask.id {
            // All-zero lanes.
        } else {
            return nil
        }
        return l.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    func current<T: Animatable>(_ i: Int, _ p: Prop<T>) -> T? {
        let idx = Int(p.id.rawValue)
        guard idx < prop.builtinCount,
            let t = nodes[i].tracks[idx],
            let (x, _) = sample(t)
        else {
            return nil
        }
        return x.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    func trackSet<T: Animatable>(_ i: Int, _ p: Prop<T>, _ value: T) {
        let (tid, changed) = _store.setChanged(nodes[i].id, p, value)
        recordTrack(i, p.id, tid, changed)
    }

    func trackAnimate<T: Animatable>(_ i: Int, _ p: Prop<T>, _ target: T, _ anim: Anim) {
        let (tid, changed) = _store.animateChanged(nodes[i].id, p, target, anim)
        recordTrack(i, p.id, tid, changed)
    }

    /// Remembers built-in props' tracks on the node (custom props live only in the store), and
    /// marks it to present again if the track changed.
    private func recordTrack(_ i: Int, _ p: PropId, _ id: TrackId, _ changed: Bool) {
        let idx = Int(p.rawValue)
        if idx < prop.builtinCount {
            nodes[i].tracks[idx] = id
        }
        if changed {
            nodes[i].dirty = true
        }
    }

    func intent(_ id: NodeId, _ bits: UInt32, _ seconds: Float) {
        if _trace != nil {
            intents.append((id, bits, seconds))
        }
    }
}
