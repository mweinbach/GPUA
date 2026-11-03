// Ported from: crates/rune/src/window/any_host.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Type-erased `AnyHost` conformance for `Host<S>` (`crates/rune/src/window/any_host.rs`).

#if os(macOS)
import AppKit
#endif

extension Host: AnyHost {
    var hostWindowId: UInt64? {
        win?.window.id
    }

    var isPrimaryHost: Bool {
        !secondary
    }

    var isAlive: Bool {
        if secondary {
            return false
        }
        return win != nil || keepRunning || overlays.contains(where: { $0.overlayIsVisible })
    }

    func attachHost(
        hostIndex: Int,
        wakeHost: @escaping @Sendable () -> Void,
        wakeSink: @escaping @Sendable (WakeEvent) -> Void
    ) {
        handle.connect(wakeHost)
        windowHandle.bind(slot: hostIndex, sink: wakeSink)
        rt.hostSetLiveWaker(wakeHost)
        #if os(macOS)
        let virtualGuards = !Thread.isMainThread || MainActor.assumeIsolated { NSApp == nil }
        #else
        let virtualGuards = isHeadless()
        #endif
        shortcutGuard = ShortcutGuard.attach(handle, wake: wakeHost, headless: virtualGuards, wayland: false)
        menuGuard = MenuGuard.attach(handle, headless: virtualGuards)
        popupPresenter.connect(wakeHost)
        if let setupFn = spec.setup {
            setupFn(&rt.state, wakeHost)
        }
    }

    func resumeHost(hostIndex: Int, displays: [Display]) {
        if let createdCb = onCreatedCallback {
            onCreatedCallback = nil
            createdCb(windowHandle)
        }
        if openOnStart {
            createDefaultWindow(visible: options.visible)
            if options.visible {
                _ = drawWindow()
            } else if win?.launchDrawables.isWarming == true {
                _ = drawWindow()
            } else if !readyFired {
                // Hidden/occluded non-launcher windows do not wait for a drawn frame to fire `onReady`.
                readyFired = true
                onReadyHook?(windowHandle)
                fireReadySignalIfArmed()
            }
        }
        mountPendingOverlays(hostIndex: hostIndex, displays: displays)
        _ = drainShellRequests(displays: displays)
    }

    func startHost(
        hostIndex: Int,
        wakeHost: @escaping @Sendable () -> Void,
        wakeSink: @escaping @Sendable (WakeEvent) -> Void,
        displays: [Display]
    ) {
        attachHost(hostIndex: hostIndex, wakeHost: wakeHost, wakeSink: wakeSink)
        resumeHost(hostIndex: hostIndex, displays: displays)
    }

    func handleHostWakeEvent(_ event: WakeEvent, displays: [Display]) -> Bool {
        switch event {
        case .window(_, let req):
            switch req {
            case .open(let tok):
                openWindow(token: tok, activateApp: true)
            case .show:
                showWindow()
            case .hide:
                hideWindow()
            case .close:
                if closeWindow(fromCloseButton: false) {
                    return true
                }
            }
        case .focus:
            focusWindow()
        case .level(_, let on):
            options.alwaysOnTop = on
            win?.window.setWindowLevel(on ? WINDOW_LEVEL_ALWAYS_ON_TOP : WINDOW_LEVEL_NORMAL)
        case .position(_, let pos):
            applyPosition(pos)
        case .place(_, let req):
            applyPlaceRequest(req, displays: displays)
        case .frame(_, let req):
            if let sz = req.size {
                let scale = max(Float(win?.window.scaleFactor() ?? Double(rt.env.scale)), 1.0)
                let pw = max(UInt32((sz.0 * scale).rounded()), 1)
                let ph = max(UInt32((sz.1 * scale).rounded()), 1)
                win?.resize((pw, ph))
                rt.hostSetViewport(sz.0, sz.1)
            }
            if req.center {
                let disp = displays.first(where: { $0.primary }) ?? displays.first ?? Display()
                let wPx = Int32(win?.window.innerSize().0 ?? UInt32(rt.viewport.0))
                let hPx = Int32(win?.window.innerSize().1 ?? UInt32(rt.viewport.1))
                let cx = disp.position.0 + max((Int32(disp.size.0) - wPx) / 2, 0)
                let cy = disp.position.1 + max((Int32(disp.size.1) - hPx) / 2, 0)
                applyPosition((cx, cy))
            }
            win?.window.requestRedraw()
        default:
            break
        }
        return drainShellRequests(displays: displays)
    }

