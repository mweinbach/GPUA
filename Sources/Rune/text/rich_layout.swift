// Ported from: crates/rune/src/text/rich_layout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rich text layout options, shaped paragraph / broken line representation (`TextLayout`),
//! and `TextSystem`'s `layoutRich*` / `layoutAligned*` / `layoutBlocks*` entry points.

#if canImport(CoreText) && canImport(CoreGraphics)
import CoreText
import CoreGraphics
#endif

/// Options controlling line breaking and alignment of rich text layouts.
public struct RichLayoutOptions: Sendable, Equatable {
    public var wrapAnywhere: Bool
    public var alignment: TextAlignment

    public init(wrapAnywhere: Bool = false, alignment: TextAlignment = .start) {
        self.wrapAnywhere = wrapAnywhere
        self.alignment = alignment
    }

    public static func new() -> RichLayoutOptions {
        RichLayoutOptions()
    }

    public func wrapAnywhere(_ enabled: Bool = true) -> RichLayoutOptions {
        var copy = self
        copy.wrapAnywhere = enabled
        return copy
    }

    public func align(_ alignment: TextAlignment) -> RichLayoutOptions {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    public func align(_ alignment: Align) -> RichLayoutOptions {
        var copy = self
        copy.alignment = TextAlignment(alignment)
        return copy
    }
}

// MARK: - Font Metrics & Shaped Primitives

public struct LayoutFontMetrics: Sendable, Equatable {
    public var ascent: Float
    public var descent: Float
    public var leading: Float
    public var capHeight: Float?
    public var xHeight: Float?
    public var strikethroughOffset: Float
    public var strikethroughSize: Float
    public var underlineOffset: Float
    public var underlineSize: Float

    public init(
        ascent: Float,
        descent: Float,
        leading: Float = 0,
        capHeight: Float? = nil,
        xHeight: Float? = nil,
        strikethroughOffset: Float = 0,
        strikethroughSize: Float = 1,
        underlineOffset: Float = -2,
        underlineSize: Float = 1
    ) {
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
        self.capHeight = capHeight
        self.xHeight = xHeight
        self.strikethroughOffset = strikethroughOffset
        self.strikethroughSize = strikethroughSize
        self.underlineOffset = underlineOffset
        self.underlineSize = underlineSize
    }
}

// PORT NOTE: Immutable font face handle carried on each `ShapedRun`. On Apple platforms `ctFont`
// holds an immutable `CTFont` reference; on all platforms `sfnt` or `builtin` backs pure-Swift
// outline extraction and metrics.
public final class ShapedFontFace: @unchecked Sendable {
    public let fontId: UInt64
    public let index: UInt32
    public let coordsHash: UInt64
    public let weight: Float
    public let isMono: Bool
    public let isColorEmoji: Bool
    /// Synthetic oblique tangent in 1/64ths (`14` ~= tan 12 deg); `0` for upright or native italic faces.
    public let skew: Int8
    /// Synthetic oblique angle in degrees (`12` when `skew != 0`, else `0`).
    public let skewDegrees: UInt8

    #if canImport(CoreText) && canImport(CoreGraphics)
    let ctFontPoint: CTFont?
    let ctFontUpem: CTFont?
    let cachedHintMetrics: HintMetrics?
    #endif
    let sfnt: SfntFont?
    let builtin: BuiltinFontKind?

    #if canImport(CoreText) && canImport(CoreGraphics)
    init(
        fontId: UInt64,
        index: UInt32,
        coordsHash: UInt64,
        weight: Float,
        isMono: Bool,
        isColorEmoji: Bool,
        skew: Int8,
        skewDegrees: UInt8,
        ctFontPoint: CTFont?,
        ctFontUpem: CTFont?,
        cachedHintMetrics: HintMetrics?,
        sfnt: SfntFont?,
        builtin: BuiltinFontKind?
    ) {
        self.fontId = fontId
        self.index = index
        self.coordsHash = coordsHash
        self.weight = weight
        self.isMono = isMono
        self.isColorEmoji = isColorEmoji
        self.skew = skew
        self.skewDegrees = skewDegrees
        self.ctFontPoint = ctFontPoint
        self.ctFontUpem = ctFontUpem
        self.cachedHintMetrics = cachedHintMetrics
        self.sfnt = sfnt
        self.builtin = builtin
    }
    #else
    init(
        fontId: UInt64,
        index: UInt32,
        coordsHash: UInt64,
        weight: Float,
        isMono: Bool,
        isColorEmoji: Bool,
        skew: Int8,
        skewDegrees: UInt8,
        sfnt: SfntFont?,
        builtin: BuiltinFontKind?
    ) {
        self.fontId = fontId
        self.index = index
        self.coordsHash = coordsHash
        self.weight = weight
        self.isMono = isMono
        self.isColorEmoji = isColorEmoji
        self.skew = skew
        self.skewDegrees = skewDegrees
        self.sfnt = sfnt
        self.builtin = builtin
    }
    #endif
}

public struct LayoutInlineBox: Sendable, Equatable {
    public var id: UInt64
    public var index: Int
    public var width: Float
    public var height: Float

