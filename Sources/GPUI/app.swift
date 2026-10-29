// Ported from: crates/gpui/src/app.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Refineable
import Scheduler

/// The duration for which futures returned from Context::on_app_quit can run before the application fully quits.
public let shutdownTimeout: Duration = .milliseconds(100)

/// Defines when the application should automatically quit.
public enum QuitMode: Sendable, Equatable, DefaultInitializable {
    /// Use .explicit on macOS and .lastWindowClosed on other platforms.
    case `default`
    /// Quit automatically when the last window is closed.
    case lastWindowClosed
    /// Quit only when requested via App::quit.
    case explicit

    public init() {
        self = .default
    }
}

/// Execution mode for GPUI applications.
public enum GpuiMode: Sendable, Equatable {
    case test(skipDrawing: Bool)
    case production

    public static func test() -> GpuiMode {
        .test(skipDrawing: false)
    }

    public var skipDrawing: Bool {
        switch self {
        case .test(let skip): return skip
        case .production: return false
        }
    }
}

// WindowId is declared in window.swift

/// A tab associated with a window in the system tab bar.
public struct SystemWindowTab: Sendable, Equatable {
    public var id: WindowId
    public var title: SharedString
    public var handle: AnyWindowHandle
    public var lastActiveAt: Date

    public init(title: SharedString, handle: AnyWindowHandle) {
        self.id = handle.windowId()
        self.title = title
        self.handle = handle
        self.lastActiveAt = Date()
    }

    public static func new(title: SharedString, handle: AnyWindowHandle) -> SystemWindowTab {
        SystemWindowTab(title: title, handle: handle)
    }
}

/// A controller for managing window tabs.
public struct SystemWindowTabController: Global, Default, Sendable, Equatable {
    public var visible: Bool?
    public var _tabGroups: [Int: [SystemWindowTab]] = [:]

    public init(visible: Bool? = nil, tabGroups: [Int: [SystemWindowTab]] = [:]) {
        self.visible = visible
        self._tabGroups = tabGroups
    }

    public static func `default`() -> SystemWindowTabController {
        SystemWindowTabController()
    }

    public static func new() -> SystemWindowTabController {
        SystemWindowTabController()
    }

    @MainActor
    public static func `init`(_ cx: App) {
        cx.setGlobal(SystemWindowTabController.new())
    }

    public func tabGroups() -> [Int: [SystemWindowTab]] {
        _tabGroups
    }

    @MainActor
    public static func getNextTabGroupWindow(_ cx: App, _ id: WindowId) -> AnyWindowHandle? {
        guard let controller = cx.tryGlobal(SystemWindowTabController.self) else { return nil }
        guard let currentGroup = controller._tabGroups.first(where: { $0.value.contains(where: { $0.id == id }) })?.key else { return nil }
        let groupIds = Array(controller._tabGroups.keys).sorted()
        guard let idx = groupIds.firstIndex(of: currentGroup), !groupIds.isEmpty else { return nil }
        let nextIdx = (idx + 1) % groupIds.count
        guard let tabs = controller._tabGroups[groupIds[nextIdx]] else { return nil }
        return tabs.max(by: { $0.lastActiveAt < $1.lastActiveAt })?.handle ?? tabs.first?.handle
    }

    @MainActor
    public static func getPrevTabGroupWindow(_ cx: App, _ id: WindowId) -> AnyWindowHandle? {
        guard let controller = cx.tryGlobal(SystemWindowTabController.self) else { return nil }
        guard let currentGroup = controller._tabGroups.first(where: { $0.value.contains(where: { $0.id == id }) })?.key else { return nil }
        let groupIds = Array(controller._tabGroups.keys).sorted()
        guard let idx = groupIds.firstIndex(of: currentGroup), !groupIds.isEmpty else { return nil }
        let prevIdx = idx == 0 ? groupIds.count - 1 : idx - 1
        guard let tabs = controller._tabGroups[groupIds[prevIdx]] else { return nil }
        return tabs.max(by: { $0.lastActiveAt < $1.lastActiveAt })?.handle ?? tabs.first?.handle
    }

    public func tabs(_ id: WindowId) -> [SystemWindowTab]? {
        _tabGroups.values.first(where: { tabs in tabs.contains(where: { $0.id == id }) })
    }

    @MainActor
    public static func initVisible(_ cx: App, _ visible: Bool) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            if controller.visible == nil {
                controller.visible = visible
            }
        }
    }

    public func isVisible() -> Bool {
        visible ?? false
    }

    @MainActor
    public static func setVisible(_ cx: App, _ visible: Bool) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            controller.visible = visible
        }
    }

    @MainActor
    public static func updateLastActive(_ cx: App, _ id: WindowId) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            for key in controller._tabGroups.keys {
                if let idx = controller._tabGroups[key]?.firstIndex(where: { $0.id == id }) {
                    controller._tabGroups[key]?[idx].lastActiveAt = Date()
                }
            }
        }
    }

    @MainActor
    public static func updateTabPosition(_ cx: App, _ id: WindowId, _ ix: Int) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            for key in controller._tabGroups.keys {
                guard var windows = controller._tabGroups[key] else { continue }
                if let currentPos = windows.firstIndex(where: { $0.id == id }) {
                    if ix < windows.count && currentPos != ix {
                        let windowTab = windows.remove(at: currentPos)
                        windows.insert(windowTab, at: ix)
                        controller._tabGroups[key] = windows
                    }
                    break
                }
            }
        }
    }

    @MainActor
    public static func updateTabTitle(_ cx: App, _ id: WindowId, _ title: SharedString) {
        guard let controller = cx.tryGlobal(SystemWindowTabController.self) else { return }
        let currentTab = controller._tabGroups.values.flatMap { $0 }.first(where: { $0.id == id })
        if let currentTab, currentTab.title == title {
            return
        }
        cx.updateDefaultGlobal { (ctrl: inout SystemWindowTabController, _) in
            for key in ctrl._tabGroups.keys {
                if let idx = ctrl._tabGroups[key]?.firstIndex(where: { $0.id == id }) {
                    ctrl._tabGroups[key]?[idx].title = title
                    return
                }
            }
        }
    }

    @MainActor
    public static func addTab(_ cx: App, _ id: WindowId, _ tabs: [SystemWindowTab]) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            guard let tab = tabs.first(where: { $0.id == id }) else { return }
            let expectedTabIds = tabs.filter { $0.id != id }.map(\.id).sorted(by: { $0.rawValue < $1.rawValue })
            var tabGroupId: Int?
            for (groupId, groupTabs) in controller._tabGroups {
                let tabIds = groupTabs.map(\.id).sorted(by: { $0.rawValue < $1.rawValue })
                if tabIds == expectedTabIds {
                    tabGroupId = groupId
                    break
                }
            }
            if let tabGroupId {
                controller._tabGroups[tabGroupId]?.append(tab)
            } else {
                let newGroupId = controller._tabGroups.count
                controller._tabGroups[newGroupId] = tabs
            }
        }
    }

    @discardableResult
    @MainActor
    public static func removeTab(_ cx: App, _ id: WindowId) -> SystemWindowTab? {
        var removedTab: SystemWindowTab?
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            for key in Array(controller._tabGroups.keys) {
                if let pos = controller._tabGroups[key]?.firstIndex(where: { $0.id == id }) {
                    removedTab = controller._tabGroups[key]?.remove(at: pos)
                }
                if controller._tabGroups[key]?.isEmpty == true {
                    controller._tabGroups.removeValue(forKey: key)
                }
            }
        }
        return removedTab
    }

    @MainActor
    public static func moveTabToNewWindow(_ cx: App, _ id: WindowId) {
        let removedTab = removeTab(cx, id)
        if let tab = removedTab {
            cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
                let newGroupId = (controller._tabGroups.keys.max() ?? -1) + 1
                controller._tabGroups[newGroupId] = [tab]
            }
        }
    }

    @MainActor
    public static func mergeAllWindows(_ cx: App, _ id: WindowId) {
        cx.updateDefaultGlobal { (controller: inout SystemWindowTabController, _) in
            guard let initialTabs = controller.tabs(id) else { return }
            let initialCount = initialTabs.count
            var allTabs = initialTabs
            for key in Array(controller._tabGroups.keys) {
                guard var tabs = controller._tabGroups.removeValue(forKey: key) else { continue }
                tabs.removeAll(where: { tab in allTabs[..<initialCount].contains(where: { $0.id == tab.id }) })
                allTabs.append(contentsOf: tabs)
            }
            controller._tabGroups[0] = allTabs
        }
    }

    @MainActor
    public static func selectNextTab(_ cx: App, _ id: WindowId) {
        guard let controller = cx.tryGlobal(SystemWindowTabController.self),
              let tabs = controller.tabs(id),
              let currentIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        _ = try? cx.updateWindow(tabs[nextIndex].handle) { _, window, _ in
            window.activateWindow()
        }
    }

    @MainActor
    public static func selectPreviousTab(_ cx: App, _ id: WindowId) {
        guard let controller = cx.tryGlobal(SystemWindowTabController.self),
              let tabs = controller.tabs(id),
              let currentIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let previousIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
        _ = try? cx.updateWindow(tabs[previousIndex].handle) { _, window, _ in
            window.activateWindow()
        }
    }
}

