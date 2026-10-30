// Swift-only: Android Platform implementation, global JNI registry, clipboard, URL, and lifecycle dispatch per ADR-0012

import Foundation
import GPUI
#if os(Android)
import CAndroidSys
import GPUIWGPU
#endif

// MARK: - Global JNI Platform Registry

/// Coordinates the active `AndroidPlatform` instance with early JNI lifecycle/surface events
/// that may arrive before `Application.run` opens its first GPUI window.
// PORT NOTE: Synchronized via NSLock so JNI callbacks on the UI thread safely resolve or bootstrap the active platform.
public final class AndroidPlatformRegistry: @unchecked Sendable {
    public static let shared = AndroidPlatformRegistry()

    private let lock = NSLock()
    private var activePlatformRef: AndroidPlatform?
    private var pendingMetrics: AndroidDisplayMetrics?
    private var pendingAppearance: WindowAppearance?
    private var pendingPhase: AndroidLifecyclePhase?
    private var pendingUrls: [String] = []

    #if os(Android)
    private var pendingNativeWindow: OpaquePointer?
    private var pendingSurfaceGeometry: (widthPx: Int32, heightPx: Int32, format: Int32) = (0, 0, 0)
    #endif

    private init() {}

    /// Registers `platform` as the active JNI target and replays any cached bootstrap state.
    public func setActivePlatform(_ platform: AndroidPlatform) {
        lock.lock()
        activePlatformRef = platform
        let metrics = pendingMetrics
        let appearance = pendingAppearance
        let phase = pendingPhase
        let urls = pendingUrls
        pendingUrls.removeAll()
        #if os(Android)
        let savedWindow = pendingNativeWindow
        let savedGeom = pendingSurfaceGeometry
        pendingNativeWindow = nil
        #endif
        lock.unlock()

        if let metrics {
            platform.activeDisplay().updateMetrics(metrics)
        }
        if let appearance {
            platform.handleAppearanceChanged(isDark: appearance == .dark || appearance == .vibrantDark)
        }
        if let phase {
            platform.handleLifecycleState(phase)
        }
        #if os(Android)
        if let savedWindow {
            platform.handleSurfaceCreated(
                nativeWindow: savedWindow,
                widthPx: savedGeom.widthPx,
                heightPx: savedGeom.heightPx,
                format: savedGeom.format
            )
            candroid_native_window_release(savedWindow)
        }
        #endif
        if !urls.isEmpty {
            platform.handleIncomingUrls(urls)
        }
    }

    /// Returns the currently registered `AndroidPlatform`, creating a default instance if none exists.
    public func ensurePlatform() -> AndroidPlatform {
        lock.lock()
        if let existing = activePlatformRef {
            lock.unlock()
            return existing
        }
        lock.unlock()
        let created = AndroidPlatform(headless: false, registerInGlobalRegistry: true)
        return created
    }

    public var currentPlatform: AndroidPlatform? {
        lock.lock()
        defer { lock.unlock() }
        return activePlatformRef
    }

    public func cacheInitialMetrics(_ metrics: AndroidDisplayMetrics) {
        lock.lock()
        pendingMetrics = metrics
        let active = activePlatformRef
        lock.unlock()
        active?.activeDisplay().updateMetrics(metrics)
    }

    public func cacheAppearance(_ appearance: WindowAppearance) {
        lock.lock()
        pendingAppearance = appearance
        let active = activePlatformRef
        lock.unlock()
        active?.handleAppearanceChanged(isDark: appearance == .dark || appearance == .vibrantDark)
    }

    public func cacheLifecyclePhase(_ phase: AndroidLifecyclePhase) {
        lock.lock()
        pendingPhase = phase
        let active = activePlatformRef
        lock.unlock()
        active?.handleLifecycleState(phase)
    }

    public func enqueueIncomingUrls(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        lock.lock()
        if let active = activePlatformRef {
            lock.unlock()
            active.handleIncomingUrls(urls)
        } else {
            pendingUrls.append(contentsOf: urls)
            lock.unlock()
        }
    }

