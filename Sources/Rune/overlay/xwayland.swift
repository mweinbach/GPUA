// Ported from: crates/rune/src/overlay/xwayland.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! XWayland fallback selection when Wayland lacks `zwlr_layer_shell_v1` (`crates/rune/src/overlay/xwayland.rs`).

#if !os(WASI)
import Foundation
#endif

/// Returns `true` when both `WAYLAND_DISPLAY` and `DISPLAY` are present, indicating XWayland is available.
func isXwaylandAvailable(
    waylandDisplay: String? = currentEnvVar("WAYLAND_DISPLAY"),
    x11Display: String? = currentEnvVar("DISPLAY")
) -> Bool {
    guard let wl = waylandDisplay, !wl.isEmpty,
          let x11 = x11Display, !x11.isEmpty
    else {
        return false
    }
    return true
}

/// Decides whether an overlay on Wayland should fall back to XWayland override-redirect X11 window creation.
func shouldFallbackOverlayToXwayland(
    isWayland: Bool,
    hasLayerShell: Bool,
    x11Display: String? = currentEnvVar("DISPLAY")
) -> Bool {
    guard isWayland && !hasLayerShell else { return false }
    guard let x11 = x11Display, !x11.isEmpty else { return false }
    return true
}

private func currentEnvVar(_ key: String) -> String? {
    #if os(WASI)
    return nil
    #else
    return ProcessInfo.processInfo.environment[key]
    #endif
}
