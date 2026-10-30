// Ported from: crates/gpui_metal/src/renderer.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(Metal)
import CoreGraphics
import Foundation
import GPUI
import ImageIO
import Metal
import QuartzCore
import UniformTypeIdentifiers
#if os(macOS)
import CoreVideo
#endif

// MARK: - Exported Aliases & Constants

/// 2D floating-point point exported to Metal shaders (`Point<f32>`).
public typealias PointF = GPUI.Point<Float>

/// Shared instance buffer pool handle matching upstream `Arc<Mutex<InstanceBufferPool>>`.
public typealias Context = InstanceBufferPool

/// Primary Metal renderer alias matching upstream `pub type Renderer = MetalRenderer`.
public typealias Renderer = MetalRenderer

// Use 4x MSAA, all Metal devices support it.
// https://developer.apple.com/documentation/metal/mtldevice/1433355-supportstexturesamplecount
private let pathSampleCountConstant: UInt32 = 4

/// Creates a new `MetalRenderer` matching upstream `gpui_metal::new_renderer`.
public func newRenderer(
    _ context: Context,
    _ nativeWindow: UnsafeMutableRawPointer?,
    _ nativeView: UnsafeMutableRawPointer?,
    _ bounds: Size<Float>,
    _ transparent: Bool
) -> Renderer {
    _ = nativeWindow
    _ = nativeView
    _ = bounds
    return MetalRenderer.new(context, transparent)
}

/// Convenience labeled overload for creating a new `MetalRenderer`.
public func newRenderer(
    context: Context,
    nativeWindow: UnsafeMutableRawPointer? = nil,
    nativeView: UnsafeMutableRawPointer? = nil,
    bounds: Size<Float> = .zero,
    transparent: Bool = false
) -> Renderer {
    newRenderer(context, nativeWindow, nativeView, bounds, transparent)
}

// MARK: - Errors

/// Errors raised by `MetalRenderer` during shader compilation or offscreen rendering.
public enum MetalRendererError: Error, LocalizedError, Sendable {
    case noCompatibleDevice
    case shaderSourceNotFound
    case shaderCompilationFailed(String)
    case missingShaderFunction(String)
    case pipelineCreationFailed(String)
    case commandQueueCreationFailed
    case commandBufferCreationFailed
    case commandEncoderCreationFailed
    case invalidViewportSize(Size<DevicePixels>)
    case offscreenTextureCreationFailed(Size<DevicePixels>)
    case instanceBufferOverflow(Int)
    case imageEncodingFailed

    public var errorDescription: String? {
        switch self {
        case .noCompatibleDevice:
            return "Unable to access a compatible Metal graphics device"
        case .shaderSourceNotFound:
            return "Unable to locate shaders.metal resource in GPUIMetal bundle"
        case .shaderCompilationFailed(let message):
            return "Metal shader compilation failed: \(message)"
        case .missingShaderFunction(let name):
            return "Missing Metal shader function '\(name)'"
        case .pipelineCreationFailed(let message):
            return "Metal render pipeline creation failed: \(message)"
        case .commandQueueCreationFailed:
            return "Unable to create Metal command queue"
        case .commandBufferCreationFailed:
            return "Unable to create Metal command buffer"
        case .commandEncoderCreationFailed:
            return "Unable to create Metal render command encoder"
        case .invalidViewportSize(let size):
            return "Invalid viewport size for Metal rendering: \(size)"
        case .offscreenTextureCreationFailed(let size):
            return "Failed to allocate offscreen Metal texture of size \(size)"
        case .instanceBufferOverflow(let size):
            return "Metal instance buffer size grew too large: \(size) bytes"
        case .imageEncodingFailed:
            return "Failed to encode rendered RGBA pixels as PNG image"
        }
    }
}

// MARK: - Stitched MSL `scene.h` Bindings & Shader Compiler

// PORT NOTE: Replaces Cargo's `build.rs` `cbindgen` `scene.h` generation with an exact C/MSL header
// stitched ahead of `shaders.metal` (matching upstream's `runtime_shaders` feature). All struct
// fields, sizes, alignments, and enum discriminants match upstream `#[repr(C)]` definitions verbatim.
enum MetalShaderCompiler {
    static let sceneHeader: String = """
    #ifndef SCENE_H
    #define SCENE_H

    typedef float Pixels;
    typedef float ScaledPixels;
    typedef int DevicePixels;
    typedef unsigned int DrawOrder;
    typedef unsigned int TileId;

    enum BorderStyle : unsigned int {
        BorderStyle_Solid = 0,
        BorderStyle_Dashed = 1,
    };

    enum BackgroundTag : unsigned int {
        BackgroundTag_Solid = 0,
        BackgroundTag_LinearGradient = 1,
        BackgroundTag_PatternSlash = 2,
        BackgroundTag_Checkerboard = 3,
    };

    enum ColorSpace : unsigned int {
        ColorSpace_Srgb = 0,
        ColorSpace_Oklab = 1,
    };

    enum AtlasTextureKind : unsigned int {
        AtlasTextureKind_Monochrome = 0,
        AtlasTextureKind_Polychrome = 1,
        AtlasTextureKind_Subpixel = 2,
    };

    enum PathRasterizationInputIndex : unsigned int {
        PathRasterizationInputIndex_Vertices = 0,
        PathRasterizationInputIndex_ViewportSize = 1,
    };

    enum ShadowInputIndex : unsigned int {
        ShadowInputIndex_Vertices = 0,
        ShadowInputIndex_Shadows = 1,
        ShadowInputIndex_ViewportSize = 2,
    };

    enum QuadInputIndex : unsigned int {
        QuadInputIndex_Vertices = 0,
        QuadInputIndex_Quads = 1,
        QuadInputIndex_ViewportSize = 2,
    };

    enum UnderlineInputIndex : unsigned int {
        UnderlineInputIndex_Vertices = 0,
        UnderlineInputIndex_Underlines = 1,
        UnderlineInputIndex_ViewportSize = 2,
    };

    enum SpriteInputIndex : unsigned int {
        SpriteInputIndex_Vertices = 0,
        SpriteInputIndex_Sprites = 1,
        SpriteInputIndex_ViewportSize = 2,
        SpriteInputIndex_AtlasTextureSize = 3,
        SpriteInputIndex_AtlasTexture = 4,
    };

    enum SurfaceInputIndex : unsigned int {
        SurfaceInputIndex_Vertices = 0,
        SurfaceInputIndex_Surfaces = 1,
        SurfaceInputIndex_ViewportSize = 2,
        SurfaceInputIndex_TextureSize = 3,
        SurfaceInputIndex_YTexture = 4,
        SurfaceInputIndex_CbCrTexture = 5,
    };

    struct PointF {
        float x;
        float y;
    };

    struct Point_ScaledPixels {
        ScaledPixels x;
        ScaledPixels y;
    };

    struct Size_ScaledPixels {
        ScaledPixels width;
        ScaledPixels height;
    };

    struct Bounds_ScaledPixels {
        Point_ScaledPixels origin;
        Size_ScaledPixels size;
    };

    struct ContentMask_ScaledPixels {
        Bounds_ScaledPixels bounds;
    };

    struct Corners_ScaledPixels {
        ScaledPixels top_left;
        ScaledPixels top_right;
        ScaledPixels bottom_right;
        ScaledPixels bottom_left;
    };

    struct Edges_ScaledPixels {
        ScaledPixels top;
        ScaledPixels right;
        ScaledPixels bottom;
        ScaledPixels left;
    };

    struct Point_DevicePixels {
        DevicePixels x;
        DevicePixels y;
    };

    struct Size_DevicePixels {
        DevicePixels width;
        DevicePixels height;
    };

    struct Bounds_DevicePixels {
        Point_DevicePixels origin;
        Size_DevicePixels size;
    };

    struct Hsla {
        float h;
        float s;
        float l;
        float a;
    };

    struct LinearColorStop {
        Hsla color;
        float percentage;
    };

    struct Background {
        BackgroundTag tag;
        ColorSpace color_space;
        Hsla solid;
        float gradient_angle_or_pattern_height;
        LinearColorStop colors[2];
        unsigned int pad;
    };

    struct AtlasTextureId {
        unsigned int index;
        AtlasTextureKind kind;
    };

    struct AtlasTile {
        AtlasTextureId texture_id;
        TileId tile_id;
        unsigned int padding;
        Bounds_DevicePixels bounds;
    };

    struct TransformationMatrix {
        float rotation_scale[2][2];
        float translation[2];
    };

    struct PathVertex_ScaledPixels {
        Point_ScaledPixels xy_position;
        PointF st_position;
        ContentMask_ScaledPixels content_mask;
    };

    struct PathRasterizationVertex {
        Point_ScaledPixels xy_position;
        PointF st_position;
        Background color;
        Bounds_ScaledPixels bounds;
    };

    struct PathSprite {
        Bounds_ScaledPixels bounds;
    };

    struct Shadow {
        DrawOrder order;
        ScaledPixels blur_radius;
        Bounds_ScaledPixels bounds;
        Corners_ScaledPixels corner_radii;
        ContentMask_ScaledPixels content_mask;
        Hsla color;
    };

    struct Quad {
        DrawOrder order;
        BorderStyle border_style;
        Bounds_ScaledPixels bounds;
        ContentMask_ScaledPixels content_mask;
        Background background;
        Hsla border_color;
        Corners_ScaledPixels corner_radii;
        Edges_ScaledPixels border_widths;
    };

    struct Underline {
        DrawOrder order;
        unsigned int pad;
        Bounds_ScaledPixels bounds;
        ContentMask_ScaledPixels content_mask;
        Hsla color;
        ScaledPixels thickness;
        unsigned int wavy;
    };

    struct MonochromeSprite {
        DrawOrder order;
        unsigned int pad;
        Bounds_ScaledPixels bounds;
        ContentMask_ScaledPixels content_mask;
        Hsla color;
        AtlasTile tile;
        TransformationMatrix transformation;
    };

    struct PolychromeSprite {
        DrawOrder order;
        unsigned int pad;
        bool grayscale;
        float opacity;
        Bounds_ScaledPixels bounds;
        ContentMask_ScaledPixels content_mask;
        Corners_ScaledPixels corner_radii;
        AtlasTile tile;
    };

    struct SurfaceBounds {
        Bounds_ScaledPixels bounds;
        ContentMask_ScaledPixels content_mask;
    };

    #endif // SCENE_H
    """