    func stepHost(now: RuneInstant, displays: [Display]) -> Bool {
        if drainShellRequests(displays: displays) {
            return true
        }
        mountPendingOverlays(hostIndex: 0, displays: displays)

        if let win {
            if win.isCovered {
                if win.hiddenPace.takeDue(now: now, hasPoll: rt.poll != nil) {
                    rt.hostPollHidden()
                }
                if timerWantsFrame(rt: rt, now: now) || rt.hostNeedsCommit() {
                    _ = coveredStep(rt: rt, clock: &clock, firstFrame: &win.firstFrame, now: now)
                }
                _ = win.firstFrame.expireIfPast(now)
            } else {
                if timerWantsFrame(rt: rt, now: now)
                    || rt.hostStale()
                    || clock.isRunning
                    || (win.window.takeRedrawRequested())
                {
                    _ = drawWindow(now: now)
                }
            }
        } else {
            // Windowless host: still poll hidden at 500ms & service timer wakes
            if windowlessHiddenPace.takeDue(now: now, hasPoll: rt.poll != nil) {
                rt.hostPollHidden()
            }
            if timerWantsFrame(rt: rt, now: now) || rt.hostNeedsCommit() {
                let dt = drainFrame(clock: &clock, rt: rt, now: now)
                _ = rt.hostFrame(dt)
            }
        }

        // Step attached overlays
        for ov in overlays {
            ov.stepOverlay(now: now, displays: displays)
        }

        return drainShellRequests(displays: displays)
    }

    func nextWakeDeadline(now: RuneInstant) -> RuneInstant? {
        var earliest: RuneInstant? = nil
        func merge(_ candidate: RuneInstant?) {
            guard let c = candidate else { return }
            if let cur = earliest {
                earliest = min(cur, c)
            } else {
                earliest = c
            }
        }

        if let win {
            merge(timerDeadline(rt: rt, now: now, covered: win.isCovered, hiddenPace: &win.hiddenPace))
            merge(win.firstFrame.deadline())
            if win.occluded, let retry = win.occludedRetry {
                merge(now.adding(retry))
            }
            if let dropSample = win.fileDrop.sampleCursor(window: win.window, scale: rt.env.scale, rt: rt) {
                merge(now.adding(dropSample))
            }
            if !win.isCovered && (clock.isRunning || rt.hostStale()) && !win.native.isDisplayLinkRunning {
                merge(now.adding(FIRST_FRAME_BUDGET))
            }
        } else {
            merge(timerDeadline(rt: rt, now: now, covered: true, hiddenPace: &windowlessHiddenPace))
        }

        for ov in overlays {
            merge(ov.overlayWakeDeadline(now: now))
        }
        return earliest
    }

    func hasVisibleReopenableWindow() -> Bool {
        guard !macOptions.nonactivatingPanelFlag && !macOptions.launcher else { return false }
        guard let win else { return false }
        return win.visible && (win.window.isMinimized() != true)
    }

    func handleReopen(hasVisibleWindows: Bool) -> Bool {
        var handled = false
        if let hook = onReopenHook {
            var tx = Tx()
            handled = hook(&rt.state, hasVisibleWindows, &tx)
            rt.hostLatchTx(&tx)
        }
        _ = drainShellRequests()
        return handled
    }

    func handleIncomingUrls(_ urls: [String]) {
        guard let hook = onOpenUrlHook else { return }
        for url in urls {
            var tx = Tx()
            hook(&rt.state, url, &tx)
            rt.hostLatchTx(&tx)
        }
        rt.hostInvalidate()
        win?.window.requestRedraw()
        _ = drainShellRequests()
    }

    func shutdownHost() {
        popupPresenter.cancel(rt)
        rt.hostCancelFileDialogs()
        shortcutGuard?.release()
        shortcutGuard = nil
        menuGuard?.detach()
        menuGuard = nil
        for ov in overlays {
            ov.shutdownOverlay()
        }
        overlays.removeAll()
        windowHandle.attachNativeWindow(nil)
        win?.releaseGpu()
        win = nil
    }
}
