// Tests ported from: crates/rune/src/render/backdrop_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Testing
import CWebGPU
@testable import Rune

private func backdropRect(_ rect: [Float], _ fill: [Float]) -> Instance {
    Instance(rect: rect, fill: fill, clip: NO_CLIP)
}

@Suite("Rune Backdrop Tests", .serialized)
struct RuneBackdropTests {
    @Test("backdrop pool is lazy, reused, resized, and follows live formats")
    func backdropPoolIsLazyReusedResizedAndFollowsLiveFormats() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        var slot = backdropRect([0.0, 0.0, 16.0, 16.0], [0.0, 0.0, 0.0, 1.0])
        slot.params = [0.0, KIND_EFFECT, 0.0, 1.0]
        for instances in [[], [slot]] {
            renderer.prepare(device, queue, &atlas, instances, (32, 32))
            #expect(renderer.backdrops.isEmpty)
        }
        slot.params[0] = 1.0
        renderer.prepare(device, queue, &atlas, [slot], (32, 32))
        let original = renderer.backdrops[0].view
        renderer.prepare(device, queue, &atlas, [slot], (32, 32))
        #expect(renderer.backdrops[0].view === original)

        let nonSrgb = WGPUTextureFormat_RGBA8Unorm
        renderer.setFormat(device, nonSrgb)
        #expect(renderer.backdrops.contains(where: { $0.format == nonSrgb }))

        let configs: [(WGPUTextureFormat, (UInt32, UInt32))] = [
            (nonSrgb, (48, 24)),
            (OFFSCREEN_FORMAT, (24, 48)),
            (nonSrgb, (32, 32)),
        ]
        for (fmt, size) in configs {
            renderer.setFormat(device, fmt)
            renderer.prepare(device, queue, &atlas, [slot, slot], size)
            let target = Offscreen(device, size.0, size.1, fmt)
            let enc = device.createCommandEncoder(label: "backdrop-pool")
            var captured: [MetalView] = []
            renderer.drawWithBackdrop(enc, target.view, [0.0, 0.0, 0.0, 0.0]) { phase, site in
                if case .backdrop = phase {
                    let v = site.backdrop!
                    #expect((v.raw.width, v.raw.height) == size)
                    #expect(v.raw.format == fmt)
                    captured.append(v)
                }
            }
            queue.submit([enc.finish()])
            #expect(captured.count == 2)
            #expect(captured[0] === captured[1])
            #expect(renderer.backdrops.count == 2)
        }
    }

    @Test("split resets the hook viewport and scissor for later primitives")
    func splitResetsTheHookViewportAndScissorForLaterPrimitives() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        var slot = backdropRect([0.0, 0.0, 16.0, 16.0], [0.0, 0.0, 0.0, 1.0])
        slot.params = [1.0, KIND_EFFECT, 0.0, 1.0]
        slot.clip = [0.0, 0.0, 16.0, 16.0]
        let instances = [
            backdropRect([0.0, 0.0, 32.0, 32.0], [1.0, 0.0, 0.0, 1.0]),
            slot,
            backdropRect([16.0, 0.0, 16.0, 32.0], [0.0, 1.0, 0.0, 1.0]),
        ]
        renderer.prepare(device, queue, &atlas, instances, (32, 32))
        let target = Offscreen(device, 32, 32)
        let enc = device.createCommandEncoder(label: "split-reset")
        renderer.drawWith(enc, target.view, [0.0, 0.0, 0.0, 0.0]) { pass, site in
            #expect(site.backdrop != nil)
            pass.setViewport(x: 0.0, y: 0.0, width: 1.0, height: 1.0, minDepth: 0.0, maxDepth: 1.0)
            pass.setScissorRect(x: 0, y: 0, width: 1, height: 1)
        }
        target.copy(enc)
        queue.submit([enc.finish()])
        let pixels = target.read(device)
        for (x, color): (Int, [UInt8]) in [(8, [255, 0, 0, 255]), (24, [0, 255, 0, 255])] {
            let at = (24 * 32 + x) * 4
            #expect(Array(pixels[at..<(at + 4)]) == color)
        }
    }

    @Test("backdrop slot degrades gracefully when the target lacks CopySrc")
    func backdropSlotDegradesWhenTheTargetCannotBeCopied() {
        let gpu = Gpu.headless()
        let (device, queue) = (gpu.metalDevice, gpu.metalQueue)
        let renderer = Renderer(device, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        var slot = backdropRect([0.0, 0.0, 16.0, 16.0], [0.0, 0.0, 0.0, 1.0])
        slot.params = [1.0, KIND_EFFECT, 0.0, 1.0]
        slot.clip = [0.0, 0.0, 16.0, 16.0]
        renderer.prepare(device, queue, &atlas, [slot], (32, 32))
        let texture = device.createTexture(
            label: "no copy src",
            format: OFFSCREEN_FORMAT,
            width: 32,
            height: 32,
            usage: UInt32(WGPUTextureUsage_RenderAttachment)
        )
        let view = texture.createView()
        let enc = device.createCommandEncoder(label: "no-copy-src")
        var draws = 0
        renderer.drawWith(enc, view, [0.0, 0.0, 0.0, 0.0]) { _, site in
            #expect(site.backdrop == nil)
            draws += 1
        }
        queue.submit([enc.finish()])
        #expect(draws == 1)
    }
}
#endif
