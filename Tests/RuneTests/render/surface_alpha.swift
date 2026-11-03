// Tests ported from: crates/rune/src/render/surface_alpha.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import Testing
@testable import Rune

@Suite("Rune Surface Alpha Tests")
struct RuneSurfaceAlphaTests {
    @Test("GPU straight alpha conversion matches CPU reference within 1 LSB")
    func gpuStraightAlphaMatchesCpuReference() {
        let gpu = Gpu.headless()
        let alpha = AlphaSurface(gpu.metalDevice, OFFSCREEN_FORMAT, 4, 4)
        let target = Offscreen(gpu.metalDevice, 4, 4)
        let colors: [[Float]] = [
            [0.125, 0.25, 0.375, 0.5],
            [0.0, 0.0, 0.0, 0.0],
            [0.4, 0.6, 0.1, 1.0],
        ]
        func srgbEncode(_ c: Float) -> Float {
            if c <= 0.0031308 { return c * 12.92 }
            return 1.055 * powf(c, 1.0 / 2.4) - 0.055
        }
        func straightAlphaCpu(_ rgba: inout [UInt8]) {
            let a = Float(rgba[3]) / 255.0
            if a <= 0.0 || a >= 1.0 { return }
            for i in 0..<3 {
                let unprem = min(max((Float(rgba[i]) / 255.0) / a, 0.0), 1.0)
                rgba[i] = UInt8((unprem * 255.0).rounded())
            }
        }

        for color in colors {
            let enc = gpu.metalDevice.createCommandEncoder(label: "alpha-surface-test")
            do {
                let pass = enc.beginRenderPass(
                    label: "clear-alpha-src",
                    colorAttachment: MetalRenderPassColorAttachment(
                        view: alpha.view,
                        loadOp: .clear(
                            r: Double(color[0]),
                            g: Double(color[1]),
                            b: Double(color[2]),
                            a: Double(color[3])
                        ),
                        storeOp: .store
                    )
                )
                pass.end()
            }
            alpha.draw(enc, target.view)
            target.copy(enc)
            gpu.metalQueue.submit([enc.finish()])
            let pixels = target.read(gpu.metalDevice)

            // Note: on Metal sRGB render targets, MTLClearColor is linear -> sRGB hardware encoded;
            // `AlphaSurface` unpremultiplies in linear space and hardware re-encodes to sRGB!
            // Let's compute the exact CPU reference matching `surface_alpha.rs`:
            var reference: [UInt8] = [
                UInt8((srgbEncode(color[0]) * 255.0).rounded()),
                UInt8((srgbEncode(color[1]) * 255.0).rounded()),
                UInt8((srgbEncode(color[2]) * 255.0).rounded()),
                UInt8((color[3] * 255.0).rounded()),
            ]
            // Upstream `crate::tooling::straight_alpha`: linearize sRGB, divide by alpha, re-encode sRGB.
            if color[3] > 0.0 && color[3] < 1.0 {
                let invA = 1.0 / color[3]
                reference[0] = UInt8((srgbEncode(min(color[0] * invA, 1.0)) * 255.0).rounded())
                reference[1] = UInt8((srgbEncode(min(color[1] * invA, 1.0)) * 255.0).rounded())
                reference[2] = UInt8((srgbEncode(min(color[2] * invA, 1.0)) * 255.0).rounded())
            } else {
                straightAlphaCpu(&reference)
            }
            for p in stride(from: 0, to: pixels.count, by: 4) {
                for ch in 0..<4 {
                    let got = pixels[p + ch]
                    let want = reference[ch]
                    let diff = got >= want ? (got - want) : (want - got)
                    #expect(diff <= 1, "GPU \(Array(pixels[p..<(p+4)])) vs CPU \(reference)")
                }
            }
        }
    }
}
#endif
