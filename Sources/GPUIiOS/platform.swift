// Ported from: crates/gpui_ios/src/platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import Foundation
import GPUI
import GPUIMetal
import Security
import UIKit
import UniformTypeIdentifiers

// MARK: - Errors

/// Errors emitted by `IosPlatform` operations.
public enum IosPlatformError: Error, LocalizedError, Sendable {
    case keychainFailure(OSStatus)
    case undeclaredUrlScheme(String)
    case auxiliaryExecutableUnsupported(String)
    case screenCaptureUnsupported

    public var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "iOS Keychain operation failed with OSStatus \(status)"
        case .undeclaredUrlScheme(let scheme):
            return "URL scheme '\(scheme)' is not declared in Info.plist CFBundleURLTypes"
        case .auxiliaryExecutableUnsupported(let name):
            return "Auxiliary executables ('\(name)') are not supported on iOS sandboxed bundles"
        case .screenCaptureUnsupported:
            return "Desktop screen capture enumeration is not supported on iOS"
        }
    }
}

// MARK: - Internal Mutable Platform State

/// Mutable state container for `IosPlatform`, matching upstream `IosPlatformState`.
public final class IosPlatformState {
    var windows: [AnyWindowHandle: IosWindow] = [:]
    var windowOrder: [AnyWindowHandle] = []
    var activeWindowHandle: AnyWindowHandle?
    let instanceBufferPool = InstanceBufferPool()

    var keyboardLayout: IosKeyboardLayout
    var keyboardMapper: IosKeyboardMapper

    var keyboardLayoutChangeCallbacks: [() -> Void] = []
    var thermalStateChangeCallbacks: [() -> Void] = []
    var reopenCallbacks: [() -> Void] = []
    var openUrlsCallbacks: [([String]) -> Void] = []
    var quitCallbacks: [() -> Void] = []

    var thermalObserver: GPUIThermalObserver?
    var inputModeObserver: GPUIInputModeObserver?

    public init() {
        let initialLayout = IosKeyboardLayout.current()
        self.keyboardLayout = initialLayout
        self.keyboardMapper = IosKeyboardMapper.new(initialLayout.id)
    }
}

// MARK: - iOS Platform Implementation (`IosPlatform`)

private let gpuiClipboardMetadataPasteboardType = "org.gpui.ClipboardMetadata"

/// Native UIKit + CoreText + Metal + Security implementation of `GPUI.Platform` for iOS and visionOS.
// PORT NOTE: Synchronizes mutable `IosPlatformState` via `NSLock` and hops UIKit operations onto
// `@MainActor` when required, satisfying `Platform: Sendable` under Swift 6 strict concurrency.
public final class IosPlatform: Platform, @unchecked Sendable {
    private let lock = NSLock()
    private let state: IosPlatformState
    private let dispatcher: IosDispatcher
    private let _textSystem: IosTextSystem
    private let _backgroundExecutor: BackgroundExecutor
    private let _foregroundExecutor: ForegroundExecutor

    public init() {
        let disp = IosDispatcher.new()
        self.dispatcher = disp
        self._textSystem = IosTextSystem.new()
        self._backgroundExecutor = BackgroundExecutor.new(dispatcher: disp)
        self._foregroundExecutor = ForegroundExecutor.new(dispatcher: disp)
        self.state = IosPlatformState()

        setupObservers()
        IosPlatformRegistry.shared.register(self)
    }

    public convenience init(headless: Bool) {
        _ = headless
        self.init()
    }

    /// Creates a new `IosPlatform` matching upstream `IosPlatform::new()`.
    public static func new(_ headless: Bool = false) -> IosPlatform {
        _ = headless
        return IosPlatform()
    }

    deinit {
        IosPlatformRegistry.shared.unregister(self)
    }

