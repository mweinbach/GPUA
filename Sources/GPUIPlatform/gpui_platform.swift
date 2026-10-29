// Ported from: crates/gpui_platform/src/gpui_platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(Windows)
import GPUIWindows
#elseif os(Linux)
import GPUILinux
#endif

/// Returns a background executor for the current platform.
public func backgroundExecutor() -> GPUI.BackgroundExecutor? {
    currentPlatform(headless: true).backgroundExecutor()
}

/// Creates a new GPUI application with the platform implementation for the current OS.
@MainActor
public func application() -> Application {
    Application.withPlatform(currentPlatform(headless: false))
}

/// Creates a headless GPUI application with the platform implementation for the current OS.
@MainActor
public func headless() -> Application {
    Application.withPlatform(currentPlatform(headless: true))
}

/// Returns the default `Platform` for the current OS.
public func currentPlatform(headless: Bool = false) -> any Platform {
    #if os(Windows)
    return WindowsPlatform(headless: headless)
    #elseif os(Linux)
    return GPUILinux.currentPlatform(headless: headless)
    #else
    return TestPlatform()
    #endif
}
