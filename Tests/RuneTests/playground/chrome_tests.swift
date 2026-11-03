// Tests ported from: crates/rune/src/playground/chrome_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pgFill(_ rt: Runtime<PgTestReal>, _ key: String) -> Rune.Color {
    pgFind(rt, key)!.fill
}

@Suite("PlaygroundChromeTests")
struct PlaygroundChromeTests {
    @Test func theChromeFollowsTheAppsOwnDarkSetting() {
        let rt = pgRuntimeWith(pgBase().dark { s in s.count >= 100 }, .some("Fade"), windowed: true)
        #expect(pgFill(rt, "playground") == tok.theme(false).bg)
        rt.state.count = 100
        rt.update { _, _ in }
        for _ in 0..<60 { _ = rt.frame(PG_DT) }
        #expect(pgFill(rt, "playground") == tok.theme(true).bg)
        #expect(pgFind(rt, "playground-theme")?.label == "Dark appearance")
    }

    @Test func withoutItTheChromeFollowsTheSystem() {
        let rt = pgRuntime(.some("Fade"))
        rt.state.count = 100
        rt.update { _, _ in }
        for _ in 0..<60 { _ = rt.frame(PG_DT) }
        #expect(pgFill(rt, "playground") == tok.theme(false).bg)
    }
}
