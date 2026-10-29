// Ported from: crates/gpui/src/text_system/line.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Set the text decoration for a run of text.
public struct DecorationRun: Sendable, Equatable {
    /// The length of the run in utf-8 bytes.
    public var len: UInt32
    /// The color for this run.
    public var color: Hsla
    /// The background color for this run.
    public var backgroundColor: Hsla?
    /// The underline style for this run.
    public var underline: UnderlineStyle?
    /// The strikethrough style for this run.
    public var strikethrough: StrikethroughStyle?

    public init(
        len: UInt32 = 0,
        color: Hsla = black(),
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil
    ) {
        self.len = len
        self.color = color
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
    }
}

/// A line of text that has been shaped and decorated.
// PORT NOTE: ShapedLine holds mutable line layout and decoration state populated during shaping.
public final class ShapedLine: @unchecked Sendable {
    public var layout: LineLayout
    /// The text that was shaped for this line.
    public var text: SharedString
    public var decorationRuns: [DecorationRun]

    public init(
        layout: LineLayout,
        text: SharedString = "",
        decorationRuns: [DecorationRun] = []
    ) {
        self.layout = layout
        self.text = text
        self.decorationRuns = decorationRuns
    }

    /// The length of the line in utf-8 bytes.
    public func len() -> Int {
        layout.len
    }

    /// Override the len, useful if you're rendering text a as text b.
    public func withLen(_ len: Int) -> ShapedLine {
        let newLayout = LineLayout(
            fontSize: layout.fontSize,
            width: layout.width,
            ascent: layout.ascent,
            descent: layout.descent,
            runs: layout.runs,
            len: len
        )
        return ShapedLine(
            layout: newLayout,
            text: text,
            decorationRuns: decorationRuns
        )
    }

    /// Paint the line of text to the window.
    @MainActor
    public func paint(
        origin: Point<Pixels>,
        lineHeight: Pixels,
        align: TextAlign,
        alignWidth: Pixels? = nil,
        window: inout Window,
        cx: App
    ) throws {
        try paintLine(
            origin: origin,
            layout: layout,
            lineHeight: lineHeight,
            align: align,
            alignWidth: alignWidth,
            decorationRuns: decorationRuns,
            wrapBoundaries: [],
            window: &window,
            cx: cx
        )
    }

    /// Paint the background of the line to the window.
    @MainActor
    public func paintBackground(
        origin: Point<Pixels>,
        lineHeight: Pixels,
        align: TextAlign,
        alignWidth: Pixels? = nil,
        window: inout Window,
        cx: App
    ) throws {
        paintLineBackground(
            origin: origin,
            layout: layout,
            lineHeight: lineHeight,
            align: align,
            alignWidth: alignWidth,
            decorationRuns: decorationRuns,
            wrapBoundaries: [],
            window: &window,
            cx: cx
        )
    }
}

/// A line of text that has been shaped, decorated, and wrapped by the text layout system.
// PORT NOTE: WrappedLine holds mutable wrapped line layout and decoration state populated during wrapping.
public final class WrappedLine: @unchecked Sendable {
    public var layout: WrappedLineLayout
    /// The text that was shaped for this line.
    public var text: SharedString
    public var decorationRuns: [DecorationRun]

    public init(
        layout: WrappedLineLayout,
        text: SharedString = "",
        decorationRuns: [DecorationRun] = []
    ) {
        self.layout = layout
        self.text = text
        self.decorationRuns = decorationRuns
    }

    /// The length of the underlying, unwrapped layout, in utf-8 bytes.
    public func len() -> Int {
        layout.len()
    }

