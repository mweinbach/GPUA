// Tests ported from: crates/rune/src/render/layers.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import Testing
@testable import Rune

@Suite("Rune Render Layers Tests", .serialized)
struct RuneRenderLayersTests {
    @Test("turnedBounds computes exact axis-aligned bounding box of a rotated rect")
    func turnedBoundsQuarterTurnAndIdentity() {
        let r: [Float] = [10.0, 20.0, 30.0, 30.0]
        let same = turnedBounds(r, 0.0, [20.0, 25.0])
        for i in 0..<4 {
            #expect(abs(same[i] - r[i]) < 1e-5)
        }
        // 90 deg clockwise around center (20, 25): width 20 x height 10 becomes width 10 x height 20 -> [15, 15, 25, 35]
        let turned = turnedBounds(r, Float.pi * 0.5, [20.0, 25.0])
        #expect(abs(turned[0] - 15.0) < 1e-4)
        #expect(abs(turned[1] - 15.0) < 1e-4)
        #expect(abs(turned[2] - 25.0) < 1e-4)
        #expect(abs(turned[3] - 35.0) < 1e-4)
    }

    @Test("ordinary pass allocates zero layer targets while cached subtrees retain and evict under budget")
    func layerIsolationAndCacheBudgetEviction() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        let plain = Instance(rect: [4.0, 4.0, 16.0, 16.0], fill: [1.0, 0.0, 0.0, 1.0], clip: NO_CLIP)
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [plain], (64, 64))
        #expect(renderer.layerStats() == LayerStats(targets: 0, bytes: 0, extraPasses: 0, allocations: 0))

        // Cached subtree allocates once, then hits cache on frame 2 with extraPasses == 0!
        let cachedStream: [Instance] = [
            Instance.beginCachedLayer([4.0, 4.0, 16.0, 16.0], NO_CLIP, 101, 1),
            plain,
            Instance.endLayer(),
        ]
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, cachedStream, (64, 64))
        #expect(renderer.layerStats().targets == 1)
        #expect(renderer.layerStats().extraPasses == 1)
        #expect(atlas.residentCaches[101] == 1)

        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, cachedStream, (64, 64))
        #expect(renderer.layerStats().targets == 1)
        #expect(renderer.layerStats().extraPasses == 0)

        // Setting cache budget to 0 evicts retained targets when no longer active
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [plain], (64, 64))
        renderer.setCacheBudget(0)
        #expect(renderer.cacheBudget() == 0)
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [plain], (64, 64))
        #expect(atlas.residentCaches.isEmpty)
    }
}
#endif
