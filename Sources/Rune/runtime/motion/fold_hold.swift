// Ported from: crates/rune/src/runtime/motion/fold_hold.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Fold-glide height hold & feather clamping (`El.foldGlide`) when accordions or drawers expand/collapse.

extension Runtime {
    func activeFoldGlideClip(for nodeIdx: Int) -> (visibleH: Float, feather: Float)? {
        guard nodes.indices.contains(nodeIdx) else { return nil }
        let node = nodes[nodeIdx]
        guard node.glideSpec != nil,
              let track = growthTracks[node.nodeId],
              track.moving()
        else { return nil }
        let feather = node.glideSpec?.feather ?? 12.0
        return (visibleH: max(track.h, 0.0), feather: max(feather, 0.0))
    }
}
