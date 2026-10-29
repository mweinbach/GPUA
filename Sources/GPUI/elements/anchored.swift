// Ported from: crates/gpui/src/elements/anchored.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

/// The state that the anchored element uses to track its children.
public struct AnchoredState {
    public var childLayoutIds: [LayoutId]

    public init(childLayoutIds: [LayoutId] = []) {
        self.childLayoutIds = childLayoutIds
    }
}

/// Which algorithm to use when fitting the anchored element to be inside the window.
public enum AnchoredFitMode: Sendable, Equatable {
    /// Snap the anchored element to the window edge.
    case snapToWindow
    /// Snap to window edge and leave some margins.
    case snapToWindowWithMargin(Edges<Pixels>)
    /// Switch which corner anchor this anchored element is attached to.
    case switchAnchor
}

/// Which algorithm to use when positioning the anchored element.
public enum AnchoredPositionMode: Sendable, Equatable {
    /// Position the anchored element relative to the window.
    case window
    /// Position the anchored element relative to its parent.
    case local

    public func getPositionAndBounds(
        anchorPosition: Point<Pixels>?,
        anchorCorner: Corner,
        size: Size<Pixels>,
        bounds: Bounds<Pixels>,
        offset: Point<Pixels>?
    ) -> (Point<Pixels>, Bounds<Pixels>) {
        let offset = offset ?? .zero

        switch self {
        case .window:
            let anchorPos = anchorPosition ?? bounds.origin
            let b = Bounds(corner: anchorCorner, origin: anchorPos + offset, size: size)
            return (anchorPos, b)
        case .local:
            let anchorPos = anchorPosition ?? .zero
            let b = Bounds(corner: anchorCorner, origin: bounds.origin + anchorPos + offset, size: size)
            return (anchorPos, b)
        }
    }
}

/// An anchored element that can be used to display UI that
/// will avoid overflowing the window bounds.
public struct Anchored: Element, IntoElement, ParentElement {
    public typealias RequestLayoutState = AnchoredState
    public typealias PrepaintState = Void

    public var children: [AnyElement]
    public var anchorCorner: Corner
    public var fitMode: AnchoredFitMode
    public var anchorPosition: Point<Pixels>?
    public var positionMode: AnchoredPositionMode
    public var offset: Point<Pixels>?

    public init() {
        self.children = []
        self.anchorCorner = .topLeft
        self.fitMode = .switchAnchor
        self.anchorPosition = nil
        self.positionMode = .window
        self.offset = nil
    }

    /// Sets which corner of the anchored element should be anchored to the current position.
    public func anchor(_ anchor: Corner) -> Self {
        var copy = self
        copy.anchorCorner = anchor
        return copy
    }

    /// Sets the position in window coordinates
    /// (otherwise the location the anchored element is rendered is used)
    public func position(_ anchor: Point<Pixels>) -> Self {
        var copy = self
        copy.anchorPosition = anchor
        return copy
    }

    /// Offset the final position by this amount.
    /// Useful when you want to anchor to an element but offset from it, such as in PopoverMenu.
    public func offset(_ offset: Point<Pixels>) -> Self {
        var copy = self
        copy.offset = offset
        return copy
    }

    /// Sets the position mode for this anchored element. Local will have this
    /// interpret its `position` as relative to the parent element.
    /// While Window will have it interpret the position as relative to the window.
    public func positionMode(_ mode: AnchoredPositionMode) -> Self {
        var copy = self
        copy.positionMode = mode
        return copy
    }

    /// Snap to window edge instead of switching anchor corner when an overflow would occur.
    public func snapToWindow() -> Self {
        var copy = self
        copy.fitMode = .snapToWindow
        return copy
    }

    /// Snap to window edge and leave some margins.
    public func snapToWindowWithMargin(_ edges: Edges<Pixels>) -> Self {
        var copy = self
        copy.fitMode = .snapToWindowWithMargin(edges)
        return copy
    }

