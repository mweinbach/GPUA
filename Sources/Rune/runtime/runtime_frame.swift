// Ported from: crates/rune/src/runtime/frame.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Frame loop, clocks, wake deadlines, viewport updates, focus transitions, and motion/paint stepping.

import RuneMotion

extension Runtime {
    /// Update viewport dimensions in logical points and display pixel scale.
    public func setViewport(_ newViewport: (Float, Float), _ scale: Float) {
        if fitHeight && windowResting && abs((fitAsked ?? viewport.1) - newViewport.1) > 0.5 {
            fitAsked = nil
            viewportStepped = false
            markDirty(CommitWhy.RELAYOUT)
        }
        if changeViewport(newViewport, scale) {
            viewportStepped = false
        }
    }

    public func setViewport(_ width: Float, _ height: Float) {
        setViewport((width, height), env.scale)
    }

    /// Update viewport for one step of the window's own resize animation without landing running springs/flights.
    public func stepViewport(_ newViewport: (Float, Float), _ scale: Float) {
        let fresh = (pendingCommitWhy & CommitWhy.RELAYOUT) == 0
        if changeViewport(newViewport, scale) && fresh {
            viewportStepped = true
        }
    }

    @discardableResult
    private func changeViewport(_ newViewport: (Float, Float), _ scale: Float) -> Bool {
        if fitHeight && newViewport.0 == viewport.0 && scale == env.scale {
            viewport = newViewport
            return false
        }
        let changed = newViewport != viewport || scale != env.scale
        if changed {
            var why = CommitWhy.RELAYOUT
            if scale != env.scale {
                activeTextFlights.removeAll()
                textLayoutCache.removeAll()
                why |= CommitWhy.ENV
            }
            viewport = newViewport
            env.scale = scale
            scene.setPixelScale(max(scale, 0.001))
            markDirty(why)
        }
        return changed
    }

    /// Notify the runtime of a native window focus transition.
    public func windowFocus(_ focused: Bool) {
        guard windowFocused != focused else { return }
        windowFocused = focused
        if !focused {
            pressedPath = nil
            pressedLinkTarget = nil
            activeDragNodePath = nil
            activeInputDragPath = nil
            isDraggingTextSelection = false
            heldModifierKeys.removeAll()
            if !hoveredPaths.isEmpty {
                hoveredPaths.removeAll()
                markDirty(CommitWhy.HOVER)
            }
            clearHelpHover()
        }
    }

    /// Mark app state dirty from outside a handler so the next frame re-runs `view`.
    public func invalidate() {
        markDirty(CommitWhy.UPDATE)
    }

    /// Whether the last committed frame is out of date.
    public func needsCommit() -> Bool {
        dirty
            || !queuedScrollReveals.isEmpty
            || !queuedScrollBottoms.isEmpty
            || !queuedScrollPages.isEmpty
            || !queuedScrollOffsets.isEmpty
            || !queuedTextFlights.isEmpty
    }

    /// Whether the last drawn frame no longer matches current state or viewport.
    public func stale() -> Bool {
        needsCommit()
    }

    /// Next requested wake deadline on the unscaled app `clock`, or `nil` when idle indefinitely.
    public func wakeDeadline() -> Double? {
        switch (timerWakes.deadlines.first, nextLoopWakeDeadline()) {
        case (let a?, let b?): return min(a, b)
        case (let a?, nil): return a
        case (nil, let b?): return b
        case (nil, nil): return nil
        }
    }

    /// Run `poll` and due timers for a hidden window without building or drawing; leaves changes dirty for the next frame.
    @discardableResult
    public func pollHidden() -> Bool {
        for w in pendingWakes {
            timerWakes.schedule(now: clock, after: w)
        }
        pendingWakes.removeAll()
        _ = timerWakes.fireDue(now: clock)
        guard let pollFn = poll else { return stale() }
        var tx = newTx(fromInput: false)
        let changed = pollFn(&state, clock, &tx)
        if changed {
            applyTx(&tx, why: CommitWhy.POLL)
        } else {
            var sideTx = tx
            sideTx.liveOnlyFlag = true
            applyTx(&sideTx, why: 0)
        }
        for w in pendingWakes {
            timerWakes.schedule(now: clock, after: w)
        }
        pendingWakes.removeAll()
        return stale()
    }

    /// Build what changed while a `fitHeight` window was hidden before ordering it on screen.
    @discardableResult
    public func buildForShow() -> Bool {
        guard fitHeight, hasCommittedOnce, stale() else { return false }
        pendingSettleCommit = true
        markDirty(CommitWhy.UPDATE)
        hiddenTimerFrame()
        return true
    }

    func hiddenTimerFrame() {
        _ = frame(0.0)
    }

    private func nextTimerSubstepTarget(toward target: Double) -> Double? {
        guard let deadline = wakeDeadline() else { return nil }
        let at = max(deadline, clock + (1.0 / 60.0))
        return at < target - 1e-3 ? at : nil
    }