    private static let cacheLock = NSLock()
    // PORT NOTE: Cached MTLLibrary dictionary keyed by MTLDevice.registryID, synchronized by cacheLock.
    nonisolated(unsafe) private static var libraryCache: [UInt64: any MTLLibrary] = [:]

    static func loadRawShaderSource() throws -> String {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "shaders", withExtension: "metal"),
           let contents = try? String(contentsOf: url, encoding: .utf8) {
            return contents
        }
        #endif

        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "shaders", withExtension: "metal"),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }
        }

        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fallbackURL = sourceDir.appendingPathComponent("shaders.metal")
        if let contents = try? String(contentsOf: fallbackURL, encoding: .utf8) {
            return contents
        }

        throw MetalRendererError.shaderSourceNotFound
    }

    static func loadStitchedShaderSource() throws -> String {
        let rawShaders = try loadRawShaderSource()
        return "\(sceneHeader)\n\(rawShaders)"
    }

    static func library(for device: any MTLDevice) throws -> any MTLLibrary {
        let registryID = device.registryID
        cacheLock.lock()
        if let cached = libraryCache[registryID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let stitchedSource = try loadStitchedShaderSource()
        let options = MTLCompileOptions()
        let compiledLibrary: any MTLLibrary
        do {
            compiledLibrary = try device.makeLibrary(source: stitchedSource, options: options)
        } catch {
            throw MetalRendererError.shaderCompilationFailed(String(describing: error))
        }

        cacheLock.lock()
        libraryCache[registryID] = compiledLibrary
        cacheLock.unlock()
        return compiledLibrary
    }
}

// MARK: - C-ABI GPU Primitive Structs (`@frozen` scalar layout matching MSL `scene.h`)

@frozen
package struct MetalPointF: Sendable, Equatable {
    package var x: Float
    package var y: Float

    package init(_ point: Point<Float>) {
        self.x = point.x
        self.y = point.y
    }

    package init(_ point: Point<ScaledPixels>) {
        self.x = point.x.value
        self.y = point.y.value
    }
}

@frozen
package struct MetalSizeScaledPixels: Sendable, Equatable {
    package var width: Float
    package var height: Float

    package init(_ size: Size<ScaledPixels>) {
        self.width = size.width.value
        self.height = size.height.value
    }
}

@frozen
package struct MetalBoundsScaledPixels: Sendable, Equatable {
    package var origin: MetalPointF
    package var size: MetalSizeScaledPixels

    package init(_ bounds: Bounds<ScaledPixels>) {
        self.origin = MetalPointF(bounds.origin)
        self.size = MetalSizeScaledPixels(bounds.size)
    }
}

@frozen
package struct MetalContentMaskScaledPixels: Sendable, Equatable {
    package var bounds: MetalBoundsScaledPixels

    package init(_ mask: ContentMask<ScaledPixels>) {
        self.bounds = MetalBoundsScaledPixels(mask.bounds)
    }
}

@frozen
package struct MetalCornersScaledPixels: Sendable, Equatable {
    package var topLeft: Float
    package var topRight: Float
    package var bottomRight: Float
    package var bottomLeft: Float

    package init(_ corners: Corners<ScaledPixels>) {
        self.topLeft = corners.topLeft.value
        self.topRight = corners.topRight.value
        self.bottomRight = corners.bottomRight.value
        self.bottomLeft = corners.bottomLeft.value
    }
}

@frozen
package struct MetalEdgesScaledPixels: Sendable, Equatable {
    package var top: Float
    package var right: Float
    package var bottom: Float
    package var left: Float

    package init(_ edges: Edges<ScaledPixels>) {
        self.top = edges.top.value
        self.right = edges.right.value
        self.bottom = edges.bottom.value
        self.left = edges.left.value
    }
}

@frozen
package struct MetalPointDevicePixels: Sendable, Equatable {
    package var x: Int32
    package var y: Int32

    package init(_ point: Point<DevicePixels>) {
        self.x = point.x.value
        self.y = point.y.value
    }
}

@frozen
package struct MetalSizeDevicePixels: Sendable, Equatable {
    package var width: Int32
    package var height: Int32

    package init(_ size: Size<DevicePixels>) {
        self.width = size.width.value
        self.height = size.height.value
    }
}

@frozen
package struct MetalBoundsDevicePixels: Sendable, Equatable {
    package var origin: MetalPointDevicePixels
    package var size: MetalSizeDevicePixels

    package init(_ bounds: Bounds<DevicePixels>) {
        self.origin = MetalPointDevicePixels(bounds.origin)
        self.size = MetalSizeDevicePixels(bounds.size)
    }
}

@frozen
package struct MetalHsla: Sendable, Equatable {
    package var h: Float
    package var s: Float
    package var l: Float
    package var a: Float

    package init(_ color: Hsla) {
        self.h = color.h
        self.s = color.s
        self.l = color.l
        self.a = color.a
    }
}

@frozen
package struct MetalLinearColorStop: Sendable, Equatable {
    package var color: MetalHsla
    package var percentage: Float

    package init(_ stop: LinearColorStop) {
        self.color = MetalHsla(stop.color)
        self.percentage = stop.percentage
    }
}

@frozen
package struct MetalBackground: Sendable, Equatable {
    package var tag: UInt32
    package var colorSpace: UInt32
    package var solid: MetalHsla
    package var gradientAngleOrPatternHeight: Float
    package var color0: MetalLinearColorStop
    package var color1: MetalLinearColorStop
    package var pad: UInt32

    package init(_ bg: Background) {
        self.tag = bg.tag.rawValue
        self.colorSpace = bg.colorSpace.rawValue
        self.solid = MetalHsla(bg.solid)
        self.gradientAngleOrPatternHeight = bg.gradientAngleOrPatternHeight
        self.color0 = MetalLinearColorStop(bg.colors.0)
        self.color1 = MetalLinearColorStop(bg.colors.1)
        self.pad = bg.pad
    }
}

@frozen
package struct MetalAtlasTextureId: Sendable, Equatable {
    package var index: UInt32
    package var kind: UInt32

    package init(_ id: AtlasTextureId) {
        self.index = id.index
        self.kind = id.kind.rawValue
    }
}

@frozen
package struct MetalAtlasTile: Sendable, Equatable {
    package var textureId: MetalAtlasTextureId
    package var tileId: UInt32
    package var padding: UInt32
    package var bounds: MetalBoundsDevicePixels

    package init(_ tile: AtlasTile) {
        self.textureId = MetalAtlasTextureId(tile.textureId)
        self.tileId = tile.tileId.rawValue
        self.padding = tile.padding
        self.bounds = MetalBoundsDevicePixels(tile.bounds)
    }
}

@frozen
package struct MetalTransformationMatrix: Sendable, Equatable {
    package var m00: Float
    package var m01: Float
    package var m10: Float
    package var m11: Float
    package var tx: Float
    package var ty: Float

    package init(_ matrix: TransformationMatrix) {
        self.m00 = matrix.rotationScale.0.0
        self.m01 = matrix.rotationScale.0.1
        self.m10 = matrix.rotationScale.1.0
        self.m11 = matrix.rotationScale.1.1
        self.tx = matrix.translation.0
        self.ty = matrix.translation.1
    }
}

@frozen
package struct MetalPathRasterizationVertex: Sendable, Equatable {
    package var xyPosition: MetalPointF
    package var stPosition: MetalPointF
    package var color: MetalBackground
    package var bounds: MetalBoundsScaledPixels

    package init(
        xyPosition: MetalPointF,
        stPosition: MetalPointF,
        color: MetalBackground,
        bounds: MetalBoundsScaledPixels
    ) {
        self.xyPosition = xyPosition
        self.stPosition = stPosition
        self.color = color
        self.bounds = bounds
    }

    package init(_ vertex: PathRasterizationVertex) {
        self.xyPosition = MetalPointF(vertex.xyPosition)
        self.stPosition = MetalPointF(vertex.stPosition)
        self.color = MetalBackground(vertex.color)
        self.bounds = MetalBoundsScaledPixels(vertex.bounds)
    }
}

@frozen
package struct MetalPathSprite: Sendable, Equatable {
    package var bounds: MetalBoundsScaledPixels

    package init(_ sprite: PathSprite) {
        self.bounds = MetalBoundsScaledPixels(sprite.bounds)
    }
}

@frozen
package struct MetalShadow: Sendable, Equatable {
    package var order: UInt32
    package var blurRadius: Float
    package var bounds: MetalBoundsScaledPixels
    package var cornerRadii: MetalCornersScaledPixels
    package var contentMask: MetalContentMaskScaledPixels
    package var color: MetalHsla

    package init(_ shadow: Shadow) {
        self.order = shadow.order
        self.blurRadius = shadow.blurRadius.value
        self.bounds = MetalBoundsScaledPixels(shadow.bounds)
        self.cornerRadii = MetalCornersScaledPixels(shadow.cornerRadii)
        self.contentMask = MetalContentMaskScaledPixels(shadow.contentMask)
        self.color = MetalHsla(shadow.color)
    }
}

