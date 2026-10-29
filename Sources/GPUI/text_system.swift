// Ported from: crates/gpui/src/text_system.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

/// An opaque identifier for a specific font.
public struct FontId: Sendable, Equatable, Hashable, Codable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

/// An opaque identifier for a specific font family.
public struct FontFamilyId: Sendable, Equatable, Hashable, Codable {
    public var value: Int

    public init(_ value: Int) {
        self.value = value
    }
}

/// Number of subpixel glyph variants along the X axis.
public let subpixelVariantsX: UInt8 = 4

/// Number of subpixel glyph variants along the Y axis.
#if os(Windows) || os(Linux)
public let subpixelVariantsY: UInt8 = 1
#else
public let subpixelVariantsY: UInt8 = subpixelVariantsX
#endif

/// Font weight values ranging from 100 (thin) to 900 (black).
public struct FontWeight: Sendable, Equatable, Hashable, Comparable, Codable, ExpressibleByFloatLiteral, DefaultInitializable {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public init(floatLiteral value: Float) {
        self.value = value
    }

    public init() {
        self.value = 400.0
    }

    public static let thin = FontWeight(100.0)
    public static let extraLight = FontWeight(200.0)
    public static let light = FontWeight(300.0)
    public static let normal = FontWeight(400.0)
    public static let medium = FontWeight(500.0)
    public static let semibold = FontWeight(600.0)
    public static let bold = FontWeight(700.0)
    public static let extraBold = FontWeight(800.0)
    public static let black = FontWeight(900.0)

    public static let all: [FontWeight] = [
        .thin, .extraLight, .light, .normal, .medium, .semibold, .bold, .extraBold, .black
    ]

    public static func < (lhs: FontWeight, rhs: FontWeight) -> Bool {
        lhs.value < rhs.value
    }
}

/// Allows italic or oblique faces to be selected.
public enum FontStyle: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// A face that is neither italic nor obliqued.
    case normal
    /// A form that is cursive in nature.
    case italic
    /// A typically-sloped version of the regular face.
    case oblique

    public init() {
        self = .normal
    }
}

/// Configuration details identifying a specific font.
public struct Font: Sendable, Equatable, Hashable {
    /// The font family name. The special name ".SystemUIFont" identifies the system UI font.
    public var family: SharedString
    /// The font features to use.
    public var features: FontFeatures
    /// The fallback fonts to use.
    public var fallbacks: FontFallbacks?
    /// The font weight.
    public var weight: FontWeight
    /// The font style.
    public var style: FontStyle

    public init(
        family: SharedString = ".SystemUIFont",
        features: FontFeatures = FontFeatures(),
        fallbacks: FontFallbacks? = nil,
        weight: FontWeight = .normal,
        style: FontStyle = .normal
    ) {
        self.family = family
        self.features = features
        self.fallbacks = fallbacks
        self.weight = weight
        self.style = style
    }

    /// Set this Font to be bold.
    public func bold() -> Font {
        var copy = self
        copy.weight = .bold
        return copy
    }

    /// Set this Font to be italic.
    public func italic() -> Font {
        var copy = self
        copy.style = .italic
        return copy
    }
}

/// Helper to construct a Font with the given family name.
public func font(_ family: SharedString) -> Font {
    Font(family: family)
}

/// A styled run of text.
public struct TextRun: Sendable, Equatable {
    public var len: Int
    public var font: Font
    public var color: Hsla
    public var backgroundColor: Hsla?
    public var underline: UnderlineStyle?
    public var strikethrough: StrikethroughStyle?

    public init(
        len: Int = 0,
        font: Font = Font(),
        color: Hsla = black(),
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil
    ) {
        self.len = len
        self.font = font
        self.color = color
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
    }
}

/// An identifier for a specific glyph, as returned by the text system.
public struct GlyphId: Sendable, Equatable, Hashable, Codable {
    public var value: UInt32

    public init(_ value: UInt32) {
        self.value = value
    }
}

