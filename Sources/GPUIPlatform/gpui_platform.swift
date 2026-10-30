// Ported from: crates/gpui_platform/src/gpui_platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(macOS)
import GPUIMacOS
#elseif os(iOS) || os(visionOS)
import GPUIiOS
#elseif os(Windows)
import GPUIWindows
#elseif os(Linux)
import GPUILinux
#elseif os(Android)
import GPUIAndroid
#elseif os(WASI)
import GPUIWeb
#endif

public typealias Platform = GPUI.Platform

/// Returns a background executor for the current platform.
public func backgroundExecutor() -> GPUI.BackgroundExecutor? {
    GPUIPlatform.currentPlatform(headless: true).backgroundExecutor()
}

/// Creates a new GPUI application with the platform implementation for the current OS.
@MainActor
public func application() -> Application {
    Application.withPlatform(GPUIPlatform.currentPlatform(headless: false))
}

/// Creates a headless GPUI application with the platform implementation for the current OS.
@MainActor
public func headless() -> Application {
    Application.withPlatform(GPUIPlatform.currentPlatform(headless: true))
}

#if os(WASI)
/// Initializes console logging for the web platform.
/// Call this before running the application in a Wasm entrypoint.
public func webInit() {
    GPUIWeb.initLogging()
}
#endif

/// Returns the default `Platform` for the current OS.
public func currentPlatform(headless: Bool = false) -> any Platform {
    #if os(macOS)
    return MacPlatform(headless: headless)
    #elseif os(iOS) || os(visionOS)
    return IosPlatform(headless: headless)
    #elseif os(Windows)
    return WindowsPlatform(headless: headless)
    #elseif os(Linux)
    return GPUILinux.currentPlatform(headless: headless)
    #elseif os(Android)
    return AndroidPlatform(headless: headless)
    #elseif os(WASI)
    _ = headless
    return WebPlatform(true)
    #else
    return TestPlatform()
    #endif
}
