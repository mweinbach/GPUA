// Ported from: crates/gpui_windows/src/platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUICollections
import GPUIUtil
import Scheduler
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Keyboard Layout

public struct WindowsKeyboardLayout: PlatformKeyboardLayout, Sendable {
    public let id: String
    public let name: String

    public init(id: String = "00000409", name: String = "US") {
        self.id = id
        self.name = name
    }
}

// MARK: - Platform Callbacks Container

// PORT NOTE: WindowsPlatformCallbacks stores mutable callback arrays accessed from the main event pump.
final class WindowsPlatformCallbacks: @unchecked Sendable {
    var openUrls: [([String]) -> Void] = []
    var quit: [() -> Void] = []
    var reopen: [() -> Void] = []
    var keyboardLayoutChange: [() -> Void] = []
    var thermalStateChange: [() -> Void] = []
    var willOpenAppMenu: [@MainActor () -> Void] = []
    var validateAppMenuCommand: [@MainActor (any Action) -> Bool] = []
    var appMenuAction: [@MainActor (any Action) -> Void] = []
}

// MARK: - WindowsPlatform

// PORT NOTE: WindowsPlatform coordinates the Win32 window message loop, dispatcher, and display abstractions across threads.
public final class WindowsPlatform: Platform, @unchecked Sendable {
    public let headless: Bool
    public let dispatcher: WindowsDispatcher
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor
    public let textSystem: any PlatformTextSystem
    public let validationNumber: UInt
    public private(set) var messageHwnd: OpaquePointer?
    public private(set) var currentCursor: OpaquePointer?

    private let lock = NSLock()
    private var rawWindowHandles: [OpaquePointer] = []
    private var windowObjects: [AnyWindowHandle: any PlatformWindow] = [:]
    private var isQuit: Bool = false
    private let callbacks = WindowsPlatformCallbacks()
    private var storedMenus: [OwnedMenu] = []
    private var dockMenuItems: [MenuItem] = []
    private let vsyncProvider: VSyncProvider

    public init(headless: Bool = false) {
        self.headless = headless
        self.validationNumber = 0x8001
        self.vsyncProvider = VSyncProvider()

        _ = cwin_win32_ole_initialize()

        let disp = WindowsDispatcher(validationNumber: validationNumber)
        self.dispatcher = disp
        self.backgroundExecutor = BackgroundExecutor(dispatcher: disp)
        self.foregroundExecutor = ForegroundExecutor(dispatcher: disp)

        if headless {
            self.textSystem = NoopTextSystem()
        } else {
            self.textSystem = NoopTextSystem()
        }

        // Register window class for message-only anchor window
        let className = toWideString(PLATFORM_WINDOW_CLASS_NAME)
        className.withUnsafeBufferPointer { buf in
            _ = cwin_win32_register_window_class(buf.baseAddress, nil, nil)
        }

        // Create message-only anchor window
        let hwnd = className.withUnsafeBufferPointer { buf in
            cwin_win32_create_message_window(buf.baseAddress, nil, nil)
        }
        if let hwnd = hwnd {
            self.messageHwnd = OpaquePointer(hwnd)
            disp.setPlatformWindowHandle(OpaquePointer(hwnd))
        }

        self.currentCursor = loadCursor(style: .arrow)
    }

    deinit {
        if let hwnd = messageHwnd {
            _ = cwin_win32_destroy_window(hwnd)
        }
        cwin_win32_ole_uninitialize()
    }

    // MARK: - Platform Protocol Conformance

    public func textSystem() -> any PlatformTextSystem {
        textSystem
    }

    public func backgroundExecutor() -> BackgroundExecutor? {
        backgroundExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        foregroundExecutor
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        onFinishLaunching()

        if !headless {
            beginVsyncThread()
        }

        var msgBuffer = [UInt8](repeating: 0, count: 64)
        while !isQuit {
            let res = msgBuffer.withUnsafeMutableBytes { buf in
                cwin_win32_get_message(buf.baseAddress, nil, 0, 0)
            }
            if res <= 0 {
                break
            }
            msgBuffer.withUnsafeBytes { buf in
                _ = cwin_win32_translate_message(buf.baseAddress)
                _ = cwin_win32_dispatch_message(buf.baseAddress)
            }
        }

        lock.lock()
        let quitCbs = callbacks.quit
        lock.unlock()
        for cb in quitCbs {
            cb()
        }
    }

    public func quit() {
        lock.lock()
        isQuit = true
        lock.unlock()
        cwin_win32_post_quit_message(0)
    }

    public func restart(path: URL?) {
        quit()
    }

    public func activate(ignoringOtherApps: Bool) {
        // Activate current active window
        if let top = activeWindow() {
            windowObjects[top]?.activate()
        }
    }

