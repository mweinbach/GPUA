// Ported from: crates/rune-motion/src/scene/travel.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

extension Scene {
    /// Hands one node's presented geometry, corner radius and fill to another, which then morphs
    /// to its own layout (SwiftUI `matchedGeometryEffect`, Motion `layoutId`). `from` disappears
    /// at once; `to` starts exactly where `from` was seen, with its velocity, and travels a
    /// straight root-space path. Under Reduce Motion it's a crossfade in place.
    public func matchGeometry(_ from: NodeId, _ to: NodeId, _ anim: some LayoutAnimConvertible) {
        matchGeometryOffset(from, to, .zero, anim)
    }

    /// ``matchGeometry(_:_:_:)`` for a `from` that was seen `offset` away from its
    /// scene rect, measured in `to`'s root space: a scroll offset the renderer applies outside the
    /// scene, which differs between the two places.
    public func matchGeometryOffset(
        _ from: NodeId,
        _ to: NodeId,
        _ offset: Vec2,
        _ anim: some LayoutAnimConvertible
    ) {
        guard let a = slot(from), let b = slot(to) else { return }
        let la = anim.intoLayoutAnim()
        if _store.reducedMotion() {
            remove(from)
            let enter = nodes[b].transition.springs.enter
            trackSet(b, prop.presence, Float(0.0))
            trackAnimate(b, prop.presence, Float(1.0), Anim(enter))
            nodes[b].phase = .entering
            return
        }
        var (start, vel) = exactWorld(a)
        start.0 += offset.x
        start.1 += offset.y
        start.2 += offset.x
        start.3 += offset.y
        let radius = current(a, prop.radius) ?? nodes[a].radius
        let fill = current(a, prop.fill) ?? nodes[a].fill
        let toRadius = nodes[b].radius
        let toFill = nodes[b].fill
        // `to` is the one surface from now on: fully present, no presence effect.
        trackSet(b, prop.presence, Float(1.0))
        nodes[b].phase = .present
        nodes[b].fxA = .identity
        startPath(b, start, vel, la)
        trackSet(b, prop.radius, radius)
        trackAnimate(b, prop.radius, toRadius, la.x)
        trackSet(b, prop.fill, fill)
        trackAnimate(b, prop.fill, toFill, la.y)
        intent(to, Intent.position | Intent.size | Intent.shape, la.y.curve.logicalDuration())
        removeNow(a)
    }

    /// Starts `id`, fully present, at `start` (root space) on one straight root-space path to
    /// its own layout: ``matchGeometry(_:_:_:)`` from a place no node was.
    /// Under Reduce Motion it keeps its own entrance.
    public func launch(_ id: NodeId, _ start: Rect, _ anim: some LayoutAnimConvertible) {
        guard let i = slot(id) else { return }
        if _store.reducedMotion() { return }
        let la = anim.intoLayoutAnim()
        trackSet(i, prop.presence, Float(1.0))
        nodes[i].phase = .present
        nodes[i].fxA = .identity
        startPath(i, start.edgesTuple(), (0.0, 0.0, 0.0, 0.0), la)
        intent(id, Intent.position, la.y.curve.logicalDuration())
    }

    /// ``setFrame(_:_:_:)`` with screen travel for a node the renderer draws `offset`
    /// away from its scene rect, moving `velocity` faster (root space), by offsets it applies
    /// outside the scene: the new path starts where the node is drawn, at the speed it's drawn
    /// moving, so a re-aim keeps its speed. The renderer then stops adding them.
    public func retargetDrawn(
        _ id: NodeId,
        _ frame: Rect,
        _ anim: some LayoutAnimConvertible,
        _ offset: Vec2,
        _ velocity: Vec2
    ) {
        setFrameDrawn(id, frame, anim.intoLayoutAnim(), offset, velocity)
    }

    /// How far node `id`'s screen path draws its top-left corner from where its layout under
    /// its parent's presented origin would, and how much faster it moves it (root space). `nil`
    /// without a path, or while the path still draws it at another size.
    // PORT NOTE: Returns a 2-tuple `(Vec2, Vec2)?` instead of `[Vec2; 2]` to avoid heap allocation.
    public func pathLead(_ id: NodeId) -> (Vec2, Vec2)? {
        guard let i = slot(id), let path = nodes[i].path else { return nil }
        let on = pathDual(i, path, path.origin)
        let laid = laidDual(i)
        // The presented snap step: 1/64 of a device pixel.
        let q: Float = 1.0 / (64.0 * _store.pixelScale())
        let sizeWOn = on.d2.x - on.d0.x
        let sizeWLaid = laid.d2.x - laid.d0.x
        let sizeHOn = on.d3.x - on.d1.x
        let sizeHLaid = laid.d3.x - laid.d1.x
        if abs(sizeWOn - sizeWLaid) > q || abs(sizeHOn - sizeHLaid) > q {
            return nil
        }
        return (
            Vec2(on.d0.x - laid.d0.x, on.d1.x - laid.d1.x),
            Vec2(on.d0.v - laid.d0.v, on.d1.v - laid.d1.v)
        )
    }

