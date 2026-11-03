// Tests ported from: crates/rune-fx/tests/blend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneMotion
import Testing
@testable import RuneFX

private typealias Fx = RuneFX.Fx

// PORT NOTE: Self-contained W3C Compositing and Blending Level 1 separable reference oracle so
// `RuneFXTests` does not import the unported `RuneRef` target.
private enum SeparableOracle {
    case multiply
    case screen
    case overlay
    case softLight

    func channel(_ cb: Float, _ cs: Float) -> Float {
        switch self {
        case .multiply:
            return cb * cs
        case .screen:
            return cb + cs - cb * cs
        case .overlay:
            return cb <= 0.5 ? (2.0 * cb * cs) : (1.0 - 2.0 * (1.0 - cb) * (1.0 - cs))
        case .softLight:
            if cs <= 0.5 {
                return cb - (1.0 - 2.0 * cs) * cb * (1.0 - cb)
            }
            let d = cb <= 0.25 ? (((16.0 * cb - 12.0) * cb + 4.0) * cb) : max(cb, 0.0).squareRoot()
            return cb + (2.0 * cs - 1.0) * (d - cb)
        }
    }
}

private func compositeOracle(_ mode: SeparableOracle, _ src: [Float], _ dst: [Float]) -> [Float] {
    let asVal = min(max(max(src[3], max(src[0], max(src[1], src[2]))), 0.0), 1.0)
    let ab = min(max(dst[3], 0.0), 1.0)
    let cs: [Float] = asVal > 1e-6
        ? [min(max(src[0] / asVal, 0.0), 1.0), min(max(src[1] / asVal, 0.0), 1.0), min(max(src[2] / asVal, 0.0), 1.0)]
        : [0.0, 0.0, 0.0]
    let cb: [Float] = ab > 1e-6
        ? [min(max(dst[0] / ab, 0.0), 1.0), min(max(dst[1] / ab, 0.0), 1.0), min(max(dst[2] / ab, 0.0), 1.0)]
        : [0.0, 0.0, 0.0]
    var out = [Float](repeating: 0.0, count: 4)
    for c in 0..<3 {
        let b = mode.channel(cb[c], cs[c])
        out[c] = (1.0 - asVal) * dst[c] + asVal * ((1.0 - ab) * cs[c] + ab * b)
    }
    out[3] = asVal + ab * (1.0 - asVal)
    return out
}

private func renderBlendFrame(
    device: WGPUDevice,
    queue: WGPUQueue,
    fx: FxRenderer,
    format: WGPUTextureFormat,
    clear: SIMD4<Float>,
    layers: [FxLayer],
    mode: FxBlend,
    srgb: Bool,
    backdrop: WGPUTextureView?
) -> [UInt8] {
    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
    fx.prepareWithSlots(
        device,
        queue,
        FxFrame(viewport: [96, 96], scale: 1.0, layers: layers, backdrop: backdrop, sources: []),
        [FxSlot.default().blend(mode).backdropSrgb(srgb)]
    )
    let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: clear)
    fx.drawAll(pass, layers, nil)
    return SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)
}

@Suite("RuneFX Separable Blending")
struct BlendIntegrationTests {
    @Test("soft_glow_coverage_matches_reference_blending_in_both_spaces")
    func softGlowCoverageMatchesReferenceBlendingInBothSpaces() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let modes: [(FxBlend, SeparableOracle)] = [
            (.multiply, .multiply),
            (.screen, .screen),
            (.overlay, .overlay),
            (.softLight, .softLight),
        ]

        for srgb in [false, true] {
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let fx = FxRenderer.new(device, format, FxOptions())
            fx.setSrgbBlend(srgb)

            let decode: (ArraySlice<UInt8>) -> [Float] = { p in
                let i = p.startIndex
                return (0..<4).map { c in
                    let v = Float(p[i + c]) / 255.0
                    return (c < 3 && !srgb) ? RuneMotion.srgbDecode(v) : v
                }
            }

            for opacity: Float in [0.35, 1.0] {
                let layers = [
                    Fx.glow(GlowParams(
                        color: rgb(0xc85a14),
                        core: rgb(0xe88c28),
                        radius: 10.0,
                        intensity: 0.8,
                        occlusion: 1.0,
                        reach: 2.5
                    ))
                    .on(Shape.rounded(32.0, 32.0, 32.0, 32.0, 10.0))
                    .at(0.5)
                    .opacity(opacity)
                ]
                let source = renderBlendFrame(
                    device: device,
                    queue: queue,
                    fx: fx,
                    format: format,
                    clear: .zero,
                    layers: layers,
                    mode: .normal,
                    srgb: srgb,
                    backdrop: nil
                )

                let backdrops: [([Float], Float)] = [
                    ([0.98, 0.97, 0.95], 1.0),
                    ([0.3, 0.6, 0.8], 1.0),
                    ([0.3, 0.6, 0.8], 0.35),
                    ([0.0, 0.0, 0.0], 0.0),
                ]

                for (bgRgb, alpha) in backdrops {
                    let clear = SIMD4<Float>(
                        (srgb ? bgRgb[0] : RuneMotion.srgbDecode(bgRgb[0])) * alpha,
                        (srgb ? bgRgb[1] : RuneMotion.srgbDecode(bgRgb[1])) * alpha,
                        (srgb ? bgRgb[2] : RuneMotion.srgbDecode(bgRgb[2])) * alpha,
                        alpha
                    )
                    let backdrop = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
                    let bytes = renderBlendFrame(
                        device: device,
                        queue: queue,
                        fx: fx,
                        format: format,
                        clear: clear,
                        layers: [],
                        mode: .normal,
                        srgb: srgb,
                        backdrop: nil
                    )
                    SyntheticFXGPU.shared.writeHeadlessTextureBytes(backdrop.texture, width: 96, height: 96, rgbaBytes: bytes)

                    for (mode, oracle) in modes {
                        let actual = renderBlendFrame(
                            device: device,
                            queue: queue,
                            fx: fx,
                            format: format,
                            clear: clear,
                            layers: layers,
                            mode: mode,
                            srgb: srgb,
                            backdrop: backdrop.view
                        )
                        var partial = 0
                        var mismatch: String?
                        let pixelCount = 96 * 96
                        for pxIdx in 0..<pixelCount {
                            let off = pxIdx * 4
                            let src = decode(source[off..<(off + 4)])
                            if src[3] > 0.02 && src[3] < 0.3 {
                                partial += 1
                            }
                            let dst = decode(bytes[off..<(off + 4)])
                            let want = compositeOracle(oracle, src, dst)
                            for c in 0..<4 {
                                let v = (c < 3 && !srgb) ? RuneMotion.srgbEncode(want[c]) : want[c]
                                let wantByte = Int((min(max(v * 255.0, 0.0), 255.0)).rounded())
                                let gotByte = Int(actual[off + c])
                                if abs(gotByte - wantByte) > 3 && mismatch == nil {
                                    mismatch = "\(mode) srgb=\(srgb) opacity=\(opacity) alpha=\(alpha) ch=\(c): \(gotByte) vs \(wantByte)"
                                }
                            }
                        }
                        #expect(mismatch == nil, "\(mismatch ?? "")")
                        #expect(partial > 100, "exercise soft edges, not just opaque centres")
                    }
                }
            }
        }
    }
}
