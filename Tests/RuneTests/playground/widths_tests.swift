// Tests ported from: crates/rune/src/playground/widths_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private final class PgWidthsSavedBox: @unchecked Sendable {
    var value: (Float, Float) = (0.0, 0.0)
}

private func pgSizeRt(_ playground: Playground<PgTestReal>) -> Runtime<PgTestReal> {
    var spec = AppSpec<PgTestReal>("playground", (1200.0, 700.0), { PgTestReal() }, pgTestView)
    spec.scenes = pgTestScenes()
    let rt = App.new(spec)
        .playground(playground)
        .headlessRuntime((1200.0, 700.0), Env.new(false, 1.0))
    rt.openPlayground("Fade", nil)
    _ = rt.frame(PG_DT)
    return rt
}

@Suite("PlaygroundWidthsTests")
struct PlaygroundWidthsTests {
    @Test func draggingBothColumnEdgesResizesThemAndDoubleClickRestoresDefaults() {
        let saved = PgWidthsSavedBox()
        let p = pgBase().widths(
            { (240.0, 310.0) },
            { a, b in saved.value = (a, b) }
        )
        let rt = pgSizeRt(p)

        #expect(pgFind(rt, "playground-list")!.rect[2] == 240.0)
        #expect(pgFind(rt, "playground-side")!.rect[2] == 310.0)

        let left1 = pgFind(rt, "playground-sidebar-edge")!.rect
        let (lx1, ly1) = (left1[0] + left1[2] * 0.5, left1[1] + 200.0)
        _ = rt.hostPointerDown(lx1, ly1)
        _ = rt.hostPointerMove(lx1 + 60.0, ly1)
        _ = rt.frame(PG_DT)
        #expect(pgFind(rt, "playground-list")!.rect[2] == 300.0)
        _ = rt.hostPointerUp(lx1 + 60.0, ly1)
        _ = rt.frame(PG_DT)
        #expect(saved.value.0 == 300.0)

        let right1 = pgFind(rt, "playground-side-edge")!.rect
        let (rx1, ry1) = (right1[0] + right1[2] * 0.5, right1[1] + 200.0)
        _ = rt.hostPointerDown(rx1, ry1)
        _ = rt.hostPointerMove(rx1 - 50.0, ry1)
        _ = rt.frame(PG_DT)
        #expect(pgFind(rt, "playground-side")!.rect[2] == 360.0)
        _ = rt.hostPointerUp(rx1 - 50.0, ry1)
        _ = rt.frame(PG_DT)
        #expect(saved.value == (300.0, 360.0))

        // Double-click each edge restores its default width.
        let left2 = pgFind(rt, "playground-sidebar-edge")!.rect
        let (lx2, ly2) = (left2[0] + left2[2] * 0.5, left2[1] + 200.0)
        _ = rt.hostPointerDown(lx2, ly2)
        _ = rt.hostPointerUp(lx2, ly2)
        _ = rt.hostPointerDown(lx2, ly2)
        _ = rt.hostPointerUp(lx2, ly2)
        _ = rt.frame(PG_DT)
        #expect(pgFind(rt, "playground-list")!.rect[2] == PLAYGROUND_SIDEBAR)
        #expect(saved.value == (PLAYGROUND_SIDEBAR, 360.0))

        let right2 = pgFind(rt, "playground-side-edge")!.rect
        let (rx2, ry2) = (right2[0] + right2[2] * 0.5, right2[1] + 200.0)
        _ = rt.hostPointerDown(rx2, ry2)
        _ = rt.hostPointerUp(rx2, ry2)
        _ = rt.hostPointerDown(rx2, ry2)
        _ = rt.hostPointerUp(rx2, ry2)
        _ = rt.frame(PG_DT)
        #expect(pgFind(rt, "playground-side")!.rect[2] == PLAYGROUND_SIDE)
        #expect(saved.value == (PLAYGROUND_SIDEBAR, PLAYGROUND_SIDE))
    }
}
