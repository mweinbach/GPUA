// Tests ported from: crates/rune-fx/tests/fills.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneMotion
import Testing
@testable import RuneFX

private typealias Fx = RuneFX.Fx

/// Draws `layers` at `scale` into a transparent `w`×`h` `Rgba16Float` target with no dither, and
/// reads it back as premultiplied linear RGBA (or sRGB-encoded with `srgb`).
private func renderFills(
    _ w: UInt32,
    _ h: UInt32,
    _ scale: Float,
    _ srgb: Bool,
    _ layers: [FxLayer]
) -> [[Float]] {
    renderFillsAt(w, h, scale, srgb, [0.0, 0.0], layers)
}

private func renderFillsAt(
    _ w: UInt32,
    _ h: UInt32,
    _ scale: Float,
    _ srgb: Bool,
    _ origin: [Float],
    _ layers: [FxLayer]
) -> [[Float]] {
    let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
    let fmt = WGPUTextureFormat_RGBA16Float
    let fx = FxRenderer.new(device, fmt, FxOptions(dither: false))
    fx.setSrgbBlend(srgb)
    precondition((w * 8) % 256 == 0, "row alignment")

    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: fmt)
    let vw = w + UInt32(max(origin[0].rounded(.up), 0.0))
    let vh = h + UInt32(max(origin[1].rounded(.up), 0.0))
    let stats = fx.prepare(
        device,
        queue,
        FxFrame(viewport: [vw, vh], scale: scale, layers: layers, backdrop: nil, sources: [])
    )
    #expect(Int(stats.drawn) == layers.count)

    let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: .zero)
    for k in 0..<layers.count {
        fx.drawLayerIn(pass, fmt, origin, k)
    }

    let words = SyntheticFXGPU.shared.readHeadlessTextureF16Words(target.texture)
    var out: [[Float]] = []
    out.reserveCapacity(words.count / 4)
    var idx = 0
    while idx + 3 < words.count {
        out.append([
            decodeF16(words[idx]),
            decodeF16(words[idx + 1]),
            decodeF16(words[idx + 2]),
            decodeF16(words[idx + 3]),
        ])
        idx += 4
    }
    return out
}

private func decodeF16(_ h: UInt16) -> Float {
    fxF16BitsToFloat(h)
}

private func lum(_ p: [Float]) -> Float {
    0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2]
}

/// A 56 pt key at 2× in a 128×128 px target.
private let keySpec: (UInt32, UInt32, Float) = (128, 128, 2.0)

private func keyShape() -> Shape {
    Shape.rounded(4.0, 4.0, 56.0, 56.0, 8.0)
}

private func layerIsBorder(_ l: FxLayer) -> Bool {
    if case .fill(let p) = l.fx {
        return p.border > 0.0
    }
    return false
}

@Suite("RuneFX Fills Integration")
struct FillsIntegrationTests {
    @Test("external_struct_update_and_emitted_rust_compile")
    func externalStructUpdateAndEmittedRustCompile() {
        let _ = FxLayer(
            fx: Fx.distort(DistortParams.chromaSplit([0.0, 0.0])),
            shape: Shape.rounded(0.0, 0.0, 16.0, 16.0, 0.0),
            place: .over,
            time: 0.0,
            seed: 1,
            reducedMotion: false,
            source: nil,
            opacity: 1.0
        )
        let card = Shape.rounded(10.0, 10.0, 120.0, 80.0, 12.0)

        var rose = LiquidMetalParams.rose()
        rose.flow = 0.9
        rose.scale = 80.0

        var dusk = MeshGradientParams.dusk()
        dusk.colors = Stops.hex([0x1b1f3b, 0xff6f91, 0xffc75f, 0x845ec2])
        dusk.drift = 0.15

        var bdDither = DitherParams.backdrop()
        bdDither.pattern = .blueNoise
        bdDither.pixel = 2.0

        var sweep = GrainGradientParams.sweep()
        sweep.kind = .conic
        sweep.mono = false
        sweep.amount = 0.3

        var reeded = FlutedGlassParams.reeded()
        reeded.rib = 10.0
        reeded.refraction = 7.0
        reeded.frost = 0.4

        var mint = MetaballParams.mint()
        mint.count = 4
        mint.gloss = 0.7

        var marble = SwirlParams.marble()
        marble.twist = -0.8
        marble.warp = 1.2

        var stained = VoronoiParams.stained()
        stained.scale = 24.0
        stained.edge = 2.0

        var dunes = WaveParams.dunes()
        dunes.amplitude = 0.06
        dunes.softness = 0.01

        var halftone = HalftoneParams.print()
        halftone.input = .linear
        halftone.cell = 5.0

        var plastic = PlasticParams.glossy()
        plastic.roughness = 0.6
        plastic.dome = -0.4

        var gold = LiquidMetalParams.gold()
        gold.anchor = .element

        let layers: [Fx] = [
            Fx.fill(rose.border(4.0).intensity(0.8)),
            Fx.fill(dusk),
            Fx.fill(bdDither),
            Fx.fill(sweep),
            Fx.fill(reeded),
            Fx.fill(mint),
            Fx.fill(marble),
            Fx.fill(stained),
            Fx.fill(dunes),
            Fx.fill(halftone),
            Fx.fill(plastic.border(5.0)),
            Fx.fill(LiquidMetalParams.chrome().anchor(.element)),
            Fx.fill(gold),
        ]

        for fx in layers {
            guard case .fill(let p) = fx else {
                Issue.record("expected Fx.fill")
                continue
            }
            #expect(!p.toRust().isEmpty)
            let layer = fx.on(card).at(1.0)
            #expect(layer.place == (p.needsBackdrop() ? .over : .under))
        }
    }

