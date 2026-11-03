// Ported from: crates/rune/src/overlay/requests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Queued `OverlayHandle` commands and state updates (`crates/rune/src/overlay/requests.rs`).

enum OverlayCommand: Sendable, Equatable {
    case show
    case hide
    case close
    case setSize(Float, Float)
    case setPlacement(OverlayPlacement?)
    case setDisplay(DisplayTarget)
    case setFollowPointer(Bool)
    case setLevel(OverlayLevel)
    case setMacosLevel(Int?)
    case setExcludeFromCapture(Bool)
    case setInput(OverlayInput)
    case requestKeys
    case releaseKeys
}

// PORT NOTE: Synchronized via `lock` (`LiveLock`) for thread-safe `OverlayHandle<T>` operations.
final class OverlaySharedState<T>: @unchecked Sendable {
    let lock = LiveLock()
    var waker: Waker? = nil
    var woken: Bool = false
    var visibleSnapshot: Bool = false
    var availabilitySnapshot: Availability = .unknown
    var failureSnapshot: String? = nil
    var capabilitiesSnapshot = OverlayCapabilities()
    var windowNumberSnapshot: UInt32? = nil
    var commands: [OverlayCommand] = []
    var updates: [(inout T, inout Tx) -> Bool] = []

    init() {}
}

extension Overlay {
    func startOverlay(displays: [Display], waker: @escaping Waker = {}) {
        handle.connect(waker)
        rt.hostSetLiveWaker(waker)
        if let setup = setupFn {
            setup(&rt.state, waker)
        }
        if options.prewarm {
            _ = ensureOverlaySurface(displays: displays, forPrewarm: true)
            if window != nil {
                _ = drawOverlay()
                rt.hostSetLiveVisible(false)
                clock.pause()
            }
        }
        _ = drainOverlayRequests(displays: displays)
    }

    @discardableResult
    func drainOverlayRequests(displays: [Display]) -> Bool {
        let (cmds, ups) = handle.shared.lock.withLock { () -> ([OverlayCommand], [(inout T, inout Tx) -> Bool]) in
            let c = handle.shared.commands
            let u = handle.shared.updates
            handle.shared.commands.removeAll()
            handle.shared.updates.removeAll()
            handle.shared.woken = false
            return (c, u)
        }

        var needsRedraw = false

        if !ups.isEmpty {
            var anyChanged = false
            var tx = Tx()
            for fn in ups {
                if fn(&rt.state, &tx) {
                    anyChanged = true
                }
            }
            rt.hostLatchTx(&tx)
            if anyChanged && !tx.liveOnlyFlag {
                rt.hostInvalidate()
                needsRedraw = true
            }
        }

        for cmd in cmds {
            switch cmd {
            case .show:
                showOverlay(displays: displays)
                needsRedraw = true

            case .hide:
                hideOverlay()

            case .close:
                closeOverlay()

            case .setSize(let w, let h):
                at.size = (max(w, 1.0), max(h, 1.0))
                repositionOverlay(displays: displays)
                needsRedraw = true

            case .setPlacement(let placement):
                options.placement = placement
                repositionOverlay(displays: displays)
                needsRedraw = true

            case .setDisplay(let target):
                options.display = target
                repositionOverlay(displays: displays)
                needsRedraw = true

            case .setFollowPointer(let follow):
                options.followPointer = follow
                if follow && visible {
                    repositionOverlay(displays: displays)
                }

            case .setLevel(let lvl):
                options.level = lvl
                window?.setWindowLevel(overlayMacWindowLevel(lvl, override: macosLevelOverride))

            case .setMacosLevel(let lvl):
                macosLevelOverride = lvl
                window?.setWindowLevel(overlayMacWindowLevel(options.level, override: lvl))

            case .setExcludeFromCapture(let exclude):
                options.excludeFromCapture = exclude
                updateCapabilitiesSnapshot()

            case .setInput(let mode):
                pendingInput = mode
                applyOverlayInput()

            case .requestKeys:
                if options.keys == .onDemand && visible {
                    keysActive = true
                    window?.focusWindow()
                    rt.hostWindowFocus(true)
                    if let f = onFocus {
                        var tx = Tx()
                        f(&rt.state, true, &tx)
                        rt.hostLatchTx(&tx)
                    }
                    needsRedraw = true
                }

            case .releaseKeys:
                if keysActive {
                    keysActive = false
                    window?.setFocused(false)
                    rt.hostWindowFocus(false)
                    if let f = onFocus {
                        var tx = Tx()
                        f(&rt.state, false, &tx)
                        rt.hostLatchTx(&tx)
                    }
                    needsRedraw = true
                }
            }
        }

        // Check `Tx.closeWindow()` / `Tx.quit()` inside overlay handlers
        let att = hostAttachment(for: rt)
        if let shell = att.shellRequest {
            att.shellRequest = nil
            switch shell {
            case .close:
                hideOverlay()
            case .quit:
                closeOverlay()
            }
        }

        return needsRedraw
    }

