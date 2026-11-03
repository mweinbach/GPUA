// Ported from: crates/rune/src/window/lifecycle.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window open, show, hide, focus, minimize, place, and close lifecycle (`crates/rune/src/window/lifecycle.rs`).

#if os(macOS)
import AppKit
#endif

extension Host {
    /// Opens or focuses the window (recreating `Win` if closed, or revealing a hidden panel).
    func openWindow(token: String? = nil, activateApp: Bool = true) {
        if win == nil {
            createDefaultWindow(visible: true)
        }
        guard let win else { return }
        win.ensureGpu()
        if win.launchDrawables.reveal() {
            #if os(macOS)
            if let rawPtr = win.window.rawNSWindowPointer(), Thread.isMainThread {
                let addr = UInt(bitPattern: rawPtr)
                MainActor.assumeIsolated {
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                    let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                    nsWin.alphaValue = 1.0
                }
            }
            #endif
        }
        win.visible = true
        win.occluded = false
        win.occludedRetry = nil
        win.hiddenPace.reset()
        win.window.setMinimized(false)
        win.window.setVisible(true)
        if floatOnOpen && !floatOnOpenFixed(options, macOptions) {
            win.floatingOnOpen = true
            win.window.setWindowLevel(WINDOW_LEVEL_ALWAYS_ON_TOP)
        }
        #if os(macOS)
        if macOptions.nonactivatingPanelFlag {
            if let rawPtr = win.window.rawNSWindowPointer(), Thread.isMainThread {
                let addr = UInt(bitPattern: rawPtr)
                MainActor.assumeIsolated {
                    guard let ptr = UnsafeMutableRawPointer(bitPattern: addr) else { return }
                    let nsWin = Unmanaged<NSWindow>.fromOpaque(ptr).takeUnretainedValue()
                    macShowWithoutFocus(nsWin)
                }
            }
        } else if activateApp && !accessory && Thread.isMainThread {
            MainActor.assumeIsolated {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        _ = token
        #else
        _ = token
        _ = activateApp
        #endif
        win.window.focusWindow()
        rt.hostSetLiveVisible(true)
        rt.hostWindowFocus(true)
        handle.setVisibleSnapshot(true)
        win.presented.invalidate()
        win.window.requestRedraw()
    }

    /// Shows the window without activating other windows (`AppHandle.show`).
    func showWindow() {
        openWindow(token: nil, activateApp: false)
    }

    /// Hides the window while keeping its `Win` surface alive (`AppHandle.hide`).
    func hideWindow() {
        guard let win else {
            handle.setVisibleSnapshot(false)
            return
        }
        popupPresenter.cancel(rt)
        rt.hostCancelFileDialogs()
        win.visible = false
        win.window.setVisible(false)
        floatOnOpenRelease(&win.floatingOnOpen, window: win.window)
        _ = rt.hostPointerLeave()
        rt.hostWindowFocus(false)
        rt.hostSetLiveVisible(false)
        win.native.setDisplayLinkPaused(true)
        clock.pause()
        handle.setVisibleSnapshot(false)
    }

    /// Closes the window (`AppHandle.close` or window close button).
    /// Returns `true` when the app should exit (no `keepRunning`).
    @discardableResult
    func closeWindow(fromCloseButton: Bool = false) -> Bool {
        _ = fromCloseButton
        if let onClose = onCloseHook {
            var tx = Tx()
            let allow = onClose(&rt.state, &tx)
            rt.hostLatchTx(&tx)
            if !allow {
                return false
            }
        }
        popupPresenter.cancel(rt)
        rt.hostCancelFileDialogs()
        if (macOptions.launcher || secondary) && keepRunning {
            hideWindow()
            return false
        }
        if let win {
            if releaseGpuWhenClosed {
                win.releaseGpu()
            }
            win.visible = false
            win.window.setVisible(false)
            win.native.detach()
        }
        win = nil
        windowHandle.attachNativeWindow(nil)
        _ = rt.hostPointerLeave()
        rt.hostWindowFocus(false)
        rt.hostSetLiveVisible(false)
        clock.pause()
        handle.setVisibleSnapshot(false)
        return !keepRunning
    }

    func focusWindow() {
        guard let win else { return }
        if !win.visible {
            showWindow()
            return
        }
        win.window.setMinimized(false)
        win.window.focusWindow()
        rt.hostWindowFocus(true)
    }

    func minimizeWindow() {
        if macOptions.nonactivatingPanelFlag || macOptions.launcher {
            return
        }
        guard let win, win.visible else { return }
        win.window.setMinimized(true)
        floatOnOpenRelease(&win.floatingOnOpen, window: win.window)
        rt.hostSetLiveVisible(false)
        clock.pause()
    }

    func applyPosition(_ pos: (Int32, Int32)) {
        options.position = pos
        guard let win else { return }
        win.window.setOuterPosition(pos)
        let scale = max(Float(win.window.scaleFactor()), 0.25)
        rt.hostSetWindowOrigin(Float(pos.0) / scale, Float(pos.1) / scale)
    }

    func applyPlaceRequest(_ req: PlaceRequest, displays: [Display]) {
        let resolvedDisplay = resolveOverlayDisplay(
            target: req.display,
            displays: displays,
            pointer: req.pointer
        ) ?? Display()
        let spec = req.placement.resolve(size: (rt.viewport.0, rt.viewport.1))
        let pos = computeOverlayOrigin(spec: spec, display: resolvedDisplay)
        applyPosition(pos)
    }

    func createDefaultWindow(visible: Bool) {
        let scale = max(Double(rt.env.scale), 1.0)
        let physSize: (UInt32, UInt32)
        if let explicit = options.physicalSize {
            physSize = (max(explicit.0, 1), max(explicit.1, 1))
        } else {
            physSize = (
                max(UInt32((Double(spec.size.0) * scale).rounded()), 1),
                max(UInt32((Double(spec.size.1) * scale).rounded()), 1)
            )
        }
        let nativeWin = NativeWindow(
            title: spec.title,
            innerSize: physSize,
            position: options.position ?? (0, 0),
            scaleFactor: scale,
            visible: visible
        )
        var effectiveOpts = options
        effectiveOpts.visible = visible
        let created = Win(
            window: nativeWin,
            options: effectiveOpts,
            mac: macOptions,
            srgb: rt.srgbBlend,
            floatOnOpen: floatOnOpen
        )
        self.win = created
        self.readyFired = false
        windowHandle.attachNativeWindow(nativeWin)
        rt.hostSetLiveVisible(visible || created.launchDrawables.isWarming)
        handle.setVisibleSnapshot(visible)
        if let hook = onWindowHook {
            hook(windowHandle)
        }
    }
}
