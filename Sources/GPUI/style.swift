// Ported from: crates/gpui/src/style.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

// MARK: - ObjectFit

/// How to fit an image into the bounds of an element.
public enum ObjectFit: Sendable, Equatable, Hashable, Codable {
    /// The image will be stretched to fill the bounds of the element.
    case fill
    /// The image will be scaled to fit within the bounds of the element.
    case contain
    /// The image will be scaled to cover the bounds of the element.
    case cover
    /// The image will be scaled down to fit within the bounds of the element.
    case scaleDown
    /// The image will maintain its original size.
    case none

    /// Get the bounds of the image within the given bounds according to this fitting policy.
    public func getBounds(
        bounds: Bounds<Pixels>,
        imageSize: Size<DevicePixels>
    ) -> Bounds<Pixels> {
        let imageSizePixels = imageSize.map { Pixels(Float($0.value)) }
        if imageSizePixels.width <= Pixels.zero || imageSizePixels.height <= Pixels.zero ||
           bounds.size.width <= Pixels.zero || bounds.size.height <= Pixels.zero {
            return Bounds(origin: bounds.origin, size: .zero)
        }

        let imageRatio = imageSizePixels.width / imageSizePixels.height
        let boundsRatio = bounds.size.width / bounds.size.height

        switch self {
        case .fill:
            return bounds

        case .contain:
            let newSize: Size<Pixels>
            if boundsRatio > imageRatio {
                newSize = size(
                    imageSizePixels.width * (bounds.size.height / imageSizePixels.height),
                    bounds.size.height
                )
            } else {
                newSize = size(
                    bounds.size.width,
                    imageSizePixels.height * (bounds.size.width / imageSizePixels.width)
                )
            }

            return Bounds(
                origin: point(
                    bounds.origin.x + (bounds.size.width - newSize.width) / 2.0,
                    bounds.origin.y + (bounds.size.height - newSize.height) / 2.0
                ),
                size: newSize
            )

        case .scaleDown:
            if imageSizePixels.width > bounds.size.width || imageSizePixels.height > bounds.size.height {
                let newSize: Size<Pixels>
                if boundsRatio > imageRatio {
                    newSize = size(
                        imageSizePixels.width * (bounds.size.height / imageSizePixels.height),
                        bounds.size.height
                    )
                } else {
                    newSize = size(
                        bounds.size.width,
                        imageSizePixels.height * (bounds.size.width / imageSizePixels.width)
                    )
                }

                return Bounds(
                    origin: point(
                        bounds.origin.x + (bounds.size.width - newSize.width) / 2.0,
                        bounds.origin.y + (bounds.size.height - newSize.height) / 2.0
                    ),
                    size: newSize
                )
            } else {
                let originalSize = imageSizePixels
                return Bounds(
                    origin: point(
                        bounds.origin.x + (bounds.size.width - originalSize.width) / 2.0,
                        bounds.origin.y + (bounds.size.height - originalSize.height) / 2.0
                    ),
                    size: originalSize
                )
            }

        case .cover:
            let newSize: Size<Pixels>
            if boundsRatio > imageRatio {
                newSize = size(
                    bounds.size.width,
                    imageSizePixels.height * (bounds.size.width / imageSizePixels.width)
                )
            } else {
                newSize = size(
                    imageSizePixels.width * (bounds.size.height / imageSizePixels.height),
                    bounds.size.height
                )
            }

            return Bounds(
                origin: point(
                    bounds.origin.x + (bounds.size.width - newSize.width) / 2.0,
                    bounds.origin.y + (bounds.size.height - newSize.height) / 2.0
                ),
                size: newSize
            )

        case .none:
            return Bounds(
                origin: bounds.origin,
                size: imageSizePixels
            )
        }
    }
}

// MARK: - Grid Template

/// The minimum size of a column or row in a grid layout.
public enum TemplateColumnMinSize: Sendable, Equatable, Hashable, Comparable, Codable, DefaultInitializable {
    /// The column size may be 0.
    case zero
    /// The column size can be determined by the min content.
    case minContent
    /// The column size can be determined by the max content.
    case maxContent

    public init() {
        self = .zero
    }
}

/// Refinement for `GridTemplate`.
public struct GridTemplateRefinement: Sendable, Equatable, Hashable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = GridTemplateRefinement

    public var repeatCount: UInt16?
    public var minSize: TemplateColumnMinSize?

    public var `repeat`: UInt16? {
        get { self.repeatCount }
        set { self.repeatCount = newValue }
    }

    public init(repeatCount: UInt16? = nil, minSize: TemplateColumnMinSize? = nil) {
        self.repeatCount = repeatCount
        self.minSize = minSize
    }

    public init(repeat: UInt16? = nil, minSize: TemplateColumnMinSize? = nil) {
        self.repeatCount = `repeat`
        self.minSize = minSize
    }

    public init() {
        self.repeatCount = nil
        self.minSize = nil
    }

    public var isEmpty: Bool {
        repeatCount == nil && minSize == nil
    }

    public mutating func refine(with refinement: GridTemplateRefinement) {
        if let r = refinement.repeatCount { self.repeatCount = r }
        if let m = refinement.minSize { self.minSize = m }
    }

    public func isSuperset(of refinement: GridTemplateRefinement) -> Bool {
        if let r = refinement.repeatCount, self.repeatCount != r { return false }
        if let m = refinement.minSize, self.minSize != m { return false }
        return true
    }

    public func subtract(_ refinement: GridTemplateRefinement) -> GridTemplateRefinement {
        GridTemplateRefinement(
            repeatCount: self.repeatCount == refinement.repeatCount ? nil : self.repeatCount,
            minSize: self.minSize == refinement.minSize ? nil : self.minSize
        )
    }
}

/// A simplified representation of the grid-template-* value.
public struct GridTemplate: Sendable, Equatable, Hashable, Comparable, Codable, DefaultInitializable, Refineable {
    public typealias Refinement = GridTemplateRefinement

    /// How this template directive should be repeated.
    public var `repeat`: UInt16
    /// The minimum size in the repeat(<>, minmax(_, 1fr)) equation.
    public var minSize: TemplateColumnMinSize

    public var repeatCount: UInt16 {
        get { self.repeat }
        set { self.repeat = newValue }
    }

    public init(repeat: UInt16 = 0, minSize: TemplateColumnMinSize = .zero) {
        self.repeat = `repeat`
        self.minSize = minSize
    }

    public init(repeatCount: UInt16 = 0, minSize: TemplateColumnMinSize = .zero) {
        self.repeat = repeatCount
        self.minSize = minSize
    }

    public init() {
        self.repeat = 0
        self.minSize = .zero
    }

    public static func < (lhs: GridTemplate, rhs: GridTemplate) -> Bool {
        if lhs.repeat != rhs.repeat {
            return lhs.repeat < rhs.repeat
        }
        return lhs.minSize < rhs.minSize
    }

    public mutating func refine(with refinement: GridTemplateRefinement) {
        if let r = refinement.repeatCount { self.repeat = r }
        if let m = refinement.minSize { self.minSize = m }
    }

    public func isSuperset(of refinement: GridTemplateRefinement) -> Bool {
        if let r = refinement.repeatCount, self.repeat != r { return false }
        if let m = refinement.minSize, self.minSize != m { return false }
        return true
    }

    public func subtract(_ refinement: GridTemplateRefinement) -> GridTemplateRefinement {
        GridTemplateRefinement(
            repeatCount: self.repeat == refinement.repeatCount ? nil : self.repeat,
            minSize: self.minSize == refinement.minSize ? nil : self.minSize
        )
    }
}

// MARK: - Layout Enums

/// Sets the layout used for the children of this node.
public enum Display: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// The children will follow the block layout algorithm.
    case block
    /// The children will follow the flexbox layout algorithm.
    case flex
    /// The children will follow the CSS Grid layout algorithm.
    case grid
    /// The children will not be laid out, and will follow absolute positioning.
    case none

    public init() {
        self = .block
    }
}

/// The value of the visibility property, similar to the CSS property `visibility`.
public enum Visibility: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// The element should be drawn as normal.
    case visible
    /// The element should not be drawn, but should still take up space in the layout.
    case hidden

    public init() {
        self = .visible
    }
}

/// Controls whether flex items are forced onto one line or can wrap onto multiple lines.
public enum FlexWrap: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// Items will not wrap and stay on a single line.
    case noWrap
    /// Items will wrap according to this item's `FlexDirection`.
    case wrap
    /// Items will wrap in the opposite direction to this item's `FlexDirection`.
    case wrapReverse

    public init() {
        self = .noWrap
    }
}

