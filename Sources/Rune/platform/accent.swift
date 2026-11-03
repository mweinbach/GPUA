// Ported from: crates/rune/src/platform/accent.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The user's accent colour and keyboard focus ring colour. macOS reads `controlAccentColor` and
//! `keyboardFocusIndicatorColor` and follows changes; other platforms use macOS's default blue.

#if os(macOS)
import AppKit
import Foundation
#endif

/// The user's accent colour and the colour of keyboard focus rings, each for a light and a dark
/// appearance. Read it with `systemAccent()`, or in a view with `Cx.accent`
/// and `Cx.focusColor`, which pick the window's appearance and re-run
/// the view when the user picks another accent.
public struct SystemAccent: Sendable, Equatable {
    private var accentColors: [Color]
    private var focusColors: [Color]

    /// macOS's default blue (`#007AFF` light, `#0A84FF` dark) and its focus ring at 50%: what
    /// platforms without an accent setting, and headless runs, report.
    public static let DEFAULT = SystemAccent.new(
        Color(0.0, 0.194_618, 1.0, 1.0),
        Color(0.003_035, 0.230_74, 1.0, 1.0)
    )

    public init() {
        self = SystemAccent.DEFAULT
    }

    public init(light: Color, dark: Color) {
        self.accentColors = [light, dark]
        self.focusColors = [
            Color(light.r, light.g, light.b, light.a * 0.5),
            Color(dark.r, dark.g, dark.b, dark.a * 0.5),
        ]
    }

    /// An accent in light and dark, with focus rings in the same colour at 50%, as AppKit draws
    /// them. For tests: `Runtime.setSystemAccent(SystemAccent.new(..))`.
    public static func new(_ light: Color, _ dark: Color) -> SystemAccent {
        SystemAccent(light: light, dark: dark)
    }

    /// The same accent with focus rings in these colours.
    public func withFocus(_ light: Color, _ dark: Color) -> SystemAccent {
        var copy = self
        copy.focusColors = [light, dark]
        return copy
    }

    /// The accent colour for a dark or light appearance.
    public func accent(_ dark: Bool) -> Color {
        accentColors[dark ? 1 : 0]
    }

    /// The keyboard focus ring colour for a dark or light appearance.
    public func focus(_ dark: Bool) -> Color {
        focusColors[dark ? 1 : 0]
    }
}

/// The user's accent and focus ring colours. On macOS, the accent picked in System Settings
/// (`NSColor.controlAccentColor` and `keyboardFocusIndicatorColor`), read on the main thread
/// and kept up to date while a window is open; elsewhere `SystemAccent.DEFAULT`.
public func systemAccent() -> SystemAccent {
    #if os(macOS)
    return macSystemAccentCurrent()
    #else
    return SystemAccent.DEFAULT
    #endif
}

/// Starts following accent changes (`NSSystemColorsDidChangeNotification`), once per process:
/// each change rereads the colours and asks every window to redraw, which hands them to its
/// runtime. Main thread.
func watchSystemAccent() {
    #if os(macOS)
    macWatchSystemAccent()
    #endif
}

#if os(macOS)
private let macAccentLock = LiveLock()
// PORT NOTE: Guarded by `macAccentLock`, matching `CURRENT: Mutex<Option<SystemAccent>>` in `accent.rs`.
nonisolated(unsafe) private var macCurrentAccent: SystemAccent? = nil
// PORT NOTE: Guarded by `macAccentLock`, matching `WATCHING` in `accent.rs`.
nonisolated(unsafe) private var macWatchingAccent: Bool = false
// PORT NOTE: Retained process-lifetime notification observer token, matching `std::mem::forget(token)` in `accent.rs`.
nonisolated(unsafe) private var macAccentObserverToken: (any NSObjectProtocol)? = nil

private func macSystemAccentCurrent() -> SystemAccent {
    if let existing = macAccentLock.withLock({ macCurrentAccent }) {
        return existing
    }
    if Thread.isMainThread {
        let resolved = MainActor.assumeIsolated { readMacSystemAccent() }
        macAccentLock.withLock {
            if macCurrentAccent == nil {
                macCurrentAccent = resolved
            }
        }
        return resolved
    }
    return SystemAccent.DEFAULT
}

@MainActor
private func readMacSystemAccent() -> SystemAccent {
    let accentPair: [Color?] = [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua].map {
        resolveMacColor({ NSColor.controlAccentColor }, appearanceName: $0)
    }
    let focusPair: [Color?] = [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua].map {
        resolveMacColor({ NSColor.keyboardFocusIndicatorColor }, appearanceName: $0)
    }
    guard let light = accentPair[0], let dark = accentPair[1] else {
        return SystemAccent.DEFAULT
    }
    let accent = SystemAccent.new(light, dark)
    if let focusLight = focusPair[0], let focusDark = focusPair[1] {
        return accent.withFocus(focusLight, focusDark)
    }
    return accent
}

/// `NSColor` resolved as `appearanceName` draws it, in linear sRGB.
@MainActor
private func resolveMacColor(
    _ fetch: () -> NSColor,
    appearanceName: NSAppearance.Name
) -> Color? {
    var result: Color? = nil
    func sample() {
        let color = fetch()
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        let r = srgbDecode(Float(min(max(srgb.redComponent, 0.0), 1.0)))
        let g = srgbDecode(Float(min(max(srgb.greenComponent, 0.0), 1.0)))
        let b = srgbDecode(Float(min(max(srgb.blueComponent, 0.0), 1.0)))
        let a = Float(min(max(srgb.alphaComponent, 0.0), 1.0))
        result = Color(r, g, b, a)
    }
    if let appearance = NSAppearance(named: appearanceName) {
        appearance.performAsCurrentDrawingAppearance {
            sample()
        }
    } else {
        sample()
    }
    return result
}

private func macWatchSystemAccent() {
    guard Thread.isMainThread else { return }
    let alreadyWatching = macAccentLock.withLock { () -> Bool in
        if macWatchingAccent { return true }
        macWatchingAccent = true
        return false
    }
    if alreadyWatching { return }
    let initial = MainActor.assumeIsolated { readMacSystemAccent() }
    macAccentLock.withLock { macCurrentAccent = initial }
    let token = NotificationCenter.default.addObserver(
        forName: NSColor.systemColorsDidChangeNotification,
        object: nil,
        queue: nil
    ) { _ in
        guard Thread.isMainThread else { return }
        let updated = MainActor.assumeIsolated { () -> SystemAccent in
            let next = readMacSystemAccent()
            for window in NSApplication.shared.windows {
                window.contentView?.needsDisplay = true
            }
            return next
        }
        macAccentLock.withLock { macCurrentAccent = updated }
    }
    macAccentLock.withLock { macAccentObserverToken = token }
}
#endif
