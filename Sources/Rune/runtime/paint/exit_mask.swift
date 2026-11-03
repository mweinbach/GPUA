// Ported from: crates/rune/src/runtime/paint/exit_mask.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Per-frame exiting-subtree mask and `Presented.mask` clip/feather application.

import RuneMotion

struct ExitMask: Sendable {
    var exiting: [Bool] = []
    var commitGen: UInt64? = nil

    mutating func forget() {
        commitGen = nil
    }

    func get(_ index: Int, count: Int, commit: UInt64) -> Bool? {
        guard commitGen == commit, exiting.count == count, exiting.indices.contains(index) else {
            return nil
        }
        return exiting[index]
    }
}

func applyPresentedMask(
    _ mask: Mask,
    rectEdges r: [Float],
    scalePx: Float,
    clip: inout [Float],
    fade: inout [Float],
    fadeOrigin: inout [Float]
) {
    guard !mask.isNone() else { return }
    let ins = mask.inset.values.map { $0 * scalePx }
    let fea = mask.feather.values.map { $0 * scalePx }
    let maskedRect: [Float] = [
        r[0] + ins[0],
        r[1] + ins[1],
        r[2] - ins[2],
        r[3] - ins[3],
    ]
    clip = [
        max(maskedRect[0], clip[0]),
        max(maskedRect[1], clip[1]),
        min(maskedRect[2], clip[2]),
        min(maskedRect[3], clip[3]),
    ]
    inheritFade(&fade, &fadeOrigin, maskedRect, fea)
}

extension Runtime {
    func beginExitMask() {
        exitMask.commitGen = nil
        exitMask.exiting.removeAll(keepingCapacity: true)
        exitMask.exiting.reserveCapacity(nodes.count)
        for i in nodes.indices {
            let n = nodes[i]
            let parentExiting: Bool = {
                guard let p = n.parent else { return false }
                if p < i {
                    return exitMask.exiting[p]
                }
                return subtreeExiting(p)
            }()
            let selfExiting = isNodeExiting(n.nodeId)
            exitMask.exiting.append(parentExiting || selfExiting)
        }
        exitMask.commitGen = totalCommits
    }

    func endExitMask() {
        exitMask.forget()
    }

    func subtreeExiting(_ idx: Int) -> Bool {
        if let cached = exitMask.get(idx, count: nodes.count, commit: totalCommits) {
            return cached
        }
        var cur: Int? = idx
        while let i = cur, nodes.indices.contains(i) {
            if isNodeExiting(nodes[i].nodeId) {
                return true
            }
            cur = nodes[i].parent
        }
        return false
    }
}