/// The direction of the flexbox layout main axis.
public enum FlexDirection: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// Defines +x as the main axis (left to right).
    case row
    /// Defines +y as the main axis (top to bottom).
    case column
    /// Defines -x as the main axis (right to left).
    case rowReverse
    /// Defines -y as the main axis (bottom to top).
    case columnReverse

    public init() {
        self = .row
    }
}

/// How children overflowing their container should affect layout.
public enum Overflow: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// Automatic minimum size is based on content; overflows contribute to scroll region.
    case visible
    /// Automatic minimum size is based on content; overflows do not contribute to scroll region.
    case clip
    /// Automatic minimum size is 0; overflows do not contribute to scroll region.
    case hidden
    /// Automatic minimum size is 0; space is reserved for a scrollbar.
    case scroll

    public init() {
        self = .visible
    }
}

/// The positioning strategy for this item.
public enum Position: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// The offset is computed relative to the final position given by layout.
    case relative
    /// The offset is computed relative to the closest positioned ancestor.
    case absolute

    public init() {
        self = .relative
    }
}

/// Controls how child nodes are aligned in the cross/block axis.
public enum AlignItems: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    case start
    case end
    case flexStart
    case flexEnd
    case center
    case baseline
    case stretch

    public init() {
        self = .start
    }
}

/// Used to control how child nodes are aligned.
public typealias JustifyItems = AlignItems
/// Used to control how the specified node is aligned.
public typealias AlignSelf = AlignItems
/// Overrides the parent Node's `JustifyItems` property.
public typealias JustifySelf = AlignItems

/// Sets the distribution of space between and around content items.
public enum AlignContent: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    case start
    case end
    case flexStart
    case flexEnd
    case center
    case stretch
    case spaceBetween
    case spaceEvenly
    case spaceAround

    public init() {
        self = .start
    }
}

/// Sets the distribution of space in the main axis.
public typealias JustifyContent = AlignContent

// MARK: - Text Formatting Enums

/// How to handle whitespace in text.
public enum WhiteSpace: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// Normal line wrapping when text overflows element width.
    case normal
    /// No line wrapping; text will overflow element width.
    case nowrap

    public init() {
        self = .normal
    }
}

/// How to truncate text that overflows the width of the element.
public enum TextOverflow: Sendable, Equatable, Hashable, Codable {
    /// Truncate text at the end, appending the provided string (e.g., "very long te…").
    case truncate(SharedString)
    /// Truncate text at the start, prepending the provided string (e.g., "…ong text here").
    case truncateStart(SharedString)
}

/// How to align text within the element.
public enum TextAlign: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    case left
    case center
    case right

    public init() {
        self = .left
    }
}

// MARK: - Visual & Decorative Types

/// The possible values of the box-shadow property.
public struct BoxShadow: Sendable, Equatable, Hashable {
    /// Shadow color.
    public var color: Hsla
    /// Offset from element origin.
    public var offset: Point<Pixels>
    /// Blur radius.
    public var blurRadius: Pixels
    /// Spread radius.
    public var spreadRadius: Pixels

    public init(
        color: Hsla = black(),
        offset: Point<Pixels> = Point(x: .zero, y: .zero),
        blurRadius: Pixels = .zero,
        spreadRadius: Pixels = .zero
    ) {
        self.color = color
        self.offset = offset
        self.blurRadius = blurRadius
        self.spreadRadius = spreadRadius
    }
}

/// Refinement for `UnderlineStyle`.
public struct UnderlineStyleRefinement: Sendable, Equatable, Hashable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = UnderlineStyleRefinement

    public var thickness: Pixels?
    public var color: Hsla?
    public var wavy: Bool?

    public init(thickness: Pixels? = nil, color: Hsla? = nil, wavy: Bool? = nil) {
        self.thickness = thickness
        self.color = color
        self.wavy = wavy
    }

    public init() {
        self.thickness = nil
        self.color = nil
        self.wavy = nil
    }

    public var isEmpty: Bool {
        thickness == nil && color == nil && wavy == nil
    }

    public mutating func refine(with refinement: UnderlineStyleRefinement) {
        if let t = refinement.thickness { self.thickness = t }
        if let c = refinement.color { self.color = c }
        if let w = refinement.wavy { self.wavy = w }
    }

    public func isSuperset(of refinement: UnderlineStyleRefinement) -> Bool {
        if let t = refinement.thickness, self.thickness != t { return false }
        if let c = refinement.color, self.color != c { return false }
        if let w = refinement.wavy, self.wavy != w { return false }
        return true
    }

    public func subtract(_ refinement: UnderlineStyleRefinement) -> UnderlineStyleRefinement {
        UnderlineStyleRefinement(
            thickness: self.thickness == refinement.thickness ? nil : self.thickness,
            color: self.color == refinement.color ? nil : self.color,
            wavy: self.wavy == refinement.wavy ? nil : self.wavy
        )
    }
}

/// Properties applied to an underline.
public struct UnderlineStyle: Sendable, Equatable, Hashable, DefaultInitializable, Refineable {
    public typealias Refinement = UnderlineStyleRefinement

    /// Underline thickness.
    public var thickness: Pixels
    /// Underline color.
    public var color: Hsla?
    /// Whether the underline is wavy (e.g. for spell checking).
    public var wavy: Bool

    public init(thickness: Pixels = .zero, color: Hsla? = nil, wavy: Bool = false) {
        self.thickness = thickness
        self.color = color
        self.wavy = wavy
    }

    public init() {
        self.thickness = .zero
        self.color = nil
        self.wavy = false
    }

    public mutating func refine(with refinement: UnderlineStyleRefinement) {
        if let t = refinement.thickness { self.thickness = t }
        if let c = refinement.color { self.color = c }
        if let w = refinement.wavy { self.wavy = w }
    }

    public func isSuperset(of refinement: UnderlineStyleRefinement) -> Bool {
        if let t = refinement.thickness, self.thickness != t { return false }
        if let c = refinement.color, self.color != c { return false }
        if let w = refinement.wavy, self.wavy != w { return false }
        return true
    }

    public func subtract(_ refinement: UnderlineStyleRefinement) -> UnderlineStyleRefinement {
        UnderlineStyleRefinement(
            thickness: self.thickness == refinement.thickness ? nil : self.thickness,
            color: self.color == refinement.color ? nil : self.color,
            wavy: self.wavy == refinement.wavy ? nil : self.wavy
        )
    }
}

/// Refinement for `StrikethroughStyle`.
public struct StrikethroughStyleRefinement: Sendable, Equatable, Hashable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = StrikethroughStyleRefinement

    public var thickness: Pixels?
    public var color: Hsla?

    public init(thickness: Pixels? = nil, color: Hsla? = nil) {
        self.thickness = thickness
        self.color = color
    }

    public init() {
        self.thickness = nil
        self.color = nil
    }

    public var isEmpty: Bool {
        thickness == nil && color == nil
    }

    public mutating func refine(with refinement: StrikethroughStyleRefinement) {
        if let t = refinement.thickness { self.thickness = t }
        if let c = refinement.color { self.color = c }
    }

    public func isSuperset(of refinement: StrikethroughStyleRefinement) -> Bool {
        if let t = refinement.thickness, self.thickness != t { return false }
        if let c = refinement.color, self.color != c { return false }
        return true
    }

    public func subtract(_ refinement: StrikethroughStyleRefinement) -> StrikethroughStyleRefinement {
        StrikethroughStyleRefinement(
            thickness: self.thickness == refinement.thickness ? nil : self.thickness,
            color: self.color == refinement.color ? nil : self.color
        )
    }
}

/// Properties applied to a strikethrough.
public struct StrikethroughStyle: Sendable, Equatable, Hashable, DefaultInitializable, Refineable {
    public typealias Refinement = StrikethroughStyleRefinement

    /// Strikethrough thickness.
    public var thickness: Pixels
    /// Strikethrough color.
    public var color: Hsla?

    public init(thickness: Pixels = .zero, color: Hsla? = nil) {
        self.thickness = thickness
        self.color = color
    }

    public init() {
        self.thickness = .zero
        self.color = nil
    }

    public mutating func refine(with refinement: StrikethroughStyleRefinement) {
        if let t = refinement.thickness { self.thickness = t }
        if let c = refinement.color { self.color = c }
    }

    public func isSuperset(of refinement: StrikethroughStyleRefinement) -> Bool {
        if let t = refinement.thickness, self.thickness != t { return false }
        if let c = refinement.color, self.color != c { return false }
        return true
    }

    public func subtract(_ refinement: StrikethroughStyleRefinement) -> StrikethroughStyleRefinement {
        StrikethroughStyleRefinement(
            thickness: self.thickness == refinement.thickness ? nil : self.thickness,
            color: self.color == refinement.color ? nil : self.color
        )
    }
}

