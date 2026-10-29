// Ported from: crates/gpui/src/elements/canvas.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

/// Construct a canvas element with the given paint callback.
/// Useful for adding short term custom drawing to a view.
public func canvas<T>(
    _ prepaint: @escaping (Bounds<Pixels>, inout Window, inout App) -> T,
    _ paint: @escaping (Bounds<Pixels>, T, inout Window, inout App) -> Void
) -> Canvas<T> {
    Canvas(prepaint: prepaint, paint: paint)
}

/// A canvas element, meant for accessing the low level paint API without defining a whole
/// custom element
public struct Canvas<T>: Element, IntoElement, Styled {
    public typealias RequestLayoutState = Style
    public typealias PrepaintState = T?

    private var prepaintCallback: ((Bounds<Pixels>, inout Window, inout App) -> T)?
    private var paintCallback: ((Bounds<Pixels>, T, inout Window, inout App) -> Void)?
    public var style: StyleRefinement

    public init(
        prepaint: @escaping (Bounds<Pixels>, inout Window, inout App) -> T,
        paint: @escaping (Bounds<Pixels>, T, inout Window, inout App) -> Void
    ) {
        self.prepaintCallback = prepaint
        self.paintCallback = paint
        self.style = StyleRefinement()
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
    ) -> (LayoutId, Style) {
        var style = Style()
        style.refine(self.style)
        let layoutId = window.requestLayout(style, [], &cx)
        return (layoutId, style)
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Style,
        _ window: inout Window,
        _ cx: inout App
    ) -> T? {
        guard let prepaint = self.prepaintCallback else { return nil }
        self.prepaintCallback = nil
        return prepaint(bounds, &window, &cx)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Style,
        _ prepaint: inout T?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        guard let prepaintVal = prepaint else { return }
        prepaint = nil
        guard let paint = self.paintCallback else { return }
        self.paintCallback = nil
        requestLayout.paint(bounds, &window, &cx) { window, cx in
            paint(bounds, prepaintVal, &window, &cx)
        }
    }

    public func intoElement() -> Canvas<T> {
        self
    }
}
