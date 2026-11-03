// Tests ported from: crates/rune/tests/playground_tree.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let pgTreeListHint = "↑↓ stories · ←→ groups · / filter · Tab controls · Esc back"

private struct PgTreeReal {
    init() {}
}

private func pgTreeRealView(_: PgTreeReal, _: Cx<PgTreeReal>) -> El {
    text("the app")
}

private struct PgTreeCard {
    var variant: UInt8 = 0
    var knob: String = ""
}

private func pgTreeCardView(_ c: PgTreeCard, _: Cx<PgTreeCard>) -> El {
    text("card \(c.variant)").key("card").onPress { (_: inout PgTreeCard, _: inout Tx) in }
}

private func pgTreeKnobKey(_ c: inout PgTreeCard, _ ev: KeyEvent, _: inout Tx) -> Bool {
    if case .text(let t) = ev.key, !t.isEmpty, t.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) {
        c.knob.append(t)
        return true
    }
    return false
}

private func pgTreePlayground() -> Playground<PgTreeReal> {
    Playground<PgTreeReal>.new()
        .story(
            Story.new("Sidebar/Rows/Plain", { PgTreeCard() }, pgTreeCardView)
                .variant("One") { c in c.variant = 1 }
                .variant("Two") { c in c.variant = 2 }
        )
        .story(Story.new("Sidebar/Rows/Pinned", { PgTreeCard() }, pgTreeCardView))
        .story(Story.new("Sidebar/Filter buttons/Compact", { PgTreeCard() }, pgTreeCardView))
        .story(Story.new("Sidebar/Filter buttons/Wide", { PgTreeCard() }, pgTreeCardView))
        .story(Story.new("Sidebar/Header", { PgTreeCard() }, pgTreeCardView))
        .story(
            Story.new("Dock/Icons", { PgTreeCard() }, pgTreeCardView)
                .sideKeys(
                    { c, active, _ in text("\(active ? "on" : "off") \(c.knob)").key("knob") },
                    pgTreeKnobKey
                )
        )
}

private func pgTreeRuntime(_ pg: Playground<PgTreeReal>, _ open: String) -> Runtime<PgTreeReal> {
    let rt = App.new(AppSpec.new("tree", (900.0, 600.0), PgTreeReal.init, pgTreeRealView))
        .playground(pg)
        .headlessRuntime((900.0, 600.0), Env.new(false, 1.0))
    rt.openPlayground(open, nil)
    return rt
}

private func pgTreePress(_ rt: Runtime<PgTreeReal>, _ key: Key) {
    _ = rt.hostKey(KeyEvent(key: key, mods: Mods()))
    _ = rt.frame(1.0 / 60.0)
}

private func pgTreeTyped(_ rt: Runtime<PgTreeReal>, _ s: String) {
    pgTreePress(rt, .text(s))
}

private func pgTreeElement(_ rt: Runtime<PgTreeReal>, _ key: String) -> ElementInfo? {
    rt.hostElements().first { $0.key == key && !$0.exiting }
}

private func pgTreeShown(_ rt: Runtime<PgTreeReal>, _ key: String) -> Bool {
    pgTreeElement(rt, key) != nil
}

private func pgTreeSays(_ rt: Runtime<PgTreeReal>, _ key: String) -> String {
    guard let t = pgTreeElement(rt, key)?.text else {
        preconditionFailure("no \(key)")
    }
    return t.replacingOccurrences(of: "\u{a0}", with: " ")
}

private func pgTreeLabel(_ rt: Runtime<PgTreeReal>, _ key: String) -> (String, Float) {
    let all = rt.hostElements()
    guard let at = all.firstIndex(where: { $0.key == key && !$0.exiting }) else {
        preconditionFailure("no \(key)")
    }
    func inside(_ e: ElementInfo) -> Bool {
        var cur = e.parent
        while let p = cur {
            if p == at { return true }
            cur = all[p].parent
        }
        return false
    }
    guard let found = all.first(where: { $0.text != nil && inside($0) }), let txt = found.text else {
        preconditionFailure("a label")
    }
    return (txt, found.rect[0])
}

private func pgTreeTitle(_ rt: Runtime<PgTreeReal>) -> String {
    let all = rt.hostElements()
    guard let at = all.firstIndex(where: { $0.key == "playground-title" }) else {
        preconditionFailure("a title")
    }
    let children = all.filter { $0.parent == at }.compactMap(\.text)
    return children.count > 1 ? children[1] : ""
}

private func pgTreeTapAt(_ rt: Runtime<PgTreeReal>, _ x: Float, _ y: Float) {
    _ = rt.hostPointerMove(x, y)
    _ = rt.hostPointerDown(x, y)
    _ = rt.hostPointerUp(x, y)
    _ = rt.frame(1.0 / 60.0)
}

