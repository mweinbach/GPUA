// Ported from: crates/gpui/src/scene.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
#if os(macOS)
import CoreVideo
#endif

// MARK: - Type Aliases

/// PathVertex specialized with ScaledPixels coordinate space.
public typealias PathVertex_ScaledPixels = PathVertex<ScaledPixels>

/// Drawing order identifier for GPU primitive ordering.
public typealias DrawOrder = UInt32

// MARK: - BorderStyle

/// The style of a border.
@frozen
public enum BorderStyle: UInt32, Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// A solid border.
    case solid = 0
    /// A dashed border.
    case dashed = 1

    public init() {
        self = .solid
    }
}

// MARK: - TransformationMatrix

/// A data type representing a 2 dimensional transformation that can be applied to an element.
@frozen
public struct TransformationMatrix: Sendable, Equatable, Hashable, DefaultInitializable {
    /// 2x2 matrix containing rotation and scale, stored row-major.
    public var rotationScale: ((Float, Float), (Float, Float))
    /// Translation vector.
    public var translation: (Float, Float)

    /// The unit matrix, has no effect.
    public static let unit = TransformationMatrix(
        rotationScale: ((1.0, 0.0), (0.0, 1.0)),
        translation: (0.0, 0.0)
    )

    public init() {
        self = .unit
    }

    public init(
        rotationScale: ((Float, Float), (Float, Float)) = ((1.0, 0.0), (0.0, 1.0)),
        translation: (Float, Float) = (0.0, 0.0)
    ) {
        self.rotationScale = rotationScale
        self.translation = translation
    }

    /// Move the origin by a given point.
    public func translate(_ point: Point<ScaledPixels>) -> TransformationMatrix {
        compose(TransformationMatrix(
            rotationScale: ((1.0, 0.0), (0.0, 1.0)),
            translation: (point.x.value, point.y.value)
        ))
    }

    /// Clockwise rotation in radians around the origin.
    public func rotate(_ angle: Radians) -> TransformationMatrix {
        let cosA = cos(angle.value)
        let sinA = sin(angle.value)
        return compose(TransformationMatrix(
            rotationScale: (
                (cosA, -sinA),
                (sinA, cosA)
            ),
            translation: (0.0, 0.0)
        ))
    }

    /// Scale around the origin.
    public func scale(_ size: Size<Float>) -> TransformationMatrix {
        compose(TransformationMatrix(
            rotationScale: (
                (size.width, 0.0),
                (0.0, size.height)
            ),
            translation: (0.0, 0.0)
        ))
    }

    /// Perform matrix multiplication with another transformation
    /// to produce a new transformation that is the result of
    /// applying both transformations: first, `other`, then `self`.
    @inline(__always)
    public func compose(_ other: TransformationMatrix) -> TransformationMatrix {
        if other == TransformationMatrix.unit {
            return self
        }
        return TransformationMatrix(
            rotationScale: (
                (
                    self.rotationScale.0.0 * other.rotationScale.0.0 + self.rotationScale.0.1 * other.rotationScale.1.0,
                    self.rotationScale.0.0 * other.rotationScale.0.1 + self.rotationScale.0.1 * other.rotationScale.1.1
                ),
                (
                    self.rotationScale.1.0 * other.rotationScale.0.0 + self.rotationScale.1.1 * other.rotationScale.1.0,
                    self.rotationScale.1.0 * other.rotationScale.0.1 + self.rotationScale.1.1 * other.rotationScale.1.1
                )
            ),
            translation: (
                self.translation.0 + self.rotationScale.0.0 * other.translation.0 + self.rotationScale.0.1 * other.translation.1,
                self.translation.1 + self.rotationScale.1.0 * other.translation.0 + self.rotationScale.1.1 * other.translation.1
            )
        )
    }

    /// Apply transformation to a point, mainly useful for debugging.
    public func apply(_ point: Point<Pixels>) -> Point<Pixels> {
        let x = point.x.value
        let y = point.y.value
        let outX = self.translation.0 + self.rotationScale.0.0 * x + self.rotationScale.0.1 * y
        let outY = self.translation.1 + self.rotationScale.1.0 * x + self.rotationScale.1.1 * y
        return Point(x: Pixels(outX), y: Pixels(outY))
    }

