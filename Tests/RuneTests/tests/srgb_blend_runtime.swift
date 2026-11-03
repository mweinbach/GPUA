// Tests ported from: crates/rune/tests/srgb_blend_runtime.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let srgbRed = Color(r: 1.0, g: 0.0, b: 0.0, a: 1.0)

private func srgbBlendView(_: Void, _: Cx<Void>) -> El {
    el().size(40.0, 40.0).fill(.BLACK)
        .child(
            el().size(20.0, 20.0).fill(srgbRed)
                .hover(Color.WHITE.alpha(0.5))
                .onPress { (_: inout Void, _: inout Tx) in }
        )
}

private func srgbHoveredRuntime(_ srgb: Bool) -> (Runtime<Void>, [Instance]) {
    let text = TextSystem([], ("Inter", "Inter"))
    let rt = Runtime.withText((), srgbBlendView, (40.0, 40.0), Env(systemDark: true, scale: 1.0), text)
    rt.hostSetSrgbBlend(srgb)
    _ = rt.hostFrame(0.0)
    _ = rt.hostPointerMove(10.0, 10.0)
    let (instances, _, _) = rt.hostFrame(1.0 / 60.0)
    return (rt, instances)
}

private func srgbTintedFill(_ instances: [Instance]) -> [Float] {
    guard let child = instances.first(where: { $0.rect[2] == 20.0 && $0.rect[3] == 20.0 }) else {
        preconditionFailure("the child's box")
    }
    return child.fill
}

@Suite("SrgbBlendRuntimeIntegrationTests")
struct SrgbBlendRuntimeIntegrationTests {
    @Test func hoverTintsFollowTheRuntimeBlendMode() {
        let tint = Color.WHITE.alpha(0.5)
        let (srgbRt, srgbInst) = srgbHoveredRuntime(true)
        let isSrgb = srgbRt.hostSrgbBlend()
        #expect(isSrgb)
        #expect(srgbTintedFill(srgbInst) == over(tint.premulSrgb(1.0), srgbRed.premulSrgb(1.0)))

        let (_, linearInst) = srgbHoveredRuntime(false)
        #expect(srgbTintedFill(linearInst) == over(tint.premul(1.0), srgbRed.premul(1.0)))
    }

    @Test(.disabled("Requires Wave 2 Gpu.headless() and Renderer wgpu offscreen readback in render.swift"))
    func aSelfDrawnRuntimeRendersGammaBlendedPixels() {}

    @Test func switchingBlendModeRedraws() {
        let (rt, _) = srgbHoveredRuntime(false)
        _ = rt.hostFrame(1.0)
        let commitsBefore = rt.hostCommits()

        rt.hostSetSrgbBlend(true)
        let (instAfter, _, _) = rt.hostFrame(1.0 / 60.0)
        let commitsAfter = rt.hostCommits()
        #expect(commitsAfter > commitsBefore)
        #expect(srgbTintedFill(instAfter) == over(Color.WHITE.alpha(0.5).premulSrgb(1.0), srgbRed.premulSrgb(1.0)))

        let commitsSame = rt.hostCommits()
        rt.hostSetSrgbBlend(true)
        _ = rt.hostFrame(1.0 / 60.0)
        let commitsUnchanged = rt.hostCommits()
        #expect(commitsUnchanged == commitsSame)
    }

    @Test func aHandlerSwitchesBlendModeLive() {
        let (rt, _) = srgbHoveredRuntime(false)
        rt.hostUpdate { _, tx in tx.setSrgbBlend(true) }
        let switchedOn = rt.hostSrgbBlend()
        #expect(switchedOn)
        let (inst, _, _) = rt.hostFrame(1.0 / 60.0)
        #expect(srgbTintedFill(inst) == over(Color.WHITE.alpha(0.5).premulSrgb(1.0), srgbRed.premulSrgb(1.0)))

        rt.hostUpdate { _, tx in
            tx.setSrgbBlend(true)
            tx.setSrgbBlend(false)
        }
        let switchedOff = rt.hostSrgbBlend()
        #expect(!switchedOff)
    }

    @Test(.disabled("Requires Wave 2 Gpu.headless() and Renderer wgpu offscreen readback in render.swift"))
    func aHeadlessRunFollowsALiveSwitch() {}

    @Test(.disabled("Requires Wave 2 Gpu.headless() and Renderer wgpu offscreen readback in render.swift"))
    func switchingFormatKeepsTheGlyphAtlasAndExtraPipelines() {}
}