    /// Paint this line of text to the window.
    @MainActor
    public func paint(
        origin: Point<Pixels>,
        lineHeight: Pixels,
        align: TextAlign,
        bounds: Bounds<Pixels>? = nil,
        window: inout Window,
        cx: App
    ) throws {
        let alignWidth = bounds?.size.width ?? layout.wrapWidth
        try paintLine(
            origin: origin,
            layout: layout.unwrappedLayout,
            lineHeight: lineHeight,
            align: align,
            alignWidth: alignWidth,
            decorationRuns: decorationRuns,
            wrapBoundaries: layout.wrapBoundaries,
            window: &window,
            cx: cx
        )
    }

    /// Paint the background of line of text to the window.
    @MainActor
    public func paintBackground(
        origin: Point<Pixels>,
        lineHeight: Pixels,
        align: TextAlign,
        bounds: Bounds<Pixels>? = nil,
        window: inout Window,
        cx: App
    ) throws {
        let alignWidth = bounds?.size.width ?? layout.wrapWidth
        paintLineBackground(
            origin: origin,
            layout: layout.unwrappedLayout,
            lineHeight: lineHeight,
            align: align,
            alignWidth: alignWidth,
            decorationRuns: decorationRuns,
            wrapBoundaries: layout.wrapBoundaries,
            window: &window,
            cx: cx
        )
    }
}

private func alignedOriginX(
    origin: Point<Pixels>,
    width: Pixels,
    x: Pixels,
    align: TextAlign,
    layout: LineLayout,
    nextWrap: WrapBoundary?
) -> Pixels {
    let nextWrapX: Pixels
    if let wrap = nextWrap, wrap.runIx < layout.runs.count, wrap.glyphIx < layout.runs[wrap.runIx].glyphs.count {
        nextWrapX = layout.runs[wrap.runIx].glyphs[wrap.glyphIx].position.x
    } else {
        nextWrapX = layout.width
    }

    switch align {
    case .left:
        return origin.x
    case .center:
        return origin.x + (width - (nextWrapX - x)).half()
    case .right:
        return origin.x + (width - (nextWrapX - x))
    }
}

