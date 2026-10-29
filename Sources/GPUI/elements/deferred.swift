// Ported from: crates/gpui/src/elements/deferred.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

/// Where a deferred element should be rendered.
public enum DeferredTarget: Sendable, Equatable {
    /// Render the deferred element in the current scene.
    case local
    /// Render the deferred element in the window overlay scene when available.
    case windowOverlay
}

/// An element which delays the painting of its child until after all of
/// its ancestors, while keeping its layout as part of the current element tree.
public struct Deferred: Element, IntoElement {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Void

    public var child: AnyElement?
    public var priority: Int
    public var target: DeferredTarget

    public init(child: some IntoElement) {
        self.child = child.intoElement().intoAnyElement()
        self.priority = 0
        self.target = .local
    }

    /// Sets the `priority` value of the `deferred` element, which
    /// determines the drawing order relative to other deferred elements,
    /// with higher values being drawn on top.
    public func withPriority(_ priority: Int) -> Self {
        var copy = self
        copy.priority = priority
        return copy
    }

    /// Paint this deferred element into the window overlay layer when possible.
    public func windowOverlay() -> Self {
        var copy = self
        copy.target = .windowOverlay
        return copy
    }

    /// Sets a priority for the element. A higher priority conceptually means painting the element
    /// on top of deferred draws with a lower priority (i.e. closer to the viewer).
    public func priority(_ priority: Int) -> Self {
        var copy = self
        copy.priority = priority
        return copy
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
        guard var child = self.child else {
            fatalError("Deferred child missing")
        }
        let layoutId = child.requestLayout(&window, &cx)
        self.child = child
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
    ) {
        guard let child = self.child else { return }
        self.child = nil
        let elementOffset = window.elementOffset()
        window.deferDrawWithTarget(child: child, offset: elementOffset, priority: self.priority, target: self.target)
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
    }

    public func intoElement() -> Deferred {
        self
    }
}

/// Builds a `Deferred` element, which delays the layout and paint of its child.
public func deferred(_ child: some IntoElement) -> Deferred {
    Deferred(child: child)
}

// PORT NOTE: ElementBox wraps AnyElement for execution during deferred frame draw on MainActor.
private final class ElementBox: @unchecked Sendable {
    var element: AnyElement
    init(_ element: AnyElement) { self.element = element }
}

extension Window {
    @MainActor
    public mutating func deferDrawWithTarget(
        child: AnyElement,
        offset: Point<Pixels>,
        priority: Int,
        target: DeferredTarget
    ) {
        let box = ElementBox(child)
        self.deferDraw(priority: priority) { window, cx in
            window.withElementOffset(offset) { window in
                _ = box.element.prepaint(&window, &cx)
                box.element.paint(&window, &cx)
            }
        }
    }
}