    public func hide() {}

    public func hideOtherApps() {}

    public func unhideOtherApps() {}

    public func displays() -> [any PlatformDisplay] {
        WindowsDisplay.displays()
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        WindowsDisplay.primaryMonitor()
    }

    public func activeWindow() -> AnyWindowHandle? {
        lock.lock()
        defer { lock.unlock() }
        let h = cwin_win32_get_active_window()
        guard let h = h else { return windowObjects.keys.first }
        let targetPtr = OpaquePointer(h)
        for (handle, win) in windowObjects {
            if let ptr = win.rawNativeViewPtr(), OpaquePointer(ptr) == targetPtr {
                return handle
            }
        }
        return windowObjects.keys.first
    }

    public func windowStack() -> [AnyWindowHandle]? {
        lock.lock()
        defer { lock.unlock() }
        return Array(windowObjects.keys)
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        let win = DefaultPlatformWindow(
            windowBounds: options.bounds,
            windowScaleFactor: 1.0,
            windowAppearance: windowAppearance()
        )
        lock.lock()
        windowObjects[handle] = win
        lock.unlock()
        return win
    }

    public func windowAppearance() -> WindowAppearance {
        systemAppearance()
    }

    public func buttonLayout() -> WindowButtonLayout? {
        .right
    }

    public func thermalState() -> ThermalState {
        .nominal
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        WindowsKeyboardLayout()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        DummyKeyboardMapper()
    }

    // MARK: - Clipboard

    public func readFromClipboard() -> ClipboardItem? {
        var textPtr: UnsafeMutablePointer<wchar_t>? = nil
        var len: Int = 0
        guard cwin_win32_clipboard_get_text(nil, &textPtr, &len) == 0, let textPtr = textPtr else {
            return nil
        }
        defer { cwin_win32_clipboard_free_text(textPtr) }
        let text = fromWideString(textPtr, length: len)
        return ClipboardItem.string(text)
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        if let text = item.text {
            let wide = toWideString(text)
            wide.withUnsafeBufferPointer { buf in
                _ = cwin_win32_clipboard_set_text(nil, buf.baseAddress, text.utf16.count)
            }
        }
    }

    public func readFromPrimary() -> ClipboardItem? {
        readFromClipboard()
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        writeToClipboard(item)
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        nil
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {}

    // MARK: - Credentials

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        let targetName = toWideString(windowsCredentialsTargetName(url: url))
        let userWide = toWideString(username)
        let blobBytes = [UInt8](password)

        let status = targetName.withUnsafeBufferPointer { targetBuf in
            userWide.withUnsafeBufferPointer { userBuf in
                blobBytes.withUnsafeBufferPointer { blobBuf in
                    cwin_win32_cred_write(
                        targetBuf.baseAddress,
                        userBuf.baseAddress,
                        blobBuf.baseAddress,
                        blobBuf.count
                    )
                }
            }
        }
        if status != 0 {
            throw NSError(domain: "GPUIWindows", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CredWrite failed with code \(status)"])
        }
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        let targetName = toWideString(windowsCredentialsTargetName(url: url))
        var userPtr: UnsafeMutablePointer<wchar_t>? = nil
        var blobPtr: UnsafeMutablePointer<UInt8>? = nil
        var blobLen: Int = 0

        let status = targetName.withUnsafeBufferPointer { targetBuf in
            cwin_win32_cred_read(
                targetBuf.baseAddress,
                &userPtr,
                &blobPtr,
                &blobLen
            )
        }
        guard status == 0, let userPtr = userPtr else { return nil }
        defer {
            cwin_win32_cred_free(userPtr)
            if let blobPtr = blobPtr {
                cwin_win32_cred_free(blobPtr)
            }
        }

        let username = fromWideString(userPtr)
        let data: Data
        if let blobPtr = blobPtr, blobLen > 0 {
            data = Data(bytes: blobPtr, count: blobLen)
        } else {
            data = Data()
        }
        return (username, data)
    }

    public func deleteCredentials(url: String) async throws {
        let targetName = toWideString(windowsCredentialsTargetName(url: url))
        let status = targetName.withUnsafeBufferPointer { targetBuf in
            cwin_win32_cred_delete(targetBuf.baseAddress)
        }
        if status != 0 {
            throw NSError(domain: "GPUIWindows", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "CredDelete failed with code \(status)"])
        }
    }

    // MARK: - Shell & File Dialogs

    public func openUrl(_ url: String) {
        let wide = toWideString(url)
        wide.withUnsafeBufferPointer { buf in
            _ = cwin_win32_shell_open(buf.baseAddress)
        }
    }

    public func registerUrlScheme(_ scheme: String) async throws {}

