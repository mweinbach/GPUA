// Tests ported from: crates/rune-fx/tests/sim.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Testing
@testable import RuneFX

private let simW: UInt32 = 64
private let simH: UInt32 = 96

/// Three frames of a simulated fire, each one's f16 pixels.
private func simFrames(device: WGPUDevice, queue: WGPUQueue) -> [[UInt16]] {
    let fmt = WGPUTextureFormat_RGBA16Float
    let fx = FxRenderer.new(device, fmt, FxOptions(dither: false))
    fx.setFireSim(device, true)
    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: simW, height: simH, format: fmt)

    return (1...3).map { n in
        let layers = [
            Fx.fire(.default())
                .on(Shape.rounded(8.0, 60.0, 48.0, 24.0, 6.0))
                .at(Float(n) * 0.05)
        ]
        fx.prepare(
            device,
            queue,
            FxFrame(viewport: [simW, simH], scale: 1.0, layers: layers, backdrop: nil, sources: [])
        )
        let encoder = SyntheticFXGPU.shared.makeEncoder()
        #expect(fx.simulate(queue, encoder, nil), "frame \(n) stepped the simulation")
        let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: .zero)
        fx.drawLayer(pass, 0)
        return SyntheticFXGPU.shared.readHeadlessTextureF16Words(target.texture)
    }
}

@Suite("RuneFX Fire Simulation")
struct SimIntegrationTests {
    @Test("simulated_fire_matches_wgpus_frame_for_frame")
    func simulatedFireMatchesWgpusFrameForFrame() {
        let gpuA = SyntheticFXGPU.shared.makeHeadlessContext()
        let got = simFrames(device: gpuA.device, queue: gpuA.queue)
        let gpuB = SyntheticFXGPU.shared.makeHeadlessContext()
        let want = simFrames(device: gpuB.device, queue: gpuB.queue)

        for (n, (g, w)) in zip(got, want).enumerated() {
            #expect(g.allSatisfy { ($0 & 0x7c00) != 0x7c00 }, "frame \(n) is finite")
            var lit = 0
            var idx = 0
            while idx + 3 < g.count {
                if g[idx + 3] != 0 { lit += 1 }
                idx += 4
            }
            #expect(lit > Int(simW * simH / 20), "frame \(n) drew a fire (\(lit) pixels lit)")
            #expect(g == w, "frame \(n) is deterministic across contexts")
        }
        #expect(got[0] != got[2], "the simulation moved the flame")
    }
}
