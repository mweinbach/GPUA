// Ported from: crates/rune/src/platform/app_icon.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The app's Dock icon from image bytes, so an app needs no AppKit glue of its own.

#if os(macOS)
import AppKit
import Foundation
#endif

/// Error returned when `setAppIcon` receives invalid image bytes.
public struct AppIconError: Error, CustomStringConvertible, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

#if os(macOS)
private let appIconLock = LiveLock()
/// The icon waiting for the main thread, newest wins.
// PORT NOTE: Guarded by `appIconLock`, matching `PENDING` and `LAUNCHED` in `app_icon.rs`.
nonisolated(unsafe) private var pendingAppIconBytes: [UInt8]? = nil
/// The event loop has started, so AppKit is ours to call.
// PORT NOTE: Guarded by `appIconLock`, matching `LAUNCHED: AtomicBool` in `app_icon.rs`.
nonisolated(unsafe) private var appIconHasLaunched: Bool = false

func isAppIconLaunchedForTests() -> Bool {
    appIconLock.withLock { appIconHasLaunched }
}

func hasPendingAppIconForTests() -> Bool {
    appIconLock.withLock { pendingAppIconBytes != nil }
}
#endif

/// macOS: shows `bytes` (an `.icns`, PNG, TIFF or anything else `NSImage` reads) as the app's
/// Dock and app-switcher icon while it runs, in place of the bundle's. Call it from any thread,
/// before `run` or after: before, Rune sets it once the app finishes launching; a later call
/// replaces it. A headless run sets nothing. Fails when the bytes aren't an image. Does nothing
/// elsewhere. (`AppHandle.setDockIcon` shows or hides the Dock icon instead.)
public func setAppIcon(_ bytes: [UInt8]) -> Result<Void, AppIconError> {
    #if os(macOS)
    guard decodeAppIconImage(bytes) != nil else {
        return .failure(AppIconError("set_app_icon: the bytes aren't an image AppKit reads"))
    }
    let launched = appIconLock.withLock { () -> Bool in
        pendingAppIconBytes = bytes
        return appIconHasLaunched
    }
    if launched {
        runOnMainQueue(applyPendingAppIcon)
    }
    return .success(())
    #else
    _ = bytes
    return .success(())
    #endif
}

/// The event loop exists: sets an icon asked for before `run` once the main queue drains, which
/// is after AppKit finishes launching (it would show the bundle's icon over an earlier one).
#if os(macOS)
func appIconLaunched() {
    appIconLock.withLock {
        appIconHasLaunched = true
    }
    runOnMainQueue(applyPendingAppIcon)
}

private func decodeAppIconImage(_ bytes: [UInt8]) -> NSImage? {
    guard !bytes.isEmpty else { return nil }
    let data = Data(bytes)
    // NSImage may be created and read on any thread; it's nil for data it can't read.
    guard let image = NSImage(data: data) else { return nil }
    let size = image.size
    return (size.width > 0.0 && size.height > 0.0) ? image : nil
}

@Sendable
private func applyPendingAppIcon() {
    guard Thread.isMainThread else { return }
    let bytes = appIconLock.withLock { () -> [UInt8]? in
        let b = pendingAppIconBytes
        pendingAppIconBytes = nil
        return b
    }
    guard let bytes else { return }
    MainActor.assumeIsolated {
        guard let image = decodeAppIconImage(bytes) else { return }
        NSApplication.shared.applicationIconImage = image
    }
}
#endif
