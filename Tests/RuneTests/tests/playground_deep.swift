// Tests ported from: crates/rune/tests/playground_deep.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgDeepReal {
    init() {}
}

private func pgDeepRealView(_: PgDeepReal, _: Cx<PgDeepReal>) -> El {
    text("the app")
}

private struct PgDeepCard {
    init() {}
}

private func pgDeepCardView(_: PgDeepCard, _: Cx<PgDeepCard>) -> El {
    text("card").key("card")
}

private func pgDeepScenes() -> [(String, (inout PgDeepReal) -> Void)] {
    [
        ("Launch", { _ in }),
        ("Fixtures/Empty", { _ in }),
    ]
}

private func pgDeepPlayground() -> Playground<PgDeepReal> {
    Playground<PgDeepReal>.new()
        .story(Story.new("Fixtures/Linux & Windows/General/Portal", PgDeepCard.init, pgDeepCardView))
        .story(Story.new("Settings panes/General/Microphone missing", PgDeepCard.init, pgDeepCardView))
        .story(Story.new("Settings panes/General/Portal", PgDeepCard.init, pgDeepCardView))
        .story(Story.new("Prototypes/HUD/Processing", PgDeepCard.init, pgDeepCardView))
        .story(Story.new("Prototypes/Onboarding/Option · Pill", PgDeepCard.init, pgDeepCardView))
        .story(Story.new("Toasts/Sync", PgDeepCard.init, pgDeepCardView))
}

private func pgDeepRuntime(_ pg: Playground<PgDeepReal>) -> Runtime<PgDeepReal> {
    var spec = AppSpec.new("deep", (900.0, 700.0), PgDeepReal.init, pgDeepRealView)
    spec.scenes = pgDeepScenes()
    return App.new(spec).playground(pg).headlessRuntime((900.0, 700.0), Env.new(false, 1.0))
}

private func pgDeepOrdered() -> Playground<PgDeepReal> {
    pgDeepPlayground().groupOrder(["Prototypes", "Settings panes", "Not a group", "Fixtures"])
}

private func pgDeepPressWith(_ rt: Runtime<PgDeepReal>, _ key: Key, _ mods: Mods) {
    _ = rt.hostKey(KeyEvent(key: key, mods: mods))
    _ = rt.frame(1.0 / 60.0)
}

private func pgDeepPress(_ rt: Runtime<PgDeepReal>, _ key: Key) {
    pgDeepPressWith(rt, key, Mods())
}

private func pgDeepTyped(_ rt: Runtime<PgDeepReal>, _ s: String) {
    pgDeepPress(rt, .text(s))
}

private func pgDeepElement(_ rt: Runtime<PgDeepReal>, _ key: String) -> ElementInfo? {
    rt.hostElements().first { $0.key == key && !$0.exiting }
}

private func pgDeepShown(_ rt: Runtime<PgDeepReal>, _ key: String) -> Bool {
    pgDeepElement(rt, key) != nil
}

private func pgDeepLabel(_ rt: Runtime<PgDeepReal>, _ key: String) -> String {
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
    guard let found = all.first(where: { $0.text != nil && inside($0) })?.text else {
        preconditionFailure("a label")
    }
    return found
}

private func pgDeepOpen(_ rt: Runtime<PgDeepReal>) -> String {
    let all = rt.hostElements()
    guard let at = all.firstIndex(where: { $0.key == "playground-title" }) else {
        preconditionFailure("a title")
    }
    let parts = all.filter { $0.parent == at }.compactMap(\.text)
    return parts.joined(separator: " › ")
}

private func pgDeepRows(_ rt: Runtime<PgDeepReal>) -> [String] {
    var rows: [(Float, String)] = rt.hostElements()
        .filter { !$0.exiting }
        .compactMap { e in
            guard let k = e.key, k.hasPrefix("playground-item-") || k.hasPrefix("playground-group-") else {
                return nil
            }
            return (e.rect[1], k)
        }
    rows.sort { $0.0 < $1.0 }
    return rows.map { $0.1.replacingOccurrences(of: "playground-", with: "") }
}

private func pgDeepFocused(_ rt: Runtime<PgDeepReal>) -> String? {
    rt.hostElements().first(where: \.focused)?.key
}

