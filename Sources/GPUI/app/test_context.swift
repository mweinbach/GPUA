// Ported from: crates/gpui/src/app/test_context.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Scheduler

// PORT NOTE: EmptyView provides an empty renderable view for test windows.
public struct EmptyView: Render, @unchecked Sendable {
    public init() {}
}

// PORT NOTE: TestAppContext wraps App and mock platform services for deterministic testing.
@MainActor
public final class TestAppContext: @unchecked Sendable {
    public let app: App
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor
    public let dispatcher: TestDispatcher
    public let testPlatform: TestPlatform
    public let textSystem: TextSystem
    public var fnName: String?
    public var onQuitCallbacks: [() -> Void] = []

    public init(
        app: App,
        backgroundExecutor: BackgroundExecutor,
        foregroundExecutor: ForegroundExecutor,
        dispatcher: TestDispatcher,
        testPlatform: TestPlatform,
        textSystem: TextSystem,
        fnName: String? = nil
    ) {
        self.app = app
        self.backgroundExecutor = backgroundExecutor
        self.foregroundExecutor = foregroundExecutor
        self.dispatcher = dispatcher
        self.testPlatform = testPlatform
        self.textSystem = textSystem
        self.fnName = fnName
    }

    public static func build(dispatcher: TestDispatcher, fnName: String? = nil) -> TestAppContext {
        let bg = BackgroundExecutor(scheduler: dispatcher.schedulerInstance)
        let fg = ForegroundExecutor(sessionId: dispatcher.sessionId, scheduler: dispatcher.schedulerInstance)
        let platform = TestPlatform(
            executor: bg,
            foregroundExecutor: fg,
            textSystem: NoopTextSystem()
        )
        let ts = TextSystem(platformTextSystem: platform.textSystem())
        let app = App.newApp(platform: platform)
        app.mode = .test(skipDrawing: false)

        return TestAppContext(
            app: app,
            backgroundExecutor: bg,
            foregroundExecutor: fg,
            dispatcher: dispatcher,
            testPlatform: platform,
            textSystem: ts,
            fnName: fnName
        )
    }

    public func skipDrawing() {
        app.mode = .test(skipDrawing: true)
    }

    public static func single() -> TestAppContext {
        let dispatcher = TestDispatcher.new(seed: 0)
        return TestAppContext.build(dispatcher: dispatcher, fnName: nil)
    }

    public func testFunctionName() -> String? {
        fnName
    }

    public func didPromptForNewPath() -> Bool {
        testPlatform.didPromptForNewPath()
    }

    public func newApp() -> TestAppContext {
        TestAppContext.build(dispatcher: dispatcher, fnName: fnName)
    }

    public func quit() {
        let callbacks = onQuitCallbacks
        onQuitCallbacks.removeAll()
        for cb in callbacks {
            cb()
        }
        app.shutdown()
    }

    public func onQuit(_ f: @escaping () -> Void) {
        onQuitCallbacks.append(f)
    }

    public func refresh() throws {
        app.refreshWindows()
    }

    public func executor() -> BackgroundExecutor {
        backgroundExecutor
    }

    @discardableResult
    public func update<R>(_ f: (App) -> R) -> R {
        app.update(f)
    }

    public func read<R>(_ f: (App) -> R) -> R {
        f(app)
    }

