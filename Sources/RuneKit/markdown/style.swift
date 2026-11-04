// Ported from: crates/rune-kit/src/markdown/style.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! ``MarkdownStyle``: how markdown looks, and its builders.

import Rune

/// Colours, icon and motion of a GFM task list checkbox (matching ``Checkbox``).
struct TaskPaint: Sendable, Equatable {
    var fillOn: Color
    var borderOn: Color
    var borderOff: Color
    var hover: Color
    var focusRing: Color
    var mark: Color
    var check: Icon
    var radius: Float
    var motion: Spring
}

/// A table's rounded frame (see ``MarkdownStyle/tableFrame(_:_:_:)``).
struct TableFrame: Sendable, Equatable {
    var fill: Color
    var ring: Color
    var pad: Float
}

/// The card a table's body rows sit on (see ``MarkdownStyle/tableBody(_:_:_:)``).
struct TableBody: Sendable, Equatable {
    var fill: Color
    var radius: Float
    var shadows: [Shadow]
}

/// Colours and sizes diagrams draw with (see ``MarkdownStyle/diagram(_:_:_:)``).
struct DiagramPaint: Sendable, Equatable {
    var text: Color
    var muted: Color
    var surface: Color
    var surfaceBorder: Color
    var nodeFill: Color
    var nodeBorder: Color
    var line: Color
    var clusterFill: Color
    var noteFill: Color
    var noteBorder: Color
    var font: TextStyle
    var maxWidth: Float
    var hover: Color
    var hoverNeighbours: Bool
}

/// How markdown looks. ``MarkdownStyle/fromKit(_:)`` takes every colour and font from the kit's
/// tokens, ``MarkdownStyle/neutral(_:)`` and ``MarkdownStyle/fromSeed(_:)`` need no kit; each builder
/// overrides one thing.
public struct MarkdownStyle {
    var textColor: Color
    var mutedColor: Color
    var accentColor: Color
    var linkUnderlineColor: Color
    var codeBg: Color
    var codeBlockFill: Color
    var codeBlockBorder: Color
    var quoteRuleColor: Color
    var ruleColor: Color
    var bodyStyle: TextStyle
    var headings: [TextStyle]
    var codeBlockStyle: TextStyle
    var inlineCodeScale: Float
    var inlineCodeWeight: Float
    var inlineCodePadPt: Float
    var codeBlockPad: [Float]
    var listIndent: Float
    var listGap: Float
    var strongWeightValue: Float
    var tableOutlineColor: Color?
    var tableRuleColor: Color
    var tableHeadFill: Color
    var tableHeadText: Color
    var tableHeadRule: Color?
    var tableHeadWeight: Float?
    var tableMinColumnPt: Float
    var tableTabular: Bool
    /// Cells' font before tabular figures and the header's weight (`nil`: the body's).
    var tableFontStyle: TextStyle?
    /// Cell padding (x, y), and whether the first column has none on its left.
    var tablePad: [Float]
    var tableFlushLeftFlag: Bool
    var tableFrameSpec: TableFrame?
    var tableBodySpec: TableBody?
    /// Header cell padding (x, y) when it differs from the body's.
    var tableHeadPad: [Float]?
    var tableFullWidthFlag: Bool
    /// Space above and below a table (collapsed with its neighbours' like CSS margins).
    var tableMarginPt: [Float]
    var diffAdd: Color
    var diffRemove: Color
    var diffAddText: Color
    var diffRemoveText: Color
    var diffHues: [Color]
    var diffHunkColor: Color
    var syntaxThemeValue: SyntaxTheme
    var highlightEnabled: Bool
    var selectionColor: Color
    var highlightBgColor: Color
    var highlightFgColor: Color?
    var highlightRingSpec: (Color, Float)?
    var highlightCurrentBgColor: Color
    var highlightCurrentFgColor: Color?
    var highlightCurrentRingSpec: (Color, Float)?
    var task: TaskPaint
    var diagramPaint: DiagramPaint