    /// Ends node `id`'s screen travel at its layout, as a path that has arrived ends: it then
    /// shows under its parent's presented origin.
    public func landPath(_ id: NodeId) {
        guard let i = slot(id), let path = nodes[i].path else { return }
        endPath(i)
        trackSet(i, prop.frame, path.endLocal)
        nodes[i].dirty = true
    }

    /// Node `i`'s root-space edges from its layout under its parent's presented origin, as if
    /// it had no screen path.
    func laidDual(_ i: Int) -> Dual4 {
        let n = nodes[i]
        let e = n.frame.edgesTuple()
        let local = lanesDual4(
            i,
            prop.frame.id,
            Dual4(.c(e.0), .c(e.1), .c(e.2), .c(e.3))
        )
        if n.parent == noneIndex {
            return local
        }
        var o = originDual(Int(n.parent))
        o.0 = o.0.add(trailDual(i))
        return Dual4(
            local.d0.add(o.0),
            local.d1.add(o.1),
            local.d2.add(o.0),
            local.d3.add(o.1)
        )
    }

    func startPath(
        _ i: Int,
        _ start: (Float, Float, Float, Float),
        _ vel: (Float, Float, Float, Float),
        _ anim: LayoutAnim
    ) {
        let endLocal = nodes[i].frame
        let po = parentTargetOrigin(i)
        let end = endLocal.translated(po).edgesTuple()
        // Project the current edge velocity onto each axis' path to keep it moving the same way.
        let px = axisProgressVelocity(start.0, start.2, end.0, end.2, vel.0, vel.2)
        let py = axisProgressVelocity(start.1, start.3, end.1, end.3, vel.1, vel.3)
        nodes[i].path = ScenePath(
            start: Rect.fromEdges(start.0, start.1, start.2, start.3),
            endLocal: endLocal,
            origin: po
        )
        if !travelling.contains(UInt32(i)) {
            travelling.append(UInt32(i))
        }
        trackSet(i, prop.travel, Vec2.zero)
        let t = nodes[i].tracks[Int(prop.travel.id.rawValue)]!.indexInt()
        var tgX = LaneStorage()
        tgX[0] = 1.0
        tgX[1] = 0.0
        var velX = LaneStorage()
        velX[0] = px
        velX[1] = 0.0
        tgX.withBuffer(count: 2) { tgBuf in
            velX.withBuffer(count: 2) { velBuf in
                _ = _store.animateRaw(t, tgBuf, anim.x, velBuf)
            }
        }
        var tgY = LaneStorage()
        tgY[0] = 1.0
        tgY[1] = 1.0
        var velY = LaneStorage()
        velY[0] = px
        velY[1] = py
        tgY.withBuffer(count: 2) { tgBuf in
            velY.withBuffer(count: 2) { velBuf in
                _ = _store.animateRaw(t, tgBuf, anim.y, velBuf)
            }
        }
        if nodes[i].tracks[Int(prop.frame.id.rawValue)] != nil {
            trackSet(i, prop.frame, endLocal)
        }
        nodes[i].dirty = true
    }

    func endPath(_ i: Int) {
        nodes[i].path = nil
        travelling.removeAll { Int($0) == i }
        let id = nodes[i].id
        _store.remove(id, prop.travel)
        nodes[i].tracks[Int(prop.travel.id.rawValue)] = nil
    }
}

/// The progress velocity that best continues edge velocities `(v0, v1)` along the path from
/// `(s0, s1)` to `(e0, e1)`.
@inline(__always)
private func axisProgressVelocity(
    _ s0: Float,
    _ s1: Float,
    _ e0: Float,
    _ e1: Float,
    _ v0: Float,
    _ v1: Float
) -> Float {
    let d0 = e0 - s0
    let d1 = e1 - s1
    let len2 = d0 * d0 + d1 * d1
    return len2 < 1e-6 ? 0.0 : (v0 * d0 + v1 * d1) / len2
}
