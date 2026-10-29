// Ported from: crates/gpui/src/window.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

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
    // PORT NOTE: Synchronized via NSLock matching upstream AtomicU32 surface ID generator.
    nonisolated(unsafe) private static var counter: UInt32 = 0

    public static func next() -> SurfaceId {
        nextId.lock()
        defer { nextId.unlock() }
        let id = counter
        counter += 1
        return SurfaceId(id)
    }

    public static func new(_ rawValue: UInt32) -> SurfaceId {
        SurfaceId(rawValue)
    }
}

/// A handle returned when registering a surface, providing the native view pointer.
// PORT NOTE: Wraps raw OS native view pointer across threads matching upstream GpuiSurfaceHandle.
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
// PORT NOTE: Synchronized via NSLock matching upstream RefCell/RwLock invalidator safety invariants.
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

    public static func new() -> WindowInvalidator {
        WindowInvalidator()
    }
}

// MARK: - Element Arena & Focus Listener Types

// PORT NOTE: In upstream GPUI, ArenaClearNeeded holds a raw pointer to RefCell<Arena>
// which is reset between frames. In Swift, element lifetimes are managed by ARC,
// but ArenaClearNeeded tracks frame allocation scope and invalidation requirements.
public struct ArenaClearNeeded: Sendable {
    public var needsClear: Bool

    public init(needsClear: Bool = true) {
        self.needsClear = needsClear
    }

    public static func new(needsClear: Bool = true) -> ArenaClearNeeded {
        ArenaClearNeeded(needsClear: needsClear)
    }

    public mutating func clear() {
        needsClear = false
    }
}

public typealias AnyWindowFocusListener = @Sendable (WindowFocusEvent, inout Window, inout App) -> Bool

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

// PORT NOTE: In Rust GPUI, ELEMENT_ARENA is a typed_arena::Arena used to pool element allocations.
// In Swift, element lifetimes are managed by ARC with ElementArena tracking draw-scoped objects.
public final class ElementArena: @unchecked Sendable {
    private var storage: [AnyObject] = []

    public init() {}

    public func alloc<T: AnyObject>(_ create: () -> T) -> T {
        let object = create()
        storage.append(object)
        return object
    }

    public func clear() {
        storage.removeAll(keepingCapacity: true)
    }
}

// PORT NOTE: Thread/draw-scoped fallback element arena matching upstream ELEMENT_ARENA.
public nonisolated(unsafe) var elementArena: ElementArena = ElementArena()

/// Scope managing element arena memory allocations during layout and drawing.
public struct ElementArenaScope: Sendable {
    public static func enter() -> ElementArenaScope {
        ElementArenaScope()
    }
}

/// Executes a closure within an active element arena scope.
public func withElementArena<R>(_ f: (inout ElementArena) -> R) -> R {
    f(&elementArena)
}

public func withElementArena<R>(_ f: () -> R) -> R {
    f()
}

/// An identifier for an `Element`.
public enum ElementId: Sendable, Equatable, Hashable, CustomStringConvertible {
    case view(EntityId)
    case integer(UInt64)
    case name(SharedString)
    case uuid(UUID)
    case focusHandle(FocusId)
    case namedInteger(SharedString, UInt64)
    case path(String)
    case codeLocation(String)
    indirect case namedChild(ElementId, SharedString)

    public init(_ integer: UInt64) {
        self = .integer(integer)
    }

    public init(named: String) {
        self = .name(SharedString(named))
    }

    public static func namedUsize(_ name: String, _ index: Int) -> ElementId {
        .namedInteger(SharedString(name), UInt64(index))
    }

    public var description: String {
        switch self {
        case .view(let entityId):
            return "view-\(entityId)"
        case .integer(let ix):
            return "\(ix)"
        case .name(let name):
            return "\(name)"
        case .uuid(let id):
            return "\(id)"
        case .focusHandle(let id):
            return "FocusHandle(\(id))"
        case .namedInteger(let s, let i):
            return "\(s)-\(i)"
        case .path(let p):
            return "\(p)"
        case .codeLocation(let loc):
            return "\(loc)"
        case .namedChild(let id, let name):
            return "\(id)-\(name)"
        }
    }
}

extension ElementId: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    public init(stringLiteral value: String) {
        self = .name(SharedString(value))
    }
    public init(integerLiteral value: UInt64) {
        self = .integer(value)
    }
}

/// Focusable allows users of your view to easily focus it (using window.focus_view(cx, view)).
public protocol Focusable {
    func focusHandle(_ cx: App) -> FocusHandle
}