// KeystrokeEvent is declared in window.swift

/// A callback invoked when a keystroke is received.
public typealias KeystrokeObserver = @MainActor (KeystrokeEvent, inout Window, App) -> Bool

// AnyDrag and AnyTooltip are declared in window.swift

/// Wraps a global variable value during updateGlobal while the value has been moved to the stack.
public struct GlobalLease<G: Global> {
    public var global: G

    public init(global: G) {
        self.global = global
    }
}

/// Text rendering mode options.
public enum TextRenderingMode: Sendable, Equatable, DefaultInitializable {
    case subpixel
    case grayscale

    public init() {
        self = .subpixel
    }
}

/// Thermal state of the underlying system.
public enum ThermalState: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical
}

/// Window button layout on supported platforms.
public struct WindowButtonLayout: Sendable, Equatable {
    public var left: Bool
    public init(left: Bool = true) { self.left = left }
}

/// An item on the system clipboard.
public struct ClipboardItem: Sendable, Equatable {
    public var text: String?
    public var data: Data?

    public init(text: String? = nil, data: Data? = nil) {
        self.text = text
        self.data = data
    }
}

/// Options for path prompt dialogs.
public struct PathPromptOptions: Sendable {
    public var files: Bool
    public var directories: Bool
    public var multiple: Bool

    public init(files: Bool = true, directories: Bool = false, multiple: Bool = false) {
        self.files = files
        self.directories = directories
        self.multiple = multiple
    }
}

/// A source of screen capture.
public protocol ScreenCaptureSource: Sendable {
    var id: String { get }
    var title: String { get }
}

/// Menu representation for system menu bar.
public struct Menu: Sendable {
    public var name: SharedString
    public var items: [MenuItem]

    public init(name: SharedString = "", items: [MenuItem] = []) {
        self.name = name
        self.items = items
    }
}

/// A single item in an application or dock menu.
public enum MenuItem: Sendable {
    case separator
    case action(name: SharedString, action: any Action)
    case submenu(Menu)
}

/// An owned menu structure returned from the platform.
public struct OwnedMenu: Sendable {
    public var name: SharedString
    public var items: [MenuItem]

    public init(name: SharedString = "", items: [MenuItem] = []) {
        self.name = name
        self.items = items
    }
}

/// Default empty asset source.
public struct EmptyAssetSource: AssetSource {
    public init() {}
    public func load(_ path: String) throws -> Data? {
        nil
    }
    public func list(_ path: String) throws -> [SharedString] {
        []
    }
}

/// HTTP client abstraction.
public protocol HttpClient: Sendable {
    func send(request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default null HTTP client that rejects requests.
public struct NullHttpClient: HttpClient {
    public init() {}
    public func send(request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.cancelled)
    }
}

/// SVG rendering engine for GPUI.
public final class SvgRenderer: Sendable {
    public let assetSource: any AssetSource

    public init(assetSource: any AssetSource = EmptyAssetSource()) {
        self.assetSource = assetSource
    }
}

// DisplayId and PlatformDisplay are declared in window.swift

/// Dummy platform keyboard layout.
public struct DummyKeyboardLayout: PlatformKeyboardLayout, Sendable {
    public var id: String { "dummy" }
    public var name: String { "Dummy Layout" }
    public init() {}
}

/// Platform abstraction protocol implemented by platform backends.
public protocol Platform: AnyObject, Sendable {
    func textSystem() -> any PlatformTextSystem
    func backgroundExecutor() -> BackgroundExecutor?
    func foregroundExecutor() -> ForegroundExecutor?
    func run(_ onFinishLaunching: @escaping () -> Void)
    func quit()
    func restart(path: URL?)
    func activate(ignoringOtherApps: Bool)
    func hide()
    func hideOtherApps()
    func unhideOtherApps()
    func displays() -> [any PlatformDisplay]
    func primaryDisplay() -> (any PlatformDisplay)?
    func activeWindow() -> AnyWindowHandle?
    func windowStack() -> [AnyWindowHandle]?
    func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow
    func windowAppearance() -> WindowAppearance
    func buttonLayout() -> WindowButtonLayout?
    func thermalState() -> ThermalState
    func keyboardLayout() -> any PlatformKeyboardLayout
    func keyboardMapper() -> any PlatformKeyboardMapper
    func readFromClipboard() -> ClipboardItem?
    func writeToClipboard(_ item: ClipboardItem)
    func readFromPrimary() -> ClipboardItem?
    func writeToPrimary(_ item: ClipboardItem)
    func readFromFindPasteboard() -> ClipboardItem?
    func writeToFindPasteboard(_ item: ClipboardItem)
    func writeCredentials(url: String, username: String, password: Data) async throws
    func readCredentials(url: String) async throws -> (String, Data)?
    func deleteCredentials(url: String) async throws
    func openUrl(_ url: String)
    func registerUrlScheme(_ scheme: String) async throws
    func appPath() throws -> URL
    func compositorName() -> String
    func pathForAuxiliaryExecutable(_ name: String) throws -> URL
    func promptForPaths(options: PathPromptOptions) async throws -> [URL]?
    func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL?
    func revealPath(_ path: URL)
    func openWithSystem(_ path: URL)
    func shouldAutoHideScrollbars() -> Bool
    func isScreenCaptureSupported() -> Bool
    func screenCaptureSources() async throws -> [any ScreenCaptureSource]
    func setMenus(_ menus: [Menu], keymap: Keymap)
    func getMenus() -> [OwnedMenu]?
    func setDockMenu(_ menus: [MenuItem], keymap: Keymap)
    func performDockMenuAction(_ action: Int)
    func addRecentDocument(_ path: URL)
    func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]]
    func canSelectMixedFilesAndDirs() -> Bool
    func onKeyboardLayoutChange(_ callback: @escaping () -> Void)
    func onThermalStateChange(_ callback: @escaping () -> Void)
    func onReopen(_ callback: @escaping () -> Void)
    func onOpenUrls(_ callback: @escaping ([String]) -> Void)
    func onQuit(_ callback: @escaping () -> Void)
}

