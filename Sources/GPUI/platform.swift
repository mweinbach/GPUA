// Ported from: crates/gpui/src/platform.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Refineable
import Scheduler

/// Mouse cursor styles matching CSS cursor values.
public enum CursorStyle: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// The default cursor.
    case arrow
    /// A text input cursor (corresponds to CSS `text`).
    case iBeam
    /// A crosshair cursor (corresponds to CSS `crosshair`).
    case crosshair
    /// A closed hand cursor (corresponds to CSS `grabbing`).
    case closedHand
    /// An open hand cursor (corresponds to CSS `grab`).
    case openHand
    /// A pointing hand cursor (corresponds to CSS `pointer`).
    case pointingHand
    /// A resize left cursor (corresponds to CSS `w-resize`).
    case resizeLeft
    /// A resize right cursor (corresponds to CSS `e-resize`).
    case resizeRight
    /// A resize cursor to the left and right (corresponds to CSS `ew-resize`).
    case resizeLeftRight
    /// A resize up cursor (corresponds to CSS `n-resize`).
    case resizeUp
    /// A resize down cursor (corresponds to CSS `s-resize`).
    case resizeDown
    /// A resize cursor up and down (corresponds to CSS `ns-resize`).
    case resizeUpDown
    /// A resize up-left cursor.
    case resizeUpLeft
    /// A resize down-right cursor.
    case resizeDownRight
    /// A resize diagonal cursor (corresponds to CSS `nwse-resize`).
    case resizeUpLeftDownRight
    /// A resize up-right cursor.
    case resizeUpRight
    /// A resize down-left cursor.
    case resizeDownLeft
    /// A resize diagonal cursor (corresponds to CSS `nesw-resize`).
    case resizeUpRightDownLeft
    /// A not allowed cursor.
    case notAllowed
    /// A wait cursor.
    case wait
    /// A progress cursor.
    case progress
    /// A copy cursor.
    case copy
    /// None (invisible cursor).
    case none

    public init() {
        self = .arrow
    }
}

// MARK: - Atlas Types

/// The unique ID of a tile within an atlas texture.
@frozen
public struct TileId: RawRepresentable, Sendable, Equatable, Hashable, Comparable, Codable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: TileId, rhs: TileId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The kind of content stored in an atlas texture.
@frozen
public enum AtlasTextureKind: UInt32, Sendable, Equatable, Hashable, Codable {
    case monochrome = 0
    case polychrome = 1
    case subpixel = 2
}

/// The identifier of a texture within the atlas.
@frozen
public struct AtlasTextureId: Sendable, Equatable, Hashable, Codable {
    /// The index of this texture in the atlas.
    public var index: UInt32
    /// The kind of content stored in this texture.
    public var kind: AtlasTextureKind

    public init(index: UInt32, kind: AtlasTextureKind) {
        self.index = index
        self.kind = kind
    }
}

/// A descriptor for a subregion tile within a texture atlas.
@frozen
public struct AtlasTile: Sendable, Equatable, Hashable {
    /// The texture this tile belongs to.
    public var textureId: AtlasTextureId
    /// The unique ID of this tile within its texture.
    public var tileId: TileId
    /// Padding around the tile content in pixels.
    public var padding: UInt32
    /// The bounds of this tile within the texture.
    public var bounds: Bounds<DevicePixels>

    public init(
        textureId: AtlasTextureId,
        tileId: TileId,
        padding: UInt32 = 0,
        bounds: Bounds<DevicePixels>
    ) {
        self.textureId = textureId
        self.tileId = tileId
        self.padding = padding
        self.bounds = bounds
    }
}

// MARK: - Image and SVG Params


/// Parameters for rendering an SVG to the atlas.
public struct RenderSvgParams: Sendable, Equatable, Hashable {
    public var path: SharedString
    public var size: Size<DevicePixels>

    public init(path: SharedString, size: Size<DevicePixels>) {
        self.path = path
        self.size = size
    }
}

/// Key identifying an entry in the platform sprite atlas.
public enum AtlasKey: Sendable, Equatable, Hashable {
    case glyph(RenderGlyphParams)
    case svg(RenderSvgParams)
    case image(RenderImageParams)

