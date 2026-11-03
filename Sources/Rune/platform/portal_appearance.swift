// Ported from: crates/rune/src/platform/portal_appearance.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The desktop's light or dark preference on Linux, from the XDG desktop portal
//! (`org.freedesktop.appearance` `color-scheme`).

#if os(Linux)
import Foundation
#endif

/// D-Bus variant model for `org.freedesktop.portal.Settings` `color-scheme` replies.
enum PortalAppearanceVariant: Sendable, Equatable {
    case u32(UInt32)
    indirect case variant(PortalAppearanceVariant)
    case str(String)
    case other
}

private let portalAppearanceLock = LiveLock()
/// The portal's numbering: 0 no preference (or not known yet), 1 dark, 2 light.
// PORT NOTE: Guarded by `portalAppearanceLock`, matching `SCHEME`, `WATCH`, and `WINDOWS` in `portal_appearance.rs`.
nonisolated(unsafe) private var portalSchemeState: UInt8 = 0
// PORT NOTE: Guarded by `portalAppearanceLock`.
nonisolated(unsafe) private var portalWatchStarted: Bool = false
// PORT NOTE: Guarded by `portalAppearanceLock`.
nonisolated(unsafe) private var portalRedrawCallbacks: [@Sendable () -> Void] = []

/// `true` when the desktop prefers dark, `false` light, `nil` when it has no preference
/// or no portal answers.
func portalAppearanceDark() -> Bool? {
    #if os(Linux)
    portalAppearanceEnsureStarted()
    #endif
    let raw = portalAppearanceLock.withLock { UInt32(portalSchemeState) }
    return portalSchemeDark(raw)
}

/// Registers a callback to redraw a window whenever the preference changes.
func portalAppearanceFollow(_ redraw: @escaping @Sendable () -> Void) {
    portalAppearanceLock.withLock {
        portalRedrawCallbacks.append(redraw)
    }
}

func portalSchemeDark(_ scheme: UInt32) -> Bool? {
    switch scheme {
    case 1:
        return true
    case 2:
        return false
    default:
        return nil
    }
}

/// `color-scheme` as a `UInt32`. Portals answer `v`, and `Read` (before `ReadOne`) wraps it twice.
func portalScheme(_ value: PortalAppearanceVariant) -> UInt32? {
    switch value {
    case .u32(let x):
        return x
    case .variant(let inner):
        return portalScheme(inner)
    case .str, .other:
        return nil
    }
}

func portalAppearanceStore(_ value: PortalAppearanceVariant) {
    guard let decoded = portalScheme(value) else { return }
    let clamped: UInt8 = decoded <= 2 ? UInt8(decoded) : 0
    let callbacks: [@Sendable () -> Void] = portalAppearanceLock.withLock {
        if portalSchemeState == clamped {
            return []
        }
        portalSchemeState = clamped
        return portalRedrawCallbacks
    }
    for cb in callbacks {
        cb()
    }
}

#if os(Linux)
private func portalAppearanceEnsureStarted() {
    let shouldStart = portalAppearanceLock.withLock { () -> Bool in
        if portalWatchStarted { return false }
        portalWatchStarted = true
        return true
    }
    guard shouldStart else { return }
    // PORT NOTE: Queries `org.freedesktop.portal.Settings.ReadOne` via `gdbus` once on Linux when available,
    // without introducing a new D-Bus SwiftPM dependency (Golden Rule #8).
    let sema = DispatchSemaphore(value: 0)
    let thread = Thread {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.portal.Desktop",
            "--object-path", "/org/freedesktop/portal/desktop",
            "--method", "org.freedesktop.portal.Settings.ReadOne",
            "org.freedesktop.appearance", "color-scheme",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            {
                if out.contains("uint32 1") {
                    portalAppearanceStore(.u32(1))
                } else if out.contains("uint32 2") {
                    portalAppearanceStore(.u32(2))
                }
            }
        }
        sema.signal()
    }
    thread.name = "rune-appearance-portal"
    thread.start()
    _ = sema.wait(timeout: .now() + .milliseconds(100))
}
#endif
