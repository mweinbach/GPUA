// Tests ported from: crates/rune-light/tests/targets.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Testing
@testable import RuneLight

private let rigW: UInt32 = 256
private let rigH: UInt32 = 160

private final class LightTestRig {
    let device: WGPUDevice
    let queue: WGPUQueue
    let light: LightRenderer
    let base: WGPUTextureView
    let text: WGPUTextureView
    let target: WGPUTextureView
    let timed: Bool

    init(timed: Bool = false) {
        let ctx = SyntheticLightGPU.shared.makeHeadlessContext()
        self.device = ctx.device
        self.queue = ctx.queue
        self.timed = timed
        self.light = LightRenderer(
            ctx.device,
            ctx.queue,
            WGPUTextureFormat_RGBA8Unorm,
            hasTimestamps: timed
        )
        let usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding
        self.base = texture(ctx.device, "rig.base", (rigW, rigH), 1, WGPUTextureFormat_RGBA16Float, usage).1
        self.text = texture(ctx.device, "rig.text", (rigW, rigH), 1, WGPUTextureFormat_RGBA16Float, usage).1
        self.target = texture(ctx.device, "rig.target", (rigW, rigH), 1, WGPUTextureFormat_RGBA8Unorm, usage).1
    }

    @discardableResult
    func record(_ prims: [Prim], _ gi: Gi?, inspectCascade: Int? = nil) -> WGPUCommandEncoder {
        let lights = [Light.point(60.0, 40.0, 120.0)]
        let scene = Scene(prims: prims, lights: lights)
        var settings = Settings()
        if let gi {
            settings.gi = gi
        } else {
            settings.gi = Gi(enabled: false)
        }
        settings.inspectCascade = inspectCascade
        let encoder = light.makeCommandEncoder()
        let rendered = light.render(encoder, base, text, target, (rigW, rigH), scene, settings)
        #expect(rendered)
        return encoder
    }

    func frame(_ prims: [Prim], _ gi: Gi?, inspectCascade: Int? = nil) {
        _ = record(prims, gi, inspectCascade: inspectCascade)
    }

    func liveBindGroups() -> Int {
        light.createdBindGroupCount()
    }
}

private func makePrims(_ n: Int) -> [Prim] {
    (0..<n).map { i in
        Prim.rect(Float(i % 16) * 14.0, Float(i / 16) * 8.0, 10.0, 6.0).raised(4.0)
    }
}

@Suite("RuneLight Targets and CPU Reference")
struct LightTargetsTests {
    @Test("growing_the_prim_buffer_keeps_the_render_targets")
    func growingThePrimBufferKeepsTheRenderTargets() {
        let r = LightTestRig()
        r.frame(makePrims(8), nil)
        let vis = r.light.visibilityTexture()
        #expect(vis != nil)
        r.frame(makePrims(300), nil)
        #expect(r.light.visibilityTexture() == vis, "a bigger scene reallocated the render targets")
    }

    @Test("without_gi_nothing_gi_is_allocated_or_recorded")
    func withoutGiNothingGiIsAllocatedOrRecorded() {
        let r = LightTestRig(timed: false)
        r.frame(makePrims(8), nil)
        do {
            let ins = try! #require(r.light.inspect())
            #expect(ins.emission == ins.fluence && ins.cascade == ins.fluence, "GI textures exist with GI off")
        }
        // Field and shadows when GI is off (2 compute passes without timestamps).
        #expect(r.light.computePasses() == 2)

        r.frame(makePrims(8), Gi(enabled: true))
        let ins = try! #require(r.light.inspect())
        #expect(ins.emission != ins.fluence, "turning GI on made its textures")
        // Field + shadows + gi.scene + 5 cascades + gi.fluence = 9 compute passes.
        #expect(r.light.computePasses() == 9)

        // Inspecting a specific cascade allocates unmerged cascade views.
        r.frame(makePrims(8), Gi(enabled: true), inspectCascade: 2)
        let insCascade = try! #require(r.light.inspect())
        #expect(insCascade.cascade != insCascade.fluence)
    }

    @Test("a_steady_frame_makes_no_bind_groups")
    func aSteadyFrameMakesNoBindGroups() {
        let r = LightTestRig()
        let glass = GlassRenderer.new(r.device, r.queue, WGPUTextureFormat_RGBA8Unorm)
        let panes = [Glass.rounded(40.0, 30.0, 80.0, 60.0, 16.0)]
        let glassFrame: (Gi?) -> WGPUCommandEncoder = { gi in
            let encoder = r.record(makePrims(8), gi)
            let fluence = r.light.inspect()!.fluence
            let lights = [Light.point(60.0, 40.0, 120.0)]
            let emitters = [GlassLight.fromEmitter(Prim.rect(20.0, 20.0, 30.0, 12.0).emissive(1.0, 0.6, 0.2, 2.0))].compactMap { $0 }
            let ok = glass.render(
                encoder,
                r.base,
                r.target,
                (rigW, rigH),
                1.0,
                panes,
                lights,
                emitters,
                GlassSettings(),
                fluence: fluence
            )
            #expect(ok)
            return encoder
        }

        for gi in [nil, Gi(enabled: true)] {
            for _ in 0..<2 {
                _ = glassFrame(gi)
            }
            let idle = r.liveBindGroups()
            _ = glassFrame(gi)
            #expect(r.liveBindGroups() == idle, "recording a steady frame made bind groups (gi: \(gi != nil))")
        }
    }

