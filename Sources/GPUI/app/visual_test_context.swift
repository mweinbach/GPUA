// Ported from: crates/gpui/src/app/visual_test_context.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Refineable
import Scheduler

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
        _ = try? cx.app.updateWindow(window) { _, win, app in
            var app = app
            win.dispatchAction(action, &app)
        }
        cx.runUntilParked()
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

    public func draw() {
        _ = try? cx.app.updateWindow(window) { _, window, cx in
            var cx = cx
            window.draw(cx: &cx)
        }
        cx.runUntilParked()
    }

    public func draw<E: IntoElement>(
        _ origin: Point<Pixels> = .zero,
        _ space: Size<Pixels>,
        _ f: (inout Window, App) -> E
    ) {
        let availSpace = Size(width: AvailableSpace.definite(space.width), height: AvailableSpace.definite(space.height))
        draw(origin, availSpace, f)
    }

    public func draw<E: IntoElement>(
        _ origin: Point<Pixels> = .zero,
        _ space: Size<AvailableSpace> = Size(width: .definite(px(1920)), height: .definite(px(1080))),
        _ f: (inout Window, App) -> E
    ) {
        update { window, cx in
            var cx = cx
            window.invalidator.setPhase(.prepaint)
            var element = f(&window, cx).intoAnyElement()
            _ = element.layoutAsRoot(space, &window, &cx)
            window.withAbsoluteElementOffset(origin) { window in
                _ = element.prepaintAt(origin, &window, &cx)
            }
            window.invalidator.setPhase(.paint)
            element.paint(&window, &cx)
            window.invalidator.setPhase(.none)

            window.nextFrame.finish(prevFrame: &window.renderedFrame)
            swap(&window.renderedFrame, &window.nextFrame)
            window.nextFrame.clear()

            window.refresh()
        }
        cx.runUntilParked()
    }

    public func simulateEvent(_ event: ScrollWheelEvent) {
        _ = cx.simulateEvent(window, .scrollWheel(event))
        cx.runUntilParked()
    }

    public func simulateEvent(_ event: PlatformInput) {
        _ = cx.simulateEvent(window, event)
        cx.runUntilParked()
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

public struct VisualTestTimeoutError: LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "Timed out waiting for condition" }
}

// MARK: - VisualTestAppContext

/// A test context that uses real platform rendering with deterministic task scheduling.
// PORT NOTE: VisualTestAppContext wraps main-actor App instance with visual test platform.
@MainActor
public final class VisualTestAppContext: AppContext, @unchecked Sendable {
    public let app: App
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor
    public let visualPlatform: VisualTestPlatform

    public init(platform: any Platform, assetSource: any AssetSource = EmptyAssetSource()) {
        let vPlatform = VisualTestPlatform(platform: platform)
        self.visualPlatform = vPlatform
        self.backgroundExecutor = vPlatform.backgroundExecutorInstance
        self.foregroundExecutor = vPlatform.foregroundExecutorInstance
        let app = App(platform: vPlatform, assetSource: assetSource)
        self.app = app
    }

    public static func new(platform: any Platform) -> VisualTestAppContext {
        VisualTestAppContext(platform: platform)
    }

    public static func withAssetSource(
        platform: any Platform,
        assetSource: any AssetSource
    ) -> VisualTestAppContext {
        VisualTestAppContext(platform: platform, assetSource: assetSource)
    }

    public func withAssetSource(_ assetSource: any AssetSource) -> VisualTestAppContext {
        VisualTestAppContext(platform: visualPlatform.platform, assetSource: assetSource)
    }

    public func openOffscreenWindow<V: Render>(
        size: Size<Pixels> = size(px(1280.0), px(800.0)),
        buildRoot: @escaping (inout Window, inout App) -> Entity<V>
    ) throws -> WindowHandle<V> {
        let bounds = Bounds(origin: point(px(-10000.0), px(-10000.0)), size: size)
        var options = WindowOptions()
        options.windowBounds = .windowed(bounds)
        options.focus = false
        options.show = true
        return try app.openWindow(options) { win, cx in
            var cx = cx
            return buildRoot(&win, &cx)
        }
    }

    public func openOffscreenWindowDefault() -> VisualTestContext {
        let handle = try! openOffscreenWindow(size: size(px(1280.0), px(800.0))) { _, cx in
            cx.new { _ in EmptyView() }
        }
        let testPlatform = (visualPlatform.platform as? TestPlatform) ?? TestPlatform(
            executor: backgroundExecutor,
            foregroundExecutor: foregroundExecutor,
            textSystem: visualPlatform.textSystem()
        )
        let ts = TextSystem(platformTextSystem: visualPlatform.textSystem())
        let testAppContext = TestAppContext(
            app: app,
            backgroundExecutor: backgroundExecutor,
            foregroundExecutor: foregroundExecutor,
            dispatcher: visualPlatform.dispatcher(),
            testPlatform: testPlatform,
            textSystem: ts
        )
        let cx = VisualTestContext(cx: testAppContext, window: handle.anyHandle)
        cx.runUntilParked()
        return cx
    }