/// In-memory platform display implementation for headless/testing execution.
public final class DefaultPlatformDisplay: PlatformDisplay, Sendable {
    public init() {}
    public func id() -> DisplayId { DisplayId(1) }
    public func visibleBounds() -> Bounds<Pixels> {
        Bounds(origin: .zero, size: size(px(1920), px(1080)))
    }
}

/// Default in-memory platform implementation for headless/testing execution.
// PORT NOTE: DefaultPlatform stores mutable callbacks and clipboard state for headless/testing execution; in upstream GPUI, platform instances are thread-safe handles accessed from the main thread loop.
public final class DefaultPlatform: Platform, @unchecked Sendable {
    private var isQuit: Bool = false
    private var clipboardItem: ClipboardItem?
    private var findPasteboardItem: ClipboardItem?
    private var primaryItem: ClipboardItem?
    private var credentialsStore: [String: (String, Data)] = [:]
    private var onKeyboardLayoutChangeCallbacks: [() -> Void] = []
    private var onThermalStateChangeCallbacks: [() -> Void] = []
    private var onReopenCallbacks: [() -> Void] = []
    private var onOpenUrlsCallbacks: [([String]) -> Void] = []
    private var onQuitCallbacks: [() -> Void] = []
    public var _displays: [any PlatformDisplay] = [DefaultPlatformDisplay()]

    public init() {}

    public func textSystem() -> any PlatformTextSystem { NoopTextSystem() }
    public func backgroundExecutor() -> BackgroundExecutor? { nil }
    public func foregroundExecutor() -> ForegroundExecutor? { nil }
    public func run(_ onFinishLaunching: @escaping () -> Void) { onFinishLaunching() }
    public func quit() {
        isQuit = true
        for cb in onQuitCallbacks { cb() }
    }
    public func restart(path: URL?) {}
    public func activate(ignoringOtherApps: Bool) {}
    public func hide() {}
    public func hideOtherApps() {}
    public func unhideOtherApps() {}
    public func displays() -> [any PlatformDisplay] { _displays }
    public func primaryDisplay() -> (any PlatformDisplay)? { _displays.first }
    public func activeWindow() -> AnyWindowHandle? { nil }
    public func windowStack() -> [AnyWindowHandle]? { nil }
    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        DefaultPlatformWindow()
    }
    public func windowAppearance() -> WindowAppearance { .dark }
    public func buttonLayout() -> WindowButtonLayout? { nil }
    public func thermalState() -> ThermalState { .nominal }
    public func keyboardLayout() -> any PlatformKeyboardLayout { DummyKeyboardLayout() }
    public func keyboardMapper() -> any PlatformKeyboardMapper { DummyKeyboardMapper() }
    public func readFromClipboard() -> ClipboardItem? { clipboardItem }
    public func writeToClipboard(_ item: ClipboardItem) { clipboardItem = item }
    public func readFromPrimary() -> ClipboardItem? { primaryItem }
    public func writeToPrimary(_ item: ClipboardItem) { primaryItem = item }
    public func readFromFindPasteboard() -> ClipboardItem? { findPasteboardItem }
    public func writeToFindPasteboard(_ item: ClipboardItem) { findPasteboardItem = item }
    public func writeCredentials(url: String, username: String, password: Data) async throws {
        credentialsStore[url] = (username, password)
    }
    public func readCredentials(url: String) async throws -> (String, Data)? {
        credentialsStore[url]
    }
    public func deleteCredentials(url: String) async throws {
        credentialsStore.removeValue(forKey: url)
    }
    public func openUrl(_ url: String) {}
    public func registerUrlScheme(_ scheme: String) async throws {}
    public func appPath() throws -> URL { URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? "") }
    public func compositorName() -> String { "" }
    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent().appendingPathComponent(name)
    }
    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? { nil }
    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? { nil }
    public func revealPath(_ path: URL) {}
    public func openWithSystem(_ path: URL) {}
    public func shouldAutoHideScrollbars() -> Bool { false }
    public func isScreenCaptureSupported() -> Bool { false }
    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] { [] }
    public func setMenus(_ menus: [Menu], keymap: Keymap) {}
    public func getMenus() -> [OwnedMenu]? { nil }
    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {}
    public func performDockMenuAction(_ action: Int) {}
    public func addRecentDocument(_ path: URL) {}
    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] { entries }
    public func canSelectMixedFilesAndDirs() -> Bool { false }
    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        onKeyboardLayoutChangeCallbacks.append(callback)
    }
    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        onThermalStateChangeCallbacks.append(callback)
    }
    public func onReopen(_ callback: @escaping () -> Void) {
        onReopenCallbacks.append(callback)
    }
    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        onOpenUrlsCallbacks.append(callback)
    }
    public func onQuit(_ callback: @escaping () -> Void) {
        onQuitCallbacks.append(callback)
    }
}

/// A reference to a GPUI application configuration before and during launch.
@MainActor
public final class Application: Sendable {
    public let app: App

    public init(app: App = App()) {
        self.app = app
    }

    public static func withPlatform(_ platform: any Platform) -> Application {
        let app = App.newApp(platform: platform)
        return Application(app: app)
    }

    public func withAssets(_ assetSource: any AssetSource) -> Self {
        app.setAssetSource(assetSource)
        return self
    }

    public func withHttpClient(_ httpClient: any HttpClient) -> Self {
        app.setHttpClient(httpClient)
        return self
    }

    public func withQuitMode(_ mode: QuitMode) -> Self {
        app.setQuitMode(mode)
        return self
    }

    public func run(_ onFinishLaunching: @escaping (App) -> Void) {
        app.platform.run { [weak app] in
            guard let app else { return }
            onFinishLaunching(app)
        }
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) -> Self {
        app.platform.onOpenUrls(callback)
        return self
    }

    public func onReopen(_ callback: @escaping (App) -> Void) -> Self {
        app.platform.onReopen { [weak app] in
            guard let app else { return }
            callback(app)
        }
        return self
    }

    public func backgroundExecutor() -> BackgroundExecutor {
        app.backgroundExecutor()
    }

    public func foregroundExecutor() -> ForegroundExecutor {
        app.foregroundExecutor()
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        try app.pathForAuxiliaryExecutable(name)
    }

    public func textSystem() -> TextSystem {
        app.textSystem()
    }
}

/// A mutable reference to an entity owned by GPUI with RAII auto-notification on drop.
// PORT NOTE: GpuiBorrow models Rust RefCell borrow semantics; thread-safety is guaranteed by MainActor isolation of the GPUI application loop where entity leasing occurs.
public final class GpuiBorrow<T>: @unchecked Sendable {
    public var value: T {
        get { lease.value }
        set { lease.value = newValue }
    }
    private var lease: Lease<T>
    private unowned let app: App

    @MainActor
    public init(inner: Entity<T>, app: App) {
        self.app = app
        app.startUpdate()
        self.lease = app.entities.lease(inner)
    }

