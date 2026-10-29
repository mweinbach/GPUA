// Ported from: crates/gpui/src/elements/text.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable
import Taffy

// MARK: - TextLayout

// PORT NOTE: TextLayoutInner is accessed synchronously on the main thread during element layout and paint matching upstream RefCell<TextLayoutInner>.
final class TextLayoutInner: @unchecked Sendable {
    var len: Int
    var lines: [WrappedLine]
    var lineHeight: Pixels
    var wrapWidth: Pixels?
    var size: Size<Pixels>?
    var bounds: Bounds<Pixels>?

    init(
        len: Int = 0,
        lines: [WrappedLine] = [],
        lineHeight: Pixels = .zero,
        wrapWidth: Pixels? = nil,
        size: Size<Pixels>? = nil,
        bounds: Bounds<Pixels>? = nil
    ) {
        self.len = len
        self.lines = lines
        self.lineHeight = lineHeight
        self.wrapWidth = wrapWidth
        self.size = size
        self.bounds = bounds
    }
}

/// The Layout for TextElement. This can be used to map indices to pixels and vice versa.
public struct TextLayout {
    // PORT NOTE: Reference cell wrapper holds mutable layout geometry across phases.
    private var inner: TextLayoutInner

    public init() {
        self.inner = TextLayoutInner()
    }

    @MainActor
    public mutating func layout(
        text: SharedString,
        runs: [TextRun]?,
        window: inout Window,
        cx: inout App
    ) -> LayoutId {
        let textStyle = window.textStyle()
        let fontSize = textStyle.fontSize.toPixels(remSize: window.remSize)
        let lineHeight = textStyle.lineHeight.toPixels(baseSize: AbsoluteLength.pixels(fontSize), remSize: window.remSize)

        let runs = runs ?? [textStyle.toRun(len: text.count)]
        let innerRef = self.inner

        return window.requestMeasuredLayout(style: Style()) { knownDimensions, availableSpace, window, cx in
            let wrapWidth: Pixels?
            if textStyle.whiteSpace == .normal {
                wrapWidth = knownDimensions.width ?? {
                    if case .definite(let px) = availableSpace.width { return px }
                    return nil
                }()
            } else {
                wrapWidth = nil
            }

            let lines: [WrappedLine]
            do {
                lines = try window.textSystem().shapeText(
                    text: text,
                    fontSize: fontSize,
                    runs: runs,
                    wrapWidth: wrapWidth,
                    lineClamp: textStyle.lineClamp
                )
            } catch {
                innerRef.lines = []
                innerRef.len = 0
                innerRef.lineHeight = lineHeight
                innerRef.wrapWidth = wrapWidth
                innerRef.size = .zero
                return .zero
            }

            var size = Size<Pixels>.zero
            for line in lines {
                let lineSize = Size(width: line.layout.width(), height: lineHeight * Float(line.layout.wrapBoundaries.count + 1))
                size.height += lineSize.height
                size.width = Swift.max(size.width, lineSize.width).ceil()
            }

            innerRef.lines = lines
            innerRef.len = text.count
            innerRef.lineHeight = lineHeight
            innerRef.wrapWidth = wrapWidth
            innerRef.size = size
            return size
        }
    }

    public mutating func prepaint(bounds: Bounds<Pixels>, text: String) {
        inner.bounds = bounds
    }

    @MainActor
    public func paint(text: String, window: inout Window, cx: inout App) {
        guard let bounds = inner.bounds else { return }
        let lineHeight = inner.lineHeight
        var lineOrigin = bounds.origin
        let textStyle = window.textStyle()

        for line in inner.lines {
            try? line.paintBackground(
                origin: lineOrigin,
                lineHeight: lineHeight,
                align: textStyle.textAlign,
                bounds: bounds,
                window: &window,
                cx: cx
            )
            try? line.paint(
                origin: lineOrigin,
                lineHeight: lineHeight,
                align: textStyle.textAlign,
                bounds: bounds,
                window: &window,
                cx: cx
            )
            let h = lineHeight * Float(line.layout.wrapBoundaries.count + 1)
            lineOrigin.y += h
        }
    }

    /// Get the byte index into the input of the pixel position.
    public func indexForPosition(_ position: Point<Pixels>) -> Result<Int, Int> {
        guard let bounds = inner.bounds else { return .failure(0) }

        if position.y < bounds.top {
            return .failure(0)
        }

        let lineHeight = inner.lineHeight
        var lineOrigin = bounds.origin
        var lineStartIx = 0

        for line in inner.lines {
            let lineH = lineHeight * Float(line.layout.wrapBoundaries.count + 1)
            let lineBottom = lineOrigin.y + lineH
            if position.y > lineBottom {
                lineOrigin.y = lineBottom
                lineStartIx += line.len() + 1
            } else {
                let positionWithinLine = position - lineOrigin
                let res = line.layout.indexForPosition(positionWithinLine, lineHeight: lineHeight)
                switch res {
                case .success(let ix):
                    return .success(lineStartIx + ix)
                case .failure(let ix):
                    return .failure(lineStartIx + ix)
                }
            }
        }

        return .failure(max(0, lineStartIx - 1))
    }

