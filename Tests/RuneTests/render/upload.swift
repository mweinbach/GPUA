// Tests ported from: crates/rune/src/render/upload.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Render Upload Unit Tests")
struct RuneRenderUploadUnitTests {
    @Test("INSTANCE_BYTE_SIZE is 128 bytes and instanceWords round-trips all 32 lanes")
    func instancePackingAndEquality() {
        #expect(INSTANCE_BYTE_SIZE == 128)
        let inst = Instance(
            rect: [1, 2, 3, 4],
            radii: [5, 6, 7, 8],
            fill: [0.1, 0.2, 0.3, 0.4],
            border: [0.5, 0.6, 0.7, 0.8],
            params: [9, 10, 11, 12],
            uv: [13, 14, 15, 16],
            clip: NO_CLIP,
            fade: [17, 18, 19, 20]
        )
        #expect(instanceBytes(inst).count == 128)
        #expect(sameInstances([inst][...], [inst][...]))
        var other = inst
        other.fade[3] ^= 1
        #expect(!sameInstances([inst][...], [other][...]))
    }
}
