// Ported from: crates/rune/src/runtime/virtual/selection_collect.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Harvest selectable text from mounted virtualized rows into `VirtualSelectionStore`.

extension Runtime {
    func collectVirtualSelectableTexts() {
        for i in nodes.indices {
            guard let spec = nodes[i].textSpec, spec.selectable else { continue }
            guard let scrollIdx = nodes[i].scrollAncestor,
                  let scrollKey = nodes[scrollIdx].key
            else { continue }
            // Record mounted selectable text under its scroll ancestor in visual order.
            let itemKey = nodes[i].key ?? nodes[i].path
            virtualSelection.record(
                VirtualTextEntry(
                    scrollKey: scrollKey,
                    itemIndex: i,
                    itemKey: itemKey,
                    path: nodes[i].path,
                    text: spec.content
                )
            )
        }
    }
}
