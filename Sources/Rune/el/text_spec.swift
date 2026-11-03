// Ported from: crates/rune/src/el/text_spec.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `TextSpec`: what a text element shows and how it lays out.

/// The part of an overflowing `truncate`d text the ellipsis replaces.
enum Elide: Sendable, Equatable, Hashable {
    /// `El.truncate`: keeps the start.
    case end
    /// `El.truncateMiddle`: keeps the start and the end.
    case middle
    /// `El.truncateHead`: keeps the end.
    case head
}

public struct TextSpec: CustomDebugStringConvertible {
    public var content: String
    public var style: TextStyle
    public var color: Color
    public var align: Align
    public var spans: [Span]
    /// Wrap at the element's width (its height follows the text).
    public var wrap: Bool
    /// Streaming word reveal: words that arrive after mount fade in over this many seconds
    /// (negative: no reveal tracking).
    public var reveal: Float
    /// One line, cut with an ellipsis when wider than the element.
    public var truncate: Bool
    /// Which part `truncate` cuts (see ``El/truncateMiddle()``).
    var elide: Elide
    /// Wrapped lines shown before "…" ends the last (see ``El/maxLines(_:)``); 0 for all.
    public var maxLines: Int
    /// Fade the overflowing trailing edge rather than replacing text with an ellipsis.
    public var truncateFade: Bool
    /// The `truncateFade` edge's width in ems (see ``El/truncateFadeWidth(_:)``).
    public var fadeEm: Float
    /// Spread wrapped lines to fill the width (see ``El/justify()``).
    public var justify: Bool
    /// Plain live run. Layout is measured from the authored placeholder before latching it.
    public var live: LiveText?
    public var links: [Link]
    var onLink: LinkFn?
    var onLinkSecondary: LinkSecondaryFn?
    /// Measured as its slice at this byte of the run (see ``El/advanceIn(_:_:)``).
    public var advanceIn: (Run, Int)?
    /// See ``El/textCase(_:)``; applied when the element is laid out.
    public var textCase: TextCase?
    /// The authored string once `textCase` has replaced `content` with the drawn one.
    var source: TextCaseSource?
    /// See ``El/selectable(_:)``.
    public var selectable: Bool
    /// See ``El/selectionColor(_:)``.
    public var selection: Color
    /// See ``El/uncopied(_:)``: byte ranges of `content`, sorted.
    var uncopied: [(UInt32, UInt32)]
    /// Inset border rings `(start, end, color, width)` on rounded span backgrounds.
    var rings: [(UInt32, UInt32, Color, Float)]
    /// Strikethrough byte ranges `(start, end, color)` of `content`.
    var strikes: [(UInt32, UInt32, Color?)]
    /// Paint-only highlight byte ranges of `content`.
    public var highlights: [TextHighlight]
    /// Per-paragraph `Block` attributes for `content`.
    public var blocks: [Block]
    /// Line indices (`> 0`) created by `Shift+Return` (`<br>`).
    public var softBreaks: [UInt32]
    /// `Mark.pill` chips in `content`, sorted.
    var pills: [PillChip]
    /// See ``El/pillColors(_:_:)``.
    var pillColors: (Color, Color?)?
    /// Visual palette for rich block and inline decorations.
    public var richStyle: RichStyle
    public var redacted: Bool
    public var secureRevealed: Bool
    public var wrapAnywhere: Bool
    /// The scale's bits and shape key at it, once the content is final.
    var shape: (UInt32, UInt64)?

    public init(content: String) {
        self.content = content
        self.style = tok.type_.BODY
        self.color = .WHITE
        self.align = .start
        self.spans = []
        self.wrap = false
        self.reveal = -1.0
        self.truncate = false
        self.elide = .end
        self.maxLines = 0
        self.truncateFade = false
        self.fadeEm = TRUNCATE_FADE_EM
        self.justify = false
        self.live = nil
        self.links = []
        self.onLink = nil
        self.onLinkSecondary = nil
        self.advanceIn = nil
        self.textCase = nil
        self.source = nil
        self.selectable = false
        self.selection = DEFAULT_SELECTION_COLOR
        self.uncopied = []
        self.rings = []
        self.strikes = []
        self.highlights = []
        self.blocks = []
        self.softBreaks = []
        self.pills = []
        self.pillColors = nil
        self.richStyle = RichStyle()
        self.redacted = false
        self.secureRevealed = false
        self.wrapAnywhere = false
        self.shape = nil
    }

    public var debugDescription: String {
        let shownContent = redacted ? "[redacted]" : content
        return "TextSpec(content: \(String(reflecting: shownContent)), style: \(style), color: \(color), align: \(align), spans: \(spans), wrap: \(wrap), reveal: \(reveal), truncate: \(truncate), maxLines: \(maxLines), truncateFade: \(truncateFade), justify: \(justify), selectable: \(selectable))"
    }

