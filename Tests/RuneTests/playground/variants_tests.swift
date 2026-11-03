// Tests ported from: crates/rune/src/playground/variants_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func pgLabVariants() -> Playground<PgTestReal> {
    let story = Story<PgTestLab>.new("Variants/Pressed", { PgTestLab() }, pgTestLabView)
        .variant("Few") { p in p.presses = 5 }
        .variant("Many") { p in p.presses = 50 }
        .trigger("x", "Clear") { p, _ in p.presses = 0 }
    return pgBase().story(story)
}

@Suite("PlaygroundVariantsTests")
struct PlaygroundVariantsTests {
    @Test func digitsSwitchAStorysVariantAndRRemakesTheOneItsOn() {
        let rt = pgRuntimeWith(pgLabVariants(), .some("Pressed"), windowed: true)
        #expect(pgShows(rt, "lab") == "ticks 0 presses 5")
        #expect(pgFind(rt, "playground-variant-0") != nil && pgFind(rt, "playground-variant-1") != nil)
        let hintList = pgShows(rt, "playground-hint").replacingOccurrences(of: "\u{a0}", with: " ")
        #expect(hintList == "↑↓ stories · ←→ groups · / filter · Tab controls · Esc back")
        let hintRect = pgFind(rt, "playground-hint")!.rect
        let sideRect = pgFind(rt, "playground-side")!.rect
        let (oneLine, lineH) = measure(pgShows(rt, "playground-hint"), [], tok.type_.SECTION)
        #expect(hintRect[0] + hintRect[2] <= sideRect[0] + sideRect[2])
        #expect(oneLine <= hintRect[2] - 8.0 || hintRect[3] > 1.5 * lineH)

        let all = rt.hostElements()
        let caps = all.compactMap { e -> String? in
            guard let p = e.parent, all[p].key == "cap" else { return nil }
            return e.text
        }
        #expect(caps == ["1", "2", "R", "X"])

        pgLetter(rt, "2")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 5")
        pgPress(rt, .tab)
        let hintSide = pgShows(rt, "playground-hint").replacingOccurrences(of: "\u{a0}", with: " ")
        #expect(hintSide == "↑↓ controls · 1–2 variants · Esc stories")
        pgLetter(rt, "2")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 50")
        pgTap(rt, "bump")
        pgEscape(rt)
        pgLetter(rt, "r")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 50")
        pgPress(rt, .tab)
        pgLetter(rt, "3")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 50")
        pgLetter(rt, "x")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "lab") == "ticks 0 presses 0")
        pgTap(rt, "playground-variant-0")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 5")
        pgLetter(rt, "2")
        pgEscape(rt)
        pgLetter(rt, "k")
        pgLetter(rt, "j")
        #expect(pgShows(rt, "lab") == "ticks 0 presses 50")
        pgEscape(rt)
        rt.update { _, tx in tx.openPlayground() }
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "lab") == "ticks 0 presses 5")
    }

    @Test func aSceneHasVariantsTooAppliedAfterItsSceneFn() {
        let scenes = pgBase()
            .variant("Still", "Ten") { s in s.count = 10 }
            .variant("Still", "Twenty") { s in s.count = 20 }
            .trigger("Still", "d", "Double") { s, _ in s.count *= 2 }
        let rt = pgRuntimeWith(scenes, .some("Still"), windowed: true)
        #expect(pgShows(rt, "count") == "count 10")
        pgPress(rt, .tab)
        pgLetter(rt, "2")
        #expect(pgShows(rt, "count") == "count 20")
        pgLetter(rt, "d")
        _ = rt.frame(PG_DT)
        #expect(pgShows(rt, "count") == "count 40")
        pgLetter(rt, "r")
        #expect(pgShows(rt, "count") == "count 20")
        pgEscape(rt)
        pgLetter(rt, "k")
        #expect(pgFind(rt, "playground-variant-0") == nil)
        pgPress(rt, .tab)
        pgLetter(rt, "1")
        #expect(pgShows(rt, "count") == "count 0")
    }
}