    #if os(Android)
    public func cacheOrAttachSurface(
        nativeWindow: OpaquePointer,
        widthPx: Int32,
        heightPx: Int32,
        format: Int32
    ) {
        lock.lock()
        if let active = activePlatformRef {
            lock.unlock()
            active.handleSurfaceCreated(
                nativeWindow: nativeWindow,
                widthPx: widthPx,
                heightPx: heightPx,
                format: format
            )
            return
        }
        if let old = pendingNativeWindow {
            candroid_native_window_release(old)
        }
        candroid_native_window_acquire(nativeWindow)
        pendingNativeWindow = nativeWindow
        pendingSurfaceGeometry = (widthPx, heightPx, format)
        lock.unlock()
    }

    public func clearCachedSurface() {
        lock.lock()
        let old = pendingNativeWindow
        pendingNativeWindow = nil
        pendingSurfaceGeometry = (0, 0, 0)
        lock.unlock()
        if let old {
            candroid_native_window_release(old)
        }
    }
    #endif
}

// MARK: - AndroidPlatform

/// Native Android implementation of GPUI's `Platform` protocol.
// PORT NOTE: Synchronized via NSLock so JNI UI/lifecycle/clipboard callbacks and GPUI executors
// safely share platform state across strict concurrency boundaries.
public final class AndroidPlatform: Platform, @unchecked Sendable {
    public let isHeadless: Bool
    public let dispatcher: AndroidDispatcher
    public let lifecycle: AndroidLifecycleController

    private let lock = NSLock()
    private let backgroundExec: GPUI.BackgroundExecutor
    private let foregroundExec: GPUI.ForegroundExecutor
    private let textSys: AndroidTextSystem
    private let primaryDisplayRef: AndroidDisplay
    private var currentAppearance: WindowAppearance
    private var currentKeyboardLayout: AndroidKeyboardLayout
    private let currentKeyboardMapper = AndroidKeyboardMapper()

    private var windowEntries: [(handle: AnyWindowHandle, window: AndroidWindow)] = []
    private var clipboardCache: ClipboardItem?
    private var primaryPasteboardCache: ClipboardItem?
    private var findPasteboardCache: ClipboardItem?
    private var credentialsStore: [String: (String, Data)] = [:]
    private var ownedMenus: [OwnedMenu] = []
    private var openedUrlsHistory: [String] = []
    private var hasQuit: Bool = false

    /// When true, `run(_:)` drives `dispatcher.runStandaloneLoop()` until `quit()` is called
    /// (useful for standalone NDK binaries outside an Android `Activity`).
    public var runStandaloneEventLoop: Bool = false

    private var onKeyboardLayoutChangeCallbacks: [() -> Void] = []
    private var onThermalStateChangeCallbacks: [() -> Void] = []
    private var onReopenCallbacks: [() -> Void] = []
    private var onOpenUrlsCallbacks: [([String]) -> Void] = []
    private var onQuitCallbacks: [() -> Void] = []
    private var onWillOpenAppMenuCallbacks: [@MainActor () -> Void] = []
    private var onValidateAppMenuCommandCallbacks: [@MainActor (any Action) -> Bool] = []
    private var onAppMenuActionCallbacks: [@MainActor (any Action) -> Void] = []

    #if os(Android)
    private let sharedGpuContext = GpuContext()
    private var pendingSurfaceWindow: OpaquePointer?
    private var pendingSurfaceGeometry: (widthPx: Int32, heightPx: Int32, format: Int32) = (0, 0, 0)
    #endif

