// Ported from: crates/gpui/src/elements/img.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Scheduler
import Taffy

/// The delay before showing the loading state.
public let loadingDelay: Duration = .milliseconds(200)

/// An error that can occur when interacting with the image cache.
public enum ImageCacheError: Error, Sendable, Equatable {
    case other(String)
    case io(String)
    case badStatus(uri: SharedUri, status: Int, body: String)
    case asset(SharedString)
    case image(String)
    case usvg(String)
}

/// An image loader for the GPUI asset system
public enum ImageAssetLoader: Asset {
    public typealias Source = Resource
    public typealias Output = Result<RenderImage, ImageCacheError>

    public static func load(source: Resource, cx: inout App) -> Task<Result<RenderImage, ImageCacheError>> {
        Task.ready(.success(RenderImage()))
    }
}

/// A type alias to the resource loader that the `img()` element uses.
public typealias ImgResourceLoader = AssetLogger<ImageAssetLoader>

/// A source of image content.
public enum ImageSource: Sendable, Equatable {
    case resource(Resource)
    case render(RenderImage)
    case custom(@Sendable (inout Window, inout App) -> Result<RenderImage, ImageCacheError>?)

    public static func == (lhs: ImageSource, rhs: ImageSource) -> Bool {
        switch (lhs, rhs) {
        case (.resource(let r1), .resource(let r2)):
            return r1 == r2
        case (.render(let i1), .render(let i2)):
            return i1 == i2
        default:
            return false
        }
    }

    public func useData(
        _ cache: AnyImageCache?,
        _ window: inout Window,
        _ cx: inout App
    ) -> Result<RenderImage, ImageCacheError>? {
        switch self {
        case .resource(let resource):
            if let cache = cache {
                return cache.load(resource, &window, &cx)
            }
            return .success(RenderImage())
        case .render(let data):
            return .success(data)
        case .custom(let loader):
            return loader(&window, &cx)
        }
    }

    public func getData(
        _ cache: AnyImageCache?,
        _ window: inout Window,
        _ cx: inout App
    ) -> Result<RenderImage, ImageCacheError>? {
        useData(cache, &window, &cx)
    }

    /// Remove this image source from the asset system
    @MainActor
    public func removeAsset(_ cx: inout App) {
        switch self {
        case .resource(let resource):
            cx.removeAsset(resource, ImgResourceLoader.self)
        case .custom, .render:
            break
        }
    }
}

/// The style of an image element.
public struct ImageStyle {
    public var grayscale: Bool
    public var objectFit: ObjectFit
    public var loading: (() -> AnyElement)?
    public var fallback: (() -> AnyElement)?

    public init(
        grayscale: Bool = false,
        objectFit: ObjectFit = .contain,
        loading: (() -> AnyElement)? = nil,
        fallback: (() -> AnyElement)? = nil
    ) {
        self.grayscale = grayscale
        self.objectFit = objectFit
        self.loading = loading
        self.fallback = fallback
    }
}

/// Style an image element.
public protocol StyledImage {
    var imageStyle: ImageStyle { get set }

    func grayscale(_ grayscale: Bool) -> Self
    func objectFit(_ objectFit: ObjectFit) -> Self
    func withFallback(_ fallback: @escaping () -> AnyElement) -> Self
    func withLoading(_ loading: @escaping () -> AnyElement) -> Self
}

extension StyledImage {
    public func grayscale(_ grayscale: Bool) -> Self {
        var copy = self
        copy.imageStyle.grayscale = grayscale
        return copy
    }

    public func objectFit(_ objectFit: ObjectFit) -> Self {
        var copy = self
        copy.imageStyle.objectFit = objectFit
        return copy
    }

    public func withFallback(_ fallback: @escaping () -> AnyElement) -> Self {
        var copy = self
        copy.imageStyle.fallback = fallback
        return copy
    }

    public func withLoading(_ loading: @escaping () -> AnyElement) -> Self {
        var copy = self
        copy.imageStyle.loading = loading
        return copy
    }
}

/// The image layout state between frames
public struct ImgLayoutState {
    public var frameIndex: Int
    public var replacement: AnyElement?

    public init(frameIndex: Int = 0, replacement: AnyElement? = nil) {
        self.frameIndex = frameIndex
        self.replacement = replacement
    }
}

/// An image element.
public struct Img: Element, IntoElement, Styled, InteractiveElement, StyledImage {
    public typealias RequestLayoutState = ImgLayoutState
    public typealias PrepaintState = Hitbox?

    public var interactivity: Interactivity
    public var source: ImageSource
    public var style: StyleRefinement
    public var imageStyle: ImageStyle
    public var customImageCache: AnyImageCache?

    public init(source: ImageSource) {
        self.interactivity = Interactivity()
        self.source = source
        self.style = StyleRefinement()
        self.imageStyle = ImageStyle()
        self.customImageCache = nil
    }

    /// A list of all format extensions currently supported by this img element
    public static func extensions() -> [String] {
        [
            "avif", "jpg", "jpeg", "png", "gif", "webp", "tif", "tiff", "tga", "dds", "bmp", "ico",
            "hdr", "exr", "pbm", "pam", "ppm", "pgm", "ff", "farbfeld", "qoi", "svg",
        ]
    }

    /// Sets the image cache for the current node.
    public func imageCache<I: ImageCache>(_ imageCache: I) -> Self {
        var copy = self
        copy.customImageCache = AnyImageCache(imageCache)
        return copy
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
    ) -> (LayoutId, ImgLayoutState) {
        var s = Style()
        s.refine(interactivity.baseStyle)
        s.refine(self.style)
        let layoutId = window.requestLayout(s, [], &cx)
        return (layoutId, ImgLayoutState())
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout ImgLayoutState,
        _ window: inout Window,
        _ cx: inout App
    ) -> Hitbox? {
        guard id != nil else { return nil }
        return window.insertHitbox(bounds)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout ImgLayoutState,
        _ prepaint: inout Hitbox?,
        _ window: inout Window,
        _ cx: inout App
    ) {
        if let dataResult = self.source.useData(self.customImageCache, &window, &cx),
           case .success(let renderImage) = dataResult {
            window.paintImage(
                bounds: bounds,
                image: renderImage,
                grayscale: self.imageStyle.grayscale
            )
        }
    }

    public func intoElement() -> Img {
        self
    }
}

/// Create a new image element.
public func img(_ source: ImageSource) -> Img {
    Img(source: source)
}
