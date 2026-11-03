// Ported from: crates/rune/src/runtime/motion/unseen_presence.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Suppress entrance animations for newly mounted nodes that lie completely outside their scrollport/viewport,
//! and end exits that drew nothing on the previous frame.

import RuneMotion

extension Runtime {
    func endUnseenExits() {
        guard hasCommittedOnce, !exitingNodes.isEmpty else { return }
        var exitingById: [RuneMotion.NodeId: ExitingNode] = [:]
        exitingById.reserveCapacity(exitingNodes.count)
        for ex in exitingNodes {
            exitingById[ex.nodeId] = ex
        }
        exitingNodes.removeAll { ex in
            guard scene.contains(ex.nodeId) else { return true }
            guard let geo = presentedExitingGeometry(ex, byId: exitingById) else {
                scene.setTimeScale(ex.nodeId, 1.0)
                scene.unmount(ex.nodeId)
                return true
            }
            let cx0 = max(geo.rect[0], max(ex.clipRect[0], 0.0))
            let cy0 = max(geo.rect[1], max(ex.clipRect[1], 0.0))
            let cx1 = min(geo.rect[0] + geo.rect[2], min(ex.clipRect[2], viewport.0))
            let cy1 = min(geo.rect[1] + geo.rect[3], min(ex.clipRect[3], viewport.1))
            let clippedOut = cx1 <= cx0 || cy1 <= cy0
            if geo.opacity < (1.0 / 512.0) || clippedOut {
                scene.setTimeScale(ex.nodeId, 1.0)
                scene.unmount(ex.nodeId)
                return true
            }
            return false
        }
    }

    func isOffscreenUnseenEntrance(nodeIdx: Int) -> Bool {
        guard nodes.indices.contains(nodeIdx) else { return false }
        let n = nodes[nodeIdx]
        let rect = n.layoutRect
        // Zero-area nodes have nothing visible to animate in
        if rect[2] <= 0.0 || rect[3] <= 0.0 {
            return false
        }

        // Check against scroll ancestor's viewport if inside a scroll container
        if let sIdx = n.scrollAncestor {
            let sNode = nodes[sIdx]
            let sKey = sNode.key ?? sNode.path
            let sy = scrolls[sKey]?.offset ?? 0.0
            let sx = scrollsX[sKey]?.offset ?? 0.0
            let drawnX = rect[0] - sx
            let drawnY = rect[1] - sy
            let vp = sNode.layoutRect
            if drawnX + rect[2] < vp[0] - 1.0
                || drawnX > vp[0] + vp[2] + 1.0
                || drawnY + rect[3] < vp[1] - 1.0
                || drawnY > vp[1] + vp[3] + 1.0
            {
                return true
            }
        }

        // Check against root window viewport (accounting for scroll offset if any)
        var ox: Float = 0.0
        var oy: Float = 0.0
        var cur = n.scrollAncestor
        while let anc = cur {
            let sk = nodes[anc].key ?? nodes[anc].path
            ox += scrollsX[sk]?.offset ?? 0.0
            oy += scrolls[sk]?.offset ?? 0.0
            cur = nodes[anc].scrollAncestor
        }
        let wx = rect[0] - ox
        let wy = rect[1] - oy
        if wx + rect[2] < -1.0 || wx > viewport.0 + 1.0 || wy + rect[3] < -1.0 || wy > viewport.1 + 1.0 {
            return true
        }
        return false
    }
}
