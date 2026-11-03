// Ported from: crates/rune/src/runtime/scroll/offset.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Vertical scroll container measurement, spring stepping, retargeting, and wheel/programmatic offsets.

import RuneMotion

func retargetScrollVelocity(_ spring: Spring, offset: Float, vel: Float, to: Float) -> Float {
    let d = offset - to
    let most = spring.omega() * abs(d)
    if vel * d < 0.0 && abs(vel) > most {
        return -(d >= 0.0 ? 1.0 : -1.0) * most
    }
    return vel
}

extension Runtime {
    func clearScrollHoverHolds() {
        for k in Array(scrolls.keys) where scrolls[k]?.hoverHeld == true {
            scrolls[k]?.hoverHeld = false
        }
    }

    var hasActiveScrollHoverHold: Bool {
        scrolls.values.contains { $0.hoverHeld && $0.isMoving }
    }
    func findScrollNodeIndex(_ key: String) -> Int? {
        if let idx = keyIndex.findMatching(key, in: nodes), nodes[idx].scrollSpec != nil {
            return idx
        }
        return nodes.indices.first { nodes[$0].scrollSpec != nil && selectsKeyPath(key, nodes[$0].path, nodes[$0].key) }
    }

    public func scrollOffset(_ key: String) -> Float {
        ensureClean()
        guard let idx = findScrollNodeIndex(key) else { return 0.0 }
        let sKey = nodes[idx].key ?? nodes[idx].path
        return scrolls[sKey]?.offset ?? 0.0
    }

    public func scrollPos(_ key: String) -> ScrollPos {
        ensureClean()
        guard let idx = findScrollNodeIndex(key) else { return ScrollPos() }
        let sKey = nodes[idx].key ?? nodes[idx].path
        let sy = scrolls[sKey]?.offset ?? 0.0
        let my = scrolls[sKey]?.maxScroll ?? 0.0
        let sx = scrollsX[sKey]?.offset ?? 0.0
        let mx = scrollsX[sKey]?.maxScroll ?? 0.0
        return ScrollPos(offset: [sx, sy], max: [mx, my])
    }

