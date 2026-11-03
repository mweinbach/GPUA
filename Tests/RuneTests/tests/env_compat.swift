// Tests ported from: crates/rune/tests/env_compat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let envCompatConst = Env(systemDark: true, scale: 2.0)

@Suite("EnvCompatIntegrationTests")
struct EnvCompatIntegrationTests {
    @Test func envKeepsItsExhaustiveLiteralApi() {
        let systemDark = envCompatConst.systemDark
        let scale = envCompatConst.scale
        #expect(systemDark)
        #expect(scale == 2.0)
    }
}
