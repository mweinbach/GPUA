// Ported from: crates/rune-motion/src/scene/trailing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

extension Scene {
    /// While its parent's width animates, `id` keeps its place against the parent's trailing
    /// (right) edge instead of its leading one. Its frame is still given in parent space; when the
    /// parent's width changes, a child that kept its distance from that edge doesn't move at all,
    /// and one that moved relative to it travels only that difference, on its own curve. Exiting
    /// children hold their distance too.
    public func setRideTrailing(_ id: NodeId, _ on: Bool) {
        if let i = slot(id), nodes[i].rideTrailing != on {
            nodes[i].rideTrailing = on
            nodes[i].dirty = true
        }
    }

    /// Node `i`'s width target changed by `dw`. Its children that ride the trailing edge are
    /// drawn `drawn width − target width` right of the leading origin, so the change would move
    /// them; their local x (target, value and anything scheduled) moves by `dw` to cancel it.
    func rebaseTrailing(_ i: Int, _ dw: Float) {
        var c = nodes[i].firstChild
        while c != noneIndex {
            let k = Int(c)
            if nodes[k].rideTrailing {
                nodes[k].frame.x += dw
                if nodes[k].path != nil {
                    nodes[k].path!.endLocal.x += dw
                }
                nodes[k].dirty = true
                if let t = nodes[k].tracks[Int(prop.frame.id.rawValue)] {
                    var delta = LaneStorage()
                    delta[0] = dw
                    delta[2] = dw
                    delta.withBuffer(count: 4) { buf in
                        _store.translate(t.indexInt(), buf)
                    }
                }
            }
            c = nodes[k].nextSibling
        }
    }

    /// How far right of its parent's leading origin node `i` rides now, with its velocity: the
    /// parent's drawn width less its target width, for a node riding the trailing edge.
    func trailDual(_ i: Int) -> Dual {
        let n = nodes[i]
        if !n.rideTrailing || n.parent == noneIndex {
            return .c(0.0)
        }
        let p = Int(n.parent)
        let w = worldDual(p)
        return w[2].sub(w[0]).sub(.c(nodes[p].frame.w))
    }
}