    public init(id: UInt64, index: Int, width: Float, height: Float) {
        self.id = id
        self.index = index
        self.width = width
        self.height = height
    }
}

public struct PositionedInlineBox: Sendable, Equatable {
    public var id: UInt64
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(id: UInt64, x: Float, y: Float, width: Float, height: Float) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct LayoutGlyph: Sendable, Equatable {
    public var id: UInt16
    public var x: Float
    public var y: Float
    public var advance: Float
    public var textByteOffset: UInt32

    public init(id: UInt16, x: Float = 0, y: Float = 0, advance: Float, textByteOffset: UInt32) {
        self.id = id
        self.x = x
        self.y = y
        self.advance = advance
        self.textByteOffset = textByteOffset
    }
}

public struct PositionedGlyph: Sendable, Equatable {
    public var id: UInt16
    public var x: Float
    public var y: Float

    public init(id: UInt16, x: Float, y: Float) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct LayoutCluster: Sendable, Equatable {
    public var textRange: Range<Int>
    public var advance: Float
    public var isHangingWhitespace: Bool
    public var isWordSpace: Bool
    public var isTab: Bool
    public var isSoftBreakAfter: Bool
    public var isHardBreak: Bool
    public var isRtl: Bool
    public var glyphRange: Range<Int>
}

public struct PositionedCluster: Sendable, Equatable {
    public var textRange: Range<Int>
    public var advance: Float
    public var visualOffset: Float
    public var isRtl: Bool
    public var isHardLineBreak: Bool

    public func textRangeValue() -> Range<Int> { textRange }
}

public struct ShapedRun: Sendable {
    public var font: ShapedFontFace
    public var fontSize: Float
    public var lineHeightPx: Float
    public var fontMetrics: LayoutFontMetrics
    public var ink: Ink
    public var textRange: Range<Int>
    public var isRtl: Bool
    public var isMono: Bool
    public var monoSpaceAdvance: Float
    public var clusters: [LayoutCluster]
    public var glyphs: [LayoutGlyph]
}

public struct PositionedGlyphRun: Sendable {
    public var font: ShapedFontFace
    public var fontSize: Float
    public var fontMetrics: LayoutFontMetrics
    public var ink: Ink
    public var textRange: Range<Int>
    public var isRtl: Bool
    public var offsetVal: Float
    public var baselineVal: Float
    public var advanceVal: Float
    public var glyphsVal: [LayoutGlyph]
    public var clustersVal: [PositionedCluster]

    public func offset() -> Float { offsetVal }
    public func baseline() -> Float { baselineVal }
    public func advance() -> Float { advanceVal }
    public func glyphs() -> [LayoutGlyph] { glyphsVal }
    public func visualClusters() -> [PositionedCluster] { clustersVal }

    public func positionedGlyphs() -> [PositionedGlyph] {
        var out: [PositionedGlyph] = []
        out.reserveCapacity(glyphsVal.count)
        var pen = offsetVal
        for g in glyphsVal {
            out.append(PositionedGlyph(id: g.id, x: pen + g.x, y: baselineVal + g.y))
            pen += g.advance
        }
        return out
    }
}

public enum PositionedLayoutItem: Sendable {
    case glyphRun(PositionedGlyphRun)
    case inlineBox(PositionedInlineBox)
}

public enum LineBreakReason: Sendable, Equatable {
    case none
    case regular
    case explicit
    case emergency
}

public struct LayoutLineMetrics: Sendable, Equatable {
    public var ascent: Float
    public var descent: Float
    public var leading: Float
    public var lineHeight: Float
    public var baseline: Float
    public var offset: Float
    public var advance: Float
    public var hangingAdvance: Float
    public var inlineMinCoord: Float
    public var blockMinCoord: Float
    public var blockMaxCoord: Float
    public var contentBlockMinCoord: Float
    public var contentBlockMaxCoord: Float
}

public struct LayoutLine: Sendable {
    public var textRangeVal: Range<Int>
    public var metricsVal: LayoutLineMetrics
    public var breakReasonVal: LineBreakReason
    public var itemsVal: [PositionedLayoutItem]