@MainActor
public func paintLine(
    origin: Point<Pixels>,
    layout: LineLayout,
    lineHeight: Pixels,
    align: TextAlign,
    alignWidth: Pixels?,
    decorationRuns: [DecorationRun],
    wrapBoundaries: [WrapBoundary],
    window: inout Window,
    cx: App
) throws {
    let lineBounds = Bounds(
        origin: origin,
        size: Size(
            width: layout.width,
            height: lineHeight * Float(wrapBoundaries.count + 1)
        )
    )
    _ = lineBounds

    let padding_top = (lineHeight - layout.ascent - layout.descent) / Float(2.0)
    let baseline_offset = Point(x: px(0), y: padding_top + layout.ascent)
    var decorationRunIndex = 0
    var wrapIndex = 0
    var runEnd = 0
    var color = black()
    var currentUnderline: (Point<Pixels>, UnderlineStyle)? = nil
    var currentStrikethrough: (Point<Pixels>, StrikethroughStyle)? = nil
    let textSystem = cx.textSystem()

    var glyphOrigin = Point(
        x: alignedOriginX(
            origin: origin,
            width: alignWidth ?? layout.width,
            x: px(0),
            align: align,
            layout: layout,
            nextWrap: wrapIndex < wrapBoundaries.count ? wrapBoundaries[wrapIndex] : nil
        ),
        y: origin.y
    )
    var prevGlyphPosition = Point<Pixels>.zero
    var maxGlyphSize = Size<Pixels>(width: px(0), height: px(0))
    var firstGlyphX = origin.x

    for (runIx, run) in layout.runs.enumerated() {
        maxGlyphSize = textSystem.boundingBox(fontId: run.fontId, fontSize: layout.fontSize).size

        for (glyphIx, glyph) in run.glyphs.enumerated() {
            glyphOrigin.x += glyph.position.x - prevGlyphPosition.x
            if glyphIx == 0 && runIx == 0 {
                firstGlyphX = glyphOrigin.x
            }

            if wrapIndex < wrapBoundaries.count && wrapBoundaries[wrapIndex] == WrapBoundary(runIx: runIx, glyphIx: glyphIx) {
                wrapIndex += 1
                if let (origin, underlineStyle) = currentUnderline {
                    var underlineOrigin = origin
                    if glyphOrigin.x == underlineOrigin.x {
                        underlineOrigin.x -= maxGlyphSize.width.half()
                    }
                    window.paintUnderline(
                        origin: underlineOrigin,
                        width: glyphOrigin.x - underlineOrigin.x,
                        style: underlineStyle
                    )
                    if glyph.index < runEnd {
                        underlineOrigin.x = origin.x
                        underlineOrigin.y += lineHeight
                        currentUnderline = (underlineOrigin, underlineStyle)
                    } else {
                        currentUnderline = nil
                    }
                }
                if let (origin, strikethroughStyle) = currentStrikethrough {
                    var strikethroughOrigin = origin
                    if glyphOrigin.x == strikethroughOrigin.x {
                        strikethroughOrigin.x -= maxGlyphSize.width.half()
                    }
                    window.paintStrikethrough(
                        origin: strikethroughOrigin,
                        width: glyphOrigin.x - strikethroughOrigin.x,
                        style: strikethroughStyle
                    )
                    if glyph.index < runEnd {
                        strikethroughOrigin.x = origin.x
                        strikethroughOrigin.y += lineHeight
                        currentStrikethrough = (strikethroughOrigin, strikethroughStyle)
                    } else {
                        currentStrikethrough = nil
                    }
                }

                glyphOrigin.x = alignedOriginX(
                    origin: origin,
                    width: alignWidth ?? layout.width,
                    x: glyph.position.x,
                    align: align,
                    layout: layout,
                    nextWrap: wrapIndex < wrapBoundaries.count ? wrapBoundaries[wrapIndex] : nil
                )
                glyphOrigin.y += lineHeight
            }
            prevGlyphPosition = glyph.position

            var finishedUnderline: (Point<Pixels>, UnderlineStyle)? = nil
            var finishedStrikethrough: (Point<Pixels>, StrikethroughStyle)? = nil
            if glyph.index >= runEnd {
                var styleRun = decorationRunIndex < decorationRuns.count ? decorationRuns[decorationRunIndex] : nil
                if styleRun != nil { decorationRunIndex += 1 }

                while let r = styleRun {
                    if glyph.index < runEnd + Int(r.len) {
                        break
                    }
                    runEnd += Int(r.len)
                    styleRun = decorationRunIndex < decorationRuns.count ? decorationRuns[decorationRunIndex] : nil
                    if styleRun != nil { decorationRunIndex += 1 }
                }

                if let styleRun = styleRun {
                    if let (_, uStyle) = currentUnderline, styleRun.underline != uStyle {
                        finishedUnderline = currentUnderline
                        currentUnderline = nil
                    }
                    if let runUnderline = styleRun.underline {
                        if currentUnderline == nil {
                            currentUnderline = (
                                Point(
                                    x: glyphOrigin.x,
                                    y: glyphOrigin.y + baseline_offset.y + (layout.descent * 0.618)
                                ),
                                UnderlineStyle(
                                    thickness: runUnderline.thickness,
                                    color: runUnderline.color ?? styleRun.color,
                                    wavy: runUnderline.wavy
                                )
                            )
                        }
                    }
                    if let (_, sStyle) = currentStrikethrough, styleRun.strikethrough != sStyle {
                        finishedStrikethrough = currentStrikethrough
                        currentStrikethrough = nil
                    }
                    if let runStrikethrough = styleRun.strikethrough {
                        if currentStrikethrough == nil {
                            currentStrikethrough = (
                                Point(
                                    x: glyphOrigin.x,
                                    y: glyphOrigin.y + (((layout.ascent * 0.5) + baseline_offset.y) * 0.5)
                                ),
                                StrikethroughStyle(
                                    thickness: runStrikethrough.thickness,
                                    color: runStrikethrough.color ?? styleRun.color
                                )
                            )
                        }
                    }

                    runEnd += Int(styleRun.len)
                    color = styleRun.color
                } else {
                    runEnd = layout.len
                    finishedUnderline = currentUnderline
                    currentUnderline = nil
                    finishedStrikethrough = currentStrikethrough
                    currentStrikethrough = nil
                }
            }

            if let (origin, underlineStyle) = finishedUnderline {
                var underlineOrigin = origin
                if underlineOrigin.x == glyphOrigin.x {
                    underlineOrigin.x -= maxGlyphSize.width.half()
                }
                window.paintUnderline(
                    origin: underlineOrigin,
                    width: glyphOrigin.x - underlineOrigin.x,
                    style: underlineStyle
                )
            }

            if let (origin, strikethroughStyle) = finishedStrikethrough {
                var strikethroughOrigin = origin
                if strikethroughOrigin.x == glyphOrigin.x {
                    strikethroughOrigin.x -= maxGlyphSize.width.half()
                }
                window.paintStrikethrough(
                    origin: strikethroughOrigin,
                    width: glyphOrigin.x - strikethroughOrigin.x,
                    style: strikethroughStyle
                )
            }

            let maxGlyphBounds = Bounds(origin: glyphOrigin, size: maxGlyphSize)
            let contentMask = window.contentMask()
            if maxGlyphBounds.intersects(contentMask.bounds) {
                let verticalOffset = Point(x: px(0), y: glyph.position.y)
                if glyph.isEmoji {
                    try window.paintEmoji(
                        origin: glyphOrigin + baseline_offset + verticalOffset,
                        fontId: run.fontId,
                        glyphId: glyph.id,
                        fontSize: layout.fontSize
                    )
                } else {
                    try window.paintGlyph(
                        origin: glyphOrigin + baseline_offset + verticalOffset,
                        fontId: run.fontId,
                        glyphId: glyph.id,
                        fontSize: layout.fontSize,
                        color: color
                    )
                }
            }
        }
    }

    var lastLineEndX = firstGlyphX + layout.width
    if let boundary = wrapBoundaries.last, boundary.runIx < layout.runs.count, boundary.glyphIx < layout.runs[boundary.runIx].glyphs.count {
        let run = layout.runs[boundary.runIx]
        let glyph = run.glyphs[boundary.glyphIx]
        lastLineEndX -= glyph.position.x
    }

    if let (start, underlineStyle) = currentUnderline {
        var underlineStart = start
        if lastLineEndX == underlineStart.x {
            underlineStart.x -= maxGlyphSize.width.half()
        }
        window.paintUnderline(
            origin: underlineStart,
            width: lastLineEndX - underlineStart.x,
            style: underlineStyle
        )
    }

    if let (start, strikethroughStyle) = currentStrikethrough {
        var strikethroughStart = start
        if lastLineEndX == strikethroughStart.x {
            strikethroughStart.x -= maxGlyphSize.width.half()
        }
        window.paintStrikethrough(
            origin: strikethroughStart,
            width: lastLineEndX - strikethroughStart.x,
            style: strikethroughStyle
        )
    }
}

