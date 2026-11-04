// Tests ported from: crates/rune-knobs/src/view_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

private struct ViewT {
    var knobs: Knobs
}

private let viewL = Knob.new("Left size", 0.0, 10.0, 5.0)
private let viewI = Knob.new("Inner gap", 0.0, 1.0, 0.5)
private let viewR = Knob.new("Right pad", 0.0, 40.0, 20.0)
private let viewGroups: [Group] = [
    Group.new("Left", "left", [viewL]),
    Group.new("Inner", "inner", [viewI]),
    Group.new("Right", "right", [viewR]),
]

private func floatingView(_ s: ViewT, _: Cx<ViewT>) -> El {
    el().key("root")
        .wFull()
        .hFull()
        .child(
            row()
                .key("cols")
                .wFull()
                .hFull()
                .child(
                    col()
                        .key("left")
                        .w(400.0)
                        .hFull()
                        .child(el().key("inner").w(200.0).h(200.0).mt(100.0).ml(100.0))
                )
                .child(col().key("right").grow(1.0).hFull())
        )
        .child(layer(s.knobs, viewGroups, Style.dark(), { (s: inout ViewT, f) in f(&s.knobs) }))
}

private func settle(_ rt: Runtime<ViewT>) {
    for _ in 0..<4 {
        _ = rt.frame(1.0 / 60.0)
    }
}

private func click(_ rt: Runtime<ViewT>, _ key: String) {
    let (x, y) = rt.find(key)!
    rt.pointerMove(x, y)
    settle(rt)
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    settle(rt)
}

