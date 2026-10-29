// Ported from: crates/gpui/src/window.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy
import Scheduler

/// Default window size used when no explicit size is provided.
public let DEFAULT_WINDOW_SIZE: Size<Pixels> = size(px(1536.0), px(864.0))

/// A 6:5 aspect ratio minimum window size used for auxiliary windows.
public let DEFAULT_ADDITIONAL_WINDOW_SIZE: Size<Pixels> = size(px(900.0), px(750.0))

// MARK: - Surface ID

/// An identifier for a secondary GPUI rendering surface within a window.
public struct SurfaceId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    private static let nextId = NSLock()
    nonisolated(unsafe) private static var counter: UInt32 = 0

    public static func next() -> SurfaceId {
        nextId.lock()
        defer { nextId.unlock() }
        let id = counter
        counter += 1
        return SurfaceId(id)
    }
}

/// A handle returned when registering a surface, providing the native view pointer.
public struct GpuiSurfaceHandle: @unchecked Sendable {
    public var id: SurfaceId
    public var nativeViewPtr: UnsafeMutableRawPointer?

    public init(id: SurfaceId, nativeViewPtr: UnsafeMutableRawPointer? = nil) {
        self.id = id
        self.nativeViewPtr = nativeViewPtr
    }
}

// MARK: - DispatchPhase

/// Represents the two different phases when dispatching events.
public enum DispatchPhase: Sendable, Equatable, CaseIterable {
    /// After the capture phase comes the bubble phase.
    case bubble
    /// During the initial capture phase, listeners are invoked top-down.
    case capture

    public var bubble: Bool { self == .bubble }
    public var capture: Bool { self == .capture }
}

// MARK: - DrawPhase

/// Phases of the frame drawing cycle.
public enum DrawPhase: Sendable, Equatable {
    case none
    case requestLayout
    case prepaint
    case paint
}

// MARK: - Window Invalidator

struct WindowInvalidatorInner {
    var dirty: Bool
    var drawPhase: DrawPhase
    var dirtyViews: Set<EntityId>
}

/// Manages dirty state and phase transitions for a window.
public final class WindowInvalidator: @unchecked Sendable {
    private let lock = NSLock()
    private var inner: WindowInvalidatorInner

    public init() {
        self.inner = WindowInvalidatorInner(
            dirty: true,
            drawPhase: .none,
            dirtyViews: []
        )
    }

    @MainActor
    @discardableResult
    public func invalidateView(_ entity: EntityId, _ cx: inout App) -> Bool {
        lock.lock()
        inner.dirtyViews.insert(entity)
        if inner.drawPhase == .none {
            inner.dirty = true
            lock.unlock()
            cx.notify(entity)
            return true
        } else {
            lock.unlock()
            return false
        }
    }

    public var isDirty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inner.dirty
    }

    public func setDirty(_ dirty: Bool) {
        lock.lock()
        defer { lock.unlock() }
        inner.dirty = dirty
    }

    public var drawPhase: DrawPhase {
        lock.lock()
        defer { lock.unlock() }
        return inner.drawPhase
    }

    public func setPhase(_ phase: DrawPhase) {
        lock.lock()
        defer { lock.unlock() }
        inner.drawPhase = phase
    }

    public func takeViews() -> Set<EntityId> {
        lock.lock()
        defer { lock.unlock() }
        let views = inner.dirtyViews
        inner.dirtyViews.removeAll()
        return views
    }

    public func replaceViews(_ views: Set<EntityId>) {
        lock.lock()
        defer { lock.unlock() }
        inner.dirtyViews = views
    }

    public var notDrawing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return inner.drawPhase == .none
    }

    public func debugAssertPaint() {
        assert(drawPhase == .paint, "Expected paint phase")
    }

    public func debugAssertPrepaint() {
        assert(drawPhase == .prepaint, "Expected prepaint phase")
    }

    public func debugAssertPaintOrPrepaint() {
        assert(drawPhase == .paint || drawPhase == .prepaint, "Expected paint or prepaint phase")
    }
}

// MARK: - Surface State & Arena Scope

/// Ephemeral state associated with a window surface.
public struct SurfaceState: Sendable, Equatable {
    public var id: SurfaceId
    public var scaleFactor: Float
    public var bounds: Bounds<Pixels>

    public init(id: SurfaceId, scaleFactor: Float, bounds: Bounds<Pixels>) {
        self.id = id
        self.scaleFactor = scaleFactor
        self.bounds = bounds
    }
}

/// Scope managing element arena memory allocations during layout and drawing.
public struct ElementArenaScope: Sendable {
    public static func enter() -> ElementArenaScope {
        ElementArenaScope()
    }
}

/// Executes a closure within an active element arena scope.
public func withElementArena<R>(_ f: () -> R) -> R {
    _ = ElementArenaScope.enter()
    return f()
}

/// An identifier for an element within a window tree.
public struct ElementId: Sendable, Equatable, Hashable {
    public var rawValue: UInt64

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

/// A globally qualified element identifier.
public struct GlobalElementId: Sendable, Equatable, Hashable {
    public var path: [ElementId]

