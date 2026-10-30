// Ported from: crates/gpui_web/src/platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(WASI)
import CWebSys
import GPUIWGPU
#endif

/// Errors raised for unsupported desktop-only `Platform` operations on the web.
public enum WebPlatformError: Error, CustomStringConvertible, Sendable, Equatable {
    case unsupportedOperation(String)

    public var description: String {
        switch self {
        case .unsupportedOperation(let name):
            return "\(name) is not available on the web"
        }
    }
}

struct WebPlatformCallbacks {
    var openUrls: (([String]) -> Void)?
    var quit: (() -> Void)?
    var reopen: (() -> Void)?
    var appMenuAction: (@MainActor (any Action) -> Void)?
    var willOpenAppMenu: (@MainActor () -> Void)?
    var validateAppMenuCommand: (@MainActor (any Action) -> Bool)?
    var keyboardLayoutChange: (() -> Void)?
    var thermalStateChange: (() -> Void)?
}

/// Maps GPUI `CursorStyle` values onto CSS `cursor` property strings.
func cursorStyleToCss(_ style: CursorStyle) -> String {
    switch style {
    case .arrow:
        return "default"
    case .iBeam:
        return "text"
    case .crosshair:
        return "crosshair"
    case .closedHand:
        return "grabbing"
    case .openHand:
        return "grab"
    case .pointingHand:
        return "pointer"
    case .resizeLeft, .resizeRight, .resizeLeftRight:
        return "ew-resize"
    case .resizeUp, .resizeDown, .resizeUpDown:
        return "ns-resize"
    case .resizeUpLeft, .resizeDownRight:
        return "nwse-resize"
    case .resizeUpLeftDownRight:
        return "nesw-resize"
    case .resizeUpRight, .resizeDownLeft:
        return "nesw-resize"
    case .resizeUpRightDownLeft:
        return "nwse-resize"
    case .notAllowed:
        return "not-allowed"
    case .wait:
        return "wait"
    case .progress:
        return "progress"
    case .copy:
        return "copy"
    case .none:
        return "none"
    }
}

/// Browser `Platform` implementation backed by `WebDispatcher`, `WebDisplay`, `WebWindow`, and WebGPU.
// PORT NOTE: WebPlatform owns browser main-thread executors, active window handle, clipboard cache, and WebGPU context; single-threaded on WASI.
public final class WebPlatform: Platform, @unchecked Sendable {
    private let dispatcher: WebDispatcher
    private let platformBackgroundExecutor: BackgroundExecutor
    private let platformForegroundExecutor: ForegroundExecutor
    private let platformTextSystem: any PlatformTextSystem
    private var activeWindowHandle: AnyWindowHandle?
    private var openedWindows: [AnyWindowHandle] = []
    private let activeDisplay: WebDisplay
    private var callbacks = WebPlatformCallbacks()
    private var clipboardCache: ClipboardItem?
    private(set) var lastAppliedCssCursor: String = "default"
    #if os(WASI)
    private var wgpuContext: WgpuContext?
    #endif

    public init(_ allowMultiThreading: Bool = false, bundledFonts: [Data] = []) {
        let dispatcher = WebDispatcher(allowThreads: allowMultiThreading)
        self.dispatcher = dispatcher
        self.platformBackgroundExecutor = BackgroundExecutor.new(dispatcher: dispatcher)
        self.platformForegroundExecutor = ForegroundExecutor.new(dispatcher: dispatcher)

        #if os(WASI)
        cwebsys_ensure_wasm_exports()
        let cosmic = CosmicTextSystem.newWithoutSystemFonts("IBM Plex Sans")
        if !bundledFonts.isEmpty {
            do {
                try cosmic.addFonts(bundledFonts)
            } catch {
                webLog(.error, "failed to load bundled fonts: \(error)")
            }
        }
        self.platformTextSystem = cosmic
        #else
        let noop = NoopTextSystem.new()
        if !bundledFonts.isEmpty {
            try? noop.addFonts(bundledFonts)
        }
        self.platformTextSystem = noop
        #endif

        self.activeDisplay = WebDisplay.new()
    }

    public convenience init(headless: Bool) {
        _ = headless
        self.init(true)
    }

    public static func new(_ allowMultiThreading: Bool = false) -> WebPlatform {
        WebPlatform(allowMultiThreading)
    }

    // MARK: - Platform Conformance

    public func backgroundExecutor() -> BackgroundExecutor? {
        platformBackgroundExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        platformForegroundExecutor
    }

    public func textSystem() -> any PlatformTextSystem {
        platformTextSystem
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        #if os(WASI)
        // PORT NOTE: `runGpuiWebApp` in `gpui_web_runtime.js` pre-acquires the browser WebGPU adapter
        // and device before invoking `_start()`, enabling synchronous `WgpuContext` setup on the
        // single-threaded WASI main thread so `_start()` launches the app before returning to JS.
        do {
            let instance = WgpuContext.instance()
            let context = try WgpuContext.new(instance: instance, surface: nil)
            webLog(.info, "WebGPU context initialized successfully")
            self.wgpuContext = context
        } catch {
            webLog(.error, "Failed to initialize WebGPU context: \(error)")
        }
        onFinishLaunching()
        #else
        onFinishLaunching()
        #endif
    }

