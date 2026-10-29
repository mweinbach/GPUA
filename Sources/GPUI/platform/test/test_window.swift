// Ported from: crates/gpui/src/platform/test/window.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

// PORT NOTE: TestAtlasState holds atlas allocations for headless testing.
public final class TestAtlasState: @unchecked Sendable {
    public var nextId: UInt32 = 0
    public var tiles: [AtlasKey: AtlasTile] = [:]

    public init(nextId: UInt32 = 0, tiles: [AtlasKey: AtlasTile] = [:]) {
        self.nextId = nextId
        self.tiles = tiles
    }
}

// PORT NOTE: TestAtlas manages mock texture allocations across threads using internal lock.
public final class TestAtlas: PlatformAtlas, @unchecked Sendable {
    private let lock = NSLock()
    private let state: TestAtlasState

    public init() {
        self.state = TestAtlasState()
    }

    public static func new() -> TestAtlas {
        TestAtlas()
    }

    public func getOrInsertWith(
        key: AtlasKey,
        build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile? {
        lock.lock()
        if let existing = state.tiles[key] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let (size, _) = try build() else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }

        state.nextId += 1
        let textureId = state.nextId
        state.nextId += 1
        let tileId = state.nextId

        let tile = AtlasTile(
            textureId: AtlasTextureId(index: textureId, kind: .monochrome),
            tileId: TileId(tileId),
            padding: 0,
            bounds: Bounds(origin: Point(x: DevicePixels(0), y: DevicePixels(0)), size: size)
        )
        state.tiles[key] = tile
        return tile
    }

    public func remove(key: AtlasKey) {
        lock.lock()
        defer { lock.unlock() }
        state.tiles.removeValue(forKey: key)
    }
}

// PORT NOTE: TestWindowState holds state for headless test window simulation.
public final class TestWindowState: @unchecked Sendable {
    public var bounds: Bounds<Pixels>
    public var handle: AnyWindowHandle
    public var display: any PlatformDisplay
    public var title: String?
    public var edited: Bool
    public weak var platform: TestPlatform?
    public var spriteAtlas: any PlatformAtlas
    public var shouldCloseHandler: (() -> Bool)?
    public var hitTestWindowControlCallback: (() -> WindowControlArea?)?
    public var inputCallback: ((PlatformInput) -> DispatchEventResult)?
    public var activeStatusChangeCallback: ((Bool) -> Void)?
    public var hoverStatusChangeCallback: ((Bool) -> Void)?
    public var resizeCallback: ((Size<Pixels>, Float) -> Void)?
    public var movedCallback: (() -> Void)?
    public var inputHandler: (any PlatformInputHandlerProtocol)?
    public var isFullscreen: Bool
    public var isActive: Bool = false
    public var isHovered: Bool = false
    public var scaleFactor: Float = 1.0

    public init(
        bounds: Bounds<Pixels>,
        handle: AnyWindowHandle,
        display: any PlatformDisplay,
        platform: TestPlatform? = nil,
        spriteAtlas: any PlatformAtlas = TestAtlas.new()
    ) {
        self.bounds = bounds
        self.handle = handle
        self.display = display
        self.platform = platform
        self.spriteAtlas = spriteAtlas
        self.title = nil
        self.edited = false
        self.shouldCloseHandler = nil
        self.hitTestWindowControlCallback = nil
        self.inputCallback = nil
        self.activeStatusChangeCallback = nil
        self.hoverStatusChangeCallback = nil
        self.resizeCallback = nil
        self.movedCallback = nil
        self.inputHandler = nil
        self.isFullscreen = false
    }
}

// PORT NOTE: TestWindow implements PlatformWindow for headless testing with synchronized state.
public final class TestWindow: PlatformWindow, @unchecked Sendable {
    private let lock = NSLock()
    public let state: TestWindowState

    public init(
        handle: AnyWindowHandle,
        bounds: Bounds<Pixels> = Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(800), height: px(600))),
        display: any PlatformDisplay = TestDisplay.new(),
        platform: TestPlatform? = nil
    ) {
        self.state = TestWindowState(
            bounds: bounds,
            handle: handle,
            display: display,
            platform: platform
        )
    }

    public static func new(
        handle: AnyWindowHandle,
        params: WindowOptions = WindowOptions(),
        platform: TestPlatform? = nil,
        display: any PlatformDisplay = TestDisplay.new()
    ) -> TestWindow {
        let bounds = params.windowBounds.map { wb in
            switch wb {
            case .windowed(let b): return b
            case .maximized(let b): return b
            case .fullscreen(let b): return b
            }
        } ?? Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(800), height: px(600)))

        return TestWindow(
            handle: handle,
            bounds: bounds,
            display: display,
            platform: platform
        )
    }

    public func simulateResize(size: Size<Pixels>) {
        lock.lock()
        let callback = state.resizeCallback
        let factor = state.scaleFactor
        state.bounds.size = size
        lock.unlock()

        callback?(size, factor)
    }

    public func simulateActiveStatusChange(active: Bool) {
        lock.lock()
        let callback = state.activeStatusChangeCallback
        state.isActive = active
        lock.unlock()

        callback?(active)
    }

    public func simulateInput(event: PlatformInput) -> Bool {
        lock.lock()
        let callback = state.inputCallback
        lock.unlock()

        guard let callback = callback else { return false }
        let result = callback(event)
        return !result.propagate
    }

    // MARK: - PlatformWindow Conformance

    public func bounds() -> Bounds<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return state.bounds
    }

    public func contentSize() -> Size<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return state.bounds.size
    }

    public func scaleFactor() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return state.scaleFactor
    }

    public func appearance() -> WindowAppearance {
        .light
    }

    public func mousePosition() -> Point<Pixels> {
        .zero
    }

    public func modifiers() -> Modifiers {
        Modifiers()
    }

    public func capslock() -> Capslock {
        Capslock()
    }

    public func activate() {
        simulateActiveStatusChange(active: true)
    }

    public func isMaximized() -> Bool {
        false
    }

    public func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isActive
    }

    public func isHovered() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isHovered
    }

    public func isFullscreen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isFullscreen
    }

    public func minimize() {}

    public func zoom() {}

    public func toggleFullScreen() {
        lock.lock()
        state.isFullscreen.toggle()
        lock.unlock()
    }

    public func draw(scene: Scene) {}

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        lock.lock()
        defer { lock.unlock() }
        state.inputHandler = handler
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        let handler = state.inputHandler
        state.inputHandler = nil
        return handler
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        return state.inputHandler
    }

    public func display() -> (any PlatformDisplay)? {
        lock.lock()
        defer { lock.unlock() }
        return state.display
    }

    public func spriteAtlas() -> any PlatformAtlas {
        lock.lock()
        defer { lock.unlock() }
        return state.spriteAtlas
    }
}
