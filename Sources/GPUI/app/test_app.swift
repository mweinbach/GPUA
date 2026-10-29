// Ported from: crates/gpui/src/app/test_app.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

// PORT NOTE: TestApp wraps App and mock platform services with automatic effect flushing for clean unit tests.
@MainActor
public final class TestApp: @unchecked Sendable {
    public let app: App
    public let platform: TestPlatform
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor
    public let dispatcher: TestDispatcher
    public let textSystem: TextSystem

    public init(
        app: App,
        platform: TestPlatform,
        backgroundExecutor: BackgroundExecutor,
        foregroundExecutor: ForegroundExecutor,
        dispatcher: TestDispatcher,
        textSystem: TextSystem
    ) {
        self.app = app
        self.platform = platform
        self.backgroundExecutor = backgroundExecutor
        self.foregroundExecutor = foregroundExecutor
        self.dispatcher = dispatcher
        self.textSystem = textSystem
    }

    public convenience init() {
        let app = TestApp.new()
        self.init(
            app: app.app,
            platform: app.platform,
            backgroundExecutor: app.backgroundExecutor,
            foregroundExecutor: app.foregroundExecutor,
            dispatcher: app.dispatcher,
            textSystem: app.textSystem
        )
    }

    public static func new() -> TestApp {
        TestApp.withSeed(0)
    }

    public static func withSeed(_ seed: UInt64) -> TestApp {
        TestApp.build(seed: seed, platformTextSystem: nil, assetSource: EmptyAssetSource())
    }

    public static func withTextSystem(_ textSystem: any PlatformTextSystem) -> TestApp {
        TestApp.build(seed: 0, platformTextSystem: textSystem, assetSource: EmptyAssetSource())
    }

    public static func withTextSystemAndAssets(
        _ textSystem: any PlatformTextSystem,
        _ assetSource: any AssetSource
    ) -> TestApp {
        TestApp.build(seed: 0, platformTextSystem: textSystem, assetSource: assetSource)
    }

    private static func build(
        seed: UInt64,
        platformTextSystem: (any PlatformTextSystem)?,
        assetSource: any AssetSource
    ) -> TestApp {
        let dispatcher = TestDispatcher.new(seed: seed)
        let bg = BackgroundExecutor(scheduler: dispatcher.schedulerInstance)
        let fg = ForegroundExecutor(sessionId: dispatcher.sessionId, scheduler: dispatcher.schedulerInstance)
        let platformTextSys = platformTextSystem ?? NoopTextSystem()
        let platform = TestPlatform(
            executor: bg,
            foregroundExecutor: fg,
            textSystem: platformTextSys
        )
        let ts = TextSystem(platformTextSystem: platformTextSys)
        let app = App.newApp(platform: platform, assetSource: assetSource)
        app.mode = .test(skipDrawing: false)

        return TestApp(
            app: app,
            platform: platform,
            backgroundExecutor: bg,
            foregroundExecutor: fg,
            dispatcher: dispatcher,
            textSystem: ts
        )
    }

    @discardableResult
    public func update<R>(_ f: (App) -> R) -> R {
        let result = app.update(f)
        runUntilParked()
        return result
    }

    public func read<R>(_ f: (App) -> R) -> R {
        f(app)
    }

    public func newEntity<T>(_ build: (inout Context<T>) -> T) -> Entity<T> {
        let entity = app.new(build)
        runUntilParked()
        return entity
    }

    @discardableResult
    public func updateEntity<T, R>(_ entity: Entity<T>, _ f: (inout T, inout Context<T>) -> R) -> R {
        let result = entity.update(app, f)
        runUntilParked()
        return result
    }

    public func readEntity<T, R>(_ entity: Entity<T>, _ f: (T, App) -> R) -> R {
        f(entity.read(app), app)
    }

    public func openWindow<V: Render>(_ buildWindow: @escaping (inout Window, App) -> V) -> TestAppWindow<V> {
        openWindowWithOptions(WindowOptions(), buildWindow)
    }

    public func openWindowWithOptions<V: Render>(
        _ options: WindowOptions,
        _ buildWindow: @escaping (inout Window, App) -> V
    ) -> TestAppWindow<V> {
        let handle = try! app.openWindow(options) { window, cx in
            cx.new { _ in buildWindow(&window, cx) }
        }
        runUntilParked()
        return TestAppWindow(
            handle: handle,
            app: app,
            platform: platform,
            backgroundExecutor: backgroundExecutor
        )
    }

    public func runUntilParked() {
        dispatcher.runUntilParked()
    }

    public func advanceClock(_ duration: TimeInterval) {
        dispatcher.advanceClock(by: duration)
        runUntilParked()
    }

