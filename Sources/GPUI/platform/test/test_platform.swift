// Ported from: crates/gpui/src/platform/test/platform.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

/// A fake screen capture source, used for testing.
public struct TestScreenCaptureSource: ScreenCaptureSource, Sendable {
    public var id: String { "test-source-0" }
    public var title: String { "Test Screen Capture Source" }

    public init() {}

    public static func new() -> TestScreenCaptureSource {
        TestScreenCaptureSource()
    }
}

/// A fake screen capture stream, used for testing.
public struct TestScreenCaptureStream: Sendable {
    public init() {}
}

// PORT NOTE: TestPrompt wraps a prompt continuation closure for synchronous test execution.
public struct TestPrompt: @unchecked Sendable {
    public var msg: String
    public var detail: String?
    public var answers: [String]
    public var continuation: (Int) -> Void

    public init(
        msg: String,
        detail: String? = nil,
        answers: [String] = [],
        continuation: @escaping (Int) -> Void
    ) {
        self.msg = msg
        self.detail = detail
        self.answers = answers
        self.continuation = continuation
    }
}

// PORT NOTE: TestPrompts manages mock prompt queues for deterministic testing.
public struct TestPrompts: @unchecked Sendable {
    public var multipleChoice: [TestPrompt] = []
    public var newPath: [(URL, (URL?) -> Void)] = []

    public init() {}
}

// PORT NOTE: TestPlatform stores mutable test state and synchronizes access with internal NSLock.
public final class TestPlatform: Platform, @unchecked Sendable {
    private let lock = NSLock()
    public var bgExecutor: BackgroundExecutor?
    public var fgExecutor: ForegroundExecutor?
    public var activeWindowVal: TestWindow?
    public var activeDisplayVal: any PlatformDisplay
    public var activeCursor: CursorStyle = .arrow
    public var currentClipboardItem: ClipboardItem?
    public var currentPrimaryItem: ClipboardItem?
    public var currentFindPasteboardItem: ClipboardItem?
    public var prompts: TestPrompts = TestPrompts()
    public var screenCaptureSourcesList: [TestScreenCaptureSource] = []
    public var openedUrl: String?
    public var textSystemInstance: any PlatformTextSystem
    public var expectRestart: ((URL?) -> Void)?

    public init(
        executor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil,
        textSystem: any PlatformTextSystem = NoopTextSystem()
    ) {
        self.bgExecutor = executor
        self.fgExecutor = foregroundExecutor
        self.textSystemInstance = textSystem
        self.activeDisplayVal = TestDisplay.new()
    }

    public static func new(
        executor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil
    ) -> TestPlatform {
        TestPlatform.withTextSystem(
            executor: executor,
            foregroundExecutor: foregroundExecutor,
            textSystem: NoopTextSystem()
        )
    }

    public static func withTextSystem(
        executor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil,
        textSystem: any PlatformTextSystem
    ) -> TestPlatform {
        TestPlatform.withPlatform(
            executor: executor,
            foregroundExecutor: foregroundExecutor,
            textSystem: textSystem,
            rendererFactory: nil
        )
    }

    public static func withPlatform(
        executor: BackgroundExecutor? = nil,
        foregroundExecutor: ForegroundExecutor? = nil,
        textSystem: any PlatformTextSystem,
        rendererFactory: Any? = nil
    ) -> TestPlatform {
        TestPlatform(
            executor: executor,
            foregroundExecutor: foregroundExecutor,
            textSystem: textSystem
        )
    }

    public func simulateNewPathSelection(_ selectPath: (URL) -> URL?) {
        lock.lock()
        guard !prompts.newPath.isEmpty else {
            lock.unlock()
            assertionFailure("no pending new path prompt")
            return
        }
        let (path, continuation) = prompts.newPath.removeFirst()
        lock.unlock()

        continuation(selectPath(path))
    }

    public func simulatePromptAnswer(_ response: String) {
        lock.lock()
        guard !prompts.multipleChoice.isEmpty else {
            lock.unlock()
            assertionFailure("no pending multiple choice prompt")
            return
        }
        let prompt = prompts.multipleChoice.removeFirst()
        lock.unlock()

        guard let ix = prompt.answers.firstIndex(of: response) else {
            assertionFailure("PROMPT: \(prompt.msg)\nCannot respond with \(response)")
            return
        }
        prompt.continuation(ix)
    }

