// Ported from: crates/rune/src/platform/preferences.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native accessibility and appearance preferences, sampled when a host is created or focused
//! (appearance also on each redraw, which a change asks for).
//! Headless runtimes use their explicit `Env` instead.

#if os(macOS)
import AppKit
import Foundation
#elseif os(Linux)
import Foundation
import Glibc
#elseif os(Windows)
import WinSDK
#endif

func platformReducedMotion() -> Bool {
    #if os(macOS)
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
    }
    return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    #elseif os(Windows)
    var animations: Int32 = 1
    let ok = withUnsafeMutablePointer(to: &animations) { ptr in
        SystemParametersInfoW(UINT(SPI_GETCLIENTAREAANIMATION), 0, UnsafeMutableRawPointer(ptr), 0)
    }
    return ok && animations == 0
    #elseif os(Linux)
    let env = ProcessInfo.processInfo.environment
    let configDir: String? = env["XDG_CONFIG_HOME"] ?? env["HOME"].map { "\($0)/.config" }
    let desktop = env["XDG_CURRENT_DESKTOP"] ?? ""
    if desktop.split(separator: ":").contains(where: { $0.lowercased() == "kde" }),
       let configDir,
       let contents = try? String(contentsOfFile: "\(configDir)/kdeglobals", encoding: .utf8)
    {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "AnimationDurationFactor", let factor = Double(value) {
                return factor == 0.0
            }
        }
    }
    if let enabled = linuxGnomeAnimations() {
        return !enabled
    }
    return false
    #else
    return false
    #endif
}

#if os(Linux)
private let gioLibLock = LiveLock()
// PORT NOTE: Guarded by `gioLibLock`, matching `static GIO: OnceLock` in `preferences.rs`.
nonisolated(unsafe) private var gioLibLoaded: Bool = false
// PORT NOTE: Guarded by `gioLibLock`; the loaded handle stays open for GLib's retained callbacks.
nonisolated(unsafe) private var gioLibHandle: UnsafeMutableRawPointer? = nil

private func linuxGnomeAnimations() -> Bool? {
    let gio = gioLibLock.withLock { () -> UnsafeMutableRawPointer? in
        if !gioLibLoaded {
            gioLibLoaded = true
            gioLibHandle = dlopen("libgio-2.0.so.0", RTLD_LAZY | RTLD_LOCAL)
        }
        return gioLibHandle
    }
    guard let gio else { return nil }
    typealias GetDefaultFn = @convention(c) () -> UnsafeMutableRawPointer?
    typealias LookupFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>, Int32) -> UnsafeMutableRawPointer?
    typealias HasKeyFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Int32
    typealias NewFullFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?
    typealias GetBoolFn = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Int32
    typealias UnrefFn = @convention(c) (UnsafeMutableRawPointer?) -> Void

    guard let defaultSym = dlsym(gio, "g_settings_schema_source_get_default"),
          let lookupSym = dlsym(gio, "g_settings_schema_source_lookup"),
          let hasKeySym = dlsym(gio, "g_settings_schema_has_key"),
          let newFullSym = dlsym(gio, "g_settings_new_full"),
          let getBoolSym = dlsym(gio, "g_settings_get_boolean"),
          let schemaUnrefSym = dlsym(gio, "g_settings_schema_unref"),
          let objectUnrefSym = dlsym(gio, "g_object_unref")
    else {
        return nil
    }

    let getDefault = unsafeBitCast(defaultSym, to: GetDefaultFn.self)
    let lookup = unsafeBitCast(lookupSym, to: LookupFn.self)
    let hasKey = unsafeBitCast(hasKeySym, to: HasKeyFn.self)
    let newFull = unsafeBitCast(newFullSym, to: NewFullFn.self)
    let getBool = unsafeBitCast(getBoolSym, to: GetBoolFn.self)
    let schemaUnref = unsafeBitCast(schemaUnrefSym, to: UnrefFn.self)
    let objectUnref = unsafeBitCast(objectUnrefSym, to: UnrefFn.self)

    guard let source = getDefault() else { return nil }
    let schema = "org.gnome.desktop.interface".withCString { lookup(source, $0, 1) }
    guard let schema else { return nil }
    let keyExists = "enable-animations".withCString { hasKey(schema, $0) } != 0
    if !keyExists {
        schemaUnref(schema)
        return nil
    }
    let settings = newFull(schema, nil, nil)
    schemaUnref(schema)
    guard let settings else { return nil }
    let enabled = "enable-animations".withCString { getBool(settings, $0) } != 0
    objectUnref(settings)
    return enabled
}
#endif

/// The desktop's light or dark preference where the window system reports none (Linux: the XDG
/// desktop portal's `color-scheme`). `nil` leaves the host's own default.
func platformDark() -> Bool? {
    #if os(Linux)
    return portalAppearanceDark()
    #else
    return nil
    #endif
}

/// `platformDark()` for a window that reports no theme; `nil` leaves the window's appearance as it is.
func platformDesktopDark(windowThemeIsKnown: Bool) -> Bool? {
    windowThemeIsKnown ? nil : platformDark()
}

/// A new window's appearance: `--theme` when given, else native window theme, else `platformDesktopDark`,
/// else dark (`true`).
func platformWindowDark(theme: String?, nativeDark: Bool?) -> Bool {
    switch theme {
    case "light":
        return false
    case "dark":
        return true
    default:
        if let nativeDark {
            return nativeDark
        }
        return platformDark() ?? true
    }
}

/// macOS "Keyboard navigation" (Full Keyboard Access): when off, Tab visits only text fields
/// and lists, as in AppKit. Windows and Linux always Tab through every control.
func platformFullKeyboardAccess() -> Bool {
    #if os(macOS)
    if Thread.isMainThread {
        return MainActor.assumeIsolated {
            NSApplication.shared.isFullKeyboardAccessEnabled
        }
    }
    return true
    #else
    return true
    #endif
}
