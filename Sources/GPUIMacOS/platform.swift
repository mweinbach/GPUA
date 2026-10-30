// Ported from: crates/gpui_macos/src/platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import CoreServices
import Foundation
import GPUI
import GPUIMetal
import Security
import UniformTypeIdentifiers

// MARK: - GPUIApplication & Delegate

final class GPUIApplication: NSApplication {
    weak var platformState: MacPlatformState?
}

final class GPUIApplicationDelegate: NSResponder, NSApplicationDelegate, NSMenuDelegate {
    weak var platformState: MacPlatformState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApp.setActivationPolicy(.regular)

        let nc = NotificationCenter.default
        let dnc = DistributedNotificationCenter.default()

        nc.addObserver(
            self,
            selector: #selector(handleThermalStateDidChange(_:)),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(handleKeyboardInputSourceDidChange(_:)),
            name: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil
        )

        platformState?.invokeFinishLaunchingCallback()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        _ = sender
        if !flag {
            platformState?.invokeReopenCallback()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = application
        let strings = urls.map { $0.absoluteString }
        platformState?.invokeOpenUrlsCallback(strings)
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = notification
        platformState?.invokeQuitCallback()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        _ = sender
        return platformState?.dockMenu
    }

    @objc private func handleThermalStateDidChange(_ notification: Notification) {
        _ = notification
        platformState?.invokeThermalStateCallback()
    }

    @objc private func handleKeyboardInputSourceDidChange(_ notification: Notification) {
        _ = notification
        platformState?.invokeKeyboardLayoutCallback()
    }

    // MARK: - Menu Action Dispatch & Validation

    func menuWillOpen(_ menu: NSMenu) {
        _ = menu
        MainActor.assumeIsolated {
            platformState?.willOpenMenuCallback?()
        }
    }

    @objc func dispatchMenuAction(_ sender: NSMenuItem) {
        let index = sender.tag
        MainActor.assumeIsolated {
            guard let state = platformState,
                  index >= 0,
                  index < state.menuActions.count
            else {
                return
            }
            let action = state.menuActions[index]
            state.menuCommandCallback?(action)
        }
    }

    @objc func dispatchDockMenuAction(_ sender: NSMenuItem) {
        let index = sender.tag
        MainActor.assumeIsolated {
            guard let state = platformState,
                  index >= 0,
                  index < state.dockMenuActions.count
            else {
                return
            }
            let action = state.dockMenuActions[index]
            state.menuCommandCallback?(action)
        }
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(dispatchMenuAction(_:)) {
            let index = menuItem.tag
            return MainActor.assumeIsolated {
                guard let state = platformState,
                      index >= 0,
                      index < state.menuActions.count
                else {
                    return false
                }
                if let validator = state.validateMenuCommandCallback {
                    return validator(state.menuActions[index])
                }
                return !menuItem.isHidden
            }
        }
        return true
    }
}

// MARK: - MacPlatformState

/// Mutable state owned by `MacPlatform` and synchronized across AppKit delegate callbacks.
// PORT NOTE: Synchronized via NSLock and AppKit main-thread dispatch matching upstream `Mutex<MacPlatformState>`.
public final class MacPlatformState: @unchecked Sendable {
    let lock = NSLock()
    let headless: Bool
    let pasteboard: Pasteboard = .general()
    let findPasteboard: Pasteboard = .find()
    let textSystem: MacTextSystem
    let rendererContext: RendererContext = RendererContext()

    var reopenCallbacks: [() -> Void] = []
    var quitCallbacks: [() -> Void] = []
    var openUrlsCallbacks: [([String]) -> Void] = []
    var thermalStateCallbacks: [() -> Void] = []
    var keyboardLayoutCallbacks: [() -> Void] = []
    var finishLaunchingCallback: (() -> Void)?

    var menuActions: [any Action] = []
    var dockMenuActions: [any Action] = []
    var ownedMenus: [OwnedMenu]?
    var dockMenu: NSMenu?

    var willOpenMenuCallback: (@MainActor () -> Void)?
    var validateMenuCommandCallback: (@MainActor (any Action) -> Bool)?
    var menuCommandCallback: (@MainActor (any Action) -> Void)?