    public func hasPendingPrompt() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !prompts.multipleChoice.isEmpty
    }

    public func pendingPrompt() -> (String, String)? {
        lock.lock()
        defer { lock.unlock() }
        guard let prompt = prompts.multipleChoice.first else { return nil }
        return (prompt.msg, prompt.detail ?? "")
    }

    public func setScreenCaptureSources(_ sources: [TestScreenCaptureSource]) {
        lock.lock()
        defer { lock.unlock() }
        screenCaptureSourcesList = sources
    }

    private func registerPrompt(msg: String, detail: String?, answerStrings: [String], continuation: @escaping (Int) -> Void) {
        lock.lock()
        prompts.multipleChoice.append(TestPrompt(
            msg: msg,
            detail: detail,
            answers: answerStrings,
            continuation: continuation
        ))
        lock.unlock()
    }

    public func prompt(
        msg: String,
        detail: String? = nil,
        answers: [PromptButton] = []
    ) async -> Int {
        let answerStrings = answers.map { $0.label.value }
        return await withCheckedContinuation { continuation in
            registerPrompt(msg: msg, detail: detail, answerStrings: answerStrings) { index in
                continuation.resume(returning: index)
            }
        }
    }

    public func setActiveWindow(_ window: TestWindow?) {
        lock.lock()
        let previous = activeWindowVal
        activeWindowVal = window
        lock.unlock()

        if let previous = previous, previous !== window {
            previous.simulateActiveStatusChange(active: false)
        }
        if let window = window {
            window.simulateActiveStatusChange(active: true)
        }
    }

    public func didPromptForNewPath() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !prompts.newPath.isEmpty
    }

    // MARK: - Platform Conformance

    public func backgroundExecutor() -> BackgroundExecutor? {
        lock.lock()
        defer { lock.unlock() }
        return bgExecutor
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        lock.lock()
        defer { lock.unlock() }
        return fgExecutor
    }

    public func textSystem() -> any PlatformTextSystem {
        lock.lock()
        defer { lock.unlock() }
        return textSystemInstance
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        onFinishLaunching()
    }

    public func quit() {}

    public func restart(path: URL?) {
        lock.lock()
        let handler = expectRestart
        expectRestart = nil
        lock.unlock()
        handler?(path)
    }

    public func activate(ignoringOtherApps: Bool) {}

    public func hide() {}

    public func hideOtherApps() {}

    public func unhideOtherApps() {}

    public func displays() -> [any PlatformDisplay] {
        lock.lock()
        defer { lock.unlock() }
        return [activeDisplayVal]
    }

    public func primaryDisplay() -> (any PlatformDisplay)? {
        lock.lock()
        defer { lock.unlock() }
        return activeDisplayVal
    }

    public func activeWindow() -> AnyWindowHandle? {
        lock.lock()
        defer { lock.unlock() }
        return activeWindowVal?.state.handle
    }

    public func windowStack() -> [AnyWindowHandle]? {
        lock.lock()
        defer { lock.unlock() }
        return activeWindowVal.map { [$0.state.handle] }
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        lock.lock()
        defer { lock.unlock() }
        let win = TestWindow.new(handle: handle, params: options, platform: self, display: activeDisplayVal)
        activeWindowVal = win
        return win
    }

    public func windowAppearance() -> WindowAppearance {
        .dark
    }

    public func buttonLayout() -> WindowButtonLayout? {
        nil
    }

    public func thermalState() -> ThermalState {
        .nominal
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        DummyKeyboardLayout()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        DummyKeyboardMapper()
    }

    public func readFromClipboard() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return currentClipboardItem
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        currentClipboardItem = item
    }

    public func readFromPrimary() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return currentPrimaryItem
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        currentPrimaryItem = item
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return currentFindPasteboardItem
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        currentFindPasteboardItem = item
    }

    public func writeCredentials(url: String, username: String, password: Data) async throws {}

    public func readCredentials(url: String) async throws -> (String, Data)? { nil }

    public func deleteCredentials(url: String) async throws {}

    public func openUrl(_ url: String) {
        lock.lock()
        openedUrl = url
        lock.unlock()
    }

    public func registerUrlScheme(_ scheme: String) async throws {}

    public func appPath() throws -> URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.arguments.first ?? "")
    }

    public func compositorName() -> String {
        "TestCompositor"
    }

    public func pathForAuxiliaryExecutable(_ name: String) throws -> URL {
        URL(fileURLWithPath: name)
    }

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
        nil
    }

    private func registerNewPathPrompt(directory: URL, continuation: @escaping (URL?) -> Void) {
        lock.lock()
        prompts.newPath.append((directory, continuation))
        lock.unlock()
    }

    public func promptForNewPath(directory: URL, suggestedName: String?) async throws -> URL? {
        await withCheckedContinuation { continuation in
            registerNewPathPrompt(directory: directory) { url in
                continuation.resume(returning: url)
            }
        }
    }

    public func revealPath(_ path: URL) {}

    public func openWithSystem(_ path: URL) {}

    public func shouldAutoHideScrollbars() -> Bool { false }

    public func isScreenCaptureSupported() -> Bool { false }

    private func getScreenCaptureSources() -> [any ScreenCaptureSource] {
        lock.lock()
        defer { lock.unlock() }
        return screenCaptureSourcesList
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        getScreenCaptureSources()
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {}

    public func getMenus() -> [OwnedMenu]? { nil }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {}

    public func performDockMenuAction(_ action: Int) {}

    public func addRecentDocument(_ path: URL) {}

    public func updateJumpList(menus: [MenuItem], entries: [[URL]]) async throws -> [[URL]] {
        entries
    }

    public func canSelectMixedFilesAndDirs() -> Bool { false }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {}

    public func onThermalStateChange(_ callback: @escaping () -> Void) {}

    public func onReopen(_ callback: @escaping () -> Void) {}

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {}

    public func onQuit(_ callback: @escaping () -> Void) {}
}
