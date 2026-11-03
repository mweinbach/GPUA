// Tests ported from: crates/rune/tests/macos_support/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
@testable import Rune

private final class MacOSOnMainBox: @unchecked Sendable {
    var value: Any?
}

enum MacOSSupport {
    static let cuaDriver = "/Applications/CuaDriver.app/Contents/MacOS/cua-driver"

    static func onMain<S, T: Sendable>(_ handle: AppHandle<S>, _ f: @escaping @Sendable () -> T) -> T {
        let sem = DispatchSemaphore(value: 0)
        let box = MacOSOnMainBox()
        handle.update { _, _ in
            box.value = f()
            sem.signal()
        }
        let waited = sem.wait(timeout: .now() + 10.0)
        precondition(waited == .success, "event thread stalled")
        return box.value as! T
    }

    static func wait(_ what: String, _ f: () -> Bool) {
        let deadline = Date().addingTimeInterval(10.0)
        while !f() {
            precondition(Date() < deadline, "timed out waiting for \(what)")
            Thread.sleep(forTimeInterval: 0.010)
        }
    }

    static func warp(_ pt: (Double, Double)) {
        CGWarpMouseCursorPosition(CGPoint(x: pt.0, y: pt.1))
    }

    static func canPostEvents() -> Bool {
        CGPreflightPostEventAccess()
    }

    static func releaseRealButton() {
        guard let here = CGEvent(source: nil) else { return }
        let at = here.location
        if let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: at, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
    }

    static func dragPasteboard() -> (String?, String?) {
        let board = NSPasteboard(name: .drag)
        let url = board.string(forType: .fileURL)
        let names = board.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]
        return (url, names?.first)
    }

    @MainActor
    static func appActive() -> Bool {
        NSApplication.shared.isActive
    }

    static func frontmostPid() -> pid_t {
        NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    }
}
#endif
