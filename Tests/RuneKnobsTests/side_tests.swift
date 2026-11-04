// Tests ported from: crates/rune-knobs/src/side_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune
import Testing
@testable import RuneKnobs

private struct SideT {
    var knobs: Knobs
}

private let sideL = Knob.new("Left size", 0.0, 10.0, 5.0).label("Left column size")
private let sideC = Knob.choice("Style", ["One", "Two", "Three"], 0).hints(["The first", "The second", ""])
private let sideR = Knob.new("Right pad", 0.0, 40.0, 20.0)
private let sideGroups: [Group] = [
    Group.new("Left", "left", [sideL, sideC]),
    Group.new("Right", "right", [sideR]),
]

private func sideView(_ s: SideT, _: Cx<SideT>) -> El {
    let page = row()
        .key("cols")
        .wFull()
        .hFull()
        .child(col().key("left").w(300.0).hFull())
        .child(col().key("right").grow(1.0).hFull())
    return side(page, s.knobs, sideGroups, Style.dark(), { (s: inout SideT, f) in f(&s.knobs) })
}

private func settle(_ rt: Runtime<SideT>) {
    for _ in 0..<60 {
        _ = rt.frame(1.0 / 60.0)
    }
}

private func click(_ rt: Runtime<SideT>, _ key: String) {
    guard let (x, y) = rt.find(key) else {
        Issue.record("no \(key)")
        return
    }
    rt.pointerMove(x, y)
    settle(rt)
    _ = rt.pointerDown(x, y)
    rt.pointerUp(x, y)
    settle(rt)
}

private func pageW(_ rt: Runtime<SideT>) -> Float {
    rt.elements().first(where: { $0.key == "knobs-page" })!.target[2]
}

private func bodyHeight(_ rt: Runtime<SideT>, _ sec: String) -> Float {
    rt.elements().first(where: { $0.path.contains(sec) && $0.key == "body" })!.rect[3]
}

private func openLeft() -> Runtime<SideT> {
    var s = SideT(knobs: Knobs())
    s.knobs.show()
    s.knobs.setFolded("Left", false)
    let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
    settle(rt)
    return rt
}

private func rect(_ rt: Runtime<SideT>, _ suffix: String) -> [Float] {
    guard let found = rt.elements().first(where: { $0.path.hasSuffix(suffix) && $0.opacity > 0.0 }) else {
        preconditionFailure("no \(suffix)")
    }
    return found.rect
}

private func rightClick(_ rt: Runtime<SideT>, _ x: Float, _ y: Float) {
    rt.pointerMove(x, y)
    settle(rt)
    rt.secondaryDown(x, y)
    rt.secondaryUp(x, y)
    settle(rt)
}

private func press(_ rt: Runtime<SideT>, _ key: Key) {
    _ = rt.key(key)
    settle(rt)
}

extension RuneKnobsSerializedSuites {
@Suite("RuneKnobs side tests", .serialized)
@MainActor
struct RuneKnobsSideTests {
    @Test("opening_pushes_the_page_over_and_closing_gives_it_back")
    func openingPushesThePageOverAndClosingGivesItBack() {
        let rt = Runtime.new(SideT(knobs: Knobs()), sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        #expect(pageW(rt) == 1000.0)
        rt.state.knobs.show()
        rt.invalidate()
        settle(rt)
        #expect(pageW(rt) == 1000.0 - SIDE_W)
        #expect(rt.state.knobs.sideRoom() == SIDE_W)
        #expect(rt.find("knobs-sec-0") != nil && rt.find("knobs-sec-1") != nil, "every group is a section")
        rt.state.knobs.close()
        rt.invalidate()
        settle(rt)
        #expect(pageW(rt) == 1000.0)
    }

    @Test("a_header_opens_its_group_and_picks_it")
    func aHeaderOpensItsGroupAndPicksIt() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        #expect(bodyHeight(rt, "knobs-sec-1") == 0.0, "folded up front, though on screen")
        click(rt, "knobs-sec-1/head")
        #expect(rt.state.knobs.unfolded.contains("Right"))
        #expect(rt.state.knobs.group == "Right")
        #expect(bodyHeight(rt, "knobs-sec-1") > 20.0)
        click(rt, "knobs-sec-1/head")
        #expect(rt.state.knobs.folded.contains("Right"))
        #expect(bodyHeight(rt, "knobs-sec-1") == 0.0)
    }

