// Ported from: crates/rune/src/runtime/playground.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scene switching, motion trace capture, and playground inspection hooks on `Runtime`.

import RuneMotion
import Taffy

extension Runtime {
    public func setTrace(_ trace: MotionTrace) {
        scene.setTrace(trace)
    }

    @discardableResult
    public func startTrace() -> SharedBuffer {
        let header = TraceHeader(
            launch: "runtime",
            width: viewport.0,
            height: viewport.1,
            hz: 60.0,
            scale: env.scale
        )
        let (trace, buf) = MotionTrace.inMemory(header)
        scene.setTrace(trace)
        return buf
    }

    public func takeTrace() -> MotionTrace? {
        scene.takeTrace()
    }

    public func tracing() -> Bool {
        scene.tracing()
    }

    public func applyScene(_ mutate: (inout S) -> Void) {
        mutate(&state)
        settleAll()
        markDirty(CommitWhy.UPDATE)
    }

    /// The root's natural height at the current width, measured without committing when not yet committed.
    public func contentHeight() -> Float {
        let savedNodes = nodes
        let savedKeyIndex = keyIndex
        let savedRootW = rootFillsViewportWidth
        let savedRootH = rootFillsViewportHeight
        let savedFit = fitHeight
        defer {
            nodes = savedNodes
            keyIndex = savedKeyIndex
            rootFillsViewportWidth = savedRootW
            rootFillsViewportHeight = savedRootH
            fitHeight = savedFit
        }
        fitHeight = true
        let cx = Cx<S>(
            env: env,
            titlebarInset: titlebarInset,
            systemAccent: systemAccent,
            systemReducedMotion: systemReducedMotion,
            reducedMotion: reducedMotion,
            timeScale: timeScale,
            caret: lastLayoutSnapshot.caret,
            layoutRects: lastLayoutSnapshot.layoutRects,
            windowRects: lastLayoutSnapshot.windowRects
        )
        var rootEl = withSceneClock(SceneClock(now: t, dt: lastDt)) {
            withBlend(srgbBlend) {
                view(state, cx)
            }
        }
        rootEl.expandMemo()
        var diagnostics: [LayoutDiagnostic] = []
        var memoReuses = 0
        var taffy = TaffyTree<NodeMeasureContext>()
        taffy.disableRounding()
        guard let rootTid = flattenViewTree(&rootEl, taffy: &taffy, diagnostics: &diagnostics, memoReuses: &memoReuses) else {
            return max(viewport.1, 1.0)
        }
        let room = Size<AvailableSpace>(width: .definite(viewport.0), height: .maxContent)
        _ = taffy.computeLayoutWithMeasure(rootTid, room, makeTaffyMeasureClosure())
        extractTaffyLayouts(&taffy, diagnostics: &diagnostics)
        let rawH = nodes.first?.localRect[3] ?? viewport.1
        let s = max(env.scale, 0.001)
        return max((rawH * s).rounded(.up) / s, 1.0)
    }
}
