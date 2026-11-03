// Tests ported from: crates/rune/src/el/virtual_rows.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Full end-to-end Taffy layout + `Runtime.wheel` scroll passes for virtual lists live in
// `runtime/` (not yet ported in `runtime.swift`). Here we verify `El.virtualRows`, `RowSource`,
// `El.virtualRowsVersion`, `El.onVisibleRows`, and `VirtualList`'s indexed windowing, overscan budget,
// prepend anchor preservation, height persistence, and `needsWindow` thresholds.

@Suite("VirtualRowsTests")
struct VirtualRowsTests {
    @Test("RowSource and El.virtualRows build only requested indices from window state")
    func rowSourceBuildsOnlyRequestedIndices() {
        struct ChatState {
            var ids: [Int]
        }
        var builtIndices: [Int] = []
        let list = col()
            .key("rows")
            .growth(GrowthSpec())
            .virtualRows(
                1000,
                50.0,
                { (s: ChatState, i: Int) in "m\(s.ids[i])" },
                { (s: ChatState, i: Int) in
                    builtIndices.append(i)
                    return text("msg \(s.ids[i])").h(50.0)
                }
            )
            .virtualRowsVersion(42)

        #expect(list.hasVirtual)
        #expect(list.virtualEstimate == 50.0)
        #expect(list.virtualRowsVersionHash != nil)

        let sameVer = col().virtualRowsVersion(42)
        let diffVer = col().virtualRowsVersion(43)
        #expect(list.virtualRowsVersionHash == sameVer.virtualRowsVersionHash)
        #expect(list.virtualRowsVersionHash != diffVer.virtualRowsVersionHash)

        guard let source = list.virtualRowsSource else {
            Issue.record("expected virtualRowsSource to be populated")
            return
        }
        #expect(source.count == 1000)

        let state = ChatState(ids: Array(10_000..<11_000))
        let ref = StatesRef.one(state)
        #expect(source.key(ref, 0) == "m10000")
        #expect(source.key(ref, 999) == "m10999")
        let rowEl = source.build(ref, 7)
        #expect(rowEl.textSpec?.value.content == "msg 10007")
        #expect(builtIndices == [7])
    }

    @Test("onVisibleRows mutates state and forwards commit boolean")
    func onVisibleRowsForwardsRangeAndReturnFlag() {
        struct VisState {
            var seen: Range<Int> = 0..<0
            var shouldCommit: Bool = false
        }
        let node = col()
            .virtualize(20.0)
            .onVisibleRows { (s: inout VisState, r: Range<Int>) in
                s.seen = r
                return s.shouldCommit
            }

        let states = States(VisState(seen: 0..<0, shouldCommit: false))
        let fn = node.handlers.value.onVisibleRows
        #expect(fn != nil)
        #expect(fn?(states, 2..<12) == false)
        #expect((states.app as? VisState)?.seen == 2..<12)

        _ = states.withMutable { (s: inout VisState) in s.shouldCommit = true }
        #expect(fn?(states, 4..<14) == true)
        #expect((states.app as? VisState)?.seen == 4..<14)
    }

    @Test("indexed VirtualList budgets new overscan per frame until full overscan is mounted")
    func anIdleWindowMountsItsOverscanInBudgetedSteps() {
        // Mirrors `an_idle_window_mounts_all_its_overscan` (1000 rows of 50pt in 500pt viewport).
        var v = VirtualList()
        v.indexed = true
        v.viewport = 500.0
        v.setEstimate(50.0)
        v.setKeys((0..<1000).map { "r\($0)" }, 0, nil)

        // First commit with empty shown set mounts viewport (0..<10) + 0.5 viewport budget (5 rows) = 0..<15.
        v.select(0.0, false, v.shown)
        #expect(v.range == 0..<15)
        v.shown = Set(v.range.map { v.keys[$0] })
        #expect(v.needsWindow(0.0, false))

        // Subsequent idle frames expand by 0.5 viewport (5 rows) per frame up to full 2.0x overscan (0..<30).
        var steps = 0
        while v.needsWindow(0.0, false) && steps < 10 {
            v.select(0.0, false, v.shown)
            v.shown = Set(v.range.map { v.keys[$0] })
            steps += 1
        }
        #expect(v.range == 0..<30)
        #expect(!v.needsWindow(0.0, false))

        // Jumping to offset 10_000 (row 200) budgets overscan around 200..210 -> settles at 180..<230.
        v.select(10_000.0, false, v.shown)
        v.shown = Set(v.range.map { v.keys[$0] })
        var jumpSteps = 0
        while v.needsWindow(10_000.0, false) && jumpSteps < 10 {
            v.select(10_000.0, false, v.shown)
            v.shown = Set(v.range.map { v.keys[$0] })
            jumpSteps += 1
        }
        #expect(v.range == 180..<230)
        #expect(!v.needsWindow(10_000.0, false))
    }

    @Test("prepending a page preserves measured heights and anchors the first visible row")
    func prependingPreservesHeightsAndAnchorsReader() {
        var v = VirtualList()
        v.indexed = true
        v.viewport = 800.0
        v.setEstimate(72.0)
        let initialKeys = (100..<400).map { "m\($0)" }
        v.setKeys(initialKeys, 0, nil)
        v.setHeight("m100", 110.0)
        v.setHeight("m105", 96.0)

        let prependedKeys = (40..<400).map { "m\($0)" }
        let anchor = v.setKeys(prependedKeys, 1, 0.0)
        #expect(anchor?.0 == "m100")
        #expect(anchor?.1 == 0.0)
        #expect(v.height("m100") == 110.0)
        #expect(v.height("m105") == 96.0)
        #expect(v.height("m50") == 72.0)

        // Adjusting scroll offset by anchorDelta keeps m100 stationary!
        v.anchor = anchor
        let delta = v.anchorDelta()
        #expect(delta == 60.0 * 72.0)
        #expect(v.visibleRange(delta, false).lowerBound == 60)
    }
}