    public static func == (lhs: TransformationMatrix, rhs: TransformationMatrix) -> Bool {
        lhs.rotationScale.0.0 == rhs.rotationScale.0.0 &&
        lhs.rotationScale.0.1 == rhs.rotationScale.0.1 &&
        lhs.rotationScale.1.0 == rhs.rotationScale.1.0 &&
        lhs.rotationScale.1.1 == rhs.rotationScale.1.1 &&
        lhs.translation.0 == rhs.translation.0 &&
        lhs.translation.1 == rhs.translation.1
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rotationScale.0.0)
        hasher.combine(rotationScale.0.1)
        hasher.combine(rotationScale.1.0)
        hasher.combine(rotationScale.1.1)
        hasher.combine(translation.0)
        hasher.combine(translation.1)
    }
}

// MARK: - Quad

/// A rectangular quad rendered by the GPU shader.
@frozen
public struct Quad: Sendable, Equatable, DefaultInitializable {
    public var order: DrawOrder
    public var borderStyle: BorderStyle
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var background: Background
    public var borderColor: Hsla
    public var cornerRadii: Corners<ScaledPixels>
    public var borderWidths: Edges<ScaledPixels>

    public init() {
        self.order = 0
        self.borderStyle = .solid
        self.bounds = Bounds(origin: .zero, size: .zero)
        self.contentMask = ContentMask(bounds: Bounds(origin: .zero, size: .zero))
        self.background = Background()
        self.borderColor = transparentBlack()
        self.cornerRadii = .zero
        self.borderWidths = .zero
    }

    public init(
        order: DrawOrder = 0,
        borderStyle: BorderStyle = .solid,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        background: Background = Background(),
        borderColor: Hsla = transparentBlack(),
        cornerRadii: Corners<ScaledPixels> = .zero,
        borderWidths: Edges<ScaledPixels> = .zero
    ) {
        self.order = order
        self.borderStyle = borderStyle
        self.bounds = bounds
        self.contentMask = contentMask
        self.background = background
        self.borderColor = borderColor
        self.cornerRadii = cornerRadii
        self.borderWidths = borderWidths
    }
}

// MARK: - Shadow

/// A shadow rendered under an element.
@frozen
public struct Shadow: Sendable, Equatable, DefaultInitializable {
    public var order: DrawOrder
    public var blurRadius: ScaledPixels
    public var bounds: Bounds<ScaledPixels>
    public var cornerRadii: Corners<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var color: Hsla

    public init() {
        self.order = 0
        self.blurRadius = .zero
        self.bounds = Bounds(origin: .zero, size: .zero)
        self.cornerRadii = .zero
        self.contentMask = ContentMask(bounds: Bounds(origin: .zero, size: .zero))
        self.color = transparentBlack()
    }

    public init(
        order: DrawOrder = 0,
        blurRadius: ScaledPixels = .zero,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        cornerRadii: Corners<ScaledPixels> = .zero,
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        color: Hsla = transparentBlack()
    ) {
        self.order = order
        self.blurRadius = blurRadius
        self.bounds = bounds
        self.cornerRadii = cornerRadii
        self.contentMask = contentMask
        self.color = color
    }
}

// MARK: - Underline

/// An underline rendered under text.
@frozen
public struct Underline: Sendable, Equatable, DefaultInitializable {
    public var order: DrawOrder
    public var pad: UInt32
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var color: Hsla
    public var thickness: ScaledPixels
    public var wavy: UInt32

    public init() {
        self.order = 0
        self.pad = 0
        self.bounds = Bounds(origin: .zero, size: .zero)
        self.contentMask = ContentMask(bounds: Bounds(origin: .zero, size: .zero))
        self.color = transparentBlack()
        self.thickness = .zero
        self.wavy = 0
    }

    public init(
        order: DrawOrder = 0,
        pad: UInt32 = 0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        color: Hsla = transparentBlack(),
        thickness: ScaledPixels = .zero,
        wavy: UInt32 = 0
    ) {
        self.order = order
        self.pad = pad
        self.bounds = bounds
        self.contentMask = contentMask
        self.color = color
        self.thickness = thickness
        self.wavy = wavy
    }
}

// MARK: - MonochromeSprite

/// A single-channel monochrome sprite (e.g. grayscale glyph).
@frozen
public struct MonochromeSprite: Sendable, Equatable {
    public var order: DrawOrder
    public var pad: UInt32
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var color: Hsla
    public var tile: AtlasTile
    public var transformation: TransformationMatrix

