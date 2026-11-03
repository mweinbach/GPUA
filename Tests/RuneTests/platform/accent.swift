// Tests ported from: crates/rune/src/platform/accent.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AccentTests")
struct AccentTests {
    @Test("the default is macos blue with rings at half")
    func defaultIsMacosBlueWithRingsAtHalf() {
        let a = SystemAccent.DEFAULT
        #expect(a.accent(false).hex() == "#007affff")
        #expect(a.accent(true).hex() == "#0a84ffff")
        #expect(a.focus(false).hex() == "#007aff80")
        #expect(a.focus(true).hex() == "#0a84ff80")
    }
}