    /// Get the pixel position for the given byte index.
    public func positionForIndex(_ index: Int) -> Point<Pixels>? {
        guard let bounds = inner.bounds else { return nil }
        let lineHeight = inner.lineHeight
        var lineOrigin = bounds.origin
        var lineStartIx = 0

        for line in inner.lines {
            let lineEndIx = lineStartIx + line.len()
            if index < lineStartIx {
                break
            } else if index > lineEndIx {
                lineOrigin.y += lineHeight * Float(line.layout.wrapBoundaries.count + 1)
                lineStartIx = lineEndIx + 1
                continue
            } else {
                let ixWithinLine = index - lineStartIx
                if let pos = line.layout.positionForIndex(ixWithinLine, lineHeight: lineHeight) {
                    return lineOrigin + pos
                }
                return nil
            }
        }

        return nil
    }

    /// Retrieve the layout for the line containing the given byte index.
    public func lineLayoutForIndex(_ index: Int) -> WrappedLineLayout? {
        guard inner.bounds != nil else { return nil }
        let lineHeight = inner.lineHeight
        var lineOrigin = Point<Pixels>.zero
        var lineStartIx = 0

        for line in inner.lines {
            let lineEndIx = lineStartIx + line.len()
            if index < lineStartIx {
                break
            } else if index > lineEndIx {
                lineOrigin.y += lineHeight * Float(line.layout.wrapBoundaries.count + 1)
                lineStartIx = lineEndIx + 1
                continue
            } else {
                return line.layout
            }
        }

        return nil
    }

    /// The bounds of this layout.
    public func bounds() -> Bounds<Pixels> {
        inner.bounds ?? .zero
    }

    /// The line height for this layout.
    public func lineHeight() -> Pixels {
        inner.lineHeight
    }

    /// The UTF-8 length of the underlying text.
    public func len() -> Int {
        inner.len
    }

    /// The text for this layout.
    public func text() -> String {
        inner.lines.map { $0.text.description }.joined(separator: "\n")
    }

    /// The text for this layout (with soft-wraps as newlines)
    public func wrappedText() -> String {
        var accumulator = ""

        for wrapped in inner.lines {
            var seen = 0
            for boundary in wrapped.layout.wrapBoundaries {
                let run = wrapped.layout.unwrappedLayout.runs[boundary.runIx]
                let index = run.glyphs[boundary.glyphIx].index
                let str = wrapped.text.description
                if seen <= index && index <= str.utf8.count {
                    let startIdx = str.utf8.index(str.utf8.startIndex, offsetBy: seen)
                    let endIdx = str.utf8.index(str.utf8.startIndex, offsetBy: index)
                    accumulator += String(str[startIdx..<endIdx]) + "\n"
                    seen = index
                }
            }
            let str = wrapped.text.description
            if seen <= str.utf8.count {
                let startIdx = str.utf8.index(str.utf8.startIndex, offsetBy: seen)
                accumulator += String(str[startIdx...]) + "\n"
            }
        }

        if accumulator.hasSuffix("\n") {
            accumulator.removeLast()
        }
        return accumulator
    }
}

// MARK: - StyledText

/// Renders text with runs of different styles.
public struct StyledText: Element, IntoElement {
    public typealias RequestLayoutState = TextLayout
    public typealias PrepaintState = Void

    public var text: SharedString
    public var runs: [TextRun]?
    public var delayedHighlights: [(Range<Int>, HighlightStyle)]?
    public var layoutState: TextLayout

    public init(text: SharedString) {
        self.text = text
        self.runs = nil
        self.delayedHighlights = nil
        self.layoutState = TextLayout()
    }

    /// Construct a new styled text element from the given string.
    public static func new(_ text: SharedString) -> Self {
        StyledText(text: text)
    }

    /// Get the layout for this element. This can be used to map indices to pixels and vice versa.
    public func layout() -> TextLayout {
        self.layoutState
    }

    /// Set the styling attributes for the given text, as well as
    /// as any ranges of text that have had their style customized.
    public func withDefaultHighlights(
        _ defaultStyle: TextStyle,
        _ highlights: [(Range<Int>, HighlightStyle)]
    ) -> Self {
        var copy = self
        var runs: [TextRun] = []
        var ix = 0
        let textLen = text.count

        for (range, highlight) in highlights {
            if ix < range.lowerBound {
                runs.append(defaultStyle.toRun(len: range.lowerBound - ix))
            }
            runs.append(defaultStyle.highlight(highlight).toRun(len: range.count))
            ix = range.upperBound
        }
        if ix < textLen {
            runs.append(defaultStyle.toRun(len: textLen - ix))
        }

        copy.runs = runs
        return copy
    }

    /// Set the styling attributes for the given text, as well as
    /// as any ranges of text that have had their style customized.
    public func withHighlights(_ highlights: [(Range<Int>, HighlightStyle)]) -> Self {
        var copy = self
        copy.delayedHighlights = highlights
        return copy
    }