    public init(_ path: [ElementId]) {
        self.path = path
    }

    public init(_ id: ElementId) {
        self.path = [id]
    }
}


// MARK: - Focus Management

/// A globally unique identifier for a focusable element.
@frozen
public struct FocusId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public func isFocused(_ window: Window) -> Bool {
        window.focus == self
    }

    public func containsFocused(_ window: Window, _ cx: App) -> Bool {
        guard let focused = window.focused(cx) else { return false }
        return contains(focused.id, window)
    }

    public func withinFocused(_ window: Window, _ cx: App) -> Bool {
        guard let focused = window.focused(cx) else { return false }
        return focused.id.contains(self, window)
    }

    public func contains(_ other: FocusId, _ window: Window) -> Bool {
        window.renderedFrame.dispatchTree.focusContains(parent: self, child: other)
    }
}

final class FocusRef: @unchecked Sendable {
    var refCount: Int
    var tabIndex: Int
    var tabStop: Bool

    init(refCount: Int = 1, tabIndex: Int = 0, tabStop: Bool = false) {
        self.refCount = refCount
        self.tabIndex = tabIndex
        self.tabStop = tabStop
    }
}

/// A thread-safe map of active focus handles.
public final class FocusMap: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [FocusId: FocusRef] = [:]
    private var nextId: UInt64 = 1

    public init() {}

    func insert(tabIndex: Int = 0, tabStop: Bool = false) -> FocusId {
        lock.lock()
        defer { lock.unlock() }
        let id = FocusId(nextId)
        nextId += 1
        slots[id] = FocusRef(refCount: 1, tabIndex: tabIndex, tabStop: tabStop)
        return id
    }

    func get(_ id: FocusId) -> FocusRef? {
        lock.lock()
        defer { lock.unlock() }
        return slots[id]
    }

    func retain(_ id: FocusId) -> FocusRef? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = slots[id], entry.refCount > 0 else { return nil }
        entry.refCount += 1
        return entry
    }

    func release(_ id: FocusId) {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = slots[id] else { return }
        entry.refCount -= 1
        if entry.refCount <= 0 {
            slots.removeValue(forKey: id)
        }
    }

    func updateTabIndex(_ id: FocusId, _ index: Int) {
        lock.lock()
        defer { lock.unlock() }
        slots[id]?.tabIndex = index
    }

    func updateTabStop(_ id: FocusId, _ tabStop: Bool) {
        lock.lock()
        defer { lock.unlock() }
        slots[id]?.tabStop = tabStop
    }
}

private final class FocusToken: @unchecked Sendable {
    let id: FocusId
    let handles: FocusMap

    init(id: FocusId, handles: FocusMap) {
        self.id = id
        self.handles = handles
    }

    deinit {
        handles.release(id)
    }
}

