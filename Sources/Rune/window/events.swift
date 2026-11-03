// Ported from: crates/rune/src/window/events.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window input, resize, scale, occlusion, focus, IME, and file-drop event dispatch (`crates/rune/src/window/events.rs`).

enum WindowEvent: Sendable, Equatable {
    case resized(UInt32, UInt32)
    case moved(Int32, Int32)
    case scaleFactorChanged(Double, UInt32, UInt32)
    case focused(Bool)
    case occluded(Bool)
    case closeRequested
    case pointerMoved(Float, Float)
    case pointerLeft
    case pointerDown(Float, Float, PointerButton)
    case pointerUp(Float, Float, PointerButton)
    case keyDown(KeyEvent, Character?)
    case ime(Ime)
    case fileStep(WindowFileStep)
    case themeChanged(Bool)
    case redrawRequested
}

extension Host {
    /// Routes a `WindowEvent` to `Win` and `Runtime<S>`.
    /// Returns `true` when the application should exit.
    @discardableResult
    func handleWindowEvent(_ event: WindowEvent, now: RuneInstant = .now()) -> Bool {
        switch event {
        case .resized(let w, let h):
            guard w > 0 && h > 0 else { return false }
            win?.resize((w, h))
            let scale = max(rt.env.scale, 0.25)
            rt.hostSetViewport(Float(w) / scale, Float(h) / scale)
            win?.window.requestRedraw()

        case .moved(let x, let y):
            win?.window.setOuterPosition((x, y))
            let scale = max(rt.env.scale, 0.25)
            rt.hostSetWindowOrigin(Float(x) / scale, Float(y) / scale)

        case .scaleFactorChanged(let factor, let newW, let newH):
            let s = Float(max(factor, 0.25))
            win?.window.setScaleFactor(factor)
            rt.hostSetScale(s)
            if newW > 0 && newH > 0 {
                win?.resize((newW, newH))
                rt.hostSetViewport(Float(newW) / s, Float(newH) / s)
            }
            win?.presented.invalidate()
            win?.window.requestRedraw()

        case .focused(let focused):
            win?.window.setFocused(focused)
            if !focused, let win {
                floatOnOpenRelease(&win.floatingOnOpen, window: win.window)
            }
            rt.hostWindowFocus(focused)
            win?.window.requestRedraw()

        case .occluded(let isOccluded):
            guard let win else { return false }
            win.occluded = isOccluded
            if isOccluded {
                floatOnOpenRelease(&win.floatingOnOpen, window: win.window)
                rt.hostSetLiveVisible(false)
                win.native.setDisplayLinkPaused(true)
            } else {
                win.occludedRetry = nil
                win.hiddenPace.reset()
                if win.visible {
                    rt.hostSetLiveVisible(true)
                    win.presented.invalidate()
                    win.window.requestRedraw()
                }
            }

        case .closeRequested:
            return closeWindow(fromCloseButton: true)

        case .pointerMoved(let x, let y):
            guard !options.clickThrough else { return false }
            if rt.hostPointerMove(x, y) || rt.hostStale() {
                win?.window.requestRedraw()
            }
            if let win {
                syncPlatform(win: win, rt: rt, chrome: chrome, options: options)
            }

        case .pointerLeft:
            if rt.hostPointerLeave() {
                win?.window.requestRedraw()
            }

        case .pointerDown(let x, let y, let button):
            guard !options.clickThrough else { return false }
            #if os(macOS)
            if button == .primary, let win {
                let band = macNativeTitlebarBand(chrome: chrome, borderless: options.borderless, fullscreen: false)
                if band > 0 && y <= band {
                    if let (prevAt, prevPt) = win.lastTitlebarClick {
                        let elapsed = now.durationSince(prevAt)
                        let dx = x - prevPt.0
                        let dy = y - prevPt.1
                        let distSq = dx * dx + dy * dy
                        if elapsed <= macDoubleClickInterval() && distSq <= 36.0 {
                            win.lastTitlebarClick = nil
                            let action = rt.hostTitlebarDoubleClick(x, y, bandHeight: band)
                            performTitlebarDoubleClick(action: action, window: win.window)
                            return false
                        }
                    }
                    win.lastTitlebarClick = (now, (x, y))
                } else {
                    win.lastTitlebarClick = nil
                }
            }
            #endif
            let (changed, hitDrag) = rt.hostPointerDown(x, y, button: button)
            if hitDrag {
                // Native window drag initiated by OS
                return false
            }
            if changed || rt.hostStale() {
                win?.window.requestRedraw()
            }

        case .pointerUp(let x, let y, let button):
            guard !options.clickThrough else { return false }
            if rt.hostPointerUp(x, y, button: button) || rt.hostStale() {
                win?.window.requestRedraw()
            }

        case .keyDown(let ev, let base):
            if rt.hostKey(ev, base: base) || rt.hostStale() {
                win?.window.requestRedraw()
            }

        case .ime(let ime):
            if rt.hostIme(ime) || rt.hostStale() {
                win?.window.requestRedraw()
            }

        case .fileStep(let step):
            if let win, win.fileDrop.step(step, rt) {
                rt.hostInvalidate()
                win.window.requestRedraw()
            }

        case .themeChanged(let dark):
            rt.hostSetSystemDark(dark)
            rt.hostSetSystemAccent(systemAccent())
            win?.presented.invalidate()
            win?.window.requestRedraw()

        case .redrawRequested:
            _ = drawWindow(now: now)
        }

        return drainShellRequests()
    }
}
