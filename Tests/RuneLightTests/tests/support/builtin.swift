// Tests ported from: crates/rune-light/tests/support/builtin.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import Foundation
@testable import RuneFX
@testable import RuneLight

private func measureMs<T>(_ body: () -> T) -> (T, Double) {
    let start = ProcessInfo.processInfo.systemUptime
    let out = body()
    let elapsedMs = (ProcessInfo.processInfo.systemUptime - start) * 1e3
    return (out, elapsedMs)
}

struct BuiltinShaderBuildSummary {
    var timings: [(String, Double)]
    var fxBuiltPipelines: Int
    var lightPipelineCount: Int
    var glassPipelineCount: Int
}

/// Builds every built-in pipeline `RuneFX` and `RuneLight` ship, timing each step in milliseconds.
// PORT NOTE: Headless port of `crates/rune-light/tests/support/builtin.rs` without referencing the
// unported `Rune` crate; exercises every WGSL resource bundle shader and pipeline layout in both
// `RuneFX` and `RuneLight`.
func buildEveryBuiltinPipeline() -> BuiltinShaderBuildSummary {
    let format = WGPUTextureFormat_BGRA8UnormSrgb
    var timings: [(String, Double)] = []

    let (fxCtx, _) = measureMs { SyntheticFXGPU.shared.makeHeadlessContext() }
    let (fx, fxInitMs) = measureMs { FxRenderer.new(fxCtx.device, format, FxOptions()) }
    timings.append(("fx", fxInitMs))

    let (_, fxAddFmtMs) = measureMs { fx.addFormat(fxCtx.device, WGPUTextureFormat_RGBA16Float) }
    timings.append(("fx_layer_format", fxAddFmtMs))

    let (_, fxEveryMs) = measureMs { fx.buildEveryPipeline() }
    timings.append(("fx_every_pipeline", fxEveryMs))

    let (_, fxFireMs) = measureMs { fx.setFireSim(fxCtx.device, true) }
    timings.append(("fx_fire_sim", fxFireMs))

    let (lightCtx, _) = measureMs { SyntheticLightGPU.shared.makeHeadlessContext() }
    let pipesBeforeLight = SyntheticLightGPU.shared.pipelineCount(for: lightCtx.device)
    let (_, lightMs) = measureMs {
        _ = LightRenderer.new(lightCtx.device, lightCtx.queue, format)
    }
    let pipesAfterLight = SyntheticLightGPU.shared.pipelineCount(for: lightCtx.device)
    timings.append(("light", lightMs))

    let (_, glassMs) = measureMs {
        _ = GlassRenderer.new(lightCtx.device, lightCtx.queue, format)
    }
    let pipesAfterGlass = SyntheticLightGPU.shared.pipelineCount(for: lightCtx.device)
    timings.append(("glass", glassMs))

    return BuiltinShaderBuildSummary(
        timings: timings,
        fxBuiltPipelines: fx.builtPipelines(),
        lightPipelineCount: pipesAfterLight - pipesBeforeLight,
        glassPipelineCount: pipesAfterGlass - pipesAfterLight
    )
}
