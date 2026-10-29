// Ported from: crates/gpui/src/platform/visual_test.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Scheduler

/// A platform that combines real platform rendering with a controllable `TestDispatcher`.
///
/// This allows visual tests to:
/// - Render real UI through the wrapped platform for accurate screenshots
/// - Control task scheduling deterministically via `TestDispatcher`
/// - Advance simulated time for testing time-based behaviors (tooltips, animations, etc.)
// PORT NOTE: VisualTestPlatform synchronizes test clipboard and delegates to underlying Platform.
public final class VisualTestPlatform: Platform, @unchecked Sendable {
    public let dispatcherInstance: TestDispatcher
    public let backgroundExecutorInstance: BackgroundExecutor
    public let foregroundExecutorInstance: ForegroundExecutor
    public let platform: any Platform
    private let lock = NSLock()
    private var clipboardItem: ClipboardItem?
    private var findPasteboardItem: ClipboardItem?

    public init(platform: any Platform, seed: UInt64 = 0) {
        let dispatcher = TestDispatcher.new(seed: seed)
        self.dispatcherInstance = dispatcher
        self.backgroundExecutorInstance = BackgroundExecutor(dispatcher: dispatcher)
        self.foregroundExecutorInstance = ForegroundExecutor(dispatcher: dispatcher)
        self.platform = platform
    }

    public static func new(platform: any Platform, seed: UInt64 = 0) -> VisualTestPlatform {
        VisualTestPlatform(platform: platform, seed: seed)
    }

    public func dispatcher() -> TestDispatcher {
        dispatcherInstance
    }

    // MARK: - Platform Conformance

    public func textSystem() -> any PlatformTextSystem {
        platform.textSystem()
    }

    public func backgroundExecutor() -> BackgroundExecutor? {
        backgroundExecutorInstance
    }

    public func foregroundExecutor() -> ForegroundExecutor? {
        foregroundExecutorInstance
    }

    public func run(_ onFinishLaunching: @escaping () -> Void) {
        // Run should not be called directly in test suites
        onFinishLaunching()
    }

    public func quit() {
        platform.quit()
    }

    public func restart(path: URL?) {
        platform.restart(path: path)
    }

    public func activate(ignoringOtherApps: Bool) {
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

    public func activeWindow() -> AnyWindowHandle? {
        platform.activeWindow()
    }

    public func windowStack() -> [AnyWindowHandle]? {
        platform.windowStack()
    }

    public func openWindow(handle: AnyWindowHandle, options: WindowOptions) -> any PlatformWindow {
        platform.openWindow(handle: handle, options: options)
    }

    public func windowAppearance() -> WindowAppearance {
        platform.windowAppearance()
    }

    public func buttonLayout() -> WindowButtonLayout? {
        platform.buttonLayout()
    }

    public func thermalState() -> ThermalState {
        platform.thermalState()
    }

    public func keyboardLayout() -> any PlatformKeyboardLayout {
        platform.keyboardLayout()
    }

    public func keyboardMapper() -> any PlatformKeyboardMapper {
        platform.keyboardMapper()
    }

    public func readFromClipboard() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return clipboardItem
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        clipboardItem = item
    }

    public func readFromPrimary() -> ClipboardItem? {
        readFromClipboard()
    }

    public func writeToPrimary(_ item: ClipboardItem) {
        writeToClipboard(item)
    }

    public func readFromFindPasteboard() -> ClipboardItem? {
        lock.lock()
        defer { lock.unlock() }
        return findPasteboardItem
    }

    public func writeToFindPasteboard(_ item: ClipboardItem) {
        lock.lock()
        defer { lock.unlock() }
        findPasteboardItem = item
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

    public func promptForPaths(options: PathPromptOptions) async throws -> [URL]? {
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

    public func isScreenCaptureSupported() -> Bool {
        platform.isScreenCaptureSupported()
    }

    public func screenCaptureSources() async throws -> [any ScreenCaptureSource] {
        try await platform.screenCaptureSources()
    }

    public func setMenus(_ menus: [Menu], keymap: Keymap) {
        platform.setMenus(menus, keymap: keymap)
    }

    public func getMenus() -> [OwnedMenu]? {
        platform.getMenus()
    }

    public func setDockMenu(_ menus: [MenuItem], keymap: Keymap) {
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

    public func canSelectMixedFilesAndDirs() -> Bool {
        platform.canSelectMixedFilesAndDirs()
    }

    public func onKeyboardLayoutChange(_ callback: @escaping () -> Void) {
        platform.onKeyboardLayoutChange(callback)
    }

    public func onThermalStateChange(_ callback: @escaping () -> Void) {
        platform.onThermalStateChange(callback)
    }

    public func onReopen(_ callback: @escaping () -> Void) {
        platform.onReopen(callback)
    }

    public func onOpenUrls(_ callback: @escaping ([String]) -> Void) {
        platform.onOpenUrls(callback)
    }

    public func onQuit(_ callback: @escaping () -> Void) {
        platform.onQuit(callback)
    }

    public func onWillOpenAppMenu(_ callback: @escaping @MainActor () -> Void) {
        platform.onWillOpenAppMenu(callback)
    }

    public func onValidateAppMenuCommand(_ callback: @escaping @MainActor (any Action) -> Bool) {
        platform.onValidateAppMenuCommand(callback)
    }

    public func onAppMenuAction(_ callback: @escaping @MainActor (any Action) -> Void) {
        platform.onAppMenuAction(callback)
    }
}
