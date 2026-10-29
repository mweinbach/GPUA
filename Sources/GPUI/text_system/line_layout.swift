// Ported from: crates/gpui/src/text_system/line_layout.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

// PORT NOTE: Int conforms to Error so Result<Int, Int> mirrors Rust's Result<usize, usize> for position indexing.
extension Int: @retroactive Error {}

// PORT NOTE: LineLayout is initialized during line shaping and treated as immutable thereafter.
public final class LineLayout: @unchecked Sendable, CustomDebugStringConvertible {
    /// The font size for this line.
    public var fontSize: Pixels
    /// The width of the line.
    public var width: Pixels
    /// The ascent of the line.
    public var ascent: Pixels
    /// The descent of the line.
    public var descent: Pixels
    /// The shaped runs that make up this line.
    public var runs: [ShapedRun]
    /// The length of the line in utf-8 bytes.
    public var len: Int

    public init(
        fontSize: Pixels = .zero,
        width: Pixels = .zero,
        ascent: Pixels = .zero,
        descent: Pixels = .zero,
        runs: [ShapedRun] = [],
        len: Int = 0
    ) {
        self.fontSize = fontSize
        self.width = width
        self.ascent = ascent
        self.descent = descent
        self.runs = runs
        self.len = len
    }

    public var debugDescription: String {
        "LineLayout(width: \(width), ascent: \(ascent), descent: \(descent), runs: \(runs.count), len: \(len))"
    }

    /// The index for the character at the given x coordinate.
    public func indexForX(_ x: Pixels) -> Int? {
        if x >= width {
            return nil
        }
        for run in runs.reversed() {
            for glyph in run.glyphs.reversed() {
                if glyph.position.x <= x {
                    return glyph.index
                }
            }
        }
        return 0
    }

    /// Returns the character boundary closest to the given x coordinate.
    public func closestIndexForX(_ x: Pixels) -> Int {
        var prevIndex = 0
        var prevX = px(0)

        for run in runs {
            for glyph in run.glyphs {
                if glyph.position.x >= x {
                    if glyph.position.x - x < x - prevX {
                        return glyph.index
                    } else {
                        return prevIndex
                    }
                }
                prevIndex = glyph.index
                prevX = glyph.position.x
            }
        }

        if len == 1 {
            if x > width / 2.0 {
                return 1
            } else {
                return 0
            }
        }

        return len
    }

    /// The x position of the character at the given index.
    public func xForIndex(_ index: Int) -> Pixels {
        for run in runs {
            for glyph in run.glyphs {
                if glyph.index >= index {
                    return glyph.position.x
                }
            }
        }
        return width
    }

    /// The corresponding Font at the given index.
    public func fontIdForIndex(_ index: Int) -> FontId? {
        for run in runs {
            for glyph in run.glyphs {
                if glyph.index >= index {
                    return run.fontId
                }
            }
        }
        return nil
    }

    public func computeWrapBoundaries(
        text: String,
        wrapWidth: Pixels,
        maxLines: Int?
    ) -> [WrapBoundary] {
        var boundaries: [WrapBoundary] = []
        var firstNonWhitespaceIx: WrapBoundary? = nil
        var lastCandidateIx: WrapBoundary? = nil
        var lastCandidateX = px(0)
        var lastBoundary = WrapBoundary(runIx: 0, glyphIx: 0)
        var lastBoundaryX = px(0)
        var prevCh: Character = "\0"

        struct GlyphItem {
            var boundary: WrapBoundary
            var character: Character
            var x: Pixels
        }

        var glyphList: [GlyphItem] = []
        let utf8View = text.utf8
        for (runIx, run) in runs.enumerated() {
            for (glyphIx, glyph) in run.glyphs.enumerated() {
                let char: Character
                if glyph.index < utf8View.count {
                    let utf8Idx = utf8View.index(utf8View.startIndex, offsetBy: glyph.index)
                    if let strIdx = String.Index(utf8Idx, within: text) {
                        char = text[strIdx]
                    } else {
                        char = " "
                    }
                } else {
                    char = " "
                }
                glyphList.append(GlyphItem(
                    boundary: WrapBoundary(runIx: runIx, glyphIx: glyphIx),
                    character: char,
                    x: glyph.position.x
                ))
            }
        }

        var i = 0
        while i < glyphList.count {
            let item = glyphList[i]
            let boundary = item.boundary
            let ch = item.character
            let x = item.x
            i += 1

            if ch == "\n" {
                continue
            }

            if LineWrapper.isWordChar(ch) {
                if prevCh == " " && ch != " " && firstNonWhitespaceIx != nil {
                    lastCandidateIx = boundary
                    lastCandidateX = x
                }
            } else {
                if ch != " " && firstNonWhitespaceIx != nil {
                    lastCandidateIx = boundary
                    lastCandidateX = x
                }
            }

            if ch != " " && firstNonWhitespaceIx == nil {
                firstNonWhitespaceIx = boundary
            }

            let nextX = (i < glyphList.count) ? glyphList[i].x : width
            let lineWidth = nextX - lastBoundaryX

            if lineWidth > wrapWidth && boundary > lastBoundary {
                if let max = maxLines, boundaries.count >= max - 1 {
                    break
                }

                if let cand = lastCandidateIx {
                    lastBoundary = cand
                    lastBoundaryX = lastCandidateX
                    lastCandidateIx = nil
                } else {
                    lastBoundary = boundary
                    lastBoundaryX = x
                }
                boundaries.append(lastBoundary)
            }
            prevCh = ch
        }

        return boundaries
    }
}