    public init(
        headless: Bool = false,
        displayMetrics: AndroidDisplayMetrics = AndroidDisplayMetrics(),
        appearance: WindowAppearance = .dark,
        registerInGlobalRegistry: Bool? = nil
    ) {
        self.isHeadless = headless
        let disp = AndroidDispatcher(attachCurrentThreadLooper: !headless)
        self.dispatcher = disp
        self.backgroundExec = GPUI.BackgroundExecutor(dispatcher: disp)
        self.foregroundExec = GPUI.ForegroundExecutor(dispatcher: disp)
        self.textSys = AndroidTextSystem(scanSystemFonts: !headless)
        self.primaryDisplayRef = AndroidDisplay(id: DisplayId(0), metrics: displayMetrics)
        self.lifecycle = AndroidLifecycleController(initialPhase: headless ? .resumed : .created)
        self.currentAppearance = appearance
        self.currentKeyboardLayout = AndroidKeyboardLayout()

        let shouldRegister = registerInGlobalRegistry ?? !headless
        if shouldRegister {
            AndroidPlatformRegistry.shared.setActivePlatform(self)
        }
    }

    deinit {
        #if os(Android)
        if let pending = pendingSurfaceWindow {
            candroid_native_window_release(pending)
            pendingSurfaceWindow = nil
        }
        #endif
    }

    // MARK: - Platform Protocol Conformance

    public func textSystem() -> any PlatformTextSystem {
        textSys
    }

    public func backgroundExecutor() -> GPUI.BackgroundExecutor? {
        backgroundExec
    }

    public func foregroundExecutor() -> GPUI.ForegroundExecutor? {
        foregroundExec
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        dispatcher.attachCurrentThreadAsMain()
        onFinishLaunching()
        _ = dispatcher.drainMainThreadTasks()

        if runStandaloneEventLoop {
            dispatcher.runStandaloneLoop()
        }
    }

    public func quit() {
        lock.lock()
        guard !hasQuit else {
            lock.unlock()
            return
        }
        hasQuit = true
        let quitCbs = onQuitCallbacks
        let windows = windowEntries.map(\.window)
        lock.unlock()

        for win in windows {
            win.detachSurface()
            win.notifyClose()
        }
        dispatcher.stop()
        #if os(Android)
        if !isHeadless {
            _ = candroid_host_finish_activity()
        }
        #endif
        for cb in quitCbs {
            cb()
        }
    }

    public func restart(path: URL?) {
        _ = path
    }

    public func activate(ignoringOtherApps: Bool) {
        _ = ignoringOtherApps
        lock.lock()
        let topWindow = windowEntries.last?.window
        lock.unlock()
        topWindow?.activate()
    }

    public func hide() {}

    public func hideOtherApps() {}

    public func unhideOtherApps() {}

    /// Convenience accessor returning the active `AndroidDisplay`.
    public func activeDisplay() -> AndroidDisplay {
        primaryDisplayRef
    }

    public func displays() -> [any PlatformDisplay] {
        [primaryDisplayRef]
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        primaryDisplayRef
    }

    public func activeWindow() -> AnyWindowHandle? {
        lock.lock()
        defer { lock.unlock() }
        return windowEntries.last?.handle
    }

    public func windowStack() -> [AnyWindowHandle]? {
        lock.lock()
        defer { lock.unlock() }
        guard !windowEntries.isEmpty else { return nil }
        return windowEntries.reversed().map(\.handle)
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        lock.lock()
        let appearance = currentAppearance
        let isActive = lifecycle.isActive || isHeadless
        #if os(Android)
        let window = AndroidWindow(
            handle: handle,
            options: options,
            display: primaryDisplayRef,
            appearance: appearance,
            isActive: isActive,
            gpuContext: sharedGpuContext
        )
        let savedSurface = pendingSurfaceWindow
        let savedGeom = pendingSurfaceGeometry
        pendingSurfaceWindow = nil
        #else
        let window = AndroidWindow(
            handle: handle,
            options: options,
            display: primaryDisplayRef,
            appearance: appearance,
            isActive: isActive
        )
        #endif
        windowEntries.removeAll { $0.handle == handle }
        windowEntries.append((handle: handle, window: window))
        lock.unlock()

        #if os(Android)
        if let savedSurface {
            window.attachSurface(
                nativeWindow: savedSurface,
                widthPx: savedGeom.widthPx,
                heightPx: savedGeom.heightPx,
                format: savedGeom.format
            )
            candroid_native_window_release(savedSurface)
        }
        #endif

        return window
    }