    private func setupObservers() {
        let thermalObs = GPUIThermalObserver { [weak self] in
            self?.notifyThermalStateChanged()
        }
        let inputObs = GPUIInputModeObserver { [weak self] in
            self?.refreshKeyboardLayoutAndNotify()
        }

        lock.lock()
        state.thermalObserver = thermalObs
        state.inputModeObserver = inputObs
        lock.unlock()
    }

    private func notifyThermalStateChanged() {
        lock.lock()
        let callbacks = state.thermalStateChangeCallbacks
        lock.unlock()
        for cb in callbacks {
            cb()
        }
    }

    private func refreshKeyboardLayoutAndNotify() {
        let updatedLayout = IosKeyboardLayout.current()
        let updatedMapper = IosKeyboardMapper.new(updatedLayout.id)

        lock.lock()
        let changed = state.keyboardLayout != updatedLayout
        state.keyboardLayout = updatedLayout
        state.keyboardMapper = updatedMapper
        let callbacks = changed ? state.keyboardLayoutChangeCallbacks : []
        lock.unlock()

        for cb in callbacks {
            cb()
        }
    }

    func deliverOpenUrls(_ urls: [String]) {
        guard !urls.isEmpty else { return }
        lock.lock()
        let callbacks = state.openUrlsCallbacks
        lock.unlock()
        for cb in callbacks {
            cb(urls)
        }
    }

    /// Returns the typed `IosWindow` registered for `handle`, if still open.
    public func iosWindow(for handle: AnyWindowHandle) -> IosWindow? {
        lock.lock()
        defer { lock.unlock() }
        return state.windows[handle]
    }

    // MARK: - Platform Protocol Conformance

    public func textSystem() -> any PlatformTextSystem {
        _textSystem
    }

    public func backgroundExecutor() -> BackgroundExecutor? {
        _backgroundExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        _foregroundExecutor
    }

    // PORT NOTE: Transfers one-shot `Platform.run` launch callback onto the main queue.
    private struct LaunchCallbackBox: @unchecked Sendable {
        let invoke: () -> Void
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        // On iOS, `UIApplicationMain` (`@main GPUIAppDelegate`) owns the process run loop and
        // invokes GPUI from `application(_:didFinishLaunchingWithOptions:)`. Invoke
        // `onFinishLaunching` immediately on the main thread when already on main, or dispatch
        // onto `DispatchQueue.main`.
        if Thread.isMainThread {
            onFinishLaunching()
        } else {
            let box = LaunchCallbackBox(invoke: onFinishLaunching)
            DispatchQueue.main.async {
                box.invoke()
            }
        }
    }

    public func quit() {
        lock.lock()
        let callbacks = state.quitCallbacks
        lock.unlock()
        for cb in callbacks {
            cb()
        }
    }

    public func restart(path: URL?) {
        _ = path
        // iOS sandboxed apps cannot self-exec to restart.
    }

    public func activate(ignoringOtherApps: Bool) {
        _ = ignoringOtherApps
    }

    public func hide() {}
    public func hideOtherApps() {}
    public func unhideOtherApps() {}

    public func displays() -> [any PlatformDisplay] {
        IosDisplay.all()
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        IosDisplay.primary()
    }

    public func activeWindow() -> AnyWindowHandle? {
        lock.lock()
        defer { lock.unlock() }
        return state.activeWindowHandle ?? state.windowOrder.last
    }

    public func windowStack() -> [AnyWindowHandle]? {
        lock.lock()
        defer { lock.unlock() }
        return state.windowOrder.reversed()
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        lock.lock()
        let pool = state.instanceBufferPool
        lock.unlock()

        let window = IosWindow(
            handle: handle,
            options: options,
            instanceBufferPool: pool
        )

        lock.lock()
        state.windows[handle] = window
        state.windowOrder.removeAll(where: { $0 == handle })
        state.windowOrder.append(handle)
        state.activeWindowHandle = handle
        lock.unlock()

        return window
    }

    public func windowAppearance() -> WindowAppearance {
        detectSystemAppearance()
    }

