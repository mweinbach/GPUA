// Tests ported from: crates/rune/src/tooling/perf_warn.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Note: `crates/rune/src/tooling/perf_warn.rs` declares `mod commits_tests; mod tests;`, which
// are ported in `Tests/RuneTests/tooling/perf_warn/commits_tests.swift` and
// `Tests/RuneTests/tooling/perf_warn/perf_warn_tests.swift`.

@Suite("PerfWarnCoreTests")
struct PerfWarnCoreTests {
    @Test func handlerSiteStripsDigitsOnly() {
        #expect(perfHandlerSite("on_press", "#0/list/r12") == "on_press #/list/r")
        #expect(perfHandlerSite("on_press", "#0/list/r12") == perfHandlerSite("on_press", "#0/list/r7"))
    }
}
