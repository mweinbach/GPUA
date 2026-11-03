// Tests ported from: crates/rune/src/render/backdrop_blur.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Testing
@testable import Rune

@Suite("Rune Backdrop Blur GPU Rendering Tests", .serialized)
struct RuneBackdropBlurGpuTests {
    @Test("backdrop blur smooths sharp edges inside clipped region without bleeding outside")
    func backdropBlurBlursInsideClippedRegionOnly() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        let target = Offscreen(device, 64, 32)
        var atlas = TextSystem().atlas

        // Left half white (0..<32), right half black (32..<64)
        let bgBlack = Instance(rect: [0.0, 0.0, 64.0, 32.0], fill: [0.0, 0.0, 0.0, 1.0], clip: NO_CLIP)
        let leftWhite = Instance(rect: [0.0, 0.0, 32.0, 32.0], fill: [1.0, 1.0, 1.0, 1.0], clip: NO_CLIP)
        let blur = Instance(
            rect: [16.0, 4.0, 32.0, 24.0],
            radii: [0.0, 0.0, 0.0, 0.0],
            fill: [0.0, 0.0, 0.0, 1.0],
            border: [0.0, 0.0, 0.0, 0.0],
            params: [6.0, KIND_BACKDROP_BLUR, 0.0, 1.0],
            uv: [0.0, 0.0, 0.0, 0.0],
            clip: [16.0, 4.0, 48.0, 28.0],
            fade: [0, 0, 0, 0]
        )
        renderer.prepare(device, queue, &atlas, [bgBlack, leftWhite, blur], (64, 32))
        #expect(renderer.hasBackdropBlur())
        let enc = device.createCommandEncoder(label: "backdrop-blur-gpu")
        renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 1.0])
        target.copy(enc)
        renderer.submit(queue, enc)
        let px = target.read(device)

        // Outside the blur rect (y = 1, x = 31 and x = 32), the edge remains sharp (255 vs 0)
        #expect(px[(1 * 64 + 31) * 4] == 255)
        #expect(px[(1 * 64 + 32) * 4] == 0)

        // Inside the blur rect across the seam (y = 16, x = 31 and x = 32), values are intermediate!
        let leftSeam = px[(16 * 64 + 31) * 4]
        let rightSeam = px[(16 * 64 + 32) * 4]
        #expect(leftSeam > 40 && leftSeam < 250)
        #expect(rightSeam > 40 && rightSeam < 250)

        // A frame without backdrop blur records clears the active record list
        renderer.prepare(device, queue, &atlas, [bgBlack, leftWhite], (64, 32))
        #expect(!renderer.hasBackdropBlur())
    }
}
#endif
