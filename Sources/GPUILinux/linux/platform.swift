// Ported from: crates/gpui_linux/src/linux/platform.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI
import GPUIWGPU
import Scheduler

public let scrollLines: Float = 3.0
public let doubleClickInterval: TimeInterval = 0.400
public let doubleClickDistance: Pixels = Pixels(5.0)
public let keyringLabel: String = "zed-github-account"

public func isWithinClickDistance(_ a: Point<Pixels>, _ b: Point<Pixels>) -> Bool {
    let diff = a - b
    return abs(diff.x.value) <= doubleClickDistance.value && abs(diff.y.value) <= doubleClickDistance.value
}

public protocol LinuxClient: AnyObject, Sendable {
    func compositorName() -> String
    @discardableResult func withCommon<R>(_ f: (inout LinuxCommon) -> R) -> R
    func keyboardLayout() -> any PlatformKeyboardLayout
    func displays() -> [any PlatformDisplay]
    func primaryDisplay() -> (any PlatformDisplay)?
    func display(_ id: DisplayId) -> (any PlatformDisplay)?
    func activeWindow() -> AnyWindowHandle?
    func windowStack() -> [AnyWindowHandle]?
    func openWindow(handle: AnyWindowHandle, options: WindowOptions) throws -> any PlatformWindow
    func setCursorStyle(_ style: CursorStyle)
    func openUri(_ uri: String)
    func revealPath(_ path: URL)
    func writeToPrimary(_ item: ClipboardItem)
    func writeToClipboard(_ item: ClipboardItem)
    func readFromPrimary() -> ClipboardItem?
    func readFromClipboard() -> ClipboardItem?
    func keyboardMapper() -> (any PlatformKeyboardMapper)?
    func run()
}

extension LinuxClient {
    public func keyboardMapper() -> (any PlatformKeyboardMapper)? {
        nil
    }
}

// PORT NOTE: PlatformHandlers stores platform callback closures accessed from the main thread.
public struct PlatformHandlers: @unchecked Sendable {
    public var openUrls: (([String]) -> Void)?
    public var quit: (() -> Void)?
    public var reopen: (() -> Void)?
    public var appMenuAction: (@MainActor (any Action) -> Void)?
    public var willOpenAppMenu: (@MainActor () -> Void)?
    public var validateAppMenuCommand: (@MainActor (any Action) -> Bool)?
    public var keyboardLayoutChange: (() -> Void)?

    public init() {}
}

// PORT NOTE: LinuxCommon holds platform state and thread-safe executors.
public struct LinuxCommon: @unchecked Sendable {
    public var backgroundExecutor: GPUI.BackgroundExecutor
    public var foregroundExecutor: GPUI.ForegroundExecutor
    public var textSystem: any PlatformTextSystem
    public var appearance: WindowAppearance
    public var autoHideScrollbars: Bool
    public var callbacks: PlatformHandlers
    public var signal: LoopSignal
    public var menus: [OwnedMenu]

    public init(
        backgroundExecutor: GPUI.BackgroundExecutor,
        foregroundExecutor: GPUI.ForegroundExecutor,
        textSystem: any PlatformTextSystem,
        appearance: WindowAppearance = .light,
        autoHideScrollbars: Bool = false,
        callbacks: PlatformHandlers = PlatformHandlers(),
        signal: LoopSignal,
        menus: [OwnedMenu] = []
    ) {
        self.backgroundExecutor = backgroundExecutor
        self.foregroundExecutor = foregroundExecutor
        self.textSystem = textSystem
        self.appearance = appearance
        self.autoHideScrollbars = autoHideScrollbars
        self.callbacks = callbacks
        self.signal = signal
        self.menus = menus
    }

    public static func new(signal: LoopSignal) -> (LinuxCommon, PriorityQueueCalloopReceiver<@Sendable () -> Void>) {
        let (mainSender, mainReceiver) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let textSystem = CosmicTextSystem.new("sans-serif")
        let callbacks = PlatformHandlers()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)
        let backgroundExecutor = GPUI.BackgroundExecutor(dispatcher: dispatcher)
        let foregroundExecutor = GPUI.ForegroundExecutor(dispatcher: dispatcher)

        let common = LinuxCommon(
            backgroundExecutor: backgroundExecutor,
            foregroundExecutor: foregroundExecutor,
            textSystem: textSystem,
            appearance: .light,
            autoHideScrollbars: false,
            callbacks: callbacks,
            signal: signal,
            menus: []
        )
        return (common, mainReceiver)
    }
}

// PORT NOTE: LinuxPlatform wraps a thread-safe LinuxClient handle.
public final class LinuxPlatform<P: LinuxClient>: Platform, @unchecked Sendable {
    public let inner: P

    public init(inner: P) {
        self.inner = inner
    }

    public func textSystem() -> any PlatformTextSystem {
        inner.withCommon { $0.textSystem }
    }

    public func backgroundExecutor() -> GPUI.BackgroundExecutor? {
        inner.withCommon { $0.backgroundExecutor }
    }

    public func foregroundExecutor() -> GPUI.ForegroundExecutor? {
        inner.withCommon { $0.foregroundExecutor }
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        onFinishLaunching()
        inner.run()
        let quitCb = inner.withCommon { $0.callbacks.quit }
        quitCb?()
    }

    public func quit() {
        inner.withCommon { common in
            common.signal.stop()
            common.callbacks.quit?()
        }
    }

    public func restart(path: URL?) {}
    public func activate(ignoringOtherApps: Bool) {}
    public func hide() {}
    public func hideOtherApps() {}
    public func unhideOtherApps() {}