/// The kinds of fill that can be applied to a shape.
public enum Fill: Sendable, Equatable, Hashable, DefaultInitializable {
    /// A background fill (solid, gradient, slash, checkerboard).
    case color(Background)

    public init() {
        self = .color(Background())
    }

    public init(_ color: Hsla) {
        self = .color(solidBackground(color))
    }

    public init(_ color: Rgba) {
        self = .color(solidBackground(Hsla(rgba: color)))
    }

    public init(_ background: Background) {
        self = .color(background)
    }

    /// Unwrap this fill into a Background, if it is one.
    public func color() -> Background? {
        switch self {
        case .color(let bg): return bg
        }
    }
}

// MARK: - HighlightStyle

/// A highlight style to apply, similar to a `TextStyle` except for uniformly sized and spaced text.
public struct HighlightStyle: Sendable, Equatable, Hashable, DefaultInitializable {
    public var color: Hsla?
    public var fontWeight: FontWeight?
    public var fontStyle: FontStyle?
    public var backgroundColor: Hsla?
    public var underline: UnderlineStyle?
    public var strikethrough: StrikethroughStyle?
    public var fadeOut: Float?

    public init(
        color: Hsla? = nil,
        fontWeight: FontWeight? = nil,
        fontStyle: FontStyle? = nil,
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil,
        fadeOut: Float? = nil
    ) {
        self.color = color
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
        self.fadeOut = fadeOut
    }

    public init() {
        self.color = nil
        self.fontWeight = nil
        self.fontStyle = nil
        self.backgroundColor = nil
        self.underline = nil
        self.strikethrough = nil
        self.fadeOut = nil
    }

    public static func color(_ color: Hsla) -> HighlightStyle {
        HighlightStyle(color: color)
    }

    public init(_ color: Hsla) {
        self.init(color: color)
    }

    public init(_ color: Rgba) {
        self.init(color: Hsla(rgba: color))
    }

    public init(_ weight: FontWeight) {
        self.init(fontWeight: weight)
    }

    public init(_ style: FontStyle) {
        self.init(fontStyle: style)
    }

    public init(_ textStyle: TextStyle) {
        self.init(
            color: textStyle.color,
            fontWeight: textStyle.fontWeight,
            fontStyle: textStyle.fontStyle,
            backgroundColor: textStyle.backgroundColor,
            underline: textStyle.underline,
            strikethrough: textStyle.strikethrough,
            fadeOut: nil
        )
    }

    /// Blend this highlight style with another.
    /// Non-continuous properties (like font_weight and font_style) are overwritten.
    public func highlight(_ other: HighlightStyle) -> HighlightStyle {
        var result = self

        if let otherColor = other.color {
            if let myColor = self.color {
                result.color = myColor.blend(with: otherColor)
            } else {
                result.color = otherColor
            }
        }

        if let fw = other.fontWeight {
            result.fontWeight = fw
        }
        if let fs = other.fontStyle {
            result.fontStyle = fs
        }
        if let bg = other.backgroundColor {
            result.backgroundColor = bg
        }
        if let u = other.underline {
            result.underline = u
        }
        if let s = other.strikethrough {
            result.strikethrough = s
        }

        if let sourceFade = other.fadeOut {
            if let destFade = self.fadeOut {
                result.fadeOut = Swift.max(0.0, Swift.min(1.0, destFade * (1.0 + sourceFade)))
            } else {
                result.fadeOut = sourceFade
            }
        }

        return result
    }
}

// MARK: - Combine Highlights

private struct HighlightEndpoint {
    let position: Int
    let highlightId: Int
    let isStart: Bool
}

/// Combine and merge highlights and ranges from two sequences of highlight intervals.
public func combineHighlights<S1: Sequence, S2: Sequence>(
    _ a: S1,
    _ b: S2
) -> [(Range<Int>, HighlightStyle)]
where S1.Element == (Range<Int>, HighlightStyle), S2.Element == (Range<Int>, HighlightStyle) {
    var endpoints = [HighlightEndpoint]()
    var highlights = [HighlightStyle]()

    for (range, highlight) in Array(a) + Array(b) {
        if !range.isEmpty {
            let highlightId = highlights.count
            endpoints.append(HighlightEndpoint(position: range.lowerBound, highlightId: highlightId, isStart: true))
            endpoints.append(HighlightEndpoint(position: range.upperBound, highlightId: highlightId, isStart: false))
            highlights.append(highlight)
        }
    }

    endpoints.sort { $0.position < $1.position }

    var result = [(Range<Int>, HighlightStyle)]()
    var activeStyles = Set<Int>()
    var ix = 0
    var endpointIndex = 0

    while endpointIndex < endpoints.count {
        let endpoint = endpoints[endpointIndex]
        let prevIndex = ix
        ix = endpoint.position

        if ix > prevIndex && !activeStyles.isEmpty {
            let currentStyle = activeStyles.sorted().reduce(HighlightStyle()) { acc, id in
                acc.highlight(highlights[id])
            }
            result.append((prevIndex..<ix, currentStyle))
        }

        if endpoint.isStart {
            activeStyles.insert(endpoint.highlightId)
        } else {
            activeStyles.remove(endpoint.highlightId)
        }
        endpointIndex += 1
    }

    return result
}

// MARK: - TextStyle & TextStyleRefinement

/// Partial style overrides for typography.
public struct TextStyleRefinement: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = TextStyleRefinement

    public var color: Hsla?
    public var fontFamily: SharedString?
    public var fontFeatures: FontFeatures?
    public var fontFallbacks: FontFallbacks?
    public var fontSize: AbsoluteLength?
    public var lineHeight: DefiniteLength?
    public var fontWeight: FontWeight?
    public var fontStyle: FontStyle?
    public var backgroundColor: Hsla?
    public var underline: UnderlineStyle?
    public var strikethrough: StrikethroughStyle?
    public var whiteSpace: WhiteSpace?
    public var textOverflow: TextOverflow?
    public var textAlign: TextAlign?
    public var lineClamp: Int?

    public init(
        color: Hsla? = nil,
        fontFamily: SharedString? = nil,
        fontFeatures: FontFeatures? = nil,
        fontFallbacks: FontFallbacks? = nil,
        fontSize: AbsoluteLength? = nil,
        lineHeight: DefiniteLength? = nil,
        fontWeight: FontWeight? = nil,
        fontStyle: FontStyle? = nil,
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil,
        whiteSpace: WhiteSpace? = nil,
        textOverflow: TextOverflow? = nil,
        textAlign: TextAlign? = nil,
        lineClamp: Int? = nil
    ) {
        self.color = color
        self.fontFamily = fontFamily
        self.fontFeatures = fontFeatures
        self.fontFallbacks = fontFallbacks
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
        self.whiteSpace = whiteSpace
        self.textOverflow = textOverflow
        self.textAlign = textAlign
        self.lineClamp = lineClamp
    }

    public init() {
        self.color = nil
        self.fontFamily = nil
        self.fontFeatures = nil
        self.fontFallbacks = nil
        self.fontSize = nil
        self.lineHeight = nil
        self.fontWeight = nil
        self.fontStyle = nil
        self.backgroundColor = nil
        self.underline = nil
        self.strikethrough = nil
        self.whiteSpace = nil
        self.textOverflow = nil
        self.textAlign = nil
        self.lineClamp = nil
    }

    public var isEmpty: Bool {
        color == nil &&
        fontFamily == nil &&
        fontFeatures == nil &&
        fontFallbacks == nil &&
        fontSize == nil &&
        lineHeight == nil &&
        fontWeight == nil &&
        fontStyle == nil &&
        backgroundColor == nil &&
        underline == nil &&
        strikethrough == nil &&
        whiteSpace == nil &&
        textOverflow == nil &&
        textAlign == nil &&
        lineClamp == nil
    }

    public mutating func refine(with refinement: TextStyleRefinement) {
        if let c = refinement.color { self.color = c }
        if let ff = refinement.fontFamily { self.fontFamily = ff }
        if let ffeat = refinement.fontFeatures { self.fontFeatures = ffeat }
        if let ffall = refinement.fontFallbacks { self.fontFallbacks = ffall }
        if let fs = refinement.fontSize { self.fontSize = fs }
        if let lh = refinement.lineHeight { self.lineHeight = lh }
        if let fw = refinement.fontWeight { self.fontWeight = fw }
        if let fst = refinement.fontStyle { self.fontStyle = fst }
        if let bg = refinement.backgroundColor { self.backgroundColor = bg }
        if let u = refinement.underline { self.underline = u }
        if let s = refinement.strikethrough { self.strikethrough = s }
        if let ws = refinement.whiteSpace { self.whiteSpace = ws }
        if let to = refinement.textOverflow { self.textOverflow = to }
        if let ta = refinement.textAlign { self.textAlign = ta }
        if let lc = refinement.lineClamp { self.lineClamp = lc }
    }

    public func isSuperset(of refinement: TextStyleRefinement) -> Bool {
        if let c = refinement.color, self.color != c { return false }
        if let ff = refinement.fontFamily, self.fontFamily != ff { return false }
        if let ffeat = refinement.fontFeatures, self.fontFeatures != ffeat { return false }
        if let ffall = refinement.fontFallbacks, self.fontFallbacks != ffall { return false }
        if let fs = refinement.fontSize, self.fontSize != fs { return false }
        if let lh = refinement.lineHeight, self.lineHeight != lh { return false }
        if let fw = refinement.fontWeight, self.fontWeight != fw { return false }
        if let fst = refinement.fontStyle, self.fontStyle != fst { return false }
        if let bg = refinement.backgroundColor, self.backgroundColor != bg { return false }
        if let u = refinement.underline, self.underline != u { return false }
        if let s = refinement.strikethrough, self.strikethrough != s { return false }
        if let ws = refinement.whiteSpace, self.whiteSpace != ws { return false }
        if let to = refinement.textOverflow, self.textOverflow != to { return false }
        if let ta = refinement.textAlign, self.textAlign != ta { return false }
        if let lc = refinement.lineClamp, self.lineClamp != lc { return false }
        return true
    }

    public func subtract(_ refinement: TextStyleRefinement) -> TextStyleRefinement {
        TextStyleRefinement(
            color: self.color == refinement.color ? nil : self.color,
            fontFamily: self.fontFamily == refinement.fontFamily ? nil : self.fontFamily,
            fontFeatures: self.fontFeatures == refinement.fontFeatures ? nil : self.fontFeatures,
            fontFallbacks: self.fontFallbacks == refinement.fontFallbacks ? nil : self.fontFallbacks,
            fontSize: self.fontSize == refinement.fontSize ? nil : self.fontSize,
            lineHeight: self.lineHeight == refinement.lineHeight ? nil : self.lineHeight,
            fontWeight: self.fontWeight == refinement.fontWeight ? nil : self.fontWeight,
            fontStyle: self.fontStyle == refinement.fontStyle ? nil : self.fontStyle,
            backgroundColor: self.backgroundColor == refinement.backgroundColor ? nil : self.backgroundColor,
            underline: self.underline == refinement.underline ? nil : self.underline,
            strikethrough: self.strikethrough == refinement.strikethrough ? nil : self.strikethrough,
            whiteSpace: self.whiteSpace == refinement.whiteSpace ? nil : self.whiteSpace,
            textOverflow: self.textOverflow == refinement.textOverflow ? nil : self.textOverflow,
            textAlign: self.textAlign == refinement.textAlign ? nil : self.textAlign,
            lineClamp: self.lineClamp == refinement.lineClamp ? nil : self.lineClamp
        )
    }
}