    func showOverlay(displays: [Display]) {
        let hadRetainedSurface = window != nil
        guard ensureOverlaySurface(displays: displays, forPrewarm: false) else {
            return
        }
        visible = true
        repositionOverlay(displays: displays)
        window?.setVisible(true)
        rt.hostSetLiveVisible(true)
        hiddenPace.reset()

        // Unretained overlays settle on show unless `.animateReveal()` was configured!
        if !hadRetainedSurface && !retainSurface && !animateReveal {
            rt.hostSettleAll()
        }
        presented.invalidate()
        syncOverlayInputPolicy()
        handle.shared.lock.withLock {
            handle.shared.visibleSnapshot = true
            handle.shared.availabilitySnapshot = .available
            handle.shared.failureSnapshot = nil
        }
    }

    func hideOverlay() {
        visible = false
        if keysActive {
            keysActive = false
            rt.hostWindowFocus(false)
            if let f = onFocus {
                var tx = Tx()
                f(&rt.state, false, &tx)
                rt.hostLatchTx(&tx)
            }
        }
        rt.hostPointerLeave()
        rt.hostSetLiveVisible(false)
        clock.pause()
        if retainSurface {
            window?.setVisible(false)
        } else {
            window = nil
            presented.invalidate()
        }
        handle.shared.lock.withLock {
            handle.shared.visibleSnapshot = false
        }
    }

    func closeOverlay() {
        visible = false
        keysActive = false
        rt.hostPointerLeave()
        rt.hostWindowFocus(false)
        rt.hostSetLiveVisible(false)
        clock.pause()
        window?.setVisible(false)
        window = nil
        presented.invalidate()
        handle.shared.lock.withLock {
            handle.shared.visibleSnapshot = false
        }
    }

    @discardableResult
    func ensureOverlaySurface(displays: [Display], forPrewarm: Bool) -> Bool {
        if let err = simulatedUnavailableError {
            visible = false
            handle.shared.lock.withLock {
                handle.shared.visibleSnapshot = false
                handle.shared.availabilitySnapshot = .unavailable
                handle.shared.failureSnapshot = err
            }
            return false
        }

        if window == nil {
            let bounds = computeOverlayBounds(
                at: at,
                placement: options.placement,
                target: options.display,
                displays: displays,
                pointer: currentOverlayPointer()
            )
            let w = NativeWindow(
                title: name,
                innerSize: bounds.physicalSize,
                position: bounds.position,
                scaleFactor: bounds.scale,
                visible: !forPrewarm
            )
            w.setWindowLevel(overlayMacWindowLevel(options.level, override: macosLevelOverride))
            self.window = w
            self.config = makeSurfaceConfig(
                size: bounds.physicalSize,
                transparent: true,
                srgb: rt.srgbBlend,
                displayLink: false
            )
            configureWindowSurface(&self.config, &self.surfaceMeter)
            rt.hostSetScale(Float(bounds.scale))
            rt.hostSetViewport(bounds.logicalSize.0, bounds.logicalSize.1)
            rt.hostSetWindowOrigin(
                Float(bounds.position.0) / Float(max(bounds.scale, 0.25)),
                Float(bounds.position.1) / Float(max(bounds.scale, 0.25))
            )
            updateCapabilitiesSnapshot()
            let winNum = UInt32(truncatingIfNeeded: w.id)
            handle.shared.lock.withLock {
                handle.shared.windowNumberSnapshot = winNum
                if !forPrewarm {
                    handle.shared.availabilitySnapshot = .available
                }
            }
            if !createdNotified {
                createdNotified = true
                let caps = handle.capabilities()
                onCreated?(OverlayCreated(windowNumber: winNum, capabilities: caps))
            }
        }
        return true
    }

    func updateCapabilitiesSnapshot() {
        #if os(macOS)
        let caps = OverlayCapabilities(
            captureExclusion: options.excludeFromCapture ? .requested : .supported,
            nonactivatingKeys: .supported,
            globalPointer: .supported
        )
        #elseif os(Windows) || os(Linux)
        let caps = OverlayCapabilities(
            captureExclusion: options.excludeFromCapture ? .requested : .supported,
            nonactivatingKeys: .supported,
            globalPointer: .supported
        )
        #else
        let caps = OverlayCapabilities(
            captureExclusion: .unsupported,
            nonactivatingKeys: .unsupported,
            globalPointer: .unsupported
        )
        #endif
        handle.shared.lock.withLock {
            handle.shared.capabilitiesSnapshot = caps
        }
    }
}
