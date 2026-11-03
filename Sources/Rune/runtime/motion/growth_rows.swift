// Ported from: crates/rune/src/runtime/motion/growth_rows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Streaming / growing row height tracks (`GrowTrack`), sibling lift propagation, and 240 Hz substepping.

import RuneMotion

extension Runtime {
    func syncNodeGrowthTrack(nodeIdx: Int, prevNode: Node?, isFirstCommit: Bool, forceInstant: Bool) {
        let node = nodes[nodeIdx]
        let parentGrowth = node.parent.flatMap { nodes[$0].growthSpec }
        guard parentGrowth != nil || node.glideSpec != nil else { return }
        let targetH = node.layoutRect[3]
        let id = node.nodeId

        let foldLimitVal: Float = {
            guard let prev = prevNode, let g = growthTracks[id], g.h > 0.5 else { return .infinity }
            let d = prev.presentedRect
            let k = d[3] / g.h
            guard k > 0.01 else { return .infinity }
            let bottom = min(prev.clipBounds[3], viewport.1)
            return max(0.0, g.h + (bottom - d[1] - d[3]) / k)
        }()
        let foldCfg: (FoldGlide, Float)? = node.glideSpec.map { ($0, foldLimitVal) }

        if var existing = growthTracks[id] {
            existing.setKind(node.streaming, node.whole, foldCfg)
            if forceInstant || node.instantChanges {
                existing = GrowTrack.settled(targetH)
                existing.setKind(node.streaming, node.whole, foldCfg)
            } else {
                existing.retarget(targetH)
            }
            growthTracks[id] = existing
        } else {
            var track: GrowTrack
            if isFirstCommit || forceInstant || node.instantChanges {
                track = GrowTrack.settled(targetH)
            } else {
                track = GrowTrack()
                track.h = 0.0
                track.target = targetH
            }
            track.setKind(node.streaming, node.whole, foldCfg)
            growthTracks[id] = track
        }
    }

    func stepGrowthTracks(_ dt: Double) {
        guard !growthTracks.isEmpty, dt > 0.0 else { return }
        if reducedMotion {
            for id in Array(growthTracks.keys) {
                if let t = growthTracks[id]?.target {
                    growthTracks[id] = GrowTrack.settled(t)
                }
            }
            return
        }

        growAccumulator += Float(dt) * timeScale
        let maxSteps = 32
        var steps = 0
        while growAccumulator >= SUBSTEP && steps < maxSteps {
            growAccumulator -= SUBSTEP
            steps += 1
            for i in nodes.indices {
                let node = nodes[i]
                let id = node.nodeId
                guard var track = growthTracks[id], track.moving() else { continue }
                let parentGrowth = node.parent.flatMap { nodes[$0].growthSpec }
                let spring = node.glideSpec?.spring ?? parentGrowth?.spring ?? GROWTH
                let streamEdge = parentGrowth?.edge ?? Rune.edge.FEATHER
                let hasFollowingSiblings: Bool = {
                    guard let p = node.parent else { return false }
                    return nodes[p].children.last != i
                }()
                track.step(spring, streamEdge, hasFollowingSiblings)
                growthTracks[id] = track
            }
        }
        if steps == maxSteps {
            growAccumulator = 0.0
        }
    }

    func hasMovingGrowthTracks() -> Bool {
        growthTracks.values.contains { $0.moving() }
    }
}
