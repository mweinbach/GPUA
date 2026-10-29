// Ported from: crates/gpui/src/assets.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// A source of assets for this app to use.
public protocol AssetSource: Sendable {
    /// Load the given asset from the source path.
    func load(_ path: String) throws -> Data?

    /// List the assets at the given path.
    func list(_ path: String) throws -> [SharedString]
}

/// A unique identifier for the image cache
@frozen
public struct ImageId: Sendable, Equatable, Hashable, RawRepresentable, Comparable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: ImageId, rhs: ImageId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct RenderImageParams: Sendable, Equatable, Hashable {
    public var imageId: ImageId
    public var frameIndex: Int
    public var crop: Bounds<DevicePixels>?

    public init(imageId: ImageId, frameIndex: Int = 0, crop: Bounds<DevicePixels>? = nil) {
        self.imageId = imageId
        self.frameIndex = frameIndex
        self.crop = crop
    }
}

public struct ImageFrame: Sendable, Equatable {
    public var bytes: [UInt8]
    public var width: Int
    public var height: Int
    public var delay: Duration

    public init(bytes: [UInt8] = [], width: Int = 0, height: Int = 0, delay: Duration = .zero) {
        self.bytes = bytes
        self.width = width
        self.height = height
        self.delay = delay
    }
}

// PORT NOTE: Synchronized via NSLock matching upstream AtomicUsize NEXT_ID for ImageId generation.
private let nextImageIdLock = NSLock()
nonisolated(unsafe) private var nextImageIdCounter = 0

private func allocateImageId() -> ImageId {
    nextImageIdLock.lock()
    defer { nextImageIdLock.unlock() }
    let id = nextImageIdCounter
    nextImageIdCounter += 1
    return ImageId(id)
}

/// A cached and processed image, in BGRA format
public struct RenderImage: Sendable, Equatable {
    /// The ID associated with this image
    public var id: ImageId
    /// The scale factor of this image on render.
    package var scaleFactor: Float
    public var data: [ImageFrame]

    public init(data: [ImageFrame] = [], scaleFactor: Float = 1.0) {
        self.id = allocateImageId()
        self.scaleFactor = scaleFactor
        self.data = data
    }

    /// Create a new image from the given data.
    public static func new(_ data: [ImageFrame]) -> Self {
        Self(data: data)
    }

    /// Set the scale factor for this image.
    /// Use this when the image was rendered at a higher resolution (e.g., 2x for Retina displays).
    public func withScaleFactor(_ scaleFactor: Float) -> Self {
        var copy = self
        copy.scaleFactor = scaleFactor
        return copy
    }

    /// Convert this image into a byte slice.
    public func asBytes(_ frameIndex: Int = 0) -> [UInt8]? {
        guard frameIndex < data.count else { return nil }
        return data[frameIndex].bytes
    }

    /// Get the size of this image, in pixels.
    public func size(_ frameIndex: Int = 0) -> Size<DevicePixels> {
        guard frameIndex < data.count else { return .zero }
        return Size(
            width: DevicePixels(Int32(data[frameIndex].width)),
            height: DevicePixels(Int32(data[frameIndex].height))
        )
    }

    /// Get the size of this image, in pixels for display, adjusted for the scale factor.
    public func renderSize(_ frameIndex: Int = 0) -> Size<Pixels> {
        let s = size(frameIndex)
        let sf = scaleFactor > 0 ? scaleFactor : 1.0
        return Size(
            width: px(Float(s.width.value) / sf),
            height: px(Float(s.height.value) / sf)
        )
    }

    /// Get the delay of this frame from the previous
    public func delay(_ frameIndex: Int = 0) -> Duration {
        guard frameIndex < data.count else { return .zero }
        return data[frameIndex].delay
    }

    /// Get the number of frames for this image.
    public func frameCount() -> Int {
        data.count
    }
}
