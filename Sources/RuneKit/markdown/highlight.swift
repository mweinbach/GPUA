// Ported from: crates/rune-kit/src/markdown/highlight.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Highlighted source ranges: match and current-match paint.

import Rune

struct HighlightRing: Sendable, Equatable {
    var color: Color
    var width: Float
}

/// How a source byte range in ``Markdown/highlights(_:)`` is painted.
///
/// ``Highlight/init()`` (or ``Highlight/new()``) draws a standard match background from
/// ``MarkdownStyle``; ``Highlight/current()`` draws the active match with a stronger background
/// and an inset border ring. Either may be customized with ``Highlight/bg(_:)``, ``Highlight/fg(_:)``,
/// ``Highlight/ring(_:_:)`` and ``Highlight/key(_:)``.
public struct Highlight: Sendable, Equatable {
    var currentFlag: Bool = false
    var bgColor: Color? = nil
    var fgColor: Color? = nil
    var ringSpec: HighlightRing? = nil
    var keyName: String? = nil

    public init() {}

    /// A standard match highlight using the theme's ``MarkdownStyle/highlightBg(_:)``.
    public static func new() -> Highlight {
        Highlight()
    }

    /// An active/current match highlight using the theme's ``MarkdownStyle/highlightCurrentBg(_:)``
    /// and ``MarkdownStyle/highlightCurrentRing(_:)``.
    public static func current() -> Highlight {
        var h = Highlight()
        h.currentFlag = true
        return h
    }

    /// Alias for ``Highlight/current()``.
    public static func active() -> Highlight {
        Highlight.current()
    }

    /// Sets whether this highlight uses the active/current match style.
    public func currentMatch(_ current: Bool) -> Highlight {
        var copy = self
        copy.currentFlag = current
        return copy
    }

    /// Whether this highlight uses the active/current match style.
    public func isCurrent() -> Bool {
        currentFlag
    }

    /// Overrides the rounded background colour behind the highlighted glyphs.
    public func bg(_ c: Color) -> Highlight {
        var copy = self
        copy.bgColor = c
        return copy
    }

    /// Overrides the glyph foreground colour over the highlighted range.
    public func fg(_ c: Color) -> Highlight {
        var copy = self
        copy.fgColor = c
        return copy
    }

    /// Alias for ``Highlight/fg(_:)``.
    public func color(_ c: Color) -> Highlight {
        fg(c)
    }

    /// Overrides the inset border ring `(color, widthPt)` inside the rounded background.
    public func ring(_ color: Color, _ width: Float) -> Highlight {
        var copy = self
        copy.ringSpec = (width > 0.0 && width.isFinite) ? HighlightRing(color: color, width: width) : nil
        return copy
    }

    /// Sets a key for `Tx.scrollIntoView`, `Cx.layout` and `Runtime.find`. When unset,
    /// the highlight is reachable under ``Markdown/highlightKey(_:)``(`index`).
    public func key(_ key: String) -> Highlight {
        var copy = self
        copy.keyName = key
        return copy
    }
}

/// An item accepted by ``Markdown/highlights(_:)``: a `Range<Int>` or a match `[Range<Int>]`
/// from ``find(_:_:_:)``.
// PORT NOTE: Swift non-nominal tuple types cannot conform to protocols, so paired `(Range<Int>, Highlight)`
// and `([Range<Int>], Highlight)` sequences are supported via overloads on `Markdown.highlights(_:)`.
public protocol HighlightItem {
    func intoHighlight() -> (Range<Int>, Highlight)
    func intoRanges() -> ([Range<Int>], Highlight)
}

extension HighlightItem {
    public func intoRanges() -> ([Range<Int>], Highlight) {
        let (r, h) = intoHighlight()
        return ([r], h)
    }
}
