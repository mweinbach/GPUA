// Tests ported from: crates/rune/src/render/layer_blur.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Rune Layer Blur Kernel Tests")
struct RuneLayerBlurKernelTests {
    @Test("layerBlurSigma clamps negative and NaN to zero and caps at LAYER_BLUR_MAX_SIGMA")
    func sigmaClampingAndPairedWeightsNormalizeToOne() {
        #expect(layerBlurSigma(0.0) == 0.0)
        #expect(layerBlurSigma(-3.0) == 0.0)
        #expect(layerBlurSigma(.nan) == 0.0)
        #expect(layerBlurSigma(200.0) == LAYER_BLUR_MAX_SIGMA)

        for sigma: Float in [0.5, 1.5, 3.0, 8.0, 24.0] {
            let kernel = layerBlurKernel(sigma)
            let tapCount = Int(kernel.meta[3])
            #expect(tapCount >= 1 && tapCount <= 128)
            var total = kernel.taps[0][1]
            for i in 1..<tapCount {
                total += 2.0 * kernel.taps[i][1]
            }
            #expect(abs(total - 1.0) < 1e-5, "sigma \(sigma) kernel sum \(total)")
        }
    }
}