    /// Requests a vsync frame on the active window via `AChoreographer`.
    public func requestFrame() {
        lock.lock()
        let topWindow = windowEntries.last?.window
        lock.unlock()
        topWindow?.requestFrame()
    }

    public func windowAppearance() -> WindowAppearance {
        lock.lock()
        defer { lock.unlock() }
        return currentAppearance
    }

    public func buttonLayout() -> WindowButtonLayout? {
        nil
    }

    public func thermalState() -> ThermalState {
        lifecycle.thermalState
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        lock.lock()
        defer { lock.unlock() }
        return currentKeyboardLayout
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        currentKeyboardMapper
    }

    public func readFromClipboard() -> ClipboardItem? {
        #if os(Android)
        if !isHeadless {
            var buffer = [CChar](repeating: 0, count: 65_536)
            let fetched = buffer.withUnsafeMutableBufferPointer { ptr -> String? in
                guard let base = ptr.baseAddress else { return nil }
                guard candroid_host_get_clipboard_text(base, ptr.count) else { return nil }
                return String(cString: base)
            }
            if let fetched {
                let item = ClipboardItem(text: fetched)
                lock.lock()
                clipboardCache = item
                lock.unlock()
                return item
            }
        }
        #endif
        lock.lock()
        defer { lock.unlock() }
        return clipboardCache
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        lock.lock()
        clipboardCache = item
        lock.unlock()

        #if os(Android)
        if !isHeadless, let text = item.text {
            text.withCString { cStr in
                _ = candroid_host_set_clipboard_text(cStr)
            }
        }
        #endif
    }