/// Parameters for rasterizing or sizing a glyph.
public struct RenderGlyphParams: Sendable, Equatable, Hashable {
    public var fontId: FontId
    public var glyphId: GlyphId
    public var fontSize: Pixels
    public var subpixelVariant: Point<UInt8>
    public var scaleFactor: Float
    public var isEmoji: Bool
    public var subpixelRendering: Bool

    public init(
        fontId: FontId,
        glyphId: GlyphId,
        fontSize: Pixels,
        subpixelVariant: Point<UInt8> = Point(x: 0, y: 0),
        scaleFactor: Float = 1.0,
        isEmoji: Bool = false,
        subpixelRendering: Bool = false
    ) {
        self.fontId = fontId
        self.glyphId = glyphId
        self.fontSize = fontSize
        self.subpixelVariant = subpixelVariant
        self.scaleFactor = scaleFactor
        self.isEmoji = isEmoji
        self.subpixelRendering = subpixelRendering
    }
}

/// A struct for storing font metrics.
public struct FontMetrics: Sendable, Equatable {
    public var unitsPerEm: UInt32
    public var ascent: Float
    public var descent: Float
    public var lineGap: Float
    public var underlinePosition: Float
    public var underlineThickness: Float
    public var capHeight: Float
    public var xHeight: Float
    public var boundingBox: Bounds<Float>

    public init(
        unitsPerEm: UInt32 = 1000,
        ascent: Float = 1025.0,
        descent: Float = -275.0,
        lineGap: Float = 0.0,
        underlinePosition: Float = -95.0,
        underlineThickness: Float = 60.0,
        capHeight: Float = 698.0,
        xHeight: Float = 516.0,
        boundingBox: Bounds<Float> = Bounds(origin: Point(x: -260.0, y: -245.0), size: Size(width: 1501.0, height: 1364.0))
    ) {
        self.unitsPerEm = unitsPerEm
        self.ascent = ascent
        self.descent = descent
        self.lineGap = lineGap
        self.underlinePosition = underlinePosition
        self.underlineThickness = underlineThickness
        self.capHeight = capHeight
        self.xHeight = xHeight
        self.boundingBox = boundingBox
    }

    public func ascent(fontSize: Pixels) -> Pixels {
        Pixels((ascent / Float(unitsPerEm)) * fontSize.value)
    }

    public func descent(fontSize: Pixels) -> Pixels {
        Pixels((descent / Float(unitsPerEm)) * fontSize.value)
    }

    public func lineGap(fontSize: Pixels) -> Pixels {
        Pixels((lineGap / Float(unitsPerEm)) * fontSize.value)
    }

    public func underlinePosition(fontSize: Pixels) -> Pixels {
        Pixels((underlinePosition / Float(unitsPerEm)) * fontSize.value)
    }

    public func underlineThickness(fontSize: Pixels) -> Pixels {
        Pixels((underlineThickness / Float(unitsPerEm)) * fontSize.value)
    }

    public func capHeight(fontSize: Pixels) -> Pixels {
        Pixels((capHeight / Float(unitsPerEm)) * fontSize.value)
    }

    public func xHeight(fontSize: Pixels) -> Pixels {
        Pixels((xHeight / Float(unitsPerEm)) * fontSize.value)
    }

    public func boundingBox(fontSize: Pixels) -> Bounds<Pixels> {
        let scale = fontSize.value / Float(unitsPerEm)
        return Bounds(
            origin: Point(x: px(boundingBox.origin.x * scale), y: px(boundingBox.origin.y * scale)),
            size: Size(width: px(boundingBox.size.width * scale), height: px(boundingBox.size.height * scale))
        )
    }
}

/// Maps well-known virtual font names to their concrete equivalents.
public func fontNameWithFallbacks(_ name: String, system: String) -> String {
    switch name {
    case ".SystemUIFont":
        return system
    case ".ZedSans", "Zed Plex Sans":
        return "IBM Plex Sans"
    case ".ZedMono", "Zed Plex Mono":
        return "Lilex"
    default:
        return name
    }
}