@frozen
package struct MetalQuad: Sendable, Equatable {
    package var order: UInt32
    package var borderStyle: UInt32
    package var bounds: MetalBoundsScaledPixels
    package var contentMask: MetalContentMaskScaledPixels
    package var background: MetalBackground
    package var borderColor: MetalHsla
    package var cornerRadii: MetalCornersScaledPixels
    package var borderWidths: MetalEdgesScaledPixels

    package init(_ quad: Quad) {
        self.order = quad.order
        self.borderStyle = quad.borderStyle.rawValue
        self.bounds = MetalBoundsScaledPixels(quad.bounds)
        self.contentMask = MetalContentMaskScaledPixels(quad.contentMask)
        self.background = MetalBackground(quad.background)
        self.borderColor = MetalHsla(quad.borderColor)
        self.cornerRadii = MetalCornersScaledPixels(quad.cornerRadii)
        self.borderWidths = MetalEdgesScaledPixels(quad.borderWidths)
    }
}

@frozen
package struct MetalUnderline: Sendable, Equatable {
    package var order: UInt32
    package var pad: UInt32
    package var bounds: MetalBoundsScaledPixels
    package var contentMask: MetalContentMaskScaledPixels
    package var color: MetalHsla
    package var thickness: Float
    package var wavy: UInt32

    package init(_ underline: Underline) {
        self.order = underline.order
        self.pad = underline.pad
        self.bounds = MetalBoundsScaledPixels(underline.bounds)
        self.contentMask = MetalContentMaskScaledPixels(underline.contentMask)
        self.color = MetalHsla(underline.color)
        self.thickness = underline.thickness.value
        self.wavy = underline.wavy
    }
}

@frozen
package struct MetalMonochromeSprite: Sendable, Equatable {
    package var order: UInt32
    package var pad: UInt32
    package var bounds: MetalBoundsScaledPixels
    package var contentMask: MetalContentMaskScaledPixels
    package var color: MetalHsla
    package var tile: MetalAtlasTile
    package var transformation: MetalTransformationMatrix

    package init(_ sprite: MonochromeSprite) {
        self.order = sprite.order
        self.pad = sprite.pad
        self.bounds = MetalBoundsScaledPixels(sprite.bounds)
        self.contentMask = MetalContentMaskScaledPixels(sprite.contentMask)
        self.color = MetalHsla(sprite.color)
        self.tile = MetalAtlasTile(sprite.tile)
        self.transformation = MetalTransformationMatrix(sprite.transformation)
    }
}

@frozen
package struct MetalPolychromeSprite: Sendable, Equatable {
    package var order: UInt32
    package var pad: UInt32
    package var grayscale: UInt8
    package var grayscalePad0: UInt8
    package var grayscalePad1: UInt8
    package var grayscalePad2: UInt8
    package var opacity: Float
    package var bounds: MetalBoundsScaledPixels
    package var contentMask: MetalContentMaskScaledPixels
    package var cornerRadii: MetalCornersScaledPixels
    package var tile: MetalAtlasTile

    package init(_ sprite: PolychromeSprite) {
        self.order = sprite.order
        self.pad = sprite.pad
        self.grayscale = sprite.isGrayscale ? 1 : 0
        self.grayscalePad0 = 0
        self.grayscalePad1 = 0
        self.grayscalePad2 = 0
        self.opacity = sprite.opacity
        self.bounds = MetalBoundsScaledPixels(sprite.bounds)
        self.contentMask = MetalContentMaskScaledPixels(sprite.contentMask)
        self.cornerRadii = MetalCornersScaledPixels(sprite.cornerRadii)
        self.tile = MetalAtlasTile(sprite.tile)
    }
}

@frozen
package struct MetalSurfaceBounds: Sendable, Equatable {
    package var bounds: MetalBoundsScaledPixels
    package var contentMask: MetalContentMaskScaledPixels

    package init(_ surfaceBounds: SurfaceBounds) {
        self.bounds = MetalBoundsScaledPixels(surfaceBounds.bounds)
        self.contentMask = MetalContentMaskScaledPixels(surfaceBounds.contentMask)
    }
}

// MARK: - Public Shader Data Types (Upstream Parity)

/// Vertex uploaded to the path rasterization pass.
public struct PathRasterizationVertex: Sendable, Equatable {
    public var xyPosition: Point<ScaledPixels>
    public var stPosition: Point<Float>
    public var color: Background
    public var bounds: Bounds<ScaledPixels>

    public init(
        xyPosition: Point<ScaledPixels>,
        stPosition: Point<Float>,
        color: Background,
        bounds: Bounds<ScaledPixels>
    ) {
        self.xyPosition = xyPosition
        self.stPosition = stPosition
        self.color = color
        self.bounds = bounds
    }
}

/// Bounds quad for blitting pre-rasterized paths from the intermediate texture.
public struct PathSprite: Sendable, Equatable {
    public var bounds: Bounds<ScaledPixels>

    public init(bounds: Bounds<ScaledPixels>) {
        self.bounds = bounds
    }
}

/// Clipped bounds uploaded when drawing an external `CVPixelBuffer` surface.
public struct SurfaceBounds: Sendable, Equatable {
    public var bounds: Bounds<ScaledPixels>
    public var contentMask: ContentMask<ScaledPixels>

    public init(bounds: Bounds<ScaledPixels>, contentMask: ContentMask<ScaledPixels>) {
        self.bounds = bounds
        self.contentMask = contentMask
    }
}

// MARK: - Shader Input Buffer Indices

private enum ShadowInputIndex: Int {
    case vertices = 0
    case shadows = 1
    case viewportSize = 2
}

private enum QuadInputIndex: Int {
    case vertices = 0
    case quads = 1
    case viewportSize = 2
}

private enum UnderlineInputIndex: Int {
    case vertices = 0
    case underlines = 1
    case viewportSize = 2
}

private enum SpriteInputIndex: Int {
    case vertices = 0
    case sprites = 1
    case viewportSize = 2
    case atlasTextureSize = 3
    case atlasTexture = 4
}

#if os(macOS)
private enum SurfaceInputIndex: Int {
    case vertices = 0
    case surfaces = 1
    case viewportSize = 2
    case textureSize = 3
    case yTexture = 4
    case cbCrTexture = 5
}
#endif

private enum PathRasterizationInputIndex: Int {
    case vertices = 0
    case viewportSize = 1
}

// MARK: - InstanceBuffer & InstanceBufferPool

private func uploadBufferOptions(_ unifiedMemory: Bool) -> MTLResourceOptions {
    #if os(macOS)
    if !unifiedMemory {
        return .storageModeManaged
    }
    #endif
    return [.storageModeShared, .cpuCacheModeWriteCombined]
}

/// Per-frame GPU upload buffer acquired from `InstanceBufferPool`.
// PORT NOTE: Exclusive ownership of `metalBuffer` transfers from the draw call to the Metal
// command buffer completion handler and back to `InstanceBufferPool` under lock.
public struct InstanceBuffer: @unchecked Sendable {
    public let metalBuffer: any MTLBuffer
    public let size: Int

    public init(metalBuffer: any MTLBuffer, size: Int) {
        self.metalBuffer = metalBuffer
        self.size = size
    }
}

/// Thread-safe pool of reusable Metal upload buffers (`Arc<Mutex<InstanceBufferPool>>` equivalent).
// PORT NOTE: Synchronized internally via `NSLock`, replacing upstream `Arc<Mutex<InstanceBufferPool>>`.
public final class InstanceBufferPool: @unchecked Sendable {
    private let lock = NSLock()
    private var currentBufferSize: Int
    private var buffers: [any MTLBuffer] = []

    public var bufferSize: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return currentBufferSize
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            currentBufferSize = newValue
        }
    }

    public init() {
        self.currentBufferSize = 2 * 1024 * 1024
    }

    public init(bufferSize: Int) {
        self.currentBufferSize = bufferSize
    }

    public static func `default`() -> InstanceBufferPool {
        InstanceBufferPool()
    }

    public func reset(_ bufferSize: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.currentBufferSize = bufferSize
        self.buffers.removeAll()
    }

    public func acquire(_ device: any MTLDevice, _ unifiedMemory: Bool) -> InstanceBuffer {
        lock.lock()
        let targetSize = currentBufferSize
        let existing = buffers.popLast()
        lock.unlock()

        if let existing {
            return InstanceBuffer(metalBuffer: existing, size: targetSize)
        }

        let options = uploadBufferOptions(unifiedMemory)
        guard let created = device.makeBuffer(length: targetSize, options: options) else {
            preconditionFailure("Failed to allocate Metal instance buffer of length \(targetSize)")
        }
        return InstanceBuffer(metalBuffer: created, size: targetSize)
    }

    public func acquire(device: any MTLDevice, unifiedMemory: Bool) -> InstanceBuffer {
        acquire(device, unifiedMemory)
    }

    public func release(_ buffer: InstanceBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if buffer.size == currentBufferSize {
            buffers.append(buffer.metalBuffer)
        }
    }
}

// MARK: - SharedRenderResources

/// GPU resources shared between the main `MetalRenderer` and any `SurfaceRenderer`s.
// PORT NOTE: Holds immutable Metal pipeline states, command queue, thread-safe `MetalAtlas`,
// and `InstanceBufferPool`, matching upstream `Rc<SharedRenderResources>`.
public final class SharedRenderResources: @unchecked Sendable {
    public let device: any MTLDevice
    public let commandQueue: any MTLCommandQueue
    public let pathsRasterizationPipelineState: any MTLRenderPipelineState
    public let pathSpritesPipelineState: any MTLRenderPipelineState
    public let shadowsPipelineState: any MTLRenderPipelineState
    public let quadsPipelineState: any MTLRenderPipelineState
    public let underlinesPipelineState: any MTLRenderPipelineState
    public let monochromeSpritesPipelineState: any MTLRenderPipelineState
    public let polychromeSpritesPipelineState: any MTLRenderPipelineState
    public let surfacesPipelineState: any MTLRenderPipelineState
    public let bgraSurfacesPipelineState: any MTLRenderPipelineState
    public let unitVertices: any MTLBuffer
    public let instanceBufferPool: InstanceBufferPool
    public let spriteAtlas: MetalAtlas
    #if os(macOS)
    public let coreVideoTextureCache: CVMetalTextureCache
    #endif
    public let pathSampleCount: UInt32
    public let isAppleGpu: Bool
    public let isUnifiedMemory: Bool

