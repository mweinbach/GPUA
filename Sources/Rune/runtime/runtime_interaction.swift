// Ported from: crates/rune/src/runtime/interaction.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! High-level interaction entrypoints on `Runtime`: `find`, `tap`, `wheel`, `applyTx`, and `withStates`.

import RuneMotion

extension Runtime {
    func withStates<R>(_ body: (States) -> R) -> R {
        let states = States.one(state)
        let res = body(states)
        if let updated = states.app as? S {
            state = updated
        }
        return res
    }

    func makeStates() -> States {
        States.one(state)
    }

    func commitStates(_ states: States) {
        if let updated = states.app as? S {
            state = updated
        }
    }

    func newTx(fromInput: Bool = true) -> Tx {
        var tx = Tx()
        tx.focusedKey = currentFocusedKey()
        tx.heldMods = heldMods
        tx.inputArrivalTime = fromInput ? currentInputTime() : nil
        tx.currentSelection = currentTextSelection()
        if scene.tracing() {
            tx.traceCalls = TraceCalls()
        }
        return tx
    }

    func applyTx(_ tx: inout Tx, why: UInt16) {
        if tx.instantFlag {
            pendingInstantCommit = true
        }
        if tx.settleFlag {
            pendingSettleCommit = true
        }
        if let sp = tx.motionSpring {
            pendingMotionSpring = sp
        }
        if let mc = tx.motionCurveAnim {
            pendingMotionCurve = mc
        } else if tx.motionSpring != nil {
            pendingMotionCurve = nil
        }

        if let wfr = tx.windowFrameRequest {
            let canAnimate = wfr.size != nil && wfr.animate && !tx.instantFlag && !reducedMotion
            let frameReq = FrameRequest(
                size: wfr.size,
                animate: canAnimate,
                spring: canAnimate ? (tx.motionSpring ?? tok.motion.DEFAULT) : nil,
                center: wfr.center
            )
            windowFrame = (windowFrame ?? FrameRequest()).merge(frameReq)
        }
        if let cs = tx.colorMotionSpring {
            pendingColorSpring = cs
        }
        if tx.relayoutFlag {
            textLayoutCache.removeAll()
        }

        // Focus & blur requests
        if tx.blurFlag {
            setFocusedPath(nil, visible: false)
        } else if tx.focusedKey != currentFocusedKey(), let reqKey = tx.focusedKey {
            focusByKey(reqKey, visible: focusVisible)
        }

        // Clipboard & window requests
        if tx.clearSecretFlag {
            if pendingWindowRequests.clipboardWrite?.isSecret() == true {
                pendingWindowRequests.clipboardWrite = nil
            }
            pendingWindowRequests.clearSecret = true
        }
        if let cw = tx.copyWrite {
            pendingWindowRequests.clipboardWrite = cw
        }
        if tx.pasteFlag {
            pendingWindowRequests.pasteRequested = true
        }
        if let sh = tx.shellRequest {
            if let cur = pendingWindowRequests.shell {
                pendingWindowRequests.shell = max(cur, sh)
            } else {
                pendingWindowRequests.shell = sh
            }
        }
        if tx.minimizeFlag {
            pendingWindowRequests.minimize = true
        }
        if let title = tx.titleString {
            pendingWindowRequests.title = title
        }
        for u in tx.openUrls {
            pendingWindowRequests.openUrls.append((u.url, u.sameTab))
        }
        if let tok = tx.shortcutActivationToken {
            pendingWindowRequests.shortcutActivationToken = tok
        }

        // System settings inside Tx
        if let srgb = tx.srgbBlendRequest {
            setSrgbBlend(srgb)
        }
        if let smooth = tx.fontSmoothingRequest {
            setFontSmoothing(smooth)
        }
        if let (sans, mono) = tx.fontFamiliesRequest {
            setFontFamilies(sans, mono)
        }

        // Flights & launches
        for pair in tx.textFlights {
            queuedTextFlights.append(pair)
        }
        for (srcKey, dstKey) in tx.launches {
            if let idx = keyIndex.findMatching(srcKey, in: nodes) {
                let pr = nodes[idx].presentedRect
                pendingLaunchRects[dstKey] = RuneMotion.Rect(pr[0], pr[1], pr[2], pr[3])
            }
        }

        // Scroll requests
        queuedScrollReveals.append(contentsOf: tx.scrollToRequests)
        queuedScrollBottoms.append(contentsOf: tx.scrollBottomRequests)
        queuedScrollPages.append(contentsOf: tx.scrollPagesRequests)
        queuedScrollOffsets.append(contentsOf: tx.scrollOffsetRequests)
        queuedKeepOnScreen.append(contentsOf: tx.keepOnScreenKeys)

        // Timers (staged for scheduling on the next frame or hidden poll clock)
        for w in tx.wakes {
            pendingWakes.append(w)
        }

        // Selection requests
        if let selReq = tx.selectRequest {
            applySelectRequest(selReq)
        }

        // Trace events
        if let tc = tx.traceCalls {
            for ev in tc.events {
                eventLog.push(t: t, frame: frameIndex, kind: "trace", detail: ev)
            }
        }

        if !tx.liveOnlyFlag {
            markDirty(why)
        } else if why != 0 {
            liveOnlySkips &+= 1
            liveDirty = true
        }
    }