/// A run of text that has been shaped.
public struct ShapedRun: Sendable, Equatable {
    /// The font id for this run.
    public var fontId: FontId
    /// The glyphs that make up this run.
    public var glyphs: [ShapedGlyph]

    public init(fontId: FontId, glyphs: [ShapedGlyph] = []) {
        self.fontId = fontId
        self.glyphs = glyphs
    }
}

/// A single glyph, ready to paint.
public struct ShapedGlyph: Sendable, Equatable {
    /// The ID for this glyph, as determined by the text system.
    public var id: GlyphId
    /// The position of this glyph in its containing line.
    public var position: Point<Pixels>
    /// The index of this glyph in the original text.
    public var index: Int
    /// Whether this glyph is an emoji.
    public var isEmoji: Bool

    public init(
        id: GlyphId,
        position: Point<Pixels>,
        index: Int,
        isEmoji: Bool = false
    ) {
        self.id = id
        self.position = position
        self.index = index
        self.isEmoji = isEmoji
    }
}

/// A run of text with a single font.
public struct FontRun: Sendable, Equatable, Hashable {
    public var len: Int
    public var fontId: FontId

    public init(len: Int, fontId: FontId) {
        self.len = len
        self.fontId = fontId
    }
}

/// A boundary at which a line was wrapped.
public struct WrapBoundary: Sendable, Equatable, Hashable, Comparable {
    /// The index in the run just before the line was wrapped.
    public var runIx: Int
    /// The index of the glyph just before the line was wrapped.
    public var glyphIx: Int

    public init(runIx: Int, glyphIx: Int) {
        self.runIx = runIx
        self.glyphIx = glyphIx
    }

    public static func < (lhs: WrapBoundary, rhs: WrapBoundary) -> Bool {
        if lhs.runIx != rhs.runIx {
            return lhs.runIx < rhs.runIx
        }
        return lhs.glyphIx < rhs.glyphIx
    }
}

// PORT NOTE: WrappedLineLayout is initialized during line wrapping and treated as immutable thereafter.
public final class WrappedLineLayout: @unchecked Sendable {
    /// The line layout, pre-wrapping.
    public var unwrappedLayout: LineLayout
    /// The boundaries at which the line was wrapped.
    public var wrapBoundaries: [WrapBoundary]
    /// The width of the line, if it was wrapped.
    public var wrapWidth: Pixels?

    public init(
        unwrappedLayout: LineLayout,
        wrapBoundaries: [WrapBoundary] = [],
        wrapWidth: Pixels? = nil
    ) {
        self.unwrappedLayout = unwrappedLayout
        self.wrapBoundaries = wrapBoundaries
        self.wrapWidth = wrapWidth
    }

    public func len() -> Int {
        unwrappedLayout.len
    }

    public func width() -> Pixels {
        min(wrapWidth ?? Pixels.max, unwrappedLayout.width)
    }

    public func size(lineHeight: Pixels) -> Size<Pixels> {
        Size(
            width: width(),
            height: lineHeight * Float(wrapBoundaries.count + 1)
        )
    }

    public func ascent() -> Pixels {
        unwrappedLayout.ascent
    }

    public func descent() -> Pixels {
        unwrappedLayout.descent
    }

    public func fontSize() -> Pixels {
        unwrappedLayout.fontSize
    }

    public func runs() -> [ShapedRun] {
        unwrappedLayout.runs
    }

    public func indexForPosition(_ position: Point<Pixels>, lineHeight: Pixels) -> Result<Int, Int> {
        _indexForPosition(position, lineHeight: lineHeight, closest: false)
    }

    public func closestIndexForPosition(_ position: Point<Pixels>, lineHeight: Pixels) -> Result<Int, Int> {
        _indexForPosition(position, lineHeight: lineHeight, closest: true)
    }