    init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        pathsRasterizationPipelineState: any MTLRenderPipelineState,
        pathSpritesPipelineState: any MTLRenderPipelineState,
        shadowsPipelineState: any MTLRenderPipelineState,
        quadsPipelineState: any MTLRenderPipelineState,
        underlinesPipelineState: any MTLRenderPipelineState,
        monochromeSpritesPipelineState: any MTLRenderPipelineState,
        polychromeSpritesPipelineState: any MTLRenderPipelineState,
        surfacesPipelineState: any MTLRenderPipelineState,
        bgraSurfacesPipelineState: any MTLRenderPipelineState,
        unitVertices: any MTLBuffer,
        instanceBufferPool: InstanceBufferPool,
        spriteAtlas: MetalAtlas,
        pathSampleCount: UInt32,
        isAppleGpu: Bool,
        isUnifiedMemory: Bool
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.pathsRasterizationPipelineState = pathsRasterizationPipelineState
        self.pathSpritesPipelineState = pathSpritesPipelineState
        self.shadowsPipelineState = shadowsPipelineState
        self.quadsPipelineState = quadsPipelineState
        self.underlinesPipelineState = underlinesPipelineState
        self.monochromeSpritesPipelineState = monochromeSpritesPipelineState
        self.polychromeSpritesPipelineState = polychromeSpritesPipelineState
        self.surfacesPipelineState = surfacesPipelineState
        self.bgraSurfacesPipelineState = bgraSurfacesPipelineState
        self.unitVertices = unitVertices
        self.instanceBufferPool = instanceBufferPool
        self.spriteAtlas = spriteAtlas
        #if os(macOS)
        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let createdCache = cache else {
            preconditionFailure("Failed to create CVMetalTextureCache (status: \(status))")
        }
        self.coreVideoTextureCache = createdCache
        #endif
        self.pathSampleCount = pathSampleCount
        self.isAppleGpu = isAppleGpu
        self.isUnifiedMemory = isUnifiedMemory
    }
}

// MARK: - Device Selection & Layer Setup

private func selectDefaultMetalDevice() throws -> any MTLDevice {
    #if os(macOS)
    let devices = MTLCopyAllDevices()
    let preferred = devices.min { lhs, rhs in
        if lhs.isRemovable != rhs.isRemovable {
            return !lhs.isRemovable && rhs.isRemovable
        }
        if lhs.isLowPower != rhs.isLowPower {
            return lhs.isLowPower && !rhs.isLowPower
        }
        return false
    }
    if let preferred {
        return preferred
    }
    if let fallback = MTLCreateSystemDefaultDevice() {
        return fallback
    }
    throw MetalRendererError.noCompatibleDevice
    #else
    if let device = MTLCreateSystemDefaultDevice() {
        return device
    }
    throw MetalRendererError.noCompatibleDevice
    #endif
}

private func configureMetalLayer(
    _ layer: CAMetalLayer,
    device: any MTLDevice,
    transparent: Bool
) {
    layer.device = device
    layer.pixelFormat = .bgra8Unorm
    layer.isOpaque = !transparent
    layer.maximumDrawableCount = 3
    #if TestSupport || DEBUG
    layer.framebufferOnly = false
    #endif
    #if os(macOS)
    layer.allowsNextDrawableTimeout = false
    layer.needsDisplayOnBoundsChange = true
    layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    #else
    layer.allowsNextDrawableTimeout = true
    layer.needsDisplayOnBoundsChange = true
    #endif
}

private func toFloat2Bits(_ x: Float, _ y: Float) -> UInt64 {
    var output = UInt64(y.bitPattern)
    output <<= 32
    output |= UInt64(x.bitPattern)
    return output
}

// MARK: - MetalRenderer

/// Primary Metal hardware renderer for GPUI scenes on macOS and iOS.
// PORT NOTE: Main-thread/window-owned renderer holding `SharedRenderResources` and `CAMetalLayer`,
// matching upstream `gpui_metal::MetalRenderer`.
public final class MetalRenderer: @unchecked Sendable {
    private let sharedResources: SharedRenderResources
    private var metalLayer: CAMetalLayer
    private var presentsWithTransaction: Bool = false
    private var pathIntermediateTexture: (any MTLTexture)?
    private var pathIntermediateMsaaTexture: (any MTLTexture)?

    public convenience init(_ instanceBufferPool: InstanceBufferPool = InstanceBufferPool(), _ transparent: Bool = false) {
        do {
            let device = try selectDefaultMetalDevice()
            try self.init(device: device, instanceBufferPool: instanceBufferPool, transparent: transparent)
        } catch {
            preconditionFailure("MetalRenderer initialization failed: \(error)")
        }
    }

    public convenience init(
        instanceBufferPool: InstanceBufferPool,
        transparent: Bool = false
    ) {
        self.init(instanceBufferPool, transparent)
    }

    public init(
        device: any MTLDevice,
        instanceBufferPool: InstanceBufferPool = InstanceBufferPool(),
        transparent: Bool = false
    ) throws {
        let layer = CAMetalLayer()
        configureMetalLayer(layer, device: device, transparent: transparent)

        let library = try MetalShaderCompiler.library(for: device)
        let isUnifiedMemory = device.hasUnifiedMemory
        let isAppleGpu = device.supportsFamily(.apple1)

        let unitVertexQuad: [UInt64] = [
            toFloat2Bits(0.0, 0.0),
            toFloat2Bits(1.0, 0.0),
            toFloat2Bits(0.0, 1.0),
            toFloat2Bits(0.0, 1.0),
            toFloat2Bits(1.0, 0.0),
            toFloat2Bits(1.0, 1.0),
        ]
        let unitVerticesBuffer: any MTLBuffer = try unitVertexQuad.withUnsafeBytes { rawBytes in
            guard let baseAddress = rawBytes.baseAddress,
                  let buffer = device.makeBuffer(
                      bytes: baseAddress,
                      length: rawBytes.count,
                      options: uploadBufferOptions(isUnifiedMemory)
                  ) else {
                throw MetalRendererError.pipelineCreationFailed("Failed to create unit_vertices buffer")
            }
            return buffer
        }

        let pathsRasterization = try buildPathRasterizationPipelineState(
            device: device,
            library: library,
            label: "paths_rasterization",
            vertexFnName: "path_rasterization_vertex",
            fragmentFnName: "path_rasterization_fragment",
            pixelFormat: .bgra8Unorm,
            pathSampleCount: pathSampleCountConstant
        )
        let pathSprites = try buildPathSpritePipelineState(
            device: device,
            library: library,
            label: "path_sprites",
            vertexFnName: "path_sprite_vertex",
            fragmentFnName: "path_sprite_fragment",
            pixelFormat: .bgra8Unorm
        )
        let shadows = try buildPipelineState(
            device: device,
            library: library,
            label: "shadows",
            vertexFnName: "shadow_vertex",
            fragmentFnName: "shadow_fragment",
            pixelFormat: .bgra8Unorm
        )
        let quads = try buildPipelineState(
            device: device,
            library: library,
            label: "quads",
            vertexFnName: "quad_vertex",
            fragmentFnName: "quad_fragment",
            pixelFormat: .bgra8Unorm
        )
        let underlines = try buildPipelineState(
            device: device,
            library: library,
            label: "underlines",
            vertexFnName: "underline_vertex",
            fragmentFnName: "underline_fragment",
            pixelFormat: .bgra8Unorm
        )
        let monochromeSprites = try buildPipelineState(
            device: device,
            library: library,
            label: "monochrome_sprites",
            vertexFnName: "monochrome_sprite_vertex",
            fragmentFnName: "monochrome_sprite_fragment",
            pixelFormat: .bgra8Unorm
        )
        let polychromeSprites = try buildPipelineState(
            device: device,
            library: library,
            label: "polychrome_sprites",
            vertexFnName: "polychrome_sprite_vertex",
            fragmentFnName: "polychrome_sprite_fragment",
            pixelFormat: .bgra8Unorm
        )
        let surfaces = try buildPipelineState(
            device: device,
            library: library,
            label: "surfaces",
            vertexFnName: "surface_vertex",
            fragmentFnName: "surface_fragment",
            pixelFormat: .bgra8Unorm
        )
        let bgraSurfaces = try buildPipelineState(
            device: device,
            library: library,
            label: "bgra_surfaces",
            vertexFnName: "surface_vertex",
            fragmentFnName: "surface_bgra_fragment",
            pixelFormat: .bgra8Unorm
        )

        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalRendererError.commandQueueCreationFailed
        }

        let spriteAtlas = MetalAtlas.new(device, isAppleGpu)