    public func spawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        foregroundExecutor.spawn(future)
    }

    public func backgroundSpawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        backgroundExecutor.spawn(future)
    }

    public func toAsync() -> AsyncApp {
        AsyncApp(
            app: app,
            backgroundExecutor: backgroundExecutor,
            foregroundExecutor: foregroundExecutor
        )
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        app.hasGlobal(type)
    }

    public func setGlobal<G: Global>(_ global: G) {
        app.setGlobal(global)
        runUntilParked()
    }

    public func readGlobal<G: Global, R>(_ type: G.Type = G.self, _ read: (G, App) -> R) -> R {
        app.readGlobal(read)
    }

    @discardableResult
    public func updateGlobal<G: Global, R>(_ type: G.Type = G.self, _ update: (inout G, App) -> R) -> R {
        let result = app.updateGlobal(update)
        runUntilParked()
        return result
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        platform.writeToClipboard(item)
    }

    public func readFromClipboard() -> ClipboardItem? {
        platform.readFromClipboard()
    }

    public func openedUrl() -> String? {
        platform.openedUrl
    }

    public func didPromptForNewPath() -> Bool {
        platform.didPromptForNewPath()
    }

    public func simulateNewPathSelection(_ selectPath: (URL) -> URL?) {
        platform.simulateNewPathSelection(selectPath)
        runUntilParked()
    }

    public func hasPendingPrompt() -> Bool {
        platform.hasPendingPrompt()
    }

    public func simulatePromptAnswer(_ response: String) {
        platform.simulatePromptAnswer(response)
        runUntilParked()
    }

    public func windows() -> [AnyWindowHandle] {
        app.windows()
    }
}

// MARK: - TestAppWindow

// PORT NOTE: TestAppWindow provides inspection and input simulation on a test window.
@MainActor
public struct TestAppWindow<V: Render>: @unchecked Sendable {
    public let handle: WindowHandle<V>
    public let app: App
    public let platform: TestPlatform
    public let backgroundExecutor: BackgroundExecutor

    public init(
        handle: WindowHandle<V>,
        app: App,
        platform: TestPlatform,
        backgroundExecutor: BackgroundExecutor
    ) {
        self.handle = handle
        self.app = app
        self.platform = platform
        self.backgroundExecutor = backgroundExecutor
    }

    public func root() -> Entity<V> {
        guard case .success(let entity) = handle.entity(app) else {
            fatalError("Root view not found")
        }
        return entity
    }

    @discardableResult
    public func update<R>(_ f: (inout V, inout Window, inout Context<V>) -> R) -> R {
        let rootEntity = root()
        let result: R = try! app.updateWindow(handle.anyHandle) { _, window, cx in
            rootEntity.update(cx) { v, cx in
                f(&v, &window, &cx)
            }
        }
        backgroundExecutor.runUntilParked()
        return result
    }

    public func read<R>(_ f: (V, App) -> R) -> R {
        let rootEntity = root()
        return f(rootEntity.read(app), app)
    }

    public func title() -> String? {
        platform.activeWindowVal?.state.title
    }

    public func simulateKeystroke(_ keystroke: String) {
        guard let ks = try? Keystroke.parse(keystroke) else { return }
        _ = try! app.updateWindow(handle.anyHandle) { _, window, cx in
            var cx = cx
            _ = window.dispatchKeystroke(ks, &cx)
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateKeystrokes(_ keystrokes: String) {
        for ks in keystrokes.components(separatedBy: " ") {
            simulateKeystroke(ks)
        }
    }

    public func simulateInput(_ input: String) {
        for ch in input {
            simulateKeystroke(String(ch))
        }
    }

    public func simulateMouseMove(position: Point<Pixels>) {
        if let win = platform.activeWindowVal {
            _ = win.simulateInput(event: .mouseMove(MouseMoveEvent(position: position)))
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateMouseDown(position: Point<Pixels>, button: MouseButton = .left) {
        if let win = platform.activeWindowVal {
            _ = win.simulateInput(event: .mouseDown(MouseDownEvent(button: button, position: position)))
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateMouseUp(position: Point<Pixels>, button: MouseButton = .left) {
        if let win = platform.activeWindowVal {
            _ = win.simulateInput(event: .mouseUp(MouseUpEvent(button: button, position: position)))
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateClick(position: Point<Pixels>, button: MouseButton = .left) {
        simulateMouseDown(position: position, button: button)
        simulateMouseUp(position: position, button: button)
    }

    public func simulateScroll(position: Point<Pixels>, delta: Point<Pixels>) {
        if let win = platform.activeWindowVal {
            _ = win.simulateInput(event: .scrollWheel(ScrollWheelEvent(position: position, delta: .pixels(delta))))
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateEvent(_ event: PlatformInput) {
        if let win = platform.activeWindowVal {
            _ = win.simulateInput(event: event)
        }
        backgroundExecutor.runUntilParked()
    }

    public func simulateResize(size: Size<Pixels>) {
        if let win = platform.activeWindowVal {
            win.simulateResize(size: size)
        }
        backgroundExecutor.runUntilParked()
    }

    public func draw() {
        app.refreshWindows()
        backgroundExecutor.runUntilParked()
    }
}
