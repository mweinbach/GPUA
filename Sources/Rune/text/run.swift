// Ported from: crates/rune/src/text/run.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Run`: a string that several text cells each show one grapheme of, shaped once as a line.

/// A string that several text cells each show one grapheme of (`El.advanceIn`), hashed once so
/// cells and frames can look up its shaped layout without rehashing it.
// PORT NOTE: Immutable reference type matching upstream `Run { text: Rc<str>, hash: u64 }`; safe
// to share across threads because all stored properties are `let` value types.
public final class Run: @unchecked Sendable, Equatable {
    public let text: String
    let hash: UInt64
    public let style: TextStyle?

    public init(_ text: String) {
        self.text = text
        self.hash = runHash(text)
        self.style = nil
    }

    public init(_ text: String, _ style: TextStyle) {
        self.text = text
        self.hash = runHash(text)
        self.style = style
    }

    public static func new(_ text: String) -> Run {
        Run(text)
    }

    public func asStr() -> String {
        text
    }

    func key(_ style: TextStyle, _ scale: Float) -> UInt64 {
        runKey(hash, style, scale)
    }

    public static func == (lhs: Run, rhs: Run) -> Bool {
        lhs.hash == rhs.hash && lhs.text == rhs.text && lhs.style == rhs.style
    }
}

struct RunFace: Sendable {
    var font: ShapedFontFace
    var size: Float
    var ink: UInt16
    var baseline: Float
}

struct RunGlyph: Sendable, Equatable {
    var face: UInt16
    var id: UInt16
    /// From the layout's left edge and its line's baseline (device px).
    var x: Float
    var y: Float
}

/// A `Run` shaped as one line, with each grapheme's offset and glyphs.
public struct RunLayout: Sendable, Equatable {
    public var layout: TextLayout?
    public var width: Float
    public var height: Float
    /// Per grapheme: `(byte, x on 1/64 px grid, firstGlyph)`; then `(len, ceil(fullWidth), glyphCount)`.
    var graphemes: [(UInt32, Float, UInt32)]
    var faces: [RunFace]
    var glyphs: [RunGlyph]

    public init(width: Float = 0, height: Float = 0) {
        self.layout = nil
        self.width = width
        self.height = height
        self.graphemes = []
        self.faces = []
        self.glyphs = []
    }

    init(
        layout: TextLayout,
        width: Float,
        height: Float,
        graphemes: [(UInt32, Float, UInt32)],
        faces: [RunFace],
        glyphs: [RunGlyph]
    ) {
        self.layout = layout
        self.width = width
        self.height = height
        self.graphemes = graphemes
        self.faces = faces
        self.glyphs = glyphs
    }

    public static func == (lhs: RunLayout, rhs: RunLayout) -> Bool {
        guard lhs.width == rhs.width,
              lhs.height == rhs.height,
              lhs.graphemes.count == rhs.graphemes.count,
              lhs.glyphs == rhs.glyphs
        else {
            return false
        }
        for (a, b) in zip(lhs.graphemes, rhs.graphemes) where a.0 != b.0 || a.1 != b.1 || a.2 != b.2 {
            return false
        }
        return lhs.layout === rhs.layout
    }