    public func readFromPrimary() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return primaryPasteboardCache
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        lock.lock()
        primaryPasteboardCache = item
        lock.unlock()
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return findPasteboardCache
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        lock.lock()
        findPasteboardCache = item
        lock.unlock()
    }

    private func withLock<R>(_ body: () -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        withLock {
            credentialsStore[url] = (username, password)
        }
        #if os(Android)
        if !isHeadless {
            let b64 = password.base64EncodedString()
            _ = url.withCString { urlPtr in
                username.withCString { userPtr in
                    b64.withCString { passPtr in
                        candroid_host_write_credential(urlPtr, userPtr, passPtr)
                    }
                }
            }
        }
        #endif
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        #if os(Android)
        if !isHeadless {
            var userBuf = [CChar](repeating: 0, count: 4096)
            var passBuf = [CChar](repeating: 0, count: 65_536)
            let hostPair: (String, Data)? = url.withCString { urlPtr in
                userBuf.withUnsafeMutableBufferPointer { uPtr in
                    passBuf.withUnsafeMutableBufferPointer { pPtr in
                        guard let uBase = uPtr.baseAddress, let pBase = pPtr.baseAddress else {
                            return nil
                        }
                        guard candroid_host_read_credential(urlPtr, uBase, uPtr.count, pBase, pPtr.count) else {
                            return nil
                        }
                        let user = String(cString: uBase)
                        let passB64 = String(cString: pBase)
                        guard let decoded = Data(base64Encoded: passB64) else {
                            return nil
                        }
                        return (user, decoded)
                    }
                }
            }
            if let hostPair {
                withLock {
                    credentialsStore[url] = hostPair
                }
                return hostPair
            }
        }
        #endif
        return withLock {
            credentialsStore[url]
        }
    }

    public func deleteCredentials(url: String) async throws {
        withLock {
            _ = credentialsStore.removeValue(forKey: url)
        }
        #if os(Android)
        if !isHeadless {
            _ = url.withCString { urlPtr in
                candroid_host_delete_credential(urlPtr)
            }
        }
        #endif
    }

    public func openUrl(_ url: String) {
        lock.lock()
        openedUrlsHistory.append(url)
        lock.unlock()

        #if os(Android)
        if !isHeadless {
            url.withCString { cStr in
                _ = candroid_host_open_url(cStr)
            }
        }
        #endif
    }

    public var openedUrls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return openedUrlsHistory
    }

    public func registerUrlScheme(_ scheme: String) async throws {
        _ = scheme
    }

    public func appPath() throws -> URL {
        if let firstArg = ProcessInfo.processInfo.arguments.first, !firstArg.isEmpty {
            return URL(fileURLWithPath: firstArg)
        }
        return URL(fileURLWithPath: "/")
    }

    public func compositorName() -> String {
        isHeadless ? "AndroidHeadless" : "SurfaceFlinger"
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        throw AndroidError("Auxiliary executables are not supported on Android (\(name))")
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        _ = options
        return nil
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        _ = directory
        _ = suggestedName
        return nil
    }

    public func revealPath(_ path: URL) {
        openUrl(path.absoluteString)
    }

    public func openWithSystem(_ path: URL) {
        openUrl(path.absoluteString)
    }

    public func shouldAutoHideScrollbars() -> Bool {
        true
    }

    public func isScreenCaptureSupported() -> Bool {
        false
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        []
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        _ = keymap
        let converted = menus.map { $0.owned() }
        lock.lock()
        ownedMenus = converted
        lock.unlock()
    }

    public func getMenus() -> [OwnedMenu]? {
        lock.lock()
        defer { lock.unlock() }
        return ownedMenus
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {
        _ = menus
        _ = keymap
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

    public func canSelectMixedFilesAndDirs() -> Bool {
        false
    }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        lock.lock()
        onKeyboardLayoutChangeCallbacks.append(callback)
        lock.unlock()
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        lock.lock()
        onThermalStateChangeCallbacks.append(callback)
        lock.unlock()
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        lock.lock()
        onReopenCallbacks.append(callback)
        lock.unlock()
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        lock.lock()
        onOpenUrlsCallbacks.append(callback)
        lock.unlock()
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        lock.lock()
        onQuitCallbacks.append(callback)
        lock.unlock()
    }

    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        lock.lock()
        onWillOpenAppMenuCallbacks.append(callback)
        lock.unlock()
    }

    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        lock.lock()
        onValidateAppMenuCommandCallbacks.append(callback)
        lock.unlock()
    }

    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        lock.lock()
        onAppMenuActionCallbacks.append(callback)
        lock.unlock()
    }

    // MARK: - JNI & Host Event Dispatch

    /// Returns the frontmost `AndroidWindow` if one has been opened.
    public var primaryAndroidWindow: AndroidWindow? {
        lock.lock()
        defer { lock.unlock() }
        return windowEntries.last?.window
    }

    /// Updates initial display density/size and binds the UI thread `ALooper` during `GPUINative.nativeInit`.
    public func handleNativeInit(
        density: Float,
        widthPx: Int32,
        heightPx: Int32,
        refreshRateHz: Float = 60.0
    ) {
        dispatcher.attachCurrentThreadAsMain()
        primaryDisplayRef.updateSize(
            widthPx: widthPx,
            heightPx: heightPx,
            density: density,
            refreshRateHz: refreshRateHz
        )
    }

    #if os(Android)
    /// Handles `SurfaceHolder.Callback.surfaceCreated` by attaching `ANativeWindow` to the active window
    /// (or retaining it until `openWindow` is called).
    public func handleSurfaceCreated(
        nativeWindow: OpaquePointer,
        widthPx: Int32 = 0,
        heightPx: Int32 = 0,
        format: Int32 = 0
    ) {
        let resolvedW = widthPx > 0 ? widthPx : max(1, candroid_native_window_get_width(nativeWindow))
        let resolvedH = heightPx > 0 ? heightPx : max(1, candroid_native_window_get_height(nativeWindow))
        _ = lifecycle.onSurfaceCreated(widthPx: resolvedW, heightPx: resolvedH, format: format)

        lock.lock()
        if let activeWin = windowEntries.last?.window {
            if let oldPending = pendingSurfaceWindow {
                candroid_native_window_release(oldPending)
                pendingSurfaceWindow = nil
            }
            lock.unlock()
            activeWin.attachSurface(
                nativeWindow: nativeWindow,
                widthPx: resolvedW,
                heightPx: resolvedH,
                format: format
            )
        } else {
            if let oldPending = pendingSurfaceWindow {
                candroid_native_window_release(oldPending)
            }
            candroid_native_window_acquire(nativeWindow)
            pendingSurfaceWindow = nativeWindow
            pendingSurfaceGeometry = (resolvedW, resolvedH, format)
            lock.unlock()
        }
    }
    #endif

    /// Handles `SurfaceHolder.Callback.surfaceChanged`.
    public func handleSurfaceChanged(
        widthPx: Int32,
        heightPx: Int32,
        format: Int32 = 0,
        density: Float? = nil,
        refreshRateHz: Float? = nil
    ) {
        _ = lifecycle.onSurfaceChanged(widthPx: widthPx, heightPx: heightPx, format: format)
        primaryDisplayRef.updateSize(
            widthPx: widthPx,
            heightPx: heightPx,
            density: density,
            refreshRateHz: refreshRateHz
        )

        lock.lock()
        #if os(Android)
        if pendingSurfaceWindow != nil {
            pendingSurfaceGeometry = (widthPx, heightPx, format)
        }
        #endif
        let windows = windowEntries.map(\.window)
        lock.unlock()

        for win in windows {
            win.surfaceChanged(
                widthPx: widthPx,
                heightPx: heightPx,
                format: format,
                density: density,
                refreshRateHz: refreshRateHz
            )
        }
    }

    /// Handles `SurfaceHolder.Callback.surfaceDestroyed` by immediately tearing down the Vulkan surface.
    public func handleSurfaceDestroyed() {
        _ = lifecycle.onSurfaceDestroyed()

        lock.lock()
        #if os(Android)
        let savedPending = pendingSurfaceWindow
        pendingSurfaceWindow = nil
        pendingSurfaceGeometry = (0, 0, 0)
        #endif
        let windows = windowEntries.map(\.window)
        lock.unlock()

        #if os(Android)
        if let savedPending {
            candroid_native_window_release(savedPending)
        }
        #endif

        for win in windows {
            win.detachSurface()
        }
    }

    /// Dispatches a touch/pointer `MotionEvent` to the active `AndroidWindow`.
    @discardableResult
    public func handleTouchEvent(
        rawAction: Int32,
        pointers: [AndroidPointerSample],
        metaState: Int32 = 0,
        buttonState: Int32 = 0,
        vScroll: Float = 0.0,
        hScroll: Float = 0.0,
        eventTimeSeconds: Double = 0.0
    ) -> [PlatformInput] {
        guard let win = primaryAndroidWindow else { return [] }
        return win.handleTouchEvent(
            rawAction: rawAction,
            pointers: pointers,
            metaState: metaState,
            buttonState: buttonState,
            vScroll: vScroll,
            hScroll: hScroll,
            eventTimeSeconds: eventTimeSeconds
        )
    }

    /// Dispatches a hardware/soft `KeyEvent` to the active `AndroidWindow`.
    @discardableResult
    public func handleKeyEvent(
        action: Int32,
        keyCode: Int32,
        metaState: Int32 = 0,
        repeatCount: Int32 = 0,
        unicodeChar: Int32 = 0,
        scanCode: Int32 = 0
    ) -> [PlatformInput] {
        guard let win = primaryAndroidWindow else { return [] }
        return win.handleKeyEvent(
            action: action,
            keyCode: keyCode,
            metaState: metaState,
            repeatCount: repeatCount,
            unicodeChar: unicodeChar,
            scanCode: scanCode
        )
    }

    /// Updates safe-area `WindowInsets` on the active display and notifies open windows.
    public func handleInsetsChanged(topPx: Int32, leftPx: Int32, bottomPx: Int32, rightPx: Int32) {
        primaryDisplayRef.updateSafeAreaInsets(
            topPx: topPx,
            leftPx: leftPx,
            bottomPx: bottomPx,
            rightPx: rightPx
        )
        lock.lock()
        let windows = windowEntries.map(\.window)
        lock.unlock()

        for win in windows {
            win.updateSafeAreaInsets(
                topPx: topPx,
                leftPx: leftPx,
                bottomPx: bottomPx,
                rightPx: rightPx
            )
        }
    }

    /// Updates dark/light theme appearance from Android `Configuration.uiMode`.
    public func handleAppearanceChanged(isDark: Bool) {
        let newAppearance: WindowAppearance = isDark ? .dark : .light
        lock.lock()
        currentAppearance = newAppearance
        let windows = windowEntries.map(\.window)
        lock.unlock()

        for win in windows {
            win.updateAppearance(newAppearance)
        }
    }

    /// Applies an Android `Activity` lifecycle transition and executes resulting window/GPU/app effects.
    public func handleLifecycleState(_ phase: AndroidLifecyclePhase) {
        let effects = lifecycle.transition(to: phase)

        lock.lock()
        let windows = windowEntries.map(\.window)
        let reopenCbs = effects.didReopen ? onReopenCallbacks : []
        lock.unlock()

        if let active = effects.activeChanged {
            for win in windows {
                win.setActiveStatus(active)
            }
        }
        if effects.shouldReleaseGpuSurface {
            for win in windows {
                win.detachSurface()
            }
        }
        if effects.shouldResumeRendering {
            for win in windows {
                win.requestFrame()
            }
        }
        for cb in reopenCbs {
            cb()
        }
        if effects.shouldQuitApp {
            quit()
        }
    }

    /// Updates system thermal status and invokes `onThermalStateChange` observers if changed.
    public func handleThermalStatus(_ androidStatus: Int32) {
        guard lifecycle.updateThermalStatus(androidStatus) != nil else { return }
        lock.lock()
        let cbs = onThermalStateChangeCallbacks
        lock.unlock()
        for cb in cbs {
            cb()
        }
    }

    /// Updates keyboard layout metadata and notifies `onKeyboardLayoutChange` observers.
    public func updateKeyboardLayout(_ layout: AndroidKeyboardLayout) {
        lock.lock()
        guard currentKeyboardLayout != layout else {
            lock.unlock()
            return
        }
        currentKeyboardLayout = layout
        let cbs = onKeyboardLayoutChangeCallbacks
        lock.unlock()
        for cb in cbs {
            cb()
        }
    }

    /// Advances vsync frame callbacks and queued main-thread tasks on `GPUINative.nativeOnFrame`.
    public func handleFrame(frameTimeNanos: Int64) {
        _ = dispatcher.drainMainThreadTasks()
        guard lifecycle.canRender || isHeadless else { return }
        lock.lock()
        let windows = windowEntries.map(\.window)
        lock.unlock()
        for win in windows {
            win.stepFrame(frameTimeNanos: frameTimeNanos)
        }
    }

    /// Routes committed UTF-8 text from Android's `InputConnection.commitText`.
    public func handleCommitText(_ text: String) {
        primaryAndroidWindow?.commitImeText(text)
    }

    /// Routes active preedit composition text from Android's `InputConnection.setComposingText`.
    public func handleSetComposingText(_ text: String, newSelectedRangeUtf16: Range<Int>? = nil) {
        primaryAndroidWindow?.setComposingText(text, newSelectedRangeUtf16: newSelectedRangeUtf16)
    }

    /// Routes `InputConnection.finishComposingText` from Android soft keyboards.
    public func handleFinishComposingText() {
        primaryAndroidWindow?.finishComposingText()
    }

    /// Routes `InputConnection.deleteSurroundingText` from Android soft keyboards.
    public func handleDeleteSurroundingText(beforeLength: Int, afterLength: Int) {
        primaryAndroidWindow?.deleteSurroundingText(
            beforeLength: beforeLength,
            afterLength: afterLength
        )
    }

    /// Routes incoming deep-link / `Intent.ACTION_VIEW` URLs to registered `onOpenUrls` callbacks.
    public func handleIncomingUrls(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        lock.lock()
        let cbs = onOpenUrlsCallbacks
        lock.unlock()
        for cb in cbs {
            cb(urls)
        }
    }
}
