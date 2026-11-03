// Ported from: crates/rune/src/runtime/scroll/watch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scroll position watch registration and change notification (`ScrollPos`).

struct ScrollWatchEntry<S> {
    var key: String
    var lastPos: ScrollPos?
    var callback: (inout S, ScrollPos, inout Tx) -> Void
}

extension Runtime {
    public func watchScroll(_ key: String, _ callback: @escaping (inout S, ScrollPos, inout Tx) -> Void) {
        scrollWatches.append(ScrollWatchEntry(key: key, lastPos: nil, callback: callback))
    }

    func notifyScrollWatches() {
        guard !scrollWatches.isEmpty else { return }
        for i in scrollWatches.indices {
            let key = scrollWatches[i].key
            guard let idx = findScrollNodeIndex(key) else { continue }
            let sKey = nodes[idx].key ?? nodes[idx].path
            let pos = ScrollPos(
                offset: [scrollsX[sKey]?.offset ?? 0.0, scrolls[sKey]?.offset ?? 0.0],
                max: [scrollsX[sKey]?.maxScroll ?? 0.0, scrolls[sKey]?.maxScroll ?? 0.0]
            )
            if scrollWatches[i].lastPos != pos {
                scrollWatches[i].lastPos = pos
                var tx = newTx(fromInput: false)
                scrollWatches[i].callback(&state, pos, &tx)
                applyTx(&tx, why: CommitWhy.SCROLL)
            }
        }
    }
}
