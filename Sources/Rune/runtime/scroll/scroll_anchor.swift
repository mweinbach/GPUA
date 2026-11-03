// Ported from: crates/rune/src/runtime/scroll/anchor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scroll anchoring: keep the top-most visible keyed child stationary in viewport space when content inserts above it.

extension Runtime {
    func captureScrollAnchors(in nodesList: [Node]) -> [String: (String, Float)] {
        var anchors: [String: (String, Float)] = [:]
        for i in nodesList.indices where nodesList[i].scrollSpec != nil {
            let sKey = nodesList[i].key ?? nodesList[i].path
            guard let entry = scrolls[sKey], entry.offset > 0.5, !entry.stuckBottom else { continue }
            let vpTop = nodesList[i].layoutRect[1]
            for cIdx in nodesList[i].children {
                guard let cKey = nodesList[cIdx].key else { continue }
                let relTop = nodesList[cIdx].layoutRect[1] - vpTop - entry.offset
                let h = nodesList[cIdx].layoutRect[3]
                if relTop + h > 0.0 {
                    anchors[sKey] = (cKey, relTop)
                    break
                }
            }
        }
        return anchors
    }
}