    /// Return the center `(x, y)` of the element matching `key` in window space, if mounted and non-empty.
    public func find(_ key: String) -> (Float, Float)? {
        ensureClean()
        guard let idx = keyIndex.findMatching(key, in: nodes) else { return nil }
        let r = nodes[idx].presentedRect
        return (r[0] + r[2] * 0.5, r[1] + r[3] * 0.5)
    }

    /// Return the presented `[x, y, w, h]` rect of the element matching `key`, if mounted.
    public func rectOf(_ key: String) -> [Float]? {
        ensureClean()
        guard let idx = keyIndex.findMatching(key, in: nodes) else { return nil }
        return nodes[idx].presentedRect
    }

    /// Perform a primary click at the center of `key`; returns `true` if found.
    @discardableResult
    public func click(_ key: String) -> Bool {
        guard let (x, y) = find(key) else { return false }
        pointerMove(x, y)
        pointerDown(x, y)
        pointerUp(x, y)
        return true
    }

    /// Dispatch a wheel scroll event at `(x, y)` with `(dx, dy)` pixel/line deltas.
    public func wheel(_ ev: WheelEvent) {
        ensureClean()
        heldMods = ev.mods
        lastPointer = (ev.x, ev.y)
        clearScrollHoverHolds()
        if let pp = pressedPath, let pIdx = keyIndex.nodeByPath(pp) {
            pressedPath = nil
            if reducedMotion {
                scene.set(nodes[pIdx].nodeId, P_PRESS, 0.0)
            } else {
                scene.animate(nodes[pIdx].nodeId, P_PRESS, 0.0, tok.motion.INSTANT)
            }
        }
        eventLog.push(t: t, frame: frameIndex, kind: "wheel", detail: "\(ev.dx),\(ev.dy)")

        // Find deepest scroll container under `(ev.x, ev.y)`
        guard let hitIdx = hitTestScrollContainer(ev.x, ev.y) else { return }
        let sNode = nodes[hitIdx]
        let sKey = sNode.key ?? sNode.path

        if abs(ev.dy) > 1e-4, var entry = scrolls[sKey] {
            let deltaY = -ev.dy
            let nextTarget = min(max(entry.target + deltaY, 0.0), entry.maxScroll)
            entry.target = nextTarget
            entry.wheelTime = t
            entry.thumbVisibleUntil = t + 1.2
            entry.stuckBottom = entry.stickBottomSpec && (entry.maxScroll - nextTarget <= STICK_BOTTOM_SLOP)
            if ev.precise || reducedMotion {
                entry.offset = nextTarget
                entry.vel = 0.0
                entry.spring = nil
                entry.direct = true
            } else {
                entry.spring = tok.motion.SNAP
            }
            scrolls[sKey] = entry
        }

        if abs(ev.dx) > 1e-4, var xEntry = scrollsX[sKey] {
            let deltaX = -ev.dx
            let nextTargetX = min(max(xEntry.target + deltaX, 0.0), xEntry.maxScroll)
            xEntry.target = nextTargetX
            if ev.precise || reducedMotion {
                xEntry.offset = nextTargetX
                xEntry.vel = 0.0
                xEntry.spring = nil
            } else {
                xEntry.spring = tok.motion.SNAP
            }
            scrollsX[sKey] = xEntry
        }

        refreshPresentedGeometries()
        updateHoverAt(ev.x, ev.y, commitIfChanged: false)
        if lastCommittedLayoutReadKeys.contains(where: { $0.hasPrefix("@win:") })
            || lastCommittedLayoutPredicates.contains(where: { $0.windowSpace })
        {
            markDirty(CommitWhy.SCROLL)
        }
        notifyScrollWatches()
    }

    public func wheel(_ x: Float, _ y: Float, _ dy: Float) {
        wheel(WheelEvent(x: x, y: y, dx: 0.0, dy: dy, precise: true, mods: heldMods))
    }

    public func wheel(_ x: Float, _ y: Float, _ dx: Float, _ dy: Float, precise: Bool = true) {
        wheel(WheelEvent(x: x, y: y, dx: dx, dy: dy, precise: precise, mods: heldMods))
    }
}
