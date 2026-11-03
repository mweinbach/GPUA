// Tests ported from: crates/rune/src/render.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
import CWebGPU
import RuneMotion
@testable import Rune

@Suite("Rune Render Core Tests", .serialized)
struct RuneRenderTests {
    @Test("prewarm_gpu_on chooses backend before starting prewarm thread")
    func prewarmGpuOnChoosesBeforeItStarts() {
        var log: [String] = []
        chooseThenStart(
            .metal,
            { b in log.append("choose \(b)") },
            { log.append("start") }
        )
        #expect(log == ["choose metal", "start"])
    }

    @Test("packFade and unpackFade round-trip widths and normalized origin offsets")
    func packAndUnpackFadeRoundTrip() {
        let clip: [Float] = [10.0, 20.0, 110.0, 220.0]
        let width: [Float] = [8.0, 12.0, 16.0, 20.0]
        let origin: [Float] = [6.0, 14.0, 118.0, 230.0]
        let packed = packFade(width, origin, clip)
        let (unpackedW, offset) = unpackFade(packed)
        for i in 0..<4 {
            #expect(abs(unpackedW[i] - width[i]) < 1e-3)
            #expect(abs(offset[i] - 0.5) < 1e-2)
        }
    }

    @Test("packClipRadii and unpackClipRadii handle uniform and mixed circular/continuous corners")
    func packAndUnpackClipRadiiRoundTrip() {
        let clip: [Float] = [0.0, 0.0, 100.0, 80.0]
        let uniform = packClipRadii(clip, [12.0, 12.0, 12.0, 12.0])
        #expect(Float(bitPattern: uniform) == 12.0)
        #expect(unpackClipRadii(uniform) == [12.0, 12.0, 12.0, 12.0])

        let mixed = packClipRadii(clip, [-10.0, -8.0, 0.0, -4.0])
        #expect(unpackClipRadii(mixed) == [-10.0, -8.0, 0.0, -4.0])
    }

    #if os(macOS)
    @Test("a window takes the prewarmed GPU and renderer once, and sealed slots ignore late starts")
    func aWindowTakesThePrewarmedGpuAndRendererOnce() {
        prewarmGpu()
        if let (_, renderer) = takePrewarmedGpu() {
            #expect(renderer.format == WGPUTextureFormat_BGRA8Unorm)
        }
        #expect(takePrewarmedGpu() == nil)

        let taken = PrewarmSlot<Int>()
        #expect(taken.take() == nil)
        taken.start { 42 }
        #expect(taken.take() == nil)

        let discarded = PrewarmSlot<Int>()
        discarded.start { 7 }
        discarded.discard()
        #expect(discarded.take() == nil)
        discarded.start { 9 }
        #expect(discarded.take() == nil)

        let restarted = PrewarmSlot<Int>()
        restarted.restart { 1 }
        restarted.start { 2 }
        restarted.restart { 3 }
        #expect(restarted.take() == 3)
        restarted.restart { 4 }
        #expect(restarted.take() == nil)
    }

    @Test("Renderer.withSprings animates and retargets nodes via writeSpringNode")
    func rendererWithSpringsAndWritePng() throws {
        let gpu = Gpu.headless()
        let spring = Spring(0.25, 0.0)
        let stationary = springs.Track(spring, 0.0, 0.0, 0.0, 0.0, 0.001)
        let activeX = springs.Track(spring, 0.0, 0.0, 16.0, 0.0, 0.001)
        let fullAlpha = springs.Track(spring, 0.0, 1.0, 1.0, 0.0, 0.001)
        let node0 = springs.Node(x: activeX, y: stationary, opacity: fullAlpha)
        let renderer = Renderer.withSprings(
            gpu.metalDevice,
            OFFSCREEN_FORMAT,
            [node0],
            [0]
        )
        #expect(renderer.springsAnimating(0.01))
        var atlas = TextSystem().atlas
        let inst = Instance(
            rect: [0.0, 4.0, 8.0, 8.0],
            fill: [1.0, 0.0, 0.0, 1.0],
            clip: NO_CLIP
        )
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [inst], (32, 16))
        renderer.presentAt(gpu.metalQueue, (32, 16), 2.0)
        let target = Offscreen(gpu.metalDevice, 32, 16)
        let enc = gpu.metalDevice.createCommandEncoder(label: "springs test")
        renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
        target.copy(enc)
        renderer.submit(gpu.metalQueue, enc)
        let px = target.read(gpu.metalDevice)
        // Settled at x = 16..24, y = 4..12 -> pixel (20, 8) is red.
        let idx = (8 * 32 + 20) * 4
        #expect(Array(px[idx..<(idx + 4)]) == [255, 0, 0, 255])

        let retargeted = springs.Node(
            x: springs.Track(spring, 2.0, 16.0, 24.0, 0.0, 0.001),
            y: stationary,
            opacity: fullAlpha
        )
        renderer.writeSpringNode(gpu.metalQueue, 0, retargeted)
        #expect(renderer.springsAnimating(2.01))

        let tmpPng = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rune-render-test-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmpPng) }
        try writePng(tmpPng.path, 32, 16, px)
        let pngBytes = try Data(contentsOf: tmpPng)
        #expect(pngBytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
    }
    #endif
}
