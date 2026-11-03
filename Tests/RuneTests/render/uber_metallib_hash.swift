// Tests ported from: crates/rune/src/render/uber_metallib_hash.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Uber Metallib Hash Constants")
struct RuneUberMetallibHashTests {
    @Test("recorded uber metallib digests match upstream constants")
    func recordedConstantsMatchUpstream() {
        #expect(UBER_WGSL_BLAKE3 == "6fba3186690a477f14444691be8208794ef1d3b84f04a6b37f66f08a983550f8")
        #expect(UBER_MSL_BLAKE3 == "a0afdeebd61eaedac218199a876051ac9c960df405aee08edfad46f2a4512f20")
        #expect(UBER_NATIVE_MSL_BLAKE3 == "c7c8741b3d0325385cb656c2001ccc3d764f036f306ab7ef9d3f477d9dea41e1")
        #expect(UBER_ABI_FNV64 == 0xb53b72e11574bdc1)
        #expect(UBER_MSL_OPTIONS_FNV64 == 0x0eaa2a2ef8dcd514)
        #expect(UBER_METALLIB_FNV64 == 0x4da6baabe0da38bb)
        #expect(UBER_NATIVE_METALLIB_FNV64 == 0xd036c7ac40564831)
    }
}