    deinit {
        let app = self.app
        var lease = self.lease
        MainActor.assumeIsolated {
            app.notify(lease.id)
            app.entities.endLease(&lease)
            app.finishUpdate()
        }
    }
}

/// The core application state container in GPUI.
// PORT NOTE: App is isolated to MainActor (ADR-0003), but conforms to Sendable for inter-thread task dispatching and async handles matching upstream App cell semantics.
@MainActor
public final class App: AppContext, BorrowAppContext, @unchecked Sendable {
    public var entities: EntityMap
    public let observers = SubscriberSet<EntityId, (App) -> Bool>()
    public let eventListeners = SubscriberSet<EntityId, (ObjectIdentifier, (Any, App) -> Bool)>()
    public let releaseListeners = SubscriberSet<EntityId, (inout Any, App) -> Void>()
    public let globalObservers = SubscriberSet<ObjectIdentifier, (App) -> Bool>()
    public let newEntityObservers = SubscriberSet<ObjectIdentifier, (AnyEntity, inout Window?, App) -> Void>()
    public let keystrokeObservers = SubscriberSet<ObjectIdentifier, (KeystrokeEvent, inout Window, App) -> Bool>()
    public let keystrokeInterceptors = SubscriberSet<ObjectIdentifier, (KeystrokeEvent, inout Window, App) -> Bool>()
    public let keyboardLayoutObservers = SubscriberSet<ObjectIdentifier, (App) -> Bool>()
    public let thermalStateObservers = SubscriberSet<ObjectIdentifier, (App) -> Bool>()
    public let quitObservers = SubscriberSet<ObjectIdentifier, (App) async -> Void>()
    public let restartObservers = SubscriberSet<ObjectIdentifier, (App) -> Bool>()
    public let windowClosedObservers = SubscriberSet<ObjectIdentifier, (App, WindowId) -> Void>()

    public var platform: any Platform
    public var _textRenderingMode: TextRenderingMode = .subpixel
    public var quitMode: QuitMode = .default
    public var mode: GpuiMode = .production
    public var actions: ActionRegistry = ActionRegistry.default
    public var activeDrag: AnyDrag?
    public var _backgroundExecutor: BackgroundExecutor
    public var _foregroundExecutor: ForegroundExecutor
    public var _assetSource: any AssetSource = EmptyAssetSource()
    public var _svgRenderer: SvgRenderer
    public var _httpClient: any HttpClient = NullHttpClient()
    public var _textSystem: TextSystem
    public var promptBuilder: Any? = nil

    private var globals: [ObjectIdentifier: Any] = [:]
    private var windowsById: [WindowId: Window] = [:]
    private var windowHandles: [WindowId: AnyWindowHandle] = [:]
    private var windowUpdateStack: [WindowId] = []
    private var nextWindowId: WindowId = WindowId(1)
    public var focusHandles: FocusMap = FocusMap()
    public var keymap: Keymap = Keymap()
    public var _keyboardLayout: any PlatformKeyboardLayout = DummyKeyboardLayout()
    public var _keyboardMapper: any PlatformKeyboardMapper = DummyKeyboardMapper()
    public var globalActionListeners: [ObjectIdentifier: [(Any, DispatchPhase, App) -> Void]] = [:]

    private var loadingAssets: [AssetId: Any] = [:]
    private var inspectorRenderer: Any? = nil
    private var inspectorElementRegistry: [ObjectIdentifier: Any] = [:]

    private var trackedEntities: [WindowId: Set<EntityId>] = [:]
    private var windowInvalidatorsByEntity: [EntityId: [WindowId: WindowInvalidator]] = [:]
    private var restartPath: URL?
    private var name: String? = nil

    public var propagateEvent: Bool = true
    private var quitting: Bool = false

    public enum Effect {
        case notify(EntityId)
        case emit(emitter: EntityId, eventType: ObjectIdentifier, event: Any)
        case refreshWindows
        case notifyGlobalObservers(ObjectIdentifier)
        case deferCallback((App) -> Void)
        case entityCreated(entity: AnyEntity, tid: ObjectIdentifier, window: WindowId?)
    }

    private var pendingEffects: [Effect] = []
    private var pendingNotifications: Set<EntityId> = []
    private var pendingGlobalNotifications: Set<ObjectIdentifier> = []
    private var pendingUpdates: Int = 0
    private var flushingEffects: Bool = false

    nonisolated public init(
        platform: any Platform = DefaultPlatform(),
        assetSource: any AssetSource = EmptyAssetSource(),
        httpClient: any HttpClient = NullHttpClient(),
        backgroundExecutor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil
    ) {
        self.entities = EntityMap()
        self.platform = platform
        self._assetSource = assetSource
        self._httpClient = httpClient
        self._backgroundExecutor = backgroundExecutor ?? platform.backgroundExecutor() ?? BackgroundExecutor(scheduler: TestScheduler())
        self._foregroundExecutor = foregroundExecutor ?? platform.foregroundExecutor() ?? ForegroundExecutor(sessionId: SessionId(0), scheduler: TestScheduler())
        self._svgRenderer = SvgRenderer(assetSource: assetSource)
        self._textSystem = TextSystem(platformTextSystem: platform.textSystem())
    }

    public func textSystem() -> TextSystem {
        _textSystem
    }

    public static func newApp(
        platform: any Platform = DefaultPlatform(),
        assetSource: any AssetSource = EmptyAssetSource(),
        httpClient: any HttpClient = NullHttpClient()
    ) -> App {
        App(
            platform: platform,
            assetSource: assetSource,
            httpClient: httpClient,
            backgroundExecutor: platform.backgroundExecutor(),
            foregroundExecutor: platform.foregroundExecutor()
        )
    }

    public func startUpdate() {
        pendingUpdates += 1
    }

    public func finishUpdate() {
        if !flushingEffects && pendingUpdates == 1 {
            flushingEffects = true
            flushEffects()
            flushingEffects = false
        }
        pendingUpdates -= 1
    }

    /// Invokes the given function in the context of the app, flushing side effects upon completion.
    @discardableResult
    public func update<R>(_ f: (App) -> R) -> R {
        startUpdate()
        defer { finishUpdate() }
        return f(self)
    }

    public func pushEffect(_ effect: Effect) {
        switch effect {
        case .notify(let emitter):
            if !pendingNotifications.insert(emitter).inserted {
                return
            }
        case .notifyGlobalObservers(let typeId):
            if !pendingGlobalNotifications.insert(typeId).inserted {
                return
            }
        default:
            break
        }
        pendingEffects.append(effect)
    }

    public func flushEffects() {
        while true {
            releaseDroppedEntities()
            if !pendingEffects.isEmpty {
                let effect = pendingEffects.removeFirst()
                switch effect {
                case .notify(let emitter):
                    applyNotifyEffect(emitter)
                case .emit(let emitter, let eventType, let event):
                    applyEmitEffect(emitter, eventType, event)
                case .refreshWindows:
                    applyRefreshEffect()
                case .notifyGlobalObservers(let typeId):
                    applyNotifyGlobalObserversEffect(typeId)
                case .deferCallback(let callback):
                    callback(self)
                case .entityCreated(let entity, let tid, let windowId):
                    applyEntityCreatedEffect(entity: entity, tid: tid, windowId: windowId)
                }
            } else {
                releaseDroppedEntities()
                if pendingEffects.isEmpty {
                    break
                }
            }
        }
    }

