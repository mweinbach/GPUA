// Ported from: crates/rune-mermaid/src/hover.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

import Rune

/// What hovering a flowchart or state diagram node lights up.
public enum Hover: Sendable, Equatable, Hashable {
    /// Nothing.
    case off
    /// The edges in and out of it, with their labels.
    case edges
    /// Its edges, its outline and the outlines of the nodes they reach.
    case neighbours

    public static let `default`: Hover = .edges
}
