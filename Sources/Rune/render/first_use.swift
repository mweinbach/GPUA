// Ported from: crates/rune/src/render/first_use.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Diagnostic timing for first-time pipeline creation and precompiled-library cache misses.

import CWebGPU

@inline(__always)
private func durationMs(_ d: Duration) -> Double {
    let c = d.components
    return Double(c.seconds) * 1000.0 + Double(c.attoseconds) * 1e-15
}

extension Renderer {
    /// Compiles each lazy renderer sub-pipeline once on `device` and returns `(stage, milliseconds)` pairs.
    public static func firstUseMs(_ device: MetalDevice) -> [(String, Double)] {
        var timings: [(String, Double)] = []

        var t0 = RuneInstant.now()
        let r = Renderer(device, WGPUTextureFormat_BGRA8Unorm)
        timings.append(("uber", durationMs(t0.elapsed())))

        t0 = RuneInstant.now()
        _ = LayerBlurPipeline(device)
        timings.append(("layer_blur", durationMs(t0.elapsed())))

        t0 = RuneInstant.now()
        let bb = BackdropBlur(device, r.bindLayout)
        bb.ensureComposite(device, WGPUTextureFormat_BGRA8Unorm)
        timings.append(("backdrop_blur", durationMs(t0.elapsed())))

        #if !os(WASI)
        t0 = RuneInstant.now()
        _ = SurfaceRenderer(device, WGPUTextureFormat_BGRA8Unorm)
        timings.append(("video", durationMs(t0.elapsed())))
        #endif

        return timings
    }
}

/// Number of built-in shader pipeline keys that missed the precompiled table on `device`, if supported.
public func precompiledMisses(_ device: MetalDevice) -> Int? {
    _ = device
    #if os(macOS)
    return metalBuiltinMisses()
    #else
    return nil
    #endif
}