        self.sharedResources = SharedRenderResources(
            device: device,
            commandQueue: commandQueue,
            pathsRasterizationPipelineState: pathsRasterization,
            pathSpritesPipelineState: pathSprites,
            shadowsPipelineState: shadows,
            quadsPipelineState: quads,
            underlinesPipelineState: underlines,
            monochromeSpritesPipelineState: monochromeSprites,
            polychromeSpritesPipelineState: polychromeSprites,
            surfacesPipelineState: surfaces,
            bgraSurfacesPipelineState: bgraSurfaces,
            unitVertices: unitVerticesBuffer,
            instanceBufferPool: instanceBufferPool,
            spriteAtlas: spriteAtlas,
            pathSampleCount: pathSampleCountConstant,
            isAppleGpu: isAppleGpu,
            isUnifiedMemory: isUnifiedMemory
        )
        self.metalLayer = layer
        self.presentsWithTransaction = false
        self.pathIntermediateTexture = nil
        self.pathIntermediateMsaaTexture = nil
    }

    public static func new(_ instanceBufferPool: InstanceBufferPool = InstanceBufferPool(), _ transparent: Bool = false) -> MetalRenderer {
        MetalRenderer(instanceBufferPool, transparent)
    }

    public func shared() -> SharedRenderResources {
        sharedResources
    }

    /// Replace the renderer's `CAMetalLayer` with an external one (e.g. a `UIView`'s backing layer on iOS).
    public func replaceLayer(_ layer: CAMetalLayer) {
        layer.device = sharedResources.device
        layer.pixelFormat = .bgra8Unorm
        layer.isOpaque = metalLayer.isOpaque
        layer.maximumDrawableCount = 3
        self.metalLayer = layer
    }

    public func layer() -> CAMetalLayer {
        metalLayer
    }

    public func layerPtr() -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(metalLayer).toOpaque()
    }

    public func spriteAtlas() -> MetalAtlas {
        sharedResources.spriteAtlas
    }

    public func setPresentsWithTransaction(_ presentsWithTransaction: Bool) {
        self.presentsWithTransaction = presentsWithTransaction
        self.metalLayer.presentsWithTransaction = presentsWithTransaction
    }

    public func updateDrawableSize(_ size: Size<DevicePixels>) {
        let cgSize = CGSize(
            width: CGFloat(size.width.value),
            height: CGFloat(size.height.value)
        )
        metalLayer.drawableSize = cgSize
        let devicePixelsSize = Size(
            width: DevicePixels(Int32(cgSize.width)),
            height: DevicePixels(Int32(cgSize.height))
        )
        updatePathIntermediateTextures(
            device: sharedResources.device,
            pathSampleCount: sharedResources.pathSampleCount,
            pathIntermediateTexture: &pathIntermediateTexture,
            pathIntermediateMsaaTexture: &pathIntermediateMsaaTexture,
            isAppleGpu: sharedResources.isAppleGpu,
            size: devicePixelsSize
        )
    }

    public func updateTransparency(_ transparent: Bool) {
        metalLayer.isOpaque = !transparent
    }

    /// Returns hardware and driver metadata for this Metal renderer's `MTLDevice`.
    public func gpuSpecs() -> GpuSpecs {
        let device = sharedResources.device
        let architectureName: String
        if #available(macOS 14.0, iOS 17.0, *) {
            architectureName = device.architecture.name
        } else {
            architectureName = sharedResources.isAppleGpu ? "Apple GPU" : "Metal GPU"
        }
        return GpuSpecs(
            isSoftwareEmulated: false,
            deviceName: device.name,
            driverName: "Metal",
            driverInfo: "\(architectureName) (unifiedMemory: \(sharedResources.isUnifiedMemory))"
        )
    }

    public func destroy() {
        pathIntermediateTexture = nil
        pathIntermediateMsaaTexture = nil
    }

    public func draw(_ scene: Scene) {
        drawScene(
            shared: sharedResources,
            layer: metalLayer,
            pathIntermediateTexture: pathIntermediateTexture,
            pathIntermediateMsaaTexture: pathIntermediateMsaaTexture,
            scene: scene,
            presentsWithTransaction: presentsWithTransaction
        )
    }

    /// Renders `scene` into an offscreen `BGRA8Unorm` Metal texture of `size` and reads back straight `RGBA8` pixels.
    public func renderToTexture(
        _ scene: Scene,
        size: Size<DevicePixels>,
        background: Hsla? = nil
    ) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        let width = Int(size.width.value)
        let height = Int(size.height.value)
        guard width > 0, height > 0 else {
            throw MetalRendererError.invalidViewportSize(size)
        }

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        targetDescriptor.usage = [.renderTarget, .shaderRead]
        #if os(macOS)
        targetDescriptor.storageMode = sharedResources.isUnifiedMemory ? .shared : .managed
        #else
        targetDescriptor.storageMode = .shared
        #endif

        guard let targetTexture = sharedResources.device.makeTexture(descriptor: targetDescriptor) else {
            throw MetalRendererError.offscreenTextureCreationFailed(size)
        }

        var localPathTexture = pathIntermediateTexture
        var localPathMsaaTexture = pathIntermediateMsaaTexture
        if localPathTexture == nil
            || localPathTexture?.width != width
            || localPathTexture?.height != height {
            updatePathIntermediateTextures(
                device: sharedResources.device,
                pathSampleCount: sharedResources.pathSampleCount,
                pathIntermediateTexture: &localPathTexture,
                pathIntermediateMsaaTexture: &localPathMsaaTexture,
                isAppleGpu: sharedResources.isAppleGpu,
                size: size
            )
        }

        let clearColor: MTLClearColor
        if let background {
            let rgba = background.toRgb()
            clearColor = MTLClearColorMake(
                Double(rgba.r),
                Double(rgba.g),
                Double(rgba.b),
                Double(rgba.a)
            )
        } else {
            let alpha = metalLayer.isOpaque ? 1.0 : 0.0
            clearColor = MTLClearColorMake(0.0, 0.0, 0.0, alpha)
        }

        while true {
            var instanceBuffer = sharedResources.instanceBufferPool.acquire(
                sharedResources.device,
                sharedResources.isUnifiedMemory
            )

            do {
                let commandBuffer = try drawPrimitives(
                    shared: sharedResources,
                    pathIntermediateTexture: localPathTexture,
                    pathIntermediateMsaaTexture: localPathMsaaTexture,
                    clearColor: clearColor,
                    scene: scene,
                    instanceBuffer: &instanceBuffer,
                    targetTexture: targetTexture,
                    viewportSize: size
                )

                #if os(macOS)
                if !sharedResources.isUnifiedMemory,
                   let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
                    blitEncoder.synchronize(resource: targetTexture)
                    blitEncoder.endEncoding()
                }
                #endif

                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()
                sharedResources.instanceBufferPool.release(instanceBuffer)

                let bytesPerRow = width * 4
                var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
                let region = MTLRegionMake2D(0, 0, width, height)
                pixels.withUnsafeMutableBytes { rawPtr in
                    guard let baseAddress = rawPtr.baseAddress else { return }
                    targetTexture.getBytes(
                        baseAddress,
                        bytesPerRow: bytesPerRow,
                        from: region,
                        mipmapLevel: 0
                    )
                }

                // Convert BGRA8Unorm to RGBA8 (swap B and R channels).
                var idx = 0
                let totalBytes = pixels.count
                while idx + 3 < totalBytes {
                    pixels.swapAt(idx, idx + 2)
                    idx += 4
                }

                return (width: width, height: height, rgba: pixels)
            } catch {
                let currentSize = sharedResources.instanceBufferPool.bufferSize
                if currentSize >= 256 * 1024 * 1024 {
                    throw MetalRendererError.instanceBufferOverflow(currentSize)
                }
                sharedResources.instanceBufferPool.reset(currentSize * 2)
            }
        }
    }

    /// Renders the scene offscreen at the current drawable size and encodes a PNG `GPUI.Image`.
    public func renderToImage(_ scene: Scene) throws -> GPUI.Image {
        let drawableSize = metalLayer.drawableSize
        let viewportSize = Size(
            width: DevicePixels(Int32(drawableSize.width.rounded(.up))),
            height: DevicePixels(Int32(drawableSize.height.rounded(.up)))
        )
        let rendered = try renderToTexture(scene, size: viewportSize, background: nil)
        let pngData = try encodeRgbaToPng(
            width: rendered.width,
            height: rendered.height,
            rgba: rendered.rgba
        )
        return GPUI.Image(
            format: .png,
            bytes: Array(pngData),
            width: rendered.width,
            height: rendered.height
        )
    }
}

// MARK: - SurfaceRenderer

/// Lightweight renderer for secondary GPUI surfaces sharing `SharedRenderResources`.
// PORT NOTE: Shares pipeline states, command queue, and sprite atlas with `MetalRenderer`,
// owning only its per-surface `CAMetalLayer` and MSAA path textures.
public final class SurfaceRenderer: @unchecked Sendable {
    private let sharedResources: SharedRenderResources
    private let metalLayer: CAMetalLayer
    private var pathIntermediateTexture: (any MTLTexture)?
    private var pathIntermediateMsaaTexture: (any MTLTexture)?

    public init(_ shared: SharedRenderResources, _ transparent: Bool = false) {
        let layer = CAMetalLayer()
        configureMetalLayer(layer, device: shared.device, transparent: transparent)
        self.sharedResources = shared
        self.metalLayer = layer
        self.pathIntermediateTexture = nil
        self.pathIntermediateMsaaTexture = nil
    }

    public convenience init(shared: SharedRenderResources, transparent: Bool = false) {
        self.init(shared, transparent)
    }

    public static func new(_ shared: SharedRenderResources, _ transparent: Bool = false) -> SurfaceRenderer {
        SurfaceRenderer(shared, transparent)
    }

    public func layer() -> CAMetalLayer {
        metalLayer
    }