/// Like fontNameWithFallbacks but accepts and returns SharedString.
public func fontNameWithFallbacksShared(_ name: SharedString, system: SharedString) -> SharedString {
    let str = name.asString
    switch str {
    case ".SystemUIFont":
        return system
    case ".ZedSans", "Zed Plex Sans":
        return SharedString("IBM Plex Sans")
    case ".ZedMono", "Zed Plex Mono":
        return SharedString("Lilex")
    default:
        return name
    }
}

private struct FontIdWithSize: Hashable, Equatable {
    var fontId: FontId
    var fontSize: Pixels
}

// PORT NOTE: TextSystem uses internal NSLock to synchronize access to font caches, metrics, and wrapper pools.
public final class TextSystem: @unchecked Sendable {
    public let platformTextSystem: any PlatformTextSystem
    private let lock = NSLock()
    private var fontIdsByFont: [Font: FontId] = [:]
    private var fontMetricsCache: [FontId: FontMetrics] = [:]
    private var rasterBoundsCache: [RenderGlyphParams: Bounds<DevicePixels>] = [:]
    private var wrapperPool: [FontIdWithSize: [LineWrapper]] = [:]
    private var fontRunsPool: [[FontRun]] = []
    public var fallbackFontStack: [Font]

    public init(platformTextSystem: any PlatformTextSystem) {
        self.platformTextSystem = platformTextSystem
        self.fallbackFontStack = [
            font(".ZedMono"),
            font(".ZedSans"),
            font("Helvetica"),
            font("Segoe UI"),
            font("Ubuntu"),
            font("Adwaita Sans"),
            font("Cantarell"),
            font("Noto Sans"),
            font("DejaVu Sans"),
            font("Arial")
        ]
    }

    public static func new(platformTextSystem: any PlatformTextSystem) -> TextSystem {
        TextSystem(platformTextSystem: platformTextSystem)
    }

    public func allFontNames() -> [String] {
        var names = platformTextSystem.allFontNames()
        names.append(contentsOf: fallbackFontStack.map { $0.family.asString })
        names.append(".SystemUIFont")
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.sorted()
    }

    public func addFonts(_ fonts: [Data]) throws {
        try platformTextSystem.addFonts(fonts)
    }

    public func fontId(font: Font) throws -> FontId {
        lock.lock()
        if let existing = fontIdsByFont[font] {
            lock.unlock()
            return existing
        }
        lock.unlock()

        let id = try platformTextSystem.fontId(descriptor: font)
        lock.lock()
        fontIdsByFont[font] = id
        lock.unlock()
        return id
    }

    public func getFontForId(_ id: FontId) -> Font? {
        lock.lock()
        defer { lock.unlock() }
        for (f, fId) in fontIdsByFont where fId == id {
            return f
        }
        return nil
    }

    public func resolveFont(_ font: Font) -> FontId {
        if let id = try? fontId(font: font) {
            return id
        }
        for fallback in fallbackFontStack {
            if let id = try? fontId(font: fallback) {
                return id
            }
        }
        return FontId(1)
    }

    public func boundingBox(fontId: FontId, fontSize: Pixels) -> Bounds<Pixels> {
        let metrics = readMetrics(fontId)
        return metrics.boundingBox(fontSize: fontSize)
    }

