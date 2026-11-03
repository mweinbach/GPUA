// Ported from: crates/rune/src/runtime/motion/content_slide.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Streaming / reveal content progress (`TextSpec.reveal`, `streamingFlag`) per node path.

extension Runtime {
    func stepContentSlides(_ dt: Float) {
        guard dt > 0.0 else { return }
        for i in nodes.indices {
            guard let ts = nodes[i].textSpec else { continue }
            let path = nodes[i].path
            if ts.reveal >= 0.0 {
                var state = reveals[path] ?? RevealState(progress: ts.reveal, target: ts.reveal, lastTextLen: ts.content.utf8.count)
                state.target = min(max(ts.reveal, 0.0), 1.0)
                let diff = state.target - state.progress
                if abs(diff) > 1e-4 {
                    state.progress += diff * min(1.0, dt * 16.0)
                } else {
                    state.progress = state.target
                }
                reveals[path] = state
            } else if nodes[i].streaming {
                let curLen = ts.content.utf8.count
                var state = reveals[path] ?? RevealState(progress: 1.0, target: 1.0, lastTextLen: curLen)
                if curLen > state.lastTextLen && state.lastTextLen > 0 {
                    let frac = Float(state.lastTextLen) / Float(max(curLen, 1))
                    state.progress = min(state.progress, frac)
                    state.target = 1.0
                }
                state.lastTextLen = curLen
                if state.progress < 0.999 {
                    state.progress = min(1.0, state.progress + dt * 6.0)
                } else {
                    state.progress = 1.0
                }
                reveals[path] = state
            }
        }
    }

    func activeRevealProgress(for nodeIdx: Int) -> Float {
        guard nodes.indices.contains(nodeIdx), let ts = nodes[nodeIdx].textSpec else { return 1.0 }
        if ts.reveal >= 0.0 {
            return reveals[nodes[nodeIdx].path]?.progress ?? min(max(ts.reveal, 0.0), 1.0)
        }
        if nodes[nodeIdx].streaming {
            return reveals[nodes[nodeIdx].path]?.progress ?? 1.0
        }
        return 1.0
    }

    func hasActiveReveals() -> Bool {
        reveals.values.contains { abs($0.target - $0.progress) > 1e-3 }
    }
}