/// The properties that can be used to style text in GPUI.
public struct TextStyle: Sendable, Equatable, Refineable, DefaultInitializable {
    public typealias Refinement = TextStyleRefinement

    public var color: Hsla
    public var fontFamily: SharedString
    public var fontFeatures: FontFeatures
    public var fontFallbacks: FontFallbacks?
    public var fontSize: AbsoluteLength
    public var lineHeight: DefiniteLength
    public var fontWeight: FontWeight
    public var fontStyle: FontStyle
    public var backgroundColor: Hsla?
    public var underline: UnderlineStyle?
    public var strikethrough: StrikethroughStyle?
    public var whiteSpace: WhiteSpace
    public var textOverflow: TextOverflow?
    public var textAlign: TextAlign
    public var lineClamp: Int?

    public init(
        color: Hsla = black(),
        fontFamily: SharedString = ".SystemUIFont",
        fontFeatures: FontFeatures = FontFeatures(),
        fontFallbacks: FontFallbacks? = nil,
        fontSize: AbsoluteLength = .rems(Rems(1.0)),
        lineHeight: DefiniteLength = phi(),
        fontWeight: FontWeight = .normal,
        fontStyle: FontStyle = .normal,
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil,
        whiteSpace: WhiteSpace = .normal,
        textOverflow: TextOverflow? = nil,
        textAlign: TextAlign = .left,
        lineClamp: Int? = nil
    ) {
        self.color = color
        self.fontFamily = fontFamily
        self.fontFeatures = fontFeatures
        self.fontFallbacks = fontFallbacks
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontWeight = fontWeight
        self.fontStyle = fontStyle
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
        self.whiteSpace = whiteSpace
        self.textOverflow = textOverflow
        self.textAlign = textAlign
        self.lineClamp = lineClamp
    }

    public init() {
        self.init(color: black())
    }

    /// Create a new text style with the given highlighting applied.
    public func highlight(_ style: HighlightStyle) -> TextStyle {
        var copy = self
        if let weight = style.fontWeight {
            copy.fontWeight = weight
        }
        if let fontStyle = style.fontStyle {
            copy.fontStyle = fontStyle
        }
        if let color = style.color {
            copy.color = copy.color.blend(with: color)
        }
        if let factor = style.fadeOut {
            copy.color.fadeOut(by: factor)
        }
        if let bg = style.backgroundColor {
            copy.backgroundColor = bg
        }
        if let underline = style.underline {
            copy.underline = underline
        }
        if let strikethrough = style.strikethrough {
            copy.strikethrough = strikethrough
        }
        return copy
    }

    /// Get the font configured for this text style.
    public func font() -> Font {
        Font(
            family: fontFamily,
            features: fontFeatures,
            fallbacks: fontFallbacks,
            weight: fontWeight,
            style: fontStyle
        )
    }

    /// Returns the rounded line height in pixels.
    public func lineHeightInPixels(remSize: Pixels) -> Pixels {
        lineHeight.toPixels(baseSize: fontSize, remSize: remSize).round()
    }

    /// Convert this text style into a `TextRun`, for the given character count.
    public func toRun(len: Int) -> TextRun {
        TextRun(
            len: len,
            font: font(),
            color: color,
            backgroundColor: backgroundColor,
            underline: underline,
            strikethrough: strikethrough
        )
    }

    public mutating func refine(with refinement: TextStyleRefinement) {
        if let c = refinement.color { self.color = c }
        if let ff = refinement.fontFamily { self.fontFamily = ff }
        if let ffeat = refinement.fontFeatures { self.fontFeatures = ffeat }
        if let ffall = refinement.fontFallbacks { self.fontFallbacks = ffall }
        if let fs = refinement.fontSize { self.fontSize = fs }
        if let lh = refinement.lineHeight { self.lineHeight = lh }
        if let fw = refinement.fontWeight { self.fontWeight = fw }
        if let fst = refinement.fontStyle { self.fontStyle = fst }
        if let bg = refinement.backgroundColor { self.backgroundColor = bg }
        if let u = refinement.underline { self.underline = u }
        if let s = refinement.strikethrough { self.strikethrough = s }
        if let ws = refinement.whiteSpace { self.whiteSpace = ws }
        if let to = refinement.textOverflow { self.textOverflow = to }
        if let ta = refinement.textAlign { self.textAlign = ta }
        if let lc = refinement.lineClamp { self.lineClamp = lc }
    }

    public func isSuperset(of refinement: TextStyleRefinement) -> Bool {
        if let c = refinement.color, self.color != c { return false }
        if let ff = refinement.fontFamily, self.fontFamily != ff { return false }
        if let ffeat = refinement.fontFeatures, self.fontFeatures != ffeat { return false }
        if let ffall = refinement.fontFallbacks, self.fontFallbacks != ffall { return false }
        if let fs = refinement.fontSize, self.fontSize != fs { return false }
        if let lh = refinement.lineHeight, self.lineHeight != lh { return false }
        if let fw = refinement.fontWeight, self.fontWeight != fw { return false }
        if let fst = refinement.fontStyle, self.fontStyle != fst { return false }
        if let bg = refinement.backgroundColor, self.backgroundColor != bg { return false }
        if let u = refinement.underline, self.underline != u { return false }
        if let s = refinement.strikethrough, self.strikethrough != s { return false }
        if let ws = refinement.whiteSpace, self.whiteSpace != ws { return false }
        if let to = refinement.textOverflow, self.textOverflow != to { return false }
        if let ta = refinement.textAlign, self.textAlign != ta { return false }
        if let lc = refinement.lineClamp, self.lineClamp != lc { return false }
        return true
    }