    private func _indexForPosition(_ position: Point<Pixels>, lineHeight: Pixels, closest: Bool) -> Result<Int, Int> {
        guard lineHeight > px(0) else { return .failure(0) }
        let wrappedLineIx = max(0, Int(position.y / lineHeight))

        let wrappedLineStartIndex: Int
        let wrappedLineStartX: Pixels
        if wrappedLineIx > 0 {
            guard let lineStartBoundary = wrapBoundaries[safe: wrappedLineIx - 1] else {
                return .failure(0)
            }
            let run = unwrappedLayout.runs[lineStartBoundary.runIx]
            let glyph = run.glyphs[lineStartBoundary.glyphIx]
            wrappedLineStartIndex = glyph.index
            wrappedLineStartX = glyph.position.x
        } else {
            wrappedLineStartIndex = 0
            wrappedLineStartX = .zero
        }

        let wrappedLineEndIndex: Int
        let wrappedLineEndX: Pixels
        if wrappedLineIx < wrapBoundaries.count {
            let nextBoundary = wrapBoundaries[wrappedLineIx]
            let run = unwrappedLayout.runs[nextBoundary.runIx]
            let glyph = run.glyphs[nextBoundary.glyphIx]
            wrappedLineEndIndex = glyph.index
            wrappedLineEndX = glyph.position.x
        } else {
            wrappedLineEndIndex = unwrappedLayout.len
            wrappedLineEndX = unwrappedLayout.width
        }

        var positionInUnwrappedLine = position
        positionInUnwrappedLine.x += wrappedLineStartX

        if positionInUnwrappedLine.x < wrappedLineStartX {
            return .failure(wrappedLineStartIndex)
        } else if positionInUnwrappedLine.x >= wrappedLineEndX {
            return .failure(wrappedLineEndIndex)
        } else {
            if closest {
                return .success(unwrappedLayout.closestIndexForX(positionInUnwrappedLine.x))
            } else {
                return .success(unwrappedLayout.indexForX(positionInUnwrappedLine.x) ?? 0)
            }
        }
    }

    public func positionForIndex(_ index: Int, lineHeight: Pixels) -> Point<Pixels>? {
        var lineStartIx = 0
        var lineEndIndices: [(Int, Int)] = []
        for (ix, b) in wrapBoundaries.enumerated() {
            let run = unwrappedLayout.runs[b.runIx]
            let glyph = run.glyphs[b.glyphIx]
            lineEndIndices.append((ix, glyph.index))
        }
        lineEndIndices.append((wrapBoundaries.count, len()))

        for (ix, lineEndIx) in lineEndIndices {
            let lineY = Float(ix) * lineHeight
            if index < lineStartIx {
                break
            } else if index > lineEndIx {
                lineStartIx = lineEndIx
                continue
            } else {
                let lineStartX = unwrappedLayout.xForIndex(lineStartIx)
                let x = unwrappedLayout.xForIndex(index) - lineStartX
                return Point(x: x, y: lineY)
            }
        }

        return nil
    }
}

extension Array {
    fileprivate subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public struct LineLayoutIndex: Sendable, Equatable, Hashable, DefaultInitializable, Comparable {
    public var linesIndex: Int
    public var wrappedLinesIndex: Int

    public init() {
        self.linesIndex = 0
        self.wrappedLinesIndex = 0
    }

    public init(linesIndex: Int = 0, wrappedLinesIndex: Int = 0) {
        self.linesIndex = linesIndex
        self.wrappedLinesIndex = wrappedLinesIndex
    }

    public static func < (lhs: LineLayoutIndex, rhs: LineLayoutIndex) -> Bool {
        if lhs.linesIndex != rhs.linesIndex {
            return lhs.linesIndex < rhs.linesIndex
        }
        return lhs.wrappedLinesIndex < rhs.wrappedLinesIndex
    }
}

private struct CacheKey: Hashable, Equatable {
    var text: String
    var fontSize: Pixels
    var runs: [FontRun]
    var wrapWidth: Pixels?
    var forceWidth: Pixels?
}

private struct FrameCache {
    var lines: [CacheKey: LineLayout] = [:]
    var wrappedLines: [CacheKey: WrappedLineLayout] = [:]
    var usedLines: [CacheKey] = []
    var usedWrappedLines: [CacheKey] = []
}

// PORT NOTE: LineLayoutCache uses NSLock to synchronize access to previousFrame and currentFrame across render frames.
public final class LineLayoutCache: @unchecked Sendable {
    private let lock = NSLock()
    private var previousFrame = FrameCache()
    private var currentFrame = FrameCache()
    public let platformTextSystem: any PlatformTextSystem

    public init(platformTextSystem: any PlatformTextSystem) {
        self.platformTextSystem = platformTextSystem
    }

    public static func new(platformTextSystem: any PlatformTextSystem) -> LineLayoutCache {
        LineLayoutCache(platformTextSystem: platformTextSystem)
    }

