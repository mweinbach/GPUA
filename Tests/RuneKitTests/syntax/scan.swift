// Tests ported from: crates/rune-kit/src/syntax/scan.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/syntax/scan.rs` declares `#[cfg(test)] mod tests;`
// pointing to `crates/rune-kit/src/syntax/scan/tests.rs`, whose full test suite is ported in
// `Tests/RuneKitTests/syntax/scan/scan_tests.swift`.

import Testing
@testable import RuneKit

@Suite("SyntaxScanCoreTests")
struct SyntaxScanCoreTests {
    @Test
    func adjacent_ranges_of_same_kind_coalesce() {
        var out = syntaxScan.Out()
        out.push(0, 2, .punctuation)
        out.push(2, 4, .punctuation)
        out.push(4, 4, .punctuation)
        out.push(5, 7, .keyword)
        #expect(out.tokens.count == 2)
        #expect(out.tokens[0].0 == 0 && out.tokens[0].1 == 4 && out.tokens[0].2 == .punctuation)
        #expect(out.tokens[1].0 == 5 && out.tokens[1].1 == 7 && out.tokens[1].2 == .keyword)
    }
}