    var restartPath: URL?
    var cursorHidden: Bool = false
    var appDelegate: GPUIApplicationDelegate?

    init(headless: Bool, textSystem: MacTextSystem) {
        self.headless = headless
        self.textSystem = textSystem
    }

    func invokeFinishLaunchingCallback() {
        lock.lock()
        let cb = finishLaunchingCallback
        finishLaunchingCallback = nil
        lock.unlock()
        cb?()
    }

    func invokeReopenCallback() {
        lock.lock()
        let cbs = reopenCallbacks
        lock.unlock()
        for cb in cbs { cb() }
    }

    func invokeOpenUrlsCallback(_ urls: [String]) {
        lock.lock()
        let cbs = openUrlsCallbacks
        lock.unlock()
        for cb in cbs { cb(urls) }
    }

    func invokeQuitCallback() {
        lock.lock()
        let cbs = quitCallbacks
        let relaunchURL = restartPath
        lock.unlock()

        for cb in cbs { cb() }

        if let targetURL = relaunchURL ?? (try? currentAppBundleURL()), relaunchURL != nil {
            let pid = ProcessInfo.processInfo.processIdentifier
            let escapedPath = targetURL.path.replacingOccurrences(of: "'", with: "'\\''")
            let script = """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(escapedPath)'
            """
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/sh")
            proc.arguments = ["-c", script]
            try? proc.run()
        }
    }

    func invokeThermalStateCallback() {
        lock.lock()
        let cbs = thermalStateCallbacks
        lock.unlock()
        for cb in cbs { cb() }
    }

    func invokeKeyboardLayoutCallback() {
        lock.lock()
        let cbs = keyboardLayoutCallbacks
        lock.unlock()
        for cb in cbs { cb() }
    }
}

