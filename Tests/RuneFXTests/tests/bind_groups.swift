// Tests ported from: crates/rune-fx/tests/bind_groups.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Testing
@testable import RuneFX

private let bgFormat = WGPUTextureFormat_RGBA8UnormSrgb

private func makeBackdrop() -> WGPUTextureView {
    SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: bgFormat).view
}

private func runBindGroupFrame(
    device: WGPUDevice,
    queue: WGPUQueue,
    fx: FxRenderer,
    layers: [FxLayer],
    backdrop: WGPUTextureView,
    slotBackdrop: WGPUTextureView?
) -> [WGPUBindGroup?] {
    fx.prepare(
        device,
        queue,
        FxFrame(viewport: [96, 96], scale: 1.0, layers: layers, backdrop: backdrop, sources: [])
    )
    let enc = SyntheticFXGPU.shared.makeEncoder()
    if let b = slotBackdrop {
        _ = fx.blurBackdrop(device, queue, enc, b, 1)
    }
    return (0..<layers.count).map { fx.layerBindGroup($0) }
}

@Suite("RuneFX Bind Group Reuse")
struct BindGroupsIntegrationTests {
    @Test("a_steady_frame_reuses_its_bind_groups")
    func aSteadyFrameReusesItsBindGroups() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let fx = FxRenderer.new(device, bgFormat, FxOptions())
        let bd = makeBackdrop()
        let slot = makeBackdrop()
        let layers: [FxLayer] = [
            Fx.glow(GlowParams(radius: 10.0, intensity: 0.8))
                .on(Shape.rounded(16.0, 16.0, 32.0, 32.0, 8.0))
                .at(0.5),
            Fx.lens(LensParams(frost: 0.6))
                .on(Shape.rounded(40.0, 40.0, 40.0, 40.0, 12.0))
                .at(0.5),
        ]

        let first = runBindGroupFrame(device: device, queue: queue, fx: fx, layers: layers, backdrop: bd, slotBackdrop: nil)
        let second = runBindGroupFrame(device: device, queue: queue, fx: fx, layers: layers, backdrop: bd, slotBackdrop: nil)
        #expect(first.allSatisfy { $0 != nil })
        #expect(first == second, "the frame backdrop's groups were made again")

        // A per-slot backdrop bound after `prepare` is reused too.
        let slotFirst = runBindGroupFrame(device: device, queue: queue, fx: fx, layers: layers, backdrop: bd, slotBackdrop: slot)
        let slotSecond = runBindGroupFrame(device: device, queue: queue, fx: fx, layers: layers, backdrop: bd, slotBackdrop: slot)
        #expect(slotFirst == slotSecond, "the slot backdrop's group was made again")

        // A different backdrop gets its own group.
        let other = makeBackdrop()
        let third = runBindGroupFrame(device: device, queue: queue, fx: fx, layers: layers, backdrop: other, slotBackdrop: nil)
        #expect(third[0] == slotSecond[0])
        #expect(third[1] != slotSecond[1])
    }
}
