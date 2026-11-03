// Ported from: crates/rune-mermaid/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

import Rune

/// Colours and type a diagram draws with.
public struct DiagramStyle: Sendable, Equatable, Hashable {
    public var text: Color
    public var muted: Color
    public var surface: Color
    public var surfaceBorder: Color
    public var nodeFill: Color
    public var nodeBorder: Color
    public var line: Color
    public var clusterFill: Color
    public var noteFill: Color
    public var noteBorder: Color
    public var font: TextStyle
    public var maxWidth: Float

    public init(
        text: Color,
        muted: Color,
        surface: Color,
        surfaceBorder: Color,
        nodeFill: Color,
        nodeBorder: Color,
        line: Color,
        clusterFill: Color,
        noteFill: Color,
        noteBorder: Color,
        font: TextStyle,
        maxWidth: Float
    ) {
        self.text = text
        self.muted = muted
        self.surface = surface
        self.surfaceBorder = surfaceBorder
        self.nodeFill = nodeFill
        self.nodeBorder = nodeBorder
        self.line = line
        self.clusterFill = clusterFill
        self.noteFill = noteFill
        self.noteBorder = noteBorder
        self.font = font
        self.maxWidth = maxWidth
    }

    public func hash(into hasher: inout Hasher) {
        for c in [
            text, muted, surface, surfaceBorder, nodeFill, nodeBorder,
            line, clusterFill, noteFill, noteBorder,
        ] {
            hasher.combine(c)
        }
        hasher.combine(font)
        let bits: UInt32
        if maxWidth == 0.0 {
            bits = 0
        } else if maxWidth.isNaN {
            bits = Float.nan.bitPattern
        } else {
            bits = maxWidth.bitPattern
        }
        hasher.combine(bits)
    }

    /// Neutral light or dark colours derived from Rune's core tokens.
    public static func neutral(_ dark: Bool) -> DiagramStyle {
        let t = tok.theme(dark)
        return DiagramStyle(
            text: t.text,
            muted: t.textSecondary,
            surface: t.bg,
            surfaceBorder: t.separator,
            nodeFill: t.card,
            nodeBorder: t.text.alpha(0.2),
            line: t.text.alpha(0.42),
            clusterFill: t.text.alpha(dark ? 0.04 : 0.025),
            noteFill: oklcha(dark ? 0.3 : 0.95, 0.04, 80.0, 1.0),
            noteBorder: oklch(dark ? 0.4 : 0.85, 0.08, 80.0),
            font: TextStyle.new(13.0, 400.0).lh(18.0),
            maxWidth: 680.0
        )
    }
}

/// `src` drawn as a diagram card in `style`, or `nil` when it is outside the supported subset.
public func render(_ src: String, _ style: DiagramStyle) -> El? {
    renderWithHover(src, style, .edges, style.text.alpha(0.9))
}

/// `render`, with `hover` lighting up in `color` while the pointer is over a node or edge.
public func renderWithHover(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    _ = src
    _ = style
    _ = hover
    _ = color
    return nil
}

/// `renderWithHover` for a source still arriving (complete lines only).
public func renderStreaming(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    _ = src
    _ = style
    _ = hover
    _ = color
    return nil
}

/// `renderStreaming` for the whole source once it has all arrived.
public func renderStreamed(_ src: String, _ style: DiagramStyle, _ hover: Hover, _ color: Color) -> El? {
    _ = src
    _ = style
    _ = hover
    _ = color
    return nil
}

/// Whether `src` parses as a supported diagram.
public func supported(_ src: String) -> Bool {
    _ = src
    return false
}

/// Whether `src`, the complete lines of a diagram still arriving, may draw once more arrive.
public func mayDraw(_ src: String) -> Bool {
    _ = src
    return false
}