    public mutating func extend(_ elements: [AnyElement]) {
        self.children.append(contentsOf: elements)
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
    ) -> (LayoutId, AnchoredState) {
        var childLayoutIds: [LayoutId] = []
        childLayoutIds.reserveCapacity(children.count)

        for i in 0..<children.count {
            let layoutId = children[i].requestLayout(&window, &cx)
            childLayoutIds.append(layoutId)
        }

        var anchoredStyle = Style()
        anchoredStyle.position = .absolute
        anchoredStyle.display = .flex

        let layoutId = window.requestLayout(anchoredStyle, childLayoutIds, &cx)
        return (layoutId, AnchoredState(childLayoutIds: childLayoutIds))
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout AnchoredState,
        _ window: inout Window,
        _ cx: inout App
    ) {
        if requestLayout.childLayoutIds.isEmpty {
            return
        }

        var childMin = point(Pixels(Float.greatestFiniteMagnitude), Pixels(Float.greatestFiniteMagnitude))
        var childMax = Point<Pixels>.zero
        for childLayoutId in requestLayout.childLayoutIds {
            let childBounds = window.layoutBounds(childLayoutId)
            childMin = childMin.min(childBounds.origin)
            childMax = childMax.max(childBounds.bottomRight)
        }
        let size = Size<Pixels>(width: childMax.x - childMin.x, height: childMax.y - childMin.y)

        let (origin, desiredBounds) = self.positionMode.getPositionAndBounds(
            anchorPosition: self.anchorPosition,
            anchorCorner: self.anchorCorner,
            size: size,
            bounds: bounds,
            offset: self.offset
        )
        var desired = desiredBounds

        let limits = Bounds<Pixels>(
            origin: .zero,
            size: window.viewportSize
        )

        if self.fitMode == .switchAnchor {
            var anchorCorner = self.anchorCorner

            if desired.left < limits.left || desired.right > limits.right {
                let switched = Bounds(
                    corner: anchorCorner.otherSideCornerAlong(.horizontal),
                    origin: origin,
                    size: size
                )
                if !(switched.left < limits.left || switched.right > limits.right) {
                    anchorCorner = anchorCorner.otherSideCornerAlong(.horizontal)
                    desired = switched
                }
            }

            if desired.top < limits.top || desired.bottom > limits.bottom {
                let switched = Bounds(
                    corner: anchorCorner.otherSideCornerAlong(.vertical),
                    origin: origin,
                    size: size
                )
                if !(switched.top < limits.top || switched.bottom > limits.bottom) {
                    desired = switched
                }
            }
        }

        let clientInset = window.clientInset()
        let edges: Edges<Pixels>
        switch self.fitMode {
        case .snapToWindowWithMargin(let m):
            edges = m.map { $0 + clientInset }
        default:
            edges = Edges.zero.map { $0 + clientInset }
        }

        if desired.right > limits.right {
            desired.origin.x -= desired.right - limits.right + edges.right
        }
        if desired.left < limits.left {
            desired.origin.x = limits.origin.x + edges.left
        }

        if desired.bottom > limits.bottom {
            desired.origin.y -= desired.bottom - limits.bottom + edges.bottom
        }
        if desired.top < limits.top {
            desired.origin.y = limits.origin.y + edges.top
        }

        let rawOffset = desired.origin - bounds.origin
        let offset = point(px(rawOffset.x.value.rounded()), px(rawOffset.y.value.rounded()))

        window.withElementOffset(offset) { window in
            for i in 0..<self.children.count {
                _ = self.children[i].prepaint(&window, &cx)
            }
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout AnchoredState,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        for i in 0..<self.children.count {
            self.children[i].paint(&window, &cx)
        }
    }

    public func intoElement() -> Anchored {
        self
    }
}

/// anchored gives you an element that will avoid overflowing the window bounds.
/// Its children should have no margin to avoid measurement issues.
public func anchored() -> Anchored {
    Anchored()
}
