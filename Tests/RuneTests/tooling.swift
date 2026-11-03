// Tests ported from: crates/rune/src/tooling.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Note: `crates/rune/src/tooling.rs` includes `tooling/parser_tests.rs` and `tooling/tests.rs`,
// which are ported in their paired files `Tests/RuneTests/tooling/parser_tests.swift` and
// `Tests/RuneTests/tooling/tooling_tests.swift`.

@Suite("ToolingSpecTests")
struct ToolingSpecTests {
    @Test func initialStateAppliesNamedScene() {
        let spec = AppSpec(
            title: "demo",
            size: (200.0, 120.0),
            init: { 1 },
            view: { _, _ in el() },
            scenes: [("ten", { $0 = 10 }), ("twenty", { $0 = 20 })]
        )
        #expect(initialState(spec) == 1)
        #expect(initialState(spec, "twenty") == 20)
    }
}