    public func layoutIndex() -> LineLayoutIndex {
        lock.lock()
        defer { lock.unlock() }
        return LineLayoutIndex(
            linesIndex: currentFrame.usedLines.count,
            wrappedLinesIndex: currentFrame.usedWrappedLines.count
        )
    }

    public func reuseLayouts(_ range: Range<LineLayoutIndex>) {
        lock.lock()
        defer { lock.unlock() }

        let startL = min(range.lowerBound.linesIndex, previousFrame.usedLines.count)
        let endL = min(range.upperBound.linesIndex, previousFrame.usedLines.count)
        if startL < endL {
            for key in previousFrame.usedLines[startL..<endL] {
                if let line = previousFrame.lines.removeValue(forKey: key) {
                    currentFrame.lines[key] = line
                }
                currentFrame.usedLines.append(key)
            }
        }

        let startW = min(range.lowerBound.wrappedLinesIndex, previousFrame.usedWrappedLines.count)
        let endW = min(range.upperBound.wrappedLinesIndex, previousFrame.usedWrappedLines.count)
        if startW < endW {
            for key in previousFrame.usedWrappedLines[startW..<endW] {
                if let line = previousFrame.wrappedLines.removeValue(forKey: key) {
                    currentFrame.wrappedLines[key] = line
                }
                currentFrame.usedWrappedLines.append(key)
            }
        }
    }

    public func truncateLayouts(_ index: LineLayoutIndex) {
        lock.lock()
        defer { lock.unlock() }
        if index.linesIndex < currentFrame.usedLines.count {
            currentFrame.usedLines.removeSubrange(index.linesIndex...)
        }
        if index.wrappedLinesIndex < currentFrame.usedWrappedLines.count {
            currentFrame.usedWrappedLines.removeSubrange(index.wrappedLinesIndex...)
        }
    }

    public func finishFrame() {
        lock.lock()
        defer { lock.unlock() }
        previousFrame = currentFrame
        currentFrame = FrameCache()
    }

    public func layoutWrappedLine(
        text: String,
        fontSize: Pixels,
        runs: [FontRun],
        wrapWidth: Pixels? = nil,
        maxLines: Int? = nil
    ) -> WrappedLineLayout {
        let key = CacheKey(
            text: text,
            fontSize: fontSize,
            runs: runs,
            wrapWidth: wrapWidth,
            forceWidth: nil
        )

        lock.lock()
        if let cached = currentFrame.wrappedLines[key] {
            currentFrame.usedWrappedLines.append(key)
            lock.unlock()
            return cached
        }

        if let cached = previousFrame.wrappedLines.removeValue(forKey: key) {
            currentFrame.wrappedLines[key] = cached
            currentFrame.usedWrappedLines.append(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        let unwrapped = layoutLine(text: text, fontSize: fontSize, runs: runs, forceWidth: nil)
        let boundaries: [WrapBoundary]
        if let wrap = wrapWidth {
            boundaries = unwrapped.computeWrapBoundaries(text: text, wrapWidth: wrap, maxLines: maxLines)
        } else {
            boundaries = []
        }

        let wrapped = WrappedLineLayout(
            unwrappedLayout: unwrapped,
            wrapBoundaries: boundaries,
            wrapWidth: wrapWidth
        )

        lock.lock()
        currentFrame.wrappedLines[key] = wrapped
        currentFrame.usedWrappedLines.append(key)
        lock.unlock()

        return wrapped
    }

    public func layoutLine(
        text: String,
        fontSize: Pixels,
        runs: [FontRun],
        forceWidth: Pixels? = nil
    ) -> LineLayout {
        let key = CacheKey(
            text: text,
            fontSize: fontSize,
            runs: runs,
            wrapWidth: nil,
            forceWidth: forceWidth
        )

        lock.lock()
        if let cached = currentFrame.lines[key] {
            currentFrame.usedLines.append(key)
            lock.unlock()
            return cached
        }

        if let cached = previousFrame.lines.removeValue(forKey: key) {
            currentFrame.lines[key] = cached
            currentFrame.usedLines.append(key)
            lock.unlock()
            return cached
        }
        lock.unlock()

        let layout = platformTextSystem.layoutLine(text: text, fontSize: fontSize, runs: runs)

        if let force = forceWidth {
            var glyphPos: Float = 0
            for rIdx in 0..<layout.runs.count {
                for gIdx in 0..<layout.runs[rIdx].glyphs.count {
                    let targetX = glyphPos * force
                    if abs((layout.runs[rIdx].glyphs[gIdx].position.x - targetX).value) > 1.0 {
                        layout.runs[rIdx].glyphs[gIdx].position.x = targetX
                    }
                    glyphPos += 1.0
                }
            }
        }

        lock.lock()
        currentFrame.lines[key] = layout
        currentFrame.usedLines.append(key)
        lock.unlock()

        return layout
    }
}
