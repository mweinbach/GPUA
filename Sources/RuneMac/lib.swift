// Ported from: crates/rune-mac/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import Darwin
import Foundation

/// Runs `body` synchronously on the main actor without suspending, matching AppKit's main-thread requirement.
@inline(__always)
func onMainThreadSync<T: Sendable>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated(body)
    } else {
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(body)
        }
    }
}

/// Parsed AppKit window frame (`NSWindow Frame <name>`) with optional screen bounds for clamping.
public struct SavedFrame: Equatable, Sendable {
    public var origin: CGPoint
    public var size: CGSize
    public var screenFrame: CGRect?

    public init(origin: CGPoint, size: CGSize, screenFrame: CGRect? = nil) {
        self.origin = origin
        self.size = size
        self.screenFrame = screenFrame
    }

    /// Clamps this window frame so it stays within `visibleFrame`.
    public func clamped(to visibleFrame: CGRect) -> CGRect {
        let w = min(max(size.width, 1), visibleFrame.width)
        let h = min(max(size.height, 1), visibleFrame.height)
        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - w)
        let minY = visibleFrame.minY
        let maxY = max(minY, visibleFrame.maxY - h)
        let x = min(max(origin.x, minX), maxX)
        let y = min(max(origin.y, minY), maxY)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// Has AppKit save the app's window frame under `name` and put the next launch's window in the
/// same place, so a rebuild's new window lands exactly over the old one. Call it every frame
/// (from `poll`) until it returns true: the window doesn't exist during `setup`.
public func rememberFrame(_ name: String) -> Bool {
    onMainThreadSync {
        let windows = NSApplication.shared.windows
        for window in windows {
            _ = window.setFrameAutosaveName(name)
        }
        return !windows.isEmpty
    }
}

/// The key window, else the main window; `nil` with neither.
@MainActor
private func keyWindow() -> NSWindow? {
    let app = NSApplication.shared
    return app.keyWindow ?? app.mainWindow
}

/// Takes the app's key window into macOS full screen, or back out (the green button's
/// ⌃⌘F). Headless, with no window, it does nothing.
public func toggleFullScreen() {
    onMainThreadSync {
        if let window = keyWindow() {
            window.toggleFullScreen(nil)
        }
    }
}

/// Whether the app's key window is in macOS full screen.
public func isFullScreen() -> Bool {
    onMainThreadSync {
        guard let window = keyWindow() else { return false }
        return window.styleMask.contains(.fullScreen)
    }
}

/// The size `rememberFrame(name)` saved, in points, to open the window at. Applying the saved
/// frame after the first layout resizes it, and the layout animates to the new size at launch.
public func savedSize(_ name: String) -> (Float, Float)? {
    let key = "NSWindow Frame \(name)"
    guard let value = UserDefaults.standard.string(forKey: key) else {
        return nil
    }
    return parseSize(value)
}

/// Reads the full saved AppKit window frame for `name` from `UserDefaults`, if present.
public func savedFrame(_ name: String) -> SavedFrame? {
    let key = "NSWindow Frame \(name)"
    guard let value = UserDefaults.standard.string(forKey: key) else {
        return nil
    }
    return parseFrame(value)
}

/// AppKit's frame string, `"x y width height"` then the screen's: the width and height.
func parseSize(_ frame: String) -> (Float, Float)? {
    let parts = frame.split(whereSeparator: { $0.isWhitespace })
    guard parts.count >= 4,
          let w = Float(parts[2]),
          let h = Float(parts[3]),
          w.isFinite, h.isFinite,
          w >= 1.0 && h >= 1.0
    else {
        return nil
    }
    return (w, h)
}

/// Parses AppKit's `"x y width height [sx sy swidth sheight]"` autosave string.
func parseFrame(_ frame: String) -> SavedFrame? {
    let parts = frame.split(whereSeparator: { $0.isWhitespace })
    guard parts.count >= 4,
          let x = Double(parts[0]),
          let y = Double(parts[1]),
          let w = Double(parts[2]),
          let h = Double(parts[3]),
          x.isFinite, y.isFinite, w.isFinite, h.isFinite,
          w >= 1.0 && h >= 1.0
    else {
        return nil
    }
    var screenRect: CGRect?
    if parts.count >= 8,
       let sx = Double(parts[4]),
       let sy = Double(parts[5]),
       let sw = Double(parts[6]),
       let sh = Double(parts[7]),
       sx.isFinite, sy.isFinite, sw > 0, sh > 0 {
        screenRect = CGRect(x: sx, y: sy, width: sw, height: sh)
    }
    return SavedFrame(
        origin: CGPoint(x: x, y: y),
        size: CGSize(width: w, height: h),
        screenFrame: screenRect
    )
}

/// Holds `scripts/mac-app`'s relaunch while `on`, for work a relaunch would lose (a recording in
/// progress, say). The marker is this process's pid in `~/Library/Caches/mac-app/busy/`, so only
/// this process holds the swap and a crash can't hold it forever.
public func busy(_ on: Bool) {
    // PORT NOTE: Read live C `getenv("HOME")` rather than cached `ProcessInfo` environment so test overrides via `setenv` take effect immediately.
    guard let rawHome = getenv("HOME") else { return }
    let home = String(cString: rawHome)
    guard !home.isEmpty else { return }

    let dirURL = URL(fileURLWithPath: home, isDirectory: true)
        .appendingPathComponent("Library/Caches/mac-app/busy", isDirectory: true)
    let markerURL = dirURL.appendingPathComponent(String(getpid()), isDirectory: false)
    let fm = FileManager.default
    if on {
        try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        _ = fm.createFile(atPath: markerURL.path, contents: Data())
    } else {
        try? fm.removeItem(at: markerURL)
    }
}
#endif