    @Test("linear_backdrop_views_are_not_double_decoded_in_srgb_frames")
    func linearBackdropViewsAreNotDoubleDecodedInSrgbFrames() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let fx = FxRenderer.new(device, WGPUTextureFormat_RGBA8Unorm, FxOptions())
        fx.setSrgbBlend(true)
        let layers = [
            Fx.distort(DistortParams.chromaSplit([1e-6, 0.0]))
                .on(Shape.rounded(0.0, 0.0, 32.0, 32.0, 0.0))
        ]
        for format in [WGPUTextureFormat_RGBA8UnormSrgb, WGPUTextureFormat_RGBA16Float] {
            let bd = SyntheticFXGPU.shared.createHeadlessTexture(width: 32, height: 32, format: format)
            for perSlot in [false, true] {
                let target = SyntheticFXGPU.shared.createHeadlessTexture(
                    width: 32,
                    height: 32,
                    format: WGPUTextureFormat_RGBA8Unorm
                )
                let frame = FxFrame(
                    viewport: [32, 32],
                    scale: 1.0,
                    layers: layers,
                    backdrop: perSlot ? nil : bd.view,
                    sources: []
                )
                let slots = perSlot ? [FxSlot.default().backdropSrgb(false)] : []
                #expect(fx.prepareWithSlots(device, queue, frame, slots).drawn == 1)

                _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(
                    view: bd.view,
                    clear: SIMD4<Float>(0.25, 0.125, 0.0625, 1.0)
                )
                let encoder = SyntheticFXGPU.shared.makeEncoder()
                fx.blurBackdrop(device, queue, encoder, bd.view, 0)
                let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(
                    view: target.view,
                    clear: SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
                )
                fx.drawLayer(pass, 0)

                let pixels = SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)
                let at = (16 * 32 + 16) * 4
                let expected: [UInt8] = [Float(0.25), 0.125, 0.0625].map { c in
                    UInt8((RuneMotion.srgbEncode(c) * 255.0).rounded())
                }
                for ch in 0..<3 {
                    let got = Int(pixels[at + ch])
                    let want = Int(expected[ch])
                    #expect(abs(got - want) <= 2, "format=\(format) perSlot=\(perSlot): \(got) != \(want)")
                }
            }
        }
    }

    @Test("gpu_fills_are_finite_at_extremes_degenerate_params_and_large_time")
    func gpuFillsAreFiniteAtExtremesDegenerateParamsAndLargeTime() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let fmt = WGPUTextureFormat_RGBA16Float
        let fx = FxRenderer.new(device, fmt, FxOptions(dither: true))
        let w: UInt32 = 32
        let h: UInt32 = 32
        let target = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: fmt)
        let bd = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: fmt)
        let src = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: fmt)

        let shape = Shape.rounded(2.0, 2.0, 28.0, 28.0, 6.0)
        let draw: (FxLayer) -> [UInt16] = { layer in
            let stats = fx.prepare(
                device,
                queue,
                FxFrame(
                    viewport: [w, h],
                    scale: 1.0,
                    layers: [layer],
                    backdrop: bd.view,
                    sources: [src.view]
                )
            )
            #expect(stats.drawn == 1)
            let enc = SyntheticFXGPU.shared.makeEncoder()
            fx.blurBackdrop(device, queue, enc, bd.view, 0)
            let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(
                view: target.view,
                clear: SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
            )
            fx.drawLayer(pass, 0)
            let words = SyntheticFXGPU.shared.readHeadlessTextureF16Words(target.texture)
            for word in words {
                #expect((word & 0x7c00) != 0x7c00, "non-finite f16 word \(String(word, radix: 16))")
            }
            return words
        }

        // Every style at catalog min, catalog max, and t = 1e5 s.
        for style in fillStyles() {
            var minFill = style.defaultFill()
            var maxFill = style.defaultFill()
            for p in style.params {
                switch p.kind {
                case .number(let lo, let hi, _, _):
                    _ = minFill.set(p.id, .number(lo))
                    _ = maxFill.set(p.id, .number(hi))
                case .count(let lo, let hi):
                    _ = minFill.set(p.id, .count(lo))
                    _ = maxFill.set(p.id, .count(hi))
                case .choice(let c):
                    _ = minFill.set(p.id, .choice(0))
                    _ = maxFill.set(p.id, .choice(c.count - 1))
                case .colors(let lo, let hi):
                    let palette: [UInt32] = [0x112233, 0x445566, 0x778899, 0xaabbcc, 0xddeeff, 0xff8800]
                    _ = minFill.set(p.id, .colors(Stops.hex(Array(palette.prefix(lo)))))
                    _ = maxFill.set(p.id, .colors(Stops.hex(Array(palette.prefix(hi)))))
                default:
                    break
                }
            }
            _ = draw(Fx.fill(minFill).on(shape).source(0, Rect.new(2.0, 2.0, 28.0, 28.0)).at(0.5))
            _ = draw(Fx.fill(maxFill).on(shape).source(0, Rect.new(2.0, 2.0, 28.0, 28.0)).at(0.5))

            let preset = style.defaultFill()
            let f0 = draw(Fx.fill(preset).on(shape).at(1e5))
            let f1 = draw(Fx.fill(preset).on(shape).at(1e5 + 0.25))
            if Fx.fill(preset).on(shape).isAnimating() {
                #expect(f0 != f1, "\(style.id) still animates at t = 1e5")
            }
        }

        // Degenerate cases.
        let pixelCenter = Shape.rounded(0.5, 0.5, 20.0, 20.0, 0.0)
        var conic = GrainGradientParams.sweep()
        conic.kind = .conic
        conic.center = [0.5, 0.5]
        _ = draw(Fx.fill(conic).on(pixelCenter).at(1.0))

        var zeroBlob = MetaballParams.lava()
        zeroBlob.size = 0.0
        _ = draw(Fx.fill(zeroBlob).on(shape).at(1.0))

        var sharpMesh = MeshGradientParams.dusk()
        sharpMesh.sharpness = 50.0
        _ = draw(Fx.fill(sharpMesh).on(shape).at(1.0))

        var imgDither = DitherParams.bayer()
        imgDither.input = .image
        _ = draw(Fx.fill(imgDither).on(shape).source(0, Rect.new(0.0, 0.0, 0.0, 0.0)).at(1.0))

        for tiny in [Shape.rounded(2.0, 2.0, 4.0, 4.0, 2.0), Shape.rounded(2.5, 2.5, 1.0, 1.0, 0.5)] {
            var pGloss = PlasticParams.glossy()
            pGloss.roughness = 0.0
            pGloss.dome = 1.0
            pGloss.bevel = 48.0
            _ = draw(Fx.fill(pGloss).on(tiny))

            var pDish = PlasticParams.dished()
            pDish.roughness = 1.0
            pDish.dome = -1.0
            pDish.bevel = 48.0
            _ = draw(Fx.fill(pDish.border(20.0)).on(tiny))

            var mTiny = LiquidMetalParams.chrome()
            mTiny.bevel = 48.0
            mTiny.dome = -1.0
            mTiny.anchor = .element
            _ = draw(Fx.fill(mTiny).on(tiny).at(1.0))
        }

        var nanPlastic = PlasticParams.glossy()
        nanPlastic.roughness = .nan
        nanPlastic.dome = .infinity
        nanPlastic.bevel = .nan
        nanPlastic.angle = -.infinity
        _ = draw(Fx.fill(nanPlastic).on(shape))

        var nanMetal = LiquidMetalParams.chrome()
        nanMetal.flow = .nan
        nanMetal.scale = .nan
        nanMetal.bevel = .infinity
        nanMetal.dome = .nan
        nanMetal.contrast = .nan
        _ = draw(Fx.fill(nanMetal).on(shape).at(1.0))
    }

    @Test("plastic_never_paints_past_its_coverage")
    func plasticNeverPaintsPastItsCoverage() {
        let (w, h, s) = keySpec
        let colorCases: [(Rgb, Float)] = [
            (rgb(0xffffff), 1.0),
            (rgb(0xffd60a), 1.0),
            (rgb(0xd7263d), 0.5),
            (rgb(0x202226), 1.0),
        ]
        for srgb in [false, true] {
            for roughness: Float in [0.0, 0.05, 0.45, 1.0] {
                for (color, intensity) in colorCases {
                    var p = PlasticParams.glossy()
                    p.color = color
                    p.roughness = roughness
                    for layer in [Fx.fill(p.intensity(intensity)).on(keyShape()), Fx.fill(p.border(6.0)).on(keyShape())] {
                        let img = renderFills(w, h, s, srgb, [layer])
                        let worst = img.reduce(-Float.greatestFiniteMagnitude) { acc, px in
                            max(acc, max(px[0], max(px[1], px[2])) - px[3])
                        }
                        #expect(worst <= 2e-3, "srgb \(srgb) roughness \(roughness) x\(intensity): rgb exceeds alpha by \(worst)")
                        let centre = img[Int((h / 2) * w + (w / 2))]
                        #expect(layerIsBorder(layer) || abs(centre[3] - intensity) < 2e-3, "centre alpha \(centre)")
                    }
                }
            }
            for dome: Float in [-1.0, 1.0] {
                let p = PlasticParams(color: rgb(0xffd60a), roughness: 0.0, dome: dome, bevel: 40.0, angle: 0.8)
                for sh in [keyShape(), Shape.rounded(4.0, 4.0, 4.0, 4.0, 1.5)] {
                    let img = renderFills(w, h, s, srgb, [Fx.fill(p).on(sh)])
                    let worst = img.reduce(-Float.greatestFiniteMagnitude) { acc, px in
                        max(acc, max(px[0], max(px[1], px[2])) - px[3])
                    }
                    #expect(worst <= 2e-3, "srgb \(srgb) dome \(dome): rgb exceeds alpha by \(worst)")
                }
            }
        }
    }

    @Test("plastic_highlight_follows_roughness_and_light")
    func plasticHighlightFollowsRoughnessAndLight() {
        let (w, h, s) = keySpec
        let base = rgb(0x3d6fd6)
        var peaks: [(Float, Int)] = []
        for roughness: Float in [0.05, 0.45, 1.0] {
            var p = PlasticParams.glossy()
            p.color = base
            p.roughness = roughness
            let img = renderFills(w, h, s, false, [Fx.fill(p).on(keyShape())])
            let at: (UInt32, UInt32) -> [Float] = { x, y in img[Int(y * w + x)] }
            let centre = at(w / 2, h / 2)
            for c in 0..<3 {
                let lift = centre[c] - base[c]
                #expect(lift >= -0.01 && lift < 0.07, "roughness \(roughness): centre \(centre) vs \(base)")
            }
            let face = img.filter { $0[3] > 0.999 }.map { lum($0) - lum(centre) }
            let peak = face.reduce(Float(0.0), max)
            let spread = face.filter { $0 > 0.5 * peak }.count
            let lit = lum(at(64, 14))
            let shade = lum(at(64, 114))
            #expect(lit > shade * 1.3, "roughness \(roughness): lit rim \(lit) vs shaded rim \(shade)")
            peaks.append((peak, spread))
        }
        #expect(peaks[0].0 > peaks[1].0 && peaks[1].0 > peaks[2].0, "gloss is brighter: \(peaks)")
        #expect(peaks[0].1 < peaks[2].1, "gloss is tighter: \(peaks)")
    }

    @Test("element_anchored_metal_keys_are_identical")
    func elementAnchoredMetalKeysAreIdentical() {
        let keysAt: (FillAnchor, Float, Float, Float) -> [FxLayer] = { anchor, t, ox, oy in
            (0..<8).map { k in
                Fx.fill(LiquidMetalParams.chrome().anchor(anchor))
                    .on(Shape.rounded(ox + Float(k) * 28.0, oy, 24.0, 24.0, 5.0))
                    .at(t)
            }
        }
        let w: UInt32 = 512
        let h: UInt32 = 64
        let tile: ([[Float]], UInt32) -> [[UInt32]] = { img, k in
            let x0 = 6 + 56 * k
            var res: [[UInt32]] = []
            res.reserveCapacity(52 * 52)
            for y: UInt32 in 6..<58 {
                for x: UInt32 in x0..<(x0 + 52) {
                    res.append(img[Int(y * w + x)].map(\.bitPattern))
                }
            }
            return res
        }

        for t: Float in [1.3, 1e5 + 0.37] {
            let img = renderFills(w, h, 2.0, false, keysAt(.element, t, 4.0, 4.0))
            let first = tile(img, 0)
            #expect(first.contains { Float(bitPattern: $0[3]) > 0.99 }, "the key is drawn")
            for k: UInt32 in 1..<8 {
                #expect(tile(img, k) == first, "t = \(t): key \(k) differs from key 0")
            }
            let world = renderFills(w, h, 2.0, false, keysAt(.world, t, 4.0, 4.0))
            let world0 = tile(world, 0)
            #expect((1..<8).contains { tile(world, UInt32($0)) != world0 }, "t = \(t): window-anchored keys should differ")
        }

        let subpx = renderFills(w, h, 2.0, false, keysAt(.element, 1.3, 4.25, 4.375))
        let subpxTile: ([[Float]], UInt32) -> [[UInt32]] = { img, k in
            let x0 = 6 + 56 * k
            var res: [[UInt32]] = []
            res.reserveCapacity(53 * 53)
            for y: UInt32 in 6..<59 {
                for x: UInt32 in x0..<(x0 + 53) {
                    res.append(img[Int(y * w + x)].map(\.bitPattern))
                }
            }
            return res
        }
        let sub0 = subpxTile(subpx, 0)
        for k: UInt32 in 1..<8 {
            #expect(subpxTile(subpx, k) == sub0, "fractional offset: key \(k) differs from key 0")
        }

        let inLayer = renderFillsAt(w, h, 2.0, false, [16.0, 12.0], keysAt(.element, 1.3, 12.25, 10.375))
        for k: UInt32 in 0..<8 {
            #expect(subpxTile(inLayer, k) == sub0, "in-layer origin shift: key \(k) differs from direct draw")
        }

        let scale15 = renderFills(w, h, 1.5, false, keysAt(.element, 1.3, 4.0, 4.0))
        let tile15: ([[Float]], UInt32) -> [[UInt32]] = { img, k in
            let x0 = 4 + 42 * k
            var res: [[UInt32]] = []
            res.reserveCapacity(40 * 40)
            for y: UInt32 in 4..<44 {
                for x: UInt32 in x0..<(x0 + 40) {
                    res.append(img[Int(y * w + x)].map(\.bitPattern))
                }
            }
            return res
        }
        let s15_0 = tile15(scale15, 0)
        for k: UInt32 in 1..<8 {
            #expect(tile15(scale15, k) == s15_0, "scale 1.5: key \(k) differs from key 0")
        }

        for fold: Float in [512.0, 1024.0] {
            let dt: Float = 1.0 / 64.0
            let key = Shape.rounded(4.0, 4.0, 24.0, 24.0, 5.0)
            let before = renderFills(128, 64, 2.0, false, [Fx.fill(LiquidMetalParams.chrome()).on(key).at(fold - dt)])
            let atFold = renderFills(128, 64, 2.0, false, [Fx.fill(LiquidMetalParams.chrome()).on(key).at(fold)])
            let after = renderFills(128, 64, 2.0, false, [Fx.fill(LiquidMetalParams.chrome()).on(key).at(fold + dt)])
            #expect(before == after, "triangle wave is symmetric across \(fold)")
            var step: Float = 0.0
            for idx in 0..<before.count {
                for c in 0..<4 {
                    step = max(step, abs(before[idx][c] - atFold[idx][c]))
                }
            }
            #expect(step < 0.2, "no frame jump at \(fold): max step \(step)")
        }
    }
}
