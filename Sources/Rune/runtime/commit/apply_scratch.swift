// Ported from: crates/rune/src/runtime/commit/apply_scratch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Reusable scratch buffers for `commit` / `apply` so commits avoid per-frame dictionary churn.

import RuneMotion

struct ApplyScratch {
    var mountedIds: Set<RuneMotion.NodeId> = []
    var previousByNodeId: [RuneMotion.NodeId: Int] = [:]
    var previousMatched: [String: (RuneMotion.NodeId, [Float])] = [:]
    var currentMatched: [String: Int] = [:]
    var siblingKeyCounts: [String: Int] = [:]

    init() {}

    mutating func resetForCommit(previousNodes: [Node]) {
        mountedIds.removeAll(keepingCapacity: true)
        previousByNodeId.removeAll(keepingCapacity: true)
        previousMatched.removeAll(keepingCapacity: true)
        currentMatched.removeAll(keepingCapacity: true)
        siblingKeyCounts.removeAll(keepingCapacity: true)

        for i in previousNodes.indices {
            let n = previousNodes[i]
            previousByNodeId[n.nodeId] = i
            if let mid = n.matchedId {
                previousMatched[mid] = (n.nodeId, n.presentedRect)
            }
        }
    }
}
