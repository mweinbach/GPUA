// Ported from: crates/gpui/src/app/headless_app_context.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Refineable
import Scheduler

/// A cross-platform headless app context for tests that need real text shaping or headless rendering.
///
/// Uses `TestPlatform` for deterministic scheduling and accepts a pluggable
/// `PlatformTextSystem` so tests get real glyph measurements.
// PORT NOTE: HeadlessAppContext wraps main-actor App instance with deterministic TestPlatform.
@MainActor
public final class HeadlessAppContext: AppContext, @unchecked Sendable {
    public let app: App
    public let backgroundExecutor: BackgroundExecutor
    public let foregroundExecutor: ForegroundExecutor
    public let dispatcher: TestDispatcher
    public let testPlatform: TestPlatform
    public let textSystem: any PlatformTextSystem

    public init(
        platformTextSystem: any PlatformTextSystem = NoopTextSystem(),
        assetSource: any AssetSource = EmptyAssetSource(),
        rendererFactory: (@Sendable () -> (any PlatformHeadlessRenderer)?)? = nil
    ) {
        let seed = ProcessInfo.processInfo.environment["SEED"].flatMap({ UInt64($0) }) ?? 0
        let dispatcher = TestDispatcher.new(seed: seed)
        let bg = BackgroundExecutor(dispatcher: dispatcher)
        let fg = ForegroundExecutor(dispatcher: dispatcher)

        let platform = TestPlatform(
            executor: bg,
            foregroundExecutor: fg,
            textSystem: platformTextSystem
        )

        self.dispatcher = dispatcher
        self.testPlatform = platform
        self.backgroundExecutor = bg
        self.foregroundExecutor = fg
        self.textSystem = platformTextSystem

        let app = App(platform: platform, assetSource: assetSource)
        self.app = app
    }

    public static func new(platformTextSystem: any PlatformTextSystem = NoopTextSystem()) -> HeadlessAppContext {
        HeadlessAppContext(platformTextSystem: platformTextSystem)
    }

    public static func withAssetSource(
        platformTextSystem: any PlatformTextSystem,
        assetSource: any AssetSource
    ) -> HeadlessAppContext {
        HeadlessAppContext(platformTextSystem: platformTextSystem, assetSource: assetSource)
    }

    public static func withPlatform(
        platformTextSystem: any PlatformTextSystem,
        assetSource: any AssetSource,
        rendererFactory: (@Sendable () -> (any PlatformHeadlessRenderer)?)? = nil
    ) -> HeadlessAppContext {
        HeadlessAppContext(
            platformTextSystem: platformTextSystem,
            assetSource: assetSource,
            rendererFactory: rendererFactory
        )
    }

    public func openWindow<V: Render>(
        size: Size<Pixels> = size(px(1280.0), px(800.0)),
        buildRoot: @escaping (inout Window, inout App) -> Entity<V>
    ) throws -> WindowHandle<V> {
        let bounds = Bounds(origin: point(px(0.0), px(0.0)), size: size)
        var options = WindowOptions()
        options.windowBounds = .windowed(bounds)
        options.focus = false
        options.show = false
        return try app.openWindow(options) { win, cx in
            var cx = cx
            return buildRoot(&win, &cx)
        }
    }

    public func runUntilParked() {
        dispatcher.runUntilParked()
    }

    public func advanceClock(_ duration: Duration) {
        dispatcher.advanceClock(by: duration)
    }

    public func allowParking() {
        dispatcher.schedulerInstance.allowParking()
    }

    public func forbidParking() {
        dispatcher.schedulerInstance.forbidParking()
    }

    public func captureScreenshot(window: AnyWindowHandle) throws -> Data {
        try app.updateWindow(window) { _, window, _ in
            let img = window.platformWindow.renderToImage(scene: window.renderedFrame.scene)
            return Data(img?.bytes ?? [])
        }
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
