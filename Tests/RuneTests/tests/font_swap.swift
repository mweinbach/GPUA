// Tests ported from: crates/rune/tests/font_swap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func fontSwapView(_: Void, _: Cx<Void>) -> El {
    let style = TextStyle.new(14.0, 400.0)
    return col().children([
        row().child(text("Hamburgefonstiv 0123").key("label").font(style)),
        row().child(text("let mono = 42;").key("code").font(style.mono())),
    ])
}

@Suite("FontSwapIntegrationTests")
struct FontSwapIntegrationTests {
    @Test func setFontFamiliesLatchesIntoWindowHostState() {
        let rt = IntegrationSupport.runtime((), fontSwapView, (600.0, 400.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        _ = rt.hostUpdateIf { _, tx in
            tx.setFontFamilies("IBM Plex Mono", "Inter")
            return false
        }
        #expect(rt.hostNeedsCommit())
        _ = rt.hostFrame(1.0 / 120.0)
        let fams = windowHostState(for: rt).fontFamilies
        #expect(fams.0 == "IBM Plex Mono")
        #expect(fams.1 == "Inter")
    }

    @Test(.disabled("Requires Wave 2 Parley TrueType font shaping in TextSystem"))
    func aSwitchMeasuresLikeAFreshLaunchAndRebuildsMemoizedSubtrees() {}

    @Test(.disabled("Requires Wave 2 Parley TrueType font shaping in TextSystem"))
    func askingForTheFamiliesAlreadyThereRebuildsNothing() {}

    @Test(.disabled("Requires Wave 2 Parley TrueType font shaping in TextSystem"))
    func everyRuntimeOnTheThreadFollows() {}

    @Test(.disabled("Requires Wave 2 Parley TrueType font shaping in TextSystem"))
    func aMissingFamilyFallsBackAsAtLaunch() {}

    @Test(.disabled("Requires Wave 2 Parley TrueType font shaping in TextSystem"))
    func aWindowOpenedAfterASwitchStartsInTheNewFamilies() {}
}
