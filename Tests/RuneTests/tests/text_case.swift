// Tests ported from: crates/rune/tests/text_case.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("TextCaseIntegrationTests")
struct TextCaseIntegrationTests {
    @Test(.disabled("Requires Wave 2 El.textCase and El.link in Spine El/Runtime"))
    func casedTextDrawsCapitalsAndReportsItsAuthoredString() {}

    @Test(.disabled("Requires Wave 2 El.textCase and El.link in Spine El/Runtime"))
    func spansAndLinksKeepTheirAuthoredByteRanges() {}
}