    public func appPath() throws -> URL {
        if let path = Bundle.main.executablePath {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: CommandLine.arguments[0])
    }

    public func compositorName() -> String {
        "Direct3D 11"
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        let base = try appPath().deletingLastPathComponent()
        return base.appendingPathComponent(name).appendingPathExtension("exe")
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        let allowMulti = options.multiple ? 1 : 0
        let pickFolders = options.directories ? 1 : 0
        var pathsPtr: UnsafeMutablePointer<UnsafeMutablePointer<wchar_t>?>? = nil
        var count: Int = 0

        let okLabelWide = options.prompt.map { toWideString($0) }
        let okPtr = okLabelWide?.withUnsafeBufferPointer { $0.baseAddress }

        let status = cwin_win32_file_open_dialog(
            messageHwnd,
            Int32(allowMulti),
            Int32(pickFolders),
            okPtr,
            &pathsPtr,
            &count
        )
        guard status == 0, let pathsPtr = pathsPtr, count > 0 else { return nil }
        defer { cwin_win32_free_path_list(pathsPtr, count) }

        var urls: [URL] = []
        for i in 0..<count {
            if let pathW = pathsPtr[i] {
                let pathStr = fromWideString(pathW)
                urls.append(URL(fileURLWithPath: pathStr))
            }
        }
        return urls
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        let dirWide = toWideString(directory.path)
        let nameWide = suggestedName.map { toWideString($0) }
        let dirPtr = dirWide.withUnsafeBufferPointer { $0.baseAddress }
        let namePtr = nameWide?.withUnsafeBufferPointer { $0.baseAddress }

        var outPath: UnsafeMutablePointer<wchar_t>? = nil
        let status = cwin_win32_file_save_dialog(
            messageHwnd,
            dirPtr,
            namePtr,
            &outPath
        )
        guard status == 0, let outPath = outPath else { return nil }
        defer { cwin_win32_cred_free(outPath) }

        let pathStr = fromWideString(outPath)
        return URL(fileURLWithPath: pathStr)
    }

    public func revealPath(_ path: URL) {
        let wide = toWideString(path.path)
        wide.withUnsafeBufferPointer { buf in
            _ = cwin_win32_shell_reveal(buf.baseAddress)
        }
    }

    public func openWithSystem(_ path: URL) {
        let wide = toWideString(path.path)
        wide.withUnsafeBufferPointer { buf in
            _ = cwin_win32_shell_open(buf.baseAddress)
        }
    }

    public func shouldAutoHideScrollbars() -> Bool {
        var autoHide: Int32 = 0
        if cwin_win32_should_auto_hide_scrollbars(&autoHide) == 0 {
            return autoHide == 1
        }
        return false
    }

    public func isScreenCaptureSupported() -> Bool {
        false
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        []
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        lock.lock()
        storedMenus = menus.map { $0.owned() }
        lock.unlock()
    }

    public func getMenus() -> [OwnedMenu]? {
        lock.lock()
        defer { lock.unlock() }
        return storedMenus
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {
        lock.lock()
        dockMenuItems = menus
        lock.unlock()
    }

    public func performDockMenuAction(_ action: Int) {
        lock.lock()
        let items = dockMenuItems
        lock.unlock()
        guard action >= 0 && action < items.count else { return }
        let item = items[action]
        if let act = item.action {
            callbacks.appMenuAction.first?(act)
        }
    }

    public func addRecentDocument(_ path: URL) {}

    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] {
        entries
    }

    public func canSelectMixedFilesAndDirs() -> Bool {
        false
    }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.keyboardLayoutChange.append(callback)
        lock.unlock()
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.thermalStateChange.append(callback)
        lock.unlock()
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.reopen.append(callback)
        lock.unlock()
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        lock.lock()
        callbacks.openUrls.append(callback)
        lock.unlock()
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.quit.append(callback)
        lock.unlock()
    }

    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        lock.lock()
        callbacks.willOpenAppMenu.append(callback)
        lock.unlock()
    }

    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        lock.lock()
        callbacks.validateAppMenuCommand.append(callback)
        lock.unlock()
    }

    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        lock.lock()
        callbacks.appMenuAction.append(callback)
        lock.unlock()
    }

    // MARK: - Private Helpers

    private func beginVsyncThread() {
        let vsync = self.vsyncProvider
        Thread.detachNewThread { [weak self] in
            while true {
                vsync.waitForVsync()
                guard let self = self, !self.isQuit else { break }
                self.lock.lock()
                let windows = self.rawWindowHandles
                self.lock.unlock()
                for hwnd in windows {
                    cwin_win32_redraw_window(hwnd)
                }
            }
        }
    }
}

#endif
