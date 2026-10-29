// Ported from: crates/gpui/src/elements/image_cache.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Scheduler
import Taffy

/// An image loading task associated with an image cache.
public typealias ImageLoadingTask = Task<Result<RenderImage, ImageCacheError>>

/// An image cache item
public enum ImageCacheItem {
    /// The associated image is currently loading
    case loading(ImageLoadingTask)
    /// This item has loaded an image.
    case loaded(Result<RenderImage, ImageCacheError>)

    /// Attempt to get the image from the cache item.
    public mutating func get() -> Result<RenderImage, ImageCacheError>? {
        switch self {
        case .loading:
            return nil
        case .loaded(let res):
            return res
        }
    }
}

/// An object that can handle the caching and unloading of images.
public protocol ImageCache: AnyObject {
    /// Load an image given a resource.
    /// Returns the result of loading the image if it has finished loading, or nil if still loading.
    func load(
        _ resource: Resource,
        _ window: inout Window,
        _ cx: inout App
    ) -> Result<RenderImage, ImageCacheError>?
}

/// A dynamically typed image cache, which can be used to store any image cache.
// PORT NOTE: In upstream GPUI, AnyImageCache wraps AnyEntity and is only accessed on the main thread during layout/paint.
public struct AnyImageCache: @unchecked Sendable {
    private let loadFn: (Resource, inout Window, inout App) -> Result<RenderImage, ImageCacheError>?

    public init<I: ImageCache>(_ imageCache: I) {
        self.loadFn = { [weak imageCache] resource, window, cx in
            imageCache?.load(resource, &window, &cx)
        }
    }

    public init(load: @escaping (Resource, inout Window, inout App) -> Result<RenderImage, ImageCacheError>?) {
        self.loadFn = load
    }

    /// Load an image given a resource
    public func load(
        _ resource: Resource,
        _ window: inout Window,
        _ cx: inout App
    ) -> Result<RenderImage, ImageCacheError>? {
        loadFn(resource, &window, &cx)
    }
}

/// Helper function to load an image from an image cache.
public func load<I: ImageCache>(
    _ imageCache: I,
    _ resource: Resource,
    _ window: inout Window,
    _ cx: inout App
) -> Result<RenderImage, ImageCacheError>? {
    imageCache.load(resource, &window, &cx)
}

/// An object that can create an ImageCache during the render phase.
public protocol ImageCacheProvider {
    /// Called during the request_layout phase to create an ImageCache.
    mutating func provide(_ window: inout Window, _ cx: inout App) -> AnyImageCache
}

/// An implementation of ImageCache that retains all loaded images.
public final class RetainAllImageCache: ImageCache {
    private var cache: [UInt64: ImageCacheItem] = [:]

    public init() {}

    /// Create a new image cache.
    public static func new(_ cx: inout App) -> RetainAllImageCache {
        RetainAllImageCache()
    }

    /// Load an image from the given source.
    public func load(
        _ resource: Resource,
        _ window: inout Window,
        _ cx: inout App
    ) -> Result<RenderImage, ImageCacheError>? {
        let h = hash(resource)
        if var item = cache[h] {
            let res = item.get()
            cache[h] = item
            return res
        }

        let dummyTask = Task.ready(Result<RenderImage, ImageCacheError>.success(RenderImage()))
        cache[h] = .loading(dummyTask)
        return nil
    }

    /// Clear the image cache.
    public func clear(_ window: inout Window, _ cx: inout App) {
        cache.removeAll()
    }

    /// Remove the image from the cache by the given source.
    public func remove(_ source: Resource, _ window: inout Window, _ cx: inout App) {
        let h = hash(source)
        cache.removeValue(forKey: h)
    }

    /// Returns the number of images in the cache.
    public func len() -> Int {
        cache.count
    }

    /// Returns true if the cache is empty.
    public func isEmpty() -> Bool {
        cache.isEmpty
    }
}

/// A provider struct for creating a retain-all image cache inline.
public struct RetainAllImageCacheProvider: ImageCacheProvider {
    public var id: ElementId

    public init(id: ElementId) {
        self.id = id
    }

    public mutating func provide(_ window: inout Window, _ cx: inout App) -> AnyImageCache {
        let cache = RetainAllImageCache.new(&cx)
        return AnyImageCache(cache)
    }
}

/// Constructs a retain-all image cache that uses the element state associated with the given ID.
public func retainAll(_ id: ElementId) -> RetainAllImageCacheProvider {
    RetainAllImageCacheProvider(id: id)
}

/// An image cache element.
public struct ImageCacheElement: Element, IntoElement, ParentElement, Styled {
    public typealias RequestLayoutState = [LayoutId]
    public typealias PrepaintState = Void

    public var imageCacheProvider: any ImageCacheProvider
    public var style: StyleRefinement
    public var children: [AnyElement]

    public init(imageCacheProvider: any ImageCacheProvider) {
        self.imageCacheProvider = imageCacheProvider
        self.style = StyleRefinement()
        self.children = []
    }

    public mutating func extend(_ elements: [AnyElement]) {
        self.children.append(contentsOf: elements)
    }

    public func id() -> ElementId? { nil }
    public func sourceLocation() -> String? { nil }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, [LayoutId]) {
        let imageCache = self.imageCacheProvider.provide(&window, &cx)
        return window.withImageCache(imageCache) { window in
            var childLayoutIds: [LayoutId] = []
            for i in 0..<self.children.count {
                childLayoutIds.append(self.children[i].requestLayout(&window, &cx))
            }
            var s = Style()
            s.refine(self.style)
            let layoutId = window.requestLayout(s, childLayoutIds, &cx)
            return (layoutId, childLayoutIds)
        }
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout [LayoutId],
        _ window: inout Window,
        _ cx: inout App
    ) {
        for i in 0..<self.children.count {
            _ = self.children[i].prepaint(&window, &cx)
        }
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout [LayoutId],
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        let imageCache = self.imageCacheProvider.provide(&window, &cx)
        window.withImageCache(imageCache) { window in
            for i in 0..<self.children.count {
                self.children[i].paint(&window, &cx)
            }
        }
    }

    public func intoElement() -> ImageCacheElement { self }
}

/// An image cache element, all its child img elements will use the cache specified by this element.
public func imageCache(_ provider: any ImageCacheProvider) -> ImageCacheElement {
    ImageCacheElement(imageCacheProvider: provider)
}
