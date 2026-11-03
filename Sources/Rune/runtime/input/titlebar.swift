// Ported from: crates/rune/src/runtime/input/titlebar.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window-drag regions (`El.windowDrag`) and double-click titlebar zoom/minimize action detection.

extension Runtime {
    public func setNativeTitlebarBand(_ height: Float) {
        nativeTitlebarBand = max(height, 0.0)
    }

    public func takeTitlebarAction() -> TitlebarAction? {
        let out = pendingTitlebarAction
        pendingTitlebarAction = nil
        return out
    }

    func checkTitlebarPointerDown(x: Float, y: Float, clicks: UInt32) -> TitlebarAction {
        // Avoid intercepting clicks inside macOS traffic-light buttons
        if let rects = chrome.trafficLightRects() {
            for r in rects where r.count >= 4 {
                if x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3] {
                    return .none
                }
            }
        }

        let hitIdx = hitTestNode(x, y, includeTransparent: true, requireInteractive: false)

        // Walk ancestor chain from `hitIdx` up to check interactive controls and `windowDrag` regions
        var cur: Int? = hitIdx
        while let idx = cur {
            let n = nodes[idx]
            if n.inert { return .none }
            let isInteractiveControl = n.onPressHandler != nil
                || n.onDragHandler != nil
                || n.input != nil
                || n.textSpec?.selectable == true
            if isInteractiveControl && !n.windowDrag {
                return .none
            }
            if n.windowDrag {
                let act: TitlebarAction = clicks >= 2 ? .doubleClick : .drag
                pendingTitlebarAction = act
                return act
            }
            cur = n.parent
        }

        if nativeTitlebarBand > 0.0 && y >= 0.0 && y < nativeTitlebarBand && clicks == 2 {
            pendingTitlebarAction = .doubleClick
            return .doubleClick
        }
        return .none
    }
}
