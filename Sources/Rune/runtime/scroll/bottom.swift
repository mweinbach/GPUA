// Ported from: crates/rune/src/runtime/scroll/bottom.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Stick-to-bottom (`ScrollSpec.stickBottom`) & programmatic `scrollToBottom` behavior.

let STICK_BOTTOM_SLOP: Float = 4.0

extension Runtime {
    public func scrollToBottom(_ key: String, animated: Bool = true) {
        ensureClean()
        guard let sIdx = findScrollNodeIndex(key) else { return }
        let sKey = nodes[sIdx].key ?? nodes[sIdx].path
        var entry = scrolls[sKey] ?? ScrollState()
        entry.stuckBottom = true
        entry.target = entry.maxScroll
        if !animated || reducedMotion {
            entry.offset = entry.maxScroll
            entry.vel = 0.0
            entry.spring = nil
            entry.hoverHeld = false
        } else {
            let sp = tok.motion.GLIDE
            entry.spring = sp
            if abs(entry.maxScroll - entry.offset) > 0.5 {
                entry.vel = retargetScrollVelocity(sp, offset: entry.offset, vel: entry.vel, to: entry.maxScroll)
                entry.hoverHeld = true
            } else {
                entry.offset = entry.maxScroll
                entry.vel = 0.0
                entry.hoverHeld = false
            }
        }
        scrolls[sKey] = entry
        refreshPresentedGeometries()
    }

    public func isStuckToBottom(_ key: String) -> Bool {
        ensureClean()
        guard let sIdx = findScrollNodeIndex(key) else { return false }
        let sKey = nodes[sIdx].key ?? nodes[sIdx].path
        guard let entry = scrolls[sKey] else { return true }
        return entry.stuckBottom || (entry.maxScroll - entry.offset <= STICK_BOTTOM_SLOP)
    }
}
