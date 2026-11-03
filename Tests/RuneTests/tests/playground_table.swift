// Tests ported from: crates/rune/tests/playground_table.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PgTableReal {
    init() {}
}

private func pgTableRealView(_: PgTableReal, _: Cx<PgTableReal>) -> El {
    text("the app")
}

private struct PgTableCounter {
    var n: UInt32
}

private struct PgTableRow {
    var path: String
    var start: UInt32
    var step: UInt32
    var label: String
}

private func pgTableRows() -> [PgTableRow] {
    (0..<50).map { (i: UInt32) in
        PgTableRow(
            path: "Group \(i / 10)/Story \(i)",
            start: i * 10,
            step: i + 1,
            label: "row \(i)"
        )
    }
}

private func pgTableRuntime() -> Runtime<PgTableReal> {
    var pg = Playground<PgTableReal>.new()
    for row in pgTableRows() {
        let start = row.start
        let step = row.step
        let label = row.label
        let story = Story.new(
            row.path,
            { PgTableCounter(n: start) },
            { c, _ in text("\(label) \(c.n)").key("counter") }
        )
        .trigger("a", "Add") { c, _ in c.n += step }
        .trigger("l", "Add later") { _, play in
            play.after(0.5) { c, _ in c.n += step }
        }
        .triggerTx("z", "Zero") { c, tx in
            c.n = 0
            tx.instant()
        }
        .variant("As listed") { _ in }
        .variant("Doubled") { c in c.n = start * 2 }
        pg = pg.story(story)
    }
    return App.new(AppSpec.new("table", (800.0, 500.0), PgTableReal.init, pgTableRealView))
        .playground(pg)
        .headlessRuntime((800.0, 500.0), Env.new(false, 1.0))
}

private func pgTableShows(_ rt: Runtime<PgTableReal>) -> String {
    rt.playgroundElement("counter")?.text ?? ""
}

@Suite("PlaygroundTableIntegrationTests")
struct PlaygroundTableIntegrationTests {
    @Test func fiftyStoriesFromATableEachWithItsOwnRow() {
        let rt = pgTableRuntime()
        #expect(playgroundSlug("Group 3/Story 37") == "group-3-story-37")
        rt.openPlayground("group-3-story-37", nil)
        #expect(pgTableShows(rt) == "row 37 370")
        rt.playgroundTrigger("a")
        let n1 = rt.playgroundState(PgTableCounter.self)?.n
        #expect(n1 == 408)
        rt.playgroundTrigger("l")
        for _ in 0..<40 {
            _ = rt.frame(1.0 / 60.0)
        }
        let n2 = rt.playgroundState(PgTableCounter.self)?.n
        #expect(n2 == 446)
        rt.playgroundTrigger("z")
        let n3 = rt.playgroundState(PgTableCounter.self)?.n
        #expect(n3 == 0)
        rt.openPlayground("group-0-story-4", "Doubled")
        #expect(pgTableShows(rt) == "row 4 80")
    }
}
