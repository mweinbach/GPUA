// Ported from: crates/rune/src/playground/widths.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Resizable widths for the playground's story list and right-hand column: dragged by their
//! separator edges, reset by double-clicking, and remembered across launches.

let PLAYGROUND_SIDEBAR_MIN: Float = 150.0
let PLAYGROUND_SIDEBAR_MAX: Float = 520.0
let PLAYGROUND_SIDE_MIN: Float = 180.0
let PLAYGROUND_SIDE_MAX: Float = 560.0
let PLAYGROUND_STAGE_MIN: Float = 200.0

private let PREF_SIDEBAR = "playground_sidebar_w"
private let PREF_SIDE = "playground_side_w"

struct PlaygroundWidths {
    var load: (() -> (Float, Float))? = nil
    var save: ((Float, Float) -> Void)? = nil

    static func prefs(_ appId: String) -> PlaygroundWidths {
        PlaygroundWidths(
            load: {
                let p = Prefs.open(appId)
                return (
                    p.get(PREF_SIDEBAR, as: Float.self) ?? PLAYGROUND_SIDEBAR,
                    p.get(PREF_SIDE, as: Float.self) ?? PLAYGROUND_SIDE
                )
            },
            save: { sidebar, side in
                var p = Prefs.open(appId)
                if abs(sidebar - PLAYGROUND_SIDEBAR) < 0.5 {
                    try? p.remove(PREF_SIDEBAR)
                } else {
                    try? p.set(PREF_SIDEBAR, sidebar)
                }
                if abs(side - PLAYGROUND_SIDE) < 0.5 {
                    try? p.remove(PREF_SIDE)
                } else {
                    try? p.set(PREF_SIDE, side)
                }
            }
        )
    }
}

extension Playground {
    /// Keeps the story list's and side column's widths from one run to the next. Windowed apps
    /// that don't set this store them in ``Prefs`` automatically.
    public func widths(
        _ load: @escaping () -> (Float, Float),
        _ save: @escaping (Float, Float) -> Void
    ) -> Playground<S> {
        var copy = self
        copy.widthsConfig = PlaygroundWidths(load: load, save: save)
        copy.customWidthsConfigured = true
        return copy
    }
}

func playgroundClampPair(_ sidebar: Float, _ side: Float, _ viewportW: Float) -> (Float, Float) {
    let maxSide = min(PLAYGROUND_SIDE_MAX, max(PLAYGROUND_SIDE_MIN, viewportW - PLAYGROUND_SIDEBAR_MIN - PLAYGROUND_STAGE_MIN - 2.0))
    let clampedSide = min(max(side, PLAYGROUND_SIDE_MIN), maxSide)
    let maxSidebar = min(PLAYGROUND_SIDEBAR_MAX, max(PLAYGROUND_SIDEBAR_MIN, viewportW - clampedSide - PLAYGROUND_STAGE_MIN - 2.0))
    let clampedSidebar = min(max(sidebar, PLAYGROUND_SIDEBAR_MIN), maxSidebar)
    return (clampedSidebar, clampedSide)
}

extension PlaygroundControls {
    func setWidths(_ sidebar: Float, _ side: Float) {
        if sidebar.isFinite && sidebar > 0.0 {
            sidebarW = min(max(sidebar, PLAYGROUND_SIDEBAR_MIN), PLAYGROUND_SIDEBAR_MAX).rounded()
        }
        if side.isFinite && side > 0.0 {
            sideW = min(max(side, PLAYGROUND_SIDE_MIN), PLAYGROUND_SIDE_MAX).rounded()
        }
    }

    func saveWidths() {
        saveWidthsFn?(sidebarW, sideW)
    }
}

extension PlaygroundLive {
    func loadWidths() {
        guard let load = widthsConfig.load else { return }
        widthsConfig.load = nil
        let (sidebar, side) = load()
        controls.setWidths(sidebar, side)
    }

    func widths(_ viewportW: Float) -> (Float, Float) {
        playgroundClampPair(controls.sidebarW, controls.sideW, viewportW)
    }

    func sidebarEdge(_ sidebarW: Float, _ viewport: (Float, Float)) -> El {
        let vw = viewport.0
        return el()
            .key("playground-sidebar-edge")
            .pgAbsolute(sidebarW - 3.0, 0.0)
            .w(7.0)
            .h(viewport.1)
            .pgCursor(.ewResize)
            .help("Drag to resize; double-click for the default width")
            .onDrag { (c: inout PlaygroundControls, d: inout Drag, tx: inout Tx) in
                tx.instant()
                switch d.phase {
                case .down:
                    d.data = playgroundClampPair(c.sidebarW, c.sideW, vw).0
                case .move:
                    let (_, sideW) = playgroundClampPair(c.sidebarW, c.sideW, vw)
                    let maxW = min(PLAYGROUND_SIDEBAR_MAX, max(PLAYGROUND_SIDEBAR_MIN, vw - sideW - PLAYGROUND_STAGE_MIN - 2.0))
                    c.sidebarW = min(max(d.data + d.dx, PLAYGROUND_SIDEBAR_MIN), maxW).rounded()
                case .up where d.cancelled():
                    c.sidebarW = d.data
                case .up:
                    c.saveWidths()
                }
            }
            .pgOnDoublePressTx { (c: inout PlaygroundControls, tx: inout Tx) in
                tx.instant()
                c.sidebarW = PLAYGROUND_SIDEBAR
                c.saveWidths()
            }
    }

    func sideEdge(_ sideW: Float, _ viewport: (Float, Float)) -> El {
        let vw = viewport.0
        return el()
            .key("playground-side-edge")
            .pgAbsolute(vw - sideW - 4.0, 0.0)
            .w(7.0)
            .h(viewport.1)
            .pgCursor(.ewResize)
            .help("Drag to resize; double-click for the default width")
            .onDrag { (c: inout PlaygroundControls, d: inout Drag, tx: inout Tx) in
                tx.instant()
                switch d.phase {
                case .down:
                    d.data = playgroundClampPair(c.sidebarW, c.sideW, vw).1
                case .move:
                    let (sidebarW, _) = playgroundClampPair(c.sidebarW, c.sideW, vw)
                    let maxW = min(PLAYGROUND_SIDE_MAX, max(PLAYGROUND_SIDE_MIN, vw - sidebarW - PLAYGROUND_STAGE_MIN - 2.0))
                    c.sideW = min(max(d.data - d.dx, PLAYGROUND_SIDE_MIN), maxW).rounded()
                case .up where d.cancelled():
                    c.sideW = d.data
                case .up:
                    c.saveWidths()
                }
            }
            .pgOnDoublePressTx { (c: inout PlaygroundControls, tx: inout Tx) in
                tx.instant()
                c.sideW = PLAYGROUND_SIDE
                c.saveWidths()
            }
    }
}
