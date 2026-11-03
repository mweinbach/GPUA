// Tests ported from: crates/rune/src/runtime/live_check_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("LiveCheckTests")
struct LiveCheckTests {
    private enum CopySide: Equatable {
        case old
        case new
    }

    private struct RowsState {
        var copy: CopySide = .new
        var hovered: [Int] = []
        var changes: Int = 0
    }

    @Test("Tx.liveOnly hover handlers skip commits when state view branch is unchanged and commit when state changes")
    func liveOnlyHoverHandlersSkipUnchangedCommitsAndCommitOnChange() {
        let rowH: Float = 20.0
        func sideFor(_ i: Int) -> CopySide { i % 4 == 3 ? .old : .new }

        let rt = Runtime.new(RowsState(), { s, _ in
            let rows = (0..<12).map { i -> El in
                let side = sideFor(i)
                let isCopy = (s.copy == side)
                let code = rtWithHover(
                    col().key("code-\(i)").grow(1.0).h(rowH)
                        .child(text("let value_\(i) = compute(\(i));").key("text-\(i)").font(TextStyle.new(12.0, 400.0).lh(rowH)))
                ) { (st: inout RowsState, inside: Bool, tx: inout Tx) in
                    if inside {
                        st.hovered.append(i)
                    } else {
                        st.hovered.removeAll { $0 == i }
                    }
                    if inside && st.copy != side {
                        st.copy = side
                        st.changes += 1
                    } else {
                        tx.liveOnly()
                    }
                }
                return rtHoverGroup(
                    row().key("r\(i)").wFull().h(rowH)
                        .bg(isCopy ? .BLACK : .TRANSPARENT)
                        .hover(Color.WHITE.alpha(0.06))
                ).child(code)
            }
            return col().wFull().hFull().children(rows)
        }, (400.0, 300.0), Env.new(true, 1.0))

        rt.checkLiveOnly(true)
        _ = rt.frame(0.0)
        let baseCommits = rt.totalCommits

        // Moving across `.new`-side rows (0, 1, 2) triggers `tx.liveOnly()` without committing
        for rowIdx in [0, 1, 2] {
            rt.pointerMove(200.0, (Float(rowIdx) + 0.5) * rowH)
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(rt.state.changes == 0)
        #expect(rt.liveOnlyEvents() >= 3)
        #expect(rt.totalCommits == baseCommits)
        #expect(rt.liveOnlyWarnings().isEmpty)

        // Entering `.old`-side row 3 mutates `s.copy` without `tx.liveOnly()` and commits
        rt.pointerMove(200.0, 3.5 * rowH)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.copy == .old)
        #expect(rt.state.changes == 1)
        #expect(rt.totalCommits > baseCommits)
    }

    @Test("LiveText updates node content in place without triggering a view commit")
    func liveTextUpdatesInPlaceWithoutViewCommit() {
        let clock = LiveText.new("00:00")
        let rt = Runtime.new((), { _, _ in
            var lbl = text("init").key("clock").font(TextStyle.new(13.0, 400.0))
            lbl.textSpec?.value.live = clock
            return col().wFull().hFull().child(lbl)
        }, (200.0, 80.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let commits = rt.totalCommits

        clock.set("01:23")
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.totalCommits == commits)
        #expect(rtElement(rt, "clock")?.text == "01:23")
    }
}
