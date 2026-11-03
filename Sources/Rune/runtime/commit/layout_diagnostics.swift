// Ported from: crates/rune/src/runtime/commit/layout_diagnostics.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Diagnostics emitted during commit/layout: duplicate sibling keys, missing anchor triggers,
//! zero-sized scroll viewports, and non-converging layout-read loops.

public enum LayoutDiagnosticKind: String, Sendable, Equatable, Hashable {
    case duplicateSiblingKey = "duplicate-sibling-key"
    case missingAnchorTarget = "missing-anchor-target"
    case unboundedScroll = "unbounded-scroll"
    case layoutReadCycle = "layout-read-cycle"
}

public struct LayoutDiagnostic: Sendable, Equatable {
    public var kind: LayoutDiagnosticKind
    public var path: String
    public var message: String

    public init(kind: LayoutDiagnosticKind, path: String, message: String) {
        self.kind = kind
        self.path = path
        self.message = message
    }
}

extension Runtime {
    public func layoutDiagnostics() -> [LayoutDiagnostic] {
        ensureClean()
        return lastLayoutDiagnostics
    }
}
