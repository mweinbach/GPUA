// Ported from: crates/rune/src/runtime/scroll/x.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Horizontal scroll offsets (`scrollOffsetX`, `setScrollOffsetX`, wheel `dx`, and spring stepping).

import RuneMotion

extension Runtime {
    public func scrollOffsetX(_ key: String) -> Float {
        ensureClean()
        guard let idx = findScrollNodeIndex(key) else { return 0.0 }
        let sKey = nodes[idx].key ?? nodes[idx].path
        return scrollsX[sKey]?.offset ?? 0.0
    }

    public func setScrollOffsetX(_ key: String, _ x: Float, animated: Bool = false, spring: Spring? = nil) {
        ensureClean()
        guard let idx = findScrollNodeIndex(key) else { return }
        let sKey = nodes[idx].key ?? nodes[idx].path
        var entry = scrollsX[sKey] ?? ScrollXState()
        let clamped = min(max(x, 0.0), entry.maxScroll)
        entry.target = clamped
        if !animated || reducedMotion {
            entry.offset = clamped
            entry.vel = 0.0
            entry.spring = nil
        } else {
            entry.spring = spring ?? tok.motion.GLIDE
        }
        scrollsX[sKey] = entry
        refreshPresentedGeometries()
    }

    func stepScrollXSprings(_ dtF: Float) {
        for k in Array(scrollsX.keys) {
            guard var s = scrollsX[k] else { continue }
            if reducedMotion {
                s.offset = s.target
                s.vel = 0.0
                s.overscroll = 0.0
                scrollsX[k] = s
                continue
            }
            if s.isMoving {
                let sp = s.spring ?? tok.motion.GLIDE
                let (nextX, nextV) = sp.sample(s.offset, s.vel, s.target, dtF)
                if abs(s.target - nextX) < 0.1 && abs(nextV) < 0.5 {
                    s.offset = s.target
                    s.vel = 0.0
                } else {
                    s.offset = nextX
                    s.vel = nextV
                }
                s.overscroll = 0.0
                scrollsX[k] = s
            }
        }
    }
}
