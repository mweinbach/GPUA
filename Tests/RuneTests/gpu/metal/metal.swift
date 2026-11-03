// Tests ported from: crates/rune/src/gpu/metal/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("MetalModuleUnitTests")
struct MetalModuleUnitTests {
    @Test("Metal MSL version is 3.0")
    func mslVersion() {
        let (major, minor) = metalMslVersion()
        #expect(major == 3 && minor == 0)
    }

    #if canImport(Metal)
    @Test("Metal adapter enumeration finds at least one GPU on Apple hosts")
    func enumerateAdapters() {
        let infos = metalEnumerateAdapterInfos()
        #expect(!infos.isEmpty)
        for info in infos {
            #expect(!info.name.isEmpty)
        }
    }
    #endif
}