    public func addWindow<V: Render>(_ buildWindow: @escaping (inout Window, App) -> V) -> WindowHandle<V> {
        let options = WindowOptions(windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080)))))
        return try! app.openWindow(options) { window, cx in
            cx.new { _ in buildWindow(&window, cx) }
        }
    }

    public func openWindow<V: Render>(
        windowSize: Size<Pixels>,
        _ buildWindow: @escaping (inout Window, App) -> V
    ) -> WindowHandle<V> {
        let options = WindowOptions(windowBounds: .windowed(Bounds(origin: .zero, size: windowSize)))
        return try! app.openWindow(options) { window, cx in
            cx.new { _ in buildWindow(&window, cx) }
        }
    }

    public func addEmptyWindow() -> AnyWindowHandle {
        let options = WindowOptions(windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(800), height: px(600)))))
        return (try! app.openWindow(options) { _, cx in
            cx.new { _ in EmptyView() }
        }).anyHandle
    }

    public func addWindowView<V: Render>(_ view: Entity<V>) -> WindowHandle<V> {
        let options = WindowOptions(windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(1920), height: px(1080)))))
        return try! app.openWindow(options) { _, _ in view }
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        testPlatform.writeToClipboard(item)
    }

    public func readFromClipboard() -> ClipboardItem? {
        testPlatform.readFromClipboard()
    }

    public func simulateNewPathSelection(_ selectPath: (URL) -> URL?) {
        testPlatform.simulateNewPathSelection(selectPath)
    }

    public func simulatePromptAnswer(_ response: String) {
        testPlatform.simulatePromptAnswer(response)
    }

    public func hasPendingPrompt() -> Bool {
        testPlatform.hasPendingPrompt()
    }

    public func pendingPrompt() -> (String, String)? {
        testPlatform.pendingPrompt()
    }

    public func openedUrl() -> String? {
        testPlatform.openedUrl
    }

    public func simulateWindowResize(_ window: AnyWindowHandle, size: Size<Pixels>) {
        if let win = testWindow(window) {
            win.simulateResize(size: size)
        }
    }

    public func expectRestart(_ handler: @escaping (URL?) -> Void) {
        testPlatform.expectRestart = handler
    }

    public func setScreenCaptureSources(_ sources: [TestScreenCaptureSource]) {
        testPlatform.setScreenCaptureSources(sources)
    }

    public func windows() -> [AnyWindowHandle] {
        app.windows()
    }

    public func testWindow(_ window: AnyWindowHandle) -> TestWindow? {
        testPlatform.activeWindowVal
    }

    public func runUntilParked() {
        dispatcher.runUntilParked()
    }

    public func clearPendingActions() {
        // Clear pending dispatched actions
    }

    public func simulateKeystroke(_ window: AnyWindowHandle, keystroke: String) {
        guard let ks = try? Keystroke.parse(keystroke) else { return }
        _ = dispatchKeystroke(window, ks)
        runUntilParked()
    }

    public func simulateKeystrokes(_ window: AnyWindowHandle, _ keystrokes: String) {
        for ks in keystrokes.components(separatedBy: " ") {
            simulateKeystroke(window, keystroke: ks)
        }
    }

    public func simulateInput(_ window: AnyWindowHandle, _ input: String) {
        for ch in input {
            simulateKeystroke(window, keystroke: String(ch))
        }
    }

    public func simulateEvent(_ window: AnyWindowHandle, _ event: PlatformInput) -> Bool {
        guard let win = testWindow(window) else { return false }
        return win.simulateInput(event: event)
    }

    public func dispatchAction(_ window: AnyWindowHandle, _ action: any Action) {
        app.update { cx in
            cx.dispatchAction(action)
        }
    }

    public func dispatchKeystroke(_ window: AnyWindowHandle, _ keystroke: Keystroke) -> Bool {
        var handled = false
        _ = try? app.updateWindow(window) { _, win, cx in
            var cx = cx
            handled = win.dispatchKeystroke(keystroke, &cx)
        }
        return handled
    }

    public func advanceClock(by: TimeInterval) {
        dispatcher.advanceClock(by: by)
    }

    public func advanceClockToNextTimer() -> Bool {
        dispatcher.advanceClockToNextTimer()
    }

    public func spawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        foregroundExecutor.spawn(future)
    }

    public func backgroundSpawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        backgroundExecutor.spawn(future)
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        app.hasGlobal(type)
    }

    public func readGlobal<G: Global, R>(_ type: G.Type = G.self, _ read: (G, App) -> R) -> R {
        app.readGlobal(read)
    }

    public func tryReadGlobal<G: Global, R>(_ type: G.Type = G.self, _ read: (G, App) -> R) -> R? {
        guard let g = app.tryGlobal(type) else { return nil }
        return read(g, app)
    }

    public func setGlobal<G: Global>(_ global: G) {
        app.setGlobal(global)
    }

    public func updateGlobal<G: Global, R>(_ type: G.Type = G.self, _ update: (inout G, App) -> R) -> R {
        app.updateGlobal(update)
    }

    public func toAsync() -> AsyncApp {
        AsyncApp(
            app: app,
            backgroundExecutor: backgroundExecutor,
            foregroundExecutor: foregroundExecutor
        )
    }

    public func notifications<T>(for entity: Entity<T>) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let sub = self.app.observe(entity) { _, _ in
                continuation.yield(())
                return true
            }
            continuation.onTermination = { _ in
                _ = sub
            }
        }
    }

    public func events<Evt: Sendable, T>(for entity: Entity<T>) -> AsyncStream<Evt> {
        AsyncStream { continuation in
            let sub = self.app.subscribe(entity) { (_: Entity<T>, event: Evt, _: App) in
                continuation.yield(event)
                return true
            }
            continuation.onTermination = { _ in
                _ = sub
            }
        }
    }

    public func condition<T>(
        entity: Entity<T>,
        _ predicate: @escaping (inout T, inout Context<T>) -> Bool
    ) async throws {
        var satisfied = false
        app.update { cx in
            entity.update(cx) { val, cx in
                satisfied = predicate(&val, &cx)
            }
        }
        if satisfied { return }

        for await _ in notifications(for: entity) {
            app.update { cx in
                entity.update(cx) { val, cx in
                    satisfied = predicate(&val, &cx)
                }
            }
            if satisfied { return }
        }
    }

    public func setName(_ name: String) {
        self.fnName = name
    }
}