    public func buttonLayout() -> WindowButtonLayout? {
        nil
    }

    public func thermalState() -> ThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return .nominal
        case .fair:
            return .fair
        case .serious:
            return .serious
        case .critical:
            return .critical
        @unknown default:
            return .nominal
        }
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        lock.lock()
        defer { lock.unlock() }
        return state.keyboardLayout
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        lock.lock()
        defer { lock.unlock() }
        return state.keyboardMapper
    }

    // MARK: - Clipboard (`UIPasteboard`)

    public func readFromClipboard() -> ClipboardItem? {
        let readOp: @MainActor () -> ClipboardItem? = {
            let pasteboard = UIPasteboard.general
            let text = pasteboard.string
            let metadata = pasteboard.data(forPasteboardType: gpuiClipboardMetadataPasteboardType)
            if let text {
                return ClipboardItem(text: text, data: metadata)
            }
            if let image = pasteboard.image, let pngData = image.pngData() {
                return ClipboardItem(text: nil, data: pngData)
            }
            if let pngData = pasteboard.data(forPasteboardType: UTType.png.identifier) {
                return ClipboardItem(text: nil, data: pngData)
            }
            return nil
        }

        if Thread.isMainThread {
            return MainActor.assumeIsolated(readOp)
        } else {
            return DispatchQueue.main.sync {
                MainActor.assumeIsolated(readOp)
            }
        }
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        let writeOp: @MainActor () -> Void = {
            let pasteboard = UIPasteboard.general
            var pasteboardItems: [[String: Any]] = []
            var entry: [String: Any] = [:]

            if let text = item.text {
                entry[UTType.utf8PlainText.identifier] = text
                if let metadata = item.data {
                    entry[gpuiClipboardMetadataPasteboardType] = metadata
                }
            } else if let data = item.data {
                if let uiImage = UIImage(data: data) {
                    entry[UTType.png.identifier] = uiImage.pngData() ?? data
                } else {
                    entry[gpuiClipboardMetadataPasteboardType] = data
                }
            }

            if !entry.isEmpty {
                pasteboardItems.append(entry)
                pasteboard.items = pasteboardItems
            } else {
                pasteboard.items = []
            }
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated(writeOp)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(writeOp)
            }
        }
    }

    public func readFromPrimary() -> ClipboardItem? { nil }
    public func writeToPrimary(_ item: ClipboardItem) { _ = item }
    public func readFromFindPasteboard() -> ClipboardItem? { nil }
    public func writeToFindPasteboard(_ item: ClipboardItem) { _ = item }

    // MARK: - Keychain Credentials (`Security.framework`)

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url,
        ]
        let attributes: [CFString: Any] = [
            kSecAttrAccount: username,
            kSecValueData: password,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addItem = query
            for (k, v) in attributes {
                addItem[k] = v
            }
            let addStatus = SecItemAdd(addItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw IosPlatformError.keychainFailure(addStatus)
            }
            return
        }
        throw IosPlatformError.keychainFailure(updateStatus)
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url,
            kSecReturnAttributes: kCFBooleanTrue as Any,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var resultRef: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &resultRef)
        if status == errSecItemNotFound || status == errSecUserCanceled {
            return nil
        }
        guard status == errSecSuccess else {
            throw IosPlatformError.keychainFailure(status)
        }
        guard let dict = resultRef as? [CFString: Any],
              let account = dict[kSecAttrAccount] as? String,
              let passwordData = dict[kSecValueData] as? Data else {
            return nil
        }
        return (account, passwordData)
    }

    public func deleteCredentials(url: String) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw IosPlatformError.keychainFailure(status)
    }

    // MARK: - URLs, Bundle Paths, and File Pickers

    public func openUrl(_ url: String) {
        guard let parsed = URL(string: url) else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                UIApplication.shared.open(parsed, options: [:], completionHandler: nil)
            }
        }
    }

    public func registerUrlScheme(_ scheme: String) async throws {
        // On iOS, custom URL schemes cannot be registered dynamically at runtime; verify that
        // `CFBundleURLTypes` in `Bundle.main.infoDictionary` declares `scheme`, matching upstream.
        let declaredTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        let normalizedTarget = scheme.lowercased()
        for urlType in declaredTypes {
            if let schemes = urlType["CFBundleURLSchemes"] as? [String],
               schemes.contains(where: { $0.lowercased() == normalizedTarget })
            {
                return
            }
        }
        throw IosPlatformError.undeclaredUrlScheme(scheme)
    }

    public func appPath() throws -> URL {
        Bundle.main.bundleURL
    }

    public func compositorName() -> String {
        "Metal"
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        let candidate = Bundle.main.bundleURL.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        throw IosPlatformError.auxiliaryExecutableUnsupported(name)
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let presenter = self?.findPresentingViewController() else {
                        continuation.resume(returning: nil)
                        return
                    }

                    var contentTypes: [UTType] = []
                    if options.files {
                        contentTypes.append(.item)
                    }
                    if options.directories {
                        contentTypes.append(.folder)
                    }
                    if contentTypes.isEmpty {
                        contentTypes.append(.item)
                    }

                    let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
                    picker.allowsMultipleSelection = options.multiple
                    let context = DocumentPickerCallbackContext(sender: .multiple(continuation))
                    let delegate = GPUIDocumentPickerDelegate(context: context)
                    picker.delegate = delegate
                    presenter.present(picker, animated: true)
                }
            }
        }
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        let fileName = (suggestedName?.isEmpty == false) ? (suggestedName ?? "Untitled") : "Untitled"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpui-ios-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let placeholderFile = tempDir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: placeholderFile.path, contents: Data())

        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let presenter = self?.findPresentingViewController() else {
                        try? FileManager.default.removeItem(at: tempDir)
                        continuation.resume(returning: nil)
                        return
                    }

                    let picker = UIDocumentPickerViewController(forExporting: [placeholderFile], asCopy: true)
                    picker.directoryURL = directory
                    let context = DocumentPickerCallbackContext(
                        sender: .single(continuation),
                        temporaryExportUrl: tempDir
                    )
                    let delegate = GPUIDocumentPickerDelegate(context: context)
                    picker.delegate = delegate
                    presenter.present(picker, animated: true)
                }
            }
        }
    }

    @MainActor
    private func findPresentingViewController() -> UIViewController? {
        if let active = activeWindow(),
           let iosWin = iosWindow(for: active),
           let rootVc = iosWin.rootViewController()
        {
            var top = rootVc
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let keyWin = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
               var top = keyWin.rootViewController
            {
                while let presented = top.presentedViewController {
                    top = presented
                }
                return top
            }
        }
        return nil
    }

    public func revealPath(_ path: URL) {
        openWithSystem(path)
    }

    public func openWithSystem(_ path: URL) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                UIApplication.shared.open(path, options: [:], completionHandler: nil)
            }
        }
    }

    public func shouldAutoHideScrollbars() -> Bool {
        true
    }

    public func isScreenCaptureSupported() -> Bool {
        false
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        throw IosPlatformError.screenCaptureUnsupported
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        _ = menus
        _ = keymap
    }

    public func getMenus() -> [OwnedMenu]? {
        nil
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
        true
    }

    // MARK: - Platform Event Callbacks

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        lock.lock()
        state.keyboardLayoutChangeCallbacks.append(callback)
        lock.unlock()
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        lock.lock()
        state.thermalStateChangeCallbacks.append(callback)
        lock.unlock()
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        lock.lock()
        state.reopenCallbacks.append(callback)
        lock.unlock()
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        lock.lock()
        state.openUrlsCallbacks.append(callback)
        lock.unlock()
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        lock.lock()
        state.quitCallbacks.append(callback)
        lock.unlock()
    }
}
#endif
