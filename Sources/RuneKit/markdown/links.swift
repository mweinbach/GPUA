// Ported from: crates/rune-kit/src/markdown/links.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Links in Markdown: their handlers, looks and rings, and wiring them onto the text.

import Rune

typealias LinkWire = (El) -> El
typealias LinkLook = (String) -> (Span, LinkPaint)?
typealias LinkRing = (String) -> (Color, Float)?

extension Markdown {
    /// Called with a link's destination when it is clicked, or pressed with Enter or Space
    /// while focused. With a handler, links show a hand and a solid underline under the
    /// pointer and are Tab stops; without one they are styled text only. Shares its slot with
    /// ``onLinkTx(_:)`` (the later call wins).
    public func onLink<S>(_ f: @escaping (inout S, String) -> Void) -> Markdown {
        onLinkTx { (s: inout S, url: String, _: inout Tx) in
            f(&s, url)
        }
    }

    /// ``onLink(_:)`` with the `Tx` of the press, for a handler that opens a screen, scrolls
    /// or copies in the same commit. Replaces any earlier `onLink` or `onLinkTx` handler
    /// (the later call wins).
    public func onLinkTx<S>(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Markdown {
        var copy = self
        copy.onLinkWire = { e in
            e.onLink { (s: inout S, url: String, tx: inout Tx) in
                f(&s, url, &tx)
            }
        }
        return copy
    }

    /// Called with a link's destination and the point (window points) when a right-click (or
    /// macOS control-click) lands on it: a menu for that link (Open, Copy Link).
    public func onLinkSecondary<S>(_ f: @escaping (inout S, String, PointerPress, inout Tx) -> Void) -> Markdown {
        var copy = self
        copy.onLinkSecondaryWire = { e in
            e.onLinkSecondary { (s: inout S, url: String, p: PointerPress, tx: inout Tx) in
                f(&s, url, p, &tx)
            }
        }
        return copy
    }

    /// A look for some links by destination. `f` returns `nil` for the default look
    /// (``MarkdownStyle/link(_:)`` with its underline, and an accent underline on hover), or
    /// `(resting, hover)`: the `Span` drawn over the link's text and the `LinkPaint` over it
    /// while hovered. Applies with or without a handler.
    public func linkStyle(_ f: @escaping (String) -> (Span, LinkPaint)?) -> Markdown {
        var copy = self
        copy.linkLookFn = f
        return copy
    }

    /// An inset border ring `(color, widthPt)` inside the rounded `Span.bg` of chosen links
    /// by destination (`nil`: no ring).
    public func linkRing(_ f: @escaping (String) -> (Color, Float)?) -> Markdown {
        var copy = self
        copy.linkRingFn = f
        return copy
    }
}

extension Renderer {
    func linkSpan(_ a: Int, _ b: Int, _ inl: MarkdownInline) -> Span {
        let url = inl.links.first(where: { $0.0 == a && $0.1 == b })?.2
        if let look = linkLook, let url, let (own, _) = look(url) {
            var sp = own
            sp.start = UInt32(max(a, 0))
            sp.end = UInt32(max(b, 0))
            return sp
        } else {
            var sp = Span.new(a, b)
            sp.color = s.accentColor
            sp.underline = s.linkUnderlineColor
            return sp
        }
    }

    /// The single place a link press is connected: each of `inl.links` becomes a pressable
    /// span of `e` (the text element holding it) reporting its destination.
    func wireLink(_ e: El, _ inl: MarkdownInline) -> El {
        var out = e
        if let ring = linkRing, !inl.links.isEmpty {
            for (a, b, url) in inl.links {
                if let (color, width) = ring(url) {
                    out = out.spanRing(a, b, color, width)
                }
            }
        }
        if inl.links.isEmpty || (onLink == nil && onLinkSecondary == nil) {
            return out
        }
        let defaultHover = LinkPaint.new().underline(s.accentColor)
        func hover(_ url: String) -> LinkPaint {
            linkLook?(url)?.1 ?? defaultHover
        }
        for (a, b, url) in inl.links {
            out = out.link(Link.new(a..<b, url).hover(hover(url)))
        }
        if let onLink {
            out = onLink(out)
        }
        if let onLinkSecondary {
            out = onLinkSecondary(out)
        }
        return out
    }
}