    /// Advance animation time by `dt` seconds, run due timers & `poll`, commit if state changed,
    /// step `Scene`, growth, scroll, reveals, and loops, and build GPU `[Instance]`s.
    @discardableResult
    public func frame(_ dt: Double = 1.0 / 60.0) -> ([Instance], [LayerSpec]) {
        let clampedDt = max(dt, 0.0)
        let target = clock + clampedDt
        if pendingWakes.isEmpty && nextTimerSubstepTarget(toward: target) != nil {
            while let at = nextTimerSubstepTarget(toward: target) {
                let step = max(0.0, at - clock)
                _ = frameSingleStep(step)
            }
            let remaining = max(0.0, target - clock)
            return frameSingleStep(remaining)
        }
        return frameSingleStep(clampedDt)
    }

    private func frameSingleStep(_ clampedDt: Double) -> ([Instance], [LayerSpec]) {
        let shapedBefore = text.shaped
        commitsThisFrame = 0
        commitWhy = 0
        settled = false

        clock += clampedDt
        let scaledDt = clampedDt * Double(max(timeScale, 0.0))
        lastDt = scaledDt > 0.0 ? scaledDt : (1.0 / 60.0)
        frameIndex &+= 1

        // Schedule any `wakeAfter` requests queued by handlers/updates since the last frame
        if !pendingWakes.isEmpty {
            for w in pendingWakes {
                timerWakes.schedule(now: clock, after: w)
            }
            pendingWakes.removeAll()
        }

        // 1. Fire scheduled `Tx.wakeAfter` timers & check tooltip delay
        let timerFired = timerWakes.fireDue(now: clock)
        checkHelpTooltipDue()

        // 2. Run per-frame `poll` callback
        if let pollFn = poll {
            var tx = newTx(fromInput: false)
            let changed = pollFn(&state, clock, &tx)
            if changed {
                applyTx(&tx, why: CommitWhy.POLL)
            } else {
                // Honour side-effect requests on `tx` even when `poll` returned `false`
                var sideTx = tx
                sideTx.liveOnlyFlag = true
                applyTx(&sideTx, why: 0)
            }
            if !pendingWakes.isEmpty {
                for w in pendingWakes {
                    timerWakes.schedule(now: clock, after: w)
                }
                pendingWakes.removeAll()
            }
        } else if timerFired {
            // Wake timers without a poll callback may still wake live bindings or tooltips
        }

        // 3. Clear coalesced `Live` wake before commit/latching so concurrent publications aren't lost
        if windowVisible {
            _ = liveWake.takePending()
        }
        endUnseenExits()

        // 4. Commit view & layout at pre-step animation time `t` so newly started tracks advance by `scaledDt` this frame
        let settledBeforeCommit = pendingSettleCommit
        if dirty || !hasCommittedOnce {
            performCommit()
        } else if !queuedScrollReveals.isEmpty
            || !queuedScrollBottoms.isEmpty
            || !queuedScrollPages.isEmpty
            || !queuedScrollOffsets.isEmpty
        {
            drainPostCommitScrollRequests()
        }
        settled = settledBeforeCommit

        // Latch `Live` and `LiveText` bindings into the scene before advancing `t`
        scene.setTime(t)
        let tweenAnimating = pollLiveBindings()

        // 5. Advance animation clock `t` and step `Scene`, loops, growth rows, scroll springs, and streaming reveals
        t += scaledDt
        scene.setTime(t)
        let loopsAwake = stepLoops()
        let sceneOut = scene.frameAt(t)
        if !sceneOut.exited.isEmpty {
            let exitedSet = Set(sceneOut.exited)
            exitingNodes.removeAll { exitedSet.contains($0.nodeId) || !scene.contains($0.nodeId) }
            for eid in exitedSet {
                if let removed = liveNodeBindings.removeValue(forKey: eid) {
                    for sub in removed.subscriptions {
                        sub.active = false
                    }
                }
            }
        }
        landGroupFades(scene, &groupFading)

        stepGrowthTracks(clampedDt)
        stepScrollSprings(clampedDt)
        stepContentSlides(Float(scaledDt))
        refreshPresentedGeometries()
        imeArea = imeCursorArea()

        // Re-evaluate hover under a stationary pointer if boxes moved (unless held by a programmatic scroll glide)
        if let (px, py) = lastPointer, activeDragNodePath == nil, !hasActiveScrollHoverHold {
            updateHoverAt(px, py, commitIfChanged: false)
        }

        // 6. Build GPU instances & layers
        let (builtInstances, builtLayers, glyphCount) = buildFramePaint()

        // 7. Compute `animating` flag & update `FrameStats`
        let sceneAnimating = sceneOut.animating
        let growthAnimating = hasMovingGrowthTracks()
        let scrollAnimating = scrolling()
        let revealAnimating = hasActiveReveals()
        let flightsAnimating = !activeTextFlights.isEmpty
        let snapEasing = pixelSnap.easing()

        let rawAnimating = sceneAnimating
            || growthAnimating
            || scrollAnimating
            || revealAnimating
            || loopsAwake
            || flightsAnimating
            || snapEasing
            || tweenAnimating
        animating = rawAnimating && timeScale > 0.0

        stats = FrameStats(
            instances: builtInstances.count,
            layers: builtLayers.count,
            animating: animating,
            commits: Int(commitsThisFrame),
            glyphs: glyphCount,
            shaped: Int(text.shaped &- shapedBefore)
        )
        idleMeter.record(animating: animating)

        return (builtInstances, builtLayers)
    }
}