    @Test("the_panel_reopens_folded_but_for_the_group_last_opened")
    func thePanelReopensFoldedButForTheGroupLastOpened() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        click(rt, "knobs-sec-0/head")
        click(rt, "knobs-sec-1/head")
        rt.state.knobs.close()
        rt.state.knobs.show()
        rt.invalidate()
        settle(rt)
        #expect(bodyHeight(rt, "knobs-sec-0") == 0.0)
        #expect(bodyHeight(rt, "knobs-sec-1") > 20.0)
    }

    @Test("using_a_knob_makes_its_group_the_panels")
    func usingAKnobMakesItsGroupThePanels() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        click(rt, "knobs-sec-1/head")
        click(rt, "knobs-sec-1/body/knobs-card/knobs-knob-0")
        #expect(rt.state.knobs.group == "Right")
        click(rt, "knobs-random")
        #expect(rt.state.knobs.values["Right pad"] != nil, "Random acts on the group in use")
        #expect(rt.state.knobs.values["Left size"] == nil)
    }

    @Test("the_edge_drags_to_resize")
    func theEdgeDragsToResize() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        let (x, y) = rt.find("knobs-edge")!
        _ = rt.pointerDown(x, y)
        rt.pointerMove(x - 60.0, y)
        rt.pointerUp(x - 60.0, y)
        settle(rt)
        #expect(rt.state.knobs.sideW() == SIDE_W + 60.0)
        #expect(pageW(rt) == 1000.0 - SIDE_W - 60.0)
    }

    @Test("choices_fit_the_width")
    func choicesFitTheWidth() {
        let few = Knob.choice("Edge", ["Fade", "Line", "Tint"], 0)
        let six = Knob.choice("Question glyph", ["Disc", "? disc", "? mark", "? square", "? ring", "Bang"], 0)
        let many = Knob.choice("Theme picker style", ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"], 0)
        #expect(shape(few, 316.0, false) == .inline)
        // Six options come out as two even rows of three, not four and two.
        #expect(shape(six, 316.0, false) == .grid(cols: 3))
        #expect(shape(six, 600.0, false) == .inline)
        if case .long = shape(many, 316.0, false) {
            #expect(Bool(true))
        } else {
            Issue.record("expected ChoiceShape.long for 12 options at 316 pt")
        }
    }

    @Test("folding_rolls_the_rows_up_on_the_fold_spring")
    func foldingRollsTheRowsUpOnTheFoldSpring() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        s.knobs.setFolded("Left", false)
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        let seen: (Runtime<SideT>) -> Float = { r in
            r.elements().first(where: { $0.path.contains("knobs-sec-0") && $0.key == "body" })!.rect[3]
        }
        let open = seen(rt)
        let (x, y) = rt.find("knobs-sec-0/head")!
        rt.pointerMove(x, y)
        _ = rt.frame(1.0 / 60.0)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        for _ in 0..<4 {
            _ = rt.frame(1.0 / 60.0)
        }
        let mid = seen(rt)
        #expect(mid > 1.0 && mid < open - 1.0, "partway: \(mid) of \(open)")
        settle(rt)
        #expect(seen(rt) < 0.5)
    }

    @Test("hovering_an_option_says_what_it_does_under_the_list")
    func hoveringAnOptionSaysWhatItDoesUnderTheList() {
        var s = SideT(knobs: Knobs())
        s.knobs.show()
        s.knobs.setFolded("Left", false)
        let rt = Runtime.new(s, sideView, (1000.0, 700.0), Env.new(true, 1.0))
        settle(rt)
        #expect(rt.find("knobs-about-option") == nil, "nothing in hand, so the keys show")
        let (x, y) = rt.find("opt-1")!
        rt.pointerMove(x, y)
        settle(rt)
        #expect(rt.find("knobs-about-option") != nil, "the hovered option's line shows")
        #expect(sideC.hint(1) == "The second")
        #expect(sideC.hint(2) == "", "an option without a line says nothing")
    }

    @Test("right_clicking_a_knob_puts_only_it_back")
    func rightClickingAKnobPutsOnlyItBack() {
        let rt = openLeft()
        rt.state.knobs.set(sideL, 8.0)
        rt.state.knobs.set(sideC, 2.0)
        let r = rect(rt, "knobs-sec-0/body/knobs-card/knobs-knob-0")
        rightClick(rt, r[0] + 40.0, r[1] + r[3] / 2.0)
        #expect(rt.state.knobs.get(sideL) == 5.0, "back to its default")
        #expect(rt.state.knobs.get(sideC) == 2.0, "its neighbour keeps its value")
        rt.state.knobs.undo()
        #expect(rt.state.knobs.get(sideL) == 8.0, "undoable")
    }

    @Test("a_hovered_group_header_offers_random_and_reset")
    func aHoveredGroupHeaderOffersRandomAndReset() {
        let rt = openLeft()
        rt.state.knobs.set(sideL, 8.0)
        rt.state.knobs.set(sideR, 30.0)
        #expect(rt.find("knobs-sec-0/head/reset") == nil, "the count shows until hovered")
        let h = rect(rt, "knobs-sec-0/head")
        rt.pointerMove(h[0] + 40.0, h[1] + h[3] / 2.0)
        settle(rt)
        click(rt, "knobs-sec-0/head/reset")
        #expect(rt.state.knobs.get(sideL) == 5.0, "Reset puts the group back")
        #expect(rt.state.knobs.get(sideR) == 30.0, "and leaves other groups alone")
        #expect(rt.find("knobs-sec-0/body/knobs-card/knobs-knob-0") != nil, "without folding the group")
        click(rt, "knobs-sec-0/head/random")
        #expect(rt.state.knobs.values["Left size"] != nil, "Random sets the group's knobs")
        rightClick(rt, h[0] + 40.0, h[1] + h[3] / 2.0)
        #expect(rt.state.knobs.values["Left size"] == nil, "right-clicking the header resets it too")
    }

    @Test("clicking_a_choice_row_puts_the_arrows_on_its_options")
    func clickingAChoiceRowPutsTheArrowsOnItsOptions() {
        let rt = openLeft()
        // Put the keyboard elsewhere first, on the header above.
        let r = rect(rt, "knobs-sec-0/head")
        click(rt, "knobs-sec-0/head")
        click(rt, "knobs-sec-0/head")
        #expect(rt.state.knobs.at() == .group(0), "at \(r)")
        let rowRect = rect(rt, "knobs-sec-0/body/knobs-card/knobs-knob-1")
        let (x, y) = (rowRect[0] + 20.0, rowRect[1] + rowRect[3] / 2.0)
        rt.pointerMove(x, y)
        settle(rt)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        settle(rt)
        press(rt, .right)
        #expect(rt.state.knobs.get(sideC) == 1.0, "→ steps the clicked choice, not the group")
        press(rt, .right)
        #expect(rt.state.knobs.get(sideC) == 2.0)
    }

    @Test("moving_the_pointer_takes_the_highlight_from_the_keyboard")
    func movingThePointerTakesTheHighlightFromTheKeyboard() {
        let rt = openLeft()
        click(rt, "knobs-sec-0/head")
        click(rt, "knobs-sec-0/head")
        press(rt, .down)
        #expect(rt.state.knobs.kbd, "the keyboard's row is lit")
        let rowRect = rect(rt, "knobs-sec-0/body/knobs-card/knobs-knob-1")
        rt.pointerMove(rowRect[0] + 30.0, rowRect[1] + rowRect[3] / 2.0)
        settle(rt)
        #expect(!rt.state.knobs.kbd, "only the row under the pointer stays lit")
        press(rt, .down)
        #expect(rt.state.knobs.kbd, "a key lights the keyboard's row again")
    }
}
}
