// Tests ported from: crates/rune/src/runtime/input/help.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputHelpTests")
struct InputHelpTests {
    @Test("Hovering a help element schedules wake deadline, reveals tooltip after delay, and warms adjacent transitions")
    func helpTooltipDelaysWarmsAndClears() {
        let rt = Runtime.new((), { _, _ in
            var cutChild = el().key("cut").size(40.0, 20.0).bg(oklch(0.5, 0.1, 180.0))
            cutChild.helpCutFlag = true
            return col().wFull().hFull()
                .child(el().key("copy").size(60.0, 30.0).bg(oklch(0.6, 0.1, 220.0)).help("Copy")
                    .child(cutChild))
                .child(el().key("low").size(60.0, 30.0).bg(oklch(0.6, 0.1, 240.0)).help("Low"))
        }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        // Hover over `copy` below `cutChild`
        rt.pointerMove(50.0, 25.0)
        #expect(rt.activeHelp() == nil)
        #expect(rt.wakeDeadline() != nil)

        // Advance past `HELP_HOVER_DELAY` (0.5 s)
        _ = rt.frame(0.55)
        #expect(rt.activeHelp()?.text == "Copy")

        // While warm, moving directly to `low` shows "Low" immediately without re-waiting
        rt.pointerMove(20.0, 45.0)
        #expect(rt.activeHelp()?.text == "Low")

        // Moving onto `cutChild` (helpCut = true) suppresses ancestor "Copy" help
        rt.pointerMove(10.0, 10.0)
        #expect(rt.activeHelp() == nil)
    }
}