/// A handle used to track and manipulate the focused element in a window.
public struct FocusHandle: @unchecked Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    public let id: FocusId
    let handles: FocusMap
    public var tabIndex: Int
    public var tabStop: Bool
    private let token: FocusToken

    public var debugDescription: String {
        "FocusHandle(\(id.rawValue))"
    }

    public init(handles: FocusMap) {
        let id = handles.insert()
        self.id = id
        self.handles = handles
        self.tabIndex = 0
        self.tabStop = false
        self.token = FocusToken(id: id, handles: handles)
    }

    public static func forId(_ id: FocusId, handles: FocusMap) -> FocusHandle? {
        guard let ref = handles.retain(id) else { return nil }
        return FocusHandle(
            id: id,
            handles: handles,
            tabIndex: ref.tabIndex,
            tabStop: ref.tabStop,
            token: FocusToken(id: id, handles: handles)
        )
    }

    private init(id: FocusId, handles: FocusMap, tabIndex: Int, tabStop: Bool, token: FocusToken) {
        self.id = id
        self.handles = handles
        self.tabIndex = tabIndex
        self.tabStop = tabStop
        self.token = token
    }

    public func tabIndex(_ index: Int) -> Self {
        var copy = self
        copy.tabIndex = index
        handles.updateTabIndex(id, index)
        return copy
    }

    public func tabStop(_ tabStop: Bool) -> Self {
        var copy = self
        copy.tabStop = tabStop
        handles.updateTabStop(id, tabStop)
        return copy
    }

    public func downgrade() -> WeakFocusHandle {
        WeakFocusHandle(id: id, handles: handles)
    }

    public func isFocused(_ window: Window) -> Bool {
        id.isFocused(window)
    }

    public func containsFocused(_ window: Window, _ cx: App) -> Bool {
        id.containsFocused(window, cx)
    }

    public func withinFocused(_ window: Window, _ cx: App) -> Bool {
        id.withinFocused(window, cx)
    }

    public func contains(_ other: FocusHandle, _ window: Window) -> Bool {
        id.contains(other.id, window)
    }

    public static func == (lhs: FocusHandle, rhs: FocusHandle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A weak reference to a focus handle that does not keep it alive.
public struct WeakFocusHandle: @unchecked Sendable, Equatable, Hashable {
    public let id: FocusId
    weak var handles: FocusMap?

    public init(id: FocusId, handles: FocusMap) {
        self.id = id
        self.handles = handles
    }

    public func upgrade() -> FocusHandle? {
        guard let handles else { return nil }
        return FocusHandle.forId(id, handles: handles)
    }

    public static func == (lhs: WeakFocusHandle, rhs: WeakFocusHandle) -> Bool {
        lhs.id == rhs.id
    }

    public static func == (lhs: WeakFocusHandle, rhs: FocusHandle) -> Bool {
        lhs.id == rhs.id
    }

    public static func == (lhs: FocusHandle, rhs: WeakFocusHandle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Event delivered when focus transitions between elements.
public struct WindowFocusEvent: Sendable {
    public var previousFocusPath: [FocusId]
    public var currentFocusPath: [FocusId]

    public init(previousFocusPath: [FocusId] = [], currentFocusPath: [FocusId] = []) {
        self.previousFocusPath = previousFocusPath
        self.currentFocusPath = currentFocusPath
    }

    public func isFocusIn(_ focusId: FocusId) -> Bool {
        !previousFocusPath.contains(focusId) && currentFocusPath.contains(focusId)
    }

    public func isFocusOut(_ focusId: FocusId) -> Bool {
        previousFocusPath.contains(focusId) && !currentFocusPath.contains(focusId)
    }
}

/// Event delivered when an element loses focus.
public struct FocusOutEvent: Sendable {
    public var blurred: WeakFocusHandle

    public init(blurred: WeakFocusHandle) {
        self.blurred = blurred
    }
}

// MARK: - Hitboxes & Hit Testing

/// A globally unique identifier for a hitbox.
@frozen
public struct HitboxId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public func isHovered(_ window: Window) -> Bool {
        window.mouseHitTest.ids.prefix(window.mouseHitTest.hoverHitboxCount).contains(self)
    }
}

/// Hitbox mouse interception behavior.
public enum HitboxBehavior: Sendable, Equatable {
    case normal
    case blockMouse
    case blockMouseExceptScroll
}

/// An interactive region that can receive mouse events.
public struct Hitbox: Sendable, Equatable {
    public var id: HitboxId
    public var bounds: Bounds<Pixels>
    public var contentMask: ContentMask<Pixels>
    public var behavior: HitboxBehavior

    public init(
        id: HitboxId,
        bounds: Bounds<Pixels>,
        contentMask: ContentMask<Pixels> = ContentMask(bounds: .zero),
        behavior: HitboxBehavior = .normal
    ) {
        self.id = id
        self.bounds = bounds
        self.contentMask = contentMask
        self.behavior = behavior
    }
}

/// The result of hit-testing a point against a set of hitboxes.
public struct HitTest: Sendable, Equatable {
    public var ids: [HitboxId]
    public var hoverHitboxCount: Int

    public init(ids: [HitboxId] = [], hoverHitboxCount: Int = 0) {
        self.ids = ids
        self.hoverHitboxCount = hoverHitboxCount
    }
}

// MARK: - Deferred Draw

/// Priority for ordering deferred draws.
public struct Priority: Sendable, Equatable, Comparable {
    public var rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A deferred draw operation executed after primary element layout and paint.
public struct DeferredDraw: Sendable {
    public var priority: Priority
    public var draw: @Sendable (inout Window, inout App) -> Void

    public init(
        priority: Priority = Priority(0),
        draw: @escaping @Sendable (inout Window, inout App) -> Void
    ) {
        self.priority = priority
        self.draw = draw
    }
}

// MARK: - Dispatch Event Result

/// The outcome of dispatching an input event to the window.
public struct DispatchEventResult: Sendable, Equatable {
    public var propagate: Bool
    public var defaultPrevented: Bool

    public init(propagate: Bool = true, defaultPrevented: Bool = false) {
        self.propagate = propagate
        self.defaultPrevented = defaultPrevented
    }
}

// MARK: - Frame Model

/// Bundles the ephemeral visual and interactive state of a single frame.
public struct Frame: @unchecked Sendable {
    public var focus: FocusId?
    public var windowActive: Bool
    public var dispatchTree: DispatchTree
    public var scene: Scene
    public var hitboxes: [Hitbox]
    public var deferredDraws: [DeferredDraw]
    public var tabStops: TabStopMap

    public init(dispatchTree: DispatchTree = DispatchTree()) {
        self.focus = nil
        self.windowActive = false
        self.dispatchTree = dispatchTree
        self.scene = Scene()
        self.hitboxes = []
        self.deferredDraws = []
        self.tabStops = TabStopMap()
    }

    public mutating func clear() {
        focus = nil
        windowActive = false
        dispatchTree.clear()
        scene.clear()
        hitboxes.removeAll()
        deferredDraws.removeAll()
        tabStops.clear()
    }

    public func hitTest(_ position: Point<Pixels>) -> HitTest {
        var setHoverHitboxCount = false
        var hitTest = HitTest()
        for hitbox in hitboxes.reversed() {
            let bounds = hitbox.bounds.intersect(hitbox.contentMask.bounds)
            if bounds.contains(position) {
                hitTest.ids.append(hitbox.id)
                if !setHoverHitboxCount && hitbox.behavior == .blockMouseExceptScroll {
                    hitTest.hoverHitboxCount = hitTest.ids.count
                    setHoverHitboxCount = true
                }
                if hitbox.behavior == .blockMouse {
                    break
                }
            }
        }
        if !setHoverHitboxCount {
            hitTest.hoverHitboxCount = hitTest.ids.count
        }
        return hitTest
    }

    public func focusPath() -> [FocusId] {
        guard let focus else { return [] }
        return dispatchTree.focusPath(focus)
    }

    public mutating func finish(prevFrame: inout Frame) {
        scene.finish()
    }
}

// MARK: - Window Options & Configuration

/// Window geometry configuration.
public enum WindowBounds: Sendable, Equatable {
    case windowed(Bounds<Pixels>)
    case maximized(Bounds<Pixels>)
    case fullscreen(Bounds<Pixels>)

    public var bounds: Bounds<Pixels> {
        switch self {
        case .windowed(let b), .maximized(let b), .fullscreen(let b):
            return b
        }
    }
}

/// Background material for the window.
public enum WindowBackgroundAppearance: Sendable, Equatable {
    case opaque
    case transparent
    case blurred
}

/// Window classification.
public enum WindowKind: Sendable, Equatable {
    case normal
    case popUpMenu
    case modal
}

/// Configuration options for the window's title bar.
public struct TitlebarOptions: Sendable, Equatable {
    public var title: String?
    public var appearsTransparent: Bool
    public var trafficLightPosition: Point<Pixels>?

    public init(
        title: String? = nil,
        appearsTransparent: Bool = false,
        trafficLightPosition: Point<Pixels>? = nil
    ) {
        self.title = title
        self.appearsTransparent = appearsTransparent
        self.trafficLightPosition = trafficLightPosition
    }
}

/// Identifier for a display monitor.
public struct DisplayId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

/// Specification used when opening a new window.
public struct WindowOptions: Sendable {
    public var windowBounds: WindowBounds?
    public var titlebar: TitlebarOptions?
    public var focus: Bool
    public var show: Bool
    public var kind: WindowKind
    public var isMovable: Bool
    public var displayId: DisplayId?
    public var windowMinSize: Size<Pixels>?
    public var windowBackground: WindowBackgroundAppearance

    public init(
        windowBounds: WindowBounds? = nil,
        titlebar: TitlebarOptions? = nil,
        focus: Bool = true,
        show: Bool = true,
        kind: WindowKind = .normal,
        isMovable: Bool = true,
        displayId: DisplayId? = nil,
        windowMinSize: Size<Pixels>? = nil,
        windowBackground: WindowBackgroundAppearance = .opaque
    ) {
        self.windowBounds = windowBounds
        self.titlebar = titlebar
        self.focus = focus
        self.show = show
        self.kind = kind
        self.isMovable = isMovable
        self.displayId = displayId
        self.windowMinSize = windowMinSize
        self.windowBackground = windowBackground
    }
}

// MARK: - Window Handles

/// Type-erased handle to a window instance.
public struct AnyWindowHandle: Sendable, Equatable, Hashable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }
}

/// Strongly-typed window handle associated with a specific root view type.
public struct WindowHandle<V>: Sendable, Equatable, Hashable {
    public let anyHandle: AnyWindowHandle

    public init(anyHandle: AnyWindowHandle) {
        self.anyHandle = anyHandle
    }
}

// MARK: - PlatformWindow Protocol

/// Platform abstraction for native window operations.
public protocol PlatformWindow: AnyObject, Sendable {
    func bounds() -> Bounds<Pixels>
    func contentSize() -> Size<Pixels>
    func scaleFactor() -> Float
    func appearance() -> WindowAppearance
    func mousePosition() -> Point<Pixels>
    func modifiers() -> Modifiers
    func capslock() -> Capslock
    func activate()
    func isMaximized() -> Bool
    func isActive() -> Bool
    func isHovered() -> Bool
    func isFullscreen() -> Bool
    func minimize()
    func zoom()
    func toggleFullScreen()
    func draw(scene: Scene)
}

/// Default mock platform window for headless test execution.
public final class DefaultPlatformWindow: PlatformWindow, @unchecked Sendable {
    public var windowBounds: Bounds<Pixels>
    public var windowScaleFactor: Float
    public var windowAppearance: WindowAppearance
    public var lastDrawnScene: Scene?
    public var isMinimizedState: Bool = false
    public var isZoomedState: Bool = false
    public var isFullScreenState: Bool = false

    public init(
        bounds: Bounds<Pixels> = Bounds(origin: .zero, size: size(px(800), px(600))),
        scaleFactor: Float = 1.0,
        appearance: WindowAppearance = .dark
    ) {
        self.windowBounds = bounds
        self.windowScaleFactor = scaleFactor
        self.windowAppearance = appearance
    }

    public func bounds() -> Bounds<Pixels> { windowBounds }
    public func contentSize() -> Size<Pixels> { windowBounds.size }
    public func scaleFactor() -> Float { windowScaleFactor }
    public func appearance() -> WindowAppearance { windowAppearance }
    public func mousePosition() -> Point<Pixels> { .zero }
    public func modifiers() -> Modifiers { Modifiers.none() }
    public func capslock() -> Capslock { Capslock() }
    public func activate() {}
    public func isMaximized() -> Bool { isZoomedState }
    public func isActive() -> Bool { true }
    public func isHovered() -> Bool { true }
    public func isFullscreen() -> Bool { isFullScreenState }
    public func minimize() { isMinimizedState = true }
    public func zoom() { isZoomedState.toggle() }
    public func toggleFullScreen() { isFullScreenState.toggle() }
    public func draw(scene: Scene) {
        self.lastDrawnScene = scene
    }
}

// MARK: - View & Element Forward Declarations

/// Type-erased view handle.
public struct AnyView: Sendable, Equatable, Hashable {
    public var entityId: EntityId

    public init(entityId: EntityId) {
        self.entityId = entityId
    }

    public static func == (lhs: AnyView, rhs: AnyView) -> Bool {
        lhs.entityId == rhs.entityId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(entityId)
    }
}

// MARK: - Window

/// Holds the complete state and manages the lifecycle, rendering pipeline,
/// and event dispatch for a single visual surface.
// PORT NOTE: Window is MainActor isolated in application usage and contains internal closures/caches
public struct Window: @unchecked Sendable {
    public var handle: AnyWindowHandle
    public var invalidator: WindowInvalidator
    public var platformWindow: any PlatformWindow
    public var scaleFactor: Float
    public var viewportSize: Size<Pixels>
    public var remSize: Pixels

    public var layoutEngine: TaffyLayoutEngine?
    public var root: AnyView?

    public var renderedFrame: Frame
    public var nextFrame: Frame

    public var mousePosition: Point<Pixels>
    public var mouseHitTest: HitTest
    public var modifiers: Modifiers
    public var capslock: Capslock

    public var focus: FocusId?
    public var focusMap: FocusMap

    public var contentMaskStack: [ContentMask<Pixels>]
    public var elementOffsetStack: [Point<Pixels>]
    public var elementOpacity: Float

    private var nextHitboxIdValue: UInt64 = 1
    public var dirtyViews: Set<EntityId>

    public var elementStates: [GlobalElementId: Any]
    public var mouseCursor: CursorStyle?
    public var autoscrollRequest: Bounds<Pixels>?
    public var nextFrameCallbacks: [@MainActor (inout Window, inout App) -> Void]
    public var appearanceObservers: [(WindowAppearance) -> Void]
    public var buttonLayoutChangedObservers: [() -> Void]
    public var clientInsetVal: Pixels
    public var windowTitle: String
    public var backgroundColor: Hsla?
    public var backgroundAppearance: WindowBackgroundAppearance

    public init(
        handle: AnyWindowHandle = AnyWindowHandle(id: 1),
        platformWindow: any PlatformWindow = DefaultPlatformWindow(),
        scaleFactor: Float = 1.0,
        viewportSize: Size<Pixels> = size(px(800.0), px(600.0)),
        remSize: Pixels = px(16.0)
    ) {
        self.handle = handle
        self.invalidator = WindowInvalidator()
        self.platformWindow = platformWindow
        self.scaleFactor = scaleFactor
        self.viewportSize = viewportSize
        self.remSize = remSize
        self.layoutEngine = TaffyLayoutEngine()
        self.root = nil
        self.renderedFrame = Frame()
        self.nextFrame = Frame()
        self.mousePosition = .zero
        self.mouseHitTest = HitTest()
        self.modifiers = Modifiers.none()
        self.capslock = Capslock()
        self.focus = nil
        self.focusMap = FocusMap()
        self.contentMaskStack = [ContentMask(bounds: Bounds(origin: .zero, size: viewportSize))]
        self.elementOffsetStack = [.zero]
        self.elementOpacity = 1.0
        self.dirtyViews = []
        self.elementStates = [:]
        self.mouseCursor = nil
        self.autoscrollRequest = nil
        self.nextFrameCallbacks = []
        self.appearanceObservers = []
        self.buttonLayoutChangedObservers = []
        self.clientInsetVal = .zero
        self.windowTitle = ""
        self.backgroundColor = nil
        self.backgroundAppearance = .opaque
    }

    // MARK: - Focus Operations

    public mutating func focus(_ handle: FocusHandle, _ cx: inout App) {
        let previousPath = renderedFrame.focusPath()
        self.focus = handle.id
        nextFrame.focus = handle.id
        let currentPath = nextFrame.focusPath()
        _ = WindowFocusEvent(previousFocusPath: previousPath, currentFocusPath: currentPath)
    }

    public func focused(_ cx: App) -> FocusHandle? {
        guard let focus else { return nil }
        return FocusHandle.forId(focus, handles: focusMap)
    }

    public func isFocused(_ handle: FocusHandle) -> Bool {
        focus == handle.id
    }

    public func focusHandle() -> FocusHandle {
        FocusHandle(handles: focusMap)
    }

    public mutating func blur(_ cx: inout App) {
        let previousPath = renderedFrame.focusPath()
        let blurredHandle = focused(cx)
        self.focus = nil
        nextFrame.focus = nil
        if let blurredHandle = blurredHandle {
            _ = FocusOutEvent(blurred: blurredHandle.downgrade())
        }
        _ = WindowFocusEvent(previousFocusPath: previousPath, currentFocusPath: [])
    }

    public mutating func disableFocus() {
        self.focus = nil
        nextFrame.focus = nil
    }

    public mutating func focusNext(_ cx: inout App) {
        let current = focused(cx)
        if let nextHandle = renderedFrame.tabStops.next(current?.id) {
            focus(nextHandle, &cx)
        }
    }

    public mutating func focusPrev(_ cx: inout App) {
        let current = focused(cx)
        if let prevHandle = renderedFrame.tabStops.prev(current?.id) {
            focus(prevHandle, &cx)
        }
    }

    // MARK: - Hitboxes

    public mutating func insertHitbox(
        bounds: Bounds<Pixels>,
        behavior: HitboxBehavior = .normal
    ) -> HitboxId {
        let id = HitboxId(nextHitboxIdValue)
        nextHitboxIdValue += 1
        let mask = contentMaskStack.last ?? ContentMask(bounds: .zero)
        let hitbox = Hitbox(id: id, bounds: bounds, contentMask: mask, behavior: behavior)
        nextFrame.hitboxes.append(hitbox)
        return id
    }

    public mutating func insertWindowControlHitbox(
        bounds: Bounds<Pixels>,
        behavior: HitboxBehavior = .normal
    ) -> HitboxId {
        insertHitbox(bounds: bounds, behavior: behavior)
    }

    // MARK: - Mouse Cursor

    public mutating func setMouseCursor(_ cursor: CursorStyle) {
        self.mouseCursor = cursor
    }

    public func effectiveMouseCursor() -> CursorStyle {
        mouseCursor ?? .arrow
    }

    // MARK: - Element States

    public mutating func withElementState<State, R>(
        _ id: GlobalElementId,
        _ f: (inout State?) -> R
    ) -> R {
        var state = elementStates[id] as? State
        let result = f(&state)
        if let state = state {
            elementStates[id] = state
        } else {
            elementStates.removeValue(forKey: id)
        }
        return result
    }

    public mutating func useState<State>(
        _ id: GlobalElementId,
        _ initial: () -> State
    ) -> State {
        if let state = elementStates[id] as? State {
            return state
        }
        let state = initial()
        elementStates[id] = state
        return state
    }

    // MARK: - Layout Integration

    public mutating func requestLayout(
        style: Style,
        children: [LayoutId] = []
    ) -> LayoutId {
        if layoutEngine == nil {
            layoutEngine = TaffyLayoutEngine()
        }
        return layoutEngine!.requestLayout(
            style: style,
            remSize: remSize,
            scaleFactor: scaleFactor,
            children: children
        )
    }

    public mutating func requestMeasuredLayout(
        style: Style,
        measure: @escaping LayoutMeasureFn
    ) -> LayoutId {
        if layoutEngine == nil {
            layoutEngine = TaffyLayoutEngine()
        }
        return layoutEngine!.requestMeasuredLayout(
            style: style,
            remSize: remSize,
            scaleFactor: scaleFactor,
            measure: measure
        )
    }

    public mutating func computeLayout(id: LayoutId, availableSpace: Size<AvailableSpace>, cx: inout App) {
        var engine = layoutEngine ?? TaffyLayoutEngine()
        engine.computeLayout(id: id, availableSpace: availableSpace, window: &self, cx: &cx)
        self.layoutEngine = engine
    }

    public mutating func layoutBounds(id: LayoutId) -> Bounds<Pixels> {
        layoutEngine?.layoutBounds(id: id, scaleFactor: scaleFactor) ?? .zero
    }

    // MARK: - Scene Painting Helpers

    public mutating func paintQuad(_ quad: Quad) {
        nextFrame.scene.insertQuad(quad)
    }

    public mutating func paintShadow(_ shadow: Shadow) {
        nextFrame.scene.insertShadow(shadow)
    }

    public mutating func paintPath(_ path: Path<Pixels>) {
        nextFrame.scene.insertPath(path.scale(scaleFactor))
    }

    public mutating func paintUnderline(_ underline: Underline) {
        nextFrame.scene.insertUnderline(underline)
    }

    public mutating func paintMonochromeSprite(_ sprite: MonochromeSprite) {
        nextFrame.scene.insertMonochromeSprite(sprite)
    }

    public mutating func paintPolychromeSprite(_ sprite: PolychromeSprite) {
        nextFrame.scene.insertPolychromeSprite(sprite)
    }

    public mutating func paintSubpixelSprite(_ sprite: SubpixelSprite) {
        nextFrame.scene.insertSubpixelSprite(sprite)
    }

    public mutating func paintStrikethrough(_ strikethrough: Underline) {
        nextFrame.scene.insertUnderline(strikethrough)
    }

    public mutating func paintSurface(_ surface: PaintSurface) {
        nextFrame.scene.insertSurface(surface)
    }

    // MARK: - Stacks & Scoping

    public mutating func withContentMask<R>(
        _ mask: ContentMask<Pixels>,
        _ f: (inout Window) -> R
    ) -> R {
        let parentMask = contentMaskStack.last ?? ContentMask(bounds: .zero)
        let combined = parentMask.intersect(mask)
        contentMaskStack.append(combined)
        defer { contentMaskStack.removeLast() }
        return f(&self)
    }

    public mutating func withElementOffset<R>(
        _ offset: Point<Pixels>,
        _ f: (inout Window) -> R
    ) -> R {
        let current = elementOffsetStack.last ?? .zero
        let accumulated = current + offset
        elementOffsetStack.append(accumulated)
        defer { elementOffsetStack.removeLast() }
        return f(&self)
    }

    public mutating func withOpacity<R>(
        _ opacity: Float,
        _ f: (inout Window) -> R
    ) -> R {
        let prev = elementOpacity
        elementOpacity *= opacity
        defer { elementOpacity = prev }
        return f(&self)
    }

    public mutating func deferDraw(
        priority: Priority = Priority(0),
        _ draw: @escaping @Sendable (inout Window, inout App) -> Void
    ) {
        nextFrame.deferredDraws.append(DeferredDraw(priority: priority, draw: draw))
    }

    // MARK: - 7-Stage Draw Pipeline

    /// Orchestrates the entire frame generation cycle:
    /// 1. Enter element arena scope.
    /// 2. Invalidate dirty entities.
    /// 3. Prepaint root element & deferred draws.
    /// 4. Evaluate mouse hit-test.
    /// 5. Paint root element and deferred draws.
    /// 6. Clear layout engine.
    /// 7. Swap `next_frame` into `rendered_frame` and present scene to `platform_window.draw()`.
    @MainActor
    public mutating func draw(cx: inout App) {
        withElementArena {
            // Stage 1 & 2: Entity Invalidation & Setup
            dirtyViews.formUnion(invalidator.takeViews())

            // Drain next-frame callbacks
            let callbacks = nextFrameCallbacks
            nextFrameCallbacks.removeAll()
            for cb in callbacks {
                cb(&self, &cx)
            }

            // Stage 3: Prepaint Phase
            invalidator.setPhase(.prepaint)
            nextFrame.windowActive = platformWindow.isActive()

            // Execute any deferred layout/prepaint passes
            let deferred = nextFrame.deferredDraws.sorted { $0.priority < $1.priority }
            for item in deferred {
                item.draw(&self, &cx)
            }

            // Stage 4: Evaluate Mouse Hit-Test
            mouseHitTest = nextFrame.hitTest(mousePosition)

            // Stage 5: Paint Phase
            invalidator.setPhase(.paint)

            // Stage 6: Finalize Layout & Text
            layoutEngine?.clear()

            // Stage 7: Frame Promotion, Presentation & Cleanup
            nextFrame.finish(prevFrame: &renderedFrame)
            swap(&renderedFrame, &nextFrame)
            nextFrame.clear()

            invalidator.setPhase(.none)
            invalidator.setDirty(false)

            // Present completed scene to display backend
            platformWindow.draw(scene: renderedFrame.scene)
        }
    }

    // MARK: - Next-Frame Callbacks & Autoscroll

    public mutating func onNextFrame(_ callback: @escaping @MainActor (inout Window, inout App) -> Void) {
        nextFrameCallbacks.append(callback)
    }

    public mutating func requestAnimationFrame() {
        invalidator.setDirty(true)
    }

    public mutating func requestAutoscroll(_ bounds: Bounds<Pixels>) {
        self.autoscrollRequest = bounds
    }

    public mutating func takeAutoscroll() -> Bounds<Pixels>? {
        let req = autoscrollRequest
        autoscrollRequest = nil
        return req
    }

    // MARK: - Observers & Notifications

    public mutating func observeWindowAppearance(_ observer: @escaping (WindowAppearance) -> Void) {
        appearanceObservers.append(observer)
    }

    public mutating func observeButtonLayoutChanged(_ observer: @escaping () -> Void) {
        buttonLayoutChangedObservers.append(observer)
    }

    public mutating func appearanceChanged(_ appearance: WindowAppearance) {
        for observer in appearanceObservers {
            observer(appearance)
        }
        invalidator.setDirty(true)
    }

    public mutating func buttonLayoutChanged() {
        for observer in buttonLayoutChangedObservers {
            observer()
        }
        invalidator.setDirty(true)
    }

    // MARK: - Window Lifecycle & Platform Properties

    public mutating func replaceRoot(_ newRoot: AnyView) {
        self.root = newRoot
        invalidator.setDirty(true)
    }

    public func windowHandle() -> AnyWindowHandle {
        handle
    }

    public mutating func refresh() {
        invalidator.setDirty(true)
    }

    public mutating func removeWindow(_ cx: inout App) {
        // PORT NOTE: App-level window registry removal is connected in Batch 3.4.
        invalidator.setDirty(false)
    }

    public func isMaximized() -> Bool {
        platformWindow.isMaximized()
    }

    public func isFullscreen() -> Bool {
        platformWindow.isFullscreen()
    }

    public func bounds() -> Bounds<Pixels> {
        platformWindow.bounds()
    }

    public func windowBounds() -> WindowBounds {
        .windowed(platformWindow.bounds())
    }

    public func innerWindowBounds() -> Bounds<Pixels> {
        Bounds(origin: .zero, size: viewportSize)
    }

    public mutating func resize(_ newSize: Size<Pixels>) {
        self.viewportSize = newSize
        if !contentMaskStack.isEmpty {
            contentMaskStack[0] = ContentMask(bounds: Bounds(origin: .zero, size: newSize))
        }
        invalidator.setDirty(true)
    }

    public func appearance() -> WindowAppearance {
        platformWindow.appearance()
    }

    public func titlebarHeight() -> Pixels {
        px(32.0)
    }

    public func windowControlsPadding() -> Pixels {
        px(8.0)
    }

    public func mousePositionInWindow() -> Point<Pixels> {
        mousePosition
    }

    public func isWindowActive() -> Bool {
        platformWindow.isActive()
    }

    public func isWindowHovered() -> Bool {
        platformWindow.isHovered()
    }

    public mutating func activateWindow() {
        platformWindow.activate()
    }

    public mutating func zoomWindow() {
        platformWindow.zoom()
    }

    public mutating func minimizeWindow() {
        platformWindow.minimize()
    }

    public mutating func toggleFullscreen() {
        platformWindow.toggleFullScreen()
    }

    public mutating func setWindowTitle(_ title: String) {
        self.windowTitle = title
    }

    public func clientInset() -> Pixels {
        clientInsetVal
    }

    public mutating func setClientInset(_ inset: Pixels) {
        self.clientInsetVal = inset
        invalidator.setDirty(true)
    }

    public mutating func setBackgroundAppearance(_ appearance: WindowBackgroundAppearance) {
        self.backgroundAppearance = appearance
        invalidator.setDirty(true)
    }

    public mutating func setBackgroundColor(_ color: Hsla) {
        self.backgroundColor = color
        invalidator.setDirty(true)
    }

    // MARK: - Event Dispatch

    /// Routes platform input across mouse hitboxes and walks `DispatchTree` for keyboard events and actions.
    @discardableResult
    public mutating func dispatchEvent(
        event: PlatformInput,
        cx: inout App
    ) -> DispatchEventResult {
        switch event {
        case .mouseMove(let move):
            mousePosition = move.position
            modifiers = move.modifiers
            mouseHitTest = renderedFrame.hitTest(mousePosition)
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .mouseDown(let down):
            mousePosition = down.position
            modifiers = down.modifiers
            mouseHitTest = renderedFrame.hitTest(mousePosition)
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .mouseUp(let up):
            mousePosition = up.position
            modifiers = up.modifiers
            mouseHitTest = renderedFrame.hitTest(mousePosition)
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .mousePressure(let pressure):
            mousePosition = pressure.position
            modifiers = pressure.modifiers
            mouseHitTest = renderedFrame.hitTest(mousePosition)
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .mouseExited:
            mousePosition = Point(x: px(-1.0), y: px(-1.0))
            mouseHitTest = HitTest()
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .scrollWheel(let scroll):
            mousePosition = scroll.position
            modifiers = scroll.modifiers
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .pinch:
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .rotation:
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .fileDrop:
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .keyDown(let key):
            modifiers = key.keystroke.modifiers
            if let focus, let nodeId = renderedFrame.dispatchTree.focusableNodeId(focus) {
                let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
                _ = renderedFrame.dispatchTree.dispatchKey([], key.keystroke, path)
            }
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .keyUp(let key):
            modifiers = key.keystroke.modifiers
            return DispatchEventResult(propagate: true, defaultPrevented: false)

        case .modifiersChanged(let mod):
            modifiers = mod.modifiers
            capslock = mod.capslock
            return DispatchEventResult(propagate: true, defaultPrevented: false)
        }
    }

    public mutating func dispatchActionOnNode(
        _ nodeId: DispatchNodeId,
        _ action: any Action,
        _ cx: inout App
    ) {
        let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
        let actionId = ObjectIdentifier(type(of: action))
        for id in path.reversed() {
            let node = renderedFrame.dispatchTree.node(id)
            for listener in node.actionListeners {
                if listener.actionType == actionId {
                    listener.listener(action, .bubble, &self, &cx)
                    return
                }
            }
        }
    }
}
