// Tests ported from: crates/rune-ref/src/blend.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneRef

@Suite("RuneRef Blend Tests")
struct RuneRefBlendTests {
    @Test("transparent backdrops preserve the source in every mode")
    func transparentBackdropsPreserveSource() {
        let src: [Float] = [0.12, 0.24, 0.06, 0.3]
        for mode in [
            Separable.multiply,
            Separable.screen,
            Separable.overlay,
            Separable.softLight,
        ] {
            #expect(composite(mode, src, [0.0, 0.0, 0.0, 0.0]) == src)
        }
    }
}
