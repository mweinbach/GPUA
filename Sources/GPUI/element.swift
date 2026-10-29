// Ported from: crates/gpui/src/element.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - Element Protocols

/// Implemented by types that participate in laying out and painting the contents of a window.
/// Elements form a tree and are laid out according to web-based layout rules, as implemented by Taffy.
public protocol Element: IntoElement {
    /// The type of state returned from `requestLayout`.
    associatedtype RequestLayoutState = Void
    /// The type of state returned from `prepaint`.
    associatedtype PrepaintState = Void

    /// If this element has a unique identifier, return it here.
    func id() -> ElementId?

    /// Source location where this element was constructed, used for debugging and inspector.
    func sourceLocation() -> String?

    /// Request layout from Taffy and initialize element state.
    @MainActor
    mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, RequestLayoutState)

    /// Prepaint phase: commit bounds, hitboxes, tooltips, autoscroll.
    @MainActor
    mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout RequestLayoutState,
        _ window: inout Window,
        _ cx: inout App
    ) -> PrepaintState

    /// Paint phase: emit scene primitives to the window.
    @MainActor
    mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout RequestLayoutState,
        _ prepaint: inout PrepaintState,
        _ window: inout Window,
        _ cx: inout App
    )

    /// Convert this element into a dynamically-typed `AnyElement`.
    func intoAny() -> AnyElement
}

extension Element {
    public func id() -> ElementId? {
        nil
    }

    public func sourceLocation() -> String? {
        nil
    }

    public func intoAny() -> AnyElement {
        AnyElement(self)
    }

    public func intoElement() -> Self {
        self
    }

    public func intoAnyElement() -> AnyElement {
        intoAny()
    }
}

/// Implemented by any type that can be converted into an element.
public protocol IntoElement {
    associatedtype ElementType: Element
    func intoElement() -> ElementType
    func intoAnyElement() -> AnyElement
}

extension IntoElement where Self: Element, ElementType == Self {
    public func intoElement() -> Self {
        self
    }

    public func intoAnyElement() -> AnyElement {
        intoAny()
    }
}

/// An object that can be drawn to the screen. Views are entities that implement Render.
public protocol Render {
    associatedtype RenderedElement: IntoElement = AnyElement
    mutating func render(_ window: inout Window, _ cx: inout Context<Self>) -> RenderedElement
}

/// Allows plain data to construct reusable components without breaking the fluent builder API.
public protocol RenderOnce {
    associatedtype RenderedElement: IntoElement = AnyElement
    func render(_ window: inout Window, _ cx: inout App) -> RenderedElement
}

/// Helper protocol providing a uniform interface for elements that can accept children.
public protocol ParentElement {
    mutating func extend(_ elements: [AnyElement])
}

extension ParentElement {
    public mutating func extend<S: Sequence>(_ elements: S) where S.Element == AnyElement {
        self.extend(elements as? [AnyElement] ?? Array(elements))
    }

    public func child(_ child: some IntoElement) -> Self {
        var copy = self
        copy.extend([child.intoElement().intoAnyElement()])
        return copy
    }

    public func children(_ children: some Sequence<some IntoElement>) -> Self {
        var copy = self
        copy.extend(children.map { $0.intoElement().intoAnyElement() })
        return copy
    }
}

// MARK: - GlobalElementId

/// A globally unique identifier for an element, used to track state across frames.
public struct GlobalElementId: Sendable, Equatable, Hashable, CustomStringConvertible {
    public var path: [ElementId]

    public init(_ path: [ElementId] = []) {
        self.path = path
    }

    public init(_ id: ElementId) {
        self.path = [id]
    }

    public var description: String {
        path.map { "\($0)" }.joined(separator: ".")
    }
}

// MARK: - Component Element

/// An element for rendering components that implement `RenderOnce`.
public struct Component<C: RenderOnce>: Element {
    public typealias RequestLayoutState = (AnyElement, String)
    public typealias PrepaintState = Void

    public var component: C?
    public var source: String?

    public init(_ component: C) {
        self.component = component
        self.source = nil
    }

    public static func new(_ component: C) -> Component<C> {
        Component(component)
    }

    public func id() -> ElementId? {
        nil
    }

