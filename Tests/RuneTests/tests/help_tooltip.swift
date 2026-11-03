// Tests ported from: crates/rune/tests/help_tooltip.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct HelpTooltipState {
    var presses: UInt32 = 0
    var hovered: Bool = false
    var inset: Float = 0.0
}

private func helpTooltipView(_ s: HelpTooltipState, _: Cx<HelpTooltipState>) -> El {
    col().wFull().hFull().padding(20.0).gap(10.0)
        .child(
            row().pl(s.inset)
                .child(
                    el().key("copy").size(28.0, 28.0)
                        .help("Copy the command")
                        .onPress { (s: inout HelpTooltipState, _: inout Tx) in s.presses += 1 }
                        .onHoverChange { (s: inout HelpTooltipState, on: Bool, _: inout Tx) in s.hovered = on }
                )
        )
        .child(el().key("plain").size(100.0, 28.0))
        .child(el().wFull().grow(1.0))
        .child(el().key("low").size(60.0, 24.0).help("Near the bottom"))
}

private func helpTooltipRuntime() -> Runtime<HelpTooltipState> {
    let rt = IntegrationSupport.runtime(HelpTooltipState(), helpTooltipView, (400.0, 300.0), Env.new(true, 2.0))
    _ = rt.hostFrame(0.0)
    return rt
}

@Suite("HelpTooltipIntegrationTests")
struct HelpTooltipIntegrationTests {
    @Test func hoverReadsHelpTextAndHidesOnLeave() {
        let rt = helpTooltipRuntime()
        #expect(IntegrationSupport.find(rt, "copy").help == "Copy the command")
        let copyCenter = IntegrationSupport.centre(IntegrationSupport.find(rt, "copy"))
        _ = rt.hostPointerMove(copyCenter.0, copyCenter.1)
        _ = rt.hostFrame(1.0 / 60.0)
        let hovered = rt.state.hovered
        #expect(hovered)
        #expect(rt.hostHelpTooltip()?.0 == "Copy the command")

        let plainCenter = IntegrationSupport.centre(IntegrationSupport.find(rt, "plain"))
        _ = rt.hostPointerMove(plainCenter.0, plainCenter.1)
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(rt.hostHelpTooltip() == nil)

        _ = rt.hostPointerMove(copyCenter.0, copyCenter.1)
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(rt.hostHelpTooltip()?.0 == "Copy the command")
        _ = rt.hostPointerLeave()
        _ = rt.hostFrame(1.0 / 60.0)
        #expect(rt.hostHelpTooltip() == nil)
        #expect(rt.hostElements().contains { $0.help != nil })
    }

    @Test func pressStillReachesElementWithHelp() {
        let rt = helpTooltipRuntime()
        let copyCenter = IntegrationSupport.centre(IntegrationSupport.find(rt, "copy"))
        IntegrationSupport.click(rt, copyCenter)
        let presses = rt.state.presses
        #expect(presses == 1)
    }

    @Test(.disabled("Requires Wave 2 Runtime.helpDelay timer and popup tooltip flip layout"))
    func followsItsElementAndFlipsAboveAtTheBottom() {}
}