    public func typographicBounds(fontId: FontId, fontSize: Pixels, character: Character) throws -> Bounds<Pixels> {
        guard let glyphId = platformTextSystem.glyphForChar(fontId: fontId, ch: character) else {
            throw NSError(domain: "TextSystem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Glyph not found for character \(character)"])
        }
        let bounds = try platformTextSystem.typographicBounds(fontId: fontId, glyphId: glyphId)
        let metrics = readMetrics(fontId)
        let scale = fontSize.value / Float(metrics.unitsPerEm)
        return Bounds(
            origin: Point(x: px(bounds.origin.x * scale), y: px(bounds.origin.y * scale)),
            size: Size(width: px(bounds.size.width * scale), height: px(bounds.size.height * scale))
        )
    }

    public func advance(fontId: FontId, fontSize: Pixels, ch: Character) throws -> Size<Pixels> {
        guard let glyphId = platformTextSystem.glyphForChar(fontId: fontId, ch: ch) else {
            throw NSError(domain: "TextSystem", code: 2, userInfo: [NSLocalizedDescriptionKey: "Glyph not found for character \(ch)"])
        }
        let adv = try platformTextSystem.advance(fontId: fontId, glyphId: glyphId)
        let unitsPerEm = Float(self.unitsPerEm(fontId: fontId))
        let width = (adv.width / unitsPerEm) * fontSize.value
        let height = (adv.height / unitsPerEm) * fontSize.value
        return Size(width: px(width), height: px(height))
    }

    public func emWidth(fontId: FontId, fontSize: Pixels) throws -> Pixels {
        try typographicBounds(fontId: fontId, fontSize: fontSize, character: "m").size.width
    }

    public func emAdvance(fontId: FontId, fontSize: Pixels) throws -> Pixels {
        try advance(fontId: fontId, fontSize: fontSize, ch: "m").width
    }

    public func layoutWidth(fontId: FontId, fontSize: Pixels, ch: Character) -> Pixels {
        let text = String(ch)
        let runs = [FontRun(len: text.utf8.count, fontId: fontId)]
        return platformTextSystem.layoutLine(text: text, fontSize: fontSize, runs: runs).width
    }

    public func emLayoutWidth(fontId: FontId, fontSize: Pixels) -> Pixels {
        layoutWidth(fontId: fontId, fontSize: fontSize, ch: "m")
    }

    public func chWidth(fontId: FontId, fontSize: Pixels) throws -> Pixels {
        try typographicBounds(fontId: fontId, fontSize: fontSize, character: "0").size.width
    }

    public func chAdvance(fontId: FontId, fontSize: Pixels) throws -> Pixels {
        try advance(fontId: fontId, fontSize: fontSize, ch: "0").width
    }

    public func unitsPerEm(fontId: FontId) -> UInt32 {
        readMetrics(fontId).unitsPerEm
    }

    public func capHeight(fontId: FontId, fontSize: Pixels) -> Pixels {
        readMetrics(fontId).capHeight(fontSize: fontSize)
    }

    public func xHeight(fontId: FontId, fontSize: Pixels) -> Pixels {
        readMetrics(fontId).xHeight(fontSize: fontSize)
    }

    public func ascent(fontId: FontId, fontSize: Pixels) -> Pixels {
        readMetrics(fontId).ascent(fontSize: fontSize)
    }

    public func descent(fontId: FontId, fontSize: Pixels) -> Pixels {
        readMetrics(fontId).descent(fontSize: fontSize)
    }

    public func baselineOffset(fontId: FontId, fontSize: Pixels, lineHeight: Pixels) -> Pixels {
        let asc = ascent(fontId: fontId, fontSize: fontSize)
        let desc = descent(fontId: fontId, fontSize: fontSize)
        let paddingTop = (lineHeight - asc - desc).half()
        return paddingTop + asc
    }

    public func lineWrapper(font: Font, fontSize: Pixels) -> LineWrapperHandle {
        let fId = resolveFont(font)
        let key = FontIdWithSize(fontId: fId, fontSize: fontSize)

        lock.lock()
        let wrapper: LineWrapper
        if var list = wrapperPool[key], !list.isEmpty {
            wrapper = list.removeLast()
            wrapperPool[key] = list
        } else {
            wrapper = LineWrapper.new(fontId: fId, fontSize: fontSize, textSystem: self)
        }
        lock.unlock()

        return LineWrapperHandle(wrapper: wrapper, textSystem: self)
    }

    public func returnLineWrapper(_ wrapper: LineWrapper) {
        let key = FontIdWithSize(fontId: wrapper.fontId, fontSize: wrapper.fontSize)
        lock.lock()
        wrapperPool[key, default: []].append(wrapper)
        lock.unlock()
    }

    public func rasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        lock.lock()
        if let cached = rasterBoundsCache[params] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let bounds = try platformTextSystem.glyphRasterBounds(params: params)
        lock.lock()
        rasterBoundsCache[params] = bounds
        lock.unlock()
        return bounds
    }

    public func rasterizeGlyph(params: RenderGlyphParams) throws -> (Size<DevicePixels>, [UInt8]) {
        let bounds = try rasterBounds(params: params)
        let (size, data) = try platformTextSystem.rasterizeGlyph(params: params, rasterBounds: bounds)
        return (size, [UInt8](data))
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        platformTextSystem.recommendedRenderingMode(fontId: fontId, fontSize: fontSize)
    }

    private func readMetrics(_ fontId: FontId) -> FontMetrics {
        lock.lock()
        if let cached = fontMetricsCache[fontId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let metrics = platformTextSystem.fontMetrics(fontId: fontId)
        lock.lock()
        fontMetricsCache[fontId] = metrics
        lock.unlock()
        return metrics
    }
}

