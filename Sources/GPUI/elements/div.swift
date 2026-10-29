// Ported from: crates/gpui/src/elements/div.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Refineable

// MARK: - StyleRefinementBox

/// A heap-allocated reference box for StyleRefinement matching upstream Box<StyleRefinement>.
// PORT NOTE: StyleRefinementBox stores StyleRefinement on the heap matching upstream Box<StyleRefinement>
// to prevent deep element trees from overflowing the thread stack (especially on Windows 1MB default stack).
public final class StyleRefinementBox: @unchecked Sendable, Equatable {
    public var value: StyleRefinement

    public init(_ value: StyleRefinement = StyleRefinement()) {
        self.value = value
    }

    public static func == (lhs: StyleRefinementBox, rhs: StyleRefinementBox) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - GroupStyle

/// The styling information for a given group.
public struct GroupStyle: Sendable, Equatable {
    /// The identifier for this group.
    public var group: SharedString

    /// The specific style refinement that this group would apply to its children.
    // PORT NOTE: GroupStyle.style is heap-boxed matching upstream Box<StyleRefinement>.
    private var styleBox: StyleRefinementBox

    public var style: StyleRefinement {
        get { styleBox.value }
        set {
            if isKnownUniquelyReferenced(&styleBox) {
                styleBox.value = newValue
            } else {
                styleBox = StyleRefinementBox(newValue)
            }
        }
        _modify {
            if !isKnownUniquelyReferenced(&styleBox) {
                styleBox = StyleRefinementBox(styleBox.value)
            }
            yield &styleBox.value
        }
    }

    public init(group: SharedString, style: StyleRefinement) {
        self.group = group
        self.styleBox = StyleRefinementBox(style)
    }

    public init(group: SharedString, styleBox: StyleRefinementBox) {
        self.group = group
        self.styleBox = styleBox
    }

    public static func == (lhs: GroupStyle, rhs: GroupStyle) -> Bool {
        lhs.group == rhs.group && lhs.styleBox.value == rhs.styleBox.value
    }
}

// MARK: - DragMoveEvent

/// An event for when a drag is moving over this element, with the given state type.
// PORT NOTE: DragMoveEvent wraps Any dynamic payload matching upstream Arc<dyn Any>.
public struct DragMoveEvent<T>: @unchecked Sendable {
    /// The mouse move event that triggered this drag move event.
    public var event: MouseMoveEvent

    /// The bounds of this element.
    public var bounds: Bounds<Pixels>

    private var draggedItemValue: Any

    public init(event: MouseMoveEvent, bounds: Bounds<Pixels>, draggedItem: Any) {
        self.event = event
        self.bounds = bounds
        self.draggedItemValue = draggedItem
    }

    @MainActor
    public func drag(_ cx: App) -> T {
        guard let drag = cx.activeDrag, let val = drag.value as? T else {
            fatalError("DragMoveEvent is only valid when the stored active drag is of the same type.")
        }
        return val
    }