    public func quit() {
        webLog(.warn, "WebPlatform::quit called, but quitting is not supported in the browser .")
    }

    public func restart(path: URL?) {
        _ = path
    }

    public func activate(ignoringOtherApps: Bool) {
        _ = ignoringOtherApps
    }

    public func hide() {}

    public func hideOtherApps() {}

    public func unhideOtherApps() {}

    public func displays() -> [any PlatformDisplay] {
        [activeDisplay]
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        activeDisplay
    }

    public func activeWindow() -> AnyWindowHandle? {
        activeWindowHandle
    }

    public func windowStack() -> [AnyWindowHandle]? {
        openedWindows.isEmpty ? nil : openedWindows
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        #if os(WASI)
        if wgpuContext == nil {
            webLog(.warn, "WebGPU context not initialized. Was Platform.run() called?")
        }
        if let window = try? WebWindow.new(handle: handle, options: options, context: wgpuContext) {
            activeWindowHandle = handle
            openedWindows.append(handle)
            return window
        }
        #endif
        let fallback = WebWindow(handle: handle, options: options)
        activeWindowHandle = handle
        openedWindows.append(handle)
        return fallback
    }

    public func windowAppearance() -> WindowAppearance {
        currentAppearance()
    }

    public func buttonLayout() -> WindowButtonLayout? {
        nil
    }

    public func openUrl(_ url: String) {
        #if os(WASI)
        let opened = Array(url.utf8).withUnsafeBufferPointer { ptr in
            cwebsys_open_url(ptr.baseAddress, ptr.count)
        }
        if !opened {
            webLog(.warn, "Failed to open URL '\(url)'")
        }
        #else
        _ = url
        #endif
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        callbacks.openUrls = callback
    }

    public func registerUrlScheme(_ scheme: String) async throws {
        _ = scheme
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        _ = options
        throw WebPlatformError.unsupportedOperation("prompt_for_paths")
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        _ = (directory, suggestedName)
        throw WebPlatformError.unsupportedOperation("prompt_for_new_path")
    }

    public func canSelectMixedFilesAndDirs() -> Bool {
        false
    }

    public func revealPath(_ path: URL) {
        _ = path
    }

    public func openWithSystem(_ path: URL) {
        _ = path
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        callbacks.quit = callback
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        callbacks.reopen = callback
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        _ = (menus, keymap)
    }

    public func getMenus() -> [OwnedMenu]? {
        nil
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {
        _ = (menus, keymap)
    }

    public func performDockMenuAction(_ action: Int) {
        _ = action
    }

    public func addRecentDocument(_ path: URL) {
        _ = path
    }

    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] {
        _ = menus
        return entries
    }

    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        callbacks.appMenuAction = callback
    }

    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        callbacks.willOpenAppMenu = callback
    }

    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        callbacks.validateAppMenuCommand = callback
    }

    public func thermalState() -> ThermalState {
        .nominal
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        callbacks.thermalStateChange = callback
    }

    public func compositorName() -> String {
        "Web"
    }

    public func appPath() throws -> URL {
        throw WebPlatformError.unsupportedOperation("app_path")
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        _ = name
        throw WebPlatformError.unsupportedOperation("path_for_auxiliary_executable")
    }

    public func setCursorStyle(_ style: CursorStyle) {
        let cssCursor = cursorStyleToCss(style)
        lastAppliedCssCursor = cssCursor
        #if os(WASI)
        Array(cssCursor.utf8).withUnsafeBufferPointer { ptr in
            cwebsys_set_cursor_style(ptr.baseAddress, ptr.count)
        }
        #endif
    }

    public func shouldAutoHideScrollbars() -> Bool {
        true
    }

    public func isScreenCaptureSupported() -> Bool {
        false
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        throw WebPlatformError.unsupportedOperation("screen_capture_sources")
    }

    public func readFromClipboard() -> ClipboardItem? {
        #if os(WASI)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        let length = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return cwebsys_clipboard_read(base, ptr.count)
        }
        if length > 0, length <= buffer.count {
            let text = String(decoding: buffer.prefix(length), as: UTF8.self)
            return ClipboardItem(text: text)
        }
        #endif
        return clipboardCache
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        clipboardCache = item
        #if os(WASI)
        if let text = item.text {
            Array(text.utf8).withUnsafeBufferPointer { ptr in
                cwebsys_clipboard_write(ptr.baseAddress, ptr.count)
            }
        }
        #endif
    }

    public func readFromPrimary() -> ClipboardItem? {
        nil
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        _ = item
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        nil
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        _ = item
    }

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        _ = (url, username, password)
        throw WebPlatformError.unsupportedOperation("credential storage")
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        _ = url
        return nil
    }

    public func deleteCredentials(url: String) async throws {
        _ = url
        throw WebPlatformError.unsupportedOperation("credential storage")
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        WebKeyboardLayout.new()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        DummyKeyboardMapper()
    }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        callbacks.keyboardLayoutChange = callback
    }
}
