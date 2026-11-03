// Tests ported from: crates/rune/tests/deco_api.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("DecoApiIntegrationTests")
struct DecoApiIntegrationTests {
    @Test(.disabled("Requires Wave 2 text.Deco in Spine text.swift"))
    func decorationLiteralRemainsSourceCompatible() {}
}
