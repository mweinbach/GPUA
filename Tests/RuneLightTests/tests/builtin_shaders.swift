// Tests ported from: crates/rune-light/tests/builtin_shaders.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Testing
@testable import RuneFX
@testable import RuneLight

@Suite("RuneLight Builtin Shaders")
struct BuiltinShadersTests {
    @Test("every_builtin_pipeline_is_precompiled")
    func everyBuiltinPipelineIsPrecompiled() {
        let summary = buildEveryBuiltinPipeline()
        #expect(summary.timings.count == 6)
        for (_, ms) in summary.timings {
            #expect(ms >= 0.0 && ms.isFinite)
        }
        // 8 effect families * 2 blend modes * 2 formats (BGRA8UnormSrgb + RGBA16Float) = 32
        #expect(summary.fxBuiltPipelines == 32)
        // LightRenderer builds 7 pipelines: gbuffer, field, shadows, gi.scene, gi.cascade, gi.fluence, composite
        #expect(summary.lightPipelineCount == 7)
        // GlassRenderer builds 2 pipelines: glass.pyr and glass
        #expect(summary.glassPipelineCount == 2)
    }
}
