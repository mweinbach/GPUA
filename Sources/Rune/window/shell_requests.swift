// Ported from: crates/rune/src/window/shell_requests.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Drains `AppHandle` commands, `Tx` shell/title/minimize/clipboard/popup/file-dialog/shortcut/menu requests (`crates/rune/src/window/shell_requests.rs`).

#if os(macOS)
import AppKit
#endif

extension Host {
    /// Processes queued `AppHandle` commands, shortcuts, menus, and `Tx` shell requests.
    /// Returns `true` when the application should quit.
    @discardableResult
    func drainShellRequests(displays: [Display] = [Display()]) -> Bool {
        if handle.isQuitRequested() {
            return true
        }

        // 1. Sync shortcut & menu guards first (native registrations + revisions)
        shortcutGuard?.drain()
        menuGuard?.drain()

        // 2. Drain `AppHandle.update` / `updateIf` before taking window/focus/geometry requests
        var handleTx = Tx()
        let updated = handle.drainUpdates(into: &rt.state, tx: &handleTx)
        if !updated {
            handleTx.liveOnly()
        }
        rt.hostLatchTx(&handleTx)
        if updated && !handleTx.liveOnlyFlag {
            rt.hostInvalidate()
        }
        if handle.takeWoken() && rt.poll != nil {
            rt.hostPollHidden()
        }

        // 3. Position / placement requests from `AppHandle`
        if let pos = handle.takePositionRequest() {
            applyPosition(pos)
        }
        if let place = handle.takePlaceRequest() {
            applyPlaceRequest(place, displays: displays)
        }

        // 4. Window open / show / hide / close / focus / minimize from `AppHandle`
        if let req = handle.takeWindowRequest() {
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
        }
        if handle.takeFocusRequest() {
            focusWindow()
        }
        if handle.takeMinimizeRequest() {
            minimizeWindow()
        }

        // 5. Dock icon visibility request from `AppHandle`
        if let dockVisible = handle.takeDockIconRequest() {
            #if os(macOS)
            macSetDockIconVisible(dockVisible)
            #else
            _ = dockVisible
            #endif
        }

        // 6. `Tx` shell / minimize / title / resize / center requests latched on `RuntimeHostAttachment`
        let att = hostAttachment(for: rt)
        if let title = att.takeWindowTitleChange() {
            spec.title = title
            win?.window.setTitle(title)
        }
        if att.minimizeRequest {
            att.minimizeRequest = false
            minimizeWindow()
        }
        if let shell = att.shellRequest {
            att.shellRequest = nil
            switch shell {
            case .quit:
                return true
            case .close:
                if closeWindow(fromCloseButton: false) {
                    return true
                }
            }
        }

        // 7. Drain popup & file-dialog queues
        if popupPresenter.answer(rt) {
            rt.hostInvalidate()
        }
        var windowViewObj: AnyObject? = nil
        #if os(macOS)
        if let rawView = win?.window.rawNSViewPointer() {
            windowViewObj = Unmanaged<NSView>.fromOpaque(rawView).takeUnretainedValue()
        }
        #endif
        if popupPresenter.open(rt, windowView: windowViewObj, paints: win?.visible == true) {
            rt.hostInvalidate()
        }
        if rt.hostFlushFileDialogAnswers() {
            rt.hostInvalidate()
        }

        return handle.isQuitRequested()
    }
}
