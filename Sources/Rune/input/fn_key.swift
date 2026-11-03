// Ported from: crates/rune/src/input/fn_key.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS) && canImport(AppKit)
import AppKit

private let KEY_CODE_FN: UInt16 = 0x3F

/// Tracks the Fn (Globe) key on macOS via an AppKit local `flagsChanged` event monitor.
// PORT NOTE: Used only on AppKit's main thread by the macOS window host; lock protects `changes` across monitor callbacks.
internal final class FnKeyMonitor: @unchecked Sendable {
    private var monitorToken: Any?
    private let lock = LiveLock()
    private var changes: [Bool] = []

    @MainActor
    internal init?(for view: NSView) {
        weak let weakView = view
        let lock = self.lock
        var token: Any?
        token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if event.keyCode == KEY_CODE_FN,
               let targetView = weakView,
               let targetWindow = targetView.window,
               event.window === targetWindow {
                let isDown = event.modifierFlags.contains(.function)
                if let self {
                    lock.withLock {
                        self.changes.append(isDown)
                    }
                }
            }
            return event
        }
        guard let token else { return nil }
        self.monitorToken = token
    }

    internal func take() -> [Bool] {
        lock.withLock {
            let result = changes
            changes.removeAll(keepingCapacity: true)
            return result
        }
    }

    deinit {
        if let token = monitorToken {
            NSEvent.removeMonitor(token)
        }
    }
}
#endif