    @Test("cpu soft shadow estimate agrees with groundTruth across open, umbra, penumbra, and floating gap")
    func cpuSoftShadowEstimateMatchesGroundTruth() {
        let card = Prim.rect(80.0, 60.0, 60.0, 60.0).raised(24.0)
        let lightPos = SIMD3<Float>(40.0, 90.0, 48.0)
        let radius: Float = 16.0

        // Unobstructed point in front of the card
        let pOpen = SIMD3<Float>(60.0, 90.0, 0.0)
        let estOpen = cpu.estimate([card], pOpen, lightPos, radius)
        let gtOpen = cpu.groundTruth([card], pOpen, lightPos, radius, 6)
        #expect(estOpen > 0.95 && gtOpen > 0.95)

        // Deep umbra right behind the raised card
        let pUmbra = SIMD3<Float>(150.0, 90.0, 0.0)
        let estUmbra = cpu.estimate([card], pUmbra, lightPos, radius)
        let gtUmbra = cpu.groundTruth([card], pUmbra, lightPos, radius, 6)
        #expect(estUmbra < 0.15 && gtUmbra < 0.15)

        // Penumbra near shadow edge: partial visibility in (0, 1)
        let pPenumbra = SIMD3<Float>(155.0, 32.0, 0.0)
        let estPen = cpu.estimate([card], pPenumbra, lightPos, radius)
        let gtPen = cpu.groundTruth([card], pPenumbra, lightPos, radius, 8)
        #expect(estPen > 0.05 && estPen < 0.95)
        #expect(abs(estPen - gtPen) < 0.35)

        // Floating card lets low-angle light slip underneath its gap
        let floating = Prim.rect(80.0, 60.0, 60.0, 60.0).floating(28.0, 12.0)
        let lowLight = SIMD3<Float>(20.0, 90.0, 14.0)
        let under = SIMD3<Float>(160.0, 90.0, 0.0)
        let estUnder = cpu.estimate([floating], under, lowLight, 6.0)
        #expect(estUnder > 0.5)
    }

    @Test("cpu bevelNormal, fresnel, ggx, and glassSdf invariants")
    func cpuOpticsAndGlassInvariants() {
        // Interior normal flattens to +Z; boundary normal tilts outward toward gradient
        let flat = cpu.bevelNormal(sd: -20.0, grad: SIMD2<Float>(1.0, 0.0), bevelWidth: 4.0, bevelHeight: 2.0)
        #expect(abs(flat.x) < 1e-5 && abs(flat.y) < 1e-5 && abs(flat.z - 1.0) < 1e-5)
        let edge = cpu.bevelNormal(sd: -0.2, grad: SIMD2<Float>(1.0, 0.0), bevelWidth: 4.0, bevelHeight: 2.0)
        #expect(edge.x > 0.5 && edge.z > 0.0 && abs((edge.x * edge.x + edge.z * edge.z) - 1.0) < 1e-5)

        // Dielectric Fresnel: ~0.04 at normal incidence for crown glass (n=1.5), 1.0 under TIR
        let r0 = cpu.fresnel(1.0, 1.0, 1.5)
        #expect(abs(r0 - 0.04) < 1e-3)
        let tir = cpu.fresnel(0.2, 1.5, 1.0)
        #expect(tir == 1.0)

        // Smooth union merges grouped Glass panes closer than standalone panes; presence(0) vanishes
        let a = Glass.rounded(20.0, 20.0, 40.0, 40.0, 12.0).union(1)
        let b = Glass.rounded(64.0, 20.0, 40.0, 40.0, 12.0).union(1)
        let aStandalone = Glass.rounded(20.0, 20.0, 40.0, 40.0, 12.0)
        let bStandalone = Glass.rounded(64.0, 20.0, 40.0, 40.0, 12.0)
        let bridgePt = SIMD2<Float>(62.0, 40.0)
        let groupedSd = cpu.glassSdf([a, b], bridgePt, unionRadius: 28.0).sd
        let separateSd = cpu.glassSdf([aStandalone, bStandalone], bridgePt, unionRadius: 28.0).sd
        #expect(groupedSd < separateSd)

        let hidden = Glass.rounded(20.0, 20.0, 40.0, 40.0, 12.0).presence(0.0)
        #expect(cpu.glassSdf([hidden], SIMD2<Float>(40.0, 40.0)).sd > 1e4)
    }
}