private func press(_ rt: Runtime<ViewT>, _ key: Key, _ shift: Bool) {
    _ = rt.keyDown(KeyEvent(key: key, mods: Mods(shift: shift)))
    settle(rt)
}

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs view tests", .serialized)
@MainActor
struct RuneKnobsViewTests {
    @Test("hover_outlines_the_smallest_region_and_a_click_opens_its_knobs")
    func hoverOutlinesTheSmallestRegionAndAClickOpensItsKnobs() {
        var s = ViewT(knobs: Knobs())
        s.knobs.show()
        s.knobs.pickRegion()
        let rt = Runtime.new(s, floatingView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        for (x, y, want) in [(Float(150.0), Float(150.0), "Inner"), (Float(50.0), Float(600.0), "Left"), (Float(600.0), Float(500.0), "Right")] {
            rt.pointerMove(x, y)
            settle(rt)
            #expect(rt.state.knobs.hover == want, "at \(x),\(y)")
            #expect(rt.find("knobs-outline") != nil)
        }
        rt.pointerMove(150.0, 150.0)
        settle(rt)
        _ = rt.pointerDown(150.0, 150.0)
        rt.pointerUp(150.0, 150.0)
        settle(rt)
        #expect(rt.state.knobs.group == "Inner")
        #expect(rt.find("knobs-knob-0") != nil)

        let (rx, ry) = rt.find("knobs-random")!
        rt.pointerMove(rx, ry)
        settle(rt)
        _ = rt.pointerDown(rx, ry)
        rt.pointerUp(rx, ry)
        settle(rt)
        #expect(rt.state.knobs.values["Inner gap"] != nil)
        #expect(rt.state.knobs.canUndo())

        let (tx, ty) = rt.find("knobs-tab-2")!
        rt.pointerMove(tx, ty)
        settle(rt)
        _ = rt.pointerDown(tx, ty)
        rt.pointerUp(tx, ty)
        settle(rt)
        #expect(rt.state.knobs.group == "Right")
    }

    @Test("opens_on_a_group_and_outlines_only_on_tab_hover")
    func opensOnAGroupAndOutlinesOnlyOnTabHover() {
        var s = ViewT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, floatingView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        #expect(rt.find("knobs-knob-0") != nil, "first group is open")
        #expect(rt.find("knobs-outline") == nil)
        let (kx, ky) = rt.find("knobs-knob-0")!
        rt.pointerMove(kx, ky)
        settle(rt)
        #expect(rt.find("knobs-outline") == nil, "no outline over a knob")
        let (tx, ty) = rt.find("knobs-tab-1")!
        rt.pointerMove(tx, ty)
        settle(rt)
        #expect(rt.find("knobs-outline") != nil)
    }

    @Test("keyboard_steps_knobs_and_switches_groups")
    func keyboardStepsKnobsAndSwitchesGroups() {
        var s = ViewT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, floatingView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        click(rt, "knobs-card")
        let getL: (Runtime<ViewT>) -> Float = { $0.state.knobs.get(viewL) }
        press(rt, .right, false)
        #expect(abs(getL(rt) - 5.1) < 1e-3, "\(getL(rt))")
        press(rt, .left, true)
        #expect(abs(getL(rt) - 4.1) < 1e-3, "\(getL(rt))")
        press(rt, .tab, false)
        #expect(rt.state.knobs.group == "Inner")
        press(rt, .text("["), false)
        #expect(rt.state.knobs.group == "Left")
        press(rt, .escape, false)
        #expect(!rt.state.knobs.open)
    }

    @Test("undo_and_reset_are_disabled_until_there_is_something_to_undo")
    func undoAndResetAreDisabledUntilThereIsSomethingToUndo() {
        var s = ViewT(knobs: Knobs())
        s.knobs.show()
        #expect(!s.knobs.canUndo() && !s.knobs.canReset(viewGroups[0]))
        let rt = Runtime.new(s, floatingView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        click(rt, "knobs-undo")
        click(rt, "knobs-reset")
        #expect(rt.state.knobs.values.isEmpty)
        click(rt, "knobs-random")
        #expect(rt.state.knobs.canUndo() && rt.state.knobs.canReset(viewGroups[0]))
        click(rt, "knobs-reset")
        #expect(!rt.state.knobs.canReset(viewGroups[0]))
    }

    @Suite("inline_width", .serialized)
    @MainActor
    struct InlineWidthTests {
        nonisolated private static let wide = Knob.new("A rather long slider label here", 0.0, 100.0, 50.0).step(1.0)
        nonisolated private static let pick = Knob.choice("Tint", ["Plain", "Accent", "Raised"], 1)
        nonisolated private static let many = Knob.choice("Corner style", ["Sharp", "Soft", "Round", "Pill", "Squircle"], 0)
        nonisolated private static let inlineGroups: [Group] = [
            Group.new("Card", "card", [viewL, wide, pick, many])
        ]

        private struct WidthHost {
            var knobs: Knobs
            var w: Float
        }

        nonisolated private static func inlineView(_ s: WidthHost, _: Cx<WidthHost>) -> El {
            row()
                .key("root")
                .wFull()
                .hFull()
                .child(
                    col()
                        .key("column")
                        .w(s.w)
                        .child(inline(s.knobs, inlineGroups, Style.dark(), { (s: inout WidthHost, f) in f(&s.knobs) }, false))
                )
        }

        private static func rects(_ w: Float) -> [ElementInfo] {
            let rt = Runtime.new(
                WidthHost(knobs: Knobs(), w: w),
                inlineView,
                (400.0, 700.0),
                Env.new(true, 1.0)
            )
            for _ in 0..<6 {
                _ = rt.frame(1.0 / 60.0)
            }
            return rt.elements()
        }

        private static func rect(_ es: [ElementInfo], _ key: String) -> [Float] {
            guard let found = es.first(where: { $0.key == key }) else {
                preconditionFailure("no \(key)")
            }
            return found.rect
        }

        @Test("rows_stay_inside_the_column_at_240_and_300")
        func rowsStayInsideTheColumnAt240And300() {
            for w: Float in [200.0, 240.0, 300.0] {
                let es = Self.rects(w)
                let card = Self.rect(es, "knobs-card")
                #expect(
                    card[0] >= 0.0 && card[0] + card[2] <= w + 0.01,
                    "card in \(w): \(card)"
                )
                for e in es where e.path.contains("knobs-card") && e.key != nil {
                    let r = e.rect
                    #expect(
                        r[0] >= card[0] - 0.01 && r[0] + r[2] <= card[0] + card[2] + 0.01,
                        "\(String(describing: e.key)) at \(w): \(r) vs \(card)"
                    )
                }
            }
        }

        @Test("the_slider_track_is_usable_and_grows_with_the_column")
        func theSliderTrackIsUsableAndGrowsWithTheColumn() {
            var last: Float = 0.0
            for w: Float in [200.0, 240.0, 300.0] {
                let es = Self.rects(w)
                let track = Self.rect(es, "knobs-knob-0")
                #expect(track[2] > 100.0, "\(w): \(track)")
                #expect(track[2] > last, "\(w)")
                last = track[2]
                let fill = es.first(where: { $0.path.contains("knobs-knob-0") && $0.key == "fill" })!.rect
                #expect(
                    abs(fill[2] - track[2] * 0.5) < 0.6,
                    "fill is the value's share of the track at \(w): \(fill)"
                )
            }
        }

        @Test("a_choice_that_does_not_fit_beside_its_label_wraps_to_a_grid_when_narrow")
        func aChoiceThatDoesNotFitBesideItsLabelWrapsToAGridWhenNarrow() {
            let wide = Self.rects(300.0)
            let narrow = Self.rects(200.0)
            #expect(Self.rect(narrow, "knobs-knob-3")[3] > Self.rect(wide, "knobs-knob-3")[3] - 0.01)
            #expect(
                Self.rect(narrow, "knobs-knob-3")[3] > 40.0,
                "the five options sit under their label"
            )
        }

        @Test("the_floating_panel_keeps_its_300_points")
        func theFloatingPanelKeepsIts300Points() {
            var s = ViewT(knobs: Knobs())
            s.knobs.show()
            let rt = Runtime.new(s, floatingView, (1000.0, 700.0), Env.new(true, 1.0))
            settle(rt)
            let p = rt.elements().first(where: { $0.key == "knobs-panel" })!.rect
            #expect(p[2] == 300.0)
        }
    }
}
}