    public func releaseDroppedEntities() {
        while true {
            let dropped = entities.takeDropped()
            if dropped.isEmpty { break }
            for (entityId, var entity) in dropped {
                _ = observers.remove(entityId)
                _ = eventListeners.remove(entityId)
                let releases = releaseListeners.remove(entityId)
                for releaseCallback in releases {
                    releaseCallback(&entity, self)
                }
            }
        }
    }

    private func applyNotifyEffect(_ emitter: EntityId) {
        pendingNotifications.remove(emitter)
        observers.retain(emitter) { handler in
            handler(self)
        }
    }

    private func applyEmitEffect(_ emitter: EntityId, _ eventType: ObjectIdentifier, _ event: Any) {
        eventListeners.retain(emitter) { entry in
            let (storedType, handler) = entry
            if storedType == eventType {
                return handler(event, self)
            }
            return true
        }
    }

    private func applyRefreshEffect() {
        for id in windowsById.keys {
            windowsById[id]?.invalidator.setDirty(true)
        }
    }

    private func applyNotifyGlobalObserversEffect(_ typeId: ObjectIdentifier) {
        pendingGlobalNotifications.remove(typeId)
        globalObservers.retain(typeId) { handler in
            handler(self)
        }
    }

    private func applyEntityCreatedEffect(entity: AnyEntity, tid: ObjectIdentifier, windowId: WindowId?) {
        newEntityObservers.retain(tid) { observer in
            if let windowId {
                if let win = windowsById[windowId] {
                    var optWin: Window? = win
                    observer(entity, &optWin, self)
                    if let updatedWin = optWin {
                        windowsById[windowId] = updatedWin
                    }
                }
            } else {
                var optWin: Window? = nil
                observer(entity, &optWin, self)
            }
            return true
        }
    }

    public func notify(_ entityId: EntityId) {
        if let invalidators = windowInvalidatorsByEntity[entityId], !invalidators.isEmpty {
            for invalidator in invalidators.values {
                var appRef = self
                _ = invalidator.invalidateView(entityId, &appRef)
            }
        } else {
            pushEffect(.notify(entityId))
        }
    }

    public func emit(emitter: EntityId, eventType: ObjectIdentifier, event: Any) {
        pushEffect(.emit(emitter: emitter, eventType: eventType, event: event))
    }

    public func `defer`(_ callback: @escaping (App) -> Void) {
        pushEffect(.deferCallback(callback))
    }

    // AppContext implementation
    public func new<T>(_ buildEntity: (inout Context<T>) -> T) -> Entity<T> {
        let reservation: Reservation<T> = reserveEntity(T.self)
        return insertEntity(reservation, buildEntity)
    }

    public func reserveEntity<T>(_ type: T.Type = T.self) -> Reservation<T> {
        Reservation(slot: entities.reserve())
    }

    public func insertEntity<T>(
        _ reservation: Reservation<T>,
        _ buildEntity: (inout Context<T>) -> T
    ) -> Entity<T> {
        var cx = Context<T>(app: self, entityState: reservation.slot.entity.downgrade())
        let value = buildEntity(&cx)
        let entity = entities.insert(reservation.slot, value)
        pushEffect(.entityCreated(
            entity: entity.intoAny(),
            tid: ObjectIdentifier(T.self),
            window: windowUpdateStack.last
        ))
        return entity
    }

    public func updateEntity<T, R>(
        _ handle: Entity<T>,
        _ update: (inout T, inout Context<T>) -> R
    ) -> R {
        startUpdate()
        defer { finishUpdate() }
        var lease = entities.lease(handle)
        var cx = Context<T>(app: self, entityState: handle.downgrade())
        let result = update(&lease.value, &cx)
        entities.endLease(&lease)
        return result
    }

    public func asMut<T>(_ handle: Entity<T>) -> GpuiBorrow<T> {
        GpuiBorrow(inner: handle, app: self)
    }

    public func readEntity<T, R>(
        _ handle: Entity<T>,
        _ read: (T, App) -> R
    ) -> R {
        let val = entities.read(handle)
        return read(val, self)
    }

    // Observers and Subscriptions
    public func observe<W>(
        _ entity: Entity<W>,
        _ handler: @escaping (Entity<W>, App) -> Bool
    ) -> Subscription {
        observeInternal(entity, handler)
    }

    public func newObserver(_ key: EntityId, _ value: @escaping (App) -> Bool) -> Subscription {
        let (subscription, activate) = observers.insert(key, value)
        self.defer { _ in activate() }
        return subscription
    }

    public func observeInternal<W>(
        _ entity: Entity<W>,
        _ onNotify: @escaping (Entity<W>, App) -> Bool
    ) -> Subscription {
        let handle = entity.downgrade()
        return newObserver(entity.entityId) { [weak self] app in
            guard let self, let entity = handle.upgrade() else { return false }
            return onNotify(entity, self)
        }
    }

    public func subscribe<T2, Evt>(
        _ entity: Entity<T2>,
        _ handler: @escaping (Entity<T2>, Evt, App) -> Bool
    ) -> Subscription {
        subscribeInternal(entity, handler)
    }

    public func newSubscription(_ key: EntityId, _ value: (ObjectIdentifier, (Any, App) -> Bool)) -> Subscription {
        let (subscription, activate) = eventListeners.insert(key, value)
        self.defer { _ in activate() }
        return subscription
    }

    public func subscribeInternal<T, Evt>(
        _ entity: Entity<T>,
        _ onEvent: @escaping (Entity<T>, Evt, App) -> Bool
    ) -> Subscription {
        let handle = entity.downgrade()
        return newSubscription(entity.entityId, (
            ObjectIdentifier(Evt.self),
            { [weak self] (eventAny: Any, app: App) -> Bool in
                guard let self, let event = eventAny as? Evt, let entity = handle.upgrade() else { return false }
                return onEvent(entity, event, self)
            }
        ))
    }

    public func newEntityObserver(
        _ key: ObjectIdentifier,
        _ value: @escaping (AnyEntity, inout Window?, App) -> Void
    ) -> Subscription {
        let (subscription, activate) = newEntityObservers.insert(key, value)
        activate()
        return subscription
    }

    public func observeNew<T>(
        _ onNew: @escaping (inout T, inout Window?, inout Context<T>) -> Void
    ) -> Subscription {
        newEntityObserver(ObjectIdentifier(T.self)) { [weak self] anyEntity, optWindow, app in
            guard let self, case .success(let entity) = anyEntity.downcast() as Result<Entity<T>, AnyEntity> else { return }
            entity.update(self) { state, cx in
                onNew(&state, &optWindow, &cx)
            }
        }
    }

    public func observeRelease<T>(
        _ handle: Entity<T>,
        _ onRelease: @escaping (inout T, App) -> Void
    ) -> Subscription {
        let (subscription, activate) = releaseListeners.insert(handle.entityId) { (boxed: inout Any, app: App) in
            if var typed = boxed as? T {
                onRelease(&typed, app)
                boxed = typed
            }
        }
        activate()
        return subscription
    }

    public func observeReleaseIn<T>(
        _ handle: Entity<T>,
        _ window: Window,
        _ onRelease: @escaping (inout T, inout Window, App) -> Void
    ) -> Subscription {
        let windowHandle = window.handle
        return observeRelease(handle) { [weak self] typed, app in
            guard let self else { return }
            _ = try? updateWindow(windowHandle) { _, win, cx in
                onRelease(&typed, &win, cx)
            }
        }
    }