    public static func fromKit(_ k: Kit) -> MarkdownStyle {
        let c = k.c
        var body = k.ty.body
        body.lineHeight = 22.4
        func heading(_ size: Float, _ lh: Float) -> TextStyle {
            var h = body
            h.size = size
            h.weight = 600.0
            h.lineHeight = lh
            return h
        }
        var codeBlock = k.ty.mono
        codeBlock.size = 13.0
        codeBlock.lineHeight = 20.0
        var diagramFont = k.ty.body
        diagramFont.size = 13.0
        diagramFont.lineHeight = 18.0
        return MarkdownStyle(
            textColor: c.textBase,
            mutedColor: c.textMuted,
            accentColor: c.textAccent,
            linkUnderlineColor: k.alpha(c.textAccent, 0.4),
            codeBg: k.alpha(c.textBase, 0.08),
            codeBlockFill: c.layer01,
            codeBlockBorder: c.borderMuted,
            quoteRuleColor: c.layer03,
            ruleColor: c.borderBase,
            bodyStyle: body,
            headings: [heading(17.0, 24.0), heading(15.0, 24.0), heading(13.0, 20.0)],
            codeBlockStyle: codeBlock,
            inlineCodeScale: 0.9,
            inlineCodeWeight: 400.0,
            inlineCodePadPt: 3.5,
            codeBlockPad: [12.0, 12.0],
            listIndent: 32.0,
            listGap: 4.0,
            strongWeightValue: 670.0,
            tableOutlineColor: c.borderMuted,
            tableRuleColor: c.borderMuted,
            tableHeadFill: c.layer01,
            tableHeadText: c.textBase,
            tableHeadRule: nil,
            tableHeadWeight: nil,
            tableMinColumnPt: 120.0,
            tableTabular: true,
            tableFontStyle: nil,
            tablePad: [10.0, 6.0],
            tableFlushLeftFlag: false,
            tableFrameSpec: nil,
            tableBodySpec: nil,
            tableHeadPad: nil,
            tableFullWidthFlag: false,
            tableMarginPt: [12.0, 16.0],
            diffAdd: tint(c.layer01, c.success.icon, k.dark ? 0.11 : 0.14),
            diffRemove: tint(c.layer01, c.danger.icon, k.dark ? 0.11 : 0.14),
            diffAddText: c.textBase,
            diffRemoveText: c.textBase,
            diffHues: [c.success.icon, c.danger.icon],
            diffHunkColor: c.textMuted,
            syntaxThemeValue: SyntaxTheme.fromKit(k),
            highlightEnabled: true,
            selectionColor: k.selection(),
            highlightBgColor: k.dark ? k.alpha(c.warning.icon, 0.24) : oklcha(0.86, 0.15, 85.0, 0.42),
            highlightFgColor: nil,
            highlightRingSpec: nil,
            highlightCurrentBgColor: k.dark ? k.alpha(c.warning.icon, 0.40) : oklcha(0.82, 0.17, 75.0, 0.58),
            highlightCurrentFgColor: nil,
            highlightCurrentRingSpec: (k.dark ? c.warning.icon : oklch(0.66, 0.16, 70.0), 1.0),
            task: TaskPaint(
                fillOn: c.surfaceWeak,
                borderOn: c.stdBorder,
                borderOff: c.borderWeak,
                hover: c.surfaceHover,
                focusRing: c.borderActive,
                mark: c.stdIcon,
                check: k.glyph.check,
                radius: k.radius.sm,
                motion: k.motion.control
            ),
            diagramPaint: DiagramPaint(
                text: c.textBase,
                muted: c.textMuted,
                surface: c.bgBase,
                surfaceBorder: c.borderMuted,
                nodeFill: c.layer01,
                nodeBorder: k.alpha(c.textBase, 0.2),
                line: k.alpha(c.textBase, 0.42),
                clusterFill: k.alpha(c.textBase, k.dark ? 0.04 : 0.025),
                noteFill: c.warning.bg,
                noteBorder: c.warning.border,
                font: diagramFont,
                maxWidth: 680.0,
                hover: k.alpha(c.textBase, 0.9),
                hoverNeighbours: false
            )
        )
    }

    /// Rune's neutral light or dark look (``Kit/neutral(_:)``'s tokens), for apps without a kit.
    public static func neutral(_ dark: Bool) -> MarkdownStyle {
        MarkdownStyle.fromKit(Kit.neutral(dark))
    }

    /// Derived from three colours, the way ``Kit/fromPalette(_:)`` derives a kit.
    public static func fromSeed(_ seed: PaletteSeed) -> MarkdownStyle {
        MarkdownStyle.fromKit(Kit.fromPalette(seed))
    }

    /// Body, heading (levels 1 to 3 and the muted level 4+) and emphasis colour.
    public func text(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.textColor = c
        return copy
    }