/// A handle to a LineWrapper from the pool.
public final class LineWrapperHandle {
    public var wrapper: LineWrapper?
    public let textSystem: TextSystem

    public init(wrapper: LineWrapper, textSystem: TextSystem) {
        self.wrapper = wrapper
        self.textSystem = textSystem
    }

    deinit {
        if let w = wrapper {
            textSystem.returnLineWrapper(w)
        }
    }

    public func wrapLine(fragments: [LineFragment], wrapWidth: Pixels) -> [Boundary] {
        wrapper?.wrapLine(fragments: fragments, wrapWidth: wrapWidth) ?? []
    }

    public func truncateLine(
        line: SharedString,
        truncateWidth: Pixels,
        truncationAffix: String,
        runs: [TextRun],
        truncateFrom: TruncateFrom
    ) -> (SharedString, [TextRun]) {
        wrapper?.truncateLine(
            line: line,
            truncateWidth: truncateWidth,
            truncationAffix: truncationAffix,
            runs: runs,
            truncateFrom: truncateFrom
        ) ?? (line, runs)
    }
}

// PORT NOTE: WindowTextSystem wraps TextSystem and LineLayoutCache, both internally synchronized for concurrency safety.
public final class WindowTextSystem: @unchecked Sendable {
    public let lineLayoutCache: LineLayoutCache
    public let textSystem: TextSystem

    public init(textSystem: TextSystem) {
        self.lineLayoutCache = LineLayoutCache.new(platformTextSystem: textSystem.platformTextSystem)
        self.textSystem = textSystem
    }

    public static func new(textSystem: TextSystem) -> WindowTextSystem {
        WindowTextSystem(textSystem: textSystem)
    }

    public func layoutIndex() -> LineLayoutIndex {
        lineLayoutCache.layoutIndex()
    }

    public func reuseLayouts(_ range: Range<LineLayoutIndex>) {
        lineLayoutCache.reuseLayouts(range)
    }

    public func truncateLayouts(_ index: LineLayoutIndex) {
        lineLayoutCache.truncateLayouts(index)
    }

