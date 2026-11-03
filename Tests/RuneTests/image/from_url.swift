// Tests ported from: crates/rune/src/image/from_url.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// PORT NOTE: Paired behavioral tests live in `Tests/RuneTests/image/from_url_tests.swift`
// (`crates/rune/src/image/from_url_tests.rs`). This file tests `percentDecodeUrlPath` directly.

@Suite("ImageFromUrlHelperTests")
struct ImageFromUrlHelperTests {
    @Test("percentDecodeUrlPath decodes UTF-8 escapes and rejects truncated hex")
    func percentDecodeUrlPathDecodesAndRejectsInvalid() {
        #expect(percentDecodeUrlPath("/tmp/hello%20world.png") == "/tmp/hello world.png")
        #expect(percentDecodeUrlPath("/tmp/%C3%A9.png") == "/tmp/é.png")
        #expect(percentDecodeUrlPath("/tmp/bad%") == nil)
        #expect(percentDecodeUrlPath("/tmp/bad%2") == nil)
        #expect(percentDecodeUrlPath("/tmp/bad%zz") == nil)
    }
}
