// Ported from: crates/rune/src/platform/reopen.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Reopening a running app: on macOS, a click on its Dock icon, or opening it again from Finder,
//! Spotlight or `open` while it runs. Without this an app whose windows Rune hid (⌘W with
//! `keepRunning`, `hide`) stays invisible, because AppKit only brings back minimized windows.

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime
#endif

/// One window as reopening sees it.
struct ReopenCandidate: Sendable, Equatable {
    /// An app window that still exists and can come back: not a launcher or other
    /// nonactivating panel, an overlay, or a window that closed for good.
    var reopenable: Bool
    /// On screen and not minimized.
    var visible: Bool
    var minimized: Bool
    /// When Rune last hid it (a close with `keepRunning`, `hide`), as `reopenStamp` counted.
    var hiddenAt: UInt64?
    /// A window of the app itself, not one `App.window` added.
    var main: Bool

    init(
        reopenable: Bool = false,
        visible: Bool = false,
        minimized: Bool = false,
        hiddenAt: UInt64? = nil,
        main: Bool = false
    ) {
        self.reopenable = reopenable
        self.visible = visible
        self.minimized = minimized
        self.hiddenAt = hiddenAt
        self.main = main
    }
}

/// Whether any window reopening could bring back already shows.
func reopenHasVisible(_ windows: [ReopenCandidate]) -> Bool {
    windows.contains { $0.reopenable && $0.visible }
}

/// The window the default reopen shows, when none shows: a minimized one, as AppKit restores
/// them; else the one Rune hid last; else the first main window, which may never have shown.
func reopenTarget(_ windows: [ReopenCandidate]) -> Int? {
    if reopenHasVisible(windows) {
        return nil
    }
    if let idx = windows.firstIndex(where: { $0.reopenable && $0.minimized }) {
        return idx
    }
    var latestStamp: UInt64? = nil
    var latestIndex: Int? = nil
    for (i, w) in windows.enumerated() where w.reopenable {
        if let hiddenAt = w.hiddenAt {
            if latestStamp == nil || hiddenAt >= latestStamp! {
                latestStamp = hiddenAt
                latestIndex = i
            }
        }
    }
    if let latestIndex {
        return latestIndex
    }
    return windows.firstIndex(where: { $0.reopenable && $0.main })
}

private let reopenStampLock = LiveLock()
// PORT NOTE: Guarded by `reopenStampLock`, matching `HIDES: AtomicU64` in `reopen.rs`.
nonisolated(unsafe) private var reopenHideCounter: UInt64 = 0

/// A number larger than every earlier one, for the order windows hid in.
func reopenStamp() -> UInt64 {
    reopenStampLock.withLock {
        reopenHideCounter += 1
        return reopenHideCounter
    }
}

/// What the reopen method answers AppKit: whether AppKit should run its own reopen handling.
func reopenAppkitHandles(_ sent: Bool, _ appkitSeesVisible: Bool) -> Bool {
    !sent || appkitSeesVisible
}

#if os(macOS)
// PORT NOTE: Main-thread reopen callback and hooked delegate class, matching thread-local `REOPEN` and `HOOKED` in `reopen.rs`.
nonisolated(unsafe) private var macReopenCallback: (() -> Bool)? = nil
// PORT NOTE: Main-thread pointer to the delegate class Rune added `applicationShouldHandleReopen:hasVisibleWindows:` to.
nonisolated(unsafe) private var macReopenHookedClass: AnyClass? = nil

private let macShouldHandleReopenImp: @convention(c) (AnyObject, Selector, AnyObject?, ObjCBool) -> ObjCBool = { _, _, _, visible in
    let sent = macReopenCallback?() ?? false
    return ObjCBool(reopenAppkitHandles(sent, visible.boolValue))
}

/// Calls `reopen` on the main thread each time the app is reopened; it returns whether the
/// event reached Rune's loop. Adds the reopen method to the app delegate's class unless the
/// class already answers it. Main thread only; a later call replaces `reopen`.
func reopenInstall(_ reopen: @escaping () -> Bool) {
    guard Thread.isMainThread else { return }
    let installed: Bool = MainActor.assumeIsolated {
        let app = NSApplication.shared
        guard let delegate = app.delegate else { return false }
        let selector = NSSelectorFromString("applicationShouldHandleReopen:hasVisibleWindows:")
        guard let cls: AnyClass = object_getClass(delegate) else { return false }
        if macReopenHookedClass !== cls {
            if (delegate as AnyObject).responds(to: selector) {
                return false
            }
            #if arch(arm64)
            let types = "B@:@B"
            #else
            let types = "c@:@c"
            #endif
            let imp = unsafeBitCast(macShouldHandleReopenImp, to: IMP.self)
            let added = types.withCString { class_addMethod(cls, selector, imp, $0) }
            if !added {
                fputs("rune: could not add the reopen method to the app delegate\n", stderr)
                return false
            }
            macReopenHookedClass = cls
            // AppKit caches which optional methods its delegate answers when it is set.
            app.delegate = delegate
        }
        return true
    }
    if installed {
        macReopenCallback = reopen
    }
}

/// The app has no Dock icon now (`App.accessory`, `AppHandle.setDockIcon(false)`).
func reopenIsAccessory() -> Bool {
    guard Thread.isMainThread else { return false }
    return MainActor.assumeIsolated {
        NSApplication.shared.activationPolicy() != .regular
    }
}

/// Unhides the app if it is hidden (⌘H, Hide Others), which also activates it.
func reopenUnhide() {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        if app.isHidden {
            app.unhide(nil)
        }
    }
}

/// Activates the app with `window` key and in front.
func reopenOrderFront(_ window: NSWindow) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