    public func displays() -> [any PlatformDisplay] {
        inner.displays()
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        inner.primaryDisplay()
    }

    public func activeWindow() -> AnyWindowHandle? {
        inner.activeWindow()
    }

    public func windowStack() -> [AnyWindowHandle]? {
        inner.windowStack()
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        guard let window = try? inner.openWindow(handle: handle, options: options) else {
            fatalError("Failed to open window")
        }
        return window
    }

    public func windowAppearance() -> WindowAppearance {
        inner.withCommon { $0.appearance }
    }

    public func buttonLayout() -> WindowButtonLayout? { nil }
    public func thermalState() -> ThermalState { .nominal }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        inner.keyboardLayout()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        inner.keyboardMapper() ?? LinuxKeyboardMapper()
    }

    public func readFromClipboard() -> ClipboardItem? {
        inner.readFromClipboard()
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        inner.writeToClipboard(item)
    }

    public func readFromPrimary() -> ClipboardItem? {
        inner.readFromPrimary()
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        inner.writeToPrimary(item)
    }

    public func readFromFindPasteboard() -> ClipboardItem? { nil }
    public func writeToFindPasteboard(_ item: ClipboardItem) {}
    public func writeCredentials(url: String, username: String, password: Data) async throws {}
    public func readCredentials(url: String) async throws -> (String, Data)? { nil }
    public func deleteCredentials(url: String) async throws {}

    public func openUrl(_ url: String) {
        inner.openUri(url)
    }

    public func registerUrlScheme(_ scheme: String) async throws {}
    public func appPath() throws -> URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? "")
    }

    public func compositorName() -> String {
        inner.compositorName()
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        throw LinuxError("auxiliary executable not found")
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? { nil }
    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? { nil }

    public func revealPath(_ path: URL) {
        inner.revealPath(path)
    }

    public func openWithSystem(_ path: URL) {
        inner.openUri(path.absoluteString)
    }

    public func shouldAutoHideScrollbars() -> Bool {
        inner.withCommon { $0.autoHideScrollbars }
    }

    public func isScreenCaptureSupported() -> Bool { false }
    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] { [] }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        inner.withCommon { $0.menus = menus.map { $0.owned() } }
    }

    public func getMenus() -> [OwnedMenu]? {
        inner.withCommon { $0.menus }
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {}
    public func performDockMenuAction(_ action: Int) {}
    public func addRecentDocument(_ path: URL) {}
    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] { [] }
    public func canSelectMixedFilesAndDirs() -> Bool { false }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        inner.withCommon { $0.callbacks.keyboardLayoutChange = callback }
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {}
    public func onReopen(_ callback: @escaping () -> Void) {
        inner.withCommon { $0.callbacks.reopen = callback }
    }
    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        inner.withCommon { $0.callbacks.openUrls = callback }
    }
    public func onQuit(_ callback: @escaping () -> Void) {
        inner.withCommon { $0.callbacks.quit = callback }
    }
    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        inner.withCommon { $0.callbacks.willOpenAppMenu = callback }
    }
    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        inner.withCommon { $0.callbacks.validateAppMenuCommand = callback }
    }
    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        inner.withCommon { $0.callbacks.appMenuAction = callback }
    }
}

public struct LinuxError: Swift.Error, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public func keystrokeUnderlyingDeadKey(_ keysym: UInt32) -> String? {
    switch keysym {
    case 0xFE50: return "`"  // dead_grave
    case 0xFE51: return "´"  // dead_acute
    case 0xFE52: return "^"  // dead_circumflex
    case 0xFE53: return "~"  // dead_tilde
    case 0xFE54: return "¯"  // dead_macron
    case 0xFE55: return "˘"  // dead_breve
    case 0xFE56: return "˙"  // dead_abovedot
    case 0xFE57: return "¨"  // dead_diaeresis
    case 0xFE58: return "˚"  // dead_abovering
    case 0xFE59: return "˝"  // dead_doubleacute
    case 0xFE5A: return "ˇ"  // dead_caron
    case 0xFE5B: return "¸"  // dead_cedilla
    case 0xFE5C: return "˛"  // dead_ogonek
    case 0xFE5D: return "ͅ"  // dead_iota
    case 0xFE5E: return "゙"  // dead_voiced_sound
    case 0xFE5F: return "゚"  // dead_semivoiced_sound
    case 0xFE60: return "̣̣"  // dead_belowdot
    case 0xFE61: return "̡"  // dead_hook
    case 0xFE62: return "̛"  // dead_horn
    case 0xFE63: return "̶̶"  // dead_stroke
    case 0xFE64: return "̓̓"  // dead_abovecomma
    case 0xFE65: return "ʽ"  // dead_abovereversedcomma
    case 0xFE66: return "̏"  // dead_doublegrave
    case 0xFE67: return "˳"  // dead_belowring
    default: return nil
    }
}

public func guessCompositor() -> String {
    if ProcessInfo.processInfo.environment["ZED_HEADLESS"] != nil {
        return "Headless"
    }
    let waylandDisplay = ProcessInfo.processInfo.environment["WAYLAND_DISPLAY"]
    let x11Display = ProcessInfo.processInfo.environment["DISPLAY"]
    if let waylandDisplay = waylandDisplay, !waylandDisplay.isEmpty {
        return "Wayland"
    } else if let x11Display = x11Display, !x11Display.isEmpty {
        return "X11"
    } else {
        return "Headless"
    }
}
#endif