    private func computeShapeKey(_ scale: Float) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(spans.count)
        for sp in spans {
            hasher.combine(sp.start)
            hasher.combine(sp.end)
            hasher.combine(sp.weight?.bitPattern)
            hasher.combine(sp.mono)
            hasher.combine(sp.size?.bitPattern)
            hasher.combine(sp.italic)
            hasher.combine(sp.bgPad.bitPattern)
        }
        hasher.combine(style)
        hasher.combine(scale.bitPattern)
        hasher.combine(wrapAnywhere)
        hasher.combine(pills.count)
        for p in pills {
            hasher.combine(p.start)
            hasher.combine(p.end)
            hasher.combine(p.icon != nil)
        }
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }

    /// Hashes what shaping depends on once, so measuring and laying the text out at each width
    /// this commit reuses it. Secure text keeps no content-derived key.
    mutating func keyShape(_ scale: Float) {
        if redacted {
            shape = nil
        } else {
            shape = (scale.bitPattern, computeShapeKey(scale))
        }
    }

    /// The key ``keyShape(_:)`` kept at `scale`.
    func shapeKey(_ scale: Float) -> UInt64? {
        guard let (bits, key) = shape, bits == scale.bitPattern else { return nil }
        assert(key == computeShapeKey(scale), "a text changed after its shape key was taken")
        return key
    }

    /// Replaces the shown string and clears any cached shape key.
    mutating func replaceContent(_ newContent: String) {
        content.removeAll(keepingCapacity: false)
        content = newContent
        shape = nil
    }

    /// The string as authored, before ``El/textCase(_:)``.
    func sourceText() -> String {
        source?.text ?? content
    }

    /// The authored text of `content[start..end]`.
    func sourceSlice(_ start: UInt32, _ end: UInt32) -> String? {
        if let s = source {
            let lo = Int(s.source(start, false))
            let hi = Int(s.source(end, true))
            return utf8Substring(s.text, lo..<hi)
        } else {
            return utf8Substring(content, Int(start)..<Int(end))
        }
    }

    /// The authored text of `content[start..end]` as copying takes it, without its
    /// ``El/uncopied(_:)`` bytes.
    func copySlice(_ start: UInt32, _ end: UInt32) -> String? {
        if redacted {
            return nil
        }
        var out = ""
        var at = start
        for (a, b) in uncopied where b > start && a < end {
            if a > at {
                guard let piece = sourceSlice(at, a) else { return nil }
                out.append(piece)
            }
            at = max(at, b)
        }
        if at < end {
            guard let piece = sourceSlice(at, end) else { return nil }
            out.append(piece)
        }
        return out
    }

    /// Masks `self.content` in place (for layout of a hidden secure label or an exiting revealed one).
    mutating func conceal() {
        guard redacted else { return }
        secureRevealed = false
        shape = nil
        let mask = content.isEmpty ? "" : MULTILINE_SECURE_MASK
        content.removeAll(keepingCapacity: false)
        content = mask
        if var src = source {
            src.text.removeAll(keepingCapacity: false)
        }
        source = nil
        textCase = nil
        spans.removeAll()
        links.removeAll()
        rings.removeAll()
        strikes.removeAll()
        blocks.removeAll()
        softBreaks.removeAll()
        pills.removeAll()
        uncopied.removeAll()
        wrap = false
        wrapAnywhere = false
        maxLines = 0
    }

    /// Replaces `content` (the authored string) with its cased form and moves span and link
    /// ranges onto it.
    mutating func applyCase() {
        shape = nil
        if redacted {
            textCase = nil
            return
        }
        if !rings.isEmpty {
            var splitSpans: [Span] = []
            for span in spans {
                var bounds: [UInt32] = [span.start, span.end]
                for (a, b, _, _) in rings {
                    if span.start < a && a < span.end { bounds.append(a) }
                    if span.start < b && b < span.end { bounds.append(b) }
                }
                bounds.sort()
                var deduped: [UInt32] = []
                for p in bounds where deduped.last != p {
                    deduped.append(p)
                }
                if deduped.count >= 2 {
                    for i in 0..<(deduped.count - 1) {
                        var piece = span
                        piece.start = deduped[i]
                        piece.end = deduped[i + 1]
                        splitSpans.append(piece)
                    }
                }
            }
            spans = splitSpans
        }
        guard let c = textCase else { return }
        let oldContent = content
        content = ""
        let (shown, src) = TextCaseSource.new(c, oldContent)
        for i in spans.indices {
            spans[i].start = src.shown(spans[i].start, false)
            spans[i].end = src.shown(spans[i].end, true)
        }
        for i in links.indices {
            links[i].start = src.shown(links[i].start, false)
            links[i].end = src.shown(links[i].end, true)
        }
        for i in uncopied.indices {
            uncopied[i] = (src.shown(uncopied[i].0, false), src.shown(uncopied[i].1, true))
        }
        for i in rings.indices {
            rings[i].0 = src.shown(rings[i].0, false)
            rings[i].1 = src.shown(rings[i].1, true)
        }
        for i in strikes.indices {
            strikes[i].0 = src.shown(strikes[i].0, false)
            strikes[i].1 = src.shown(strikes[i].1, true)
        }
        for i in highlights.indices {
            highlights[i].start = src.shown(highlights[i].start, false)
            highlights[i].end = src.shown(highlights[i].end, true)
        }
        content = shown
        source = src
    }
}

private func utf8Substring(_ s: String, _ range: Range<Int>) -> String? {
    let utf8 = s.utf8
    guard range.lowerBound >= 0,
          range.upperBound <= utf8.count,
          range.lowerBound <= range.upperBound else {
        return nil
    }
    let startIdx = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
    let endIdx = utf8.index(utf8.startIndex, offsetBy: range.upperBound)
    guard let startScalar = startIdx.samePosition(in: s.unicodeScalars),
          let endScalar = endIdx.samePosition(in: s.unicodeScalars) else {
        return nil
    }
    return String(s.unicodeScalars[startScalar..<endScalar])
}
