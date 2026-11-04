// Ported from: crates/rune-kit/src/shell/mod.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A desktop app's shell: ``SplitView`` (sidebar, main pane, inspector, title bar band) with
//! its ``SidebarToggle``, ``PaneMotion`` and ``SidebarPeek`` settings, ``Toolbar``, ``Sidebar``
//! with ``SidebarSection``, ``SidebarHeader`` and ``SidebarRow``, and the app-owned
//! ``PaneState`` behind each resizable pane and ``Reorder`` behind a list's drag to reorder.
//!
//! The module uses only Rune's and RuneKit's public API.

import Rune

/// Namespace mirroring `rune_kit::shell` module exports.
public enum shell {
    /// The sidebar toggle's glyph: a window with its leading pane drawn in.
    public static let SIDEBAR = Icon(
        name: "kit-sidebar",
        view: 16.0,
        body: #"<rect x="2" y="3" width="12" height="10" rx="2" stroke="currentColor" stroke-width="1" fill="none"/><path d="M6 3.5V12.5" stroke="currentColor" stroke-width="1"/>"#
    )
    /// The inspector toggle's glyph: the same window with its trailing pane drawn in.
    public static let INSPECTOR = Icon(
        name: "kit-inspector",
        view: 16.0,
        body: #"<rect x="2" y="3" width="12" height="10" rx="2" stroke="currentColor" stroke-width="1" fill="none"/><path d="M10 3.5V12.5" stroke="currentColor" stroke-width="1"/>"#
    )

    public static let INDENT: Float = RuneKit.INDENT
    public static let ROW_HEIGHT: Float = RuneKit.ROW_HEIGHT
    public static let TWO_LINE_ROW_HEIGHT: Float = RuneKit.TWO_LINE_ROW_HEIGHT
    public static let TOOLBAR_HEIGHT: Float = RuneKit.TOOLBAR_HEIGHT

    public typealias PaneMotion = RuneKit.PaneMotion
    public typealias PaneState = RuneKit.PaneState
    public typealias SidebarPeek = RuneKit.SidebarPeek
    public typealias Reorder = RuneKit.Reorder
    public typealias RowStatus = RuneKit.RowStatus
    public typealias Sidebar = RuneKit.Sidebar
    public typealias SidebarHeader = RuneKit.SidebarHeader
    public typealias SidebarRow = RuneKit.SidebarRow
    public typealias SidebarSection = RuneKit.SidebarSection
    public typealias Page = RuneKit.Page
    public typealias SidebarToggle = RuneKit.SidebarToggle
    public typealias SplitView = RuneKit.SplitView
    public typealias Toolbar = RuneKit.Toolbar

    public static func isSidebarToggle(_ ev: KeyEvent) -> Bool {
        RuneKit.isSidebarToggle(ev)
    }
}
