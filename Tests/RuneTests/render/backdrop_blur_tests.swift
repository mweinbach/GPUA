// Tests ported from: crates/rune/src/render/backdrop_blur_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Backdrop Blur Pyramid Tests")
struct RuneBackdropBlurTests {
    @Test("levels cover the sigma range continuously and monotonically")
    func levelsCoverTheRangeContinuously() {
        let top = BACKDROP_BLUR_SIGMAS.count - 1
        let zero = backdropBlurLevels(0.0, top)
        #expect(zero.0 == 1 && zero.1 == 0.0)
        let high = backdropBlurLevels(BACKDROP_BLUR_SIGMAS[top] * 4.0, top)
        #expect(high.0 == top && high.1 == 1.0)

        var last: Float = 0.0
        for k in 1..<400 {
            let sigma = Float(k) * 0.5
            let (n, share) = backdropBlurLevels(sigma, top)
            let a = BACKDROP_BLUR_SIGMAS[n - 1]
            let b = BACKDROP_BLUR_SIGMAS[n]
            let got = (a * a + share * (b * b - a * a)).squareRoot()
            let clamped = min(max(sigma, BACKDROP_BLUR_SIGMAS[0]), BACKDROP_BLUR_SIGMAS[top])
            #expect(abs(got - clamped) < 1e-3, "sigma \(sigma): \(got)")
            #expect(got >= last)
            last = got
        }
    }
}
