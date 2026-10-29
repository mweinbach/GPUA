// Ported from: crates/gpui_linux/src/linux.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

/// Returns the default platform implementation for the current OS.
public func currentPlatform(headless: Bool = false) -> any Platform {
    if headless {
        return LinuxPlatform(inner: HeadlessClient.new())
    }

    let compositor = guessCompositor()
    switch compositor {
    case "Wayland":
        if let client = try? WaylandClient.new() {
            return LinuxPlatform(inner: client)
        }
        if let client = try? X11Client.new() {
            return LinuxPlatform(inner: client)
        }
        return LinuxPlatform(inner: HeadlessClient.new())

    case "X11":
        if let client = try? X11Client.new() {
            return LinuxPlatform(inner: client)
        }
        return LinuxPlatform(inner: HeadlessClient.new())

    default:
        return LinuxPlatform(inner: HeadlessClient.new())
    }
}
#endif
