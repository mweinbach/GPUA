// Tests ported from: crates/rune/src/tooling/interaction/gate.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Note: `crates/rune/src/tooling/interaction/gate.rs` defines `#[cfg(test)] force_on()`, while
// gate behavioral assertions live in `crates/rune/src/tooling/interaction/tests.rs`.

@Suite("InteractionGateUnitTests")
struct InteractionGateUnitTests {
    @Test func loopbackAcceptsLocalIpv4Ipv6AndLocalhostOnly() {
        #expect(interactionGateLoopback("127.0.0.1:27686")?.port == 27686)
        #expect(interactionGateLoopback("localhost:4318")?.port == 4318)
        #expect(interactionGateLoopback("[::1]:4318")?.port == 4318)
        #expect(interactionGateLoopback("192.168.1.5:4318") == nil)
    }
}