    public init(
        order: DrawOrder = 0,
        pad: UInt32 = 0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        color: Hsla = transparentBlack(),
        tile: AtlasTile,
        transformation: TransformationMatrix = .unit
    ) {
        self.order = order
        self.pad = pad
        self.bounds = bounds
        self.contentMask = contentMask
        self.color = color
        self.tile = tile
        self.transformation = transformation
    }
}

// MARK: - SubpixelSprite

/// A subpixel sprite with LCD RGB subpixel anti-aliasing.
@frozen
public struct SubpixelSprite: Sendable, Equatable {
    public var order: DrawOrder
    public var pad: UInt32
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var color: Hsla
    public var tile: AtlasTile
    public var transformation: TransformationMatrix

    public init(
        order: DrawOrder = 0,
        pad: UInt32 = 0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        color: Hsla = transparentBlack(),
        tile: AtlasTile,
        transformation: TransformationMatrix = .unit
    ) {
        self.order = order
        self.pad = pad
        self.bounds = bounds
        self.contentMask = contentMask
        self.color = color
        self.tile = tile
        self.transformation = transformation
    }
}

// MARK: - PolychromeSprite

/// A full-color sprite (e.g. emoji or icon image).
@frozen
public struct PolychromeSprite: Sendable, Equatable {
    public var order: DrawOrder
    public var pad: UInt32
    public var grayscale: UInt32
    public var opacity: Float
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var cornerRadii: Corners<ScaledPixels>
    public var tile: AtlasTile

    public init(
        order: DrawOrder = 0,
        pad: UInt32 = 0,
        grayscale: UInt32 = 0,
        opacity: Float = 1.0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        cornerRadii: Corners<ScaledPixels> = .zero,
        tile: AtlasTile
    ) {
        self.order = order
        self.pad = pad
        self.grayscale = grayscale
        self.opacity = opacity
        self.bounds = bounds
        self.contentMask = contentMask
        self.cornerRadii = cornerRadii
        self.tile = tile
    }

    public init(
        order: DrawOrder = 0,
        pad: UInt32 = 0,
        grayscale: Bool,
        opacity: Float = 1.0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        cornerRadii: Corners<ScaledPixels> = .zero,
        tile: AtlasTile
    ) {
        self.order = order
        self.pad = pad
        self.grayscale = grayscale ? 1 : 0
        self.opacity = opacity
        self.bounds = bounds
        self.contentMask = contentMask
        self.cornerRadii = cornerRadii
        self.tile = tile
    }

    public var isGrayscale: Bool {
        get { grayscale != 0 }
        set { grayscale = newValue ? 1 : 0 }
    }
}

// MARK: - PaintSurface

#if os(macOS)
/// A surface rendered directly (e.g. native video buffer or platform view).
// PORT NOTE: CVPixelBuffer is an immutable/retained frame reference in Scene, safe across concurrency boundaries.
public struct PaintSurface: @unchecked Sendable {
    public var order: DrawOrder
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>
    public var imageBuffer: CVPixelBuffer?

    public init(
        order: DrawOrder = 0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero)),
        imageBuffer: CVPixelBuffer? = nil
    ) {
        self.order = order
        self.bounds = bounds
        self.contentMask = contentMask
        self.imageBuffer = imageBuffer
    }
}

extension PaintSurface: Equatable {
    public static func == (lhs: PaintSurface, rhs: PaintSurface) -> Bool {
        lhs.order == rhs.order &&
        lhs.bounds == rhs.bounds &&
        lhs.contentMask == rhs.contentMask &&
        lhs.imageBuffer === rhs.imageBuffer
    }
}
#else
/// A surface rendered directly (e.g. native video buffer or platform view).
public struct PaintSurface: Sendable {
    public var order: DrawOrder
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>

    public init(
        order: DrawOrder = 0,
        bounds: Bounds<ScaledPixels> = Bounds(origin: .zero, size: .zero),
        contentMask: ContentMask<ScaledPixels> = ContentMask(bounds: Bounds(origin: .zero, size: .zero))
    ) {
        self.order = order
        self.bounds = bounds
        self.contentMask = contentMask
    }
}

extension PaintSurface: Equatable {
    public static func == (lhs: PaintSurface, rhs: PaintSurface) -> Bool {
        lhs.order == rhs.order &&
        lhs.bounds == rhs.bounds &&
        lhs.contentMask == rhs.contentMask
    }
}
#endif

// MARK: - PathId & PathVertex & Path

