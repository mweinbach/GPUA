// Ported from: crates/gpui_macos/src/window_appearance.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import GPUI

/// Maps an AppKit `NSAppearance` to GPUI's `WindowAppearance`.
func windowAppearanceFromNative(_ appearance: NSAppearance?) -> WindowAppearance {
    guard let appearance else {
        return .light
    }
    let bestMatch = appearance.bestMatch(from: [
        .aqua,
        .vibrantLight,
        .darkAqua,
        .vibrantDark,
    ])
    switch bestMatch {
    case .vibrantLight:
        return .vibrantLight
    case .aqua:
        return .light
    case .vibrantDark:
        return .vibrantDark
    case .darkAqua:
        return .dark
    default:
        return .light
    }
}
#endif
