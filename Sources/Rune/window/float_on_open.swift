// Ported from: crates/rune/src/window/float_on_open.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Temporary always-on-top level while opening a normal window (`crates/rune/src/window/float_on_open.rs`).

/// Window level constant for `AlwaysOnTop` (`NSFloatingWindowLevel` = 3).
let WINDOW_LEVEL_NORMAL: Int = 0
let WINDOW_LEVEL_ALWAYS_ON_TOP: Int = 3

/// Returns `true` when the window's level is already fixed by `alwaysOnTop` or an explicit `MacWindowOptions.level(...)`.
func floatOnOpenFixed(_ options: WindowOptions, _ mac: MacWindowOptions) -> Bool {
    if options.alwaysOnTop {
        return true
    }
    #if os(macOS)
    if mac.levelValue != nil {
        return true
    }
    #else
    _ = mac
    #endif
    return false
}

/// Releases temporary float-on-open level once the window loses focus (`!focused`) or becomes occluded.
func floatOnOpenRelease(_ floating: inout Bool, window: NativeWindow) {
    guard floating else { return }
    floating = false
    window.setWindowLevel(WINDOW_LEVEL_NORMAL)
}
