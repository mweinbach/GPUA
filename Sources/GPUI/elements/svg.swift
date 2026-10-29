// Ported from: crates/gpui/src/elements/svg.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

/// A transformation to apply to an SVG element.
public struct Transformation: Sendable, Equatable {
    public var scale: Size<Float>
    public var translate: Point<Pixels>
    public var rotate: Radians

    public init(
        scale: Size<Float> = Size(width: 1.0, height: 1.0),
        translate: Point<Pixels> = .zero,
        rotate: Radians = Radians(0.0)
    ) {
        self.scale = scale
        self.translate = translate
        self.rotate = rotate
    }

    /// Create a new Transformation with the specified scale along each axis.
    public static func scale(_ scale: Size<Float>) -> Self {
        Self(scale: scale, translate: .zero, rotate: Radians(0.0))
    }

    /// Create a new Transformation with the specified translation.
    public static func translate(_ translate: Point<Pixels>) -> Self {
        Self(scale: Size(width: 1.0, height: 1.0), translate: translate, rotate: Radians(0.0))
    }

    /// Create a new Transformation with the specified rotation in radians.
    public static func rotate(_ rotate: Radians) -> Self {
        Self(scale: Size(width: 1.0, height: 1.0), translate: .zero, rotate: rotate)
    }

    /// Update the scaling factor of this transformation.
    public func withScaling(_ scale: Size<Float>) -> Self {
        var copy = self
        copy.scale = scale
        return copy
    }

    /// Update the translation value of this transformation.
    public func withTranslation(_ translate: Point<Pixels>) -> Self {
        var copy = self
        copy.translate = translate
        return copy
    }

    /// Update the rotation angle of this transformation.
    public func withRotation(_ rotate: Radians) -> Self {
        var copy = self
        copy.rotate = rotate
        return copy
    }

    public func intoMatrix(center: Point<Pixels>, scaleFactor: Float) -> TransformationMatrix {
        TransformationMatrix.unit
            .translate(center.scale(scaleFactor) + self.translate.scale(scaleFactor))
            .rotate(self.rotate)
            .scale(self.scale)
            .translate(center.scale(-scaleFactor))
    }
}

/// An SVG element.
public struct Svg: Element, IntoElement, Styled, InteractiveElement {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Hitbox?

    public var interactivity: Interactivity
    public var transformation: Transformation?
    public var path: SharedString?
    public var externalPath: SharedString?

    public init() {
        self.interactivity = Interactivity()
        self.transformation = nil
        self.path = nil
        self.externalPath = nil
    }

    /// Set the path to the SVG file for this element.
    public func path(_ path: SharedString) -> Self {
        var copy = self
        copy.path = path
        return copy
    }

    /// Set the path to the SVG file for this element.
    public func externalPath(_ path: SharedString) -> Self {
        var copy = self
        copy.externalPath = path
        return copy
    }

    /// Transform the SVG element with the given transformation.
    public func withTransformation(_ transformation: Transformation) -> Self {
        var copy = self
        copy.transformation = transformation
        return copy
    }

    public var style: StyleRefinement {
        get { interactivity.baseStyle }
        set { interactivity.baseStyle = newValue }
    }

    public func id() -> ElementId? {
        interactivity.elementId
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
        style.refine(interactivity.baseStyle)
        let layoutId = window.requestLayout(style, [], &cx)
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
    ) -> Hitbox? {
        self.interactivity.prepaint(
            id,
            inspectorId,
            bounds,
            bounds.size,
            &window,
            &cx
        ) { _, _, hitbox, _, _ in
            hitbox
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout Void,
        _ prepaint: inout Hitbox?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        if let path = self.path ?? self.externalPath {
            let color = interactivity.baseStyle.text.color ?? hsla(0, 0, 0, 1)
            let tf = self.transformation?.intoMatrix(center: bounds.center(), scaleFactor: window.scaleFactor) ?? .unit
            window.paintSvg(bounds: bounds, path: path.description, color: color, transformation: tf)
        }
    }

    public func intoElement() -> Svg {
        self
    }
}

/// Create a new SVG element.
public func svg() -> Svg {
    Svg()
}
