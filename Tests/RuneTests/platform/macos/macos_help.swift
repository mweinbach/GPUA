// Tests ported from: crates/rune/src/platform/macos/help.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MacosHelpTests")
struct MacosHelpTests {
    @Test("only changed regions are replaced")
    func onlyChangedRegionsAreReplaced() {
        let toolbar: ([Float], String) = ([10.0, 4.0, 30.0, 24.0], "Copy")
        let row: (Float) -> ([Float], String) = { y in ([0.0, y, 200.0, y + 20.0], "Open") }
        // A list scrolled under a still toolbar button: the button's tooltip stays registered.
        let (stays1, covered1) = macHelpDiff([toolbar, row(40.0)], [toolbar, row(30.0)])
        #expect(stays1 == [true, false])
        #expect(covered1 == [true, false])
        // Two identical regions each keep one registration.
        let (stays2, covered2) = macHelpDiff([toolbar, toolbar], [toolbar])
        #expect(stays2 == [true, false])
        #expect(covered2 == [true])
        #expect(macHelpSnap([10.3, 4.74, 30.0, 24.2], 2.0) == [10.5, 4.5, 30.0, 24.0])
    }
}