    /// An item that is about to be dropped.
    public func draggedItem() -> Any {
        draggedItemValue
    }
}

// MARK: - Listener Typealiases

public typealias MouseDownListener = @Sendable (MouseDownEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias MouseUpListener = @Sendable (MouseUpEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias MousePressureListener = @Sendable (MousePressureEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias MouseMoveListener = @Sendable (MouseMoveEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias ScrollWheelListener = @Sendable (ScrollWheelEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias PinchListener = @Sendable (PinchEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias RotationListener = @Sendable (RotationEvent, DispatchPhase, Hitbox, inout Window, inout App) -> Void
public typealias ClickListener = @Sendable (ClickEvent, inout Window, inout App) -> Void
public typealias DragListener = @Sendable (Any, Point<Pixels>, inout Window, inout App) -> AnyView

// PORT NOTE: Wrapper for drag value and listener to satisfy Sendable closure capture requirements
public struct DragInfo: @unchecked Sendable {
    public var value: Any
    public var listener: DragListener

    public init(value: Any, listener: @escaping DragListener) {
        self.value = value
        self.listener = listener
    }
}
public typealias DropListener = @Sendable (Any, inout Window, inout App) -> Void
public typealias CanDropPredicate = @Sendable (Any, inout Window, inout App) -> Bool
public typealias KeyDownListener = @Sendable (KeyDownEvent, DispatchPhase, inout Window, inout App) -> Void
public typealias KeyUpListener = @Sendable (KeyUpEvent, DispatchPhase, inout Window, inout App) -> Void
public typealias ModifiersChangedListener = @Sendable (ModifiersChangedEvent, inout Window, inout App) -> Void
public typealias ActionListener = @Sendable (any Action, DispatchPhase, inout Window, inout App) -> Void

// MARK: - TooltipBuilder

// PORT NOTE: TooltipBuilder holds a closure constructing AnyView matching upstream Box<dyn Fn(...) -> AnyView>.
public struct TooltipBuilder: @unchecked Sendable {
    public var build: @Sendable (inout Window, inout App) -> AnyView
    public var hoverable: Bool

    public init(build: @escaping @Sendable (inout Window, inout App) -> AnyView, hoverable: Bool) {
        self.build = build
        self.hoverable = hoverable
    }
}

// MARK: - ActiveTooltip

// PORT NOTE: ActiveTooltip manages tooltip presentation and hide timers matching upstream Task<()>.
public enum ActiveTooltip: @unchecked Sendable {
    /// Currently delaying before showing the tooltip.
    case waitingForShow(_Concurrency.Task<Void, Never>?)
    /// Tooltip is visible, element was hovered or for hoverable tooltips, the tooltip was hovered.
    case visible(tooltip: AnyTooltip, isHoverable: Bool)
    /// Tooltip is visible and hoverable, but the mouse is no longer hovering. Currently delaying before hiding it.
    case waitingForHide(tooltip: AnyTooltip, task: _Concurrency.Task<Void, Never>?)
}

public func clearActiveTooltip(
    _ activeTooltip: inout ActiveTooltip?,
    _ window: inout Window
) {
    if let current = activeTooltip {
        switch current {
        case .waitingForShow:
            break
        case .visible, .waitingForHide:
            window.refresh()
        }
        activeTooltip = nil
    }
}

public func clearActiveTooltipIfNotHoverable(
    _ activeTooltip: inout ActiveTooltip?,
    _ window: inout Window
) {
    guard let current = activeTooltip else { return }
    var shouldClear = false
    switch current {
    case .waitingForShow, .waitingForHide:
        shouldClear = false
    case .visible(_, let isHoverable):
        shouldClear = !isHoverable
    }
    if shouldClear {
        activeTooltip = nil
        window.refresh()
    }
}

public func setTooltipOnWindow(
    _ activeTooltip: ActiveTooltip?,
    _ window: inout Window
) -> TooltipId? {
    guard let active = activeTooltip else { return nil }
    let tooltip: AnyTooltip
    switch active {
    case .waitingForShow:
        return nil
    case .visible(let tt, _):
        tooltip = tt
    case .waitingForHide(let tt, _):
        tooltip = tt
    }
    return window.setTooltip(tooltip)
}

public func registerTooltipMouseHandlers(
    _ activeTooltipHolder: InteractiveElementState,
    _ tooltipId: TooltipId?,
    _ buildTooltip: @escaping @Sendable (inout Window, inout App) -> (AnyView, Bool)?,
    _ checkIsHovered: @escaping @Sendable (Window) -> Bool,
    _ checkIsHoveredDuringPrepaint: @escaping @Sendable (Window) -> Bool,
    _ window: inout Window
) {
    window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
        if checkIsHovered(window) {
            if activeTooltipHolder.activeTooltip == nil {
                if let (view, hoverable) = buildTooltip(&window, &cx) {
                    let tooltip = AnyTooltip(
                        view: view,
                        mousePosition: window.mousePosition
                    )
                    activeTooltipHolder.activeTooltip = .visible(tooltip: tooltip, isHoverable: hoverable)
                    window.refresh()
                }
            }
        } else {
            clearActiveTooltipIfNotHoverable(&activeTooltipHolder.activeTooltip, &window)
        }
    }

    window.onMouseEvent { (event: MouseDownEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
        if let tooltipId = tooltipId, tooltipId.isHovered(window) {
            return
        }
        clearActiveTooltipIfNotHoverable(&activeTooltipHolder.activeTooltip, &window)
    }

    window.onMouseEvent { (event: ScrollWheelEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
        if let tooltipId = tooltipId, tooltipId.isHovered(window) {
            return
        }
        clearActiveTooltipIfNotHoverable(&activeTooltipHolder.activeTooltip, &window)
    }
}

// MARK: - Element Clicked and Hover State

/// Whether or not the element or a group that contains it is clicked by the mouse.
public struct ElementClickedState: Sendable, Equatable {
    public var group: Bool
    public var element: Bool

    public init(group: Bool = false, element: Bool = false) {
        self.group = group
        self.element = element
    }

    public var isClicked: Bool {
        group || element
    }
}

/// Whether or not the element or a group that contains it is hovered.
public struct ElementHoverState: Sendable, Equatable {
    public var group: Bool
    public var element: Bool

    public init(group: Bool = false, element: Bool = false) {
        self.group = group
        self.element = element
    }
}

// MARK: - InteractiveElementState

/// The per-frame state of an interactive element.
// PORT NOTE: InteractiveElementState holds per-frame state across renders matching upstream InteractiveElementState.
public final class InteractiveElementState: @unchecked Sendable {
    public var focusHandle: FocusHandle?
    public var clickedState: ElementClickedState = ElementClickedState()
    public var hoverState: ElementHoverState = ElementHoverState()
    public var hoverListenerState: Bool = false
    public var pendingMouseDown: MouseDownEvent?
    public var scrollOffset: Point<Pixels> = .zero
    public var activeTooltip: ActiveTooltip?

    public init() {}
}

// MARK: - GroupHitboxes

// PORT NOTE: GroupHitboxes stores active hitbox stacks for named groups across frame layout/paint.
public struct GroupHitboxes: Global, DefaultInitializable, @unchecked Sendable {
    public var hitboxes: [SharedString: [HitboxId]] = [:]

    public init() {}

    @MainActor
    public static func get(_ name: SharedString, _ cx: inout App) -> HitboxId? {
        let global = cx.defaultGlobal(GroupHitboxes.self)
        return global.hitboxes[name]?.last
    }

    @MainActor
    public static func push(_ name: SharedString, _ hitboxId: HitboxId, _ cx: inout App) {
        var global = cx.defaultGlobal(GroupHitboxes.self)
        global.hitboxes[name, default: []].append(hitboxId)
        cx.setGlobal(global)
    }

    @MainActor
    public static func pop(_ name: SharedString, _ cx: inout App) {
        var global = cx.defaultGlobal(GroupHitboxes.self)
        _ = global.hitboxes[name]?.popLast()
        cx.setGlobal(global)
    }
}

// MARK: - InteractivityStorage

// PORT NOTE: InteractivityStorage holds interactivity state on the heap matching upstream Interactivity,
// avoiding deep element stack bloat and Windows 1MB thread stack overflows.
final class InteractivityStorage: @unchecked Sendable {
    var elementId: ElementId?
    var active: Bool?
    var hovered: Bool?
    var tooltipId: TooltipId?
    var contentSize: Size<Pixels> = .zero
    var keyContext: KeyContext?
    var focusable: Bool = false
    var trackedFocusHandle: FocusHandle?
    var trackedScrollHandle: ScrollHandle?
    var scrollAnchor: ScrollAnchor?
    var scrollOffset: Point<Pixels>?
    var group: SharedString?

    var baseStyleBox: StyleRefinementBox = StyleRefinementBox()
    var focusStyleBox: StyleRefinementBox?
    var inFocusStyleBox: StyleRefinementBox?
    var focusVisibleStyleBox: StyleRefinementBox?
    var hoverStyleBox: StyleRefinementBox?
    var groupHoverStyle: GroupStyle?
    var activeStyleBox: StyleRefinementBox?
    var groupActiveStyle: GroupStyle?
    var dragOverStyles: [(ObjectIdentifier, @Sendable (Any, inout Window, inout App) -> StyleRefinement)] = []
    var groupDragOverStyles: [(ObjectIdentifier, GroupStyle)] = []

    var mouseDownListeners: [MouseDownListener] = []
    var mouseUpListeners: [MouseUpListener] = []
    var mousePressureListeners: [MousePressureListener] = []
    var mouseMoveListeners: [MouseMoveListener] = []
    var scrollWheelListeners: [ScrollWheelListener] = []
    var pinchListeners: [PinchListener] = []
    var rotationListeners: [RotationListener] = []
    var keyDownListeners: [KeyDownListener] = []
    var keyUpListeners: [KeyUpListener] = []
    var modifiersChangedListeners: [ModifiersChangedListener] = []
    var actionListeners: [(ObjectIdentifier, ActionListener)] = []
    var dropListeners: [(ObjectIdentifier, DropListener)] = []
    var canDropPredicate: CanDropPredicate?
    var clickListeners: [ClickListener] = []
    var auxClickListeners: [ClickListener] = []
    var dragListener: DragInfo?
    var hoverListener: (@Sendable (Bool, inout Window, inout App) -> Void)?
    var tooltipBuilder: TooltipBuilder?
    var windowControl: WindowControlArea?
    var hitboxBehavior: HitboxBehavior = .normal
    var tabIndex: Int?
    var tabGroup: Bool = false
    var tabStop: Bool = false
    var sourceLocationValue: String?

    init(file: String = #fileID, line: Int = #line) {
        #if DEBUG
        self.sourceLocationValue = "\(file):\(line)"
        #else
        self.sourceLocationValue = nil
        #endif
    }

    init(copying other: InteractivityStorage) {
        self.elementId = other.elementId
        self.active = other.active
        self.hovered = other.hovered
        self.tooltipId = other.tooltipId
        self.contentSize = other.contentSize
        self.keyContext = other.keyContext
        self.focusable = other.focusable
        self.trackedFocusHandle = other.trackedFocusHandle
        self.trackedScrollHandle = other.trackedScrollHandle
        self.scrollAnchor = other.scrollAnchor
        self.scrollOffset = other.scrollOffset
        self.group = other.group

        self.baseStyleBox = other.baseStyleBox
        self.focusStyleBox = other.focusStyleBox
        self.inFocusStyleBox = other.inFocusStyleBox
        self.focusVisibleStyleBox = other.focusVisibleStyleBox
        self.hoverStyleBox = other.hoverStyleBox
        self.groupHoverStyle = other.groupHoverStyle
        self.activeStyleBox = other.activeStyleBox
        self.groupActiveStyle = other.groupActiveStyle
        self.dragOverStyles = other.dragOverStyles
        self.groupDragOverStyles = other.groupDragOverStyles

        self.mouseDownListeners = other.mouseDownListeners
        self.mouseUpListeners = other.mouseUpListeners
        self.mousePressureListeners = other.mousePressureListeners
        self.mouseMoveListeners = other.mouseMoveListeners
        self.scrollWheelListeners = other.scrollWheelListeners
        self.pinchListeners = other.pinchListeners
        self.rotationListeners = other.rotationListeners
        self.keyDownListeners = other.keyDownListeners
        self.keyUpListeners = other.keyUpListeners
        self.modifiersChangedListeners = other.modifiersChangedListeners
        self.actionListeners = other.actionListeners
        self.dropListeners = other.dropListeners
        self.canDropPredicate = other.canDropPredicate
        self.clickListeners = other.clickListeners
        self.auxClickListeners = other.auxClickListeners
        self.dragListener = other.dragListener
        self.hoverListener = other.hoverListener
        self.tooltipBuilder = other.tooltipBuilder
        self.windowControl = other.windowControl
        self.hitboxBehavior = other.hitboxBehavior
        self.tabIndex = other.tabIndex
        self.tabGroup = other.tabGroup
        self.tabStop = other.tabStop
        self.sourceLocationValue = other.sourceLocationValue
    }
}

// MARK: - Interactivity

/// The interactivity struct. Powers all of the general-purpose interactivity in the `Div` element.
// PORT NOTE: Interactivity wraps heap storage with copy-on-write semantics matching upstream
// Box<StyleRefinement> to keep stack frame size tiny (8 bytes) and prevent Windows 1MB thread stack overflows.
public struct Interactivity: @unchecked Sendable {
    internal var storage: InteractivityStorage

    internal mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = InteractivityStorage(copying: storage)
        }
    }

    public var elementId: ElementId? {
        get { storage.elementId }
        set { ensureUnique(); storage.elementId = newValue }
    }
    public var active: Bool? {
        get { storage.active }
        set { ensureUnique(); storage.active = newValue }
    }
    public var hovered: Bool? {
        get { storage.hovered }
        set { ensureUnique(); storage.hovered = newValue }
    }
    public var tooltipId: TooltipId? {
        get { storage.tooltipId }
        set { ensureUnique(); storage.tooltipId = newValue }
    }
    public var contentSize: Size<Pixels> {
        get { storage.contentSize }
        set { ensureUnique(); storage.contentSize = newValue }
    }
    public var keyContext: KeyContext? {
        get { storage.keyContext }
        set { ensureUnique(); storage.keyContext = newValue }
    }
    public var focusable: Bool {
        get { storage.focusable }
        set { ensureUnique(); storage.focusable = newValue }
    }
    public var trackedFocusHandle: FocusHandle? {
        get { storage.trackedFocusHandle }
        set { ensureUnique(); storage.trackedFocusHandle = newValue }
    }
    public var trackedScrollHandle: ScrollHandle? {
        get { storage.trackedScrollHandle }
        set { ensureUnique(); storage.trackedScrollHandle = newValue }
    }
    public var scrollAnchor: ScrollAnchor? {
        get { storage.scrollAnchor }
        set { ensureUnique(); storage.scrollAnchor = newValue }
    }
    public var scrollOffset: Point<Pixels>? {
        get { storage.scrollOffset }
        set { ensureUnique(); storage.scrollOffset = newValue }
    }
    public var group: SharedString? {
        get { storage.group }
        set { ensureUnique(); storage.group = newValue }
    }

    public var baseStyle: StyleRefinement {
        get { storage.baseStyleBox.value }
        set {
            ensureUnique()
            if isKnownUniquelyReferenced(&storage.baseStyleBox) {
                storage.baseStyleBox.value = newValue
            } else {
                storage.baseStyleBox = StyleRefinementBox(newValue)
            }
        }
        _modify {
            ensureUnique()
            if !isKnownUniquelyReferenced(&storage.baseStyleBox) {
                storage.baseStyleBox = StyleRefinementBox(storage.baseStyleBox.value)
            }
            yield &storage.baseStyleBox.value
        }
    }

    public var focusStyle: StyleRefinement? {
        get { storage.focusStyleBox?.value }
        set {
            ensureUnique()
            if let newValue {
                if let box = storage.focusStyleBox, isKnownUniquelyReferenced(&storage.focusStyleBox) {
                    box.value = newValue
                } else {
                    storage.focusStyleBox = StyleRefinementBox(newValue)
                }
            } else {
                storage.focusStyleBox = nil
            }
        }
        _modify {
            ensureUnique()
            var current = storage.focusStyleBox?.value
            yield &current
            if let current {
                if let box = storage.focusStyleBox, isKnownUniquelyReferenced(&storage.focusStyleBox) {
                    box.value = current
                } else {
                    storage.focusStyleBox = StyleRefinementBox(current)
                }
            } else {
                storage.focusStyleBox = nil
            }
        }
    }

    public var inFocusStyle: StyleRefinement? {
        get { storage.inFocusStyleBox?.value }
        set {
            ensureUnique()
            if let newValue {
                if let box = storage.inFocusStyleBox, isKnownUniquelyReferenced(&storage.inFocusStyleBox) {
                    box.value = newValue
                } else {
                    storage.inFocusStyleBox = StyleRefinementBox(newValue)
                }
            } else {
                storage.inFocusStyleBox = nil
            }
        }
        _modify {
            ensureUnique()
            var current = storage.inFocusStyleBox?.value
            yield &current
            if let current {
                if let box = storage.inFocusStyleBox, isKnownUniquelyReferenced(&storage.inFocusStyleBox) {
                    box.value = current
                } else {
                    storage.inFocusStyleBox = StyleRefinementBox(current)
                }
            } else {
                storage.inFocusStyleBox = nil
            }
        }
    }

    public var focusVisibleStyle: StyleRefinement? {
        get { storage.focusVisibleStyleBox?.value }
        set {
            ensureUnique()
            if let newValue {
                if let box = storage.focusVisibleStyleBox, isKnownUniquelyReferenced(&storage.focusVisibleStyleBox) {
                    box.value = newValue
                } else {
                    storage.focusVisibleStyleBox = StyleRefinementBox(newValue)
                }
            } else {
                storage.focusVisibleStyleBox = nil
            }
        }
        _modify {
            ensureUnique()
            var current = storage.focusVisibleStyleBox?.value
            yield &current
            if let current {
                if let box = storage.focusVisibleStyleBox, isKnownUniquelyReferenced(&storage.focusVisibleStyleBox) {
                    box.value = current
                } else {
                    storage.focusVisibleStyleBox = StyleRefinementBox(current)
                }
            } else {
                storage.focusVisibleStyleBox = nil
            }
        }
    }

    public var hoverStyle: StyleRefinement? {
        get { storage.hoverStyleBox?.value }
        set {
            ensureUnique()
            if let newValue {
                if let box = storage.hoverStyleBox, isKnownUniquelyReferenced(&storage.hoverStyleBox) {
                    box.value = newValue
                } else {
                    storage.hoverStyleBox = StyleRefinementBox(newValue)
                }
            } else {
                storage.hoverStyleBox = nil
            }
        }
        _modify {
            ensureUnique()
            var current = storage.hoverStyleBox?.value
            yield &current
            if let current {
                if let box = storage.hoverStyleBox, isKnownUniquelyReferenced(&storage.hoverStyleBox) {
                    box.value = current
                } else {
                    storage.hoverStyleBox = StyleRefinementBox(current)
                }
            } else {
                storage.hoverStyleBox = nil
            }
        }
    }

    public var groupHoverStyle: GroupStyle? {
        get { storage.groupHoverStyle }
        set { ensureUnique(); storage.groupHoverStyle = newValue }
        _modify {
            ensureUnique()
            yield &storage.groupHoverStyle
        }
    }

    public var activeStyle: StyleRefinement? {
        get { storage.activeStyleBox?.value }
        set {
            ensureUnique()
            if let newValue {
                if let box = storage.activeStyleBox, isKnownUniquelyReferenced(&storage.activeStyleBox) {
                    box.value = newValue
                } else {
                    storage.activeStyleBox = StyleRefinementBox(newValue)
                }
            } else {
                storage.activeStyleBox = nil
            }
        }
        _modify {
            ensureUnique()
            var current = storage.activeStyleBox?.value
            yield &current
            if let current {
                if let box = storage.activeStyleBox, isKnownUniquelyReferenced(&storage.activeStyleBox) {
                    box.value = current
                } else {
                    storage.activeStyleBox = StyleRefinementBox(current)
                }
            } else {
                storage.activeStyleBox = nil
            }
        }
    }

    public var groupActiveStyle: GroupStyle? {
        get { storage.groupActiveStyle }
        set { ensureUnique(); storage.groupActiveStyle = newValue }
        _modify {
            ensureUnique()
            yield &storage.groupActiveStyle
        }
    }

    public var dragOverStyles: [(ObjectIdentifier, @Sendable (Any, inout Window, inout App) -> StyleRefinement)] {
        get { storage.dragOverStyles }
        set { ensureUnique(); storage.dragOverStyles = newValue }
        _modify {
            ensureUnique()
            yield &storage.dragOverStyles
        }
    }

    public var groupDragOverStyles: [(ObjectIdentifier, GroupStyle)] {
        get { storage.groupDragOverStyles }
        set { ensureUnique(); storage.groupDragOverStyles = newValue }
        _modify {
            ensureUnique()
            yield &storage.groupDragOverStyles
        }
    }

    public var mouseDownListeners: [MouseDownListener] {
        get { storage.mouseDownListeners }
        set { ensureUnique(); storage.mouseDownListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.mouseDownListeners
        }
    }

    public var mouseUpListeners: [MouseUpListener] {
        get { storage.mouseUpListeners }
        set { ensureUnique(); storage.mouseUpListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.mouseUpListeners
        }
    }

    public var mousePressureListeners: [MousePressureListener] {
        get { storage.mousePressureListeners }
        set { ensureUnique(); storage.mousePressureListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.mousePressureListeners
        }
    }

    public var mouseMoveListeners: [MouseMoveListener] {
        get { storage.mouseMoveListeners }
        set { ensureUnique(); storage.mouseMoveListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.mouseMoveListeners
        }
    }

    public var scrollWheelListeners: [ScrollWheelListener] {
        get { storage.scrollWheelListeners }
        set { ensureUnique(); storage.scrollWheelListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.scrollWheelListeners
        }
    }

    public var pinchListeners: [PinchListener] {
        get { storage.pinchListeners }
        set { ensureUnique(); storage.pinchListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.pinchListeners
        }
    }

    public var rotationListeners: [RotationListener] {
        get { storage.rotationListeners }
        set { ensureUnique(); storage.rotationListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.rotationListeners
        }
    }

    public var keyDownListeners: [KeyDownListener] {
        get { storage.keyDownListeners }
        set { ensureUnique(); storage.keyDownListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.keyDownListeners
        }
    }

    public var keyUpListeners: [KeyUpListener] {
        get { storage.keyUpListeners }
        set { ensureUnique(); storage.keyUpListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.keyUpListeners
        }
    }

    public var modifiersChangedListeners: [ModifiersChangedListener] {
        get { storage.modifiersChangedListeners }
        set { ensureUnique(); storage.modifiersChangedListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.modifiersChangedListeners
        }
    }

    public var actionListeners: [(ObjectIdentifier, ActionListener)] {
        get { storage.actionListeners }
        set { ensureUnique(); storage.actionListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.actionListeners
        }
    }

    public var dropListeners: [(ObjectIdentifier, DropListener)] {
        get { storage.dropListeners }
        set { ensureUnique(); storage.dropListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.dropListeners
        }
    }

    public var canDropPredicate: CanDropPredicate? {
        get { storage.canDropPredicate }
        set { ensureUnique(); storage.canDropPredicate = newValue }
    }

    public var clickListeners: [ClickListener] {
        get { storage.clickListeners }
        set { ensureUnique(); storage.clickListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.clickListeners
        }
    }

    public var auxClickListeners: [ClickListener] {
        get { storage.auxClickListeners }
        set { ensureUnique(); storage.auxClickListeners = newValue }
        _modify {
            ensureUnique()
            yield &storage.auxClickListeners
        }
    }

    public var dragListener: DragInfo? {
        get { storage.dragListener }
        set { ensureUnique(); storage.dragListener = newValue }
    }

    public var hoverListener: (@Sendable (Bool, inout Window, inout App) -> Void)? {
        get { storage.hoverListener }
        set { ensureUnique(); storage.hoverListener = newValue }
    }

    public var tooltipBuilder: TooltipBuilder? {
        get { storage.tooltipBuilder }
        set { ensureUnique(); storage.tooltipBuilder = newValue }
    }

    public var windowControl: WindowControlArea? {
        get { storage.windowControl }
        set { ensureUnique(); storage.windowControl = newValue }
    }

    public var hitboxBehavior: HitboxBehavior {
        get { storage.hitboxBehavior }
        set { ensureUnique(); storage.hitboxBehavior = newValue }
    }

    public var tabIndex: Int? {
        get { storage.tabIndex }
        set { ensureUnique(); storage.tabIndex = newValue }
    }

    public var tabGroup: Bool {
        get { storage.tabGroup }
        set { ensureUnique(); storage.tabGroup = newValue }
    }

    public var tabStop: Bool {
        get { storage.tabStop }
        set { ensureUnique(); storage.tabStop = newValue }
    }

    public var sourceLocationValue: String? {
        get { storage.sourceLocationValue }
        set { ensureUnique(); storage.sourceLocationValue = newValue }
    }

    public init(file: String = #fileID, line: Int = #line) {
        self.storage = InteractivityStorage(file: file, line: line)
    }

    internal init(storage: InteractivityStorage) {
        self.storage = storage
    }

    public static func new(file: String = #fileID, line: Int = #line) -> Interactivity {
        Interactivity(file: file, line: line)
    }

    public func sourceLocation() -> String? {
        storage.sourceLocationValue
    }

    public mutating func onMouseDown(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) {
        mouseDownListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && event.button == button && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureAnyMouseDown(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) {
        mouseDownListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onAnyMouseDown(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) {
        mouseDownListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onMousePressure(
        _ listener: @escaping @Sendable (MousePressureEvent, inout Window, inout App) -> Void
    ) {
        mousePressureListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureMousePressure(
        _ listener: @escaping @Sendable (MousePressureEvent, inout Window, inout App) -> Void
    ) {
        mousePressureListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onMouseUp(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) {
        mouseUpListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && event.button == button && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureAnyMouseUp(
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) {
        mouseUpListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onAnyMouseUp(
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) {
        mouseUpListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onMouseDownOut(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) {
        mouseDownListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture && !hitbox.bounds.contains(window.mousePosition) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onMouseUpOut(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) {
        mouseUpListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture && event.button == button && !hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onMouseMove(
        _ listener: @escaping @Sendable (MouseMoveEvent, inout Window, inout App) -> Void
    ) {
        mouseMoveListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onDragMove<T>(
        _ listener: @escaping @Sendable (DragMoveEvent<T>, inout Window, inout App) -> Void
    ) {
        mouseMoveListeners.append { event, phase, hitbox, window, cx in
            if phase == .capture {
                MainActor.assumeIsolated {
                    if let drag = cx.activeDrag, drag.value is T {
                        let dragEvent = DragMoveEvent<T>(
                            event: event,
                            bounds: hitbox.bounds,
                            draggedItem: drag.value
                        )
                        listener(dragEvent, &window, &cx)
                    }
                }
            }
        }
    }

    public mutating func onScrollWheel(
        _ listener: @escaping @Sendable (ScrollWheelEvent, inout Window, inout App) -> Void
    ) {
        scrollWheelListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.shouldHandleScroll(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onPinch(
        _ listener: @escaping @Sendable (PinchEvent, inout Window, inout App) -> Void
    ) {
        pinchListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onRotation(
        _ listener: @escaping @Sendable (RotationEvent, inout Window, inout App) -> Void
    ) {
        rotationListeners.append { event, phase, hitbox, window, cx in
            if phase == .bubble && hitbox.isHovered(window) {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureAction<A: Action>(
        _ listener: @escaping @Sendable (A, inout Window, inout App) -> Void
    ) {
        actionListeners.append((ObjectIdentifier(A.self), { action, phase, window, cx in
            if let a = action as? A {
                if phase == .capture {
                    listener(a, &window, &cx)
                } else {
                    MainActor.assumeIsolated {
                        cx.propagate()
                    }
                }
            }
        }))
    }

    public mutating func onAction<A: Action>(
        _ listener: @escaping @Sendable (A, inout Window, inout App) -> Void
    ) {
        actionListeners.append((ObjectIdentifier(A.self), { action, phase, window, cx in
            if let a = action as? A {
                if phase == .bubble {
                    listener(a, &window, &cx)
                }
            }
        }))
    }

    public mutating func onBoxedAction(
        _ action: any Action,
        _ listener: @escaping @Sendable (any Action, inout Window, inout App) -> Void
    ) {
        let actionTypeId = ObjectIdentifier(type(of: action))
        actionListeners.append((actionTypeId, { dynAction, phase, window, cx in
            if phase == .bubble {
                listener(dynAction, &window, &cx)
            }
        }))
    }

    public mutating func onKeyDown(
        _ listener: @escaping @Sendable (KeyDownEvent, inout Window, inout App) -> Void
    ) {
        keyDownListeners.append { event, phase, window, cx in
            if phase == .bubble {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureKeyDown(
        _ listener: @escaping @Sendable (KeyDownEvent, inout Window, inout App) -> Void
    ) {
        keyDownListeners.append { event, phase, window, cx in
            if phase == .capture {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onKeyUp(
        _ listener: @escaping @Sendable (KeyUpEvent, inout Window, inout App) -> Void
    ) {
        keyUpListeners.append { event, phase, window, cx in
            if phase == .bubble {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func captureKeyUp(
        _ listener: @escaping @Sendable (KeyUpEvent, inout Window, inout App) -> Void
    ) {
        keyUpListeners.append { event, phase, window, cx in
            if phase == .capture {
                listener(event, &window, &cx)
            }
        }
    }

    public mutating func onModifiersChanged(
        _ listener: @escaping @Sendable (ModifiersChangedEvent, inout Window, inout App) -> Void
    ) {
        modifiersChangedListeners.append { event, window, cx in
            listener(event, &window, &cx)
        }
    }

    public mutating func onDrop<T>(
        _ listener: @escaping @Sendable (T, inout Window, inout App) -> Void
    ) {
        dropListeners.append((ObjectIdentifier(T.self), { draggedValue, window, cx in
            if let val = draggedValue as? T {
                listener(val, &window, &cx)
            }
        }))
    }

    public mutating func canDrop(
        _ predicate: @escaping @Sendable (Any, inout Window, inout App) -> Bool
    ) {
        self.canDropPredicate = predicate
    }

    public mutating func onClick(
        _ listener: @escaping @Sendable (ClickEvent, inout Window, inout App) -> Void
    ) {
        clickListeners.append(listener)
    }

    public mutating func onAuxClick(
        _ listener: @escaping @Sendable (ClickEvent, inout Window, inout App) -> Void
    ) {
        auxClickListeners.append(listener)
    }

    public mutating func onDrag<T: Sendable, W: Render & Sendable>(
        _ value: T,
        _ constructor: @escaping @Sendable (T, Point<Pixels>, inout Window, inout App) -> Entity<W>
    ) {
        self.dragListener = DragInfo(value: value, listener: { val, offset, window, cx in
            if let typed = val as? T {
                let entity = constructor(typed, offset, &window, &cx)
                return AnyView(entity)
            }
            fatalError("Unexpected drag value type")
        })
    }

    public mutating func onHover(
        _ listener: @escaping @Sendable (Bool, inout Window, inout App) -> Void
    ) {
        self.hoverListener = listener
    }

    public mutating func tooltip(
        _ buildTooltip: @escaping @Sendable (inout Window, inout App) -> AnyView
    ) {
        self.tooltipBuilder = TooltipBuilder(build: buildTooltip, hoverable: false)
    }

    public mutating func hoverableTooltip(
        _ buildTooltip: @escaping @Sendable (inout Window, inout App) -> AnyView
    ) {
        self.tooltipBuilder = TooltipBuilder(build: buildTooltip, hoverable: true)
    }

    public mutating func occludeMouse() {
        self.hitboxBehavior = .blockMouse
    }

    public mutating func windowControlArea(_ area: WindowControlArea) {
        self.windowControl = area
    }

    public mutating func blockMouseExceptScroll() {
        self.hitboxBehavior = .blockMouseExceptScroll
    }

    @MainActor
    public mutating func requestLayout(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App,
        _ f: (Style, inout Window, inout App) -> LayoutId
    ) -> LayoutId {
        let (layoutId, _) = window.withOptionalElementState(globalId) { (elementState: inout InteractiveElementState?, window: inout Window) -> LayoutId in
            let state = elementState ?? InteractiveElementState()

            if cx.hasActiveDrag() {
                state.pendingMouseDown = nil
                state.clickedState = ElementClickedState()
            }

            if self.focusable && self.trackedFocusHandle == nil {
                var handle = state.focusHandle ?? cx.focusHandle()
                handle = handle.tabStop(self.tabStop)
                if let index = self.tabIndex {
                    handle = handle.tabIndex(index)
                }
                state.focusHandle = handle
                self.trackedFocusHandle = handle
            }

            if let scrollHandle = self.trackedScrollHandle {
                self.scrollOffset = scrollHandle.offset()
            } else if self.baseStyle.overflow.x == .scroll || self.baseStyle.overflow.y == .scroll {
                self.scrollOffset = state.scrollOffset
            }

            let style = self.computeStyleInternal(hitbox: nil, elementState: state, window: &window, cx: &cx)
            let id = f(style, &window, &cx)
            elementState = state
            return id
        }
        return layoutId
    }

    @MainActor
    public mutating func prepaint<R>(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ contentSize: Size<Pixels>,
        _ window: inout Window,
        _ cx: inout App,
        _ f: (Style, Point<Pixels>, Hitbox?, inout Window, inout App) -> R
    ) -> R {
        self.contentSize = contentSize

        if let focusHandle = self.trackedFocusHandle {
            window.setFocusHandle(focusHandle)
        }

        let (result, _) = window.withOptionalElementState(globalId) { (elementState: inout InteractiveElementState?, window: inout Window) -> R in
            let state = elementState ?? InteractiveElementState()
            let style = self.computeStyleInternal(hitbox: nil, elementState: state, window: &window, cx: &cx)

            self.active = state.clickedState.element

            if self.hoverStyle != nil || self.groupHoverStyle != nil {
                // Ensure hover state is tracked
            }

            if let activeTooltip = state.activeTooltip {
                if self.tooltipBuilder != nil {
                    self.tooltipId = setTooltipOnWindow(activeTooltip, &window)
                } else {
                    state.activeTooltip = nil
                }
            }

            let overflowMask = style.overflowMask(bounds: bounds, remSize: window.remSize)
            let res: R
            if let mask = overflowMask {
                res = window.withContentMask(mask) { window in
                    let hitbox: Hitbox?
                    if self.shouldInsertHitbox(style: style, window: window, cx: cx) {
                        hitbox = window.insertHitbox(bounds, self.hitboxBehavior)
                    } else {
                        hitbox = nil
                    }

                    let scrollOffset = self.clampScrollPosition(bounds: bounds, style: style, window: &window)
                    return f(style, scrollOffset, hitbox, &window, &cx)
                }
            } else {
                let hitbox: Hitbox?
                if self.shouldInsertHitbox(style: style, window: window, cx: cx) {
                    hitbox = window.insertHitbox(bounds, self.hitboxBehavior)
                } else {
                    hitbox = nil
                }

                let scrollOffset = self.clampScrollPosition(bounds: bounds, style: style, window: &window)
                res = f(style, scrollOffset, hitbox, &window, &cx)
            }
            elementState = state
            return res
        }

        return result
    }

    @MainActor
    public mutating func paint(
        _ globalId: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ hitbox: Hitbox?,
        _ window: inout Window,
        _ cx: inout App,
        _ f: (Style, inout Window, inout App) -> Void
    ) {
        self.hovered = hitbox?.isHovered(window)

        let (_, _) = window.withOptionalElementState(globalId) { (elementState: inout InteractiveElementState?, window: inout Window) -> Void in
            let state = elementState ?? InteractiveElementState()
            let style = self.computeStyleInternal(hitbox: hitbox, elementState: state, window: &window, cx: &cx)

            self.paintHoverGroupHandler(&window, &cx)

            if style.visibility == .hidden {
                elementState = state
                return
            }

            var tabGroupIndex: Int? = nil
            if self.tabGroup {
                tabGroupIndex = self.tabIndex
            }
            if let focusHandle = self.trackedFocusHandle {
                window.nextFrame.tabStops.insert(focusHandle)
            }

            window.withElementOpacity(style.opacity) { window in
                style.paint(bounds, &window, &cx) { window, cx in
                    window.withTextStyle(style.textStyle()) { window in
                        window.withContentMask(style.overflowMask(bounds: bounds, remSize: window.remSize)) { window in
                            window.withTabGroup(tabGroupIndex) { window in
                                if let hb = hitbox {
                                    if let drag = cx.activeDrag {
                                        if let cursorStyle = drag.cursorStyle {
                                            window.setWindowCursorStyle(cursorStyle)
                                        }
                                    } else if let mouseCursor = style.mouseCursor {
                                        window.setCursorStyle(mouseCursor, hitbox: hb)
                                    }

                                    if let groupName = self.group {
                                        GroupHitboxes.push(groupName, hb.id, &cx)
                                    }

                                    if let area = self.windowControl {
                                        window.insertWindowControlHitbox(area, hb)
                                    }

                                    self.paintMouseListeners(hitbox: hb, elementState: state, window: &window, cx: &cx)
                                    self.paintScrollListener(hitbox: hb, style: style, window: &window, cx: &cx)
                                }

                                self.paintKeyboardListeners(&window, &cx)
                                f(style, &window, &cx)

                                if hitbox != nil {
                                    if let groupName = self.group {
                                        GroupHitboxes.pop(groupName, &cx)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            elementState = state
        }
    }

    @MainActor
    public func computeStyle(
        _ globalId: GlobalElementId?,
        _ hitbox: Hitbox?,
        _ window: inout Window,
        _ cx: inout App
    ) -> Style {
        let (style, _) = window.withOptionalElementState(globalId) { (elementState: inout InteractiveElementState?, window: inout Window) -> Style in
            let state = elementState ?? InteractiveElementState()
            return self.computeStyleInternal(hitbox: hitbox, elementState: state, window: &window, cx: &cx)
        }
        return style
    }

    @MainActor
    func computeStyleInternal(
        hitbox: Hitbox?,
        elementState: InteractiveElementState?,
        window: inout Window,
        cx: inout App
    ) -> Style {
        var style = Style()
        style.refine(with: self.baseStyle)

        if let focusHandle = self.trackedFocusHandle {
            if let inFocus = self.inFocusStyle, focusHandle.withinFocused(window, cx) {
                style.refine(with: inFocus)
            }
            if let focus = self.focusStyle, focusHandle.isFocused(window) {
                style.refine(with: focus)
            }
            if let focusVisible = self.focusVisibleStyle, focusHandle.isFocused(window), window.lastInputWasKeyboard() {
                style.refine(with: focusVisible)
            }
        }

        if !cx.hasActiveDrag() {
            if let groupHover = self.groupHoverStyle {
                var isGroupHovered = false
                if let groupHitboxId = GroupHitboxes.get(groupHover.group, &cx) {
                    isGroupHovered = groupHitboxId.isHovered(window)
                } else if let es = elementState {
                    isGroupHovered = es.hoverState.group
                }
                if isGroupHovered {
                    style.refine(with: groupHover.style)
                }
            }

            if let hoverStyle = self.hoverStyle {
                var isHovered = false
                if let hb = hitbox {
                    isHovered = hb.isHovered(window)
                } else if let es = elementState {
                    isHovered = es.hoverState.element
                }
                if isHovered {
                    style.refine(with: hoverStyle)
                }
            }
        }

        if let hb = hitbox {
            if let drag = cx.activeDrag {
                var canDrop = true
                if let pred = self.canDropPredicate {
                    canDrop = pred(drag.value, &window, &cx)
                }
                if canDrop {
                    let dragTypeId = ObjectIdentifier(type(of: drag.value))
                    for (typeId, groupDragStyle) in self.groupDragOverStyles {
                        if typeId == dragTypeId,
                           let ghId = GroupHitboxes.get(groupDragStyle.group, &cx),
                           ghId.isHovered(window) {
                            style.refine(with: groupDragStyle.style)
                        }
                    }
                    for (typeId, buildDragOverStyle) in self.dragOverStyles {
                        if typeId == dragTypeId && hb.isHovered(window) {
                            style.refine(with: buildDragOverStyle(drag.value, &window, &cx))
                        }
                    }
                }
                style.mouseCursor = drag.cursorStyle
            }
        }

        if let es = elementState {
            if es.clickedState.group, let group = self.groupActiveStyle {
                style.refine(with: group.style)
            }
            if es.clickedState.element, let activeStyle = self.activeStyle {
                style.refine(with: activeStyle)
            }
        }

        return style
    }

    private func shouldInsertHitbox(style: Style, window: Window, cx: App) -> Bool {
        hitboxBehavior != .normal
            || windowControl != nil
            || style.mouseCursor != nil
            || group != nil
            || scrollOffset != nil
            || trackedFocusHandle != nil
            || hoverStyle != nil
            || groupHoverStyle != nil
            || hoverListener != nil
            || !mouseUpListeners.isEmpty
            || !mousePressureListeners.isEmpty
            || !mouseDownListeners.isEmpty
            || !mouseMoveListeners.isEmpty
            || !clickListeners.isEmpty
            || !auxClickListeners.isEmpty
            || !scrollWheelListeners.isEmpty
            || !pinchListeners.isEmpty
            || !rotationListeners.isEmpty
            || dragListener != nil
            || !dropListeners.isEmpty
            || tooltipBuilder != nil
    }

    private mutating func clampScrollPosition(
        bounds: Bounds<Pixels>,
        style: Style,
        window: inout Window
    ) -> Point<Pixels> {
        guard var scrollOffset = self.scrollOffset else {
            return .zero
        }

        var scrollToBottom = false
        if let handle = self.trackedScrollHandle {
            handle.state.overflow = style.overflow
            scrollToBottom = handle.state.scrollToBottom
            handle.state.scrollToBottom = false
        }

        let remSize = window.remSize
        let padding = style.padding.toPixels(parentSize: bounds.size, remSize: remSize)
        let paddingSize = Size(width: padding.left + padding.right, height: padding.top + padding.bottom)
        let paddedContentSize = self.contentSize + paddingSize

        let scrollMaxX = max(px(0), px(((paddedContentSize.width - bounds.size.width).value * 100.0).rounded() / 100.0))
        let scrollMaxY = max(px(0), px(((paddedContentSize.height - bounds.size.height).value * 100.0).rounded() / 100.0))

        scrollOffset.x = min(px(0), max(-scrollMaxX, scrollOffset.x))
        if scrollToBottom {
            scrollOffset.y = -scrollMaxY
        } else {
            scrollOffset.y = min(px(0), max(-scrollMaxY, scrollOffset.y))
        }

        if let handle = self.trackedScrollHandle {
            handle.state.maxOffset = Point(x: scrollMaxX, y: scrollMaxY)
            handle.state.bounds = bounds
            handle.setOffset(scrollOffset)
        }

        self.scrollOffset = scrollOffset
        return scrollOffset
    }

    @MainActor
    private mutating func paintMouseListeners(
        hitbox: Hitbox,
        elementState: InteractiveElementState,
        window: inout Window,
        cx: inout App
    ) {
        if let focusHandle = self.trackedFocusHandle {
            let hb = hitbox
            window.onMouseEvent { (event: MouseDownEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if phase == .bubble && hb.isHovered(window) && !window.defaultPrevented {
                    MainActor.assumeIsolated {
                        window.focus(focusHandle, &cx)
                        window.preventDefault()
                    }
                }
            }
        }

        for listener in self.mouseDownListeners {
            let hb = hitbox
            window.onMouseEvent { (event: MouseDownEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.mouseUpListeners {
            let hb = hitbox
            window.onMouseEvent { (event: MouseUpEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.mousePressureListeners {
            let hb = hitbox
            window.onMouseEvent { (event: MousePressureEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.mouseMoveListeners {
            let hb = hitbox
            window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.scrollWheelListeners {
            let hb = hitbox
            window.onMouseEvent { (event: ScrollWheelEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.pinchListeners {
            let hb = hitbox
            window.onMouseEvent { (event: PinchEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        for listener in self.rotationListeners {
            let hb = hitbox
            window.onMouseEvent { (event: RotationEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                listener(event, phase, hb, &window, &cx)
            }
        }

        if self.hoverStyle != nil || self.baseStyle.mouseCursor != nil {
            let hb = hitbox
            let currentView = window.currentView()
            window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if phase == .capture {
                    MainActor.assumeIsolated {
                        let hovered = hb.isHovered(window)
                        if hovered != elementState.hoverState.element {
                            elementState.hoverState.element = hovered
                            if let cv = currentView {
                                cx.notify(cv)
                            }
                        }
                    }
                }
            }
        }

        if !self.dropListeners.isEmpty {
            let hb = hitbox
            let drops = self.dropListeners
            let canDropPred = self.canDropPredicate
            window.onMouseEvent { (event: MouseUpEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                MainActor.assumeIsolated {
                    if let drag = cx.activeDrag, phase == .bubble && hb.isHovered(window) {
                        let dragTypeId = ObjectIdentifier(type(of: drag.value))
                        for (dropTypeId, listener) in drops {
                            if dropTypeId == dragTypeId {
                                var canDrop = true
                                if let pred = canDropPred {
                                    canDrop = pred(drag.value, &window, &cx)
                                }
                                if canDrop {
                                    cx.activeDrag = nil
                                    listener(drag.value, &window, &cx)
                                    window.refresh()
                                    cx.stopPropagation()
                                }
                            }
                        }
                    }
                }
            }
        }

        if !self.clickListeners.isEmpty || !self.auxClickListeners.isEmpty || self.dragListener != nil {
            let hb = hitbox
            let hasAux = !self.auxClickListeners.isEmpty
            window.onMouseEvent { (event: MouseDownEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if phase == .bubble && (event.button == .left || hasAux) && hb.isHovered(window) {
                    elementState.pendingMouseDown = event
                    window.refresh()
                }
            }

            let dragInfo = self.dragListener
            let dragCursorStyle = self.baseStyle.mouseCursor
            window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if phase == .capture { return }
                MainActor.assumeIsolated {
                    if let mouseDown = elementState.pendingMouseDown,
                       !cx.hasActiveDrag(),
                       (event.position - mouseDown.position).magnitude() > 4.0,
                       let dragInfo = dragInfo,
                       mouseDown.button == .left {
                        elementState.clickedState = ElementClickedState()
                        let cursorOffset = event.position - hb.bounds.origin
                        let dragView = dragInfo.listener(dragInfo.value, cursorOffset, &window, &cx)
                        cx.activeDrag = AnyDrag(
                            view: dragView,
                            value: dragInfo.value,
                            cursorOffset: cursorOffset,
                            cursorStyle: dragCursorStyle
                        )
                        elementState.pendingMouseDown = nil
                        window.refresh()
                        cx.stopPropagation()
                    }
                }
            }

            let clicks = self.clickListeners
            let auxClicks = self.auxClickListeners
            window.onMouseEvent { (event: MouseUpEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                switch phase {
                case .capture:
                    if elementState.pendingMouseDown != nil && hb.isHovered(window) {
                        // Handled in bubble
                    } else if elementState.pendingMouseDown != nil {
                        elementState.pendingMouseDown = nil
                        window.refresh()
                    }
                case .bubble:
                    if let mouseDown = elementState.pendingMouseDown {
                        elementState.pendingMouseDown = nil
                        let clickEvent = ClickEvent.mouse(MouseClickEvent(down: mouseDown, up: event))
                        if mouseDown.button == .left {
                            for listener in clicks {
                                listener(clickEvent, &window, &cx)
                            }
                        } else {
                            for listener in auxClicks {
                                listener(clickEvent, &window, &cx)
                            }
                        }
                    }
                }
            }
        }

        if let hoverListener = self.hoverListener {
            let hb = hitbox
            window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if phase == .bubble {
                    MainActor.assumeIsolated {
                        let isHovered = elementState.pendingMouseDown == nil && !cx.hasActiveDrag() && hb.isHovered(window)
                        if isHovered != elementState.hoverListenerState {
                            elementState.hoverListenerState = isHovered
                            hoverListener(isHovered, &window, &cx)
                        }
                    }
                }
            }
        }

        if let tooltipBuilder = self.tooltipBuilder {
            let tooltipIsHoverable = tooltipBuilder.hoverable
            let buildTooltip: @Sendable (inout Window, inout App) -> (AnyView, Bool)? = { window, cx in
                let view = tooltipBuilder.build(&window, &cx)
                return (view, tooltipIsHoverable)
            }
            let hb = hitbox
            let checkIsHovered: @Sendable (Window) -> Bool = { window in
                elementState.pendingMouseDown == nil && hb.isHovered(window)
            }
            let checkIsHoveredPrepaint: @Sendable (Window) -> Bool = { window in
                !window.lastInputWasKeyboard() && elementState.pendingMouseDown == nil && hb.bounds.contains(window.mousePosition)
            }
            registerTooltipMouseHandlers(
                elementState,
                self.tooltipId,
                buildTooltip,
                checkIsHovered,
                checkIsHoveredPrepaint,
                &window
            )
        }

        let hb = hitbox
        let groupActiveHitboxId = self.groupActiveStyle.flatMap { GroupHitboxes.get($0.group, &cx) }
        window.onMouseEvent { (event: MouseDownEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
            if phase == .bubble && !window.defaultPrevented {
                let groupHovered = groupActiveHitboxId.map { $0.isHovered(window) } ?? false
                let elementHovered = hb.isHovered(window)
                if groupHovered || elementHovered {
                    elementState.clickedState = ElementClickedState(group: groupHovered, element: elementHovered)
                    window.refresh()
                }
            }
        }

        window.onMouseEvent { (event: MouseUpEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
            if phase == .capture && elementState.clickedState.isClicked {
                elementState.clickedState = ElementClickedState()
                window.refresh()
            }
        }
    }

    @MainActor
    private mutating func paintKeyboardListeners(
        _ window: inout Window,
        _ cx: inout App
    ) {
        if let context = self.keyContext {
            window.setKeyContext(context)
        }

        for listener in self.keyDownListeners {
            window.onKeyEvent { (event: any KeyEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if let keyDown = event as? KeyDownEvent {
                    listener(keyDown, phase, &window, &cx)
                }
            }
        }

        for listener in self.keyUpListeners {
            window.onKeyEvent { (event: any KeyEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                if let keyUp = event as? KeyUpEvent {
                    listener(keyUp, phase, &window, &cx)
                }
            }
        }

        for listener in self.modifiersChangedListeners {
            window.onModifiersChanged { (event: ModifiersChangedEvent, window: inout Window, cx: inout App) in
                listener(event, &window, &cx)
            }
        }

        for (actionType, listener) in self.actionListeners {
            window.onAction(actionType, listener)
        }
    }

    @MainActor
    private func paintHoverGroupHandler(
        _ window: inout Window,
        _ cx: inout App
    ) {
        if let groupHover = self.groupHoverStyle,
           let groupHitbox = GroupHitboxes.get(groupHover.group, &cx) {
            let wasHovered = groupHitbox.isHovered(window)
            let currentView = window.currentView()
            window.onMouseEvent { (event: MouseMoveEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
                MainActor.assumeIsolated {
                    let hovered = groupHitbox.isHovered(window)
                    if phase == .capture && hovered != wasHovered {
                        if let cv = currentView {
                            cx.notify(cv)
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func paintScrollListener(
        hitbox: Hitbox,
        style: Style,
        window: inout Window,
        cx: inout App
    ) {
        guard let _ = self.scrollOffset else { return }
        let overflow = style.overflow
        let allowConcurrentScroll = style.allowConcurrentScroll
        let restrictScrollToAxis = style.restrictScrollToAxis
        let lineHeight = window.lineHeight()
        let hb = hitbox
        let currentView = window.currentView()

        window.onMouseEvent { (event: ScrollWheelEvent, phase: DispatchPhase, window: inout Window, cx: inout App) in
            if phase == .bubble && hb.shouldHandleScroll(window) {
                let delta = event.delta.pixelDelta(lineHeight: lineHeight)
                var deltaX = Pixels.zero
                if overflow.x == .scroll {
                    if !delta.x.isZero {
                        deltaX = delta.x
                    } else if !restrictScrollToAxis && overflow.y != .scroll {
                        deltaX = delta.y
                    }
                }
                var deltaY = Pixels.zero
                if overflow.y == .scroll {
                    if !delta.y.isZero {
                        deltaY = delta.y
                    } else if !restrictScrollToAxis && overflow.x != .scroll {
                        deltaY = delta.x
                    }
                }

                if !allowConcurrentScroll && !deltaX.isZero && !deltaY.isZero {
                    if deltaX.abs() > deltaY.abs() {
                        deltaY = Pixels.zero
                    } else {
                        deltaX = Pixels.zero
                    }
                }

                if let handle = self.trackedScrollHandle {
                    let oldOffset = handle.offset()
                    var newOffset = oldOffset
                    newOffset.x += deltaX
                    newOffset.y += deltaY
                    handle.setOffset(newOffset)
                    if newOffset != oldOffset, let cv = currentView {
                        MainActor.assumeIsolated {
                            cx.notify(cv)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - InteractiveElement Protocol

/// A protocol for elements that want to use the standard GPUI event handlers that don't require any state.
public protocol InteractiveElement {
    var interactivity: Interactivity { get set }
}

extension InteractiveElement {
    /// Assign this element to a group of elements that can be styled together.
    public func group(_ group: SharedString) -> Self {
        var copy = self
        copy.interactivity.group = group
        return copy
    }

    /// Assign this element an ID, so that it can be used with interactivity.
    public func id(_ id: ElementId) -> Stateful<Self> where Self: Element {
        var copy = self
        copy.interactivity.elementId = id
        return Stateful(element: copy)
    }

    /// Track the focus state of the given focus handle on this element.
    public func trackFocus(_ focusHandle: FocusHandle) -> Self {
        var copy = self
        copy.interactivity.focusable = true
        copy.interactivity.trackedFocusHandle = focusHandle
        return copy
    }

    /// Set whether this element is a tab stop.
    public func tabStop(_ tabStop: Bool) -> Self {
        var copy = self
        copy.interactivity.tabStop = tabStop
        return copy
    }

    /// Set index of the tab stop order, and set this node as a tab stop.
    public func tabIndex(_ index: Int) -> Self {
        var copy = self
        copy.interactivity.focusable = true
        copy.interactivity.tabIndex = index
        copy.interactivity.tabStop = true
        return copy
    }

    /// Designate this element as a tab group.
    public func tabGroup() -> Self {
        var copy = self
        copy.interactivity.tabGroup = true
        if copy.interactivity.tabIndex == nil {
            copy.interactivity.tabIndex = 0
        }
        return copy
    }

    /// Set the keymap context for this element.
    public func keyContext(_ keyContext: KeyContext) -> Self {
        var copy = self
        copy.interactivity.keyContext = keyContext
        return copy
    }

    public func onMouseDown(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMouseDown(button, listener)
        return copy
    }

    public func captureAnyMouseDown(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureAnyMouseDown(listener)
        return copy
    }

    public func onAnyMouseDown(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onAnyMouseDown(listener)
        return copy
    }

    public func onMousePressure(
        _ listener: @escaping @Sendable (MousePressureEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMousePressure(listener)
        return copy
    }

    public func captureMousePressure(
        _ listener: @escaping @Sendable (MousePressureEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureMousePressure(listener)
        return copy
    }

    public func onMouseUp(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMouseUp(button, listener)
        return copy
    }

    public func captureAnyMouseUp(
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureAnyMouseUp(listener)
        return copy
    }

    public func onAnyMouseUp(
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onAnyMouseUp(listener)
        return copy
    }

    public func onMouseDownOut(
        _ listener: @escaping @Sendable (MouseDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMouseDownOut(listener)
        return copy
    }

    public func onMouseUpOut(
        _ button: MouseButton,
        _ listener: @escaping @Sendable (MouseUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMouseUpOut(button, listener)
        return copy
    }

    public func onMouseMove(
        _ listener: @escaping @Sendable (MouseMoveEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onMouseMove(listener)
        return copy
    }

    public func onDragMove<T>(
        _ listener: @escaping @Sendable (DragMoveEvent<T>, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onDragMove(listener)
        return copy
    }

    public func onScrollWheel(
        _ listener: @escaping @Sendable (ScrollWheelEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onScrollWheel(listener)
        return copy
    }

    public func onPinch(
        _ listener: @escaping @Sendable (PinchEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onPinch(listener)
        return copy
    }

    public func onRotation(
        _ listener: @escaping @Sendable (RotationEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onRotation(listener)
        return copy
    }

    public func captureAction<A: Action>(
        _ listener: @escaping @Sendable (A, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureAction(listener)
        return copy
    }

    public func onAction<A: Action>(
        _ listener: @escaping @Sendable (A, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onAction(listener)
        return copy
    }

    public func onBoxedAction(
        _ action: any Action,
        _ listener: @escaping @Sendable (any Action, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onBoxedAction(action, listener)
        return copy
    }

    public func onKeyDown(
        _ listener: @escaping @Sendable (KeyDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onKeyDown(listener)
        return copy
    }

    public func captureKeyDown(
        _ listener: @escaping @Sendable (KeyDownEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureKeyDown(listener)
        return copy
    }

    public func onKeyUp(
        _ listener: @escaping @Sendable (KeyUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onKeyUp(listener)
        return copy
    }

    public func captureKeyUp(
        _ listener: @escaping @Sendable (KeyUpEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.captureKeyUp(listener)
        return copy
    }

    public func onModifiersChanged(
        _ listener: @escaping @Sendable (ModifiersChangedEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onModifiersChanged(listener)
        return copy
    }

    public func onDrop<T>(
        _ listener: @escaping @Sendable (T, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onDrop(listener)
        return copy
    }

    public func canDrop(
        _ predicate: @escaping @Sendable (Any, inout Window, inout App) -> Bool
    ) -> Self {
        var copy = self
        copy.interactivity.canDrop(predicate)
        return copy
    }

    public func occludeMouse() -> Self {
        var copy = self
        copy.interactivity.occludeMouse()
        return copy
    }

    public func windowControlArea(_ area: WindowControlArea) -> Self {
        var copy = self
        copy.interactivity.windowControlArea(area)
        return copy
    }

    public func blockMouseExceptScroll() -> Self {
        var copy = self
        copy.interactivity.blockMouseExceptScroll()
        return copy
    }

    public func hover(_ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        var hoverStyle = copy.interactivity.hoverStyle ?? StyleRefinement()
        hoverStyle = f(hoverStyle)
        copy.interactivity.hoverStyle = hoverStyle
        return copy
    }

    public func groupHover(_ group: SharedString, _ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        var style = copy.interactivity.groupHoverStyle?.style ?? StyleRefinement()
        style = f(style)
        copy.interactivity.groupHoverStyle = GroupStyle(group: group, style: style)
        return copy
    }

    public func focus(_ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        copy.interactivity.focusable = true
        var focusStyle = copy.interactivity.focusStyle ?? StyleRefinement()
        focusStyle = f(focusStyle)
        copy.interactivity.focusStyle = focusStyle
        return copy
    }

    public func inFocus(_ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        copy.interactivity.focusable = true
        var inFocusStyle = copy.interactivity.inFocusStyle ?? StyleRefinement()
        inFocusStyle = f(inFocusStyle)
        copy.interactivity.inFocusStyle = inFocusStyle
        return copy
    }

    public func focusVisible(_ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        copy.interactivity.focusable = true
        var focusVisibleStyle = copy.interactivity.focusVisibleStyle ?? StyleRefinement()
        focusVisibleStyle = f(focusVisibleStyle)
        copy.interactivity.focusVisibleStyle = focusVisibleStyle
        return copy
    }
}

// MARK: - StatefulInteractiveElement Protocol

/// A protocol for interactive elements that have been assigned an element ID and can track state.
public protocol StatefulInteractiveElement: InteractiveElement {}

extension StatefulInteractiveElement {
    public func focusable() -> Self {
        var copy = self
        copy.interactivity.focusable = true
        return copy
    }

    public func overflowScroll() -> Self {
        var copy = self
        copy.interactivity.baseStyle.overflow.x = .scroll
        copy.interactivity.baseStyle.overflow.y = .scroll
        return copy
    }

    public func overflowXScroll() -> Self {
        var copy = self
        copy.interactivity.baseStyle.overflow.x = .scroll
        return copy
    }

    public func overflowYScroll() -> Self {
        var copy = self
        copy.interactivity.baseStyle.overflow.y = .scroll
        return copy
    }

    public func scrollbarWidth(_ width: AbsoluteLength) -> Self {
        var copy = self
        copy.interactivity.baseStyle.scrollbarWidth = width
        return copy
    }

    public func trackScroll(_ scrollHandle: ScrollHandle) -> Self {
        var copy = self
        copy.interactivity.trackedScrollHandle = scrollHandle
        return copy
    }

    public func anchorScroll(_ scrollAnchor: ScrollAnchor?) -> Self {
        var copy = self
        copy.interactivity.scrollAnchor = scrollAnchor
        return copy
    }

    public func active(_ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        var activeStyle = copy.interactivity.activeStyle ?? StyleRefinement()
        activeStyle = f(activeStyle)
        copy.interactivity.activeStyle = activeStyle
        return copy
    }

    public func groupActive(_ group: SharedString, _ f: (StyleRefinement) -> StyleRefinement) -> Self {
        var copy = self
        var style = copy.interactivity.groupActiveStyle?.style ?? StyleRefinement()
        style = f(style)
        copy.interactivity.groupActiveStyle = GroupStyle(group: group, style: style)
        return copy
    }

    public func onClick(
        _ listener: @escaping @Sendable (ClickEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onClick(listener)
        return copy
    }

    public func onAuxClick(
        _ listener: @escaping @Sendable (ClickEvent, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onAuxClick(listener)
        return copy
    }

    public func onDrag<T: Sendable, W: Render & Sendable>(
        _ value: T,
        _ constructor: @escaping @Sendable (T, Point<Pixels>, inout Window, inout App) -> Entity<W>
    ) -> Self {
        var copy = self
        copy.interactivity.onDrag(value, constructor)
        return copy
    }

    public func onHover(
        _ listener: @escaping @Sendable (Bool, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.interactivity.onHover(listener)
        return copy
    }

    public func tooltip(
        _ buildTooltip: @escaping @Sendable (inout Window, inout App) -> AnyView
    ) -> Self {
        var copy = self
        copy.interactivity.tooltip(buildTooltip)
        return copy
    }

    public func hoverableTooltip(
        _ buildTooltip: @escaping @Sendable (inout Window, inout App) -> AnyView
    ) -> Self {
        var copy = self
        copy.interactivity.hoverableTooltip(buildTooltip)
        return copy
    }
}

// MARK: - Div Element

/// Construct a new [`Div`] element.
public func div() -> Div {
    Div()
}

/// A [`Div`] element, the all-in-one element for building complex UIs in GPUI.
public struct Div: Styled, InteractiveElement, ParentElement, Element, IntoElement {
    public typealias RequestLayoutState = DivFrameState
    public typealias PrepaintState = Hitbox?

    public var interactivity: Interactivity
    public var children: [AnyElement]
    public var prepaintListener: (@Sendable ([Bounds<Pixels>], inout Window, inout App) -> Void)?
    public var imageCacheProvider: (any ImageCacheProvider)?
    public var prepaintOrderFn: (@Sendable (inout Window, inout App) -> [Int])?

    public init() {
        self.interactivity = Interactivity.new()
        self.children = []
        self.prepaintListener = nil
        self.imageCacheProvider = nil
        self.prepaintOrderFn = nil
    }

    public mutating func extend(_ elements: [AnyElement]) {
        self.children.append(contentsOf: elements)
    }

    public var style: StyleRefinement {
        get { interactivity.baseStyle }
        set { interactivity.baseStyle = newValue }
        _modify { yield &interactivity.baseStyle }
    }

    public func onChildrenPrepainted(
        _ listener: @escaping @Sendable ([Bounds<Pixels>], inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.prepaintListener = listener
        return copy
    }

    public func imageCache(_ cache: any ImageCacheProvider) -> Self {
        var copy = self
        copy.imageCacheProvider = cache
        return copy
    }

    public func withDynamicPrepaintOrder(
        _ orderFn: @escaping @Sendable (inout Window, inout App) -> [Int]
    ) -> Self {
        var copy = self
        copy.prepaintOrderFn = orderFn
        return copy
    }

    public mutating func child(_ child: AnyElement) {
        children.append(child)
    }

    public mutating func children(_ children: [AnyElement]) {
        self.children.append(contentsOf: children)
    }

    public func child(_ child: some IntoElement) -> Self {
        var copy = self
        copy.children.append(child.intoAnyElement())
        return copy
    }

    public func children(_ children: [some IntoElement]) -> Self {
        var copy = self
        copy.children.append(contentsOf: children.map { $0.intoAnyElement() })
        return copy
    }

    public func id() -> ElementId? {
        interactivity.elementId
    }

    public func sourceLocation() -> String? {
        interactivity.sourceLocation()
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, DivFrameState) {
        var childLayoutIds: [LayoutId] = []
        let imageCacheObj = self.imageCacheProvider?.provide(&window, &cx)

        let layoutId = window.withImageCache(imageCacheObj as Any) { window in
            self.interactivity.requestLayout(
                id,
                inspectorId,
                &window,
                &cx
            ) { style, window, cx in
                window.withTextStyle(style.textStyle()) { window in
                    childLayoutIds = self.children.indices.map { i in
                        self.children[i].requestLayout(&window, &cx)
                    }
                    return window.requestLayout(style: style, children: childLayoutIds)
                }
            }
        }

        return (layoutId, DivFrameState(childLayoutIds: childLayoutIds))
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ state: inout DivFrameState,
        _ window: inout Window,
        _ cx: inout App
    ) -> Hitbox? {
        let imageCacheObj = self.imageCacheProvider?.provide(&window, &cx)
        let hasPrepaintListener = self.prepaintListener != nil
        var childrenBounds: [Bounds<Pixels>] = []
        if hasPrepaintListener {
            childrenBounds.reserveCapacity(state.childLayoutIds.count)
        }

        var childMin = Point(x: Pixels.max, y: Pixels.max)
        var childMax = Point<Pixels>.zero

        if let anchor = self.interactivity.scrollAnchor {
            anchor.setLastOrigin(bounds.origin - window.elementOffset())
        }

        let contentSize: Size<Pixels>
        if state.childLayoutIds.isEmpty {
            contentSize = bounds.size
        } else if let scrollHandle = self.interactivity.trackedScrollHandle {
            scrollHandle.state.childBounds.removeAll(keepingCapacity: true)
            for childLayoutId in state.childLayoutIds {
                let childBounds = window.layoutBounds(childLayoutId)
                childMin = childMin.min(childBounds.origin)
                childMax = childMax.max(childBounds.bottomRight)
                scrollHandle.state.childBounds.append(childBounds)
            }
            contentSize = Size(width: childMax.x - childMin.x, height: childMax.y - childMin.y)
        } else {
            for childLayoutId in state.childLayoutIds {
                let childBounds = window.layoutBounds(childLayoutId)
                childMin = childMin.min(childBounds.origin)
                childMax = childMax.max(childBounds.bottomRight)
                if hasPrepaintListener {
                    childrenBounds.append(childBounds)
                }
            }
            contentSize = Size(width: childMax.x - childMin.x, height: childMax.y - childMin.y)
        }

        if let scrollHandle = self.interactivity.trackedScrollHandle {
            scrollHandle.scrollToActiveItem()
        }

        return self.interactivity.prepaint(
            id,
            inspectorId,
            bounds,
            contentSize,
            &window,
            &cx
        ) { style, scrollOffset, hitbox, window, cx in
            if style.display == .none {
                return hitbox
            }

            window.withImageCache(imageCacheObj as Any) { window in
                window.withElementOffset(scrollOffset) { window in
                    if let orderFn = self.prepaintOrderFn {
                        let order = orderFn(&window, &cx)
                        for idx in order {
                            if idx >= 0 && idx < self.children.count {
                                _ = self.children[idx].prepaint(&window, &cx)
                            }
                        }
                    } else {
                        for idx in self.children.indices {
                            _ = self.children[idx].prepaint(&window, &cx)
                        }
                    }
                }

                if let listener = self.prepaintListener {
                    listener(childrenBounds, &window, &cx)
                }
            }

            return hitbox
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout DivFrameState,
        _ prepaint: inout Hitbox?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        let imageCacheObj = self.imageCacheProvider?.provide(&window, &cx)

        window.withImageCache(imageCacheObj as Any) { window in
            self.interactivity.paint(
                id,
                inspectorId,
                bounds,
                prepaint,
                &window,
                &cx
            ) { style, window, cx in
                if style.display == .none {
                    return
                }

                for idx in self.children.indices {
                    self.children[idx].paint(&window, &cx)
                }
            }
        }
    }

    public func intoAnyElement() -> AnyElement {
        AnyElement(self)
    }
}

// MARK: - Div Frame and Inspector State

public struct DivFrameState: Sendable {
    public var childLayoutIds: [LayoutId]

    public init(childLayoutIds: [LayoutId] = []) {
        self.childLayoutIds = childLayoutIds
    }
}

public struct DivInspectorState: Sendable {
    // PORT NOTE: DivInspectorState.baseStyle is heap-boxed matching upstream Box<StyleRefinement>.
    private var baseStyleBox: StyleRefinementBox

    public var baseStyle: StyleRefinement {
        get { baseStyleBox.value }
        set {
            if isKnownUniquelyReferenced(&baseStyleBox) {
                baseStyleBox.value = newValue
            } else {
                baseStyleBox = StyleRefinementBox(newValue)
            }
        }
        _modify {
            if !isKnownUniquelyReferenced(&baseStyleBox) {
                baseStyleBox = StyleRefinementBox(baseStyleBox.value)
            }
            yield &baseStyleBox.value
        }
    }

    public var bounds: Bounds<Pixels>
    public var contentSize: Size<Pixels>

    public init(
        baseStyle: StyleRefinement = StyleRefinement(),
        bounds: Bounds<Pixels> = Bounds(origin: .zero, size: .zero),
        contentSize: Size<Pixels> = Size(width: .zero, height: .zero)
    ) {
        self.baseStyleBox = StyleRefinementBox(baseStyle)
        self.bounds = bounds
        self.contentSize = contentSize
    }
}

// MARK: - Stateful Element Wrapper

/// A wrapper around an element that can store state, produced after assigning an ElementId.
public struct Stateful<E: Element>: Element, IntoElement {
    public typealias RequestLayoutState = E.RequestLayoutState
    public typealias PrepaintState = E.PrepaintState

    public var element: E

    public init(element: E) {
        self.element = element
    }

    public func id() -> ElementId? {
        element.id()
    }

    public func sourceLocation() -> String? {
        element.sourceLocation()
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, E.RequestLayoutState) {
        element.requestLayout(id, inspectorId, &window, &cx)
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ state: inout E.RequestLayoutState,
        _ window: inout Window,
        _ cx: inout App
    ) -> E.PrepaintState {
        element.prepaint(id, inspectorId, bounds, &state, &window, &cx)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout E.RequestLayoutState,
        _ prepaint: inout E.PrepaintState,
        _ window: inout Window,
        _ cx: inout App
    ) {
        element.paint(
            id,
            inspectorId,
            bounds,
            &requestLayout,
            &prepaint,
            &window,
            &cx
        )
    }

    public func intoAnyElement() -> AnyElement {
        AnyElement(self)
    }
}

extension Stateful: Styled where E: Styled {
    public var style: StyleRefinement {
        get { element.style }
        set { element.style = newValue }
    }
}

extension Stateful: InteractiveElement where E: InteractiveElement {
    public var interactivity: Interactivity {
        get { element.interactivity }
        set { element.interactivity = newValue }
    }
}

extension Stateful: StatefulInteractiveElement where E: InteractiveElement {}

extension Stateful: ParentElement where E: ParentElement {
    public mutating func extend(_ elements: [AnyElement]) {
        element.extend(elements)
    }
}

// MARK: - ScrollAnchor

/// Represents an element that can be scrolled to in its parent element.
public struct ScrollAnchor: Sendable {
    public var handle: ScrollHandle
    // PORT NOTE: OriginHolder retains mutable origin for anchor scrolling matching upstream Rc<RefCell<Point<Pixels>>>.
    final class OriginHolder: @unchecked Sendable {
        var lastOrigin: Point<Pixels> = .zero
    }
    private let originHolder: OriginHolder

    public init(handle: ScrollHandle) {
        self.handle = handle
        self.originHolder = OriginHolder()
    }

    public static func forHandle(_ handle: ScrollHandle) -> ScrollAnchor {
        ScrollAnchor(handle: handle)
    }

    public func setLastOrigin(_ origin: Point<Pixels>) {
        originHolder.lastOrigin = origin
    }

    public func scrollTo(_ window: inout Window, _ cx: inout App) {
        let anchor = self
        window.onNextFrame { window, _ in
            let viewportBounds = anchor.handle.bounds()
            let selfBounds = anchor.originHolder.lastOrigin
            anchor.handle.setOffset(viewportBounds.origin - selfBounds)
        }
    }
}

// MARK: - ScrollHandle

// PORT NOTE: Renamed from upstream private ScrollStrategy to DivScrollStrategy to avoid collision with uniform_list.ScrollStrategy
enum DivScrollStrategy: Sendable {
    case firstVisible
    case top

    static var `default`: DivScrollStrategy { .firstVisible }
}

struct ScrollActiveItem: Sendable {
    var index: Int
    var strategy: DivScrollStrategy

    init(index: Int, strategy: DivScrollStrategy = .default) {
        self.index = index
        self.strategy = strategy
    }
}

// PORT NOTE: ScrollHandleState manages scrolling coordinates and child bounds matching upstream Rc<RefCell<ScrollHandleState>>.
final class ScrollHandleState: @unchecked Sendable {
    var offset: Point<Pixels> = .zero
    var bounds: Bounds<Pixels> = Bounds(origin: .zero, size: .zero)
    var maxOffset: Point<Pixels> = .zero
    var childBounds: [Bounds<Pixels>] = []
    var scrollToBottom: Bool = false
    var overflow: Point<Overflow> = Point(x: .visible, y: .visible)
    var activeItem: ScrollActiveItem? = nil

    init() {}
}

/// A handle to the scrollable aspects of an element.
public struct ScrollHandle: Sendable {
    let state: ScrollHandleState

    public init() {
        self.state = ScrollHandleState()
    }

    public static func new() -> ScrollHandle {
        ScrollHandle()
    }

    public func offset() -> Point<Pixels> {
        state.offset
    }

    public func maxOffset() -> Point<Pixels> {
        state.maxOffset
    }

    public func topItem() -> Int {
        let top = state.bounds.top - state.offset.y
        for (i, bounds) in state.childBounds.enumerated() {
            if bounds.bottom >= top {
                return i
            }
        }
        return max(0, state.childBounds.count - 1)
    }

    public func bottomItem() -> Int {
        let bottom = state.bounds.bottom - state.offset.y
        for (i, bounds) in state.childBounds.enumerated().reversed() {
            if bounds.top <= bottom {
                return i
            }
        }
        return 0
    }

    public func bounds() -> Bounds<Pixels> {
        state.bounds
    }

    public func boundsForItem(_ ix: Int) -> Bounds<Pixels>? {
        guard ix >= 0 && ix < state.childBounds.count else { return nil }
        return state.childBounds[ix]
    }

    public func scrollToItem(_ ix: Int) {
        state.activeItem = ScrollActiveItem(index: ix, strategy: .firstVisible)
    }

    public func scrollToTopOfItem(_ ix: Int) {
        state.activeItem = ScrollActiveItem(index: ix, strategy: .top)
    }

    func scrollToActiveItem() {
        guard let active = state.activeItem else { return }
        guard active.index >= 0 && active.index < state.childBounds.count else {
            return
        }
        let bounds = state.childBounds[active.index]
        switch active.strategy {
        case .firstVisible:
            if state.overflow.y == .scroll {
                let childHeight = bounds.size.height
                let viewportHeight = state.bounds.size.height
                if childHeight > viewportHeight {
                    state.offset.y = state.bounds.top - bounds.top
                } else if bounds.top + state.offset.y < state.bounds.top {
                    state.offset.y = state.bounds.top - bounds.top
                } else if bounds.bottom + state.offset.y > state.bounds.bottom {
                    state.offset.y = state.bounds.bottom - bounds.bottom
                }
            }
        case .top:
            state.offset.y = state.bounds.top - bounds.top
        }

        if state.overflow.x == .scroll {
            let childWidth = bounds.size.width
            let viewportWidth = state.bounds.size.width
            if childWidth > viewportWidth {
                state.offset.x = state.bounds.left - bounds.left
            } else if bounds.left + state.offset.x < state.bounds.left {
                state.offset.x = state.bounds.left - bounds.left
            } else if bounds.right + state.offset.x > state.bounds.right {
                state.offset.x = state.bounds.right - bounds.right
            }
        }
        state.activeItem = nil
    }

    public func scrollToBottom() {
        state.scrollToBottom = true
    }

    public func setOffset(_ position: Point<Pixels>) {
        state.offset = position
    }

    public func logicalScrollTop() -> (Int, Pixels) {
        let ix = topItem()
        if ix < state.childBounds.count {
            return (ix, state.childBounds[ix].top + state.offset.y - state.bounds.top)
        }
        return (ix, px(0))
    }

    public func logicalScrollBottom() -> (Int, Pixels) {
        let ix = bottomItem()
        if ix < state.childBounds.count {
            return (ix, state.childBounds[ix].bottom + state.offset.y - state.bounds.bottom)
        }
        return (ix, px(0))
    }

    public func childrenCount() -> Int {
        state.childBounds.count
    }
}
