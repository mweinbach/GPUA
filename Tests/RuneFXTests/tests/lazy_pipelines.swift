// Tests ported from: crates/rune-fx/tests/lazy_pipelines.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Testing
@testable import RuneFX

private func drawLazy(
    device: WGPUDevice,
    queue: WGPUQueue,
    fx: FxRenderer,
    format: WGPUTextureFormat,
    layers: [FxLayer],
    slots: [FxSlot]
) {
    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 64, height: 64, format: format)
    fx.prepareWithSlots(
        device,
        queue,
        FxFrame(viewport: [64, 64], scale: 1.0, layers: layers, backdrop: nil, sources: []),
        slots
    )
    let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: .zero)
    for i in 0..<layers.count {
        fx.drawLayerIn(pass, format, [0.0, 0.0], i)
    }
}

@Suite("RuneFX Lazy Pipelines")
struct LazyPipelinesIntegrationTests {
    @Test("pipelines_are_built_for_what_frames_draw")
    func pipelinesAreBuiltForWhatFramesDraw() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let window = WGPUTextureFormat_RGBA8UnormSrgb
        let layer = WGPUTextureFormat_RGBA16Float
        let fx = FxRenderer.new(device, window, FxOptions())
        fx.addFormat(device, layer)
        #expect(fx.builtPipelines() == 0, "nothing is built before a frame draws")

        let shape = Shape.rounded(16.0, 16.0, 32.0, 32.0, 6.0)
        let glow = Fx.glow(.default()).on(shape)
        drawLazy(device: device, queue: queue, fx: fx, format: window, layers: [glow], slots: [])
        #expect(fx.builtPipelines() == 1, "a glow builds the glow")
        drawLazy(device: device, queue: queue, fx: fx, format: window, layers: [glow], slots: [])
        #expect(fx.builtPipelines() == 1, "and keeps it")

        let fire = Fx.fire(.default()).on(shape)
        drawLazy(
            device: device,
            queue: queue,
            fx: fx,
            format: window,
            layers: [glow, fire, glow],
            slots: [.default(), .default(), FxSlot.default().blend(.screen)]
        )
        #expect(fx.builtPipelines() == 3, "a fire and a screen-blended glow build one each")

        drawLazy(device: device, queue: queue, fx: fx, format: layer, layers: [glow], slots: [])
        #expect(fx.builtPipelines() == 4, "another format builds its own when drawn into")

        fx.buildEveryPipeline()
        #expect(fx.builtPipelines() == 32, "eight families, two blends, two formats")
    }
}