private func pgTreeTap(_ rt: Runtime<PgTreeReal>, _ key: String) {
    guard let (x, y) = rt.testCenter(key) else {
        preconditionFailure("no \(key)")
    }
    pgTreeTapAt(rt, x, y)
}

private func pgTreeFocused(_ rt: Runtime<PgTreeReal>) -> String? {
    rt.hostElements().first(where: \.focused)?.key
}

private func pgTreeCardState(_ rt: Runtime<PgTreeReal>) -> (UInt8, String) {
    guard let c = rt.playgroundState(PgTreeCard.self) else {
        preconditionFailure("a card story")
    }
    return (c.variant, c.knob)
}

@Suite("PlaygroundTreeIntegrationTests")
struct PlaygroundTreeIntegrationTests {
    @Test func aPathNestsGroupsOneLevelPerSlash() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Sidebar/Filter buttons/Compact")
        let order = [
            "playground-group-0", "playground-group-0-1", "playground-item-0", "playground-item-1",
            "playground-group-2-1", "playground-item-2", "playground-item-3", "playground-item-4",
            "playground-group-5", "playground-item-5",
        ]
        let ys = order.map { pgTreeElement(rt, $0)!.rect[1] }
        for i in 0..<(ys.count - 1) {
            #expect(ys[i] < ys[i + 1])
        }
        #expect(pgTreeLabel(rt, "playground-group-2-1").0 == "Filter buttons")
        let sidebar = pgTreeLabel(rt, "playground-group-0").1
        let rows = pgTreeLabel(rt, "playground-group-0-1").1
        let compact = pgTreeLabel(rt, "playground-item-2").1
        let header = pgTreeLabel(rt, "playground-item-4").1
        #expect(header == sidebar)
        #expect(rows - sidebar == 12.0 && compact - header == 12.0)
        #expect([
            pgTreeSays(rt, "playground-count-0"),
            pgTreeSays(rt, "playground-count-0-1"),
            pgTreeSays(rt, "playground-count-2-1"),
            pgTreeSays(rt, "playground-count-5"),
        ] == ["5", "2", "2", "1"])
        #expect(pgTreeLabel(rt, "playground-title").0 == "Sidebar › Filter buttons")
        #expect(pgTreeTitle(rt) == "Compact")
    }

    @Test func everyLevelFoldsAndAFoldInsideOneOutlastsItsParents() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Dock/Icons")
        pgTreeTap(rt, "playground-group-2-1")
        #expect(!pgTreeShown(rt, "playground-item-2") && !pgTreeShown(rt, "playground-item-3"))
        #expect(pgTreeShown(rt, "playground-item-0") && pgTreeShown(rt, "playground-item-4"))
        pgTreeTap(rt, "playground-group-0")
        #expect(!pgTreeShown(rt, "playground-group-0-1") && !pgTreeShown(rt, "playground-group-2-1") && !pgTreeShown(rt, "playground-item-4"))
        #expect(pgTreeShown(rt, "playground-item-5"))
        pgTreeTap(rt, "playground-group-0")
        #expect(pgTreeShown(rt, "playground-item-0") && pgTreeShown(rt, "playground-group-2-1"))
        #expect(!pgTreeShown(rt, "playground-item-2"))
    }

    @Test func foldsKeepGroupsAtAnyLevelByTheirPath() {
        final class SavedBox { var saved: [[String]] = [] }
        let box = SavedBox()
        let pg = pgTreePlayground().folds(
            { ["Sidebar/Filter buttons", "Dock"] },
            { groups in box.saved.append(groups) }
        )
        let rt = pgTreeRuntime(pg, "Sidebar/Header")
        #expect(!pgTreeShown(rt, "playground-item-2") && pgTreeShown(rt, "playground-group-2-1"))
        #expect(!pgTreeShown(rt, "playground-item-5"))
        pgTreeTap(rt, "playground-group-0-1")
        #expect(box.saved.last == ["Sidebar/Filter buttons", "Dock", "Sidebar/Rows"])
        rt.openPlayground("Sidebar/Filter buttons/Wide", nil)
        #expect(pgTreeShown(rt, "playground-item-3"))
        #expect(box.saved.last == ["Dock", "Sidebar/Rows"])
    }

    @Test func arrowsWalkIntoAndOutOfNestedGroups() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Sidebar/Filter buttons/Compact")
        pgTreePress(rt, .left)
        pgTreePress(rt, .left)
        #expect(!pgTreeShown(rt, "playground-item-2"))
        pgTreePress(rt, .left)
        pgTreePress(rt, .left)
        #expect(!pgTreeShown(rt, "playground-group-0-1"))
        pgTreePress(rt, .left)
        #expect(!pgTreeShown(rt, "playground-group-0-1"))
        pgTreePress(rt, .right)
        #expect(pgTreeShown(rt, "playground-group-0-1") && !pgTreeShown(rt, "playground-item-2"))
        pgTreePress(rt, .right)
        pgTreePress(rt, .down)
        #expect(pgTreeTitle(rt) == "Plain")
        pgTreePress(rt, .down)
        pgTreePress(rt, .down)
        pgTreePress(rt, .right)
        #expect(pgTreeShown(rt, "playground-item-2"))
        pgTreePress(rt, .down)
        #expect(pgTreeTitle(rt) == "Compact")
        pgTreePress(rt, .down)
        pgTreePress(rt, .down)
        #expect(pgTreeTitle(rt) == "Header")
    }

    @Test func theFilterKeepsMatchesAndTheGroupsAboveThem() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Sidebar/Rows/Plain")
        pgTreeTyped(rt, "/")
        #expect(pgTreeFocused(rt) == "playground-filter")
        pgTreeTyped(rt, "filter wi")
        #expect(pgTreeShown(rt, "playground-group-0") && pgTreeShown(rt, "playground-group-2-1") && pgTreeShown(rt, "playground-item-3"))
        #expect(!pgTreeShown(rt, "playground-item-0") && !pgTreeShown(rt, "playground-item-2") && !pgTreeShown(rt, "playground-group-5"))
        #expect(pgTreeSays(rt, "playground-count-0") == "1")
        pgTreePress(rt, .enter)
        #expect(pgTreeTitle(rt) == "Wide" && pgTreeFocused(rt) == nil)
        pgTreeTyped(rt, "/")
        pgTreePress(rt, .escape)
        #expect(pgTreeShown(rt, "playground-item-0"))
    }

    @Test func theKeyboardMovesFromTheListToTheSideColumnAndBack() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Sidebar/Rows/Plain")
        #expect(pgTreeSays(rt, "playground-hint") == pgTreeListHint)
        pgTreeTyped(rt, "2")
        #expect(pgTreeCardState(rt).0 == 1)
        pgTreePress(rt, .tab)
        #expect(pgTreeSays(rt, "playground-hint") == "↑↓ controls · 1–2 variants · Esc stories")
        #expect(pgTreeFocused(rt) == "playground-variant-0")
        pgTreeTyped(rt, "2")
        #expect(pgTreeCardState(rt).0 == 2)
        pgTreePress(rt, .escape)
        #expect(pgTreeSays(rt, "playground-hint") == pgTreeListHint && pgTreeFocused(rt) == nil)
        pgTreePress(rt, .down)
        #expect(pgTreeTitle(rt) == "Pinned")
        pgTreePress(rt, .right)
        #expect(pgTreeSays(rt, "playground-hint").hasPrefix("↑↓ controls"))
    }

    @Test func sideKeysHearOnlyTheSideColumn() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Dock/Icons")
        pgTreeTyped(rt, "3")
        #expect(pgTreeCardState(rt).1.isEmpty)
        pgTreePress(rt, .right)
        pgTreeTyped(rt, "3")
        #expect(pgTreeSays(rt, "knob") == "on 3")
        pgTreePress(rt, .escape)
        pgTreeTyped(rt, "4")
        #expect(pgTreeSays(rt, "knob") == "off 3")
    }

    @Test func aClickGivesItsColumnTheKeyboard() {
        let rt = pgTreeRuntime(pgTreePlayground(), "Sidebar/Rows/Plain")
        pgTreeTap(rt, "card")
        #expect(pgTreeSays(rt, "playground-hint") == "Keys go to the story · Esc stories")
        #expect(pgTreeShown(rt, "playground-stage-ring"))
        pgTreePress(rt, .down)
        pgTreeTyped(rt, "j")
        #expect(pgTreeTitle(rt) == "Plain")
        let side = pgTreeElement(rt, "playground-side")!.rect
        pgTreeTapAt(rt, side[0] + side[2] * 0.5, side[1] + side[3] * 0.6)
        #expect(pgTreeSays(rt, "playground-hint").hasPrefix("↑↓ controls"))
        #expect(!pgTreeShown(rt, "playground-stage-ring"))
        pgTreeTyped(rt, "2")
        #expect(pgTreeCardState(rt).0 == 2)
        pgTreeTap(rt, "playground-item-1")
        #expect(pgTreeSays(rt, "playground-hint") == pgTreeListHint && pgTreeTitle(rt) == "Pinned")
        pgTreePress(rt, .escape)
        let closed = rt.playgroundState(PgTreeCard.self) == nil
        #expect(closed)
    }
}