    public func sourceLocation() -> String? {
        source
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, (AnyElement, String)) {
        let typeName = String(describing: C.self)
        return window.withId(ElementId.name(SharedString(typeName))) { window in
            guard let comp = self.component else {
                fatalError("Component render called without component")
            }
            self.component = nil
            var element = comp.render(&window, &cx).intoAnyElement()
            let layoutId = element.requestLayout(&window, &cx)
            return (layoutId, (element, typeName))
        }
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout (AnyElement, String),
        _ window: inout Window,
        _ cx: inout App
    ) -> Void {
        window.withId(ElementId.name(SharedString(requestLayout.1))) { window in
            _ = requestLayout.0.prepaint(&window, &cx)
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout (AnyElement, String),
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        window.withId(ElementId.name(SharedString(requestLayout.1))) { window in
            requestLayout.0.paint(&window, &cx)
        }
    }
}

// MARK: - ElementObject & Drawable

// PORT NOTE: ElementObject implementations are thread-confined to window draw pipeline.
private protocol AnyElementObject: AnyObject, Sendable {
    func innerElementAny() -> Any
    @MainActor func requestLayout(_ window: inout Window, _ cx: inout App) -> LayoutId
    @MainActor func prepaint(_ window: inout Window, _ cx: inout App)
    @MainActor func paint(_ window: inout Window, _ cx: inout App)
    @MainActor func layoutAsRoot(_ availableSpace: Size<AvailableSpace>, _ window: inout Window, _ cx: inout App) -> Size<Pixels>
}

private enum ElementDrawPhase<RequestLayoutState, PrepaintState> {
    case start
    case requestLayout(
        layoutId: LayoutId,
        globalId: GlobalElementId?,
        inspectorId: InspectorElementId?,
        requestLayout: RequestLayoutState
    )
    case layoutComputed(
        layoutId: LayoutId,
        globalId: GlobalElementId?,
        inspectorId: InspectorElementId?,
        availableSpace: Size<AvailableSpace>,
        requestLayout: RequestLayoutState
    )
    case prepaint(
        nodeId: DispatchNodeId,
        globalId: GlobalElementId?,
        inspectorId: InspectorElementId?,
        bounds: Bounds<Pixels>,
        requestLayout: RequestLayoutState,
        prepaint: PrepaintState
    )
    case painted
}

/// A wrapper around an implementer of `Element` that tracks layout and drawing lifecycle phases.
// PORT NOTE: Drawable is thread-confined to window draw pipeline on the main thread.
public final class Drawable<E: Element>: AnyElementObject, @unchecked Sendable {
    public var element: E
    private var phase: ElementDrawPhase<E.RequestLayoutState, E.PrepaintState>

    public init(_ element: E) {
        self.element = element
        self.phase = .start
    }

    public static func new(_ element: E) -> Drawable<E> {
        Drawable(element)
    }

    fileprivate func innerElementAny() -> Any {
        element
    }

    @MainActor
    public func requestLayout(_ window: inout Window, _ cx: inout App) -> LayoutId {
        switch phase {
        case .start:
            let globalId: GlobalElementId?
            if let elementId = element.id() {
                window.elementIdStack.append(elementId)
                globalId = GlobalElementId(window.elementIdStack)
            } else {
                globalId = nil
            }

            let inspectorId: InspectorElementId? = nil
            let (layoutId, requestLayoutState) = element.requestLayout(
                globalId,
                inspectorId,
                &window,
                &cx
            )

            if globalId != nil {
                _ = window.elementIdStack.removeLast()
            }

            phase = .requestLayout(
                layoutId: layoutId,
                globalId: globalId,
                inspectorId: inspectorId,
                requestLayout: requestLayoutState
            )
            return layoutId

        default:
            fatalError("must call request_layout only once")
        }
    }

    @MainActor
    public func prepaint(_ window: inout Window, _ cx: inout App) {
        switch phase {
        case .requestLayout(let layoutId, let globalId, let inspectorId, var requestLayoutState),
             .layoutComputed(let layoutId, let globalId, let inspectorId, _, var requestLayoutState):
            if let elementId = element.id() {
                window.elementIdStack.append(elementId)
            }

            let bounds = window.layoutBounds(id: layoutId)
            let nodeId = window.nextFrame.dispatchTree.pushNode()
            let prepaintState = element.prepaint(
                globalId,
                inspectorId,
                bounds,
                &requestLayoutState,
                &window,
                &cx
            )
            window.nextFrame.dispatchTree.popNode()

            if element.id() != nil {
                _ = window.elementIdStack.removeLast()
            }

            phase = .prepaint(
                nodeId: nodeId,
                globalId: globalId,
                inspectorId: inspectorId,
                bounds: bounds,
                requestLayout: requestLayoutState,
                prepaint: prepaintState
            )

        default:
            fatalError("must call request_layout before prepaint")
        }
    }

    @MainActor
    public func paint(_ window: inout Window, _ cx: inout App) {
        _ = paintAndReturnState(&window, &cx)
    }