    public func subtract(_ refinement: TextStyleRefinement) -> TextStyleRefinement {
        TextStyleRefinement(
            color: self.color == refinement.color ? nil : self.color,
            fontFamily: self.fontFamily == refinement.fontFamily ? nil : self.fontFamily,
            fontFeatures: self.fontFeatures == refinement.fontFeatures ? nil : self.fontFeatures,
            fontFallbacks: self.fontFallbacks == refinement.fontFallbacks ? nil : self.fontFallbacks,
            fontSize: self.fontSize == refinement.fontSize ? nil : self.fontSize,
            lineHeight: self.lineHeight == refinement.lineHeight ? nil : self.lineHeight,
            fontWeight: self.fontWeight == refinement.fontWeight ? nil : self.fontWeight,
            fontStyle: self.fontStyle == refinement.fontStyle ? nil : self.fontStyle,
            backgroundColor: self.backgroundColor == refinement.backgroundColor ? nil : self.backgroundColor,
            underline: self.underline == refinement.underline ? nil : self.underline,
            strikethrough: self.strikethrough == refinement.strikethrough ? nil : self.strikethrough,
            whiteSpace: self.whiteSpace == refinement.whiteSpace ? nil : self.whiteSpace,
            textOverflow: self.textOverflow == refinement.textOverflow ? nil : self.textOverflow,
            textAlign: self.textAlign == refinement.textAlign ? nil : self.textAlign,
            lineClamp: self.lineClamp == refinement.lineClamp ? nil : self.lineClamp
        )
    }
}

// MARK: - StyleRefinement & Style

