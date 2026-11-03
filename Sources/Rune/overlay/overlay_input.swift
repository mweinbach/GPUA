// Ported from: crates/rune/src/overlay/input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Overlay hit-region passthrough, pointer routing, and key/focus policy (`crates/rune/src/overlay/input.rs`).

enum OverlayEvent: Sendable, Equatable {
    case pointerMoved(Float, Float)
    case pointerLeft
    case pointerDown(Float, Float, PointerButton)
    case pointerUp(Float, Float, PointerButton)
    case keyDown(KeyEvent, Character?)
    case focused(Bool)
}

extension Overlay {
    func applyOverlayInput() {
        guard !rt.hostPointerCaptured() else { return }
        if let next = pendingInput {
            pendingInput = nil
            options.input = next
            syncOverlayInputPolicy()
        }
    }

    func resolvedInputMode() -> OverlayInput {
        options.input.resolved(interactive)
    }

    func syncOverlayInputPolicy() {
        let mode = resolvedInputMode()
        switch mode {
        case .none, .legacy:
            passthrough = true
            hitRects.removeAll(keepingCapacity: true)
            window?.setCursorHittest(false)
        case .all:
            passthrough = false
            hitRects = [[0.0, 0.0, rt.viewport.0, rt.viewport.1]]
            window?.setCursorHittest(true)
        case .regions:
            // Collect interactive element bounds `[x0, y0, x1, y1]`
            let rects = rt.hostInteractiveRegions()
            hitRects = rects
            if let ptr = rt.hostPointer() {
                let overHit = rects.contains { overlayContains($0, ptr.0, ptr.1) }
                passthrough = !overHit
            } else {
                passthrough = rects.isEmpty
            }
            window?.setCursorHittest(!passthrough)
        }
    }

    func hitsOverlayPoint(_ x: Float, _ y: Float) -> Bool {
        switch resolvedInputMode() {
        case .none, .legacy:
            return false
        case .all:
            return x >= 0.0 && y >= 0.0 && x < rt.viewport.0 && y < rt.viewport.1
        case .regions:
            return hitRects.contains { overlayContains($0, x, y) }
        }
    }

    func handleOverlayEvent(_ event: OverlayEvent) {
        switch event {
        case .pointerMoved(let x, let y):
            guard resolvedInputMode() != .none else { return }
            if resolvedInputMode() == .regions {
                let overHit = hitsOverlayPoint(x, y)
                passthrough = !overHit
                window?.setCursorHittest(overHit)
                if !overHit {
                    _ = rt.hostPointerLeave()
                    window?.setCursor(.default)
                    return
                }
            }
            if rt.hostPointerMove(x, y) {
                window?.requestRedraw()
            }
            window?.setCursor(rt.hostCursor())

        case .pointerLeft:
            _ = rt.hostPointerLeave()
            window?.setCursor(.default)
            if resolvedInputMode() == .regions {
                passthrough = true
                window?.setCursorHittest(false)
            }

        case .pointerDown(let x, let y, let button):
            guard hitsOverlayPoint(x, y) else { return }
            let (changed, _) = rt.hostPointerDown(x, y, button: button)
            if changed {
                window?.requestRedraw()
            }

        case .pointerUp(let x, let y, let button):
            guard hitsOverlayPoint(x, y) || rt.hostPointerCaptured() else { return }
            if rt.hostPointerUp(x, y, button: button) {
                window?.requestRedraw()
            }
            applyOverlayInput()

        case .keyDown(let ev, let base):
            guard options.keys == .onDemand && keysActive else { return }
            if rt.hostKey(ev, base: base) {
                window?.requestRedraw()
            }

        case .focused(let focused):
            keysActive = focused && options.keys == .onDemand
            rt.hostWindowFocus(keysActive)
            if let f = onFocus {
                var tx = Tx()
                f(&rt.state, keysActive, &tx)
                rt.hostLatchTx(&tx)
                rt.hostInvalidate()
                window?.requestRedraw()
            }
        }
    }
}