    @discardableResult
    @MainActor
    public func paintAndReturnState(
        _ window: inout Window,
        _ cx: inout App
    ) -> (E.RequestLayoutState, E.PrepaintState) {
        switch phase {
        case .prepaint(let nodeId, let globalId, let inspectorId, let bounds, var requestLayoutState, var prepaintState):
            if let elementId = element.id() {
                window.elementIdStack.append(elementId)
            }

            window.nextFrame.dispatchTree.setActiveNode(nodeId)
            element.paint(
                globalId,
                inspectorId,
                bounds,
                &requestLayoutState,
                &prepaintState,
                &window,
                &cx
            )

            if element.id() != nil {
                _ = window.elementIdStack.removeLast()
            }

            phase = .painted
            return (requestLayoutState, prepaintState)

        default:
            fatalError("must call prepaint before paint")
        }
    }

    @MainActor
    public func layoutAsRoot(
        _ availableSpace: Size<AvailableSpace>,
        _ window: inout Window,
        _ cx: inout App
    ) -> Size<Pixels> {
        if case .start = phase {
            _ = requestLayout(&window, &cx)
        }

        let layoutId: LayoutId
        switch phase {
        case .requestLayout(let id, let globalId, let inspectorId, let requestLayoutState):
            window.computeLayout(id: id, availableSpace: availableSpace, cx: &cx)
            phase = .layoutComputed(
                layoutId: id,
                globalId: globalId,
                inspectorId: inspectorId,
                availableSpace: availableSpace,
                requestLayout: requestLayoutState
            )
            layoutId = id

        case .layoutComputed(let id, let globalId, let inspectorId, let prevSpace, let requestLayoutState):
            if availableSpace != prevSpace {
                window.computeLayout(id: id, availableSpace: availableSpace, cx: &cx)
            }
            phase = .layoutComputed(
                layoutId: id,
                globalId: globalId,
                inspectorId: inspectorId,
                availableSpace: availableSpace,
                requestLayout: requestLayoutState
            )
            layoutId = id

        default:
            fatalError("cannot measure after painting")
        }

        return window.layoutBounds(id: layoutId).size
    }
}

// MARK: - AnyElement

/// A dynamically typed element that can store any element type.
// PORT NOTE: AnyElement is thread-confined to window draw pipeline on the main thread.
public struct AnyElement: Element, @unchecked Sendable {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Void

    private var object: any AnyElementObject

    public init<E: Element>(_ element: E) {
        self.object = Drawable(element)
    }

    public static func new<E: Element>(_ element: E) -> AnyElement {
        AnyElement(element)
    }

    public func downcastMut<T>() -> T? {
        object.innerElementAny() as? T
    }

    @MainActor
    public mutating func requestLayout(_ window: inout Window, _ cx: inout App) -> LayoutId {
        object.requestLayout(&window, &cx)
    }

    @MainActor
    public mutating func prepaint(_ window: inout Window, _ cx: inout App) -> FocusHandle? {
        let focusAssigned = window.nextFrame.focus != nil
        object.prepaint(&window, &cx)
        if !focusAssigned, let focusId = window.nextFrame.focus {
            return FocusHandle.forId(focusId, handles: cx.focusHandles)
        }
        return nil
    }

    @MainActor
    public mutating func paint(_ window: inout Window, _ cx: inout App) {
        object.paint(&window, &cx)
    }

    @MainActor
    public mutating func layoutAsRoot(
        _ availableSpace: Size<AvailableSpace>,
        _ window: inout Window,
        _ cx: inout App
    ) -> Size<Pixels> {
        object.layoutAsRoot(availableSpace, &window, &cx)
    }

    @MainActor
    public mutating func prepaintAt(
        _ origin: Point<Pixels>,
        _ window: inout Window,
        _ cx: inout App
    ) -> FocusHandle? {
        window.withAbsoluteElementOffset(origin) { window in
            self.prepaint(&window, &cx)
        }
    }

    @MainActor
    public mutating func prepaintAsRoot(
        _ origin: Point<Pixels>,
        _ availableSpace: Size<AvailableSpace>,
        _ window: inout Window,
        _ cx: inout App
    ) -> FocusHandle? {
        _ = layoutAsRoot(availableSpace, &window, &cx)
        return window.withAbsoluteElementOffset(origin) { window in
            self.prepaint(&window, &cx)
        }
    }

    public func id() -> ElementId? {
        nil
    }

    public func sourceLocation() -> String? {
        nil
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, Void) {
        let layoutId = requestLayout(&window, &cx)
        return (layoutId, ())
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) -> Void {
        _ = prepaint(&window, &cx)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        paint(&window, &cx)
    }
}

// MARK: - Empty Element

/// The empty element, which renders nothing.
public struct Empty: Element, Render {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Void

    public init() {}

    public func id() -> ElementId? {
        nil
    }

    public func sourceLocation() -> String? {
        nil
    }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, Void) {
        var style = Style()
        style.display = .none
        let layoutId = window.requestLayout(style: style)
        return (layoutId, ())
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) -> Void {}

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {}

    public func render(_ window: inout Window, _ cx: inout Context<Empty>) -> Empty {
        self
    }
}