/// The cascading CSS-like styling that can be applied to an element.
public struct StyleRefinement: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = StyleRefinement

    public var display: Display?
    public var visibility: Visibility?
    public var overflow: PointRefinement<Overflow>
    public var scrollbarWidth: AbsoluteLength?
    public var allowConcurrentScroll: Bool?
    public var restrictScrollToAxis: Bool?
    public var position: Position?
    public var inset: EdgesRefinement<Length>
    public var size: SizeRefinement<Length>
    public var minSize: SizeRefinement<Length>
    public var maxSize: SizeRefinement<Length>
    public var aspectRatio: Float?
    public var margin: EdgesRefinement<Length>
    public var padding: EdgesRefinement<DefiniteLength>
    public var borderWidths: EdgesRefinement<AbsoluteLength>
    public var alignItems: AlignItems?
    public var alignSelf: AlignSelf?
    public var alignContent: AlignContent?
    public var justifyContent: JustifyContent?
    public var gap: SizeRefinement<DefiniteLength>
    public var flexDirection: FlexDirection?
    public var flexWrap: FlexWrap?
    public var flexBasis: Length?
    public var flexGrow: Float?
    public var flexShrink: Float?
    public var background: Fill?
    public var borderColor: Hsla?
    public var borderStyle: BorderStyle?
    public var cornerRadii: CornersRefinement<AbsoluteLength>
    public var boxShadow: [BoxShadow]?
    public var text: TextStyleRefinement
    public var mouseCursor: CursorStyle?
    public var opacity: Float?
    public var gridCols: GridTemplate?
    public var gridRows: GridTemplate?
    public var gridLocation: GridLocation?
    public var debug: Bool?
    public var debugBelow: Bool?

    public init(
        display: Display? = nil,
        visibility: Visibility? = nil,
        overflow: PointRefinement<Overflow> = PointRefinement(),
        scrollbarWidth: AbsoluteLength? = nil,
        allowConcurrentScroll: Bool? = nil,
        restrictScrollToAxis: Bool? = nil,
        position: Position? = nil,
        inset: EdgesRefinement<Length> = EdgesRefinement(),
        size: SizeRefinement<Length> = SizeRefinement(),
        minSize: SizeRefinement<Length> = SizeRefinement(),
        maxSize: SizeRefinement<Length> = SizeRefinement(),
        aspectRatio: Float? = nil,
        margin: EdgesRefinement<Length> = EdgesRefinement(),
        padding: EdgesRefinement<DefiniteLength> = EdgesRefinement(),
        borderWidths: EdgesRefinement<AbsoluteLength> = EdgesRefinement(),
        alignItems: AlignItems? = nil,
        alignSelf: AlignSelf? = nil,
        alignContent: AlignContent? = nil,
        justifyContent: JustifyContent? = nil,
        gap: SizeRefinement<DefiniteLength> = SizeRefinement(),
        flexDirection: FlexDirection? = nil,
        flexWrap: FlexWrap? = nil,
        flexBasis: Length? = nil,
        flexGrow: Float? = nil,
        flexShrink: Float? = nil,
        background: Fill? = nil,
        borderColor: Hsla? = nil,
        borderStyle: BorderStyle? = nil,
        cornerRadii: CornersRefinement<AbsoluteLength> = CornersRefinement(),
        boxShadow: [BoxShadow]? = nil,
        text: TextStyleRefinement = TextStyleRefinement(),
        mouseCursor: CursorStyle? = nil,
        opacity: Float? = nil,
        gridCols: GridTemplate? = nil,
        gridRows: GridTemplate? = nil,
        gridLocation: GridLocation? = nil,
        debug: Bool? = nil,
        debugBelow: Bool? = nil
    ) {
        self.display = display
        self.visibility = visibility
        self.overflow = overflow
        self.scrollbarWidth = scrollbarWidth
        self.allowConcurrentScroll = allowConcurrentScroll
        self.restrictScrollToAxis = restrictScrollToAxis
        self.position = position
        self.inset = inset
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.aspectRatio = aspectRatio
        self.margin = margin
        self.padding = padding
        self.borderWidths = borderWidths
        self.alignItems = alignItems
        self.alignSelf = alignSelf
        self.alignContent = alignContent
        self.justifyContent = justifyContent
        self.gap = gap
        self.flexDirection = flexDirection
        self.flexWrap = flexWrap
        self.flexBasis = flexBasis
        self.flexGrow = flexGrow
        self.flexShrink = flexShrink
        self.background = background
        self.borderColor = borderColor
        self.borderStyle = borderStyle
        self.cornerRadii = cornerRadii
        self.boxShadow = boxShadow
        self.text = text
        self.mouseCursor = mouseCursor
        self.opacity = opacity
        self.gridCols = gridCols
        self.gridRows = gridRows
        self.gridLocation = gridLocation
        self.debug = debug
        self.debugBelow = debugBelow
    }

    public init() {
        self.display = nil
        self.visibility = nil
        self.overflow = PointRefinement()
        self.scrollbarWidth = nil
        self.allowConcurrentScroll = nil
        self.restrictScrollToAxis = nil
        self.position = nil
        self.inset = EdgesRefinement()
        self.size = SizeRefinement()
        self.minSize = SizeRefinement()
        self.maxSize = SizeRefinement()
        self.aspectRatio = nil
        self.margin = EdgesRefinement()
        self.padding = EdgesRefinement()
        self.borderWidths = EdgesRefinement()
        self.alignItems = nil
        self.alignSelf = nil
        self.alignContent = nil
        self.justifyContent = nil
        self.gap = SizeRefinement()
        self.flexDirection = nil
        self.flexWrap = nil
        self.flexBasis = nil
        self.flexGrow = nil
        self.flexShrink = nil
        self.background = nil
        self.borderColor = nil
        self.borderStyle = nil
        self.cornerRadii = CornersRefinement()
        self.boxShadow = nil
        self.text = TextStyleRefinement()
        self.mouseCursor = nil
        self.opacity = nil
        self.gridCols = nil
        self.gridRows = nil
        self.gridLocation = nil
        self.debug = nil
        self.debugBelow = nil
    }

    public var isEmpty: Bool {
        display == nil &&
        visibility == nil &&
        overflow.isEmpty &&
        scrollbarWidth == nil &&
        allowConcurrentScroll == nil &&
        restrictScrollToAxis == nil &&
        position == nil &&
        inset.isEmpty &&
        size.isEmpty &&
        minSize.isEmpty &&
        maxSize.isEmpty &&
        aspectRatio == nil &&
        margin.isEmpty &&
        padding.isEmpty &&
        borderWidths.isEmpty &&
        alignItems == nil &&
        alignSelf == nil &&
        alignContent == nil &&
        justifyContent == nil &&
        gap.isEmpty &&
        flexDirection == nil &&
        flexWrap == nil &&
        flexBasis == nil &&
        flexGrow == nil &&
        flexShrink == nil &&
        background == nil &&
        borderColor == nil &&
        borderStyle == nil &&
        cornerRadii.isEmpty &&
        boxShadow == nil &&
        text.isEmpty &&
        mouseCursor == nil &&
        opacity == nil &&
        gridCols == nil &&
        gridRows == nil &&
        gridLocation == nil &&
        debug == nil &&
        debugBelow == nil
    }

    public mutating func refine(with refinement: StyleRefinement) {
        if let d = refinement.display { self.display = d }
        if let v = refinement.visibility { self.visibility = v }
        self.overflow.refine(with: refinement.overflow)
        if let sw = refinement.scrollbarWidth { self.scrollbarWidth = sw }
        if let ac = refinement.allowConcurrentScroll { self.allowConcurrentScroll = ac }
        if let rs = refinement.restrictScrollToAxis { self.restrictScrollToAxis = rs }
        if let p = refinement.position { self.position = p }
        self.inset.refine(with: refinement.inset)
        self.size.refine(with: refinement.size)
        self.minSize.refine(with: refinement.minSize)
        self.maxSize.refine(with: refinement.maxSize)
        if let ar = refinement.aspectRatio { self.aspectRatio = ar }
        self.margin.refine(with: refinement.margin)
        self.padding.refine(with: refinement.padding)
        self.borderWidths.refine(with: refinement.borderWidths)
        if let ai = refinement.alignItems { self.alignItems = ai }
        if let aself = refinement.alignSelf { self.alignSelf = aself }
        if let ac = refinement.alignContent { self.alignContent = ac }
        if let jc = refinement.justifyContent { self.justifyContent = jc }
        self.gap.refine(with: refinement.gap)
        if let fd = refinement.flexDirection { self.flexDirection = fd }
        if let fw = refinement.flexWrap { self.flexWrap = fw }
        if let fb = refinement.flexBasis { self.flexBasis = fb }
        if let fg = refinement.flexGrow { self.flexGrow = fg }
        if let fs = refinement.flexShrink { self.flexShrink = fs }
        if let b = refinement.background { self.background = b }
        if let bc = refinement.borderColor { self.borderColor = bc }
        if let bs = refinement.borderStyle { self.borderStyle = bs }
        self.cornerRadii.refine(with: refinement.cornerRadii)
        if let shadows = refinement.boxShadow { self.boxShadow = shadows }
        self.text.refine(with: refinement.text)
        if let mc = refinement.mouseCursor { self.mouseCursor = mc }
        if let o = refinement.opacity { self.opacity = o }
        if let gc = refinement.gridCols { self.gridCols = gc }
        if let gr = refinement.gridRows { self.gridRows = gr }
        if let gl = refinement.gridLocation { self.gridLocation = gl }
        if let dbg = refinement.debug { self.debug = dbg }
        if let dbgB = refinement.debugBelow { self.debugBelow = dbgB }
    }

    public func isSuperset(of refinement: StyleRefinement) -> Bool {
        if let d = refinement.display, self.display != d { return false }
        if let v = refinement.visibility, self.visibility != v { return false }
        if !self.overflow.isSuperset(of: refinement.overflow) { return false }
        if let sw = refinement.scrollbarWidth, self.scrollbarWidth != sw { return false }
        if let ac = refinement.allowConcurrentScroll, self.allowConcurrentScroll != ac { return false }
        if let rs = refinement.restrictScrollToAxis, self.restrictScrollToAxis != rs { return false }
        if let p = refinement.position, self.position != p { return false }
        if !self.inset.isSuperset(of: refinement.inset) { return false }
        if !self.size.isSuperset(of: refinement.size) { return false }
        if !self.minSize.isSuperset(of: refinement.minSize) { return false }
        if !self.maxSize.isSuperset(of: refinement.maxSize) { return false }
        if let ar = refinement.aspectRatio, self.aspectRatio != ar { return false }
        if !self.margin.isSuperset(of: refinement.margin) { return false }
        if !self.padding.isSuperset(of: refinement.padding) { return false }
        if !self.borderWidths.isSuperset(of: refinement.borderWidths) { return false }
        if let ai = refinement.alignItems, self.alignItems != ai { return false }
        if let aself = refinement.alignSelf, self.alignSelf != aself { return false }
        if let ac = refinement.alignContent, self.alignContent != ac { return false }
        if let jc = refinement.justifyContent, self.justifyContent != jc { return false }
        if !self.gap.isSuperset(of: refinement.gap) { return false }
        if let fd = refinement.flexDirection, self.flexDirection != fd { return false }
        if let fw = refinement.flexWrap, self.flexWrap != fw { return false }
        if let fb = refinement.flexBasis, self.flexBasis != fb { return false }
        if let fg = refinement.flexGrow, self.flexGrow != fg { return false }
        if let fs = refinement.flexShrink, self.flexShrink != fs { return false }
        if let b = refinement.background, self.background != b { return false }
        if let bc = refinement.borderColor, self.borderColor != bc { return false }
        if let bs = refinement.borderStyle, self.borderStyle != bs { return false }
        if !self.cornerRadii.isSuperset(of: refinement.cornerRadii) { return false }
        if let shadows = refinement.boxShadow, self.boxShadow != shadows { return false }
        if !self.text.isSuperset(of: refinement.text) { return false }
        if let mc = refinement.mouseCursor, self.mouseCursor != mc { return false }
        if let o = refinement.opacity, self.opacity != o { return false }
        if let gc = refinement.gridCols, self.gridCols != gc { return false }
        if let gr = refinement.gridRows, self.gridRows != gr { return false }
        if let gl = refinement.gridLocation, self.gridLocation != gl { return false }
        if let dbg = refinement.debug, self.debug != dbg { return false }
        if let dbgB = refinement.debugBelow, self.debugBelow != dbgB { return false }
        return true
    }

    public func subtract(_ refinement: StyleRefinement) -> StyleRefinement {
        StyleRefinement(
            display: self.display == refinement.display ? nil : self.display,
            visibility: self.visibility == refinement.visibility ? nil : self.visibility,
            overflow: self.overflow.subtract(refinement.overflow),
            scrollbarWidth: self.scrollbarWidth == refinement.scrollbarWidth ? nil : self.scrollbarWidth,
            allowConcurrentScroll: self.allowConcurrentScroll == refinement.allowConcurrentScroll ? nil : self.allowConcurrentScroll,
            restrictScrollToAxis: self.restrictScrollToAxis == refinement.restrictScrollToAxis ? nil : self.restrictScrollToAxis,
            position: self.position == refinement.position ? nil : self.position,
            inset: self.inset.subtract(refinement.inset),
            size: self.size.subtract(refinement.size),
            minSize: self.minSize.subtract(refinement.minSize),
            maxSize: self.maxSize.subtract(refinement.maxSize),
            aspectRatio: self.aspectRatio == refinement.aspectRatio ? nil : self.aspectRatio,
            margin: self.margin.subtract(refinement.margin),
            padding: self.padding.subtract(refinement.padding),
            borderWidths: self.borderWidths.subtract(refinement.borderWidths),
            alignItems: self.alignItems == refinement.alignItems ? nil : self.alignItems,
            alignSelf: self.alignSelf == refinement.alignSelf ? nil : self.alignSelf,
            alignContent: self.alignContent == refinement.alignContent ? nil : self.alignContent,
            justifyContent: self.justifyContent == refinement.justifyContent ? nil : self.justifyContent,
            gap: self.gap.subtract(refinement.gap),
            flexDirection: self.flexDirection == refinement.flexDirection ? nil : self.flexDirection,
            flexWrap: self.flexWrap == refinement.flexWrap ? nil : self.flexWrap,
            flexBasis: self.flexBasis == refinement.flexBasis ? nil : self.flexBasis,
            flexGrow: self.flexGrow == refinement.flexGrow ? nil : self.flexGrow,
            flexShrink: self.flexShrink == refinement.flexShrink ? nil : self.flexShrink,
            background: self.background == refinement.background ? nil : self.background,
            borderColor: self.borderColor == refinement.borderColor ? nil : self.borderColor,
            borderStyle: self.borderStyle == refinement.borderStyle ? nil : self.borderStyle,
            cornerRadii: self.cornerRadii.subtract(refinement.cornerRadii),
            boxShadow: self.boxShadow == refinement.boxShadow ? nil : self.boxShadow,
            text: self.text.subtract(refinement.text),
            mouseCursor: self.mouseCursor == refinement.mouseCursor ? nil : self.mouseCursor,
            opacity: self.opacity == refinement.opacity ? nil : self.opacity,
            gridCols: self.gridCols == refinement.gridCols ? nil : self.gridCols,
            gridRows: self.gridRows == refinement.gridRows ? nil : self.gridRows,
            gridLocation: self.gridLocation == refinement.gridLocation ? nil : self.gridLocation,
            debug: self.debug == refinement.debug ? nil : self.debug,
            debugBelow: self.debugBelow == refinement.debugBelow ? nil : self.debugBelow
        )
    }

    /// Access or create the mutable grid location for this style refinement.
    public mutating func gridLocationMut() -> GridLocation {
        if let loc = gridLocation {
            return loc
        }
        let loc = GridLocation()
        self.gridLocation = loc
        return loc
    }

    // Builder helpers for fluent style composition
    public func textSize(_ size: AbsoluteLength) -> StyleRefinement {
        var copy = self
        copy.text.fontSize = size
        return copy
    }

    public func textSize(_ pixels: Pixels) -> StyleRefinement {
        textSize(.pixels(pixels))
    }

    public func fontWeight(_ weight: FontWeight) -> StyleRefinement {
        var copy = self
        copy.text.fontWeight = weight
        return copy
    }

    public func textColor(_ color: Hsla) -> StyleRefinement {
        var copy = self
        copy.text.color = color
        return copy
    }
}