    // Globals
    public func setGlobal<G: Global>(_ global: G) {
        startUpdate()
        defer { finishUpdate() }
        let typeId = ObjectIdentifier(G.self)
        globals[typeId] = global
        pushEffect(.notifyGlobalObservers(typeId))
    }

    public func global<G: Global>(_ type: G.Type = G.self) -> G {
        guard let val = globals[ObjectIdentifier(G.self)] as? G else {
            fatalError("no global of type \(G.self) found")
        }
        return val
    }

    public func tryGlobal<G: Global>(_ type: G.Type = G.self) -> G? {
        globals[ObjectIdentifier(G.self)] as? G
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        globals[ObjectIdentifier(G.self)] != nil
    }

    public func globalMut<G: Global>(_ type: G.Type = G.self) -> G {
        global(type)
    }

    public func defaultGlobal<G: Global & DefaultInitializable>(_ type: G.Type = G.self) -> G {
        if !hasGlobal(type) {
            setGlobal(G())
        }
        return global(type)
    }

    public func clearGlobals() {
        globals.removeAll()
    }

    public func removeGlobal<G: Global>(_ type: G.Type = G.self) -> G {
        leaseGlobal(type)
    }

    public func leaseGlobal<G: Global>(_ type: G.Type = G.self) -> G {
        guard let val = globals.removeValue(forKey: ObjectIdentifier(G.self)) as? G else {
            fatalError("no global of type \(G.self) found")
        }
        return val
    }

    public func endGlobalLease<G: Global>(_ global: G) {
        setGlobal(global)
    }

    public func updateGlobal<G: Global, R>(_ update: (inout G, App) -> R) -> R {
        var g: G = leaseGlobal()
        let result = update(&g, self)
        endGlobalLease(g)
        return result
    }

    public func updateDefaultGlobal<G: Global & Default, R>(_ update: (inout G, App) -> R) -> R {
        if !hasGlobal(G.self) {
            globals[ObjectIdentifier(G.self)] = G.default()
        }
        return updateGlobal(update)
    }

    public func readGlobal<G: Global, R>(_ callback: (G, App) -> R) -> R {
        callback(global(), self)
    }

    public func observeGlobal<G: Global>(_ type: G.Type = G.self, _ handler: @escaping (App) -> Bool) -> Subscription {
        let (subscription, activate) = globalObservers.insert(ObjectIdentifier(G.self)) { [weak self] app in
            guard let self else { return false }
            return handler(self)
        }
        self.defer { _ in activate() }
        return subscription
    }

    // Windows
    public func windows() -> [AnyWindowHandle] {
        Array(windowHandles.values)
    }

    public func windowStack() -> [AnyWindowHandle]? {
        platform.windowStack() ?? windows()
    }

    public func activeWindow() -> AnyWindowHandle? {
        platform.activeWindow() ?? windows().first
    }

    public func openWindow<V: Render>(
        _ options: WindowOptions = WindowOptions(),
        _ buildRootView: @escaping (inout Window, App) -> Entity<V>
    ) throws -> WindowHandle<V> {
        return update { cx in
            let id = cx.nextWindowId
            cx.nextWindowId = WindowId(cx.nextWindowId.rawValue + 1)
            let anyHandle = AnyWindowHandle(id: id.rawValue)
            let handle = WindowHandle<V>(anyHandle: anyHandle)
            var window = Window(handle: anyHandle)
            cx.windowUpdateStack.append(id)
            let rootView = buildRootView(&window, cx)
            cx.windowUpdateStack.removeLast()
            window.root = AnyView(rootView)
            cx.windowHandles[id] = anyHandle
            cx.windowsById[id] = window
            return handle
        }
    }

    public func refreshWindows() {
        pushEffect(.refreshWindows)
    }

    public func updateWindow<T>(
        _ handle: AnyWindowHandle,
        _ update: (AnyView, inout Window, App) throws -> T
    ) throws -> T {
        let id = handle.windowId()
        guard var window = windowsById[id], let root = window.root else {
            throw GPUIError.windowClosed
        }
        windowUpdateStack.append(id)
        defer { windowUpdateStack.removeLast() }
        let result = try update(root, &window, self)
        windowsById[id] = window
        return result
    }

    public func readWindow<R>(
        _ handle: AnyWindowHandle,
        _ read: (AnyView, App) throws -> R
    ) throws -> R {
        guard let win = windowsById[handle.windowId()], let root = win.root else {
            throw GPUIError.windowClosed
        }
        return try read(root, self)
    }

    // Entity Access Detection
    public func detectAccessedEntities<R>(_ callback: (App) -> R) -> (R, Set<EntityId>) {
        let before = entities.accessedEntities
        let result = callback(self)
        let newlyAccessed = entities.accessedEntities.subtracting(before)
        return (result, newlyAccessed)
    }

    public func recordEntitiesAccessed(
        _ windowHandle: AnyWindowHandle,
        _ invalidator: WindowInvalidator,
        _ entities: Set<EntityId>
    ) {
        let windowId = windowHandle.windowId()
        let prevTracked = trackedEntities[windowId] ?? []
        for entity in prevTracked {
            windowInvalidatorsByEntity[entity]?.removeValue(forKey: windowId)
        }
        for entity in entities {
            if windowInvalidatorsByEntity[entity] == nil {
                windowInvalidatorsByEntity[entity] = [:]
            }
            windowInvalidatorsByEntity[entity]?[windowId] = invalidator
        }
        trackedEntities[windowId] = entities
    }

    // Keystroke Observers & Interceptors
    public func observeKeystrokes(_ f: @escaping (KeystrokeEvent, inout Window, App) -> Void) -> Subscription {
        let (subscription, activate) = keystrokeObservers.insert(ObjectIdentifier(App.self)) { event, window, app in
            f(event, &window, app)
            return true
        }
        activate()
        return subscription
    }

    public func interceptKeystrokes(_ f: @escaping (KeystrokeEvent, inout Window, App) -> Void) -> Subscription {
        let (subscription, activate) = keystrokeInterceptors.insert(ObjectIdentifier(App.self)) { event, window, app in
            f(event, &window, app)
            return true
        }
        activate()
        return subscription
    }

    public func clearPendingKeystrokes() {
        for windowId in windowsById.keys {
            windowsById[windowId]?.clearPendingKeystrokes()
        }
    }

    // Keymap & Action Bindings
    public func bindKeys(_ bindings: [KeyBinding]) {
        keymap.addBindings(bindings)
        refreshWindows()
    }

    public func clearKeyBindings() {
        keymap.clear()
        refreshWindows()
    }

    public func keyBindings() -> Keymap {
        keymap
    }

    public func onAction<A: Action>(_ listener: @escaping (A, App) -> Void) -> Self {
        let typeId = ObjectIdentifier(A.self)
        let handler: (Any, DispatchPhase, App) -> Void = { anyAction, phase, app in
            if phase == .bubble, let action = anyAction as? A {
                listener(action, app)
            }
        }
        globalActionListeners[typeId, default: []].append(handler)
        return self
    }

    public func stopPropagation() {
        propagateEvent = false
    }

    public func propagate() {
        propagateEvent = true
    }

    public func buildAction(_ name: String, _ data: Any? = nil) throws -> any Action {
        try actions.buildAction(name: name, params: data as? [String: Any])
    }

    public func allActionNames() -> [String] {
        actions.allActionNames()
    }