@MainActor
public func paintLineBackground(
    origin: Point<Pixels>,
    layout: LineLayout,
    lineHeight: Pixels,
    align: TextAlign,
    alignWidth: Pixels?,
    decorationRuns: [DecorationRun],
    wrapBoundaries: [WrapBoundary],
    window: inout Window,
    cx: App
) {
    var decorationRunIndex = 0
    var wrapIndex = 0
    var runEnd = 0
    var backgroundColor: Hsla? = nil
    var glyphOrigin = Point(
        x: alignedOriginX(
            origin: origin,
            width: alignWidth ?? layout.width,
            x: px(0),
            align: align,
            layout: layout,
            nextWrap: wrapIndex < wrapBoundaries.count ? wrapBoundaries[wrapIndex] : nil
        ),
        y: origin.y
    )
    var prevGlyphPosition = Point<Pixels>.zero
    var currentBackground: Bounds<Pixels>? = nil
    var firstGlyphX = origin.x

    for (runIx, run) in layout.runs.enumerated() {
        for (glyphIx, glyph) in run.glyphs.enumerated() {
            glyphOrigin.x += glyph.position.x - prevGlyphPosition.x
            if glyphIx == 0 && runIx == 0 {
                firstGlyphX = glyphOrigin.x
            }

            if wrapIndex < wrapBoundaries.count && wrapBoundaries[wrapIndex] == WrapBoundary(runIx: runIx, glyphIx: glyphIx) {
                wrapIndex += 1
                if let bg = backgroundColor, var backgroundBounds = currentBackground {
                    backgroundBounds.size.width = glyphOrigin.x - backgroundBounds.origin.x
                    window.paintQuad(fill(bounds: backgroundBounds, color: bg))
                    currentBackground = Bounds(
                        origin: Point(x: origin.x, y: glyphOrigin.y + lineHeight),
                        size: Size(width: px(0), height: lineHeight)
                    )
                }

                glyphOrigin.x = alignedOriginX(
                    origin: origin,
                    width: alignWidth ?? layout.width,
                    x: glyph.position.x,
                    align: align,
                    layout: layout,
                    nextWrap: wrapIndex < wrapBoundaries.count ? wrapBoundaries[wrapIndex] : nil
                )
                glyphOrigin.y += lineHeight
            }
            prevGlyphPosition = glyph.position

            var finishedBackground: Bounds<Pixels>? = nil
            if glyph.index >= runEnd {
                var styleRun = decorationRunIndex < decorationRuns.count ? decorationRuns[decorationRunIndex] : nil
                if styleRun != nil { decorationRunIndex += 1 }

                while let r = styleRun {
                    if glyph.index < runEnd + Int(r.len) {
                        break
                    }
                    runEnd += Int(r.len)
                    styleRun = decorationRunIndex < decorationRuns.count ? decorationRuns[decorationRunIndex] : nil
                    if styleRun != nil { decorationRunIndex += 1 }
                }

                if let styleRun = styleRun {
                    if styleRun.backgroundColor != backgroundColor {
                        finishedBackground = currentBackground
                        currentBackground = nil
                    }
                    if styleRun.backgroundColor != nil {
                        if currentBackground == nil {
                            currentBackground = Bounds(
                                origin: Point(x: glyphOrigin.x, y: glyphOrigin.y),
                                size: Size(width: px(0), height: lineHeight)
                            )
                        }
                    }
                    runEnd += Int(styleRun.len)
                    backgroundColor = styleRun.backgroundColor
                } else {
                    runEnd = layout.len
                    finishedBackground = currentBackground
                    currentBackground = nil
                }
            }

            if let bg = backgroundColor, var backgroundBounds = finishedBackground {
                backgroundBounds.size.width = glyphOrigin.x - backgroundBounds.origin.x
                window.paintQuad(fill(bounds: backgroundBounds, color: bg))
            }
        }
    }

    var lastLineEndX = firstGlyphX + layout.width
    if let boundary = wrapBoundaries.last, boundary.runIx < layout.runs.count, boundary.glyphIx < layout.runs[boundary.runIx].glyphs.count {
        let run = layout.runs[boundary.runIx]
        let glyph = run.glyphs[boundary.glyphIx]
        lastLineEndX -= glyph.position.x
    }

    if let bg = backgroundColor, var backgroundBounds = currentBackground {
        backgroundBounds.size.width = lastLineEndX - backgroundBounds.origin.x
        window.paintQuad(fill(bounds: backgroundBounds, color: bg))
    }
}
