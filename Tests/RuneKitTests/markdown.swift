// Tests ported from: crates/rune-kit/src/markdown.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/markdown.rs` declares `#[cfg(test)] mod tests;`
// pointing to `crates/rune-kit/src/markdown/tests.rs`, whose unit tests live in
// `Tests/RuneKitTests/markdown/markdown_tests.swift`.

import Testing
@testable import RuneKit

@Suite("MarkdownModuleSmokeTests")
struct MarkdownModuleSmokeTests {
    @Test func highlightKeyFormatsDefaultPrefix() {
        #expect(Markdown.highlightKey(0) == "md-mark-0")
        #expect(Markdown.highlightKey(42) == "md-mark-42")
    }
}