    /// Returns the texture kind for this atlas key.
    public func textureKind() -> AtlasTextureKind {
        switch self {
        case .glyph(let params):
            if params.isEmoji {
                return .polychrome
            } else if params.subpixelRendering {
                return .subpixel
            } else {
                return .monochrome
            }
        case .svg:
            return .monochrome
        case .image:
            return .polychrome
        }
    }
}

// MARK: - Platform Atlas

/// Platform abstraction for a sprite atlas texture manager.
public protocol PlatformAtlas: AnyObject, Sendable {
    func getOrInsertWith(
        key: AtlasKey,
        build: () throws -> (Size<DevicePixels>, Data)?
    ) throws -> AtlasTile?

    func remove(key: AtlasKey)
}

/// List of textures in an atlas with free slot reuse.
public struct AtlasTextureList<T>: Sendable where T: Sendable {
    public var textures: [T?]
    public var freeList: [Int]

    public init(textures: [T?] = [], freeList: [Int] = []) {
        self.textures = textures
        self.freeList = freeList
    }

    public static func `default`() -> AtlasTextureList<T> {
        AtlasTextureList<T>()
    }

    public subscript(index: Int) -> T? {
        get { textures[index] }
        set { textures[index] = newValue }
    }
}

// MARK: - Frame Options

/// Options requested when asking the platform for a new frame.
public struct RequestFrameOptions: Sendable, Equatable, DefaultInitializable {
    public var requirePresentation: Bool
    public var forceRender: Bool

    public init() {
        self.requirePresentation = false
        self.forceRender = false
    }

    public init(requirePresentation: Bool = false, forceRender: Bool = false) {
        self.requirePresentation = requirePresentation
        self.forceRender = forceRender
    }
}

// MARK: - Gamma Correction

/// Compute gamma correction ratios for subpixel text rendering.
public func getGammaCorrectionRatios(_ gamma: Float) -> [Float] {
    let gammaIncorrectTargetRatios: [[Float]] = [
        [0.0000 / 4.0, 0.0000 / 4.0, 0.0000 / 4.0, 0.0000 / 4.0], // gamma = 1.0
        [0.0166 / 4.0, -0.0807 / 4.0, 0.2227 / 4.0, -0.0751 / 4.0], // gamma = 1.1
        [0.0350 / 4.0, -0.1760 / 4.0, 0.4325 / 4.0, -0.1370 / 4.0], // gamma = 1.2
        [0.0543 / 4.0, -0.2821 / 4.0, 0.6302 / 4.0, -0.1876 / 4.0], // gamma = 1.3
        [0.0739 / 4.0, -0.3963 / 4.0, 0.8167 / 4.0, -0.2287 / 4.0], // gamma = 1.4
        [0.0933 / 4.0, -0.5161 / 4.0, 0.9926 / 4.0, -0.2616 / 4.0], // gamma = 1.5
        [0.1121 / 4.0, -0.6395 / 4.0, 1.1588 / 4.0, -0.2877 / 4.0], // gamma = 1.6
        [0.1300 / 4.0, -0.7649 / 4.0, 1.3159 / 4.0, -0.3080 / 4.0], // gamma = 1.7
        [0.1469 / 4.0, -0.8911 / 4.0, 1.4644 / 4.0, -0.3234 / 4.0], // gamma = 1.8
        [0.1627 / 4.0, -1.0170 / 4.0, 1.6051 / 4.0, -0.3347 / 4.0], // gamma = 1.9
        [0.1773 / 4.0, -1.1420 / 4.0, 1.7385 / 4.0, -0.3426 / 4.0], // gamma = 2.0
        [0.1908 / 4.0, -1.2652 / 4.0, 1.8650 / 4.0, -0.3476 / 4.0], // gamma = 2.1
        [0.2031 / 4.0, -1.3864 / 4.0, 1.9851 / 4.0, -0.3501 / 4.0], // gamma = 2.2
    ]

    let norm13 = Float(Double(0x10000) / (255.0 * 255.0) * 4.0)
    let norm24 = Float(Double(0x100) / 255.0 * 4.0)

    let rawIdx = Int((gamma * 10.0).rounded())
    let clampedIdx = min(max(rawIdx, 10), 22) - 10
    let ratios = gammaIncorrectTargetRatios[clampedIdx]

    return [
        ratios[0] * norm13,
        ratios[1] * norm24,
        ratios[2] * norm13,
        ratios[3] * norm24,
    ]
}

// MARK: - Platform Dispatcher

