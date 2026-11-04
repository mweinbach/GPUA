// Ported from: crates/rune-kit/src/mermaid.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native ```` ```mermaid ```` diagrams inside ``Markdown``, backed by `RuneMermaid`.
//!
//! Covers flowcharts (`graph`/`flowchart` in `TD`/`TB`/`BT`/`LR`/`RL` with subgraphs, all node
//! shapes including `@{ shape: … }`, link styles and `style`/`classDef`/`linkStyle` tints),
//! sequence diagrams (`sequenceDiagram` with participants and their v11 types, actors, `box`
//! groups, `rect` bands, activations, notes, frames, `create`/`destroy` and `autonumber`), state
//! diagrams (`stateDiagram`/`stateDiagram-v2` with `[*]`, composite states and `--` regions,
//! notes, `<<choice>>` and `<<fork>>`/`<<join>>`), class diagrams (`classDiagram` with fields,
//! methods, stereotypes, namespaces and UML relations), entity-relationship diagrams
//! (`erDiagram` with attribute tables and crow's-foot cardinalities), gantt charts (`gantt` with
//! sections, durations, `after`/`until` links and `excludes`), pie charts (`pie`, with
//! `showData`), mindmaps (`mindmap`), timelines (`timeline`), user journeys (`journey`), git
//! graphs (`gitGraph` with branches, merges, cherry-picks, tags and commit types), quadrant
//! charts (`quadrantChart`), XY charts (`xychart-beta` bars and lines, upright or horizontal),
//! sankey diagrams (`sankey-beta`), block diagrams (`block-beta` with columns, spans, groups and
//! block arrows), requirement diagrams (`requirementDiagram`) and C4 diagrams (`C4Context`,
//! `C4Container`, `C4Component`, `C4Dynamic` and `C4Deployment`). Lines that don't read are
//! skipped and the rest draws; an unknown diagram type, or a source where nothing reads, returns
//! `nil`, and ``Markdown`` falls back to the code block.

import Rune
import RuneMermaid

/// Namespace mirroring `rune_kit::mermaid` module exports.
public enum mermaid {
    public typealias DiagramStyle = RuneMermaid.DiagramStyle
    public typealias Hover = RuneMermaid.Hover

    /// Whether `src` parses as a supported diagram.
    public static func supported(_ src: String) -> Bool {
        RuneMermaid.supported(src)
    }

    /// Whether `src`, the complete lines of a diagram still arriving, may draw once more arrive.
    public static func mayDraw(_ src: String) -> Bool {
        RuneMermaid.mayDraw(src)
    }

    /// `src` drawn as a diagram card with `style`'s diagram colours, or `nil` when it is outside
    /// the supported subset.
    public static func render(_ src: String, _ style: MarkdownStyle) -> El? {
        diagram(src, style.diagramPaint, false, false)
    }

    /// `streaming`: the reply is still arriving, so what's new since the last build comes in on its
    /// own; `open`: `src` is the complete lines of a fence still arriving, so the diagram only grows
    /// (`RuneMermaid.renderStreaming`) until the fence closes and it settles
    /// (`RuneMermaid.renderStreamed`).
    static func diagram(_ src: String, _ paint: DiagramPaint, _ streaming: Bool, _ open: Bool) -> El? {
        let style = DiagramStyle(
            text: paint.text,
            muted: paint.muted,
            surface: paint.surface,
            surfaceBorder: paint.surfaceBorder,
            nodeFill: paint.nodeFill,
            nodeBorder: paint.nodeBorder,
            line: paint.line,
            clusterFill: paint.clusterFill,
            noteFill: paint.noteFill,
            noteBorder: paint.noteBorder,
            font: paint.font,
            maxWidth: paint.maxWidth
        )
        let hover: Hover
        if paint.hover.a <= 0.0 {
            hover = .off
        } else if paint.hoverNeighbours {
            hover = .neighbours
        } else {
            hover = .edges
        }
        switch (streaming, open) {
        case (false, _):
            return RuneMermaid.renderWithHover(src, style, hover, paint.hover)
        case (true, true):
            return RuneMermaid.renderStreaming(src, style, hover, paint.hover)
        case (true, false):
            return RuneMermaid.renderStreamed(src, style, hover, paint.hover)
        }
    }
}