    public func allBindingsForInput(_ input: [Keystroke]) -> [KeyBinding] {
        keymap.allBindingsForInput(input)
    }

    public func bindingsForInputInContext(_ input: [Keystroke], _ contextStack: [KeyContext]) -> ([KeyBinding], Bool) {
        let result = keymap.bindingsForInput(input, contextStack)
        return (result.bindings, result.hasPending)
    }

    public func actionSchemas() -> [(String, String?)] {
        actions.allActionNames().map { ($0, nil) }
    }

    public func actionSchemaByName(_ name: String) -> String? {
        guard actions.allActionNames().contains(name) else {
            return nil
        }
        return "{\"type\": \"object\", \"title\": \"\(name)\"}"
    }

    public func deprecatedActionsToPreferredActions() -> [String: String] {
        actions.deprecatedAliases()
    }

    public func actionDeprecationMessages() -> [String: String] {
        actions.deprecationMessages()
    }

    public func actionDocumentation() -> [String: String] {
        actions.documentation()
    }

    public func isActionAvailable(_ action: any Action) -> Bool {
        let typeId = ObjectIdentifier(type(of: action))
        if globalActionListeners[typeId] != nil {
            return true
        }
        if let active = activeWindow(), let window = windowsById[active.windowId()] {
            return window.isActionAvailable(action, self)
        }
        return false
    }

    public func dispatchAction(_ action: any Action) {
        if let active = activeWindow() {
            _ = try? updateWindow(active) { (_: AnyView, window: inout Window, cx: App) in
                var app = cx
                window.dispatchAction(action, &app)
            }
        } else {
            dispatchGlobalAction(action)
        }
    }

    public func dispatchGlobalAction(_ action: any Action) {
        propagateEvent = true
        let typeId = ObjectIdentifier(type(of: action))
        guard let listeners = globalActionListeners[typeId] else { return }
        for listener in listeners {
            listener(action, .capture, self)
            if !propagateEvent { break }
        }
        if propagateEvent {
            for listener in listeners.reversed() {
                listener(action, .bubble, self)
                if !propagateEvent { break }
            }
        }
    }

    // App Lifecycle & Observers
    public func onAppQuit(_ onQuit: @escaping (App) async -> Void) -> Subscription {
        let (subscription, activate) = quitObservers.insert(ObjectIdentifier(App.self), onQuit)
        activate()
        return subscription
    }

    public func onAppRestart(_ onRestart: @escaping (App) -> Void) -> Subscription {
        let (subscription, activate) = restartObservers.insert(ObjectIdentifier(App.self)) { app in
            onRestart(app)
            return true
        }
        activate()
        return subscription
    }

    public func onWindowClosed(_ onClosed: @escaping (App, WindowId) -> Void) -> Subscription {
        let (subscription, activate) = windowClosedObservers.insert(ObjectIdentifier(App.self), onClosed)
        activate()
        return subscription
    }

    public func shutdown() {
        quitting = true
        windowsById.removeAll()
        windowHandles.removeAll()
        flushEffects()
        quitting = false
    }

    public func restart() {
        restartObservers.retain(ObjectIdentifier(App.self)) { observer in
            observer(self)
        }
        platform.restart(path: restartPath)
    }

    public func setRestartPath(_ path: URL) {
        restartPath = path
    }

    public func quit() {
        platform.quit()
    }

    // Platform Delegation
    public func activate(ignoringOtherApps: Bool = true) {
        platform.activate(ignoringOtherApps: ignoringOtherApps)
    }

    public func hide() {
        platform.hide()
    }

    public func hideOtherApps() {
        platform.hideOtherApps()
    }

    public func unhideOtherApps() {
        platform.unhideOtherApps()
    }

    public func displays() -> [any PlatformDisplay] {
        platform.displays()
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        platform.primaryDisplay()
    }

    public func findDisplay(_ id: DisplayId) -> (any PlatformDisplay)? {
        displays().first(where: { $0.id() == id })
    }

    public func isScreenCaptureSupported() -> Bool {
        platform.isScreenCaptureSupported()
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        try await platform.screenCaptureSources()
    }

    public func thermalState() -> ThermalState {
        platform.thermalState()
    }

    public func onThermalStateChange(_ callback: @escaping (App) -> Void) -> Subscription {
        let (subscription, activate) = thermalStateObservers.insert(ObjectIdentifier(App.self)) { app in
            callback(app)
            return true
        }
        activate()
        return subscription
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        _keyboardLayout
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        _keyboardMapper
    }

    public func onKeyboardLayoutChange(_ callback: @escaping (App) -> Void) -> Subscription {
        let (subscription, activate) = keyboardLayoutObservers.insert(ObjectIdentifier(App.self)) { app in
            callback(app)
            return true
        }
        activate()
        return subscription
    }

    public func windowAppearance() -> WindowAppearance {
        platform.windowAppearance()
    }

    public func buttonLayout() -> WindowButtonLayout? {
        platform.buttonLayout()
    }

    public func readFromClipboard() -> ClipboardItem? {
        platform.readFromClipboard()
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        platform.writeToClipboard(item)
    }

    public func readFromPrimary() -> ClipboardItem? {
        platform.readFromPrimary()
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        platform.writeToPrimary(item)
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        platform.readFromFindPasteboard()
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        platform.writeToFindPasteboard(item)
    }

    public func setTextRenderingMode(_ mode: TextRenderingMode) {
        _textRenderingMode = mode
    }

    public func textRenderingMode() -> TextRenderingMode {
        _textRenderingMode
    }

    public func writeCredentials(url: String, username: String, password: Data) async throws {
        try await platform.writeCredentials(url: url, username: username, password: password)
    }

    public func readCredentials(url: String) async throws -> (String, Data)? {
        try await platform.readCredentials(url: url)
    }

    public func deleteCredentials(url: String) async throws {
        try await platform.deleteCredentials(url: url)
    }

    public func openUrl(_ url: String) {
        platform.openUrl(url)
    }

    public func registerUrlScheme(_ scheme: String) async throws {
        try await platform.registerUrlScheme(scheme)
    }

    public func appPath() throws -> URL {
        try platform.appPath()
    }

    public func compositorName() -> String {
        platform.compositorName()
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        try platform.pathForAuxiliaryExecutable(name)
    }

    public func promptForPaths(_ options: PathPromptOptions) async throws -> [URL]? {
        try await platform.promptForPaths(options: options)
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        try await platform.promptForNewPath(directory: directory, suggestedName: suggestedName)
    }

    public func revealPath(_ path: URL) {
        platform.revealPath(path)
    }

    public func openWithSystem(_ path: URL) {
        platform.openWithSystem(path)
    }

    public func shouldAutoHideScrollbars() -> Bool {
        platform.shouldAutoHideScrollbars()
    }

    public func httpClient() -> any HttpClient {
        _httpClient
    }

    public func setHttpClient(_ client: any HttpClient) {
        _httpClient = client
    }

    public func setQuitMode(_ mode: QuitMode) {
        quitMode = mode
    }

    public func svgRenderer() -> SvgRenderer {
        _svgRenderer
    }

    public func setMenus(_ menus: [Menu]) {
        platform.setMenus(menus, keymap: keymap)
    }

    public func getMenus() -> [OwnedMenu]? {
        platform.getMenus()
    }

    public func setDockMenu(_ menus: [MenuItem]) {
        platform.setDockMenu(menus, keymap: keymap)
    }