    /// Level 4+ headings and list markers.
    public func muted(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.mutedColor = c
        return copy
    }

    /// Link text; the underline is the same colour at 40% unless set with ``linkUnderline(_:)``.
    public func link(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.accentColor = c
        copy.linkUnderlineColor = c.alpha(0.4)
        return copy
    }

    public func linkUnderline(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.linkUnderlineColor = c
        return copy
    }

    /// The chip behind inline code.
    public func inlineCodeBg(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.codeBg = c
        return copy
    }

    public func codeBlock(_ fill: Color, _ border: Color) -> MarkdownStyle {
        var copy = self
        copy.codeBlockFill = fill
        copy.codeBlockBorder = border
        return copy
    }

    /// Room (x, y) inside a code block's frame; 12 by 12 by default.
    public func codeBlockPadding(_ x: Float, _ y: Float) -> MarkdownStyle {
        var copy = self
        copy.codeBlockPad = [x, y]
        return copy
    }

    /// The column a list's markers sit centred in (32 by default), and the gap between its
    /// items (4).
    public func list(_ indent: Float, _ gap: Float) -> MarkdownStyle {
        var copy = self
        copy.listIndent = indent
        copy.listGap = gap
        return copy
    }

    public func quoteRule(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.quoteRuleColor = c
        return copy
    }

    public func rule(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.ruleColor = c
        return copy
    }

    /// Paragraphs, list items and list markers.
    public func bodyFont(_ f: TextStyle) -> MarkdownStyle {
        var copy = self
        copy.bodyStyle = f
        return copy
    }

    /// The font of heading `level` (1 to 3; level 4 and deeper share 3).
    public func headingFont(_ level: UInt8, _ f: TextStyle) -> MarkdownStyle {
        var copy = self
        let clamped = min(max(Int(level), 1), 3) - 1
        copy.headings[clamped] = f
        return copy
    }

    /// Code blocks and diffs. Inline code is set in the app's mono slot, so keep this on
    /// `Family.mono` for the two to match; for the platform's monospaced font (SF Mono) in
    /// both, name `ui-monospace` in the mono slot of `AppSpec.families`.
    public func codeBlockFont(_ f: TextStyle) -> MarkdownStyle {
        var copy = self
        copy.codeBlockStyle = f
        return copy
    }

    /// Inline code's size as a multiple of the surrounding text, and its weight (the family is
    /// always the mono slot's).
    public func inlineCodeFont(_ scale: Float, _ weight: Float) -> MarkdownStyle {
        var copy = self
        copy.inlineCodeScale = scale
        copy.inlineCodeWeight = weight
        return copy
    }

    /// Room in points between inline code and the edges of its chip. Up to twice a narrow
    /// space's width; what's left of it is the gap between the chip and the text around it.
    public func inlineCodePad(_ pad: Float) -> MarkdownStyle {
        var copy = self
        copy.inlineCodePadPt = pad
        return copy
    }

    public func strongWeight(_ w: Float) -> MarkdownStyle {
        var copy = self
        copy.strongWeightValue = w
        return copy
    }

    /// The tints behind a diff's added and removed lines (full width).
    public func diff(_ added: Color, _ removed: Color) -> MarkdownStyle {
        var copy = self
        copy.diffAdd = added
        copy.diffRemove = removed
        return copy
    }

    /// The text colours of a diff's added and removed lines (the body text colour by default).
    public func diffText(_ added: Color, _ removed: Color) -> MarkdownStyle {
        var copy = self
        copy.diffAddText = added
        copy.diffRemoveText = removed
        return copy
    }

    /// Tints added and removed lines' text `amount` (0 to 1) of the way toward the theme's green
    /// and red, from the text colour set so far; around 0.5 reads clearly in both themes.
    public func diffTextTint(_ amount: Float) -> MarkdownStyle {
        var copy = self
        let t = min(max(amount, 0.0), 1.0)
        copy.diffAddText = tint(copy.textColor, copy.diffHues[0], t)
        copy.diffRemoveText = tint(copy.textColor, copy.diffHues[1], t)
        return copy
    }

    /// The text colour of a diff's `@@` hunk headers and file header lines.
    public func diffHunk(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.diffHunkColor = c
        return copy
    }

