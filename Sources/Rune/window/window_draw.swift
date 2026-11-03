// Ported from: crates/rune/src/window/draw.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window frame encoding, surface acquire handling, deduplication, and `FrameReports` dispatch (`crates/rune/src/window/draw.rs`).

extension Host {
    /// Executes one render/present pass on `win` (or `coveredStep` when covered).
    /// Returns `true` if another frame should be scheduled immediately.
    @discardableResult
    func drawWindow(now: RuneInstant = .now()) -> Bool {
        guard let win else {
            clock.pause()
            return false
        }

        // Launcher warm-up renders hidden frames at alpha 0 even before `visible == true`.
        let warmingHidden = !win.visible && win.launchDrawables.isWarming
        if win.isCovered && !warmingHidden {
            win.native.setDisplayLinkPaused(true)
            return coveredStep(rt: rt, clock: &clock, firstFrame: &win.firstFrame, now: now)
        }

        win.ensureGpu()
        win.setSrgbBlend(rt.srgbBlend)

        let dt = drainFrame(clock: &clock, rt: rt, now: now)
        let (instances, layers, stats) = rt.hostFrame(dt)

        // Optional fit-content-height resize
        if fitContentHeight, let rootElem = rt.hostElements().first {
            let contentH = max(rootElem.rect[3], 1.0)
            let scale = max(Float(win.window.scaleFactor()), 1.0)
            let targetPhysH = max(UInt32((contentH * scale).rounded()), 1)
            let curSize = win.window.innerSize()
            if curSize.1 != targetPhysH {
                win.resize((curSize.0, targetPhysH))
            }
        }

        let size = win.window.innerSize()
        let clearColor: Color = options.transparent
            ? .TRANSPARENT
            : (rt.hostElements().first?.fill ?? Color(0.08, 0.08, 0.09, 1.0))
        syncPlatform(win: win, rt: rt, chrome: chrome, options: options)

        if let encodedHook = reports.encoded {
            let summary = WindowFrameEncoded(
                size: size,
                scale: rt.env.scale,
                dt: dt,
                instances: stats.instances,
                layers: stats.layers,
                animating: stats.animating
            )
            encodedHook(&rt.state, summary)
        }

        // Deduplicate unchanged idle frames (unless warming hidden launcher drawables or waiting on first frame)
        if !warmingHidden
            && !win.firstFrame.isWaiting
            && compositor == nil
            && win.presented.unchanged(
                size: size,
                clear: clearColor,
                rt: rt,
                instances: instances,
                layers: layers,
                stats: stats
            )
        {
            reports.drawn?(&rt.state, .skipped)
            clock.pause()
            win.native.setDisplayLinkPaused(true)
            return false
        }

        // Acquire swapchain texture & handle suboptimal / occluded / timeout / outdated outcomes
        let firstStatus = win.nextAcquireStatus()
        let acquireOutcome = resolveSurfaceAcquire(
            firstStatus,
            retryAcquire: { win.nextAcquireStatus() },
            reconfigure: { configureWindowSurface(&win.config, &win.surfaceMeter) },
            meter: &win.surfaceMeter
        )

        switch acquireOutcome {
        case .success(let suboptimal):
            win.occluded = false
            win.occludedRetry = nil

            if var comp = compositor {
                let compFrame = HostCompositorFrame(
                    size: size,
                    scale: rt.env.scale,
                    time: rt.t,
                    effectSlots: rt.hostEffectSlots()
                )
                comp.compose(compFrame)
                compositor = comp
            }

            win.window.prePresentNotify()
            win.surfaceMeter.presented(suboptimal)
            win.drawCount += 1

            win.presented.settle(
                size: size,
                clear: clearColor,
                rt: rt,
                instances: instances,
                layers: layers,
                stats: stats
            )

            if win.firstFrame.markReady() {
                win.window.setVisible(win.visible)
                if !readyFired {
                    readyFired = true
                    windowHandle.markReady(true)
                    onReadyHook?(windowHandle)
                    fireReadySignalIfArmed()
                }
            } else if !readyFired && (win.visible || warmingHidden) {
                readyFired = true
                windowHandle.markReady(true)
                onReadyHook?(windowHandle)
                fireReadySignalIfArmed()
            }

            windowHandle.publishStats(win.surfaceMeter.snapshot())
            reports.drawn?(&rt.state, .presented(suboptimal: suboptimal))
            reports.drawnRuntime?(rt)

            if warmingHidden {
                let moreWarmup = win.launchDrawables.presented()
                if !moreWarmup && !win.visible {
                    rt.hostSetLiveVisible(false)
                    clock.pause()
                    win.native.setDisplayLinkPaused(true)
                    return false
                }
                return moreWarmup
            }

            let keepGoing = stats.animating || rt.hostStale()
            if !keepGoing {
                clock.pause()
                win.native.setDisplayLinkPaused(true)
            } else {
                win.native.setDisplayLinkPaused(false)
            }
            return keepGoing

        case .failure(let missed):
            win.presented.invalidate()
            switch missed {
            case .occluded:
                win.occluded = true
                floatOnOpenRelease(&win.floatingOnOpen, window: win.window)
                _ = nextOccludedRetry(&win.occludedRetry)
                reports.drawn?(&rt.state, .missed("occluded"))
                win.native.setDisplayLinkPaused(true)
                return false
            case .timeout:
                reports.drawn?(&rt.state, .missed("timeout"))
                return true
            case .reconfigured:
                reports.drawn?(&rt.state, .missed("reconfigured"))
                return true
            case .skip:
                reports.drawn?(&rt.state, .missed("other"))
                return false
            }
        }
    }
}

func fireReadySignalIfArmed() {
    #if !os(WASI)
    readySignalReady()
    #endif
}