/// Platform-level task dispatcher interface.
public protocol PlatformDispatcher: Sendable {
    func isMainThread() -> Bool
    func dispatch(_ runnable: @escaping @Sendable () -> Void, priority: Priority)
    func dispatchOnMainThread(_ runnable: @escaping @Sendable () -> Void, priority: Priority)
    func dispatchAfter(duration: TimeInterval, _ runnable: @escaping @Sendable () -> Void)
    func spawnRealtime(_ f: @escaping @Sendable () -> Void)
    func now() -> Date
}

// MARK: - Platform Text System

/// Platform abstraction for system font enumeration, glyph rasterization, and line layout.
public protocol PlatformTextSystem: Sendable {
    func addFonts(_ fonts: [Data]) throws
    func allFontNames() -> [String]
    func fontId(descriptor: Font) throws -> FontId
    func fontMetrics(fontId: FontId) -> FontMetrics
    func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float>
    func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float>
    func glyphForChar(fontId: FontId, ch: Character) -> GlyphId?
    func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels>
    func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data)
    func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout
    func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode
}

// MARK: - Headless Renderer

/// A renderer for headless test windows that can produce raster output.
public protocol PlatformHeadlessRenderer: AnyObject, Sendable {
    func renderSceneToImage(scene: Scene, size: Size<DevicePixels>) throws -> Data
    func spriteAtlas() -> any PlatformAtlas
}

// MARK: - Noop Text System

/// A deterministic, mock text system for testing that does not depend on host fonts or APIs.
public struct NoopTextSystem: PlatformTextSystem, Sendable {
    public init() {}

    public static func new() -> NoopTextSystem {
        NoopTextSystem()
    }

    public func addFonts(_ fonts: [Data]) throws {}

    public func allFontNames() -> [String] {
        []
    }

    public func fontId(descriptor: Font) throws -> FontId {
        FontId(1)
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        FontMetrics(
            unitsPerEm: 1000,
            ascent: 1025.0,
            descent: -275.0,
            lineGap: 0.0,
            underlinePosition: -95.0,
            underlineThickness: 60.0,
            capHeight: 698.0,
            xHeight: 516.0,
            boundingBox: Bounds(
                origin: Point(x: -260.0, y: -245.0),
                size: Size(width: 1501.0, height: 1364.0)
            )
        )
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        Bounds(
            origin: Point(x: 54.0, y: 0.0),
            size: Size(width: 392.0, height: 528.0)
        )
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        Size(width: 600.0 * Float(glyphId.value), height: 0.0)
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        GlyphId(UInt32(ch.utf16.count))
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        Bounds.zero
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        (rasterBounds.size, Data())
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        var position = px(0.0)
        let metrics = fontMetrics(fontId: FontId(0))
        let glyphM = glyphForChar(fontId: FontId(0), ch: "m") ?? GlyphId(1)
        let advanceM = (try? advance(fontId: FontId(0), glyphId: glyphM)) ?? Size(width: 600.0, height: 0.0)
        let emWidth = fontSize * (advanceM.width / Float(metrics.unitsPerEm))

        var glyphs: [ShapedGlyph] = []
        var byteIndex = 0

        for ch in text {
            let chBytes = ch.utf8.count
            if let glyph = glyphForChar(fontId: FontId(0), ch: ch) {
                let isEmoji = glyph.value == 2
                glyphs.append(ShapedGlyph(
                    id: glyph,
                    position: Point(x: position, y: px(0.0)),
                    index: byteIndex,
                    isEmoji: isEmoji
                ))
                if isEmoji {
                    position = position + (emWidth * 2.0)
                } else {
                    position = position + emWidth
                }
            } else {
                position = position + emWidth
            }
            byteIndex += chBytes
        }

        var shapedRuns: [ShapedRun] = []
        if !glyphs.isEmpty {
            shapedRuns.append(ShapedRun(fontId: FontId(0), glyphs: glyphs))
        } else {
            position = px(0.0)
        }

        let ascent = fontSize * (metrics.ascent / Float(metrics.unitsPerEm))
        let descent = fontSize * (metrics.descent / Float(metrics.unitsPerEm))

        return LineLayout(
            fontSize: fontSize,
            width: position,
            ascent: ascent,
            descent: descent,
            runs: shapedRuns,
            len: text.utf8.count
        )
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        .grayscale
    }
}