private func currentAppBundleURL() throws -> URL {
    let bundleURL = Bundle.main.bundleURL
    if bundleURL.pathExtension == "app" {
        return bundleURL
    }
    if let execURL = Bundle.main.executableURL {
        var candidate = execURL
        while candidate.pathComponents.count > 1 {
            if candidate.pathExtension == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return execURL
    }
    throw NSError(
        domain: "GPUIMacOS.MacPlatform",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Unable to determine application path"]
    )
}

// MARK: - MacPlatform

/// Native macOS implementation of `GPUI.Platform` backed by AppKit, CoreText, Security.framework, and Metal.
// PORT NOTE: Synchronized via `MacPlatformState`'s lock and main-thread AppKit dispatch.
public final class MacPlatform: Platform, @unchecked Sendable {
    private let _dispatcher: MacDispatcher
    private let _backgroundExecutor: BackgroundExecutor
    private let _foregroundExecutor: ForegroundExecutor
    private let _textSystem: MacTextSystem
    public let state: MacPlatformState

    public init(headless: Bool = false) {
        let dispatcher = MacDispatcher.new()
        let scheduler = PlatformScheduler.new(dispatcher: dispatcher)
        let sessionId = scheduler.allocateSessionId()
        let bg = BackgroundExecutor(scheduler: scheduler, dispatcher: dispatcher)
        let fg = ForegroundExecutor(sessionId: sessionId, scheduler: scheduler, dispatcher: dispatcher)
        let ts = MacTextSystem.new()

        self._dispatcher = dispatcher
        self._backgroundExecutor = bg
        self._foregroundExecutor = fg
        self._textSystem = ts
        self.state = MacPlatformState(headless: headless, textSystem: ts)

        if !headless && Thread.isMainThread {
            MainActor.assumeIsolated {
                let app = GPUIApplication.shared as? GPUIApplication
                app?.platformState = self.state
            }
        }
    }

    public static func new(headless: Bool = false) -> MacPlatform {
        MacPlatform(headless: headless)
    }

    // MARK: - Core Executors & TextSystem

    public func textSystem() -> any PlatformTextSystem {
        _textSystem
    }

    public func backgroundExecutor() -> BackgroundExecutor? {
        _backgroundExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        _foregroundExecutor
    }

    // MARK: - Application Lifecycle

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        if state.headless {
            onFinishLaunching()
            CFRunLoopRun()
            return
        }

        state.lock.lock()
        state.finishLaunchingCallback = onFinishLaunching
        state.lock.unlock()

        MainActor.assumeIsolated {
            let app = GPUIApplication.shared
            if let gpuiApp = app as? GPUIApplication {
                gpuiApp.platformState = state
            }
            let delegate = GPUIApplicationDelegate()
            delegate.platformState = state
            state.lock.lock()
            state.appDelegate = delegate
            state.lock.unlock()

            app.delegate = delegate
            app.run()
        }
    }

    public func quit() {
        if state.headless {
            CFRunLoopStop(CFRunLoopGetMain())
            state.invokeQuitCallback()
            return
        }
        let terminateOnMain: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                NSApp?.terminate(nil)
            }
        }
        if Thread.isMainThread {
            terminateOnMain()
        } else {
            DispatchQueue.main.async(execute: terminateOnMain)
        }
    }

    public func restart(path: URL?) {
        state.lock.lock()
        state.restartPath = path ?? (try? appPath())
        state.lock.unlock()
        quit()
    }

    public func activate(ignoringOtherApps: Bool) {
        let act: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                if #available(macOS 14.0, *), ignoringOtherApps {
                    NSApp?.activate()
                } else {
                    NSApp?.activate(ignoringOtherApps: ignoringOtherApps)
                }
            }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.async(execute: act) }
    }

    public func hide() {
        let act: @Sendable () -> Void = {
            MainActor.assumeIsolated { NSApp?.hide(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.async(execute: act) }
    }

    public func hideOtherApps() {
        let act: @Sendable () -> Void = {
            MainActor.assumeIsolated { NSApp?.hideOtherApplications(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.async(execute: act) }
    }

    public func unhideOtherApps() {
        let act: @Sendable () -> Void = {
            MainActor.assumeIsolated { NSApp?.unhideAllApplications(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.async(execute: act) }
    }

    // MARK: - Displays & Windows

    public func displays() -> [any PlatformDisplay] {
        MacDisplay.all()
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        MacDisplay.primary()
    }

    public func activeWindow() -> AnyWindowHandle? {
        MacWindow.activeWindow()
    }

    public func windowStack() -> [AnyWindowHandle]? {
        MacWindow.orderedWindows()
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        MacWindow.open(
            handle: handle,
            options: options,
            foregroundExecutor: _foregroundExecutor,
            backgroundExecutor: _backgroundExecutor,
            rendererContext: state.rendererContext
        )
    }

    public func windowAppearance() -> WindowAppearance {
        let query: () -> WindowAppearance = {
            MainActor.assumeIsolated {
                windowAppearanceFromNative(NSApp?.effectiveAppearance)
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func buttonLayout() -> WindowButtonLayout? {
        WindowButtonLayout(left: true)
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

    // MARK: - Keyboard & Pasteboards

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        MacKeyboardLayout.new()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        let layout = MacKeyboardLayout.new()
        return MacKeyboardMapper.new(layout.id)
    }

    public func readFromClipboard() -> ClipboardItem? {
        state.pasteboard.readClipboardItem()
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        state.pasteboard.writeClipboardItem(item)
    }

    public func readFromPrimary() -> ClipboardItem? {
        nil
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        _ = item
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        state.findPasteboard.readClipboardItem()
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        state.findPasteboard.writeClipboardItem(item)
    }

    // MARK: - Keychain Credentials (Security.framework)

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url as CFString,
        ]
        let attributesToUpdate: [CFString: Any] = [
            kSecAttrAccount: username as CFString,
            kSecValueData: password as CFData,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecAttrAccount] = username as CFString
            addQuery[kSecValueData] = password as CFData
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(
                    domain: NSOSStatusErrorDomain,
                    code: Int(addStatus),
                    userInfo: [NSLocalizedDescriptionKey: "SecItemAdd failed with status \(addStatus)"]
                )
            }
            return
        }
        throw NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(updateStatus),
            userInfo: [NSLocalizedDescriptionKey: "SecItemUpdate failed with status \(updateStatus)"]
        )
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url as CFString,
            kSecReturnAttributes: kCFBooleanTrue as Any,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var itemOut: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &itemOut)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "SecItemCopyMatching failed with status \(status)"]
            )
        }
        guard let dict = itemOut as? [CFString: Any],
              let account = dict[kSecAttrAccount] as? String,
              let passwordData = dict[kSecValueData] as? Data
        else {
            return nil
        }
        return (account, passwordData)
    }

    public func deleteCredentials(url: String) async throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: url as CFString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "SecItemDelete failed with status \(status)"]
            )
        }
    }

    // MARK: - URLs, Bundles, Open/Save Panels & Workspace

    public func openUrl(_ url: String) {
        guard let parsed = URL(string: url) else { return }
        NSWorkspace.shared.open(parsed)
    }

    public func registerUrlScheme(_ scheme: String) async throws {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw NSError(
                domain: "GPUIMacOS.MacPlatform",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot register URL scheme without bundle identifier"]
            )
        }
        let status = LSSetDefaultHandlerForURLScheme(scheme as CFString, bundleId as CFString)
        guard status == noErr else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "LSSetDefaultHandlerForURLScheme failed: \(status)"]
            )
        }
    }

    public func appPath() throws -> URL {
        try currentAppBundleURL()
    }

    public func compositorName() -> String {
        "Quartz Compositor"
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        if let macOSDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = macOSDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw NSError(
            domain: "GPUIMacOS.MacPlatform",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Auxiliary executable '\(name)' not found in bundle"]
        )
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        await MainActor.run {
            let panel = NSOpenPanel()
            panel.canChooseFiles = options.files
            panel.canChooseDirectories = options.directories
            panel.allowsMultipleSelection = options.multiple
            panel.canCreateDirectories = true
            panel.resolvesAliases = false

            let response = panel.runModal()
            guard response == .OK else {
                return nil
            }
            return panel.urls
        }
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        await MainActor.run {
            let panel = NSSavePanel()
            panel.directoryURL = directory
            panel.canCreateDirectories = true

            // Workaround for macOS 15 Sequoia NSSavePanel bug that duplicates file extensions
            // when `nameFieldStringValue` already contains an extension (upstream `platform.rs`).
            if let suggestedName {
                if isMacosVersionAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)) {
                    let nsName = suggestedName as NSString
                    let ext = nsName.pathExtension
                    if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
                        panel.allowedContentTypes = [utType]
                        panel.allowsOtherFileTypes = true
                        panel.nameFieldStringValue = nsName.deletingPathExtension
                    } else {
                        panel.nameFieldStringValue = suggestedName
                    }
                } else {
                    panel.nameFieldStringValue = suggestedName
                }
            }

            let response = panel.runModal()
            guard response == .OK else {
                return nil
            }
            return panel.url
        }
    }

    public func revealPath(_ path: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([path])
    }

    public func openWithSystem(_ path: URL) {
        NSWorkspace.shared.open(path)
    }

    public func shouldAutoHideScrollbars() -> Bool {
        let query: () -> Bool = {
            MainActor.assumeIsolated {
                NSScroller.preferredScrollerStyle == .overlay
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func isScreenCaptureSupported() -> Bool {
        true
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        try await getSources()
    }

    public func addRecentDocument(_ path: URL) {
        let act: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                NSDocumentController.shared.noteNewRecentDocumentURL(path)
            }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.async(execute: act) }
    }

    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] {
        _ = menus
        return entries
    }

    public func canSelectMixedFilesAndDirs() -> Bool {
        true
    }

    // MARK: - Menus & Dock Menu

    public func setMenus(_ menus: [GPUI.Menu], keymap: Keymap) {
        MainActor.assumeIsolated {
            let delegate: GPUIApplicationDelegate
            state.lock.lock()
            if let existing = state.appDelegate {
                delegate = existing
            } else {
                let created = GPUIApplicationDelegate()
                created.platformState = state
                state.appDelegate = created
                delegate = created
            }
            state.menuActions.removeAll()
            state.ownedMenus = menus.map { $0.owned() }
            state.lock.unlock()

            let mapper = keyboardMapper()
            let mainMenu = NSMenu(title: "MainMenu")
            mainMenu.delegate = delegate

            for menu in menus {
                let submenuItem = NSMenuItem(title: menu.name.asString, action: nil, keyEquivalent: "")
                submenuItem.isEnabled = !menu.disabled
                let nsMenu = buildNSMenu(
                    from: menu,
                    delegate: delegate,
                    actionSelector: #selector(GPUIApplicationDelegate.dispatchMenuAction(_:)),
                    isDock: false,
                    keymap: keymap,
                    mapper: mapper
                )
                submenuItem.submenu = nsMenu
                mainMenu.addItem(submenuItem)
            }

            NSApp?.mainMenu = mainMenu
        }
    }

    public func getMenus() -> [OwnedMenu]? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.ownedMenus
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {
        MainActor.assumeIsolated {
            let delegate: GPUIApplicationDelegate
            state.lock.lock()
            if let existing = state.appDelegate {
                delegate = existing
            } else {
                let created = GPUIApplicationDelegate()
                created.platformState = state
                state.appDelegate = created
                delegate = created
            }
            state.dockMenuActions.removeAll()
            state.lock.unlock()

            let wrapper = GPUI.Menu(name: "DockMenu", items: menus, disabled: false)
            let mapper = keyboardMapper()
            let dockNSMenu = buildNSMenu(
                from: wrapper,
                delegate: delegate,
                actionSelector: #selector(GPUIApplicationDelegate.dispatchDockMenuAction(_:)),
                isDock: true,
                keymap: keymap,
                mapper: mapper
            )
            state.lock.lock()
            state.dockMenu = dockNSMenu
            state.lock.unlock()
        }
    }

    public func performDockMenuAction(_ action: Int) {
        MainActor.assumeIsolated {
            state.lock.lock()
            let actions = state.dockMenuActions
            let cb = state.menuCommandCallback
            state.lock.unlock()

            guard action >= 0, action < actions.count else { return }
            cb?(actions[action])
        }
    }

    @MainActor
    private func buildNSMenu(
        from menu: GPUI.Menu,
        delegate: GPUIApplicationDelegate,
        actionSelector: Selector,
        isDock: Bool,
        keymap: Keymap,
        mapper: any PlatformKeyboardMapper
    ) -> NSMenu {
        let nsMenu = NSMenu(title: menu.name.asString)
        nsMenu.delegate = delegate
        nsMenu.autoenablesItems = true

        for item in menu.items {
            switch item {
            case .separator:
                nsMenu.addItem(.separator())

            case .submenu(let sub):
                let subItem = NSMenuItem(title: sub.name.asString, action: nil, keyEquivalent: "")
                subItem.isEnabled = !sub.disabled
                subItem.submenu = buildNSMenu(
                    from: sub,
                    delegate: delegate,
                    actionSelector: actionSelector,
                    isDock: isDock,
                    keymap: keymap,
                    mapper: mapper
                )
                nsMenu.addItem(subItem)

            case .systemMenu(let osMenu):
                let sysItem = NSMenuItem(title: osMenu.name.asString, action: nil, keyEquivalent: "")
                let sysSubmenu = NSMenu(title: osMenu.name.asString)
                if osMenu.menuType == .services {
                    NSApp?.servicesMenu = sysSubmenu
                }
                sysItem.submenu = sysSubmenu
                nsMenu.addItem(sysItem)

            case .action(let name, let action, let osAction, let checked, let disabled):
                let nsItem = NSMenuItem(title: name.asString, action: nil, keyEquivalent: "")
                nsItem.state = checked ? .on : .off
                nsItem.isEnabled = !disabled

                if let osAction {
                    switch osAction {
                    case .cut: nsItem.action = #selector(NSText.cut(_:))
                    case .copy: nsItem.action = #selector(NSText.copy(_:))
                    case .paste: nsItem.action = #selector(NSText.paste(_:))
                    case .selectAll: nsItem.action = #selector(NSText.selectAll(_:))
                    case .undo: nsItem.action = Selector(("undo:"))
                    case .redo: nsItem.action = Selector(("redo:"))
                    }
                } else {
                    state.lock.lock()
                    let tag: Int
                    if isDock {
                        tag = state.dockMenuActions.count
                        state.dockMenuActions.append(action)
                    } else {
                        tag = state.menuActions.count
                        state.menuActions.append(action)
                    }
                    state.lock.unlock()

                    nsItem.target = delegate
                    nsItem.action = actionSelector
                    nsItem.tag = tag
                }

                // Populate key equivalent from keymap if a single-stroke binding exists
                let bindings = keymap.bindingsForAction(action)
                if let firstBinding = bindings.first, firstBinding.keystrokes.count == 1 {
                    let mapped = mapper.mapKeyEquivalent(
                        keystroke: firstBinding.keystrokes[0].inner,
                        useKeyEquivalents: true
                    )
                    nsItem.keyEquivalent = keyToNative(mapped.inner.key)
                    var mask: NSEvent.ModifierFlags = []
                    if mapped.inner.modifiers.control { mask.insert(.control) }
                    if mapped.inner.modifiers.alt { mask.insert(.option) }
                    if mapped.inner.modifiers.shift { mask.insert(.shift) }
                    if mapped.inner.modifiers.platform { mask.insert(.command) }
                    if mapped.inner.modifiers.function { mask.insert(.function) }
                    nsItem.keyEquivalentModifierMask = mask
                }

                nsMenu.addItem(nsItem)
            }
        }
        return nsMenu
    }

    // MARK: - Cursor Styling

    public func setCursorStyle(_ style: CursorStyle) {
        MainActor.assumeIsolated {
            if style == .none {
                state.lock.lock()
                let alreadyHidden = state.cursorHidden
                state.cursorHidden = true
                state.lock.unlock()
                if !alreadyHidden {
                    NSCursor.hide()
                }
                return
            }

            state.lock.lock()
            let wasHidden = state.cursorHidden
            state.cursorHidden = false
            state.lock.unlock()
            if wasHidden {
                NSCursor.unhide()
            }

            let cursor: NSCursor
            switch style {
            case .arrow, .wait, .progress:
                cursor = .arrow
            case .iBeam:
                cursor = .iBeam
            case .crosshair:
                cursor = .crosshair
            case .closedHand:
                cursor = .closedHand
            case .openHand:
                cursor = .openHand
            case .pointingHand:
                cursor = .pointingHand
            case .resizeLeft:
                cursor = .resizeLeft
            case .resizeRight:
                cursor = .resizeRight
            case .resizeLeftRight:
                cursor = .resizeLeftRight
            case .resizeUp:
                cursor = .resizeUp
            case .resizeDown:
                cursor = .resizeDown
            case .resizeUpDown:
                cursor = .resizeUpDown
            case .resizeUpLeft, .resizeDownRight, .resizeUpLeftDownRight:
                cursor = Self.undocumentedCursor("_windowResizeNorthWestSouthEastCursor") ?? .crosshair
            case .resizeUpRight, .resizeDownLeft, .resizeUpRightDownLeft:
                cursor = Self.undocumentedCursor("_windowResizeNorthEastSouthWestCursor") ?? .crosshair
            case .notAllowed:
                cursor = .operationNotAllowed
            case .copy:
                cursor = .dragCopy
            case .none:
                cursor = .arrow
            }
            cursor.set()
        }
    }

    private static func undocumentedCursor(_ selectorName: String) -> NSCursor? {
        let sel = NSSelectorFromString(selectorName)
        guard NSCursor.responds(to: sel),
              let unmanaged = NSCursor.perform(sel)
        else {
            return nil
        }
        return unmanaged.takeUnretainedValue() as? NSCursor
    }

    // MARK: - Platform Event Observers

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.keyboardLayoutCallbacks.append(callback)
        state.lock.unlock()
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.thermalStateCallbacks.append(callback)
        state.lock.unlock()
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.reopenCallbacks.append(callback)
        state.lock.unlock()
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        state.lock.lock()
        state.openUrlsCallbacks.append(callback)
        state.lock.unlock()
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.quitCallbacks.append(callback)
        state.lock.unlock()
    }

    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        state.lock.lock()
        state.willOpenMenuCallback = callback
        state.lock.unlock()
    }

    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        state.lock.lock()
        state.validateMenuCommandCallback = callback
        state.lock.unlock()
    }

    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        state.lock.lock()
        state.menuCommandCallback = callback
        state.lock.unlock()
    }
}
#endif