    public func setScrollOffset(_ key: String, _ y: Float, animated: Bool = false, spring: Spring? = nil) {
        ensureClean()
        guard let idx = findScrollNodeIndex(key) else { return }
        let sKey = nodes[idx].key ?? nodes[idx].path
        var entry = scrolls[sKey] ?? ScrollState()
        let clamped = min(max(y, 0.0), entry.maxScroll)
        entry.target = clamped
        entry.stuckBottom = entry.stickBottomSpec && (entry.maxScroll - clamped <= STICK_BOTTOM_SLOP)
        if !animated || reducedMotion {
            entry.offset = clamped
            entry.vel = 0.0
            entry.spring = nil
            entry.hoverHeld = false
            entry.direct = true
        } else {
            let sp = spring ?? tok.motion.GLIDE
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
        refreshPresentedGeometries()
    }

    public func scrolling() -> Bool {
        scrolls.values.contains { $0.isScrollingOrMoving } || scrollsX.values.contains { $0.isMoving }
    }

    private func subtreeHasMovingGrowthTrack(_ rootIdx: Int) -> Bool {
        if growthTracks[nodes[rootIdx].nodeId]?.moving() == true {
            return true
        }
        for c in nodes[rootIdx].children {
            if subtreeHasMovingGrowthTrack(c) {
                return true
            }
        }
        return false
    }

    func syncScrollContainersAfterLayout(diagnostics: inout [LayoutDiagnostic]) {
        for i in nodes.indices {
            guard let spec = nodes[i].scrollSpec else { continue }
            let sKey = nodes[i].key ?? nodes[i].path
            let vpW = nodes[i].layoutRect[2]
            let vpH = nodes[i].layoutRect[3]

            // Compute content extent from children's layout rects plus growing row heights
            var maxBottom = nodes[i].layoutRect[1]
            var maxRight = nodes[i].layoutRect[0]
            for childIdx in nodes[i].children {
                let cr = nodes[childIdx].layoutRect
                let childH: Float = {
                    if let gt = growthTracks[nodes[childIdx].nodeId], gt.moving() {
                        return gt.target
                    }
                    return cr[3]
                }()
                maxBottom = max(maxBottom, cr[1] + childH)
                maxRight = max(maxRight, cr[0] + cr[2])
            }
            let contentH = max(0.0, maxBottom - nodes[i].layoutRect[1])
            let contentW = max(0.0, maxRight - nodes[i].layoutRect[0])

            let zeroAxis = nodes[i].scrollXEnabled ? (vpW < 0.5 && contentW >= 0.5) : (vpH < 0.5 && contentH >= 0.5)
            if zeroAxis || (vpH <= 0.0 && vpW <= 0.0) {
                diagnostics.append(
                    LayoutDiagnostic(
                        kind: .unboundedScroll,
                        path: nodes[i].path,
                        message: "Scroll container '\(sKey)' laid out with zero viewport size"
                    )
                )
            }
            let maxScrollY = max(0.0, contentH - vpH)
            let maxScrollX = max(0.0, contentW - vpW)

            var entry = scrolls[sKey] ?? ScrollState(
                offset: spec.stickBottom ? maxScrollY : 0.0,
                target: spec.stickBottom ? maxScrollY : 0.0,
                vel: 0.0,
                maxScroll: maxScrollY,
                viewportH: vpH,
                contentH: contentH,
                stuckBottom: spec.stickBottom,
                stickBottomSpec: spec.stickBottom
            )
            let wasFirstMount = (scrolls[sKey] == nil)
            let prevMax = entry.maxScroll
            entry.viewportH = vpH
            entry.contentH = contentH
            entry.maxScroll = maxScrollY
            entry.stickBottomSpec = spec.stickBottom

            if wasFirstMount && spec.stickBottom {
                entry.offset = maxScrollY
                entry.target = maxScrollY
                entry.stuckBottom = true
            } else if entry.stuckBottom && maxScrollY >= prevMax {
                // Content grew while stuck to bottom: carry or spring to the new bottom!
                let wasMovingBefore = entry.isMoving
                entry.target = maxScrollY
                let hasGrowingChild = subtreeHasMovingGrowthTrack(i)
                if !hasGrowingChild && !wasMovingBefore {
                    entry.offset = maxScrollY
                } else if entry.spring == nil {
                    entry.spring = GROWTH
                }
            } else {
                let wasMovingBefore = entry.isMoving
                entry.target = min(max(entry.target, 0.0), maxScrollY)
                if !wasMovingBefore {
                    entry.offset = min(max(entry.offset, 0.0), maxScrollY)
                }
            }
            scrolls[sKey] = entry

            if nodes[i].scrollXEnabled || maxScrollX > 0.5 || scrollsX[sKey] != nil {
                var xEntry = scrollsX[sKey] ?? ScrollXState()
                let wasMovingX = xEntry.isMoving
                xEntry.viewportW = vpW
                xEntry.contentW = contentW
                xEntry.maxScroll = maxScrollX
                xEntry.target = min(max(xEntry.target, 0.0), maxScrollX)
                if !wasMovingX {
                    xEntry.offset = min(max(xEntry.offset, 0.0), maxScrollX)
                }
                scrollsX[sKey] = xEntry
            }
        }
    }

    func stepScrollSprings(_ dt: Double) {
        guard dt > 0.0 else { return }
        let dtF = Float(dt) * timeScale

        // Recompute live maxScroll when a growing child is animating its height
        for i in nodes.indices where nodes[i].scrollSpec != nil {
            let sKey = nodes[i].key ?? nodes[i].path
            guard var entry = scrolls[sKey] else { continue }
            var liveBottom = nodes[i].layoutRect[1]
            var anyChildGrowing = false
            for cIdx in nodes[i].children {
                let cr = nodes[cIdx].layoutRect
                if let gt = growthTracks[nodes[cIdx].nodeId], gt.moving() {
                    anyChildGrowing = true
                    liveBottom = max(liveBottom, cr[1] + gt.h)
                } else {
                    var stackDelta: Float = 0.0
                    for gcIdx in nodes[cIdx].children {
                        if let gt = growthTracks[nodes[gcIdx].nodeId], gt.moving() {
                            anyChildGrowing = true
                            stackDelta += (gt.h - nodes[gcIdx].layoutRect[3])
                        }
                    }
                    liveBottom = max(liveBottom, cr[1] + max(0.0, cr[3] + stackDelta))
                }
            }
            if anyChildGrowing && entry.stuckBottom {
                let liveContentH = max(0.0, liveBottom - nodes[i].layoutRect[1])
                let liveMax = max(0.0, liveContentH - entry.viewportH)
                entry.offset = liveMax
                entry.target = entry.maxScroll
                entry.vel = 0.0
                scrolls[sKey] = entry
            }
        }

        for k in Array(scrolls.keys) {
            guard var s = scrolls[k] else { continue }
            let wasDirect = s.direct
            s.scrolling = wasDirect || abs(s.vel) > 1.0
            s.direct = false
            if reducedMotion {
                s.offset = s.target
                s.vel = 0.0
                s.overscroll = 0.0
                s.hoverHeld = false
                scrolls[k] = s
                continue
            }
            if s.isMoving {
                let sp = s.spring ?? tok.motion.GLIDE
                let (d, nextV) = sp.sample(s.offset - s.target, s.vel, 0.0, dtF)
                if abs(d) < 0.1 && abs(nextV) < 4.0 {
                    s.offset = s.target
                    s.vel = 0.0
                    s.hoverHeld = false
                } else {
                    s.offset = s.target + d
                    s.vel = nextV
                }
                if abs(s.overscroll) > 0.1 {
                    let (ox, _) = tok.motion.SNAP.sample(s.overscroll, 0.0, 0.0, dtF)
                    s.overscroll = abs(ox) < 0.1 ? 0.0 : ox
                } else {
                    s.overscroll = 0.0
                }
            } else {
                s.hoverHeld = false
            }
            if s.stickBottomSpec && queuedKeepOnScreen.isEmpty && queuedScrollReveals.isEmpty
                && s.offset >= s.maxScroll - 0.5 && abs(s.vel) <= 1.0
            {
                s.stuckBottom = true
            }
            scrolls[k] = s
        }

        stepScrollXSprings(dtF)
        notifyScrollWatches()
    }
}