/// The concrete CSS-like styling applied to an element via the `Styled` protocol.
public struct Style: Sendable, Equatable, Refineable, DefaultInitializable {
    public typealias Refinement = StyleRefinement

    /// What layout strategy should be used?
    public var display: Display
    /// Should the element be painted on screen?
    public var visibility: Visibility
    /// How children overflowing their container should affect layout.
    public var overflow: Point<Overflow>
    /// Space reserved for scrollbars.
    public var scrollbarWidth: AbsoluteLength
    /// Whether both x and y axes can scroll concurrently.
    public var allowConcurrentScroll: Bool
    /// Restrict scroll to axis indicated by mouse wheel.
    public var restrictScrollToAxis: Bool
    /// Positioning strategy (relative vs. absolute).
    public var position: Position
    /// Inset tweaking position relative to layout.
    public var inset: Edges<Length>
    /// Initial size.
    public var size: Size<Length>
    /// Minimum size.
    public var minSize: Size<Length>
    /// Maximum size.
    public var maxSize: Size<Length>
    /// Preferred aspect ratio (width / height).
    public var aspectRatio: Float?
    /// Outer margins.
    public var margin: Edges<Length>
    /// Inner padding.
    public var padding: Edges<DefiniteLength>
    /// Border stroke widths.
    public var borderWidths: Edges<AbsoluteLength>
    /// Cross-axis item alignment.
    public var alignItems: AlignItems?
    /// Self cross-axis override.
    public var alignSelf: AlignSelf?
    /// Cross-axis space distribution.
    public var alignContent: AlignContent?
    /// Main-axis space distribution.
    public var justifyContent: JustifyContent?
    /// Gaps between items in flex/grid.
    public var gap: Size<DefiniteLength>
    /// Main axis flow direction.
    public var flexDirection: FlexDirection
    /// Whether items wrap.
    public var flexWrap: FlexWrap
    /// Initial main axis size.
    public var flexBasis: Length
    /// Expansion growth rate.
    public var flexGrow: Float
    /// Contraction shrink rate.
    public var flexShrink: Float
    /// Fill/background of element.
    public var background: Fill?
    /// Border stroke color.
    public var borderColor: Hsla?
    /// Border style.
    public var borderStyle: BorderStyle
    /// Corner radii.
    public var cornerRadii: Corners<AbsoluteLength>
    /// Drop shadows.
    public var boxShadow: [BoxShadow]
    /// Text styling overrides.
    public var text: TextStyleRefinement
    /// Mouse pointer hover cursor.
    public var mouseCursor: CursorStyle?
    /// Opacity factor.
    public var opacity: Float?
    /// Grid columns template.
    public var gridCols: GridTemplate?
    /// Grid rows template.
    public var gridRows: GridTemplate?
    /// Grid location placement.
    public var gridLocation: GridLocation?
    /// Red debugging outline.
    public var debug: Bool
    /// Red debugging outline on descendants.
    public var debugBelow: Bool

    public init(
        display: Display = .block,
        visibility: Visibility = .visible,
        overflow: Point<Overflow> = Point(x: .visible, y: .visible),
        scrollbarWidth: AbsoluteLength = .pixels(Pixels(0.0)),
        allowConcurrentScroll: Bool = false,
        restrictScrollToAxis: Bool = false,
        position: Position = .relative,
        inset: Edges<Length> = Edges.auto(),
        size: Size<Length> = Size.auto(),
        minSize: Size<Length> = Size.auto(),
        maxSize: Size<Length> = Size.auto(),
        aspectRatio: Float? = nil,
        margin: Edges<Length> = Edges.zero,
        padding: Edges<DefiniteLength> = Edges.zero,
        borderWidths: Edges<AbsoluteLength> = Edges.zero,
        alignItems: AlignItems? = nil,
        alignSelf: AlignSelf? = nil,
        alignContent: AlignContent? = nil,
        justifyContent: JustifyContent? = nil,
        gap: Size<DefiniteLength> = Size(width: .zero, height: .zero),
        flexDirection: FlexDirection = .row,
        flexWrap: FlexWrap = .noWrap,
        flexBasis: Length = .auto,
        flexGrow: Float = 0.0,
        flexShrink: Float = 1.0,
        background: Fill? = nil,
        borderColor: Hsla? = nil,
        borderStyle: BorderStyle = .solid,
        cornerRadii: Corners<AbsoluteLength> = Corners.zero,
        boxShadow: [BoxShadow] = [],
        text: TextStyleRefinement = TextStyleRefinement(),
        mouseCursor: CursorStyle? = nil,
        opacity: Float? = nil,
        gridCols: GridTemplate? = nil,
        gridRows: GridTemplate? = nil,
        gridLocation: GridLocation? = nil,
        debug: Bool = false,
        debugBelow: Bool = false
    ) {
        self.display = display
        self.visibility = visibility
        self.overflow = overflow
        self.scrollbarWidth = scrollbarWidth
        self.allowConcurrentScroll = allowConcurrentScroll
        self.restrictScrollToAxis = restrictScrollToAxis
        self.position = position
        self.inset = inset
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.aspectRatio = aspectRatio
        self.margin = margin
        self.padding = padding
        self.borderWidths = borderWidths
        self.alignItems = alignItems
        self.alignSelf = alignSelf
        self.alignContent = alignContent
        self.justifyContent = justifyContent
        self.gap = gap
        self.flexDirection = flexDirection
        self.flexWrap = flexWrap
        self.flexBasis = flexBasis
        self.flexGrow = flexGrow
        self.flexShrink = flexShrink
        self.background = background
        self.borderColor = borderColor
        self.borderStyle = borderStyle
        self.cornerRadii = cornerRadii
        self.boxShadow = boxShadow
        self.text = text
        self.mouseCursor = mouseCursor
        self.opacity = opacity
        self.gridCols = gridCols
        self.gridRows = gridRows
        self.gridLocation = gridLocation
        self.debug = debug
        self.debugBelow = debugBelow
    }

    public init() {
        self.init(display: .block)
    }

    /// Returns true if the style is visible and the background is opaque.
    public func hasOpaqueBackground() -> Bool {
        if let bg = background?.color() {
            return !bg.isTransparent
        }
        return false
    }

    /// Returns true if any border side has non-zero width and the border color is not transparent.
    public func isBorderVisible() -> Bool {
        if let color = borderColor, !color.isTransparent {
            return borderWidths.any { !$0.isZero }
        }
        return false
    }

    /// Get the text style refinement in this element style if not empty.
    public func textStyle() -> TextStyleRefinement? {
        if !text.isEmpty {
            return text
        }
        return nil
    }

    /// Get the content mask for this element style, based on the given bounds and rem size.
    /// If the element does not hide its overflow, returns `nil`.
    public func overflowMask(
        bounds: Bounds<Pixels>,
        remSize: Pixels
    ) -> ContentMask<Pixels>? {
        if overflow.x == .visible && overflow.y == .visible {
            return nil
        }

        var minPt = bounds.origin
        var maxPt = bounds.bottomRight

        if let color = borderColor, !color.isTransparent {
            minPt.x += borderWidths.left.toPixels(remSize: remSize)
            maxPt.x -= borderWidths.right.toPixels(remSize: remSize)
            minPt.y += borderWidths.top.toPixels(remSize: remSize)
            maxPt.y -= borderWidths.bottom.toPixels(remSize: remSize)
        }

        let maskBounds: Bounds<Pixels>
        switch (overflow.x == .visible, overflow.y == .visible) {
        case (true, true):
            return nil
        case (true, false):
            maskBounds = Bounds.fromCorners(
                point(minPt.x, bounds.origin.y),
                point(maxPt.x, bounds.bottomRight.y)
            )
        case (false, true):
            maskBounds = Bounds.fromCorners(
                point(bounds.origin.x, minPt.y),
                point(bounds.bottomRight.x, maxPt.y)
            )
        case (false, false):
            maskBounds = Bounds.fromCorners(minPt, maxPt)
        }

        return ContentMask(bounds: maskBounds)
    }