    /// Set the text runs for this piece of text.
    public func withRuns(_ runs: [TextRun]) -> Self {
        var copy = self
        copy.runs = runs
        return copy
    }

    public func id() -> ElementId? { nil }
    public func sourceLocation() -> String? { nil }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, TextLayout) {
        let layoutId = layoutState.layout(text: text, runs: runs, window: &window, cx: &cx)
        return (layoutId, layoutState)
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout TextLayout,
        _ window: inout Window,
        _ cx: inout App
    ) {
        requestLayout.prepaint(bounds: bounds, text: text.description)
        self.layoutState = requestLayout
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout TextLayout,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        requestLayout.paint(text: text.description, window: &window, cx: &cx)
    }

    public func intoElement() -> StyledText { self }
}

// MARK: - InteractiveText

public struct InteractiveTextState {
    public var mouseDownIndex: Int?
    public var hoveredIndex: Int?
    public var activeTooltip: TooltipId?

    public init(mouseDownIndex: Int? = nil, hoveredIndex: Int? = nil, activeTooltip: TooltipId? = nil) {
        self.mouseDownIndex = mouseDownIndex
        self.hoveredIndex = hoveredIndex
        self.activeTooltip = activeTooltip
    }
}

/// InteractiveText is a wrapper around StyledText that adds mouse interactions.
public struct InteractiveText: Element, IntoElement {
    public typealias RequestLayoutState = Void
    public typealias PrepaintState = Void

    public var elementId: ElementId
    public var text: StyledText
    public var clickListener: ((Int, inout Window, inout App) -> Void)?
    public var hoverListener: ((Int?, inout Window, inout App) -> Void)?
    public var tooltipBuilder: ((Int, inout Window, inout App) -> AnyView?)?
    public var clickableRanges: [Range<Int>]

    public init(id: ElementId, text: StyledText) {
        self.elementId = id
        self.text = text
        self.clickListener = nil
        self.hoverListener = nil
        self.tooltipBuilder = nil
        self.clickableRanges = []
    }

    /// Creates a new InteractiveText from the given text.
    public static func new(_ id: ElementId, _ text: StyledText) -> Self {
        InteractiveText(id: id, text: text)
    }

    /// on_click is called when the user clicks on one of the given ranges, passing the index of
    /// the clicked range.
    public func onClick(
        _ ranges: [Range<Int>],
        _ listener: @escaping (Int, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.clickableRanges = ranges
        copy.clickListener = listener
        return copy
    }

    /// on_hover is called when the mouse moves over a character within the text, passing the
    /// index of the hovered character, or nil if the mouse leaves the text.
    public func onHover(
        _ listener: @escaping (Int?, inout Window, inout App) -> Void
    ) -> Self {
        var copy = self
        copy.hoverListener = listener
        return copy
    }

    /// tooltip lets you specify a tooltip for a given character index in the string.
    public func tooltip(
        _ builder: @escaping (Int, inout Window, inout App) -> AnyView?
    ) -> Self {
        var copy = self
        copy.tooltipBuilder = builder
        return copy
    }

    public func id() -> ElementId? { self.elementId }
    public func sourceLocation() -> String? { nil }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, Void) {
        let (layoutId, _) = text.requestLayout(id, inspectorId, &window, &cx)
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
        var dummy = text.layoutState
        text.prepaint(id, inspectorId, bounds, &dummy, &window, &cx)
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
        var dummy = text.layoutState
        var dummyPrepaint: Void = ()
        text.paint(id, inspectorId, bounds, &dummy, &dummyPrepaint, &window, &cx)
    }

    public func intoElement() -> InteractiveText { self }
}

// MARK: - String Element Extensions

extension SharedString: Element, IntoElement {
    public typealias RequestLayoutState = TextLayout
    public typealias PrepaintState = Void

    public func id() -> ElementId? { nil }
    public func sourceLocation() -> String? { nil }

    @MainActor
    public mutating func requestLayout(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ window: inout Window,
        _ cx: inout App
    ) -> (LayoutId, TextLayout) {
        var state = TextLayout()
        let layoutId = state.layout(text: self, runs: nil, window: &window, cx: &cx)
        return (layoutId, state)
    }

    @MainActor
    public mutating func prepaint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout TextLayout,
        _ window: inout Window,
        _ cx: inout App
    ) {
        requestLayout.prepaint(bounds: bounds, text: self.description)
    }

    @MainActor
    public mutating func paint(
        _ id: GlobalElementId?,
        _ inspectorId: InspectorElementId?,
        _ bounds: Bounds<Pixels>,
        _ requestLayout: inout TextLayout,
        _ prepaint: inout Void,
        _ window: inout Window,
        _ cx: inout App
    ) {
        requestLayout.paint(text: self.description, window: &window, cx: &cx)
    }

    public func intoElement() -> SharedString { self }
}

extension String: IntoElement {
    public func intoElement() -> SharedString {
        SharedString(self)
    }

    public func intoAnyElement() -> AnyElement {
        AnyElement(SharedString(self))
    }
}
