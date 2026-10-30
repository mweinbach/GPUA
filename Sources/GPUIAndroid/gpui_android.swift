// Swift-only: Android platform backend module root, logging bridge, and public entry points per ADR-0012

import Foundation
import GPUI
#if os(Android)
import CAndroidSys
#endif

/// Log severity levels mapped to Android's `<android/log.h>` `android_LogPriority`.
public enum AndroidLogLevel: Int32, Sendable, Equatable, Hashable {
    case verbose = 2
    case debug = 3
    case info = 4
    case warn = 5
    case error = 6
}

/// Emits a structured log message to Android logcat under the `GPUA` tag on Android.
public func androidLog(_ level: AndroidLogLevel, _ message: String, tag: String = "GPUA") {
    #if os(Android)
    tag.withCString { cTag in
        message.withCString { cMsg in
            _ = candroid_log_print(level.rawValue, cTag, cMsg)
        }
    }
    #else
    _ = level
    _ = message
    _ = tag
    #endif
}

/// Error domain for Android platform operations.
public struct AndroidError: Swift.Error, CustomStringConvertible, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// Optional bootstrap hook allowing an Android shared library target to register
/// its GPUI `Application` startup closure before `GPUINative.nativeInit` fires.
// PORT NOTE: Synchronized via NSLock for safe registration before or during JNI initialization.
public final class AndroidAppBootstrap: @unchecked Sendable {
    public static let shared = AndroidAppBootstrap()

    private let lock = NSLock()
    private var launchHandler: (@Sendable () -> Void)?
    private var hasLaunched: Bool = false

    private init() {}

    /// Registers a one-shot launch callback invoked when the Android Activity initializes.
    public func register(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.launchHandler = handler
        self.hasLaunched = false
        lock.unlock()
    }

    /// Invokes the registered launch handler once on the Android UI thread.
    public func launchIfNeeded() {
        lock.lock()
        guard !hasLaunched, let handler = launchHandler else {
            lock.unlock()
            return
        }
        hasLaunched = true
        lock.unlock()
        handler()
    }

    /// Resets launch tracking for tests or full process re-initialization.
    public func reset() {
        lock.lock()
        hasLaunched = false
        launchHandler = nil
        lock.unlock()
    }
}

/// Returns the native Android `Platform` implementation (or headless variant for tests).
public func currentPlatform(headless: Bool = false) -> any Platform {
    AndroidPlatform(headless: headless)
}
