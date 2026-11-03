// Ported from: crates/rune/src/runtime/scroll/reveal.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scroll-into-view (`Tx.scrollIntoView`, `Tx.scrollCenter`) and page scrolling (`PageUp` / `PageDown`).

import RuneMotion

public extension Tx {
    mutating func scrollToWith(_ key: String, _ y: Float, _ spring: Spring) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: y, animated: true, spring: spring))
        scrollOffsetAnchors.append(false)
    }

    mutating func scrollToInstant(_ key: String, _ y: Float) {
        scrollOffsetRequests.append(ScrollRequest(key: key, x: nil, y: y, animated: false, spring: nil))
        scrollOffsetAnchors.append(false)
    }
}

extension Runtime {
    func drainPostCommitScrollRequests() {
        for req in queuedScrollOffsets {
            if let y = req.y {
                setScrollOffset(req.key, y, animated: req.animated, spring: req.spring)
            }
            if let x = req.x {
                setScrollOffsetX(req.key, x, animated: req.animated, spring: req.spring)
            }
        }
        queuedScrollOffsets.removeAll(keepingCapacity: true)

        for (key, animated) in queuedScrollBottoms {
            scrollToBottom(key, animated: animated)
        }
        queuedScrollBottoms.removeAll(keepingCapacity: true)

        for (key, pages) in queuedScrollPages {
            scrollByPages(key, pages: pages)
        }
        queuedScrollPages.removeAll(keepingCapacity: true)

        for rev in queuedScrollReveals {
            revealTargetInScroll(rev.key, center: rev.center, animated: rev.animated)
        }
        queuedScrollReveals.removeAll(keepingCapacity: true)

        for key in queuedKeepOnScreen {
            revealTargetInScroll(key, center: false, animated: true)
        }
        queuedKeepOnScreen.removeAll(keepingCapacity: true)
    }

    public func scrollIntoView(_ key: String, center: Bool = false, animated: Bool = true) {
        ensureClean()
        revealTargetInScroll(key, center: center, animated: animated)
        refreshPresentedGeometries()
    }

    func revealTargetInScroll(_ key: String, center: Bool, animated: Bool) {
        guard let targetIdx = keyIndex.findMatching(key, in: nodes),
              let scrollIdx = nodes[targetIdx].scrollAncestor
        else { return }

        let sNode = nodes[scrollIdx]
        let sKey = sNode.key ?? sNode.path
        guard var entry = scrolls[sKey] else { return }

        let targetTop = nodes[targetIdx].layoutRect[1] - sNode.layoutRect[1]
        let targetH = nodes[targetIdx].layoutRect[3]
        let targetBottom = targetTop + targetH
        let vpH = entry.viewportH

        var desired = entry.target
        if center {
            desired = targetTop + targetH * 0.5 - vpH * 0.5
        } else {
            if targetTop < desired {
                desired = targetTop
            } else if targetBottom > desired + vpH {
                desired = targetBottom - vpH
            }
        }
        let clamped = min(max(desired, 0.0), entry.maxScroll)
        entry.target = clamped
        entry.stuckBottom = entry.stickBottomSpec && (entry.maxScroll - clamped <= STICK_BOTTOM_SLOP)
        if !animated || reducedMotion {
            entry.offset = clamped
            entry.vel = 0.0
            entry.hoverHeld = false
        } else {
            let sp = tok.motion.GLIDE
            entry.spring = sp
            if abs(clamped - entry.offset) > 0.5 {
                entry.vel = retargetScrollVelocity(sp, offset: entry.offset, vel: entry.vel, to: clamped)
                entry.hoverHeld = true
            } else {
                entry.offset = clamped
                entry.vel = 0.0
                entry.hoverHeld = false
            }
        }
        scrolls[sKey] = entry
    }

    func scrollByPages(_ key: String, pages: Int32) {
        guard let idx = findScrollNodeIndex(key) else { return }
        let sKey = nodes[idx].key ?? nodes[idx].path
        guard var entry = scrolls[sKey] else { return }
        let step = max(entry.viewportH * 0.9, 1.0) * Float(pages)
        let next = min(max(entry.offset + step, 0.0), entry.maxScroll)
        entry.offset = next
        entry.target = next
        entry.vel = 0.0
        entry.spring = nil
        entry.direct = true
        entry.stuckBottom = entry.stickBottomSpec && (entry.maxScroll - next <= 0.5)
        scrolls[sKey] = entry
    }
}