    public func layerPtr() -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(metalLayer).toOpaque()
    }

    public func updateDrawableSize(_ size: Size<DevicePixels>) {
        let cgSize = CGSize(
            width: CGFloat(size.width.value),
            height: CGFloat(size.height.value)
        )
        metalLayer.drawableSize = cgSize
        updatePathIntermediateTextures(
            device: sharedResources.device,
            pathSampleCount: sharedResources.pathSampleCount,
            pathIntermediateTexture: &pathIntermediateTexture,
            pathIntermediateMsaaTexture: &pathIntermediateMsaaTexture,
            isAppleGpu: sharedResources.isAppleGpu,
            size: size
        )
    }

    public func updateTransparency(_ transparent: Bool) {
        metalLayer.isOpaque = !transparent
    }

    public func draw(_ scene: Scene) {
        drawScene(
            shared: sharedResources,
            layer: metalLayer,
            pathIntermediateTexture: pathIntermediateTexture,
            pathIntermediateMsaaTexture: pathIntermediateMsaaTexture,
            scene: scene,
            presentsWithTransaction: false
        )
    }
}

// MARK: - Shared Rendering Helpers

private func updatePathIntermediateTextures(
    device: any MTLDevice,
    pathSampleCount: UInt32,
    pathIntermediateTexture: inout (any MTLTexture)?,
    pathIntermediateMsaaTexture: inout (any MTLTexture)?,
    isAppleGpu: Bool,
    size: Size<DevicePixels>
) {
    if size.width.value <= 0 || size.height.value <= 0 {
        pathIntermediateTexture = nil
        pathIntermediateMsaaTexture = nil
        return
    }

    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.width = Int(size.width.value)
    textureDescriptor.height = Int(size.height.value)
    textureDescriptor.pixelFormat = .bgra8Unorm
    textureDescriptor.storageMode = .private
    textureDescriptor.usage = [.renderTarget, .shaderRead]
    pathIntermediateTexture = device.makeTexture(descriptor: textureDescriptor)

    if pathSampleCount > 1 {
        let msaaDescriptor = MTLTextureDescriptor()
        msaaDescriptor.textureType = .type2DMultisample
        msaaDescriptor.width = Int(size.width.value)
        msaaDescriptor.height = Int(size.height.value)
        msaaDescriptor.pixelFormat = .bgra8Unorm
        msaaDescriptor.storageMode = isAppleGpu ? .memoryless : .private
        msaaDescriptor.usage = [.renderTarget, .shaderRead]
        msaaDescriptor.sampleCount = Int(pathSampleCount)
        pathIntermediateMsaaTexture = device.makeTexture(descriptor: msaaDescriptor)
    } else {
        pathIntermediateMsaaTexture = nil
    }
}

private func drawScene(
    shared: SharedRenderResources,
    layer: CAMetalLayer,
    pathIntermediateTexture: (any MTLTexture)?,
    pathIntermediateMsaaTexture: (any MTLTexture)?,
    scene: Scene,
    presentsWithTransaction: Bool
) {
    let rawDrawableSize = layer.drawableSize
    let viewportSize = Size(
        width: DevicePixels(Int32(rawDrawableSize.width.rounded(.up))),
        height: DevicePixels(Int32(rawDrawableSize.height.rounded(.up)))
    )
    guard viewportSize.width.value > 0, viewportSize.height.value > 0 else {
        return
    }
    guard let drawable = layer.nextDrawable() else {
        return
    }

    let alpha = layer.isOpaque ? 1.0 : 0.0
    let clearColor = MTLClearColorMake(0.0, 0.0, 0.0, alpha)

    while true {
        var instanceBuffer = shared.instanceBufferPool.acquire(
            shared.device,
            shared.isUnifiedMemory
        )

        do {
            let commandBuffer = try drawPrimitives(
                shared: shared,
                pathIntermediateTexture: pathIntermediateTexture,
                pathIntermediateMsaaTexture: pathIntermediateMsaaTexture,
                clearColor: clearColor,
                scene: scene,
                instanceBuffer: &instanceBuffer,
                targetTexture: drawable.texture,
                viewportSize: viewportSize
            )

            let pool = shared.instanceBufferPool
            let bufferToRelease = instanceBuffer
            commandBuffer.addCompletedHandler { _ in
                pool.release(bufferToRelease)
            }

            if presentsWithTransaction {
                commandBuffer.commit()
                commandBuffer.waitUntilScheduled()
                drawable.present()
            } else {
                commandBuffer.present(drawable)
                commandBuffer.commit()
            }
            return
        } catch {
            let currentSize = shared.instanceBufferPool.bufferSize
            if currentSize >= 256 * 1024 * 1024 {
                break
            }
            shared.instanceBufferPool.reset(currentSize * 2)
        }
    }
}

