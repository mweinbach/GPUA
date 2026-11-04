// Tests ported from: crates/rune-kit/src/css.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

@Test func parsesLayersAndInset() {
    let s = css.boxShadows(
        "#0000001a 0px 1px 1.5px 0px, #ffffff29 0px 0px 0px 0.5px inset, #00000000 0px 0px 0px 0px",
        { $0 }
    )
    #expect(s.count == 2)
    #expect(s[0].y == 1.0 && s[0].blur == 1.5 && s[0].inset == false)
    #expect(s[1].spread == 0.5 && s[1].inset == true)
}
