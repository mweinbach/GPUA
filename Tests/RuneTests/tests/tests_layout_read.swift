// Tests ported from: crates/rune/tests/layout_read.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct LayoutReadBannerState {
    var banner: Bool = false
}

private func layoutReadBannerView(_ s: LayoutReadBannerState, _ cx: Cx<LayoutReadBannerState>) -> El {
    var root = col().wFull().hFull().padding(10.0)
        .child(el().key("banner").wFull().h(s.banner ? 55.0 : 20.0))
        .child(col().key("timeline").wFull().grow(1.0).shrink())
    if let r = cx.layout("banner"), r.count == 4 {
        root = root.child(el().key("badge").absolute(r[0] + r[2] - 30.0, r[1] + r[3]).size(30.0, 10.0))
    }
    return root
}

@Suite("LayoutReadIntegrationTests")
struct LayoutReadIntegrationTests {
    @Test func cxLayoutReadsPreviousLaidOutRectAndUpdatesOnNextCommit() {
        let rt = IntegrationSupport.runtime(LayoutReadBannerState(), layoutReadBannerView, (300.0, 400.0), Env.new(true, 2.0))
        _ = rt.hostFrame(0.0)
        let badge1 = IntegrationSupport.find(rt, "badge").target
        #expect(badge1 == [260.0, 30.0, 30.0, 10.0])

        rt.hostUpdate { s, _ in s.banner = true }
        _ = rt.hostFrame(1.0 / 120.0)
        let badge2 = IntegrationSupport.find(rt, "badge").target
        #expect(badge2 == [260.0, 65.0, 30.0, 10.0])
    }

    @Test(.disabled("Requires Wave 2 intra-commit settling loop, Cx.layoutSize, Cx.windowLayoutWith, and El.onLayout in Spine Runtime"))
    func intraCommitLayoutSettlingAndSizeThresholds() {}
}
