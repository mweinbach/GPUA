// Ported from: crates/rune/src/runtime/commit/prune.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Prune stale per-node/per-key runtime maps when nodes finish exiting or are unmounted.

import RuneMotion

extension Runtime {
    func pruneStaleState(mountedIds: Set<RuneMotion.NodeId>, mountedKeys: Set<String>, mountedPaths: Set<String>) {
        // Keep exiting nodes only while the scene still holds them in `.exiting`.
        exitingNodes.removeAll { ex in
            !scene.contains(ex.nodeId) || mountedIds.contains(ex.nodeId)
        }

        let liveAndExitingIds = mountedIds.union(exitingNodes.map(\.nodeId))

        // Prune loops
        loops = loops.filter { mountedIds.contains($0.key) }

        // Prune growth tracks
        growthTracks = growthTracks.filter { liveAndExitingIds.contains($0.key) }

        // Prune reveal states
        reveals = reveals.filter { mountedPaths.contains($0.key) }

        // Prune group fading set
        groupFading = groupFading.filter { liveAndExitingIds.contains($0) }

        // Prune live subscriptions for nodes that are neither mounted nor still exiting
        var keptLive: [RuneMotion.NodeId: LiveNodeEntry] = [:]
        for (id, entry) in liveNodeBindings {
            if liveAndExitingIds.contains(id) {
                keptLive[id] = entry
            } else {
                for sub in entry.subscriptions {
                    sub.active = false
                }
            }
        }
        liveNodeBindings = keptLive

        // Prune scroll & input caches for vanished nodes
        scrolls = scrolls.filter { mountedKeys.contains($0.key) || mountedPaths.contains($0.key) }
        scrollsX = scrollsX.filter { mountedKeys.contains($0.key) || mountedPaths.contains($0.key) }
        inputScrollOffsets = inputScrollOffsets.filter { mountedPaths.contains($0.key) }
        previousShapedByPath = previousShapedByPath.filter { mountedPaths.contains($0.key) }
        glyphCache.prune(keeping: liveAndExitingIds)

        // Prune hovered paths that vanished
        hoveredPaths = hoveredPaths.filter { mountedPaths.contains($0) }
        if let pressed = pressedPath, !mountedPaths.contains(pressed) {
            pressedPath = nil
        }

        // Prune layer caches for vanished nodes
        layerCache.prune(keeping: liveAndExitingIds)
    }
}
