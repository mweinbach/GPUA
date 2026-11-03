// Ported from: crates/rune/src/runtime/motion/motion_elements.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Compact `MotionElement` snapshot builder (`Runtime.motionElements()`) for high-rate motion gate & telemetry.

import RuneMotion

extension MotionElement {
    public static let FLAG_EXITING: UInt16 = 1 << 0
    public static let FLAG_MOVING: UInt16 = 1 << 1
    public static let FLAG_SCROLLING: UInt16 = 1 << 2
    public static let FLAG_REVEALING: UInt16 = 1 << 3
    public static let FLAG_GROWING: UInt16 = 1 << 4
    public static let FLAG_FOCUSED: UInt16 = 1 << 5
    public static let FLAG_INERT: UInt16 = 1 << 6

    public func `is`(_ flag: UInt16) -> Bool {
        (self.flags & flag) != 0
    }
}

extension Runtime {
    /// Compute world-space `[x, y, w, h]`, effective opacity, effective scale, and effective blur for a node in
    /// `exitingNodes`, inheriting exit opacity, scale, and blur from any exiting ancestors in `exitingById`.
    func presentedExitingGeometry(
        _ ex: ExitingNode,
        byId exitingById: [RuneMotion.NodeId: ExitingNode]
    ) -> (rect: [Float], opacity: Float, scale: Float, blur: Float)? {
        guard let pres = scene.presented(ex.nodeId) else { return nil }

        // Check whether this node itself or an ancestor in `exitingById` is actively exiting in `Scene`
        if let pid = ex.parentNodeId, let parentEx = exitingById[pid] {
            guard let parentGeo = presentedExitingGeometry(parentEx, byId: exitingById),
                  let parentPres = scene.presented(pid)
            else { return nil }

            let lx = pres.rect.x - parentPres.rect.x
            let ly = pres.rect.y - parentPres.rect.y
            let lw = pres.rect.w
            let lh = pres.rect.h

            let parentScale = max(parentGeo.scale, 0.001)
            let ownRelScale = ex.scale * pres.transform.scale.x
            let effScale = parentScale * ownRelScale

            let bx = parentGeo.rect[0] + lx * parentScale
            let by = parentGeo.rect[1] + ly * parentScale
            let bw = lw * parentScale
            let bh = lh * parentScale
            let sw = lw * effScale
            let sh = lh * effScale
            var wx = bx
            var wy = by
            if abs(ownRelScale - 1.0) > 1e-5 {
                wx += (bw - sw) * 0.5
                wy += (bh - sh) * 0.5
            }
            let effOp = min(max(parentGeo.opacity * pres.opacity, 0.0), 1.0)
            let effBlur = parentGeo.blur + pres.blur
            return ([wx, wy, sw, sh], effOp, effScale, effBlur)
        } else {
            guard isNodeExiting(ex.nodeId) else { return nil }
            var mountedParentScale: Float = 1.0
            var mountedParentOp: Float = 1.0
            var mountedParentBlur: Float = 0.0
            if let pid = ex.parentNodeId, let pIdx = nodes.firstIndex(where: { $0.nodeId == pid }) {
                mountedParentScale = nodes[pIdx].cumulativeScale
                var cur: Int? = pIdx
                while let idx = cur {
                    let pn = nodes[idx]
                    mountedParentOp *= (scene.presented(pn.nodeId)?.opacity ?? pn.vis.opacity) * pn.groupOpacityAccum
                    mountedParentBlur += scene.presented(pn.nodeId)?.blur ?? (pn.vis.cold.getIfSome?.layerBlur ?? 0.0)
                    cur = pn.parent
                }
            }
            let effScale = max(mountedParentScale * ex.scale * pres.transform.scale.x, 0.001)
            let pw = pres.rect.w
            let ph = pres.rect.h
            let sw = pw * effScale
            let sh = ph * effScale
            let wx = pres.rect.x + (pw * mountedParentScale - sw) * 0.5
            let wy = pres.rect.y + (ph * mountedParentScale - sh) * 0.5
            let effOp = min(max(mountedParentOp * pres.opacity, 0.0), 1.0)
            let effBlur = mountedParentBlur + pres.blur
            return ([wx, wy, sw, sh], effOp, effScale, effBlur)
        }
    }

    public func motionElements() -> [MotionElement] {
        ensureClean()
        var out: [MotionElement] = []
        out.reserveCapacity(nodes.count + exitingNodes.count)

        for i in nodes.indices {
            let n = nodes[i]
            let p = scene.presented(n.nodeId)
            let op = (p?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
            let sc = (p?.transform.scale.x ?? 1.0) * (scene.get(n.nodeId, P_SCALE) ?? n.scale)
            var flags: UInt16 = 0
            if (p?.flags ?? 0) != 0 { flags |= MotionElement.FLAG_MOVING }
            if let k = n.key, scrolls[k]?.isMoving == true || scrollsX[k]?.isMoving == true {
                flags |= MotionElement.FLAG_SCROLLING
            }
            if activeRevealProgress(for: i) < 0.999 { flags |= MotionElement.FLAG_REVEALING }
            if n.inGrowingRow && (growthTracks[n.nodeId]?.moving() == true) {
                flags |= MotionElement.FLAG_GROWING
            }
            if focusedPath == n.path { flags |= MotionElement.FLAG_FOCUSED }
            if n.inert { flags |= MotionElement.FLAG_INERT }

            let lp = loops[n.nodeId].flatMap { $0.sleeping ? nil : $0.phase }
            let th = n.textSpec.map { fnvTextHash($0.content) } ?? 0

            var elem = MotionElement(
                path: n.path,
                key: n.key,
                rect: n.presentedRect,
                opacity: op
            )
            elem.id = n.nodeId
            elem.parent = n.parent
            elem.visible = n.visibleRect
            elem.scale = sc
            elem.loopPhase = lp
            elem.textHash = th
            elem.flags = flags
            out.append(elem)
        }

        if !exitingNodes.isEmpty {
            var exitingById: [RuneMotion.NodeId: ExitingNode] = [:]
            exitingById.reserveCapacity(exitingNodes.count)
            for ex in exitingNodes {
                exitingById[ex.nodeId] = ex
            }
            for ex in exitingNodes {
                guard let geo = presentedExitingGeometry(ex, byId: exitingById) else { continue }
                var elem = MotionElement(
                    path: ex.path,
                    key: ex.key,
                    rect: geo.rect,
                    opacity: geo.opacity
                )
                elem.id = ex.nodeId
                elem.visible = geo.rect
                elem.scale = geo.scale
                elem.flags = MotionElement.FLAG_EXITING | MotionElement.FLAG_MOVING
                out.append(elem)
            }
        }

        return out
    }
}