    public mutating func refine(with refinement: StyleRefinement) {
        if let d = refinement.display { self.display = d }
        if let v = refinement.visibility { self.visibility = v }
        self.overflow.refine(with: refinement.overflow)
        if let sw = refinement.scrollbarWidth { self.scrollbarWidth = sw }
        if let ac = refinement.allowConcurrentScroll { self.allowConcurrentScroll = ac }
        if let rs = refinement.restrictScrollToAxis { self.restrictScrollToAxis = rs }
        if let p = refinement.position { self.position = p }
        self.inset.refine(with: refinement.inset)
        self.size.refine(with: refinement.size)
        self.minSize.refine(with: refinement.minSize)
        self.maxSize.refine(with: refinement.maxSize)
        if let ar = refinement.aspectRatio { self.aspectRatio = ar }
        self.margin.refine(with: refinement.margin)
        self.padding.refine(with: refinement.padding)
        self.borderWidths.refine(with: refinement.borderWidths)
        if let ai = refinement.alignItems { self.alignItems = ai }
        if let aself = refinement.alignSelf { self.alignSelf = aself }
        if let ac = refinement.alignContent { self.alignContent = ac }
        if let jc = refinement.justifyContent { self.justifyContent = jc }
        self.gap.refine(with: refinement.gap)
        if let fd = refinement.flexDirection { self.flexDirection = fd }
        if let fw = refinement.flexWrap { self.flexWrap = fw }
        if let fb = refinement.flexBasis { self.flexBasis = fb }
        if let fg = refinement.flexGrow { self.flexGrow = fg }
        if let fs = refinement.flexShrink { self.flexShrink = fs }
        if let b = refinement.background { self.background = b }
        if let bc = refinement.borderColor { self.borderColor = bc }
        if let bs = refinement.borderStyle { self.borderStyle = bs }
        self.cornerRadii.refine(with: refinement.cornerRadii)
        if let shadows = refinement.boxShadow { self.boxShadow = shadows }
        self.text.refine(with: refinement.text)
        if let mc = refinement.mouseCursor { self.mouseCursor = mc }
        if let o = refinement.opacity { self.opacity = o }
        if let gc = refinement.gridCols { self.gridCols = gc }
        if let gr = refinement.gridRows { self.gridRows = gr }
        if let gl = refinement.gridLocation { self.gridLocation = gl }
        if let dbg = refinement.debug { self.debug = dbg }
        if let dbgB = refinement.debugBelow { self.debugBelow = dbgB }
    }

    public func isSuperset(of refinement: StyleRefinement) -> Bool {
        if let d = refinement.display, self.display != d { return false }
        if let v = refinement.visibility, self.visibility != v { return false }
        if !self.overflow.isSuperset(of: refinement.overflow) { return false }
        if let sw = refinement.scrollbarWidth, self.scrollbarWidth != sw { return false }
        if let ac = refinement.allowConcurrentScroll, self.allowConcurrentScroll != ac { return false }
        if let rs = refinement.restrictScrollToAxis, self.restrictScrollToAxis != rs { return false }
        if let p = refinement.position, self.position != p { return false }
        if !self.inset.isSuperset(of: refinement.inset) { return false }
        if !self.size.isSuperset(of: refinement.size) { return false }
        if !self.minSize.isSuperset(of: refinement.minSize) { return false }
        if !self.maxSize.isSuperset(of: refinement.maxSize) { return false }
        if let ar = refinement.aspectRatio, self.aspectRatio != ar { return false }
        if !self.margin.isSuperset(of: refinement.margin) { return false }
        if !self.padding.isSuperset(of: refinement.padding) { return false }
        if !self.borderWidths.isSuperset(of: refinement.borderWidths) { return false }
        if let ai = refinement.alignItems, self.alignItems != ai { return false }
        if let aself = refinement.alignSelf, self.alignSelf != aself { return false }
        if let ac = refinement.alignContent, self.alignContent != ac { return false }
        if let jc = refinement.justifyContent, self.justifyContent != jc { return false }
        if !self.gap.isSuperset(of: refinement.gap) { return false }
        if let fd = refinement.flexDirection, self.flexDirection != fd { return false }
        if let fw = refinement.flexWrap, self.flexWrap != fw { return false }
        if let fb = refinement.flexBasis, self.flexBasis != fb { return false }
        if let fg = refinement.flexGrow, self.flexGrow != fg { return false }
        if let fs = refinement.flexShrink, self.flexShrink != fs { return false }
        if let b = refinement.background, self.background != b { return false }
        if let bc = refinement.borderColor, self.borderColor != bc { return false }
        if let bs = refinement.borderStyle, self.borderStyle != bs { return false }
        if !self.cornerRadii.isSuperset(of: refinement.cornerRadii) { return false }
        if let shadows = refinement.boxShadow, self.boxShadow != shadows { return false }
        if !self.text.isSuperset(of: refinement.text) { return false }
        if let mc = refinement.mouseCursor, self.mouseCursor != mc { return false }
        if let o = refinement.opacity, self.opacity != o { return false }
        if let gc = refinement.gridCols, self.gridCols != gc { return false }
        if let gr = refinement.gridRows, self.gridRows != gr { return false }
        if let gl = refinement.gridLocation, self.gridLocation != gl { return false }
        if let dbg = refinement.debug, self.debug != dbg { return false }
        if let dbgB = refinement.debugBelow, self.debugBelow != dbgB { return false }
        return true
    }

    public func subtract(_ refinement: StyleRefinement) -> StyleRefinement {
        StyleRefinement(
            display: self.display == refinement.display ? nil : self.display,
            visibility: self.visibility == refinement.visibility ? nil : self.visibility,
            overflow: self.overflow.subtract(refinement.overflow),
            scrollbarWidth: self.scrollbarWidth == refinement.scrollbarWidth ? nil : self.scrollbarWidth,
            allowConcurrentScroll: self.allowConcurrentScroll == refinement.allowConcurrentScroll ? nil : self.allowConcurrentScroll,
            restrictScrollToAxis: self.restrictScrollToAxis == refinement.restrictScrollToAxis ? nil : self.restrictScrollToAxis,
            position: self.position == refinement.position ? nil : self.position,
            inset: self.inset.subtract(refinement.inset),
            size: self.size.subtract(refinement.size),
            minSize: self.minSize.subtract(refinement.minSize),
            maxSize: self.maxSize.subtract(refinement.maxSize),
            aspectRatio: self.aspectRatio == refinement.aspectRatio ? nil : self.aspectRatio,
            margin: self.margin.subtract(refinement.margin),
            padding: self.padding.subtract(refinement.padding),
            borderWidths: self.borderWidths.subtract(refinement.borderWidths),
            alignItems: self.alignItems == refinement.alignItems ? nil : self.alignItems,
            alignSelf: self.alignSelf == refinement.alignSelf ? nil : self.alignSelf,
            alignContent: self.alignContent == refinement.alignContent ? nil : self.alignContent,
            justifyContent: self.justifyContent == refinement.justifyContent ? nil : self.justifyContent,
            gap: self.gap.subtract(refinement.gap),
            flexDirection: self.flexDirection == refinement.flexDirection ? nil : self.flexDirection,
            flexWrap: self.flexWrap == refinement.flexWrap ? nil : self.flexWrap,
            flexBasis: self.flexBasis == refinement.flexBasis ? nil : self.flexBasis,
            flexGrow: self.flexGrow == refinement.flexGrow ? nil : self.flexGrow,
            flexShrink: self.flexShrink == refinement.flexShrink ? nil : self.flexShrink,
            background: self.background == refinement.background ? nil : self.background,
            borderColor: self.borderColor == refinement.borderColor ? nil : self.borderColor,
            borderStyle: self.borderStyle == refinement.borderStyle ? nil : self.borderStyle,
            cornerRadii: self.cornerRadii.subtract(refinement.cornerRadii),
            boxShadow: self.boxShadow == refinement.boxShadow ? nil : self.boxShadow,
            text: self.text.subtract(refinement.text),
            mouseCursor: self.mouseCursor == refinement.mouseCursor ? nil : self.mouseCursor,
            opacity: self.opacity == refinement.opacity ? nil : self.opacity,
            gridCols: self.gridCols == refinement.gridCols ? nil : self.gridCols,
            gridRows: self.gridRows == refinement.gridRows ? nil : self.gridRows,
            gridLocation: self.gridLocation == refinement.gridLocation ? nil : self.gridLocation,
            debug: self.debug == refinement.debug ? nil : self.debug,
            debugBelow: self.debugBelow == refinement.debugBelow ? nil : self.debugBelow
        )
    }
}

// MARK: - Styled Protocol

/// A trait for types that can be styled with `StyleRefinement`.
public protocol Styled {
    var style: StyleRefinement { get set }
}

extension StyleRefinement: Styled {
    public var style: StyleRefinement {
        get { self }
        set { self = newValue }
    }
}

extension Style {
    public mutating func refine(_ refinement: StyleRefinement) {
        self.refine(with: refinement)
    }
}