private func drawPrimitives(
    shared: SharedRenderResources,
    pathIntermediateTexture: (any MTLTexture)?,
    pathIntermediateMsaaTexture: (any MTLTexture)?,
    clearColor: MTLClearColor,
    scene: Scene,
    instanceBuffer: inout InstanceBuffer,
    targetTexture: any MTLTexture,
    viewportSize: Size<DevicePixels>
) throws -> any MTLCommandBuffer {
    guard let commandBuffer = shared.commandQueue.makeCommandBuffer() else {
        throw MetalRendererError.commandBufferCreationFailed
    }

    var instanceOffset = 0
    var commandEncoder = try makeRenderCommandEncoder(
        commandBuffer: commandBuffer,
        targetTexture: targetTexture,
        viewportSize: viewportSize
    ) { colorAttachment in
        colorAttachment.loadAction = .clear
        colorAttachment.clearColor = clearColor
    }

    for batch in scene.batches() {
        let ok: Bool
        switch batch {
        case .shadows(let range):
            ok = drawShadows(
                shared: shared,
                shadows: scene.shadows[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
        case .quads(let range):
            ok = drawQuads(
                shared: shared,
                quads: scene.quads[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
        case .paths(let range):
            let paths = scene.paths[range]
            commandEncoder.endEncoding()

            let didDraw = drawPathsToIntermediate(
                shared: shared,
                pathIntermediateTexture: pathIntermediateTexture,
                pathIntermediateMsaaTexture: pathIntermediateMsaaTexture,
                paths: paths,
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandBuffer: commandBuffer
            )

            commandEncoder = try makeRenderCommandEncoder(
                commandBuffer: commandBuffer,
                targetTexture: targetTexture,
                viewportSize: viewportSize
            ) { colorAttachment in
                colorAttachment.loadAction = .load
            }

            if didDraw {
                ok = drawPathsFromIntermediate(
                    shared: shared,
                    pathIntermediateTexture: pathIntermediateTexture,
                    paths: paths,
                    instanceBuffer: &instanceBuffer,
                    instanceOffset: &instanceOffset,
                    viewportSize: viewportSize,
                    commandEncoder: commandEncoder
                )
            } else {
                ok = false
            }
        case .underlines(let range):
            ok = drawUnderlines(
                shared: shared,
                underlines: scene.underlines[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
        case .monochromeSprites(let textureId, let range):
            ok = drawMonochromeSprites(
                shared: shared,
                textureId: textureId,
                sprites: scene.monochromeSprites[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
        case .polychromeSprites(let textureId, let range):
            ok = drawPolychromeSprites(
                shared: shared,
                textureId: textureId,
                sprites: scene.polychromeSprites[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
        case .surfaces(let range):
            #if os(macOS)
            ok = drawSurfacesBatch(
                shared: shared,
                surfaces: scene.surfaces[range],
                instanceBuffer: &instanceBuffer,
                instanceOffset: &instanceOffset,
                viewportSize: viewportSize,
                commandEncoder: commandEncoder
            )
            #else
            _ = range
            ok = true
            #endif
        case .subpixelSprites:
            // PORT NOTE: Metal does not use subpixel glyph sprites on Apple displays; ignore gracefully.
            ok = true
        }

        if !ok {
            commandEncoder.endEncoding()
            throw MetalRendererError.instanceBufferOverflow(instanceBuffer.size)
        }
    }

    commandEncoder.endEncoding()

    #if os(macOS)
    if !shared.isUnifiedMemory && instanceOffset > 0 {
        instanceBuffer.metalBuffer.didModifyRange(0..<instanceOffset)
    }
    #endif

    return commandBuffer
}

private func drawPathsToIntermediate(
    shared: SharedRenderResources,
    pathIntermediateTexture: (any MTLTexture)?,
    pathIntermediateMsaaTexture: (any MTLTexture)?,
    paths: ArraySlice<GPUI.Path<ScaledPixels>>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandBuffer: any MTLCommandBuffer
) -> Bool {
    if paths.isEmpty {
        return true
    }
    guard let intermediateTexture = pathIntermediateTexture else {
        return false
    }

    let renderPassDescriptor = MTLRenderPassDescriptor()
    guard let colorAttachment = renderPassDescriptor.colorAttachments[0] else {
        return false
    }
    colorAttachment.loadAction = .clear
    colorAttachment.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0)

    if let msaaTexture = pathIntermediateMsaaTexture {
        colorAttachment.texture = msaaTexture
        colorAttachment.resolveTexture = intermediateTexture
        colorAttachment.storeAction = .multisampleResolve
    } else {
        colorAttachment.texture = intermediateTexture
        colorAttachment.storeAction = .store
    }

    guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
        return false
    }
    commandEncoder.setRenderPipelineState(shared.pathsRasterizationPipelineState)

    alignOffset(&instanceOffset)

    var totalVertices = 0
    for path in paths {
        totalVertices += path.vertices.count
    }
    if totalVertices == 0 {
        commandEncoder.endEncoding()
        return true
    }

    let stride = MemoryLayout<MetalPathRasterizationVertex>.stride
    let verticesBytesLen = totalVertices * stride
    let nextOffset = instanceOffset + verticesBytesLen
    if nextOffset > instanceBuffer.size {
        commandEncoder.endEncoding()
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIndex = 0
    for path in paths {
        let clippedBounds = path.bounds.intersect(path.contentMask.bounds)
        let metalColor = MetalBackground(path.color)
        let metalBounds = MetalBoundsScaledPixels(clippedBounds)
        for v in path.vertices {
            let gpuVertex = MetalPathRasterizationVertex(
                xyPosition: MetalPointF(v.xyPosition),
                stPosition: MetalPointF(v.stPosition),
                color: metalColor,
                bounds: metalBounds
            )
            basePtr.storeBytes(
                of: gpuVertex,
                toByteOffset: writeIndex * stride,
                as: MetalPathRasterizationVertex.self
            )
            writeIndex += 1
        }
    }

    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: PathRasterizationInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: PathRasterizationInputIndex.viewportSize.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: PathRasterizationInputIndex.vertices.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: totalVertices
    )

    instanceOffset = nextOffset
    commandEncoder.endEncoding()
    return true
}

private func drawPathsFromIntermediate(
    shared: SharedRenderResources,
    pathIntermediateTexture: (any MTLTexture)?,
    paths: ArraySlice<GPUI.Path<ScaledPixels>>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    guard let firstPath = paths.first, let lastPath = paths.last else {
        return true
    }
    guard let intermediateTexture = pathIntermediateTexture else {
        return false
    }

    let sprites: [MetalPathSprite]
    if lastPath.order == firstPath.order {
        sprites = paths.map { path in
            MetalPathSprite(PathSprite(bounds: path.clippedBounds))
        }
    } else {
        var combinedBounds = firstPath.clippedBounds
        for path in paths.dropFirst() {
            combinedBounds = combinedBounds.union(path.clippedBounds)
        }
        sprites = [MetalPathSprite(PathSprite(bounds: combinedBounds))]
    }

    alignOffset(&instanceOffset)
    let stride = MemoryLayout<MetalPathSprite>.stride
    let spriteBytesLen = sprites.count * stride
    let nextOffset = instanceOffset + spriteBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    for (idx, sprite) in sprites.enumerated() {
        basePtr.storeBytes(of: sprite, toByteOffset: idx * stride, as: MetalPathSprite.self)
    }

    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    commandEncoder.setRenderPipelineState(shared.pathSpritesPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: SpriteInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: SpriteInputIndex.viewportSize.rawValue
    )
    commandEncoder.setFragmentTexture(
        intermediateTexture,
        index: SpriteInputIndex.atlasTexture.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: SpriteInputIndex.sprites.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: sprites.count
    )

    instanceOffset = nextOffset
    return true
}

private func drawShadows(
    shared: SharedRenderResources,
    shadows: ArraySlice<Shadow>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    if shadows.isEmpty {
        return true
    }
    alignOffset(&instanceOffset)

    let stride = MemoryLayout<MetalShadow>.stride
    let shadowBytesLen = shadows.count * stride
    let nextOffset = instanceOffset + shadowBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIdx = 0
    for shadow in shadows {
        basePtr.storeBytes(
            of: MetalShadow(shadow),
            toByteOffset: writeIdx * stride,
            as: MetalShadow.self
        )
        writeIdx += 1
    }

    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    commandEncoder.setRenderPipelineState(shared.shadowsPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: ShadowInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: ShadowInputIndex.shadows.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: ShadowInputIndex.shadows.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: ShadowInputIndex.viewportSize.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: shadows.count
    )

    instanceOffset = nextOffset
    return true
}

private func drawQuads(
    shared: SharedRenderResources,
    quads: ArraySlice<Quad>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    if quads.isEmpty {
        return true
    }
    alignOffset(&instanceOffset)

    let stride = MemoryLayout<MetalQuad>.stride
    let quadBytesLen = quads.count * stride
    let nextOffset = instanceOffset + quadBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIdx = 0
    for quad in quads {
        basePtr.storeBytes(
            of: MetalQuad(quad),
            toByteOffset: writeIdx * stride,
            as: MetalQuad.self
        )
        writeIdx += 1
    }

    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    commandEncoder.setRenderPipelineState(shared.quadsPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: QuadInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: QuadInputIndex.quads.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: QuadInputIndex.quads.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: QuadInputIndex.viewportSize.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: quads.count
    )

    instanceOffset = nextOffset
    return true
}

private func drawUnderlines(
    shared: SharedRenderResources,
    underlines: ArraySlice<Underline>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    if underlines.isEmpty {
        return true
    }
    alignOffset(&instanceOffset)

    let stride = MemoryLayout<MetalUnderline>.stride
    let underlineBytesLen = underlines.count * stride
    let nextOffset = instanceOffset + underlineBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIdx = 0
    for underline in underlines {
        basePtr.storeBytes(
            of: MetalUnderline(underline),
            toByteOffset: writeIdx * stride,
            as: MetalUnderline.self
        )
        writeIdx += 1
    }

    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    commandEncoder.setRenderPipelineState(shared.underlinesPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: UnderlineInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: UnderlineInputIndex.underlines.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: UnderlineInputIndex.underlines.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: UnderlineInputIndex.viewportSize.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: underlines.count
    )

    instanceOffset = nextOffset
    return true
}

private func drawMonochromeSprites(
    shared: SharedRenderResources,
    textureId: AtlasTextureId,
    sprites: ArraySlice<MonochromeSprite>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    if sprites.isEmpty {
        return true
    }
    alignOffset(&instanceOffset)

    let stride = MemoryLayout<MetalMonochromeSprite>.stride
    let spriteBytesLen = sprites.count * stride
    let nextOffset = instanceOffset + spriteBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIdx = 0
    for sprite in sprites {
        basePtr.storeBytes(
            of: MetalMonochromeSprite(sprite),
            toByteOffset: writeIdx * stride,
            as: MetalMonochromeSprite.self
        )
        writeIdx += 1
    }

    let texture = shared.spriteAtlas.metalTexture(textureId)
    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    var gpuTextureSize = MetalSizeDevicePixels(
        Size(width: DevicePixels(Int32(texture.width)), height: DevicePixels(Int32(texture.height)))
    )

    commandEncoder.setRenderPipelineState(shared.monochromeSpritesPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: SpriteInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: SpriteInputIndex.sprites.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: SpriteInputIndex.viewportSize.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuTextureSize,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: SpriteInputIndex.atlasTextureSize.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: SpriteInputIndex.sprites.rawValue
    )
    commandEncoder.setFragmentTexture(
        texture,
        index: SpriteInputIndex.atlasTexture.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: sprites.count
    )

    instanceOffset = nextOffset
    return true
}

private func drawPolychromeSprites(
    shared: SharedRenderResources,
    textureId: AtlasTextureId,
    sprites: ArraySlice<PolychromeSprite>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    if sprites.isEmpty {
        return true
    }
    alignOffset(&instanceOffset)

    let stride = MemoryLayout<MetalPolychromeSprite>.stride
    let spriteBytesLen = sprites.count * stride
    let nextOffset = instanceOffset + spriteBytesLen
    if nextOffset > instanceBuffer.size {
        return false
    }

    let basePtr = instanceBuffer.metalBuffer.contents().advanced(by: instanceOffset)
    var writeIdx = 0
    for sprite in sprites {
        basePtr.storeBytes(
            of: MetalPolychromeSprite(sprite),
            toByteOffset: writeIdx * stride,
            as: MetalPolychromeSprite.self
        )
        writeIdx += 1
    }

    let texture = shared.spriteAtlas.metalTexture(textureId)
    var gpuViewport = MetalSizeDevicePixels(viewportSize)
    var gpuTextureSize = MetalSizeDevicePixels(
        Size(width: DevicePixels(Int32(texture.width)), height: DevicePixels(Int32(texture.height)))
    )

    commandEncoder.setRenderPipelineState(shared.polychromeSpritesPipelineState)
    commandEncoder.setVertexBuffer(
        shared.unitVertices,
        offset: 0,
        index: SpriteInputIndex.vertices.rawValue
    )
    commandEncoder.setVertexBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: SpriteInputIndex.sprites.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuViewport,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: SpriteInputIndex.viewportSize.rawValue
    )
    commandEncoder.setVertexBytes(
        &gpuTextureSize,
        length: MemoryLayout<MetalSizeDevicePixels>.stride,
        index: SpriteInputIndex.atlasTextureSize.rawValue
    )
    commandEncoder.setFragmentBuffer(
        instanceBuffer.metalBuffer,
        offset: instanceOffset,
        index: SpriteInputIndex.sprites.rawValue
    )
    commandEncoder.setFragmentTexture(
        texture,
        index: SpriteInputIndex.atlasTexture.rawValue
    )
    commandEncoder.drawPrimitives(
        type: .triangle,
        vertexStart: 0,
        vertexCount: 6,
        instanceCount: sprites.count
    )

    instanceOffset = nextOffset
    return true
}

#if os(macOS)
private func drawSurfacesBatch(
    shared: SharedRenderResources,
    surfaces: ArraySlice<PaintSurface>,
    instanceBuffer: inout InstanceBuffer,
    instanceOffset: inout Int,
    viewportSize: Size<DevicePixels>,
    commandEncoder: any MTLRenderCommandEncoder
) -> Bool {
    let stride = MemoryLayout<MetalSurfaceBounds>.stride
    for surface in surfaces {
        guard let imageBuffer = surface.imageBuffer else {
            continue
        }
        let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        alignOffset(&instanceOffset)
        let nextOffset = instanceOffset + stride
        if nextOffset > instanceBuffer.size {
            return false
        }

        if pixelFormat == kCVPixelFormatType_32BGRA {
            commandEncoder.setRenderPipelineState(shared.bgraSurfacesPipelineState)
        } else {
            commandEncoder.setRenderPipelineState(shared.surfacesPipelineState)
        }

        var gpuViewport = MetalSizeDevicePixels(viewportSize)
        var gpuTextureSize = MetalSizeDevicePixels(
            Size(width: DevicePixels(Int32(width)), height: DevicePixels(Int32(height)))
        )

        commandEncoder.setVertexBuffer(
            shared.unitVertices,
            offset: 0,
            index: SurfaceInputIndex.vertices.rawValue
        )
        commandEncoder.setVertexBytes(
            &gpuViewport,
            length: MemoryLayout<MetalSizeDevicePixels>.stride,
            index: SurfaceInputIndex.viewportSize.rawValue
        )
        commandEncoder.setVertexBuffer(
            instanceBuffer.metalBuffer,
            offset: instanceOffset,
            index: SurfaceInputIndex.surfaces.rawValue
        )
        commandEncoder.setVertexBytes(
            &gpuTextureSize,
            length: MemoryLayout<MetalSizeDevicePixels>.stride,
            index: SurfaceInputIndex.textureSize.rawValue
        )

        // Retain CVMetalTexture handles for the duration of the draw call.
        var primaryCvTexture: CVMetalTexture?
        var secondaryCvTexture: CVMetalTexture?

        if pixelFormat == kCVPixelFormatType_32BGRA {
            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                shared.coreVideoTextureCache,
                imageBuffer,
                nil,
                .bgra8Unorm,
                width,
                height,
                0,
                &primaryCvTexture
            )
            guard status == kCVReturnSuccess,
                  let cvTex = primaryCvTexture,
                  let mtlTex = CVMetalTextureGetTexture(cvTex) else {
                continue
            }
            commandEncoder.setFragmentTexture(mtlTex, index: SurfaceInputIndex.yTexture.rawValue)
        } else {
            guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
                continue
            }
            let yStatus = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                shared.coreVideoTextureCache,
                imageBuffer,
                nil,
                .r8Unorm,
                CVPixelBufferGetWidthOfPlane(imageBuffer, 0),
                CVPixelBufferGetHeightOfPlane(imageBuffer, 0),
                0,
                &primaryCvTexture
            )
            let cbCrStatus = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                shared.coreVideoTextureCache,
                imageBuffer,
                nil,
                .rg8Unorm,
                CVPixelBufferGetWidthOfPlane(imageBuffer, 1),
                CVPixelBufferGetHeightOfPlane(imageBuffer, 1),
                1,
                &secondaryCvTexture
            )
            guard yStatus == kCVReturnSuccess,
                  cbCrStatus == kCVReturnSuccess,
                  let yCv = primaryCvTexture,
                  let cbCrCv = secondaryCvTexture,
                  let yTex = CVMetalTextureGetTexture(yCv),
                  let cbCrTex = CVMetalTextureGetTexture(cbCrCv) else {
                continue
            }
            commandEncoder.setFragmentTexture(yTex, index: SurfaceInputIndex.yTexture.rawValue)
            commandEncoder.setFragmentTexture(cbCrTex, index: SurfaceInputIndex.cbCrTexture.rawValue)
        }

        let gpuSurface = MetalSurfaceBounds(
            SurfaceBounds(bounds: surface.bounds, contentMask: surface.contentMask)
        )
        instanceBuffer.metalBuffer.contents()
            .advanced(by: instanceOffset)
            .storeBytes(of: gpuSurface, as: MetalSurfaceBounds.self)

        commandEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        instanceOffset = nextOffset

        withExtendedLifetime((primaryCvTexture, secondaryCvTexture)) {}
    }
    return true
}
#endif

// MARK: - Command Encoder & Pipeline Builders

private func makeRenderCommandEncoder(
    commandBuffer: any MTLCommandBuffer,
    targetTexture: any MTLTexture,
    viewportSize: Size<DevicePixels>,
    configureColorAttachment: (MTLRenderPassColorAttachmentDescriptor) -> Void
) throws -> any MTLRenderCommandEncoder {
    let renderPassDescriptor = MTLRenderPassDescriptor()
    guard let colorAttachment = renderPassDescriptor.colorAttachments[0] else {
        throw MetalRendererError.commandEncoderCreationFailed
    }
    colorAttachment.texture = targetTexture
    colorAttachment.storeAction = .store
    configureColorAttachment(colorAttachment)

    guard let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
        throw MetalRendererError.commandEncoderCreationFailed
    }
    commandEncoder.setViewport(
        MTLViewport(
            originX: 0.0,
            originY: 0.0,
            width: Double(viewportSize.width.value),
            height: Double(viewportSize.height.value),
            znear: 0.0,
            zfar: 1.0
        )
    )
    return commandEncoder
}

private func buildPipelineState(
    device: any MTLDevice,
    library: any MTLLibrary,
    label: String,
    vertexFnName: String,
    fragmentFnName: String,
    pixelFormat: MTLPixelFormat
) throws -> any MTLRenderPipelineState {
    guard let vertexFn = library.makeFunction(name: vertexFnName) else {
        throw MetalRendererError.missingShaderFunction(vertexFnName)
    }
    guard let fragmentFn = library.makeFunction(name: fragmentFnName) else {
        throw MetalRendererError.missingShaderFunction(fragmentFnName)
    }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.label = label
    descriptor.vertexFunction = vertexFn
    descriptor.fragmentFunction = fragmentFn

    guard let colorAttachment = descriptor.colorAttachments[0] else {
        throw MetalRendererError.pipelineCreationFailed(label)
    }
    colorAttachment.pixelFormat = pixelFormat
    colorAttachment.isBlendingEnabled = true
    colorAttachment.rgbBlendOperation = .add
    colorAttachment.alphaBlendOperation = .add
    colorAttachment.sourceRGBBlendFactor = .sourceAlpha
    colorAttachment.sourceAlphaBlendFactor = .one
    colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    colorAttachment.destinationAlphaBlendFactor = .one

    do {
        return try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
        throw MetalRendererError.pipelineCreationFailed("\(label): \(error)")
    }
}

private func buildPathSpritePipelineState(
    device: any MTLDevice,
    library: any MTLLibrary,
    label: String,
    vertexFnName: String,
    fragmentFnName: String,
    pixelFormat: MTLPixelFormat
) throws -> any MTLRenderPipelineState {
    guard let vertexFn = library.makeFunction(name: vertexFnName) else {
        throw MetalRendererError.missingShaderFunction(vertexFnName)
    }
    guard let fragmentFn = library.makeFunction(name: fragmentFnName) else {
        throw MetalRendererError.missingShaderFunction(fragmentFnName)
    }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.label = label
    descriptor.vertexFunction = vertexFn
    descriptor.fragmentFunction = fragmentFn

    guard let colorAttachment = descriptor.colorAttachments[0] else {
        throw MetalRendererError.pipelineCreationFailed(label)
    }
    colorAttachment.pixelFormat = pixelFormat
    colorAttachment.isBlendingEnabled = true
    colorAttachment.rgbBlendOperation = .add
    colorAttachment.alphaBlendOperation = .add
    colorAttachment.sourceRGBBlendFactor = .one
    colorAttachment.sourceAlphaBlendFactor = .one
    colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    colorAttachment.destinationAlphaBlendFactor = .one

    do {
        return try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
        throw MetalRendererError.pipelineCreationFailed("\(label): \(error)")
    }
}

private func buildPathRasterizationPipelineState(
    device: any MTLDevice,
    library: any MTLLibrary,
    label: String,
    vertexFnName: String,
    fragmentFnName: String,
    pixelFormat: MTLPixelFormat,
    pathSampleCount: UInt32
) throws -> any MTLRenderPipelineState {
    guard let vertexFn = library.makeFunction(name: vertexFnName) else {
        throw MetalRendererError.missingShaderFunction(vertexFnName)
    }
    guard let fragmentFn = library.makeFunction(name: fragmentFnName) else {
        throw MetalRendererError.missingShaderFunction(fragmentFnName)
    }

    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.label = label
    descriptor.vertexFunction = vertexFn
    descriptor.fragmentFunction = fragmentFn
    if pathSampleCount > 1 {
        descriptor.rasterSampleCount = Int(pathSampleCount)
        descriptor.isAlphaToCoverageEnabled = false
    }

    guard let colorAttachment = descriptor.colorAttachments[0] else {
        throw MetalRendererError.pipelineCreationFailed(label)
    }
    colorAttachment.pixelFormat = pixelFormat
    colorAttachment.isBlendingEnabled = true
    colorAttachment.rgbBlendOperation = .add
    colorAttachment.alphaBlendOperation = .add
    colorAttachment.sourceRGBBlendFactor = .one
    colorAttachment.sourceAlphaBlendFactor = .one
    colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

    do {
        return try device.makeRenderPipelineState(descriptor: descriptor)
    } catch {
        throw MetalRendererError.pipelineCreationFailed("\(label): \(error)")
    }
}

/// Aligns offset up to the next 256-byte boundary required by Metal constant buffer bindings.
private func alignOffset(_ offset: inout Int) {
    offset = (offset + 255) & ~255
}

// MARK: - PNG Encoding Helper

private func encodeRgbaToPng(width: Int, height: Int, rgba: [UInt8]) throws -> Data {
    let bytesPerRow = width * 4
    guard width > 0, height > 0, rgba.count >= height * bytesPerRow else {
        throw MetalRendererError.imageEncodingFailed
    }

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let data = Data(rgba)
    guard let provider = CGDataProvider(data: data as CFData) else {
        throw MetalRendererError.imageEncodingFailed
    }

    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
    guard let cgImage = CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    ) else {
        throw MetalRendererError.imageEncodingFailed
    }

    guard let mutableData = CFDataCreateMutable(kCFAllocatorDefault, 0),
          let destination = CGImageDestinationCreateWithData(
              mutableData,
              UTType.png.identifier as CFString,
              1,
              nil
          ) else {
        throw MetalRendererError.imageEncodingFailed
    }

    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw MetalRendererError.imageEncodingFailed
    }

    return mutableData as Data
}
#endif
