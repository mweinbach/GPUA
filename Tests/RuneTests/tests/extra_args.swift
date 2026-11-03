// Tests ported from: crates/rune/tests/extra_args.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Rune.extraArgs()` is ready before any `App` or window exists.

import Testing
@testable import Rune

@Suite("ExtraArgsIntegrationTests")
struct ExtraArgsIntegrationTests {
    @Test func extraArgsAreReadyBeforeAnyWindow() {
        headlessTestMutex.lock()
        defer {
            resetExtraArgsForTests()
            headlessTestMutex.unlock()
        }
        resetExtraArgsForTests()
        _ = Args.parseFrom(["--scale", "2", "--doc", "a.txt"])
        let extra = extraArgs()
        #expect(extra.suffix(2) == ["--doc", "a.txt"])
        #expect(!extra.contains("--scale") && !extra.contains("2"), "Rune's own flags are not extras: \(extra)")
    }
}