/// The unique identifier of a vector path within a scene.
@frozen
public struct PathId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A vertex of a vector path with barycentric curve coordinates.
@frozen
public struct PathVertex<P: Sendable & Equatable>: Sendable, Equatable {
    public var xyPosition: Point<P>
    public var stPosition: Point<Float>
    public var contentMask: ContentMask<P>

    public init(
        xyPosition: Point<P>,
        stPosition: Point<Float>,
        contentMask: ContentMask<P>
    ) {
        self.xyPosition = xyPosition
        self.stPosition = stPosition
        self.contentMask = contentMask
    }
}

extension PathVertex where P == Pixels {
    /// Scale this vertex by the given factor.
    public func scale(_ factor: Float) -> PathVertex<ScaledPixels> {
        PathVertex<ScaledPixels>(
            xyPosition: xyPosition.scale(factor),
            stPosition: stPosition,
            contentMask: contentMask.scale(factor)
        )
    }
}

/// A line made up of a series of vertices and control points.
public struct Path<P: Sendable & Equatable>: Sendable, Equatable {
    public var id: PathId
    public var order: DrawOrder
    public var bounds: Bounds<P>
    public var contentMask: ContentMask<P>
    public var vertices: [PathVertex<P>]
    public var color: Background
    private var start: Point<P>
    private var current: Point<P>
    private var contourCount: Int

    public init(
        id: PathId = PathId(0),
        order: DrawOrder = 0,
        bounds: Bounds<P>,
        contentMask: ContentMask<P>,
        vertices: [PathVertex<P>] = [],
        color: Background = Background(),
        start: Point<P>,
        current: Point<P>,
        contourCount: Int = 0
    ) {
        self.id = id
        self.order = order
        self.bounds = bounds
        self.contentMask = contentMask
        self.vertices = vertices
        self.color = color
        self.start = start
        self.current = current
        self.contourCount = contourCount
    }
}

extension Path where P == Pixels {
    /// Create a new path with the given starting point.
    public init(start: Point<Pixels>) {
        self.id = PathId(0)
        self.order = 0
        self.vertices = []
        self.start = start
        self.current = start
        self.bounds = Bounds(origin: start, size: .zero)
        self.contentMask = ContentMask(bounds: Bounds(origin: .zero, size: .zero))
        self.color = Background()
        self.contourCount = 0
    }

    /// Scale this path by the given factor.
    public func scale(_ factor: Float) -> Path<ScaledPixels> {
        Path<ScaledPixels>(
            id: self.id,
            order: self.order,
            bounds: self.bounds.scale(factor),
            contentMask: self.contentMask.scale(factor),
            vertices: self.vertices.map { $0.scale(factor) },
            color: self.color,
            start: self.start.scale(factor),
            current: self.current.scale(factor),
            contourCount: self.contourCount
        )
    }

    /// Move the start, current point to the given point.
    public mutating func moveTo(_ to: Point<Pixels>) {
        self.contourCount += 1
        self.start = to
        self.current = to
    }

    /// Draw a straight line from the current point to the given point.
    public mutating func lineTo(_ to: Point<Pixels>) {
        self.contourCount += 1
        if self.contourCount > 1 {
            self.pushTriangle(
                xy: (self.start, self.current, to),
                st: (point(0.0, 1.0), point(0.0, 1.0), point(0.0, 1.0))
            )
        }
        self.current = to
    }

    /// Draw a curve from the current point to the given point, using the given control point.
    public mutating func curveTo(_ to: Point<Pixels>, ctrl: Point<Pixels>) {
        self.contourCount += 1
        if self.contourCount > 1 {
            self.pushTriangle(
                xy: (self.start, self.current, to),
                st: (point(0.0, 1.0), point(0.0, 1.0), point(0.0, 1.0))
            )
        }

        self.pushTriangle(
            xy: (self.current, ctrl, to),
            st: (point(0.0, 0.0), point(0.5, 0.0), point(1.0, 1.0))
        )
        self.current = to
    }