    static func new(_ layout: TextLayout, _ text: String) -> RunLayout {
        // Swift `Character` iteration follows Unicode UAX #29 extended grapheme clusters,
        // matching `unicode_segmentation::UnicodeSegmentation::grapheme_indices(true)`.
        var starts: [UInt32] = []
        starts.reserveCapacity(text.count)
        var byteCursor = 0
        for ch in text {
            starts.append(UInt32(byteCursor))
            byteCursor += ch.utf8.count
        }

        func graphemeOf(_ byte: UInt32) -> Int {
            var lo = 0
            var hi = starts.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if starts[mid] <= byte {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            return max(lo - 1, 0)
        }

        var xs = [Float](repeating: .infinity, count: starts.count)
        var faces: [RunFace] = []
        var taggedGlyphs: [(Int, RunGlyph)] = []

        for line in layout.lines() {
            let inlineMin = line.metrics().inlineMinCoord
            for item in line.items() {
                guard case .glyphRun(let glyphRun) = item else { continue }
                faces.append(RunFace(
                    font: glyphRun.font,
                    size: glyphRun.fontSize,
                    ink: glyphRun.ink.rawValue,
                    baseline: glyphRun.baseline()
                ))
                let faceIdx = UInt16(faces.count - 1)

                var x = glyphRun.offset()
                for cl in glyphRun.visualClusters() {
                    let gi = graphemeOf(UInt32(cl.textRange.lowerBound))
                    if gi < xs.count {
                        xs[gi] = min(xs[gi], x)
                    }
                    x += cl.advance
                }

                // Glyphs carry `textByteOffset` from the cluster they were shaped in, so a
                // zero-advance combining mark stays with its base grapheme.
                var rel = glyphRun.offset()
                for g in glyphRun.glyphs() {
                    let gi = starts.isEmpty ? 0 : graphemeOf(g.textByteOffset)
                    taggedGlyphs.append((gi, RunGlyph(
                        face: faceIdx,
                        id: g.id,
                        x: rel + g.x,
                        y: g.y
                    )))
                    rel += g.advance
                    _ = inlineMin
                }
            }
        }

        // Stable sort by grapheme index preserves glyph drawing order within each grapheme.
        if taggedGlyphs.count > 1 {
            var indexed = taggedGlyphs.enumerated().map { ($0.element.0, $0.offset, $0.element.1) }
            indexed.sort { a, b in
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1 < b.1
            }
            taggedGlyphs = indexed.map { ($0.0, $0.2) }
        }

        var graphemes: [(UInt32, Float, UInt32)] = []
        graphemes.reserveCapacity(starts.count + 1)
        var prev: Float = 0.0
        for (i, start) in starts.enumerated() {
            let x = xs[i].isFinite ? xs[i] : prev
            prev = x
            var lo = 0
            var hi = taggedGlyphs.count
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                if taggedGlyphs[mid].0 < i {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            let snapped = (x * 64.0).rounded(.toNearestOrAwayFromZero) / 64.0
            graphemes.append((start, snapped, UInt32(lo)))
        }
        let endX = max(0.0, (layout.fullWidth() - 1e-3).rounded(.up))
        graphemes.append((UInt32(text.utf8.count), endX, UInt32(taggedGlyphs.count)))

        return RunLayout(
            layout: layout,
            width: layout.fullWidth(),
            height: layout.height(),
            graphemes: graphemes,
            faces: faces,
            glyphs: taggedGlyphs.map(\.1)
        )
    }

    /// The index of the grapheme starting at byte `at` (never the end sentinel).
    func grapheme(_ at: Int) -> Int? {
        guard at >= 0, graphemes.count >= 2 else { return nil }
        let target = UInt32(at)
        var lo = 0
        var hi = graphemes.count - 1
        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            let val = graphemes[mid].0
            if val == target {
                return (mid + 1 < graphemes.count) ? mid : nil
            } else if val < target {
                lo = mid + 1
            } else {
                if mid == 0 { break }
                hi = mid - 1
            }
        }
        return nil
    }

    /// The x (device px) of the grapheme at byte `at`.
    public func x(_ at: Int) -> Float? {
        guard let i = grapheme(at) else { return nil }
        return graphemes[i].1
    }

    /// Width in points of the grapheme at byte `at`: the gap to the next grapheme, or for the
    /// last to the run's end rounded up as `TextSystem.measure` does, so cells measured this way
    /// keep the run's kerning and sum to its measured width.
    public func advance(_ at: Int, _ scale: Float) -> Float? {
        guard let i = grapheme(at), scale > 0.0 else { return nil }
        return max(0.0, (graphemes[i + 1].1 - graphemes[i].1) / scale)
    }
}

extension TextSystem {
    /// `run` shaped as one line in `style`, cached as `endCommit` keeps layouts.
    public func runLayout(_ run: Run, _ style: TextStyle, _ scale: Float) -> RunLayout {
        let k = run.key(style, scale)
        let g = generation
        if var hit = runs[k] {
            hit.used = g
            runs[k] = hit
            return hit.value
        }
        let s = run.asStr()
        let r = RunLayout.new(layoutRich(s, [], style, scale, nil), s)
        runs[k] = LayoutCacheEntry(value: r, used: g, textLen: s.utf8.count, shape: 0)
        return r
    }
}