private func pgDeepTap(_ rt: Runtime<PgDeepReal>, _ key: String) {
    guard let (x, y) = rt.testCenter(key) else {
        preconditionFailure("no \(key)")
    }
    _ = rt.hostPointerMove(x, y)
    _ = rt.hostPointerDown(x, y)
    _ = rt.hostPointerUp(x, y)
    _ = rt.frame(1.0 / 60.0)
}

private func pgDeepReopen(_ rt: Runtime<PgDeepReal>) {
    rt.update { _, tx in tx.closePlayground() }
    _ = rt.frame(1.0 / 60.0)
    rt.update { _, tx in tx.openPlayground() }
    _ = rt.frame(1.0 / 60.0)
}

@Suite("PlaygroundDeepIntegrationTests")
struct PlaygroundDeepIntegrationTests {
    @Test func aPathNestsAsDeepAsItGoesAndEveryLookupFindsIt() {
        let rt = pgDeepRuntime(pgDeepPlayground())
        rt.openPlayground("Fixtures/Linux & Windows/General/Portal", nil)
        #expect(pgDeepOpen(rt) == "Fixtures › Linux & Windows › General › Portal")
        let rowList = pgDeepRows(rt)
        let deep = ["group-1", "item-1", "group-2-1", "group-2-2", "item-2"]
        #expect(deep.allSatisfy { rowList.contains($0) })
        #expect([pgDeepLabel(rt, "playground-group-2-1"), pgDeepLabel(rt, "playground-group-2-2")] == ["Linux & Windows", "General"])
        rt.openPlayground("prototypes-onboarding-option-pill", nil)
        #expect(pgDeepOpen(rt) == "Prototypes › Onboarding › Option · Pill")
        rt.openPlayground("Microphone missing", nil)
        #expect(pgDeepOpen(rt) == "Settings panes › General › Microphone missing")
        rt.openPlayground("Launch", nil)
        #expect(pgDeepOpen(rt) == "Scenes › Launch")
        rt.openPlayground("toasts-sync", nil)
        #expect(pgDeepOpen(rt) == "Toasts › Sync")
    }

    @Test func groupOrderListsTheNamedGroupsFirstScenesAndStoriesAlike() {
        let rt = pgDeepRuntime(pgDeepOrdered())
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(0.0)
        #expect(pgDeepOpen(rt) == "Prototypes › HUD › Processing")
        let expected = [
            "group-5", "group-5-1", "item-5", "group-6-1", "item-6",
            "group-3", "group-3-1", "item-3", "item-4",
            "group-1", "item-1", "group-2-1", "group-2-2", "item-2",
            "group-0", "item-0", "group-7", "item-7",
        ]
        #expect(pgDeepRows(rt) == expected)
        rt.update { _, tx in tx.openPlaygroundAt("Portal", nil) }
        _ = rt.frame(0.0)
        #expect(pgDeepOpen(rt) == "Settings panes › General › Portal")
        rt.update { _, tx in tx.openPlaygroundAt("Processing", nil) }
        _ = rt.frame(0.0)
        pgDeepTyped(rt, "j")
        #expect(pgDeepOpen(rt) == "Prototypes › Onboarding › Option · Pill")
        pgDeepTyped(rt, "j")
        #expect(pgDeepOpen(rt) == "Settings panes › General › Microphone missing")
        pgDeepPress(rt, .down)
        #expect(pgDeepOpen(rt) == "Settings panes › General › Portal")
        pgDeepTyped(rt, "/")
        pgDeepTyped(rt, "general")
        pgDeepPress(rt, .down)
        #expect(pgDeepOpen(rt) == "Settings panes › General › Microphone missing")
    }

    @Test func withoutGroupOrderScenesComeFirstAsBefore() {
        let rt = pgDeepRuntime(pgDeepPlayground())
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(0.0)
        #expect(pgDeepOpen(rt) == "Scenes › Launch")
        #expect(Array(pgDeepRows(rt).prefix(4)) == ["group-0", "item-0", "group-1", "item-1"])
    }