    /// Push a triangle to the Path.
    public mutating func pushTriangle(
        xy: (Point<Pixels>, Point<Pixels>, Point<Pixels>),
        st: (Point<Float>, Point<Float>, Point<Float>)
    ) {
        self.bounds = self.bounds
            .union(Bounds(origin: xy.0, size: .zero))
            .union(Bounds(origin: xy.1, size: .zero))
            .union(Bounds(origin: xy.2, size: .zero))

        let defaultMask = ContentMask<Pixels>(bounds: Bounds(origin: .zero, size: .zero))
        self.vertices.append(PathVertex(
            xyPosition: xy.0,
            stPosition: st.0,
            contentMask: defaultMask
        ))
        self.vertices.append(PathVertex(
            xyPosition: xy.1,
            stPosition: st.1,
            contentMask: defaultMask
        ))
        self.vertices.append(PathVertex(
            xyPosition: xy.2,
            stPosition: st.2,
            contentMask: defaultMask
        ))
    }
}

extension Path where P: Comparable & AdditiveArithmetic {
    /// Bounds of this path clipped to its content mask.
    public var clippedBounds: Bounds<P> {
        self.bounds.intersect(self.contentMask.bounds)
    }
}

// MARK: - Primitive

/// An individual scene primitive.
public enum Primitive: Sendable, Equatable {
    case shadow(Shadow)
    case quad(Quad)
    case path(Path<ScaledPixels>)
    case underline(Underline)
    case monochromeSprite(MonochromeSprite)
    case subpixelSprite(SubpixelSprite)
    case polychromeSprite(PolychromeSprite)
    case surface(PaintSurface)

    public var bounds: Bounds<ScaledPixels> {
        switch self {
        case .shadow(let shadow): return shadow.bounds
        case .quad(let quad): return quad.bounds
        case .path(let path): return path.bounds
        case .underline(let underline): return underline.bounds
        case .monochromeSprite(let sprite): return sprite.bounds
        case .subpixelSprite(let sprite): return sprite.bounds
        case .polychromeSprite(let sprite): return sprite.bounds
        case .surface(let surface): return surface.bounds
        }
    }

    public var contentMask: ContentMask<ScaledPixels> {
        switch self {
        case .shadow(let shadow): return shadow.contentMask
        case .quad(let quad): return quad.contentMask
        case .path(let path): return path.contentMask
        case .underline(let underline): return underline.contentMask
        case .monochromeSprite(let sprite): return sprite.contentMask
        case .subpixelSprite(let sprite): return sprite.contentMask
        case .polychromeSprite(let sprite): return sprite.contentMask
        case .surface(let surface): return surface.contentMask
        }
    }

    public init(_ shadow: Shadow) { self = .shadow(shadow) }
    public init(_ quad: Quad) { self = .quad(quad) }
    public init(_ path: Path<ScaledPixels>) { self = .path(path) }
    public init(_ underline: Underline) { self = .underline(underline) }
    public init(_ sprite: MonochromeSprite) { self = .monochromeSprite(sprite) }
    public init(_ sprite: SubpixelSprite) { self = .subpixelSprite(sprite) }
    public init(_ sprite: PolychromeSprite) { self = .polychromeSprite(sprite) }
    public init(_ surface: PaintSurface) { self = .surface(surface) }
}

// MARK: - PaintOperation

/// Recorded paint operation for subtree replay and scene reconstruction.
public enum PaintOperation: Sendable, Equatable {
    case primitive(Primitive)
    case startLayer(Bounds<ScaledPixels>)
    case endLayer
}

// MARK: - PrimitiveKind

/// Categorization of render primitives for batch ordering and state grouping.
public enum PrimitiveKind: Int, Sendable, Equatable, Comparable {
    case shadow = 0
    case quad = 1
    case path = 2
    case underline = 3
    case monochromeSprite = 4
    case subpixelSprite = 5
    case polychromeSprite = 6
    case surface = 7