    // PORT NOTE: WindowTextSystem derefs to TextSystem in Rust (via #[deref] text_system: Arc<TextSystem>).
    public func rasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        try textSystem.rasterBounds(params: params)
    }

    public func rasterizeGlyph(params: RenderGlyphParams) throws -> (Size<DevicePixels>, [UInt8]) {
        try textSystem.rasterizeGlyph(params: params)
    }

    public func shapeLine(
        text: SharedString,
        fontSize: Pixels,
        runs: [TextRun],
        forceWidth: Pixels? = nil
    ) -> ShapedLine {
        let textStr = text.asString
        assert(!textStr.contains("\n"), "text argument should not contain newlines")

        var decorationRuns: [DecorationRun] = []
        for run in runs {
            if let last = decorationRuns.last,
               last.color == run.color &&
               last.underline == run.underline &&
               last.strikethrough == run.strikethrough &&
               last.backgroundColor == run.backgroundColor {
                decorationRuns[decorationRuns.count - 1].len += UInt32(run.len)
                continue
            }
            decorationRuns.append(DecorationRun(
                len: UInt32(run.len),
                color: run.color,
                backgroundColor: run.backgroundColor,
                underline: run.underline,
                strikethrough: run.strikethrough
            ))
        }

        let layout = layoutLine(text: textStr, fontSize: fontSize, runs: runs, forceWidth: forceWidth)
        return ShapedLine(layout: layout, text: text, decorationRuns: decorationRuns)
    }

    public func shapeText(
        text: SharedString,
        fontSize: Pixels,
        runs: [TextRun],
        wrapWidth: Pixels? = nil,
        lineClamp: Int? = nil
    ) throws -> [WrappedLine] {
        var activeRuns = runs.filter { $0.len > 0 }
        var resultLines: [WrappedLine] = []
        var wrappedLinesCount = 0

        let lines = text.asString.components(separatedBy: "\n")
        var runIndex = 0

        for lineText in lines {
            let sharedLine = SharedString(lineText)
            var lineBytesRemaining = lineText.utf8.count
            var decorationRuns: [DecorationRun] = []
            var fontRuns: [FontRun] = []

            while lineBytesRemaining > 0 && runIndex < activeRuns.count {
                let runLenWithinLine = min(lineBytesRemaining, activeRuns[runIndex].len)
                let run = activeRuns[runIndex]

                let decorationChanged: Bool
                if let last = decorationRuns.last,
                   last.color == run.color &&
                   last.underline == run.underline &&
                   last.strikethrough == run.strikethrough &&
                   last.backgroundColor == run.backgroundColor {
                    decorationRuns[decorationRuns.count - 1].len += UInt32(runLenWithinLine)
                    decorationChanged = false
                } else {
                    decorationRuns.append(DecorationRun(
                        len: UInt32(runLenWithinLine),
                        color: run.color,
                        backgroundColor: run.backgroundColor,
                        underline: run.underline,
                        strikethrough: run.strikethrough
                    ))
                    decorationChanged = true
                }

                let fId = textSystem.resolveFont(run.font)
                if let last = fontRuns.last, last.fontId == fId, !decorationChanged {
                    fontRuns[fontRuns.count - 1].len += runLenWithinLine
                } else {
                    fontRuns.append(FontRun(len: runLenWithinLine, fontId: fId))
                }

                activeRuns[runIndex].len -= runLenWithinLine
                if activeRuns[runIndex].len == 0 {
                    runIndex += 1
                }
                lineBytesRemaining -= runLenWithinLine
            }

            let maxWrap = lineClamp.map { max(0, $0 - wrappedLinesCount) }
            let layout = lineLayoutCache.layoutWrappedLine(
                text: lineText,
                fontSize: fontSize,
                runs: fontRuns,
                wrapWidth: wrapWidth,
                maxLines: maxWrap
            )
            wrappedLinesCount += layout.wrapBoundaries.count

            resultLines.append(WrappedLine(
                layout: layout,
                text: sharedLine,
                decorationRuns: decorationRuns
            ))
        }

        return resultLines
    }

    public func finishFrame() {
        lineLayoutCache.finishFrame()
    }

    public func layoutLine(
        text: String,
        fontSize: Pixels,
        runs: [TextRun],
        forceWidth: Pixels? = nil
    ) -> LineLayout {
        var lastRun: TextRun? = nil
        var fontRuns: [FontRun] = []

        for run in runs {
            let decorationChanged: Bool
            if let last = lastRun,
               last.color == run.color &&
               last.underline == run.underline &&
               last.strikethrough == run.strikethrough {
                decorationChanged = false
            } else {
                lastRun = run
                decorationChanged = true
            }

            let fId = textSystem.resolveFont(run.font)
            if let last = fontRuns.last, last.fontId == fId && !decorationChanged {
                fontRuns[fontRuns.count - 1].len += run.len
            } else {
                fontRuns.append(FontRun(len: run.len, fontId: fId))
            }
        }

        return lineLayoutCache.layoutLine(
            text: text,
            fontSize: fontSize,
            runs: fontRuns,
            forceWidth: forceWidth
        )
    }
}