// MARK: - Entity Test Extensions

@MainActor
extension Entity {
    public func nextEvent<Event: Sendable>(cx: TestAppContext) async -> Event {
        let stream: AsyncStream<Event> = cx.events(for: self)
        for await event in stream {
            return event
        }
        fatalError("No event emitted")
    }

    public func nextNotification(advanceClockBy: TimeInterval = 0, cx: TestAppContext) async {
        if advanceClockBy > 0 {
            cx.advanceClock(by: advanceClockBy)
        }
        let stream = cx.notifications(for: self)
        for await _ in stream {
            return
        }
    }

    public func condition<Evt>(_ eventType: Evt.Type = Evt.self, cx: TestAppContext, _ predicate: @escaping (T, App) -> Bool) async {
        if cx.read({ predicate(self.read($0), $0) }) { return }
        let stream = cx.notifications(for: self)
        for await _ in stream {
            if cx.read({ predicate(self.read($0), $0) }) { return }
        }
    }
}

// MARK: - VisualTestContext

// PORT NOTE: VisualTestContext provides window-scoped test helpers.
@MainActor
public final class VisualTestContext: @unchecked Sendable {
    public var cx: TestAppContext
    public var window: AnyWindowHandle

    public init(cx: TestAppContext, window: AnyWindowHandle) {
        self.cx = cx
        self.window = window
    }

    public static func fromWindow(_ window: AnyWindowHandle, _ cx: TestAppContext) -> VisualTestContext {
        VisualTestContext(cx: cx, window: window)
    }

    @discardableResult
    public func update<R>(_ f: (inout Window, App) -> R) -> R {
        try! cx.app.updateWindow(window) { root, window, app in
            f(&window, app)
        }
    }

    public func runUntilParked() {
        cx.runUntilParked()
    }

    public func dispatchAction(_ action: any Action) {
        cx.dispatchAction(window, action)
    }

    public func windowTitle() -> String? {
        cx.testWindow(window)?.state.title
    }

    public func simulateKeystrokes(_ keystrokes: String) {
        cx.simulateKeystrokes(window, keystrokes)
    }

    public func simulateInput(_ input: String) {
        cx.simulateInput(window, input)
    }

    public func simulateMouseMove(position: Point<Pixels>) {
        _ = cx.simulateEvent(window, .mouseMove(MouseMoveEvent(position: position)))
    }

    public func simulateMouseDown(position: Point<Pixels>, button: MouseButton = .left) {
        _ = cx.simulateEvent(window, .mouseDown(MouseDownEvent(button: button, position: position)))
    }

    public func simulateMouseUp(position: Point<Pixels>, button: MouseButton = .left) {
        _ = cx.simulateEvent(window, .mouseUp(MouseUpEvent(button: button, position: position)))
    }

    public func simulateClick(position: Point<Pixels>, button: MouseButton = .left) {
        simulateMouseDown(position: position, button: button)
        simulateMouseUp(position: position, button: button)
    }

    public func simulateScroll(position: Point<Pixels>, delta: Point<Pixels>) {
        _ = cx.simulateEvent(window, .scrollWheel(ScrollWheelEvent(position: position, delta: .pixels(delta))))
    }

    public func simulateModifiersChange(modifiers: Modifiers) {
        _ = cx.simulateEvent(window, .modifiersChanged(ModifiersChangedEvent(modifiers: modifiers)))
    }

    public func simulateCapslockChange(on: Bool) {
        _ = cx.simulateEvent(window, .modifiersChanged(ModifiersChangedEvent(modifiers: Modifiers(), capslock: Capslock(on: on))))
    }

    public func simulateResize(size: Size<Pixels>) {
        cx.simulateWindowResize(window, size: size)
    }

    public func debugBounds(_ selector: String) -> Bounds<Pixels>? {
        cx.testWindow(window)?.bounds()
    }

    public func draw(
        _ origin: Point<Pixels> = .zero,
        _ space: Size<AvailableSpace> = Size(width: .definite(px(1920)), height: .definite(px(1080)))
    ) {
        update { window, _ in
            window.refresh()
        }
    }

    public func deactivateWindow() {
        if cx.testPlatform.activeWindow() == window {
            cx.testPlatform.setActiveWindow(nil)
        }
        cx.runUntilParked()
    }

    public func simulateClose() -> Bool {
        if let win = cx.testWindow(window), let handler = win.state.shouldCloseHandler {
            return handler()
        }
        return false
    }

    public func intoMut() -> VisualTestContext {
        self
    }
}

// MARK: - AnyWindowHandle Test Extension

@MainActor
extension AnyWindowHandle {
    public func buildEntity<V: Render>(
        cx: TestAppContext,
        _ buildView: @escaping (inout Window, App) -> V
    ) -> Entity<V> {
        try! cx.app.updateWindow(self) { _, window, app in
            app.new { _ in buildView(&window, app) }
        }
    }
}