    public func openOffscreenWindowDefault<V: Render>(
        buildRoot: @escaping (inout Window, inout App) -> Entity<V>
    ) throws -> WindowHandle<V> {
        try openOffscreenWindow(size: size(px(1280.0), px(800.0)), buildRoot: buildRoot)
    }

    public func isScreenCaptureSupported() -> Bool {
        visualPlatform.isScreenCaptureSupported()
    }

    public func textSystem() -> TextSystem {
        TextSystem(platformTextSystem: visualPlatform.textSystem())
    }

    public func executor() -> BackgroundExecutor {
        backgroundExecutor
    }

    public func runUntilParked() {
        visualPlatform.dispatcher().runUntilParked()
    }

    public func advanceClock(_ duration: Duration) {
        visualPlatform.dispatcher().advanceClock(by: duration)
    }

    public func read<R>(_ f: (App) -> R) -> R {
        f(app)
    }

    public func spawn<R: Sendable>(_ future: @escaping @Sendable () async -> R) -> Task<R> {
        foregroundExecutor.spawn(future)
    }

    public func hasGlobal<G: Global>(_ type: G.Type = G.self) -> Bool {
        app.hasGlobal(type)
    }

    public func updateGlobal<G: Global, R>(_ f: (inout G, inout App) -> R) -> R {
        var global: G = leaseGlobal()
        var a = app
        let result = f(&global, &a)
        endGlobalLease(global)
        return result
    }

    public func dispatchKeystroke(_ window: AnyWindowHandle, _ keystroke: Keystroke) {
        _ = try? updateWindow(window) { _, win, app in
            var win = win
            var a = app
            _ = win.dispatchKeystroke(keystroke, &a)
        }
    }

    public func writeToClipboard(_ item: ClipboardItem) {
        visualPlatform.writeToClipboard(item)
    }

    public func readFromClipboard() -> ClipboardItem? {
        visualPlatform.readFromClipboard()
    }

    public func waitFor<T>(
        timeout: Duration = .seconds(5),
        _ condition: @escaping () -> T?
    ) async throws -> T {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            runUntilParked()
            if let result = condition() {
                return result
            }
            advanceClock(.milliseconds(10))
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }
        if let result = condition() {
            return result
        }
        throw VisualTestTimeoutError()
    }

    public func waitFor<T>(
        _ entity: Entity<T>,
        timeout: Duration = .seconds(5),
        predicate: @escaping (T) -> Bool
    ) async throws {
        _ = try await waitFor(timeout: timeout) { [weak self] () -> Bool? in
            guard let self else { return nil }
            let val = self.readEntity(entity) { state, _ in state }
            return predicate(val) ? true : nil
        }
    }

    public func captureScreenshot(_ window: AnyWindowHandle) throws -> Image? {
        try app.updateWindow(window) { _, window, _ in
            window.platformWindow.renderToImage(scene: window.renderedFrame.scene)
        }
    }

    public func waitForAnimations() async throws {
        advanceClock(.milliseconds(32))
        try? await _Concurrency.Task.sleep(nanoseconds: 32_000_000)
        runUntilParked()
    }

    // MARK: - AppContext Protocol

    public func update<R>(_ f: (inout App) -> R) -> R {
        var a = app
        return f(&a)
    }

    public func new<T>(_ build: (inout Context<T>) -> T) -> Entity<T> {
        app.new(build)
    }

    public func reserveEntity<T>(_ type: T.Type = T.self) -> Reservation<T> {
        app.reserveEntity(type)
    }

    public func insertEntity<T>(
        _ reservation: Reservation<T>,
        _ buildEntity: (inout Context<T>) -> T
    ) -> Entity<T> {
        app.insertEntity(reservation, buildEntity)
    }

    public func updateEntity<T, R>(_ entity: Entity<T>, _ update: (inout T, inout Context<T>) -> R) -> R {
        var a = app
        return entity.update(&a, update)
    }

    public func asMut<T>(_ handle: Entity<T>) -> GpuiBorrow<T> {
        app.asMut(handle)
    }

    public func readEntity<T, R>(_ entity: Entity<T>, _ read: (T, App) -> R) -> R {
        app.readEntity(entity, read)
    }

    public func readGlobal<G: Global, R>(_ callback: (G, App) -> R) -> R {
        app.readGlobal(callback)
    }

    public func updateWindow<T>(_ handle: AnyWindowHandle, _ f: (AnyView, inout Window, App) -> T) throws -> T {
        try app.updateWindow(handle, f)
    }

    public func readWindow<T, R>(_ handle: WindowHandle<T>, _ read: (Entity<T>, App) throws -> R) throws -> R {
        let ent = try handle.entity(app).get()
        return try read(ent, app)
    }

    public func global<G: Global>() -> G {
        app.global()
    }

    public func setGlobal<G: Global>(_ value: G) {
        app.setGlobal(value)
    }

    public func defaultGlobal<G: Global & DefaultInitializable>() -> G {
        app.defaultGlobal()
    }

    public func leaseGlobal<G: Global>() -> G {
        app.leaseGlobal()
    }

    public func endGlobalLease<G: Global>(_ global: G) {
        app.endGlobalLease(global)
    }
}