    @Test func startFoldedFoldsEverythingButTheOpenStorysGroups() {
        let rt = pgDeepRuntime(pgDeepOrdered().startFolded(true))
        rt.update { _, tx in tx.openPlaygroundAt("prototypes-onboarding-option-pill", nil) }
        _ = rt.frame(0.0)
        #expect(pgDeepRows(rt) == ["group-5", "group-5-1", "group-6-1", "item-6", "group-3", "group-1", "group-0", "group-7"])
        pgDeepTap(rt, "playground-group-3")
        #expect(pgDeepShown(rt, "playground-group-3-1") && !pgDeepShown(rt, "playground-item-3"))
        pgDeepReopen(rt)
        #expect(pgDeepShown(rt, "playground-group-3-1"))
        #expect(pgDeepShown(rt, "playground-item-6"))
    }

    @Test func startFoldedSavesTheUnfoldedGroupsAndLoadsThemNextRun() {
        final class SavedBox { var value: [String] = [] }
        let saved = SavedBox()
        let rt = pgDeepRuntime(
            pgDeepOrdered()
                .startFolded(true)
                .folds({ [] }, { groups in saved.value = groups })
        )
        rt.openPlayground("Processing", nil)
        pgDeepTap(rt, "playground-group-1")
        pgDeepTap(rt, "playground-group-2-1")
        #expect(saved.value == ["Prototypes", "Prototypes/HUD", "Fixtures", "Fixtures/Linux & Windows"])
        let names = saved.value
        let next = pgDeepRuntime(
            pgDeepOrdered()
                .startFolded(true)
                .folds({ names }, { _ in })
        )
        next.update { _, tx in tx.openPlaygroundAt("Toasts/Sync", nil) }
        _ = next.frame(0.0)
        #expect(pgDeepShown(next, "playground-group-2-2") && !pgDeepShown(next, "playground-item-2"))
        #expect(pgDeepShown(next, "playground-item-5") && !pgDeepShown(next, "playground-group-3-1"))
        #expect(pgDeepShown(next, "playground-item-7"))
    }

    @Test func foldsSaveFullPathsAndLoadOldOneLevelNames() {
        final class SavedBox { var value: [String] = [] }
        let saved = SavedBox()
        let rt = pgDeepRuntime(
            pgDeepOrdered().folds(
                { ["Toasts", "Fixtures/Linux & Windows/General", "Gone"] },
                { groups in saved.value = groups }
            )
        )
        rt.openPlayground("Processing", nil)
        #expect(!pgDeepShown(rt, "playground-item-7") && !pgDeepShown(rt, "playground-item-2") && pgDeepShown(rt, "playground-group-2-2"))
        pgDeepTap(rt, "playground-group-6-1")
        #expect(saved.value == ["Fixtures/Linux & Windows/General", "Toasts", "Prototypes/Onboarding"])
    }

    @Test func theFilterEditsLikeAFieldAndDownGoesIntoItsMatches() {
        let rt = pgDeepRuntime(pgDeepOrdered())
        rt.openPlayground("Toasts/Sync", nil)
        pgDeepTap(rt, "playground-filter")
        #expect(pgDeepFocused(rt) == "playground-filter")
        pgDeepTyped(rt, "hud")
        pgDeepPressWith(rt, .command("a"), Mods(cmd: true))
        pgDeepTyped(rt, "portal")
        #expect(pgDeepRows(rt) == ["group-3", "group-3-1", "item-4", "group-1", "group-2-1", "group-2-2", "item-2"])
        pgDeepPress(rt, .down)
        #expect(pgDeepOpen(rt) == "Settings panes › General › Portal")
        #expect(pgDeepFocused(rt) == nil)
        pgDeepTyped(rt, "j")
        #expect(pgDeepOpen(rt) == "Fixtures › Linux & Windows › General › Portal")
        pgDeepTyped(rt, "k")
        pgDeepPress(rt, .up)
        #expect(pgDeepFocused(rt) == "playground-filter")
        pgDeepPress(rt, .escape)
        #expect(pgDeepFocused(rt) == "playground-filter")
        #expect(pgDeepShown(rt, "playground-item-5"))
        pgDeepPress(rt, .escape)
        #expect(pgDeepFocused(rt) == nil)
        let stillOpen = rt.playgroundState(PgDeepCard.self) != nil
        #expect(stillOpen)
    }
}