    /// The colour of one kind of token in highlighted code blocks.
    public func syntax(_ kind: Syntax, _ c: Color) -> MarkdownStyle {
        var copy = self
        copy.syntaxThemeValue = copy.syntaxThemeValue.with(kind, c)
        return copy
    }

    /// Every token colour at once (by default ``SyntaxTheme/fromKit(_:)``).
    public func syntaxTheme(_ theme: SyntaxTheme) -> MarkdownStyle {
        var copy = self
        copy.syntaxThemeValue = theme
        return copy
    }

    /// Whether code blocks are coloured (on by default): fences in a language the highlighter
    /// knows (see ``Markdown/highlight(_:file:line:column:)``). Off, every code block draws in the text colour.
    public func syntaxHighlight(_ on: Bool) -> MarkdownStyle {
        var copy = self
        copy.highlightEnabled = on
        return copy
    }

    /// The highlight of ``Markdown/selectable(_:)`` text (the kit's field selection by default).
    public func selection(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.selectionColor = c
        return copy
    }

    /// Diagram nodes (and sequence participants): their fill and outline, and the colour of
    /// edges, arrows and lifelines.
    public func diagram(_ nodeFill: Color, _ nodeBorder: Color, _ line: Color) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.nodeFill = nodeFill
        copy.diagramPaint.nodeBorder = nodeBorder
        copy.diagramPaint.line = line
        return copy
    }

    /// The card a diagram sits on, and the tint behind flowchart subgraphs. Keep `fill` opaque:
    /// translucent lines and outlines are flattened over it so they don't brighten where they
    /// overlap. For no card, pass the colour behind the diagram with a clear `border`.
    public func diagramSurface(_ fill: Color, _ border: Color, _ subgraph: Color) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.surface = fill
        copy.diagramPaint.surfaceBorder = border
        copy.diagramPaint.clusterFill = subgraph
        return copy
    }

    /// Sequence diagram notes.
    public func diagramNote(_ fill: Color, _ border: Color) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.noteFill = fill
        copy.diagramPaint.noteBorder = border
        return copy
    }

    /// The font of diagram labels (13 points of the body face by default).
    public func diagramFont(_ f: TextStyle) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.font = f
        return copy
    }

    /// The widest a diagram draws, in points (680 by default). A left-to-right flowchart that
    /// would have to shrink below 78% to fit is laid out top-down instead, when that comes out
    /// narrower; anything still wider is drawn smaller, down to 60%.
    public func diagramMaxWidth(_ points: Float) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.maxWidth = max(points, 120.0)
        return copy
    }

    /// What lights up while the pointer is over a flowchart or state diagram node: its edges and
    /// their labels in `color` (the text colour by default; transparent turns it off), and with
    /// `neighbours` its outline and the outlines of the nodes they reach. Pointing at an edge or
    /// its label lights that edge and its label.
    public func diagramHover(_ color: Color, _ neighbours: Bool) -> MarkdownStyle {
        var copy = self
        copy.diagramPaint.hover = color
        copy.diagramPaint.hoverNeighbours = neighbours
        return copy
    }

    /// Background fill of standard ``Markdown/highlights(_:)`` matches.
    public func highlightBg(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.highlightBgColor = c
        return copy
    }

    /// Optional glyph foreground colour of standard ``Markdown/highlights(_:)`` matches.
    public func highlightFg(_ c: Color?) -> MarkdownStyle {
        var copy = self
        copy.highlightFgColor = c
        return copy
    }

    /// Optional inset border ring `(color, widthPt)` of standard ``Markdown/highlights(_:)`` matches.
    public func highlightRing(_ ring: (Color, Float)?) -> MarkdownStyle {
        var copy = self
        copy.highlightRingSpec = ring
        return copy
    }

    /// Background fill of ``Highlight/current()`` matches.
    public func highlightCurrentBg(_ c: Color) -> MarkdownStyle {
        var copy = self
        copy.highlightCurrentBgColor = c
        return copy
    }

    /// Optional glyph foreground colour of ``Highlight/current()`` matches.
    public func highlightCurrentFg(_ c: Color?) -> MarkdownStyle {
        var copy = self
        copy.highlightCurrentFgColor = c
        return copy
    }

    /// Optional inset border ring `(color, widthPt)` of ``Highlight/current()`` matches.
    public func highlightCurrentRing(_ ring: (Color, Float)?) -> MarkdownStyle {
        var copy = self
        copy.highlightCurrentRingSpec = ring
        return copy
    }
}
