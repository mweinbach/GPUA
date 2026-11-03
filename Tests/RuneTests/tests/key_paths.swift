// Tests ported from: crates/rune/tests/key_paths.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func keyPathsList(_ key: String) -> El {
    var rows = col().wFull()
    for _ in 0..<30 {
        rows = rows.child(el().wFull().h(30.0))
    }
    return col().key(key).w(100.0).h(200.0).scroll(ScrollSpec(stickBottom: false))
        .child(rows.child(el().key("label").wFull().h(30.0)))
}

private func keyPathsView(_: Void, _: Cx<Void>) -> El {
    row().wFull().hFull().child(keyPathsList("a")).child(keyPathsList("b"))
}

private func keyPathsLabelY(_ rt: Runtime<Void>, _ nth: Int) -> Float {
    let matches = rt.hostElements().filter { $0.key == "label" }
    return matches[nth].rect[1]
}

private func keyPathsSettled(_ f: (inout Tx) -> Void) -> Runtime<Void> {
    let rt = IntegrationSupport.runtime((), keyPathsView, (200.0, 200.0), Env())
    _ = rt.hostFrame(0.0)
    #expect(keyPathsLabelY(rt, 0) == 900.0 && keyPathsLabelY(rt, 1) == 900.0)
    rt.hostUpdate { _, tx in f(&tx) }
    for _ in 0..<120 {
        _ = rt.hostFrame(1.0 / 60.0)
    }
    return rt
}

@Suite("KeyPathsIntegrationTests")
struct KeyPathsIntegrationTests {
    @Test func scrollIntoViewTakesAKeyPath() {
        let rt = keyPathsSettled { $0.scrollIntoView("b/label") }
        #expect(keyPathsLabelY(rt, 1) < 200.0)
        #expect(keyPathsLabelY(rt, 0) == 900.0)
        let bare = keyPathsSettled { $0.scrollIntoView("label") }
        #expect(keyPathsLabelY(bare, 0) < 200.0 && keyPathsLabelY(bare, 1) == 900.0)
    }

    @Test func scrollToBottomTakesAKeyPath() {
        let rt = keyPathsSettled { $0.scrollToBottomInstant("b/label") }
        #expect(keyPathsLabelY(rt, 1) < 200.0)
        #expect(keyPathsLabelY(rt, 0) == 900.0)
    }

    @Test func scrollToOffsetTakesAKeyPath() {
        let rt = keyPathsSettled { $0.scrollToInstant("b/label", 0.0, 400.0) }
        #expect(keyPathsLabelY(rt, 1) == 500.0)
        #expect(keyPathsLabelY(rt, 0) == 900.0)
    }

    @Test(.disabled("Requires Wave 2 El.virtualRows in Spine El"))
    func scrollIntoViewReachesAnOffscreenVirtualRowByKeyPath() {}
}
