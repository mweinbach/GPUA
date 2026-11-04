// Tests ported from: crates/rune-kit/src/markdown/stream.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/markdown/stream.rs` declares `#[cfg(test)] #[path = "stream_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneKitTests/markdown/stream_tests.swift`.

import Testing
@testable import RuneKit

@Suite("MarkdownStreamModuleSmokeTests")
struct MarkdownStreamModuleSmokeTests {
    @Test func emptyStreamParsesCleanly() {
        #expect(parseStreaming("", true).blocks.isEmpty)
    }
}
