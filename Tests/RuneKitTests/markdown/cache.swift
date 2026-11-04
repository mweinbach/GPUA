// Tests ported from: crates/rune-kit/src/markdown/cache.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/markdown/cache.rs` has no inline `#[cfg(test)]` items;
// its behavioral tests live in `crates/rune-kit/src/markdown/tests.rs` (ported to
// `Tests/RuneKitTests/markdown/markdown_tests.swift`) and `crates/rune-kit/tests/markdown.rs`
// (ported to `Tests/RuneKitTests/tests/tests_markdown.swift`).

import Testing
@testable import RuneKit

@Suite("MarkdownCacheSmokeTests")
struct MarkdownCacheSmokeTests {
    @Test func docCachedReusesEntryInstance() {
        let a = docCached("cache smoke **bold**")
        let b = docCached("cache smoke **bold**")
        #expect(a === b)
    }
}