    public func textRange() -> Range<Int> { textRangeVal }
    public func metrics() -> LayoutLineMetrics { metricsVal }
    public func breakReason() -> LineBreakReason { breakReasonVal }
    public func items() -> [PositionedLayoutItem] { itemsVal }

    public func runs() -> [PositionedGlyphRun] {
        var out: [PositionedGlyphRun] = []
        for item in itemsVal {
            if case .glyphRun(let gr) = item {
                out.append(gr)
            }
        }
        return out
    }
}

/// A shaped and line-broken paragraph (`Layout<Ink>` in upstream).
// PORT NOTE: Reference type matching upstream `Rc<Layout<Ink>>` so identity (`===`) and `Weak`
// references in `GlyphCache` behave identically to `Rc::ptr_eq` / `Weak::upgrade`, and `cloneShaped()`
// shares the immutable `runs` & `inlineBoxesData` arrays via Swift copy-on-write during re-wrapping.
public final class TextLayout: @unchecked Sendable {
    public let text: String
    public let byteLen: Int
    public let scale: Float
    public let baseStyle: TextStyle
    public let isRtl: Bool
    let shapedRuns: [ShapedRun]
    let inlineBoxesData: [LayoutInlineBox]
    let pillRanges: [(Int, Int)]

    var linesData: [LayoutLine] = []
    var widthVal: Float = 0.0
    var fullWidthVal: Float = 0.0
    var heightVal: Float = 0.0

    init(
        text: String,
        scale: Float,
        baseStyle: TextStyle,
        isRtl: Bool,
        shapedRuns: [ShapedRun],
        inlineBoxesData: [LayoutInlineBox],
        pillRanges: [(Int, Int)]
    ) {
        self.text = text
        self.byteLen = text.utf8.count
        self.scale = scale
        self.baseStyle = baseStyle
        self.isRtl = isRtl
        self.shapedRuns = shapedRuns
        self.inlineBoxesData = inlineBoxesData
        self.pillRanges = pillRanges
    }

    func cloneShaped() -> TextLayout {
        TextLayout(
            text: text,
            scale: scale,
            baseStyle: baseStyle,
            isRtl: isRtl,
            shapedRuns: shapedRuns,
            inlineBoxesData: inlineBoxesData,
            pillRanges: pillRanges
        )
    }

    func cloneLayout() -> TextLayout {
        let copy = cloneShaped()
        copy.linesData = linesData
        copy.widthVal = widthVal
        copy.fullWidthVal = fullWidthVal
        copy.heightVal = heightVal
        return copy
    }

    public func len() -> Int { linesData.count }
    public var isEmpty: Bool { linesData.isEmpty }
    public func get(_ index: Int) -> LayoutLine? {
        guard index >= 0 && index < linesData.count else { return nil }
        return linesData[index]
    }
    public func lines() -> [LayoutLine] { linesData }
    public func inlineBoxes() -> [LayoutInlineBox] { inlineBoxesData }
    public func width() -> Float { widthVal }
    public func fullWidth() -> Float { fullWidthVal }
    public func height() -> Float { heightVal }
}

// MARK: - TextSystem Rich Layout API

extension TextSystem {
    public func layoutRich(
        _ text: String,
        _ spans: [Span],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: [],
            pills: [],
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: .start,
            wrapAnywhere: false,
            retain: true
        )
    }

    public func layoutRichWith(
        _ text: String,
        _ spans: [Span],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?,
        _ options: RichLayoutOptions
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: [],
            pills: [],
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: options.alignment,
            wrapAnywhere: options.wrapAnywhere,
            retain: true
        )
    }

    public func layoutAligned(
        _ text: String,
        _ spans: [Span],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?,
        _ align: TextAlignment
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: [],
            pills: [],
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: false,
            retain: true
        )
    }

    public func layoutAlignedWith(
        _ text: String,
        _ spans: [Span],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?,
        _ align: TextAlignment,
        _ options: RichLayoutOptions
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: [],
            pills: [],
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: options.wrapAnywhere,
            retain: true
        )
    }

    func layoutBlocks(
        _ text: String,
        _ spans: [Span],
        _ blocks: [Block],
        _ pills: [PillChip],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?,
        _ align: TextAlignment
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: blocks,
            pills: pills,
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: false,
            retain: true
        )
    }

    func layoutBlocksWith(
        _ text: String,
        _ spans: [Span],
        _ blocks: [Block],
        _ pills: [PillChip],
        _ style: TextStyle,
        _ scale: Float,
        _ maxWidth: Float?,
        _ align: TextAlignment,
        _ options: RichLayoutOptions
    ) -> TextLayout {
        layoutBlocksInner(
            text: text,
            spans: spans,
            blocks: blocks,
            pills: pills,
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: options.wrapAnywhere,
            retain: true
        )
    }
}