extension Entity: Focusable where T: Focusable {
    public func focusHandle(_ cx: App) -> FocusHandle {
        MainActor.assumeIsolated {
            read(cx).focusHandle(cx)
        }
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

// PORT NOTE: FocusRef fields are protected by FocusMap's NSLock matching upstream RwLock<FocusMap>.
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
public typealias FocusHandleMap = FocusMap
// PORT NOTE: Synchronized via NSLock matching upstream RwLock<SlotMap<FocusId, FocusRef>>.
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

// PORT NOTE: Holds reference to thread-safe FocusMap for RAII release matching upstream Arc<FocusHandle>.
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
// PORT NOTE: Thread-safe handle containing token backed by thread-safe FocusMap matching upstream FocusHandle.
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

    public static func new(handles: FocusMap) -> FocusHandle {
        FocusHandle(handles: handles)
    }

    @MainActor
    public func dispatchAction(_ action: any Action, _ window: inout Window, _ cx: inout App) {
        if let nodeId = window.renderedFrame.dispatchTree.focusableNodeId(id) {
            window.dispatchActionOnNode(nodeId, action, &cx)
        }
    }

    public static func == (lhs: FocusHandle, rhs: FocusHandle) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// A weak reference to a focus handle that does not keep it alive.
// PORT NOTE: Weak reference to thread-safe FocusMap matching upstream WeakFocusHandle.
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

// MARK: - Managed View & Event Protocols

public protocol ManagedView: Focusable, EventEmitter<DismissEvent> {}

public struct DismissEvent: Sendable, Equatable {
    public init() {}
}

public typealias AnyMouseListener = @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void

public struct CursorStyleRequest: Sendable {
    public var hitboxId: HitboxId?
    public var style: CursorStyle

    public init(hitboxId: HitboxId? = nil, style: CursorStyle) {
        self.hitboxId = hitboxId
        self.style = style
    }
}

public enum WindowControlArea: Sendable, Equatable {
    case drag
    case close
    case max
    case min
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
        if window.capturedHitbox == self {
            return true
        }
        if window.lastInputWasKeyboard() {
            return false
        }
        return window.mouseHitTest.ids.prefix(window.mouseHitTest.hoverHitboxCount).contains(self)
    }

    public func shouldHandleScroll(_ window: Window) -> Bool {
        window.mouseHitTest.ids.contains(self)
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

    public func isHovered(_ window: Window) -> Bool {
        id.isHovered(window)
    }

    public func shouldHandleScroll(_ window: Window) -> Bool {
        id.shouldHandleScroll(window)
    }
}

/// An identifier for a tooltip.
public struct TooltipId: Sendable, Equatable, Hashable {
    public var rawValue: Int

    public init(_ rawValue: Int = 0) {
        self.rawValue = rawValue
    }

    public func isHovered(_ window: Window) -> Bool {
        guard let tooltipBounds = window.tooltipBounds else { return false }
        return tooltipBounds.id == self && tooltipBounds.bounds.contains(window.mousePosition)
    }
}

public struct TooltipBounds: Sendable {
    public var id: TooltipId
    public var bounds: Bounds<Pixels>

    public init(id: TooltipId, bounds: Bounds<Pixels>) {
        self.id = id
        self.bounds = bounds
    }
}

// PORT NOTE: Holds TooltipId and AnyTooltip across frame lifecycle matching upstream TooltipRequest.
public struct TooltipRequest: @unchecked Sendable {
    public var id: TooltipId
    public var tooltip: AnyTooltip

    public init(id: TooltipId, tooltip: AnyTooltip) {
        self.id = id
        self.tooltip = tooltip
    }
}

public struct PrepaintStateIndex: Sendable, Equatable, Hashable, Comparable {
    public var hitboxesIndex: Int
    public var tooltipsIndex: Int
    public var deferredDrawsIndex: Int
    public var dispatchTreeIndex: Int
    public var accessedElementStatesIndex: Int
    public var lineLayoutIndex: LineLayoutIndex

    public init(
        hitboxesIndex: Int = 0,
        tooltipsIndex: Int = 0,
        deferredDrawsIndex: Int = 0,
        dispatchTreeIndex: Int = 0,
        accessedElementStatesIndex: Int = 0,
        lineLayoutIndex: LineLayoutIndex = LineLayoutIndex()
    ) {
        self.hitboxesIndex = hitboxesIndex
        self.tooltipsIndex = tooltipsIndex
        self.deferredDrawsIndex = deferredDrawsIndex
        self.dispatchTreeIndex = dispatchTreeIndex
        self.accessedElementStatesIndex = accessedElementStatesIndex
        self.lineLayoutIndex = lineLayoutIndex
    }

    public static func < (lhs: PrepaintStateIndex, rhs: PrepaintStateIndex) -> Bool {
        if lhs.hitboxesIndex != rhs.hitboxesIndex { return lhs.hitboxesIndex < rhs.hitboxesIndex }
        if lhs.tooltipsIndex != rhs.tooltipsIndex { return lhs.tooltipsIndex < rhs.tooltipsIndex }
        if lhs.deferredDrawsIndex != rhs.deferredDrawsIndex { return lhs.deferredDrawsIndex < rhs.deferredDrawsIndex }
        if lhs.dispatchTreeIndex != rhs.dispatchTreeIndex { return lhs.dispatchTreeIndex < rhs.dispatchTreeIndex }
        return lhs.accessedElementStatesIndex < rhs.accessedElementStatesIndex
    }
}

public struct PaintIndex: Sendable, Equatable, Hashable, Comparable {
    public var sceneIndex: Int
    public var mouseListenersIndex: Int
    public var inputHandlersIndex: Int
    public var cursorStylesIndex: Int
    public var accessedElementStatesIndex: Int
    public var tabHandleIndex: Int
    public var lineLayoutIndex: LineLayoutIndex

    public init(
        sceneIndex: Int = 0,
        mouseListenersIndex: Int = 0,
        inputHandlersIndex: Int = 0,
        cursorStylesIndex: Int = 0,
        accessedElementStatesIndex: Int = 0,
        tabHandleIndex: Int = 0,
        lineLayoutIndex: LineLayoutIndex = LineLayoutIndex()
    ) {
        self.sceneIndex = sceneIndex
        self.mouseListenersIndex = mouseListenersIndex
        self.inputHandlersIndex = inputHandlersIndex
        self.cursorStylesIndex = cursorStylesIndex
        self.accessedElementStatesIndex = accessedElementStatesIndex
        self.tabHandleIndex = tabHandleIndex
        self.lineLayoutIndex = lineLayoutIndex
    }

    public static func < (lhs: PaintIndex, rhs: PaintIndex) -> Bool {
        if lhs.sceneIndex != rhs.sceneIndex { return lhs.sceneIndex < rhs.sceneIndex }
        if lhs.mouseListenersIndex != rhs.mouseListenersIndex { return lhs.mouseListenersIndex < rhs.mouseListenersIndex }
        if lhs.inputHandlersIndex != rhs.inputHandlersIndex { return lhs.inputHandlersIndex < rhs.inputHandlersIndex }
        if lhs.cursorStylesIndex != rhs.cursorStylesIndex { return lhs.cursorStylesIndex < rhs.cursorStylesIndex }
        if lhs.accessedElementStatesIndex != rhs.accessedElementStatesIndex { return lhs.accessedElementStatesIndex < rhs.accessedElementStatesIndex }
        return lhs.tabHandleIndex < rhs.tabHandleIndex
    }
}

public struct InputRateTracker: Sendable {
    private var timestamps: [Date]
    private var windowInterval: TimeInterval
    private var inputsPerSecond: Int
    private var sustainUntil: Date
    private var sustainDuration: TimeInterval

    public init(
        windowInterval: TimeInterval = 0.1,
        inputsPerSecond: Int = 60,
        sustainDuration: TimeInterval = 1.0
    ) {
        self.timestamps = []
        self.windowInterval = windowInterval
        self.inputsPerSecond = inputsPerSecond
        self.sustainUntil = Date()
        self.sustainDuration = sustainDuration
    }

    public mutating func recordInput() {
        let now = Date()
        timestamps.append(now)
        timestamps.removeAll { now.timeIntervalSince($0) > windowInterval }
        let minEvents = Double(inputsPerSecond) * windowInterval
        if Double(timestamps.count) >= minEvents {
            sustainUntil = now.addingTimeInterval(sustainDuration)
        }
    }

    public func isHighRate() -> Bool {
        Date() < sustainUntil
    }
}

// PORT NOTE: Type-erased Any container for element state matching upstream Box<dyn Any>.
public struct ElementStateBox: @unchecked Sendable {
    public var inner: Any

    public init(_ inner: Any) {
        self.inner = inner
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

/// A deferred draw operation executed after primary element layout and paint.
public struct DeferredDraw: Sendable {
    public var priority: Int
    public var draw: @Sendable (inout Window, inout App) -> Void

    public init(
        priority: Int = 0,
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
// PORT NOTE: Rendered frame data structures are thread-confined to main thread window pipeline.
public struct Frame: @unchecked Sendable {
    public var focus: FocusId?
    public var windowActive: Bool
    public var dispatchTree: DispatchTree
    public var scene: Scene
    public var hitboxes: [Hitbox]
    public var windowControlHitboxes: [(WindowControlArea, Hitbox)]
    public var deferredDraws: [DeferredDraw]
    public var tabStops: TabStopMap
    public var mouseListeners: [AnyMouseListener]
    public var inputHandlers: [any PlatformInputHandlerProtocol]
    public var tooltipRequests: [TooltipRequest]
    public var cursorStyles: [CursorStyleRequest]

    public init(dispatchTree: DispatchTree = DispatchTree()) {
        var dt = dispatchTree
        if dt.nodes.isEmpty {
            _ = dt.pushNode()
        }
        self.focus = nil
        self.windowActive = false
        self.dispatchTree = dt
        self.scene = Scene()
        self.hitboxes = []
        self.windowControlHitboxes = []
        self.deferredDraws = []
        self.tabStops = TabStopMap()
        self.mouseListeners = []
        self.inputHandlers = []
        self.tooltipRequests = []
        self.cursorStyles = []
    }

    public static func new(dispatchTree: DispatchTree = DispatchTree()) -> Frame {
        Frame(dispatchTree: dispatchTree)
    }

    public mutating func clear() {
        focus = nil
        windowActive = false
        dispatchTree.clear()
        _ = dispatchTree.pushNode()
        scene.clear()
        hitboxes.removeAll()
        windowControlHitboxes.removeAll()
        deferredDraws.removeAll()
        tabStops.clear()
        mouseListeners.removeAll()
        inputHandlers.removeAll()
        tooltipRequests.removeAll()
        cursorStyles.removeAll()
    }

    public func cursorStyle(_ window: Window) -> CursorStyle? {
        for request in cursorStyles.reversed() {
            if let hitboxId = request.hitboxId {
                if hitboxId.isHovered(window) {
                    return request.style
                }
            } else {
                return request.style
            }
        }
        return nil
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

// MARK: - Window Identifiers & Handles

/// Globally unique identifier for a window.
public struct WindowId: Sendable, Equatable, Hashable, RawRepresentable, ExpressibleByIntegerLiteral {
    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt64) {
        self.rawValue = value
    }

    public func asU64() -> UInt64 {
        rawValue
    }
}

/// Type-erased handle to a window instance.
public struct AnyWindowHandle: Sendable, Equatable, Hashable {
    public let id: UInt64

    public init(id: UInt64) {
        self.id = id
    }

    public func windowId() -> WindowId {
        WindowId(id)
    }

    public func downcast<V>() -> WindowHandle<V>? {
        WindowHandle<V>(anyHandle: self)
    }

    @MainActor
    public func update<R>(_ cx: inout App, _ update: (AnyView, inout Window, inout App) -> R) -> Result<R, any Error> {
        do {
            var appCopy = cx
            let result = try cx.updateWindow(self) { root, window, _ in
                update(root, &window, &appCopy)
            }
            cx = appCopy
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    @MainActor
    public func read<R>(_ cx: App, _ read: (AnyView, App) -> R) -> Result<R, any Error> {
        do {
            let result = try cx.readWindow(self, read)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }
}

/// Strongly-typed window handle associated with a specific root view type.
public struct WindowHandle<V>: Sendable, Equatable, Hashable {
    public let anyHandle: AnyWindowHandle

    public init(anyHandle: AnyWindowHandle) {
        self.anyHandle = anyHandle
    }

    public static func new(anyHandle: AnyWindowHandle) -> WindowHandle<V> {
        WindowHandle(anyHandle: anyHandle)
    }

    @MainActor
    public func update<R>(_ cx: inout App, _ update: (AnyView, inout Window, inout App) -> R) -> Result<R, any Error> {
        anyHandle.update(&cx, update)
    }

    @MainActor
    public func read<R>(_ cx: App, _ read: (AnyView, App) -> R) -> Result<R, any Error> {
        anyHandle.read(cx, read)
    }

    @MainActor
    public func readWith<R>(_ cx: App, _ read: (AnyView, App) -> R) -> Result<R, any Error> {
        anyHandle.read(cx, read)
    }

    @MainActor
    public func entity(_ cx: App) -> Result<Entity<V>, any Error> {
        let readResult = anyHandle.read(cx) { view, _ in
            view
        }
        switch readResult {
        case .success(let view):
            let downcastRes: Result<Entity<V>, AnyView> = view.downcast()
            switch downcastRes {
            case .success(let entity):
                return .success(entity)
            case .failure(let errView):
                return .failure(errView)
            }
        case .failure(let error):
            return .failure(error)
        }
    }
}

// MARK: - ContentMask Extension

extension ContentMask where P == Pixels {
    public func scale(factor: Float) -> ContentMask<ScaledPixels> {
        ContentMask<ScaledPixels>(bounds: bounds.scale(factor))
    }

    public func intersect(other: ContentMask<Pixels>) -> ContentMask<Pixels> {
        ContentMask<Pixels>(bounds: bounds.intersect(other.bounds))
    }
}

// MARK: - PaintQuad & Primitives

/// Quad definition passed into Window.paintQuad.
public struct PaintQuad: Sendable, Equatable {
    public var bounds: Bounds<Pixels>
    public var cornerRadii: Corners<Pixels>
    public var background: Fill
    public var borderWidths: Edges<Pixels>
    public var borderColor: Hsla
    public var borderStyle: BorderStyle

    public init(
        bounds: Bounds<Pixels>,
        cornerRadii: Corners<Pixels> = .zero,
        background: Fill = Fill(transparentBlack()),
        borderWidths: Edges<Pixels> = .zero,
        borderColor: Hsla = transparentBlack(),
        borderStyle: BorderStyle = .solid
    ) {
        self.bounds = bounds
        self.cornerRadii = cornerRadii
        self.background = background
        self.borderWidths = borderWidths
        self.borderColor = borderColor
        self.borderStyle = borderStyle
    }

    public func cornerRadii(_ cornerRadii: Corners<Pixels>) -> PaintQuad {
        var copy = self
        copy.cornerRadii = cornerRadii
        return copy
    }

    public func borderWidths(_ borderWidths: Edges<Pixels>) -> PaintQuad {
        var copy = self
        copy.borderWidths = borderWidths
        return copy
    }

    public func borderColor(_ borderColor: Hsla) -> PaintQuad {
        var copy = self
        copy.borderColor = borderColor
        return copy
    }

    public func background(_ background: Fill) -> PaintQuad {
        var copy = self
        copy.background = background
        return copy
    }

    public func fill(_ color: Hsla) -> PaintQuad {
        background(Fill(color))
    }

    public func cornerRadius(_ radius: Pixels) -> PaintQuad {
        cornerRadii(Corners(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius))
    }

    public func border(width: Pixels, color: Hsla) -> PaintQuad {
        borderWidths(Edges(top: width, right: width, bottom: width, left: width)).borderColor(color)
    }
}

public func quad(
    bounds: Bounds<Pixels>,
    cornerRadii: Corners<Pixels> = .zero,
    background: Fill = Fill(transparentBlack()),
    borderWidths: Edges<Pixels> = .zero,
    borderColor: Hsla = transparentBlack(),
    borderStyle: BorderStyle = .solid
) -> PaintQuad {
    PaintQuad(
        bounds: bounds,
        cornerRadii: cornerRadii,
        background: background,
        borderWidths: borderWidths,
        borderColor: borderColor,
        borderStyle: borderStyle
    )
}

public func fill(
    bounds: Bounds<Pixels>,
    background: Fill
) -> PaintQuad {
    PaintQuad(
        bounds: bounds,
        cornerRadii: .zero,
        background: background,
        borderWidths: .zero,
        borderColor: transparentBlack(),
        borderStyle: .solid
    )
}

public func fill(
    bounds: Bounds<Pixels>,
    color: Hsla
) -> PaintQuad {
    PaintQuad(
        bounds: bounds,
        cornerRadii: .zero,
        background: Fill(color),
        borderWidths: .zero,
        borderColor: transparentBlack(),
        borderStyle: .solid
    )
}

public func outline(
    bounds: Bounds<Pixels>,
    borderColor: Hsla,
    borderStyle: BorderStyle = .solid,
    width: Pixels = px(1)
) -> PaintQuad {
    PaintQuad(
        bounds: bounds,
        cornerRadii: .zero,
        background: Fill(transparentBlack()),
        borderWidths: Edges(top: width, right: width, bottom: width, left: width),
        borderColor: borderColor,
        borderStyle: borderStyle
    )
}

// MARK: - Platform Helper Types

public enum WindowDecorations: Sendable, Equatable {
    case client
    case server
}

public struct WindowControls: Sendable, Equatable {
    public init() {}
}

public enum ResizeEdge: Sendable, Equatable {
    case top
    case left
    case bottom
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public struct EdgeInsets<T: Sendable & Equatable>: Sendable, Equatable {
    public var top: T
    public var left: T
    public var bottom: T
    public var right: T

    public init(top: T, left: T, bottom: T, right: T) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static func zero(value: T) -> EdgeInsets<T> {
        EdgeInsets(top: value, left: value, bottom: value, right: value)
    }
}

public protocol PlatformDisplay: AnyObject {
    func id() -> DisplayId
    func visibleBounds() -> Bounds<Pixels>
}

public struct GpuSpecs: Sendable, Equatable {
    public init() {}
}

public struct Image: Sendable, Equatable {
    public var id: UInt64
    public var width: Int
    public var height: Int
    public var data: [UInt8]

    public init(id: UInt64 = 1, width: Int = 0, height: Int = 0, data: [UInt8] = []) {
        self.id = id
        self.width = width
        self.height = height
        self.data = data
    }
}

public struct RenderImage: Sendable {
    public init() {}
}

public enum InputModality: Sendable, Equatable {
    case mouse
    case keyboard
}

public protocol PlatformInputHandlerProtocol: AnyObject {
    func acceptsTextInput(window: Window, cx: App) -> Bool
    func dispatchInput(_ text: String, _ window: inout Window, _ cx: inout App)
}

extension PlatformInputHandlerProtocol {
    public func acceptsTextInput(window: Window, cx: App) -> Bool { true }
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
    func setInputHandler(_ handler: any PlatformInputHandlerProtocol)
    func takeInputHandler() -> (any PlatformInputHandlerProtocol)?
    func activeInputHandler() -> (any PlatformInputHandlerProtocol)?
}

extension PlatformWindow {
    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? { nil }
    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {}
    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? { nil }
    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? { nil }
    public func nativeToolbarItemBounds() -> [String: Bounds<Pixels>] { [:] }
    public func requestDecorations(_ decorations: WindowDecorations) {}
    public func startWindowResize(_ edge: ResizeEdge) {}
    public func startWindowMove() {}
    public func windowDecorations() -> WindowDecorations { .client }
    public func windowControls() -> WindowControls { WindowControls() }
    public func showWindowMenu(_ position: Point<Pixels>) {}
    public func setAppId(_ appId: String) {}
    public func setEdited(_ edited: Bool) {}
    public func showCharacterPalette() {}
    public func display() -> (any PlatformDisplay)? { nil }
    public func gpuSpecs() -> GpuSpecs? { nil }
    public func tabbedWindows() -> [AnyWindowHandle]? { nil }
    public func tabBarVisible() -> Bool { false }
    public func mergeAllWindows() {}
    public func moveTabToNewWindow() {}
    public func toggleWindowTabOverview() {}
    public func setTabbingIdentifier(_ identifier: String) {}
    public func renderToImage(scene: Scene) -> Image? { nil }
}

/// Default mock platform window for headless test execution.
// PORT NOTE: Mock platform window confined to test execution context.
public final class DefaultPlatformWindow: PlatformWindow, @unchecked Sendable {
    public var windowBounds: Bounds<Pixels>
    public var windowScaleFactor: Float
    public var windowAppearance: WindowAppearance
    public var lastDrawnScene: Scene?
    public var isMinimizedState: Bool = false
    public var isZoomedState: Bool = false
    public var isFullScreenState: Bool = false
    public var currentInputHandler: (any PlatformInputHandlerProtocol)? = nil
    public var windowDecorationsVal: WindowDecorations = .client
    public var windowControlsVal: WindowControls = WindowControls()
    public var appIdVal: String? = nil
    public var isEditedVal: Bool = false
    public var characterPaletteShown: Bool = false
    public var isActivated: Bool = false
    public var resizeEdgeState: ResizeEdge? = nil
    public var windowMoveStarted: Bool = false
    public var menuPosition: Point<Pixels>? = nil
    public var rawViewPtr: UnsafeMutableRawPointer? = nil
    public var toolbarItemBoundsMap: [String: Bounds<Pixels>] = [:]
    public var currentDisplay: (any PlatformDisplay)? = nil
    public var currentGpuSpecs: GpuSpecs? = nil
    public var tabbingId: String? = nil
    public var tabOverviewShown: Bool = false
    public var tabsVisible: Bool = false

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
    public func activate() { isActivated = true }
    public func isMaximized() -> Bool { isZoomedState }
    public func isActive() -> Bool { isActivated || !isMinimizedState }
    public func isHovered() -> Bool { true }
    public func isFullscreen() -> Bool { isFullScreenState }
    public func minimize() { isMinimizedState = true }
    public func zoom() { isZoomedState.toggle() }
    public func toggleFullScreen() { isFullScreenState.toggle() }
    public func draw(scene: Scene) {
        self.lastDrawnScene = scene
    }
    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        let h = currentInputHandler
        currentInputHandler = nil
        return h
    }
    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        currentInputHandler = handler
    }
    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        currentInputHandler
    }
    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? { rawViewPtr }
    public func nativeToolbarItemBounds() -> [String: Bounds<Pixels>] { toolbarItemBoundsMap }
    public func requestDecorations(_ decorations: WindowDecorations) { windowDecorationsVal = decorations }
    public func startWindowResize(_ edge: ResizeEdge) { resizeEdgeState = edge }
    public func startWindowMove() { windowMoveStarted = true }
    public func windowDecorations() -> WindowDecorations { windowDecorationsVal }
    public func windowControls() -> WindowControls { windowControlsVal }
    public func showWindowMenu(_ position: Point<Pixels>) { menuPosition = position }
    public func setAppId(_ appId: String) { appIdVal = appId }
    public func setEdited(_ edited: Bool) { isEditedVal = edited }
    public func showCharacterPalette() { characterPaletteShown = true }
    public func display() -> (any PlatformDisplay)? { currentDisplay }
    public func gpuSpecs() -> GpuSpecs? { currentGpuSpecs }
    public func tabbedWindows() -> [AnyWindowHandle]? { [] }
    public func tabBarVisible() -> Bool { tabsVisible }
    public var mergedWindowsCalled: Bool = false
    public var movedTabCalled: Bool = false
    public func mergeAllWindows() { mergedWindowsCalled = true }
    public func moveTabToNewWindow() { movedTabCalled = true }
    public func toggleWindowTabOverview() { tabOverviewShown.toggle() }
    public func setTabbingIdentifier(_ identifier: String) { tabbingId = identifier }
    public func renderToImage(scene: Scene) -> Image? {
        Image(width: Int(windowBounds.size.width.value), height: Int(windowBounds.size.height.value), data: [])
    }
}


public struct PendingInput: Sendable {
    public var keystrokes: [Keystroke]
    public var focus: FocusId?

    public init(keystrokes: [Keystroke] = [], focus: FocusId? = nil) {
        self.keystrokes = keystrokes
        self.focus = focus
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

    public var capturedHitbox: HitboxId? = nil
    public var nextTooltipId: TooltipId = TooltipId(1)
    public var tooltipBounds: TooltipBounds? = nil
    public var lastInputModality: InputModality = .mouse
    public var defaultPrevented: Bool = false
    public var propagateEvent: Bool = true
    public var pendingInput: PendingInput? = nil
    public var pendingInputObservers: [(@Sendable (inout Window, inout App) -> Bool)] = []
    public var focusListeners: [AnyWindowFocusListener] = []
    public var windowShouldCloseCallbacks: [() -> Bool] = []
    public var nativeViewOverrideStack: [UnsafeMutableRawPointer] = []
    public var currentEventNativeViewPtr: UnsafeMutableRawPointer? = nil
    public var surfaces: [SurfaceId: SurfaceState] = [:]
    public var remSizeOverrideStack: [Pixels] = []
    public var renderedEntityStack: [EntityId] = []
    public var textStyleStack: [TextStyleRefinement] = []
    public var inputRateTracker: InputRateTracker = InputRateTracker()
    public var displayId: DisplayId? = nil
    public var elementIdStack: [ElementId] = []
    public var isInspectorPickingState: Bool = false
    public var assetCache: [ObjectIdentifier: Any] = [:]
    public var keystrokeObservers: [(@Sendable (KeystrokeEvent, inout Window, inout App) -> Void)] = []
    public var keystrokeInterceptors: [(@Sendable (KeystrokeEvent, inout Window, inout App) -> Bool)] = []
    public var spriteAtlas: any PlatformAtlas = TestAtlas.new()
    public var windowTextSystem: WindowTextSystem? = nil
    public var refreshing: Bool = false
    public var accessedElementStates: [(GlobalElementId, ObjectIdentifier)] = []

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

    public static func new(
        handle: AnyWindowHandle = AnyWindowHandle(id: 1),
        platformWindow: any PlatformWindow = DefaultPlatformWindow(),
        scaleFactor: Float = 1.0,
        viewportSize: Size<Pixels> = size(px(800.0), px(600.0)),
        remSize: Pixels = px(16.0)
    ) -> Window {
        Window(
            handle: handle,
            platformWindow: platformWindow,
            scaleFactor: scaleFactor,
            viewportSize: viewportSize,
            remSize: remSize
        )
    }

    public init(
        handle: AnyWindowHandle,
        options: WindowOptions,
        cx: inout App
    ) {
        let bounds = options.windowBounds?.bounds ?? Bounds(origin: .zero, size: DEFAULT_WINDOW_SIZE)
        self.init(
            handle: handle,
            platformWindow: DefaultPlatformWindow(bounds: bounds),
            scaleFactor: 1.0,
            viewportSize: bounds.size,
            remSize: px(16.0)
        )
        self.backgroundAppearance = options.windowBackground
        self.displayId = options.displayId
        if let title = options.titlebar?.title {
            self.windowTitle = title
        }
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
        _ bounds: Bounds<Pixels>,
        _ behavior: HitboxBehavior = .normal
    ) -> Hitbox {
        let id = HitboxId(nextHitboxIdValue)
        nextHitboxIdValue += 1
        let mask = contentMaskStack.last ?? ContentMask(bounds: .zero)
        let hitbox = Hitbox(id: id, bounds: bounds, contentMask: mask, behavior: behavior)
        nextFrame.hitboxes.append(hitbox)
        return hitbox
    }

    public mutating func insertHitbox(
        bounds: Bounds<Pixels>,
        behavior: HitboxBehavior = .normal
    ) -> Hitbox {
        insertHitbox(bounds, behavior)
    }

    public mutating func insertWindowControlHitbox(
        _ area: WindowControlArea,
        _ hitbox: Hitbox
    ) {
        nextFrame.windowControlHitboxes.append((area, hitbox))
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
        accessedElementStates.append((id, ObjectIdentifier(State.self)))
        let result = f(&state)
        if let state = state {
            elementStates[id] = state
        } else {
            elementStates.removeValue(forKey: id)
        }
        return result
    }

    public mutating func withElementState<State, R>(
        _ id: GlobalElementId,
        _ f: (State?, inout Window) -> (R, State?)
    ) -> R {
        let existing = elementStates[id] as? State
        accessedElementStates.append((id, ObjectIdentifier(State.self)))
        let (result, newState) = f(existing, &self)
        if let newState = newState {
            elementStates[id] = newState
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

    public mutating func layoutBounds(_ id: LayoutId) -> Bounds<Pixels> {
        layoutEngine?.layoutBounds(id: id, scaleFactor: scaleFactor) ?? .zero
    }

    public mutating func layoutBounds(id: LayoutId) -> Bounds<Pixels> {
        layoutBounds(id)
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

    public mutating func paintUnderline(
        origin: Point<Pixels>,
        width: Pixels,
        style: UnderlineStyle
    ) {
        let scale = scaleFactor
        let height = style.wavy ? (style.thickness * Float(3.0)) : style.thickness
        let bounds = Bounds(origin: origin, size: Size(width: width, height: height))
        let mask = (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scale)
        let opacity = elementOpacity

        nextFrame.scene.insertUnderline(Underline(
            order: 0,
            pad: 0,
            bounds: bounds.scale(scale),
            contentMask: mask,
            color: (style.color ?? transparentBlack()).opacity(opacity),
            thickness: style.thickness.scale(scale),
            wavy: style.wavy ? 1 : 0
        ))
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

    public mutating func paintStrikethrough(
        origin: Point<Pixels>,
        width: Pixels,
        style: StrikethroughStyle
    ) {
        let scale = scaleFactor
        let height = style.thickness
        let bounds = Bounds(origin: origin, size: Size(width: width, height: height))
        let mask = (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scale)
        let opacity = elementOpacity

        nextFrame.scene.insertUnderline(Underline(
            order: 0,
            pad: 0,
            bounds: bounds.scale(scale),
            contentMask: mask,
            color: (style.color ?? transparentBlack()).opacity(opacity),
            thickness: style.thickness.scale(scale),
            wavy: 0
        ))
    }

    public mutating func paintSurface(_ surface: PaintSurface) {
        nextFrame.scene.insertSurface(surface)
    }

    // MARK: - Stacks & Scoping

    public mutating func withContentMask<R>(
        _ mask: ContentMask<Pixels>?,
        _ f: (inout Window) -> R
    ) -> R {
        guard let mask = mask else {
            return f(&self)
        }
        let parentMask = contentMaskStack.last ?? ContentMask(bounds: .zero)
        let combined = parentMask.intersect(mask)
        contentMaskStack.append(combined)
        defer { contentMaskStack.removeLast() }
        return f(&self)
    }

    public mutating func withContentMask<R>(
        _ mask: ContentMask<Pixels>,
        _ f: (inout Window) -> R
    ) -> R {
        withContentMask(Optional(mask), f)
    }

    public func contentMask() -> ContentMask<Pixels> {
        contentMaskStack.last ?? ContentMask(bounds: .zero)
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
        priority: Int = 0,
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
            nextFrame.dispatchTree.keymap = cx.keymap
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

    // MARK: - Event Dispatch & Routing

    /// Dispatches an input event across the window's visual tree.
    @discardableResult
    @MainActor
    public mutating func dispatchEvent(
        event: PlatformInput,
        cx: inout App
    ) -> DispatchEventResult {
        let oldModality = lastInputModality
        switch event {
        case .keyDown:
            lastInputModality = .keyboard
        case .mouseMove, .mouseDown:
            lastInputModality = .mouse
        default:
            break
        }
        if lastInputModality != oldModality {
            refresh()
        }

        propagateEvent = true
        defaultPrevented = false

        switch event {
        case .mouseMove(let move):
            mousePosition = move.position
            modifiers = move.modifiers
            dispatchMouseEvent(move, &cx)

        case .mouseDown(let down):
            mousePosition = down.position
            modifiers = down.modifiers
            dispatchMouseEvent(down, &cx)

        case .mouseUp(let up):
            mousePosition = up.position
            modifiers = up.modifiers
            dispatchMouseEvent(up, &cx)
            if capturedHitbox != nil {
                capturedHitbox = nil
            }

        case .mousePressure(let pressure):
            mousePosition = pressure.position
            modifiers = pressure.modifiers
            dispatchMouseEvent(pressure, &cx)

        case .mouseExited(let exit):
            mousePosition = Point(x: px(-1.0), y: px(-1.0))
            modifiers = exit.modifiers
            mouseHitTest = HitTest()
            dispatchMouseEvent(exit, &cx)

        case .scrollWheel(let scroll):
            mousePosition = scroll.position
            modifiers = scroll.modifiers
            dispatchMouseEvent(scroll, &cx)

        case .pinch(let pinch):
            mousePosition = pinch.position
            modifiers = pinch.modifiers
            dispatchMouseEvent(pinch, &cx)

        case .rotation(let rotation):
            mousePosition = rotation.center
            dispatchMouseEvent(rotation, &cx)

        case .fileDrop(let fileDrop):
            dispatchMouseEvent(fileDrop, &cx)

        case .keyDown(let key):
            modifiers = key.keystroke.modifiers
            dispatchKeyEvent(key, &cx)

        case .keyUp(let key):
            modifiers = key.keystroke.modifiers
            dispatchKeyEvent(key, &cx)

        case .modifiersChanged(let mod):
            modifiers = mod.modifiers
            capslock = mod.capslock
            dispatchKeyEvent(mod, &cx)
        }

        if invalidator.isDirty {
            inputRateTracker.recordInput()
        }

        return DispatchEventResult(
            propagate: propagateEvent,
            defaultPrevented: defaultPrevented
        )
    }

    /// Evaluates mouse hitboxes and dispatches through capture and bubble phases.
    @MainActor
    private mutating func dispatchMouseEvent(_ event: Any, _ cx: inout App) {
        let hitTest = renderedFrame.hitTest(mousePosition)
        if hitTest != mouseHitTest {
            mouseHitTest = hitTest
        }

        let listeners = renderedFrame.mouseListeners

        // Capture phase (front to back)
        for listener in listeners {
            listener(event, .capture, &self, &cx)
            if !propagateEvent {
                break
            }
        }

        // Bubble phase (back to front)
        if propagateEvent {
            for listener in listeners.reversed() {
                listener(event, .bubble, &self, &cx)
                if !propagateEvent {
                    break
                }
            }
        }

        renderedFrame.mouseListeners = listeners
    }

    /// Dispatches key event through dispatch tree, keymap chords, action handlers, and listeners.
    @MainActor
    private mutating func dispatchKeyEvent(_ event: Any, _ cx: inout App) {
        renderedFrame.dispatchTree.keymap = cx.keymap
        let nodeId = focusNodeIdInRenderedFrame(focus)
        let dispatchPath = renderedFrame.dispatchTree.dispatchPath(nodeId)

        var keystroke: Keystroke? = nil
        if let keyDown = event as? KeyDownEvent {
            keystroke = keyDown.keystroke
        }

        if let keystroke = keystroke {
            let currentPending = pendingInputKeystrokes() ?? []
            let matchResult = renderedFrame.dispatchTree.dispatchKey(
                currentPending,
                keystroke,
                dispatchPath
            )

            if !matchResult.toReplay.isEmpty {
                replayPendingInput(matchResult.toReplay, &cx)
                propagateEvent = true
            }

            if !matchResult.pending.isEmpty {
                pendingInput = PendingInput(keystrokes: matchResult.pending, focus: focus)
                pendingInputChanged(&cx)
                propagateEvent = false
                return
            } else {
                pendingInput = nil
            }

            for binding in matchResult.bindings {
                dispatchActionOnNode(nodeId, binding.action, &cx)
                if !propagateEvent {
                    pendingInputChanged(&cx)
                    return
                }
            }
        }

        // Low-level key event listeners: capture phase
        for id in dispatchPath {
            let node = renderedFrame.dispatchTree.nodes[id.rawValue]
            for keyListener in node.keyListeners {
                keyListener(event, .capture, &self, &cx)
                if !propagateEvent { return }
            }
        }

        // Low-level key event listeners: bubble phase
        for id in dispatchPath.reversed() {
            let node = renderedFrame.dispatchTree.nodes[id.rawValue]
            for keyListener in node.keyListeners {
                keyListener(event, .bubble, &self, &cx)
                if !propagateEvent { return }
            }
        }

        // Modifiers changed listeners
        if let modEvent = event as? ModifiersChangedEvent {
            for id in dispatchPath.reversed() {
                let node = renderedFrame.dispatchTree.nodes[id.rawValue]
                for listener in node.modifiersChangedListeners {
                    listener(modEvent, &self, &cx)
                    if !propagateEvent { return }
                }
            }
        }

        pendingInputChanged(&cx)
    }

    @MainActor
    private mutating func replayPendingInput(_ replays: [Replay], _ cx: inout App) {
        let nodeId = focusNodeIdInRenderedFrame(focus)
        let dispatchPath = renderedFrame.dispatchTree.dispatchPath(nodeId)

        for replay in replays {
            let event = KeyDownEvent(
                keystroke: replay.keystroke,
                isHeld: false,
                preferCharacterInput: true
            )
            propagateEvent = true
            for binding in replay.bindings {
                dispatchActionOnNode(nodeId, binding.action, &cx)
                if !propagateEvent { break }
            }
            if propagateEvent {
                for id in dispatchPath.reversed() {
                    let node = renderedFrame.dispatchTree.nodes[id.rawValue]
                    for keyListener in node.keyListeners {
                        keyListener(event, .bubble, &self, &cx)
                        if !propagateEvent { break }
                    }
                    if !propagateEvent { break }
                }
            }
        }
    }

    private func focusNodeIdInRenderedFrame(_ focusId: FocusId?) -> DispatchNodeId {
        guard let focusId = focusId else { return DispatchNodeId(0) }
        return renderedFrame.dispatchTree.focusableNodeId(focusId) ?? DispatchNodeId(0)
    }

    // MARK: - Action Dispatch

    @MainActor
    public mutating func dispatchAction(_ action: any Action, _ cx: inout App) {
        if let focused = focused(cx) {
            focused.dispatchAction(action, &self, &cx)
        } else {
            dispatchActionOnNode(DispatchNodeId(0), action, &cx)
        }
    }

    @MainActor
    public mutating func dispatchActionOnView(_ view: EntityId, _ action: any Action, _ cx: inout App) {
        if let nodeId = renderedFrame.dispatchTree.viewNodeId(view) {
            dispatchActionOnNode(nodeId, action, &cx)
        }
    }

    @MainActor
    public mutating func dispatchActionOnNode(
        _ nodeId: DispatchNodeId,
        _ action: any Action,
        _ cx: inout App
    ) {
        let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
        let actionId = ObjectIdentifier(type(of: action))

        // Capture phase
        for id in path {
            let node = renderedFrame.dispatchTree.node(id)
            for listener in node.actionListeners where listener.actionType == actionId {
                listener.listener(action, .capture, &self, &cx)
                if !propagateEvent { return }
            }
        }

        // Bubble phase
        for id in path.reversed() {
            let node = renderedFrame.dispatchTree.node(id)
            for listener in node.actionListeners where listener.actionType == actionId {
                listener.listener(action, .bubble, &self, &cx)
                if !propagateEvent { return }
            }
        }
    }

    public mutating func onAction<A: Action>(_ listener: @escaping @Sendable (A, inout Window, inout App) -> Void) {
        nextFrame.dispatchTree.onAction(actionType: ObjectIdentifier(A.self)) { action, phase, window, app in
            if phase == .bubble, let typedAction = action as? A {
                listener(typedAction, &window, &app)
            }
        }
    }

    public mutating func onAction(
        _ actionType: ObjectIdentifier,
        _ listener: @escaping @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void
    ) {
        nextFrame.dispatchTree.onAction(actionType: actionType, listener: listener)
    }

    public mutating func onAction(
        _ actionType: ObjectIdentifier,
        _ listener: @escaping ActionListener
    ) {
        nextFrame.dispatchTree.onAction(actionType: actionType) { action, phase, window, app in
            if let action = action as? any Action {
                listener(action, phase, &window, &app)
            }
        }
    }

    public mutating func onActionWhen<A: Action>(
        _ condition: @escaping @Sendable (Window, App) -> Bool,
        _ listener: @escaping @Sendable (A, inout Window, inout App) -> Void
    ) {
        nextFrame.dispatchTree.onAction(actionType: ObjectIdentifier(A.self)) { action, phase, window, app in
            if phase == .bubble && condition(window, app), let typedAction = action as? A {
                listener(typedAction, &window, &app)
            }
        }
    }

    public func isActionAvailable(_ action: any Action, _ cx: App) -> Bool {
        if let focused = focused(cx) {
            return isActionAvailableIn(action, focused)
        } else {
            return renderedFrame.dispatchTree.isActionAvailable(action, target: DispatchNodeId(0))
        }
    }

    public func isActionAvailableIn(_ action: any Action, _ handle: FocusHandle) -> Bool {
        if let nodeId = renderedFrame.dispatchTree.focusableNodeId(handle.id) {
            return renderedFrame.dispatchTree.isActionAvailable(action, target: nodeId)
        }
        return false
    }

    public func availableActions(_ cx: App? = nil) -> [any Action] {
        let target = focusNodeIdInRenderedFrame(focus)
        return renderedFrame.dispatchTree.availableActions(target: target)
    }

    public func bindingsForAction(_ action: any Action, _ cx: App? = nil) -> [KeyBinding] {
        let stack = contextStack(cx)
        return bindingsForActionInContext(action, stack)
    }

    public func highestPrecedenceBindingForAction(_ action: any Action, _ cx: App? = nil) -> KeyBinding? {
        let stack = contextStack(cx)
        return highestPrecedenceBindingForActionInContext(action, stack)
    }

    public func bindingsForActionInContext(_ action: any Action, _ contextStack: [KeyContext]) -> [KeyBinding] {
        renderedFrame.dispatchTree.bindingsForAction(action, contextStack)
    }

    public func highestPrecedenceBindingForActionInContext(_ action: any Action, _ contextStack: [KeyContext]) -> KeyBinding? {
        renderedFrame.dispatchTree.highestPrecedenceBindingForAction(action, contextStack)
    }

    public func bindingsForActionIn(_ action: any Action, _ handle: FocusHandle) -> [KeyBinding] {
        if let nodeId = renderedFrame.dispatchTree.focusableNodeId(handle.id) {
            let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
            let stack: [KeyContext] = path.compactMap { renderedFrame.dispatchTree.nodes[$0.rawValue].context }
            return bindingsForActionInContext(action, stack)
        }
        return []
    }

    public func highestPrecedenceBindingForActionIn(_ action: any Action, _ handle: FocusHandle) -> KeyBinding? {
        if let nodeId = renderedFrame.dispatchTree.focusableNodeId(handle.id) {
            let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
            let stack: [KeyContext] = path.compactMap { renderedFrame.dispatchTree.nodes[$0.rawValue].context }
            return highestPrecedenceBindingForActionInContext(action, stack)
        }
        return nil
    }

    public func possibleBindingsForInput(_ input: [Keystroke], _ cx: App? = nil) -> [KeyBinding] {
        let stack = contextStack(cx)
        return renderedFrame.dispatchTree.possibleNextBindingsForInput(input, stack)
    }

    public func contextStack(_ cx: App? = nil) -> [KeyContext] {
        let nodeId = focusNodeIdInRenderedFrame(focus)
        let path = renderedFrame.dispatchTree.dispatchPath(nodeId)
        return path.compactMap { renderedFrame.dispatchTree.nodes[$0.rawValue].context }
    }

    public func keystrokeTextFor(_ action: any Action) -> String {
        if let binding = highestPrecedenceBindingForAction(action) {
            return binding.keystrokes.map { "\($0)" }.joined(separator: " ")
        }
        return action.name
    }

    // MARK: - Event Listeners Registration

    public mutating func onMouseEvent<Event>(
        _ listener: @escaping @Sendable (Event, DispatchPhase, inout Window, inout App) -> Void
    ) {
        nextFrame.mouseListeners.append { anyEvent, phase, window, app in
            if let event = anyEvent as? Event {
                listener(event, phase, &window, &app)
            }
        }
    }

    public mutating func onKeyEvent(
        _ listener: @escaping @Sendable (any KeyEvent, DispatchPhase, inout Window, inout App) -> Void
    ) {
        nextFrame.dispatchTree.onKeyEvent { anyEvent, phase, window, app in
            if let event = anyEvent as? any KeyEvent {
                listener(event, phase, &window, &app)
            }
        }
    }

    public mutating func onModifiersChanged(
        _ listener: @escaping @Sendable (ModifiersChangedEvent, inout Window, inout App) -> Void
    ) {
        nextFrame.dispatchTree.onModifiersChanged(listener)
    }

    @MainActor
    public mutating func onFocusIn(
        _ handle: FocusHandle,
        _ cx: inout App,
        _ listener: @escaping @Sendable (inout Window, inout App) -> Void
    ) -> Subscription {
        let focusId = handle.id
        let (subscription, activate) = newFocusListener { event, window, app in
            if event.isFocusIn(focusId) {
                listener(&window, &app)
            }
            return true
        }
        cx.defer { _ in activate() }
        return subscription
    }

    @MainActor
    public mutating func onFocusOut(
        _ handle: FocusHandle,
        _ cx: inout App,
        _ listener: @escaping @Sendable (FocusOutEvent, inout Window, inout App) -> Void
    ) -> Subscription {
        let focusId = handle.id
        let (subscription, activate) = newFocusListener { event, window, app in
            if let blurredId = event.previousFocusPath.last, event.isFocusOut(focusId) {
                let focusEvent = FocusOutEvent(blurred: WeakFocusHandle(id: blurredId, handles: window.focusMap))
                listener(focusEvent, &window, &app)
            }
            return true
        }
        cx.defer { _ in activate() }
        return subscription
    }

    public mutating func newFocusListener(
        _ listener: @escaping AnyWindowFocusListener
    ) -> (Subscription, () -> Void) {
        focusListeners.append(listener)
        let sub = Subscription {}
        return (sub, {})
    }

    // MARK: - Keystroke Dispatch & IME

    @MainActor
    public mutating func dispatchKeystroke(_ keystroke: Keystroke, _ cx: inout App) -> Bool {
        let event = PlatformInput.keyDown(KeyDownEvent(
            keystroke: keystroke,
            isHeld: false,
            preferCharacterInput: false
        ))
        let result = dispatchEvent(event: event, cx: &cx)
        if !result.propagate {
            return true
        }
        if let keyChar = keystroke.keyChar, let inputHandler = platformWindow.takeInputHandler() {
            inputHandler.dispatchInput(keyChar, &self, &cx)
            platformWindow.setInputHandler(inputHandler)
            return true
        }
        return false
    }

    public mutating func handleInput(
        _ focusHandle: FocusHandle,
        _ inputHandler: any PlatformInputHandlerProtocol,
        _ cx: App
    ) {
        invalidator.debugAssertPaint()
        if focusHandle.isFocused(self) {
            nextFrame.inputHandlers.append(inputHandler)
        }
    }

    public mutating func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        platformWindow.setInputHandler(handler)
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        if let handler = platformWindow.takeInputHandler() {
            platformWindow.setInputHandler(handler)
            return handler
        }
        return nil
    }

    public mutating func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        platformWindow.takeInputHandler()
    }

    public mutating func handleInput(_ text: String, cx: inout App) {
        if let handler = platformWindow.activeInputHandler() {
            handler.dispatchInput(text, &self, &cx)
        }
    }

    public mutating func dispatchKeystrokeObservers(
        _ event: Any,
        _ action: (any Action)?,
        _ contextStack: [KeyContext],
        _ cx: inout App
    ) {
        if let keyDown = event as? KeyDownEvent {
            let keystrokeEvent = KeystrokeEvent(keystroke: keyDown.keystroke, action: action, contextStack: contextStack)
            let observers = keystrokeObservers
            for observer in observers {
                observer(keystrokeEvent, &self, &cx)
            }
        }
    }

    public mutating func dispatchKeystrokeInterceptors(
        _ event: Any,
        _ contextStack: [KeyContext],
        _ cx: inout App
    ) {
        if let keyDown = event as? KeyDownEvent {
            let keystrokeEvent = KeystrokeEvent(keystroke: keyDown.keystroke, action: nil, contextStack: contextStack)
            let interceptors = keystrokeInterceptors
            for interceptor in interceptors {
                if !interceptor(keystrokeEvent, &self, &cx) {
                    propagateEvent = false
                    break
                }
            }
        }
    }

    public mutating func pendingInputChanged(_ cx: inout App) {
        let observers = pendingInputObservers
        var retained: [(@Sendable (inout Window, inout App) -> Bool)] = []
        for observer in observers {
            if observer(&self, &cx) {
                retained.append(observer)
            }
        }
        pendingInputObservers = retained
    }

    public func hasPendingKeystrokes() -> Bool {
        pendingInput != nil
    }

    public mutating func clearPendingKeystrokes() {
        pendingInput = nil
    }

    public func pendingInputKeystrokes() -> [Keystroke]? {
        pendingInput?.keystrokes
    }

    public mutating func invalidateCharacterCoordinates() {
        invalidator.setDirty(true)
    }

    // MARK: - Event Control & Interaction Primitives

    public mutating func preventDefault() {
        self.defaultPrevented = true
    }

    public mutating func stopPropagation() {
        self.propagateEvent = false
    }

    public mutating func capturePointer(_ hitboxId: HitboxId) {
        self.capturedHitbox = hitboxId
    }

    public mutating func releasePointer() {
        self.capturedHitbox = nil
    }

    public func lastInputWasKeyboard() -> Bool {
        self.lastInputModality == .keyboard
    }

    public mutating func setCursorStyle(_ style: CursorStyle, hitbox: Hitbox? = nil) {
        nextFrame.cursorStyles.append(CursorStyleRequest(hitboxId: hitbox?.id, style: style))
    }

    public mutating func setWindowCursorStyle(_ style: CursorStyle) {
        self.mouseCursor = style
    }

    public mutating func setTooltip(_ tooltip: AnyTooltip) -> TooltipId {
        let id = nextTooltipId
        nextTooltipId = TooltipId(nextTooltipId.rawValue + 1)
        nextFrame.tooltipRequests.append(TooltipRequest(id: id, tooltip: tooltip))
        return id
    }

    public mutating func setModifiers(_ modifiers: Modifiers) {
        self.modifiers = modifiers
    }

    @MainActor
    public mutating func simulateMouseMove(_ cx: inout App) {
        let move = MouseMoveEvent(position: mousePosition, modifiers: modifiers)
        _ = dispatchEvent(event: .mouseMove(move), cx: &cx)
    }

    public func listenerFor<T, E>(
        _ view: Entity<T>,
        _ f: @escaping @Sendable (inout T, E, inout Window, inout Context<T>) -> Void
    ) -> @MainActor @Sendable (E, inout Window, inout App) -> Void {
        let weakView = view.downgrade()
        return { (e: E, window: inout Window, cx: inout App) in
            _ = try? weakView.update(&cx) { entity, context in
                f(&entity, e, &window, &context)
            }
        }
    }

    public func handlerFor<E>(
        _ entity: Entity<E>,
        _ f: @escaping @Sendable (inout E, inout Window, inout Context<E>) -> Void
    ) -> @MainActor @Sendable (inout Window, inout App) -> Void {
        let weakEntity = entity.downgrade()
        return { (window: inout Window, cx: inout App) in
            _ = try? weakEntity.update(&cx) { target, context in
                f(&target, &window, &context)
            }
        }
    }

    public mutating func onWindowShouldClose(_ callback: @escaping () -> Bool) {
        windowShouldCloseCallbacks.append(callback)
    }

    // MARK: - Element Scoping & Keyed State

    public mutating func withId<R>(_ id: ElementId, _ f: (inout Window) -> R) -> R {
        elementIdStack.append(id)
        defer { _ = elementIdStack.removeLast() }
        return f(&self)
    }

    public mutating func withGlobalId<R>(_ id: GlobalElementId, _ f: (inout Window) -> R) -> R {
        elementIdStack.append(contentsOf: id.path)
        defer {
            for _ in id.path { _ = elementIdStack.removeLast() }
        }
        return f(&self)
    }

    public mutating func withElementNamespace<R>(_ namespace: ElementId, _ f: (inout Window) -> R) -> R {
        elementIdStack.append(namespace)
        defer { _ = elementIdStack.removeLast() }
        return f(&self)
    }

    public mutating func withAbsoluteElementOffset<R>(_ offset: Point<Pixels>, _ f: (inout Window) -> R) -> R {
        let prev = elementOffsetStack
        elementOffsetStack = [offset]
        defer { elementOffsetStack = prev }
        return f(&self)
    }

    public mutating func withElementOpacity<R>(_ opacity: Float?, _ f: (inout Window) -> R) -> R {
        guard let opacity = opacity else {
            return f(&self)
        }
        let prev = elementOpacity
        elementOpacity *= opacity
        defer { elementOpacity = prev }
        return f(&self)
    }

    public mutating func withElementOpacity<R>(_ opacity: Float, _ f: (inout Window) -> R) -> R {
        withElementOpacity(Optional(opacity), f)
    }

    public mutating func withOptionalElementState<State, R>(
        _ id: GlobalElementId?,
        _ f: (inout State?, inout Window) -> R
    ) -> (R, State?) {
        guard let id = id else {
            var state: State? = nil
            let result = f(&state, &self)
            return (result, state)
        }
        var state = elementStates[id] as? State
        accessedElementStates.append((id, ObjectIdentifier(State.self)))
        let result = f(&state, &self)
        if let state = state {
            elementStates[id] = state
        } else {
            elementStates.removeValue(forKey: id)
        }
        return (result, state)
    }

    public mutating func withTabGroup<R>(_ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public mutating func withTabGroup<R>(_ tabGroupIndex: Int?, _ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public mutating func withRenderedView<R>(_ viewId: EntityId, _ f: (inout Window) -> R) -> R {
        renderedEntityStack.append(viewId)
        defer { _ = renderedEntityStack.removeLast() }
        return f(&self)
    }

    public mutating func withImageCache<R>(_ cache: Any, _ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public func prepaintIndex() -> PrepaintStateIndex {
        PrepaintStateIndex(
            hitboxesIndex: nextFrame.hitboxes.count,
            tooltipsIndex: nextFrame.tooltipRequests.count,
            deferredDrawsIndex: nextFrame.deferredDraws.count,
            dispatchTreeIndex: nextFrame.dispatchTree.count,
            accessedElementStatesIndex: accessedElementStates.count,
            lineLayoutIndex: textSystem().layoutIndex()
        )
    }

    public mutating func reusePrepaint(_ range: Range<PrepaintStateIndex>) {
        if range.lowerBound.hitboxesIndex <= range.upperBound.hitboxesIndex &&
           range.upperBound.hitboxesIndex <= renderedFrame.hitboxes.count {
            nextFrame.hitboxes.append(contentsOf: renderedFrame.hitboxes[range.lowerBound.hitboxesIndex..<range.upperBound.hitboxesIndex])
        }
        if range.lowerBound.tooltipsIndex <= range.upperBound.tooltipsIndex &&
           range.upperBound.tooltipsIndex <= renderedFrame.tooltipRequests.count {
            nextFrame.tooltipRequests.append(contentsOf: renderedFrame.tooltipRequests[range.lowerBound.tooltipsIndex..<range.upperBound.tooltipsIndex])
        }
        textSystem().reuseLayouts(range.lowerBound.lineLayoutIndex..<range.upperBound.lineLayoutIndex)

        let reusedSubtree = nextFrame.dispatchTree.reuseSubtree(
            oldRange: range.lowerBound.dispatchTreeIndex..<range.upperBound.dispatchTreeIndex,
            source: &renderedFrame.dispatchTree,
            focus: focus
        )
        if reusedSubtree.containsFocus {
            nextFrame.focus = focus
        }
        if range.lowerBound.deferredDrawsIndex <= range.upperBound.deferredDrawsIndex &&
           range.upperBound.deferredDrawsIndex <= renderedFrame.deferredDraws.count {
            for draw in renderedFrame.deferredDraws[range.lowerBound.deferredDrawsIndex..<range.upperBound.deferredDrawsIndex] {
                nextFrame.deferredDraws.append(draw)
            }
        }
    }

    public func paintIndex() -> PaintIndex {
        PaintIndex(
            sceneIndex: nextFrame.scene.count,
            mouseListenersIndex: nextFrame.mouseListeners.count,
            inputHandlersIndex: nextFrame.inputHandlers.count,
            cursorStylesIndex: nextFrame.cursorStyles.count,
            accessedElementStatesIndex: accessedElementStates.count,
            tabHandleIndex: nextFrame.tabStops.paintIndex,
            lineLayoutIndex: textSystem().layoutIndex()
        )
    }

    public mutating func reusePaint(_ range: Range<PaintIndex>) {
        if range.lowerBound.cursorStylesIndex <= range.upperBound.cursorStylesIndex &&
           range.upperBound.cursorStylesIndex <= renderedFrame.cursorStyles.count {
            nextFrame.cursorStyles.append(contentsOf: renderedFrame.cursorStyles[range.lowerBound.cursorStylesIndex..<range.upperBound.cursorStylesIndex])
        }
        if range.lowerBound.inputHandlersIndex <= range.upperBound.inputHandlersIndex &&
           range.upperBound.inputHandlersIndex <= renderedFrame.inputHandlers.count {
            nextFrame.inputHandlers.append(contentsOf: renderedFrame.inputHandlers[range.lowerBound.inputHandlersIndex..<range.upperBound.inputHandlersIndex])
        }
        if range.lowerBound.mouseListenersIndex <= range.upperBound.mouseListenersIndex &&
           range.upperBound.mouseListenersIndex <= renderedFrame.mouseListeners.count {
            nextFrame.mouseListeners.append(contentsOf: renderedFrame.mouseListeners[range.lowerBound.mouseListenersIndex..<range.upperBound.mouseListenersIndex])
        }
        nextFrame.tabStops.replay(
            Array(renderedFrame.tabStops.insertionHistory[range.lowerBound.tabHandleIndex..<min(range.upperBound.tabHandleIndex, renderedFrame.tabStops.insertionHistory.count)])
        )
        textSystem().reuseLayouts(range.lowerBound.lineLayoutIndex..<range.upperBound.lineLayoutIndex)
        nextFrame.scene.replay(
            range: range.lowerBound.sceneIndex..<min(range.upperBound.sceneIndex, renderedFrame.scene.paintOperations.count),
            prevScene: renderedFrame.scene
        )
    }

    public mutating func withTextStyle<R>(_ style: TextStyleRefinement?, _ f: (inout Window) -> R) -> R {
        guard let style = style else {
            return f(&self)
        }
        textStyleStack.append(style)
        defer { _ = textStyleStack.removeLast() }
        return f(&self)
    }

    public mutating func withTextStyle<R>(_ style: TextStyleRefinement, _ f: (inout Window) -> R) -> R {
        withTextStyle(Optional(style), f)
    }

    public mutating func useKeyedState<T: Sendable>(_ key: String, _ initial: () -> T) -> T {
        let globalId = GlobalElementId(ElementId(named: key))
        return useState(globalId, initial)
    }

    public mutating func useAsset<A>(_ asset: A) {
        assetCache[ObjectIdentifier(A.self)] = asset
    }

    public func getAsset<A>(_ type: A.Type) -> A? {
        assetCache[ObjectIdentifier(A.self)] as? A
    }

    public func elementOffset() -> Point<Pixels> {
        elementOffsetStack.reduce(.zero) { point($0.x + $1.x, $0.y + $1.y) }
    }

    public mutating func setKeyContext(_ context: KeyContext) {
        nextFrame.dispatchTree.setKeyContext(context)
    }

    public mutating func setFocusHandle(_ handle: FocusHandle) {
        nextFrame.dispatchTree.setFocusId(handle.id)
    }

    public mutating func setViewId(_ viewId: EntityId) {
        nextFrame.dispatchTree.setViewId(viewId)
    }

    public func currentView() -> EntityId? {
        renderedEntityStack.last
    }

    public mutating func deferDrawWithTarget(
        priority: Int = 0,
        _ draw: @escaping @Sendable (inout Window, inout App) -> Void
    ) {
        nextFrame.deferredDraws.append(DeferredDraw(priority: priority, draw: draw))
    }

    // MARK: - Painting Primitives

    public mutating func paintLayer<R>(_ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public mutating func paintShadows(
        bounds: Bounds<Pixels>,
        cornerRadii: Corners<Pixels>,
        shadows: [BoxShadow]
    ) {
        for shadow in shadows {
            let shadowOrigin = point(
                bounds.origin.x + shadow.offset.x - shadow.spreadRadius,
                bounds.origin.y + shadow.offset.y - shadow.spreadRadius
            )
            let shadowSize = size(
                bounds.size.width + shadow.spreadRadius * 2,
                bounds.size.height + shadow.spreadRadius * 2
            )
            let shadowBounds = Bounds(origin: shadowOrigin, size: shadowSize)
            paintShadow(Shadow(
                order: 0,
                blurRadius: shadow.blurRadius.scale(scaleFactor),
                bounds: shadowBounds.scale(scaleFactor),
                cornerRadii: cornerRadii.scale(scaleFactor),
                contentMask: (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scaleFactor),
                color: shadow.color.opacity(elementOpacity)
            ))
        }
    }

    public mutating func paintPath(_ path: Path<Pixels>, color: Hsla) {
        var scaled = path.scale(scaleFactor)
        scaled.color = solidBackground(color)
        nextFrame.scene.insertPath(scaled)
    }

    public mutating func paintSvg(
        bounds: Bounds<Pixels>,
        path: String,
        color: Hsla
    ) {
        invalidator.debugAssertPaint()
        let scaledBounds = bounds.scale(scaleFactor)
        let mask = (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scaleFactor)
        let sprite = MonochromeSprite(
            bounds: Bounds(origin: scaledBounds.origin.map { $0.floor() }, size: scaledBounds.size.map { $0.ceil() }),
            contentMask: mask,
            color: color.opacity(elementOpacity),
            tile: AtlasTile(textureId: AtlasTextureId(index: 0, kind: .monochrome), tileId: TileId(0), bounds: Bounds(origin: .zero, size: .zero)),
            transformation: .unit
        )
        nextFrame.scene.insertMonochromeSprite(sprite)
    }

    public func textSystem() -> WindowTextSystem {
        if let ts = windowTextSystem {
            return ts
        }
        return WindowTextSystem(textSystem: TextSystem(platformTextSystem: NoopTextSystem()))
    }

    public func textStyle() -> TextStyle {
        var style = TextStyle()
        for refinement in textStyleStack {
            style.refine(with: refinement)
        }
        return style
    }

    public mutating func paintGlyph(
        origin: Point<Pixels>,
        fontId: FontId,
        glyphId: GlyphId,
        fontSize: Pixels,
        color: Hsla
    ) throws {
        invalidator.debugAssertPaint()
        let factor = scaleFactor
        let glyphOrigin = origin.scale(factor)

        let fractX = (glyphOrigin.x.value - glyphOrigin.x.value.rounded(.down)) * 4.0
        let fractY = (glyphOrigin.y.value - glyphOrigin.y.value.rounded(.down)) * 4.0
        let subpixelVariant = Point(x: UInt8(fractX.rounded(.down)), y: UInt8(fractY.rounded(.down)))

        let params = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphId,
            fontSize: fontSize,
            subpixelVariant: subpixelVariant,
            scaleFactor: factor,
            isEmoji: false,
            subpixelRendering: false
        )

        let rasterBounds = try textSystem().rasterBounds(params: params)
        if !rasterBounds.isZero {
            if let tile = try spriteAtlas.getOrInsertWith(key: .glyph(params), build: {
                let (size, bytes) = try self.textSystem().rasterizeGlyph(params: params)
                return (size, Data(bytes))
            }) {
                let bounds = Bounds<ScaledPixels>(
                    origin: Point(
                        x: ScaledPixels(glyphOrigin.x.value.rounded(.down)) + ScaledPixels(Float(rasterBounds.origin.x.value)),
                        y: ScaledPixels(glyphOrigin.y.value.rounded(.down)) + ScaledPixels(Float(rasterBounds.origin.y.value))
                    ),
                    size: Size(
                        width: ScaledPixels(Float(tile.bounds.size.width.value)),
                        height: ScaledPixels(Float(tile.bounds.size.height.value))
                    )
                )
                let monochromeSprite = MonochromeSprite(
                    order: 0,
                    bounds: bounds,
                    contentMask: (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(factor),
                    color: color.opacity(elementOpacity),
                    tile: tile,
                    transformation: .unit
                )
                nextFrame.scene.insertMonochromeSprite(monochromeSprite)
            }
        }
    }

    public mutating func paintEmoji(
        origin: Point<Pixels>,
        fontId: FontId,
        glyphId: GlyphId,
        fontSize: Pixels
    ) throws {
        invalidator.debugAssertPaint()
        let factor = scaleFactor
        let glyphOrigin = origin.scale(factor)

        let params = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphId,
            fontSize: fontSize,
            subpixelVariant: Point(x: 0, y: 0),
            scaleFactor: factor,
            isEmoji: true,
            subpixelRendering: false
        )

        let rasterBounds = try textSystem().rasterBounds(params: params)
        if !rasterBounds.isZero {
            if let tile = try spriteAtlas.getOrInsertWith(key: .glyph(params), build: {
                let (size, bytes) = try self.textSystem().rasterizeGlyph(params: params)
                return (size, Data(bytes))
            }) {
                let bounds = Bounds<ScaledPixels>(
                    origin: Point(
                        x: ScaledPixels(glyphOrigin.x.value.rounded(.down)) + ScaledPixels(Float(rasterBounds.origin.x.value)),
                        y: ScaledPixels(glyphOrigin.y.value.rounded(.down)) + ScaledPixels(Float(rasterBounds.origin.y.value))
                    ),
                    size: Size(
                        width: ScaledPixels(Float(tile.bounds.size.width.value)),
                        height: ScaledPixels(Float(tile.bounds.size.height.value))
                    )
                )
                let polychromeSprite = PolychromeSprite(
                    order: 0,
                    bounds: bounds,
                    contentMask: (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(factor),
                    tile: tile
                )
                nextFrame.scene.insertPolychromeSprite(polychromeSprite)
            }
        }
    }

    public mutating func paintImage(
        bounds: Bounds<Pixels>,
        cornerRadii: Corners<Pixels> = .zero,
        image: Image
    ) {
        invalidator.debugAssertPaint()
        let scaledBounds = bounds.scale(scaleFactor)
        let mask = (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scaleFactor)
        let sprite = PolychromeSprite(
            grayscale: 0,
            opacity: elementOpacity,
            bounds: Bounds(origin: scaledBounds.origin.map { $0.floor() }, size: scaledBounds.size.map { $0.ceil() }),
            contentMask: mask,
            cornerRadii: cornerRadii.scale(scaleFactor),
            tile: AtlasTile(textureId: AtlasTextureId(index: 0, kind: .polychrome), tileId: TileId(0), bounds: Bounds(origin: .zero, size: .zero))
        )
        nextFrame.scene.insertPolychromeSprite(sprite)
    }

    public mutating func dropImage(_ image: RenderImage) {
        invalidator.setDirty(true)
    }

    public mutating func dropImage(_ image: Image) {
        invalidator.setDirty(true)
    }

    public mutating func paintQuad(_ paintQuad: PaintQuad) {
        let q = Quad(
            borderStyle: paintQuad.borderStyle,
            bounds: paintQuad.bounds.scale(scaleFactor),
            contentMask: (contentMaskStack.last ?? ContentMask(bounds: .zero)).scale(scaleFactor),
            background: paintQuad.background.color() ?? solidBackground(transparentBlack()),
            borderColor: paintQuad.borderColor,
            cornerRadii: paintQuad.cornerRadii.scale(scaleFactor),
            borderWidths: paintQuad.borderWidths.scale(scaleFactor)
        )
        nextFrame.scene.insertQuad(q)
    }

    // MARK: - Lifecycle, Tasks & Platform Observers

    @MainActor
    public mutating func `defer`(_ cx: inout App, _ callback: @escaping (inout Window, inout App) -> Void) {
        cx.defer { [weak platformWindow] _ in
            guard platformWindow != nil else { return }
        }
    }

    @MainActor
    public mutating func observe<E: AnyObject>(
        _ entity: Entity<E>,
        _ cx: inout App,
        _ callback: @escaping (inout Window, inout App) -> Void
    ) -> Subscription {
        return cx.observe(entity) { [weak platformWindow] _, _ in
            guard platformWindow != nil else { return false }
            return true
        }
    }

    @MainActor
    public mutating func subscribe<E: AnyObject, Evt>(
        _ entity: Entity<E>,
        _ cx: inout App,
        _ callback: @escaping (inout Window, inout App, Evt) -> Void
    ) -> Subscription {
        return cx.subscribe(entity) { [weak platformWindow] (_, _: Evt, _) -> Bool in
            guard platformWindow != nil else { return false }
            return true
        }
    }

    public mutating func observeRelease<E: AnyObject>(
        _ entity: Entity<E>,
        _ cx: inout App,
        _ callback: @escaping (inout Window, inout App) -> Void
    ) -> Subscription {
        return Subscription {}
    }

    @MainActor
    public mutating func observeGlobal<G: Global>(
        _ type: G.Type = G.self,
        _ cx: inout App,
        _ observer: @escaping (inout Window, inout App) -> Void
    ) -> Subscription {
        return cx.observeGlobal(G.self) { [weak platformWindow] _ in
            guard platformWindow != nil else { return false }
            return true
        }
    }

    @MainActor
    public func toAsync(_ cx: App) -> AsyncApp {
        cx.toAsync()
    }

    @MainActor
    public func spawn<R: Sendable>(_ cx: App, _ f: @escaping @Sendable (AsyncApp) async -> R) -> Task<R> {
        cx.spawn(f)
    }

    @MainActor
    public func spawnWithPriority<R: Sendable>(
        _ priority: Priority,
        _ cx: App,
        _ f: @escaping @Sendable (AsyncApp) async -> R
    ) -> Task<R> {
        cx.spawnWithPriority(priority, f)
    }

    public mutating func transact<R>(_ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public mutating func setRemSize(_ size: Pixels) {
        self.remSize = size
        invalidator.setDirty(true)
    }

    public mutating func withRemSize<R>(_ size: Pixels, _ f: (inout Window) -> R) -> R {
        remSizeOverrideStack.append(remSize)
        remSize = size
        defer {
            remSize = remSizeOverrideStack.removeLast()
        }
        return f(&self)
    }

    public func lineHeight() -> Pixels {
        px(20.0)
    }

    @MainActor
    public mutating func prompt(
        level: PromptLevel = .info,
        message: String,
        detail: String? = nil,
        actions: [PromptButton] = [],
        cx: inout App
    ) -> Task<Int?> {
        // PORT NOTE: Holds continuation for async prompt response within checked continuation scope.
        final class ResponseBox: @unchecked Sendable {
            var continuation: CheckedContinuation<Int?, Never>?
        }
        let box = ResponseBox()
        let handle = PromptHandle.withHandler { index in
            box.continuation?.resume(returning: index)
        }
        _ = fallbackPromptRenderer(
            level: level,
            message: message,
            detail: detail,
            actions: actions,
            handle: handle,
            window: &self,
            cx: &cx
        )
        return cx.spawn { _ in
            await withCheckedContinuation { continuation in
                box.continuation = continuation
            }
        }
    }

    public mutating func renderToImage(_ size: Size<Pixels>, _ cx: inout App) -> Image? {
        platformWindow.renderToImage(scene: renderedFrame.scene)
    }

    public mutating func requestDecorations(_ decorations: WindowDecorations) {
        platformWindow.requestDecorations(decorations)
    }

    public mutating func startWindowResize(_ edge: ResizeEdge) {
        platformWindow.startWindowResize(edge)
    }

    public mutating func startWindowMove() {
        platformWindow.startWindowMove()
    }

    public func safeAreaInsets() -> EdgeInsets<Pixels> {
        EdgeInsets.zero(value: .zero)
    }

    public mutating func showWindowMenu(_ position: Point<Pixels>) {
        platformWindow.showWindowMenu(position)
    }

    public func windowDecorations() -> WindowDecorations {
        platformWindow.windowDecorations()
    }

    public func windowControls() -> WindowControls {
        platformWindow.windowControls()
    }

    public mutating func setAppId(_ appId: String) {
        platformWindow.setAppId(appId)
    }

    public mutating func setWindowEdited(_ edited: Bool) {
        platformWindow.setEdited(edited)
    }

    public func display(_ cx: App? = nil) -> (any PlatformDisplay)? {
        platformWindow.display()
    }

    public mutating func showCharacterPalette() {
        platformWindow.showCharacterPalette()
    }

    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? {
        nativeViewOverrideStack.last ?? platformWindow.rawNativeViewPtr()
    }

    public func nativeToolbarItemBounds() -> [String: Bounds<Pixels>] {
        platformWindow.nativeToolbarItemBounds()
    }

    public mutating func pushNativeViewOverride(_ ptr: UnsafeMutableRawPointer) {
        nativeViewOverrideStack.append(ptr)
    }

    public mutating func popNativeViewOverride() {
        _ = nativeViewOverrideStack.popLast()
    }

    public mutating func registerSurface(_ surface: GpuiSurfaceHandle) {
        surfaces[surface.id] = SurfaceState(id: surface.id, scaleFactor: scaleFactor, bounds: Bounds(origin: .zero, size: viewportSize))
    }

    public mutating func unregisterSurface(_ id: SurfaceId) {
        surfaces.removeValue(forKey: id)
    }

    public func surfaceNativeViewPtr(_ id: SurfaceId) -> UnsafeMutableRawPointer? {
        rawNativeViewPtr()
    }

    public mutating func invalidateSurface(_ id: SurfaceId) {
        invalidator.setDirty(true)
    }

    public mutating func updateSurfaceRootView(_ id: SurfaceId, _ rootView: AnyView) {
        invalidator.setDirty(true)
    }

    public func gpuSpecs() -> GpuSpecs? {
        platformWindow.gpuSpecs()
    }

    public mutating func titlebarDoubleClick() {
        platformWindow.zoom()
    }

    public func tabbedWindows() -> [AnyWindowHandle] {
        platformWindow.tabbedWindows() ?? []
    }

    public func tabBarVisible() -> Bool {
        platformWindow.tabBarVisible()
    }

    public mutating func mergeAllWindows() {
        platformWindow.mergeAllWindows()
    }

    public mutating func moveTabToNewWindow() {
        platformWindow.moveTabToNewWindow()
    }

    public mutating func toggleWindowTabOverview() {
        platformWindow.toggleWindowTabOverview()
    }

    public mutating func setTabbingIdentifier(_ identifier: String) {
        platformWindow.setTabbingIdentifier(identifier)
    }

    public mutating func toggleInspector(_ cx: inout App) {
        isInspectorPickingState.toggle()
        invalidator.setDirty(true)
    }

    public func isInspectorPicking(_ cx: App) -> Bool {
        isInspectorPickingState
    }

    public mutating func withInspectorState<R>(_ f: (inout Window) -> R) -> R {
        f(&self)
    }

    public func buildInspectorElementId() -> ElementId? {
        elementIdStack.last
    }

    public mutating func insertInspectorHitbox(bounds: Bounds<Pixels>) {
        _ = insertHitbox(bounds: bounds, behavior: .normal)
    }
}
