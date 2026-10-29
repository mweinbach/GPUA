// Ported from: crates/gpui/src/elements/surface.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy
#if canImport(CoreVideo)
import CoreVideo
#endif

/// A source of a surface's content.
public enum SurfaceSource {
    #if canImport(CoreVideo)
    /// A macOS image buffer from CoreVideo
    case surface(CVPixelBuffer)
    #else
    case surface(AnyObject)
    #endif
}

/// A surface element.
public struct Surface: Element, IntoElement, Styled {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Void

    public var source: SurfaceSource
    public var objectFit: ObjectFit
    public var style: StyleRefinement

    public init(source: SurfaceSource) {
        self.source = source
        self.objectFit = .contain
        self.style = StyleRefinement()
    }

    /// Set the object fit for the image.
    public func objectFit(_ objectFit: ObjectFit) -> Self {
        var copy = self
        copy.objectFit = objectFit
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
        var s = Style()
        s.refine(self.style)
        let layoutId = window.requestLayout(s, [], &cx)
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
        #if os(macOS)
        switch self.source {
        case .surface(let pixelBuffer):
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let imageSize = Size<DevicePixels>(width: DevicePixels(Int32(width)), height: DevicePixels(Int32(height)))
            let newBounds = self.objectFit.getBounds(bounds: bounds, imageSize: imageSize)
            _ = newBounds
        }
        #endif
    }

    public func intoElement() -> Surface {
        self
    }
}

/// Create a new surface element.
public func surface(_ source: SurfaceSource) -> Surface {
    Surface(source: source)
}
