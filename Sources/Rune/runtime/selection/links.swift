// Ported from: crates/rune/src/runtime/selection/links.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Inline `Link` hit-testing and activation (`http`/`https`/`mailto` URL opening + custom link callbacks).

extension Runtime {
    public func onLink(_ handler: @escaping (inout S, String, inout Tx) -> Void) {
        linkHandler = handler
    }

    func hitLinkInNode(nodeIdx: Int, windowX: Float, windowY: Float) -> Int? {
        guard nodes.indices.contains(nodeIdx),
              let spec = nodes[nodeIdx].textSpec,
              !spec.links.isEmpty,
              let layout = nodes[nodeIdx].textLayout
        else { return nil }

        let r = nodes[nodeIdx].presentedRect
        let lx = windowX - r[0]
        let ly = windowY - r[1]
        guard lx >= 0.0 && lx <= r[2] && ly >= 0.0 && ly <= r[3] else { return nil }

        for line in layout.lines where ly >= line.y && ly < line.y + line.height {
            for g in line.glyphs where !g.isEllipsis && lx >= g.x && lx < g.x + g.advance {
                let b = UInt32(g.byteOffset)
                if let linkIdx = spec.links.firstIndex(where: { $0.start <= b && b < $0.end }) {
                    return linkIdx
                }
            }
        }
        return nil
    }

    func activateLinkInNode(nodeIdx: Int, linkIdx: Int) {
        guard nodes.indices.contains(nodeIdx),
              let spec = nodes[nodeIdx].textSpec,
              spec.links.indices.contains(linkIdx)
        else { return }

        let link = spec.links[linkIdx]
        var tx = newTx()
        if let custom = linkHandler {
            custom(&state, link.id, &tx)
        } else if let validated = try? checkOpenUrl(link.id) {
            pendingWindowRequests.openUrls.append((validated, false))
        }
        applyTx(&tx, why: CommitWhy.PRESS)
        if dirty { performCommit() }
    }
}