    public static func < (lhs: PrimitiveKind, rhs: PrimitiveKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - PrimitiveBatch

/// A contiguous slice of instances to be rendered in a single GPU draw call.
public enum PrimitiveBatch: Sendable, Equatable {
    case shadows(Range<Int>)
    case quads(Range<Int>)
    case paths(Range<Int>)
    case underlines(Range<Int>)
    case monochromeSprites(textureId: AtlasTextureId, range: Range<Int>)
    case subpixelSprites(textureId: AtlasTextureId, range: Range<Int>)
    case polychromeSprites(textureId: AtlasTextureId, range: Range<Int>)
    case surfaces(Range<Int>)
}

// MARK: - BatchIterator

/// An iterator that merges sorted primitive buffers into non-conflicting GPU draw call batches.
public struct BatchIterator: IteratorProtocol, Sequence, Sendable {
    public typealias Element = PrimitiveBatch

    private let shadows: [Shadow]
    private var shadowsIndex: Int = 0

    private let quads: [Quad]
    private var quadsIndex: Int = 0

    private let paths: [Path<ScaledPixels>]
    private var pathsIndex: Int = 0

    private let underlines: [Underline]
    private var underlinesIndex: Int = 0

    private let monochromeSprites: [MonochromeSprite]
    private var monochromeSpritesIndex: Int = 0

    private let subpixelSprites: [SubpixelSprite]
    private var subpixelSpritesIndex: Int = 0

    private let polychromeSprites: [PolychromeSprite]
    private var polychromeSpritesIndex: Int = 0

    private let surfaces: [PaintSurface]
    private var surfacesIndex: Int = 0

    public init(scene: Scene) {
        self.shadows = scene.shadows
        self.quads = scene.quads
        self.paths = scene.paths
        self.underlines = scene.underlines
        self.monochromeSprites = scene.monochromeSprites
        self.subpixelSprites = scene.subpixelSprites
        self.polychromeSprites = scene.polychromeSprites
        self.surfaces = scene.surfaces
    }

    private struct OrderAndKind: Comparable {
        let order: UInt32
        let kind: PrimitiveKind

        static func < (lhs: OrderAndKind, rhs: OrderAndKind) -> Bool {
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.kind < rhs.kind
        }
    }

    public mutating func next() -> PrimitiveBatch? {
        var ordersAndKinds: [(order: UInt32?, kind: PrimitiveKind)] = [
            (shadowsIndex < shadows.count ? shadows[shadowsIndex].order : nil, .shadow),
            (quadsIndex < quads.count ? quads[quadsIndex].order : nil, .quad),
            (pathsIndex < paths.count ? paths[pathsIndex].order : nil, .path),
            (underlinesIndex < underlines.count ? underlines[underlinesIndex].order : nil, .underline),
            (monochromeSpritesIndex < monochromeSprites.count ? monochromeSprites[monochromeSpritesIndex].order : nil, .monochromeSprite),
            (subpixelSpritesIndex < subpixelSprites.count ? subpixelSprites[subpixelSpritesIndex].order : nil, .subpixelSprite),
            (polychromeSpritesIndex < polychromeSprites.count ? polychromeSprites[polychromeSpritesIndex].order : nil, .polychromeSprite),
            (surfacesIndex < surfaces.count ? surfaces[surfacesIndex].order : nil, .surface),
        ]
        ordersAndKinds.sort { lhs, rhs in
            let lOrder = lhs.order ?? UInt32.max
            let rOrder = rhs.order ?? UInt32.max
            if lOrder != rOrder {
                return lOrder < rOrder
            }
            return lhs.kind < rhs.kind
        }

        let first = ordersAndKinds[0]
        let second = ordersAndKinds[1]
        guard let _ = first.order else {
            return nil
        }

        let batchKind = first.kind
        let maxOrderAndKind = OrderAndKind(order: second.order ?? UInt32.max, kind: second.kind)

        switch batchKind {
        case .shadow:
            let start = shadowsIndex
            var end = start + 1
            shadowsIndex += 1
            while shadowsIndex < shadows.count {
                let ok = OrderAndKind(order: shadows[shadowsIndex].order, kind: .shadow)
                if ok < maxOrderAndKind {
                    end += 1
                    shadowsIndex += 1
                } else {
                    break
                }
            }
            return .shadows(start..<end)

        case .quad:
            let start = quadsIndex
            var end = start + 1
            quadsIndex += 1
            while quadsIndex < quads.count {
                let ok = OrderAndKind(order: quads[quadsIndex].order, kind: .quad)
                if ok < maxOrderAndKind {
                    end += 1
                    quadsIndex += 1
                } else {
                    break
                }
            }
            return .quads(start..<end)

        case .path:
            let start = pathsIndex
            var end = start + 1
            pathsIndex += 1
            while pathsIndex < paths.count {
                let ok = OrderAndKind(order: paths[pathsIndex].order, kind: .path)
                if ok < maxOrderAndKind {
                    end += 1
                    pathsIndex += 1
                } else {
                    break
                }
            }
            return .paths(start..<end)

        case .underline:
            let start = underlinesIndex
            var end = start + 1
            underlinesIndex += 1
            while underlinesIndex < underlines.count {
                let ok = OrderAndKind(order: underlines[underlinesIndex].order, kind: .underline)
                if ok < maxOrderAndKind {
                    end += 1
                    underlinesIndex += 1
                } else {
                    break
                }
            }
            return .underlines(start..<end)

        case .monochromeSprite:
            let textureId = monochromeSprites[monochromeSpritesIndex].tile.textureId
            let start = monochromeSpritesIndex
            var end = start + 1
            monochromeSpritesIndex += 1
            while monochromeSpritesIndex < monochromeSprites.count {
                let sprite = monochromeSprites[monochromeSpritesIndex]
                let ok = OrderAndKind(order: sprite.order, kind: .monochromeSprite)
                if ok < maxOrderAndKind && sprite.tile.textureId == textureId {
                    end += 1
                    monochromeSpritesIndex += 1
                } else {
                    break
                }
            }
            return .monochromeSprites(textureId: textureId, range: start..<end)

        case .subpixelSprite:
            let textureId = subpixelSprites[subpixelSpritesIndex].tile.textureId
            let start = subpixelSpritesIndex
            var end = start + 1
            subpixelSpritesIndex += 1
            while subpixelSpritesIndex < subpixelSprites.count {
                let sprite = subpixelSprites[subpixelSpritesIndex]
                let ok = OrderAndKind(order: sprite.order, kind: .subpixelSprite)
                if ok < maxOrderAndKind && sprite.tile.textureId == textureId {
                    end += 1
                    subpixelSpritesIndex += 1
                } else {
                    break
                }
            }
            return .subpixelSprites(textureId: textureId, range: start..<end)

        case .polychromeSprite:
            let textureId = polychromeSprites[polychromeSpritesIndex].tile.textureId
            let start = polychromeSpritesIndex
            var end = start + 1
            polychromeSpritesIndex += 1
            while polychromeSpritesIndex < polychromeSprites.count {
                let sprite = polychromeSprites[polychromeSpritesIndex]
                let ok = OrderAndKind(order: sprite.order, kind: .polychromeSprite)
                if ok < maxOrderAndKind && sprite.tile.textureId == textureId {
                    end += 1
                    polychromeSpritesIndex += 1
                } else {
                    break
                }
            }
            return .polychromeSprites(textureId: textureId, range: start..<end)

        case .surface:
            let start = surfacesIndex
            var end = start + 1
            surfacesIndex += 1
            while surfacesIndex < surfaces.count {
                let ok = OrderAndKind(order: surfaces[surfacesIndex].order, kind: .surface)
                if ok < maxOrderAndKind {
                    end += 1
                    surfacesIndex += 1
                } else {
                    break
                }
            }
            return .surfaces(start..<end)
        }
    }
}

// MARK: - Scene

/// The immediate-mode display list accumulated during a frame's paint phase.
public struct Scene: Sendable, DefaultInitializable {
    public internal(set) var paintOperations: [PaintOperation]
    internal var primitiveBounds: BoundsTree<ScaledPixels>
    internal var layerStack: [DrawOrder]
    public var shadows: [Shadow]
    public var quads: [Quad]
    public var paths: [Path<ScaledPixels>]
    public var underlines: [Underline]
    public var monochromeSprites: [MonochromeSprite]
    public var subpixelSprites: [SubpixelSprite]
    public var polychromeSprites: [PolychromeSprite]
    public var surfaces: [PaintSurface]

    public init() {
        self.paintOperations = []
        self.primitiveBounds = BoundsTree<ScaledPixels>()
        self.layerStack = []
        self.shadows = []
        self.quads = []
        self.paths = []
        self.underlines = []
        self.monochromeSprites = []
        self.subpixelSprites = []
        self.polychromeSprites = []
        self.surfaces = []
    }

    /// Clear all primitive buffers, bounds tree, layer stack, and recorded operations.
    public mutating func clear() {
        paintOperations.removeAll(keepingCapacity: true)
        primitiveBounds.clear()
        layerStack.removeAll(keepingCapacity: true)
        paths.removeAll(keepingCapacity: true)
        shadows.removeAll(keepingCapacity: true)
        quads.removeAll(keepingCapacity: true)
        underlines.removeAll(keepingCapacity: true)
        monochromeSprites.removeAll(keepingCapacity: true)
        subpixelSprites.removeAll(keepingCapacity: true)
        polychromeSprites.removeAll(keepingCapacity: true)
        surfaces.removeAll(keepingCapacity: true)
    }

    /// Number of paint operations recorded in this scene.
    public var count: Int {
        paintOperations.count
    }

    /// Number of paint operations recorded in this scene (upstream parity).
    public var len: Int {
        count
    }

    /// Whether this scene contains no paint operations.
    public var isEmpty: Bool {
        paintOperations.isEmpty
    }

    /// Push a layer onto the layer stack, isolating child z-ordering.
    public mutating func pushLayer(bounds: Bounds<ScaledPixels>) {
        let order = primitiveBounds.insert(bounds)
        layerStack.append(order)
        paintOperations.append(.startLayer(bounds))
    }

    /// Pop the topmost layer from the layer stack.
    public mutating func popLayer() {
        layerStack.removeLast()
        paintOperations.append(.endLayer)
    }

    /// Insert a primitive into the scene, computing spatial z-order and culling empty bounds.
    public mutating func insertPrimitive(_ primitive: Primitive) {
        var primitive = primitive
        let clippedBounds = primitive.bounds.intersect(primitive.contentMask.bounds)
        if clippedBounds.isEmpty {
            return
        }

        let order = layerStack.last ?? primitiveBounds.insert(clippedBounds)

        switch primitive {
        case .shadow(var shadow):
            shadow.order = order
            shadows.append(shadow)
            primitive = .shadow(shadow)
        case .quad(var quad):
            quad.order = order
            quads.append(quad)
            primitive = .quad(quad)
        case .path(var path):
            path.order = order
            path.id = PathId(paths.count)
            paths.append(path)
            primitive = .path(path)
        case .underline(var underline):
            underline.order = order
            underlines.append(underline)
            primitive = .underline(underline)
        case .monochromeSprite(var sprite):
            sprite.order = order
            monochromeSprites.append(sprite)
            primitive = .monochromeSprite(sprite)
        case .subpixelSprite(var sprite):
            sprite.order = order
            subpixelSprites.append(sprite)
            primitive = .subpixelSprite(sprite)
        case .polychromeSprite(var sprite):
            sprite.order = order
            polychromeSprites.append(sprite)
            primitive = .polychromeSprite(sprite)
        case .surface(var surface):
            surface.order = order
            surfaces.append(surface)
            primitive = .surface(surface)
        }

        paintOperations.append(.primitive(primitive))
    }

    public mutating func insertQuad(_ quad: Quad) {
        insertPrimitive(.quad(quad))
    }

    public mutating func insertShadow(_ shadow: Shadow) {
        insertPrimitive(.shadow(shadow))
    }

    public mutating func insertPath(_ path: Path<ScaledPixels>) {
        insertPrimitive(.path(path))
    }

    public mutating func insertUnderline(_ underline: Underline) {
        insertPrimitive(.underline(underline))
    }

    public mutating func insertMonochromeSprite(_ sprite: MonochromeSprite) {
        insertPrimitive(.monochromeSprite(sprite))
    }

    public mutating func insertSubpixelSprite(_ sprite: SubpixelSprite) {
        insertPrimitive(.subpixelSprite(sprite))
    }

    public mutating func insertPolychromeSprite(_ sprite: PolychromeSprite) {
        insertPrimitive(.polychromeSprite(sprite))
    }

    public mutating func insertSurface(_ surface: PaintSurface) {
        insertPrimitive(.surface(surface))
    }

    /// Replay a range of operations from a previously painted scene.
    public mutating func replay(range: Range<Int>, prevScene: Scene) {
        for operation in prevScene.paintOperations[range] {
            switch operation {
            case .primitive(let primitive):
                insertPrimitive(primitive)
            case .startLayer(let bounds):
                pushLayer(bounds: bounds)
            case .endLayer:
                popLayer()
            }
        }
    }

    /// Sort all primitive buffers by draw order (and tile ID for sprites) prior to batch generation.
    public mutating func finish() {
        shadows.sort { $0.order < $1.order }
        quads.sort { $0.order < $1.order }
        paths.sort { $0.order < $1.order }
        underlines.sort { $0.order < $1.order }
        monochromeSprites.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.tile.tileId < $1.tile.tileId
        }
        subpixelSprites.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.tile.tileId < $1.tile.tileId
        }
        polychromeSprites.sort {
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.tile.tileId < $1.tile.tileId
        }
        surfaces.sort { $0.order < $1.order }
    }

    /// Generate a stream of merged primitive batches for GPU drawing.
    public func batches() -> BatchIterator {
        BatchIterator(scene: self)
    }
}