    public func performDockMenuAction(_ action: Int) {
        platform.performDockMenuAction(action)
    }

    public func addRecentDocument(_ path: URL) {
        platform.addRecentDocument(path)
    }

    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] {
        try await platform.updateJumpList(menus: menus, entries: entries)
    }

    public func hasActiveDrag() -> Bool {
        activeDrag != nil
    }

    public func activeDragCursorStyle() -> CursorStyle? {
        activeDrag?.cursorStyle
    }

    public func stopActiveDrag(_ window: inout Window) -> Bool {
        if activeDrag != nil {
            activeDrag = nil
            window.refresh()
            return true
        }
        return false
    }

    public func setActiveDragCursorStyle(_ cursorStyle: CursorStyle, _ window: inout Window) -> Bool {
        if activeDrag != nil {
            activeDrag?.cursorStyle = cursorStyle
            window.refresh()
            return true
        }
        return false
    }

    public func setPromptBuilder(_ renderer: Any) {
        promptBuilder = renderer
    }

    public func resetPromptBuilder() {
        promptBuilder = nil
    }

    public func assetSource() -> any AssetSource {
        _assetSource
    }

    public func setAssetSource(_ source: any AssetSource) {
        _assetSource = source
        _svgRenderer = SvgRenderer(assetSource: source)
    }

    public func removeAsset<A: Asset>(_ source: A.Source, _ type: A.Type = A.self) {
        var hasher = Hasher()
        hasher.combine(source)
        let key = AssetId(typeId: ObjectIdentifier(A.self), sourceHash: hasher.finalize())
        loadingAssets.removeValue(forKey: key)
    }

    public func fetchAsset<A: Asset>(_ source: A.Source, _ type: A.Type = A.self) -> (Task<A.Output>, Bool) {
        var hasher = Hasher()
        hasher.combine(source)
        let key = AssetId(typeId: ObjectIdentifier(A.self), sourceHash: hasher.finalize())
        if let existing = loadingAssets[key] as? Task<A.Output> {
            return (existing, false)
        }
        var cx = self
        let task = A.load(source: source, cx: &cx)
        loadingAssets[key] = task
        return (task, true)
    }

    public func focusHandle() -> FocusHandle {
        FocusHandle(handles: focusHandles)
    }

    public func getName() -> String? {
        name
    }

    public func canSelectMixedFilesAndDirs() -> Bool {
        platform.canSelectMixedFilesAndDirs()
    }

    public func dropImage(_ image: RenderImage) {
        for window in windowsById.values {
            var win = window
            win.dropImage(image)
        }
    }

    public func dropImage(_ image: RenderImage, _ currentWindow: inout Window?) {
        for window in windowsById.values {
            var win = window
            win.dropImage(image)
        }
        if var currentWindow {
            currentWindow.dropImage(image)
        }
    }

    public func setInspectorRenderer(_ f: Any) {
        inspectorRenderer = f
    }

    public func registerInspectorElement<T>(_ f: Any, _ type: T.Type = T.self) {
        inspectorElementRegistry[ObjectIdentifier(T.self)] = f
    }

    public func initColors() {
        setGlobal(GlobalColors(Colors.dark()))
    }

    public func backgroundExecutor() -> BackgroundExecutor {
        _backgroundExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor {
        _foregroundExecutor
    }

    public func spawn<R: Sendable>(_ f: @escaping @Sendable (AsyncApp) async -> R) -> Task<R> {
        let asyncApp = toAsync()
        return _foregroundExecutor.spawn {
            await f(asyncApp)
        }
    }

    public func spawnWithPriority<R: Sendable>(_ priority: Priority, _ f: @escaping @Sendable (AsyncApp) async -> R) -> Task<R> {
        let asyncApp = toAsync()
        return _foregroundExecutor.spawn {
            await f(asyncApp)
        }
    }

    public func toAsync() -> AsyncApp {
        AsyncApp(app: self, backgroundExecutor: _backgroundExecutor, foregroundExecutor: _foregroundExecutor)
    }
}

extension AnyWindowHandle {
    @MainActor
    public func update<T>(
        _ cx: App,
        _ update: (AnyView, inout Window, App) throws -> T
    ) throws -> T {
        try cx.updateWindow(self, update)
    }

    @MainActor
    public func read<T>(
        _ cx: App,
        _ read: (AnyView, App) throws -> T
    ) throws -> T {
        try cx.readWindow(self, read)
    }
}

extension WindowHandle {
    @MainActor
    public func update<T>(
        _ cx: App,
        _ update: (AnyView, inout Window, App) throws -> T
    ) throws -> T {
        try cx.updateWindow(anyHandle, update)
    }
}

// MARK: - Asset & Drag/Tooltip/Keystroke Data Structures

struct AssetId: Hashable, Sendable {
    let typeId: ObjectIdentifier
    let sourceHash: Int
}

/// Contains state associated with an active drag operation, started by dragging an element
/// within the window or by dragging into the app from the underlying platform.
// PORT NOTE: AnyDrag stores a type-erased value (`Any`) and view handle passed across UI callbacks; safe because drag operations execute strictly on the MainActor in GPUI.
public struct AnyDrag: @unchecked Sendable {
    /// The view used to render this drag
    public var view: AnyView

    /// The value of the dragged item, to be dropped
    public var value: Any

    /// This is used to render the dragged item in the same place
    /// on the original element that the drag was initiated
    public var cursorOffset: Point<Pixels>

    /// The cursor style to use while dragging
    public var cursorStyle: CursorStyle?

    public init(
        view: AnyView,
        value: Any,
        cursorOffset: Point<Pixels> = .zero,
        cursorStyle: CursorStyle? = nil
    ) {
        self.view = view
        self.value = value
        self.cursorOffset = cursorOffset
        self.cursorStyle = cursorStyle
    }
}

/// Contains state associated with a tooltip. You'll only need this struct if you're implementing
/// tooltip behavior on a custom element.
// PORT NOTE: AnyTooltip stores a view and closure (`inout Window, inout App`) for dynamic hover bounds checks; safe under GPUI's MainActor event loop execution model.
public struct AnyTooltip: @unchecked Sendable {
    /// The view used to display the tooltip
    public var view: AnyView

    /// The absolute position of the mouse when the tooltip was deployed.
    public var mousePosition: Point<Pixels>

    /// Given the bounds of the tooltip, checks whether the tooltip should still be visible and
    /// updates its state accordingly.
    public var checkVisibleAndUpdate: @Sendable (Bounds<Pixels>, inout Window, inout App) -> Bool

    public init(
        view: AnyView,
        mousePosition: Point<Pixels> = .zero,
        checkVisibleAndUpdate: @escaping @Sendable (Bounds<Pixels>, inout Window, inout App) -> Bool = { _, _, _ in true }
    ) {
        self.view = view
        self.mousePosition = mousePosition
        self.checkVisibleAndUpdate = checkVisibleAndUpdate
    }
}

/// A keystroke event, and potentially the associated action
public struct KeystrokeEvent: Sendable {
    /// The keystroke that occurred
    public var keystroke: Keystroke

    /// The action that was resolved for the keystroke, if any
    public var action: (any Action)?

    /// The context stack at the time
    public var contextStack: [KeyContext]

    public init(
        keystroke: Keystroke,
        action: (any Action)? = nil,
        contextStack: [KeyContext] = []
    ) {
        self.keystroke = keystroke
        self.action = action
        self.contextStack = contextStack
    }
}

