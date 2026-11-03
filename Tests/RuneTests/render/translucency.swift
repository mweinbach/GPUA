// Tests ported from: crates/rune/src/render/translucency.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Translucency Tests")
struct RuneTranslucencyTests {
    @Test("low power order puts integrated first and software last")
    func lowPowerOrderPutsIntegratedFirstAndSoftwareLast() {
        var devices: [AdapterDeviceType] = [.cpu, .discreteGpu, .other, .integratedGpu, .virtualGpu]
        devices.sort { powerRank($0) < powerRank($1) }
        #expect(devices == [.integratedGpu, .discreteGpu, .virtualGpu, .other, .cpu])
    }
}
