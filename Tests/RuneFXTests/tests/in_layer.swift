// Tests ported from: crates/rune-fx/tests/in_layer.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! An effect drawn at a compositor effect slot: inside a faded, rounded layer, in either blend
//! mode, through one renderer serving the frame target and the layer's target.
// PORT NOTE: Upstream drives `rune::App` with a `Dusk` compositor; since `Rune` is not yet ported,
// this harness drives the identical `FxRenderer` slot/backdrop/isolated-layer contract directly
// against `SyntheticFXGPU.shared` with zero `Rune` imports.

import CWebGPU
import RuneMotion
import Testing
@testable import RuneFX

private typealias Fx = RuneFX.Fx

// MARK: - Minimal Effect-Slot Compositor Harness

private struct SlotDesc {
    var rectPx: [Float]        // [x, y, w, h] in window device pixels
    var radiusPx: Float        // corner radius in window device pixels
    var scale: Float           // slot scale (device px per pt)
    var clip: [Float] = noClip // window device-pixel clip [x0, y0, x1, y1]
    var fade: [UInt32] = [0, 0, 0, 0]
    var mark: UInt32 = 1
    var backdrop: Bool = false
}

private func dusk() -> Fx {
    Fx.fill(MeshGradientParams.dusk())
}

private func glow(_ occlusion: Float) -> Fx {
    Fx.glow(GlowParams(radius: 12.0, occlusion: occlusion))
}

private func frostedGlassFx(_ mark: UInt32) -> Fx {
    switch mark {
    case 1:
        return Fx.lens(LensParams(depth: 0.0, magnification: 1.0, frost: 0.85, shadow: 0.0, rim: 0.0))
    default:
        var p = FlutedGlassParams.frosted()
        p.frost = 0.85
        p.refraction = 0.0
        p.dispersion = 0.0
        p.highlight = 0.0
        return Fx.fill(p)
    }
}

private func identityGlassAndDitherFx(_ mark: UInt32) -> Fx {
    switch mark {
    case 1:
        var p = FlutedGlassParams.reeded()
        p.refraction = 0.0
        p.frost = 0.0
        p.dispersion = 0.0
        p.highlight = 0.0
        p.tintAmount = 0.0
        return Fx.fill(p)
    case 2:
        var p = FlutedGlassParams.reeded()
        p.refraction = 0.0
        p.frost = 0.6
        p.dispersion = 0.0
        p.highlight = 0.0
        p.tintAmount = 0.0
        return Fx.fill(p)
    default:
        return Fx.fill(DitherParams.backdrop())
    }
}

private func px(_ rgba: [UInt8], _ width: UInt32, _ x: UInt32, _ y: UInt32) -> [UInt8] {
    let at = Int((y * width + x) * 4)
    return [rgba[at], rgba[at + 1], rgba[at + 2]]
}

private func hexWorkingColor(_ hex: UInt32, srgb: Bool) -> SIMD4<Float> {
    let r = Float((hex >> 16) & 0xFF) / 255.0
    let g = Float((hex >> 8) & 0xFF) / 255.0
    let b = Float(hex & 0xFF) / 255.0
    if srgb {
        return SIMD4<Float>(r, g, b, 1.0)
    }
    return SIMD4<Float>(RuneMotion.srgbDecode(r), RuneMotion.srgbDecode(g), RuneMotion.srgbDecode(b), 1.0)
}

private func sdRoundedBox(_ q: SIMD2<Float>, _ half: SIMD2<Float>, _ radius: Float) -> Float {
    let r = min(max(radius, 0.0), min(half.x, half.y))
    let k = SIMD2<Float>(abs(q.x) - half.x + r, abs(q.y) - half.y + r)
    return (max(k.x, 0.0) * max(k.x, 0.0) + max(k.y, 0.0) * max(k.y, 0.0)).squareRoot() + min(max(k.x, k.y), 0.0) - r
}

/// Paints an anti-aliased solid rectangle `[x, y, w, h]` (in window device pixels) into `view`
/// whose top-left sits at `origin` in window device pixels.
private func paintSolidRect(
    view: WGPUTextureView,
    origin: [Float] = [0.0, 0.0],
    rect: [Float],
    hex: UInt32,
    srgb: Bool
) {
    let col = hexWorkingColor(hex, srgb: srgb)
    let half = SIMD2<Float>(rect[2] * 0.5, rect[3] * 0.5)
    let center = SIMD2<Float>(rect[0] + half.x, rect[1] + half.y)
    let ox = origin[0]
    let oy = origin[1]
    SyntheticFXGPU.shared.mutateViewMip0(view) { fmt, mip in
        let x0 = max(Int((rect[0] - ox - 1.0).rounded(.down)), 0)
        let y0 = max(Int((rect[1] - oy - 1.0).rounded(.down)), 0)
        let x1 = min(Int((rect[0] + rect[2] - ox + 1.0).rounded(.up)), mip.width)
        let y1 = min(Int((rect[1] + rect[3] - oy + 1.0).rounded(.up)), mip.height)
        guard x1 > x0, y1 > y0 else { return }
        for ty in y0..<y1 {
            let py = Float(ty) + 0.5 + oy
            for tx in x0..<x1 {
                let px = Float(tx) + 0.5 + ox
                let d = sdRoundedBox(SIMD2<Float>(px - center.x, py - center.y), half, 0.0)
                let cov = min(max(0.5 - d, 0.0), 1.0)
                if cov <= 0.0 { continue }
                let src = col * cov
                let idx = ty * mip.width + tx
                let dst = mip.pixels[idx]
                let out = src + dst * (1.0 - src.w)
                mip.pixels[idx] = quantizeForFormat(out, fmt)
            }
        }
    }
}

/// Separable Gaussian blur of `view` in place (sigma in device pixels).
private func blurLayerInPlace(view: WGPUTextureView, sigma: Float) {
    guard sigma > 0.0 else { return }
    let rad = max(Int((sigma * 3.0).rounded(.up)), 1)
    var weights = [Float](repeating: 0.0, count: 2 * rad + 1)
    var sum: Float = 0.0
    for k in -rad...rad {
        let x = Float(k)
        let w = FoundationCompat.expf(-(x * x) / (2.0 * sigma * sigma))
        weights[k + rad] = w
        sum += w
    }
    for i in weights.indices {
        weights[i] /= sum
    }
    SyntheticFXGPU.shared.mutateViewMip0(view) { fmt, mip in
        let w = mip.width
        let h = mip.height
        guard w > 0, h > 0 else { return }
        var horiz = [SIMD4<Float>](repeating: .zero, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc = SIMD4<Float>.zero
                for k in -rad...rad {
                    let sx = x + k
                    if sx >= 0 && sx < w {
                        acc += mip.pixels[y * w + sx] * weights[k + rad]
                    }
                }
                horiz[y * w + x] = acc
            }
        }
        for y in 0..<h {
            for x in 0..<w {
                var acc = SIMD4<Float>.zero
                for k in -rad...rad {
                    let sy = y + k
                    if sy >= 0 && sy < h {
                        acc += horiz[sy * w + x] * weights[k + rad]
                    }
                }
                mip.pixels[y * w + x] = quantizeForFormat(acc, fmt)
            }
        }
    }
}

/// Composites an isolated layer (`srcView` at `srcOrigin`) onto `dstView` (at `dstOrigin`) with
/// `opacity` and optional rounded clip `[cx, cy, cw, ch]` + `clipRadius` in window device pixels.
private func compositeIsolatedLayer(
    srcView: WGPUTextureView,
    srcOrigin: [Float],
    dstView: WGPUTextureView,
    dstOrigin: [Float] = [0.0, 0.0],
    opacity: Float,
    clipRect: [Float]? = nil,
    clipRadius: Float = 0.0
) {
    guard let snap = SyntheticFXGPU.shared.viewMipSnapshot(srcView),
          let srcMip = snap.mips.first else { return }
    let sox = srcOrigin[0]
    let soy = srcOrigin[1]
    let dox = dstOrigin[0]
    let doy = dstOrigin[1]

    SyntheticFXGPU.shared.mutateViewMip0(dstView) { dstFmt, dstMip in
        for ty in 0..<dstMip.height {
            let wy = Float(ty) + 0.5 + doy
            let sy = Int((wy - soy).rounded(.down))
            guard sy >= 0, sy < srcMip.height else { continue }
            for tx in 0..<dstMip.width {
                let wx = Float(tx) + 0.5 + dox
                let sx = Int((wx - sox).rounded(.down))
                guard sx >= 0, sx < srcMip.width else { continue }
                var cov: Float = 1.0
                if let cr = clipRect {
                    let half = SIMD2<Float>(cr[2] * 0.5, cr[3] * 0.5)
                    let ctr = SIMD2<Float>(cr[0] + half.x, cr[1] + half.y)
                    let d = sdRoundedBox(SIMD2<Float>(wx - ctr.x, wy - ctr.y), half, clipRadius)
                    cov = min(max(0.5 - d, 0.0), 1.0)
                }
                let k = opacity * cov
                if k <= 0.0 { continue }
                let src = srcMip.pixels[sy * srcMip.width + sx] * k
                if src == .zero { continue }
                let idx = ty * dstMip.width + tx
                let dst = dstMip.pixels[idx]
                let out = src + dst * (1.0 - src.w)
                dstMip.pixels[idx] = quantizeForFormat(out, dstFmt)
            }
        }
    }
}

/// Copies the visible portion of `targetView` (at `origin`, size `size`) into a window-sized
/// backdrop texture of `format` and invokes `fx.blurBackdrop`, matching `rune::render::pass::split`.
private func splitAndBlurBackdrop(
    device: WGPUDevice,
    queue: WGPUQueue,
    fx: FxRenderer,
    targetView: WGPUTextureView,
    format: WGPUTextureFormat,
    origin: [Float],
    size: [UInt32],
    inLayer: Bool,
    viewport: [UInt32],
    layerIndex: Int
) {
    let vw = viewport[0]
    let vh = viewport[1]
    let bd = SyntheticFXGPU.shared.createHeadlessTexture(width: vw, height: vh, format: format)
    if inLayer {
        _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: bd.view, clear: .zero)
    }
    if let snap = SyntheticFXGPU.shared.viewMipSnapshot(targetView),
       let srcMip = snap.mips.first {
        let srcW = UInt32(srcMip.width)
        let srcH = UInt32(srcMip.height)
        let srcX = UInt32(max(-origin[0], 0.0))
        let srcY = UInt32(max(-origin[1], 0.0))
        let dstX = UInt32(max(origin[0], 0.0))
        let dstY = UInt32(max(origin[1], 0.0))
        let limW = min(size[0], srcW)
        let limH = min(size[1], srcH)
        let copyW = min(limW > srcX ? (limW - srcX) : 0, vw > dstX ? (vw - dstX) : 0)
        let copyH = min(limH > srcY ? (limH - srcY) : 0, vh > dstY ? (vh - dstY) : 0)
        if copyW > 0 && copyH > 0 {
            SyntheticFXGPU.shared.mutateViewMip0(bd.view) { _, dstMip in
                for row in 0..<Int(copyH) {
                    let sy = Int(srcY) + row
                    let dy = Int(dstY) + row
                    for col in 0..<Int(copyW) {
                        let sx = Int(srcX) + col
                        let dx = Int(dstX) + col
                        dstMip.pixels[dy * dstMip.width + dx] = srcMip.pixels[sy * srcMip.width + sx]
                    }
                }
            }
        }
    }
    let enc = SyntheticFXGPU.shared.makeEncoder()
    fx.blurBackdrop(device, queue, enc, bd.view, layerIndex)
}

private func prepareDuskSlots(
    device: WGPUDevice,
    queue: WGPUQueue,
    viewport: [UInt32],
    frameFormat: WGPUTextureFormat,
    srgb: Bool,
    slots: [SlotDesc],
    effect: (UInt32) -> Fx
) -> FxRenderer {
    let fx = FxRenderer.new(device, frameFormat, FxOptions())
    fx.setSrgbBlend(srgb)
    fx.addFormat(device, WGPUTextureFormat_RGBA16Float)

    let layers: [FxLayer] = slots.map { s in
        let k = s.scale
        let x = s.rectPx[0] / k
        let y = s.rectPx[1] / k
        let w = s.rectPx[2] / k
        let h = s.rectPx[3] / k
        let r = s.radiusPx / k
        return effect(s.mark).on(Shape.rounded(x, y, w, h, r)).at(1.0)
    }
    let placements: [FxSlot] = slots.map { s in
        FxSlot.default().scale(s.scale).clip(s.clip, s.fade)
    }
    fx.prepareWithSlots(
        device,
        queue,
        FxFrame(viewport: viewport, scale: 1.0, layers: layers, backdrop: nil, sources: []),
        placements
    )
    return fx
}

private func executeSlot(
    device: WGPUDevice,
    queue: WGPUQueue,
    fx: FxRenderer,
    slotIndex: Int,
    slots: [SlotDesc],
    targetView: WGPUTextureView,
    format: WGPUTextureFormat,
    origin: [Float],
    size: [UInt32],
    inLayer: Bool,
    viewport: [UInt32],
    seenFormats: inout [WGPUTextureFormat]
) {
    let s = slots[slotIndex]
    let edge: (Float, Float, UInt32) -> UInt32 = { v, o, lim in
        UInt32(min(max(v - o, 0.0), Float(lim)))
    }
    let x0 = edge(s.clip[0].rounded(.down), origin[0], size[0])
    let y0 = edge(s.clip[1].rounded(.down), origin[1], size[1])
    let x1 = edge(s.clip[2].rounded(.up), origin[0], size[0])
    let y1 = edge(s.clip[3].rounded(.up), origin[1], size[1])
    guard x1 > x0, y1 > y0 else { return }

    if s.backdrop {
        splitAndBlurBackdrop(
            device: device,
            queue: queue,
            fx: fx,
            targetView: targetView,
            format: format,
            origin: origin,
            size: size,
            inLayer: inLayer,
            viewport: viewport,
            layerIndex: slotIndex
        )
    }
    if !seenFormats.contains(format) {
        seenFormats.append(format)
    }
    let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: targetView, clear: nil)
    SyntheticFXGPU.shared.setPassScissor(pass, x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    fx.drawLayerIn(pass, format, origin, slotIndex)
}

// MARK: - Scene Helpers Matching `crates/rune-fx/tests/in_layer.rs`

private func snapPlain(
    srgb: Bool,
    seenFormats: inout [WGPUTextureFormat],
    effect: (UInt32) -> Fx = { _ in dusk() }
) -> (UInt32, [UInt8]) {
    let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
    let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
    let slots = [SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 0.0, scale: 1.0)]
    let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: srgb, slots: slots, effect: effect)

    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
    _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
    executeSlot(
        device: device,
        queue: queue,
        fx: fx,
        slotIndex: 0,
        slots: slots,
        targetView: target.view,
        format: format,
        origin: [0.0, 0.0],
        size: [96, 96],
        inLayer: false,
        viewport: [96, 96],
        seenFormats: &seenFormats
    )
    return (96, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
}

private func snapFadedRounded(
    srgb: Bool,
    seenFormats: inout [WGPUTextureFormat],
    scale: UInt32 = 1,
    effect: (UInt32) -> Fx = { _ in dusk() }
) -> (UInt32, [UInt8]) {
    let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
    let sc = Float(scale)
    let vw = 96 * scale
    let vh = 96 * scale
    let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
    let clipRect: [Float] = [16.0 * sc, 16.0 * sc, 80.0 * sc, 80.0 * sc]
    let fadeWords: [UInt32] = [0, 0, 0, (24.0 * sc).bitPattern]
    let slots = [
        SlotDesc(
            rectPx: [16.0 * sc, 16.0 * sc, 64.0 * sc, 64.0 * sc],
            radiusPx: 0.0,
            scale: sc,
            clip: clipRect,
            fade: fadeWords
        )
    ]
    let fx = prepareDuskSlots(device: device, queue: queue, viewport: [vw, vh], frameFormat: format, srgb: srgb, slots: slots, effect: effect)

    let layerW = 64 * scale
    let layerH = 64 * scale
    let layerOrigin: [Float] = [16.0 * sc, 16.0 * sc]
    let layerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: layerW, height: layerH, format: WGPUTextureFormat_RGBA16Float)
    _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: layerTex.view, clear: .zero)
    executeSlot(
        device: device,
        queue: queue,
        fx: fx,
        slotIndex: 0,
        slots: slots,
        targetView: layerTex.view,
        format: WGPUTextureFormat_RGBA16Float,
        origin: layerOrigin,
        size: [layerW, layerH],
        inLayer: true,
        viewport: [vw, vh],
        seenFormats: &seenFormats
    )
    paintSolidRect(
        view: layerTex.view,
        origin: layerOrigin,
        rect: [64.0 * sc, 64.0 * sc, 8.0 * sc, 8.0 * sc],
        hex: 0x0000ff,
        srgb: srgb
    )

    let target = SyntheticFXGPU.shared.createHeadlessTexture(width: vw, height: vh, format: format)
    _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
    compositeIsolatedLayer(
        srcView: layerTex.view,
        srcOrigin: layerOrigin,
        dstView: target.view,
        opacity: 0.5,
        clipRect: [16.0 * sc, 16.0 * sc, 64.0 * sc, 64.0 * sc],
        clipRadius: 24.0 * sc
    )
    return (vw, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
}

// MARK: - Test Suite

@Suite("RuneFX In-Layer & Compositor Slots")
struct InLayerIntegrationTests {
    @Test("fill_in_a_faded_rounded_layer_matches_the_plain_fill_faded")
    func fillInAFadedRoundedLayerMatchesThePlainFillFaded() {
        for srgb in [false, true] {
            var unused: [WGPUTextureFormat] = []
            let (w, plain) = snapPlain(srgb: srgb, seenFormats: &unused)
            var formats: [WGPUTextureFormat] = []
            let (_, layered) = snapFadedRounded(srgb: srgb, seenFormats: &formats)
            let bg: Float = 32.0 / 255.0
            for (x, y): (UInt32, UInt32) in [(40, 40), (60, 30)] {
                let fill = px(plain, w, x, y)
                let want: [UInt8] = (0..<3).map { c in
                    let f = Float(fill[c]) / 255.0
                    let v = srgb
                        ? (0.5 * f + 0.5 * bg)
                        : RuneMotion.srgbEncode(0.5 * RuneMotion.srgbDecode(f) + 0.5 * RuneMotion.srgbDecode(bg))
                    return UInt8((v * 255.0).rounded())
                }
                let got = px(layered, w, x, y)
                for ch in 0..<3 {
                    #expect(abs(Int(got[ch]) - Int(want[ch])) <= 4, "srgb \(srgb) at (\(x), \(y)): got \(got), want \(want)")
                }
            }
            let corner = px(layered, w, 17, 17)
            #expect(corner.allSatisfy { abs(Int($0) - 32) <= 2 }, "corner is clipped away: \(corner)")
            #expect(formats == [WGPUTextureFormat_RGBA16Float])
        }
    }

    @Test("fills_match_across_blend_modes_when_opaque")
    func fillsMatchAcrossBlendModesWhenOpaque() {
        var f0: [WGPUTextureFormat] = []
        var f1: [WGPUTextureFormat] = []
        let (_, linear) = snapPlain(srgb: false, seenFormats: &f0)
        let (_, gamma) = snapPlain(srgb: true, seenFormats: &f1)
        var worst = 0
        for idx in 0..<linear.count {
            worst = max(worst, abs(Int(linear[idx]) - Int(gamma[idx])))
        }
        #expect(worst <= 3, "modes differ by \(worst)")
    }

    @Test("faint_occlusion_keeps_the_glow_lit_in_gamma_blend")
    func faintOcclusionKeepsTheGlowLitInGammaBlend() {
        let renderGlowOnBlack: (Float) -> (UInt32, [UInt8]) = { occ in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let format = WGPUTextureFormat_RGBA8Unorm
            let slots = [SlotDesc(rectPx: [32.0, 32.0, 32.0, 32.0], radiusPx: 0.0, scale: 1.0)]
            let fx = prepareDuskSlots(
                device: device,
                queue: queue,
                viewport: [96, 96],
                frameFormat: format,
                srgb: true,
                slots: slots,
                effect: { _ in glow(occ) }
            )
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: SIMD4<Float>(0.0, 0.0, 0.0, 1.0))
            var seen: [WGPUTextureFormat] = []
            executeSlot(
                device: device,
                queue: queue,
                fx: fx,
                slotIndex: 0,
                slots: slots,
                targetView: target.view,
                format: format,
                origin: [0.0, 0.0],
                size: [96, 96],
                inLayer: false,
                viewport: [96, 96],
                seenFormats: &seen
            )
            return (96, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        let (w, clear) = renderGlowOnBlack(0.0)
        let (_, faint) = renderGlowOnBlack(0.002)
        var lit: UInt32 = 0
        for (x, y): (UInt32, UInt32) in [(28, 48), (24, 48), (48, 27), (48, 22), (68, 48), (28, 28)] {
            let a = px(clear, w, x, y)
            let b = px(faint, w, x, y)
            if a.contains(where: { $0 > 24 }) {
                lit += 1
            }
            for ch in 0..<3 {
                #expect(abs(Int(a[ch]) - Int(b[ch])) <= 6, "(\(x), \(y)): clear \(a), faint \(b)")
            }
        }
        #expect(lit >= 3, "the glow should light the samples")
    }

    @Test("grain_is_symmetric_in_both_blend_modes")
    func grainIsSymmetricInBothBlendModes() {
        let renderGrainOnGrey: (Bool, Float) -> (UInt32, [UInt8]) = { srgb, amount in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let slots = [SlotDesc(rectPx: [0.0, 0.0, 96.0, 96.0], radiusPx: 0.0, scale: 1.0)]
            let fx = prepareDuskSlots(
                device: device,
                queue: queue,
                viewport: [96, 96],
                frameFormat: format,
                srgb: srgb,
                slots: slots,
                effect: { _ in Fx.grain(GrainParams(amount: amount)) }
            )
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x808080, srgb: srgb))
            var seen: [WGPUTextureFormat] = []
            executeSlot(
                device: device,
                queue: queue,
                fx: fx,
                slotIndex: 0,
                slots: slots,
                targetView: target.view,
                format: format,
                origin: [0.0, 0.0],
                size: [96, 96],
                inLayer: false,
                viewport: [96, 96],
                seenFormats: &seen
            )
            return (96, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        for srgb in [false, true] {
            let (w, img) = renderGrainOnGrey(srgb, 0.06)
            let (_, base) = renderGrainOnGrey(srgb, 0.0)
            let space: (UInt8) -> Double = { v in
                srgb ? (Double(v) / 255.0) : Double(RuneMotion.srgbDecode(Float(v) / 255.0))
            }
            var up = 0.0
            var down = 0.0
            var raw = 0.0
            var n = 0.0
            for y: UInt32 in 0..<96 {
                for x: UInt32 in 0..<min(w, 96) {
                    let v = px(img, w, x, y)[0]
                    let b = px(base, w, x, y)[0]
                    let vs = space(v)
                    let bs = space(b)
                    if vs > bs {
                        up += (vs - bs) / (1.0 - bs)
                    } else {
                        down += (bs - vs) / bs
                    }
                    raw += Double(v) - Double(b)
                    n += 1.0
                }
            }
            up /= n
            down /= n
            raw /= n
            #expect(up > 0.005 && down > 0.005, "srgb \(srgb): grain should show, up \(up) down \(down)")
            #expect(abs(up - down) <= 0.1 * (up + down) / 2.0, "srgb \(srgb): toward white \(up), toward black \(down)")
            if srgb {
                #expect(abs(raw) <= 1.0, "srgb \(srgb): mean shifts by \(raw)/255")
            }
        }
    }

    @Test("slot_scale_scales_effect_lengths_and_radii_without_bleed")
    func slotScaleScalesEffectLengthsAndRadiiWithoutBleed() {
        let renderRing: (SlotDesc, Float) -> (UInt32, [UInt8]) = { slot, border in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let format = WGPUTextureFormat_RGBA8UnormSrgb
            let slots = [slot]
            let fx = prepareDuskSlots(
                device: device,
                queue: queue,
                viewport: [96, 96],
                frameFormat: format,
                srgb: false,
                slots: slots,
                effect: { _ in Fx.fill(FillParams.from(MeshGradientParams.dusk()).border(border)) }
            )
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: false))
            var seen: [WGPUTextureFormat] = []
            executeSlot(
                device: device,
                queue: queue,
                fx: fx,
                slotIndex: 0,
                slots: slots,
                targetView: target.view,
                format: format,
                origin: [0.0, 0.0],
                size: [96, 96],
                inLayer: false,
                viewport: [96, 96],
                seenFormats: &seen
            )
            return (96, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        // 32x32 element at (32, 32) scaled 2x around its centre sits at [16, 16, 64, 64] px with radius 16 px and scale 2.0.
        let zoomedSlot = SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 16.0, scale: 2.0)
        let directSlot = SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 16.0, scale: 1.0)
        let (w, zoomed) = renderRing(zoomedSlot, 6.0)
        let (_, direct) = renderRing(directSlot, 12.0)

        #expect(px(zoomed, w, 22, 48).contains { $0 > 45 }, "ring is lit at 12px width")
        #expect(px(zoomed, w, 48, 48).allSatisfy { abs(Int($0) - 32) <= 2 }, "centre is hollow")
        var worst = 0
        for idx in 0..<zoomed.count {
            worst = max(worst, abs(Int(zoomed[idx]) - Int(direct[idx])))
        }
        #expect(worst <= 3, "zoomed slot and 2x direct ring differ by \(worst)")
    }

    @Test("fill_under_a_rounded_scroll_container_clips_without_a_layer")
    func fillUnderARoundedScrollContainerClipsWithoutALayer() {
        for srgb in [false, true] {
            var unused: [WGPUTextureFormat] = []
            let (w, plainImg) = snapPlain(srgb: srgb, seenFormats: &unused)

            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let fadeBottomBits = UInt32(fxFloatToF16Bits(16.0)) << 16
            // Scroll content 64x96 inside 64x64 viewport at scrollY=0: bottom edge has remaining overflow, so offset.w = 0.
            let slots = [
                SlotDesc(
                    rectPx: [16.0, 16.0, 64.0, 64.0],
                    radiusPx: 0.0,
                    scale: 1.0,
                    clip: [16.0, 16.0, 80.0, 80.0],
                    fade: [0, fadeBottomBits, 0, Float(24.0).bitPattern]
                )
            ]
            let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: srgb, slots: slots, effect: { _ in dusk() })
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
            var seen: [WGPUTextureFormat] = []
            executeSlot(
                device: device,
                queue: queue,
                fx: fx,
                slotIndex: 0,
                slots: slots,
                targetView: target.view,
                format: format,
                origin: [0.0, 0.0],
                size: [96, 96],
                inLayer: false,
                viewport: [96, 96],
                seenFormats: &seen
            )
            let clipped = SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)

            #expect(!seen.contains(WGPUTextureFormat_RGBA16Float), "must not allocate an isolated layer: \(seen)")
            let corner = px(clipped, w, 17, 17)
            #expect(corner.allSatisfy { abs(Int($0) - 32) <= 2 }, "srgb \(srgb) corner is clipped away: \(corner)")
            for (x, y): (UInt32, UInt32) in [(48, 17), (48, 48)] {
                let got = px(clipped, w, x, y)
                let want = px(plainImg, w, x, y)
                for ch in 0..<3 {
                    #expect(abs(Int(got[ch]) - Int(want[ch])) <= 2, "srgb \(srgb) at (\(x), \(y)): got \(got), want \(want)")
                }
            }
            let midFade = px(clipped, w, 48, 72)
            let full = px(plainImg, w, 48, 72)
            let fadedEnough = (0..<3).contains { ch in Int(midFade[ch]) < max(Int(full[ch]) - 15, 0) }
            #expect(fadedEnough, "srgb \(srgb) soft edge fades toward background: \(midFade) vs \(full)")
            #expect(midFade.contains { $0 > 40 }, "srgb \(srgb) soft edge is not hard-cut at y = 72: \(midFade)")
        }
    }

    @Test("backdrop_slots_blur_background_and_stack_glass_over_glass_in_painter_order")
    func backdropSlotsBlurBackgroundAndStackGlassOverGlassInPainterOrder() {
        let format = WGPUTextureFormat_RGBA8UnormSrgb
        let w: UInt32 = 96

        // Scene 1: single glass over cyan left half.
        let one: [UInt8] = {
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let slots = [SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 1, backdrop: true)]
            let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: false, slots: slots, effect: frostedGlassFx)
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: false))
            paintSolidRect(view: target.view, rect: [0.0, 0.0, 48.0, 96.0], hex: 0x00e5ff, srgb: false)
            var seen: [WGPUTextureFormat] = []
            executeSlot(device: device, queue: queue, fx: fx, slotIndex: 0, slots: slots, targetView: target.view, format: format, origin: [0.0, 0.0], size: [96, 96], inLayer: false, viewport: [96, 96], seenFormats: &seen)
            return SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)
        }()

        let pOne = px(one, w, 54, 48)
        #expect(pOne[1] > 60 && pOne[2] > 70, "glass 1 blurs cyan across the x=48 edge: \(pOne)")

        // Scene 2: stacked glass 1 -> red bar -> glass 2 -> sharp green badge.
        let stacked: [UInt8] = {
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let slots = [
                SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 1, backdrop: true),
                SlotDesc(rectPx: [24.0, 24.0, 56.0, 48.0], radiusPx: 0.0, scale: 1.0, mark: 2, backdrop: true),
            ]
            let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: false, slots: slots, effect: frostedGlassFx)
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: false))
            paintSolidRect(view: target.view, rect: [0.0, 0.0, 48.0, 96.0], hex: 0x00e5ff, srgb: false)
            var seen: [WGPUTextureFormat] = []
            executeSlot(device: device, queue: queue, fx: fx, slotIndex: 0, slots: slots, targetView: target.view, format: format, origin: [0.0, 0.0], size: [96, 96], inLayer: false, viewport: [96, 96], seenFormats: &seen)
            paintSolidRect(view: target.view, rect: [40.0, 32.0, 16.0, 32.0], hex: 0xff2040, srgb: false)
            executeSlot(device: device, queue: queue, fx: fx, slotIndex: 1, slots: slots, targetView: target.view, format: format, origin: [0.0, 0.0], size: [96, 96], inLayer: false, viewport: [96, 96], seenFormats: &seen)
            paintSolidRect(view: target.view, rect: [68.0, 60.0, 10.0, 10.0], hex: 0x00ff00, srgb: false)
            return SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)
        }()

        let pTwo = px(stacked, w, 60, 48)
        let pOne60 = px(one, w, 60, 48)
        #expect(Int(pTwo[0]) > Int(pOne60[0]) + 15, "glass 2 sees the intermediate red bar and glass 1: \(pTwo) vs \(pOne60)")
        let badge = px(stacked, w, 72, 64)
        #expect(badge[0] < 10 && badge[1] > 245 && badge[2] < 10, "later content stays sharp on top of glass 2: \(badge)")
    }

    @Test("backdrop_origin_tracks_fractional_scale_scroll_live_offset_and_nested_layers")
    func backdropOriginTracksFractionalScaleScrollLiveOffsetAndNestedLayers() {
        let renderMovedNested: (Bool, Bool) -> (UInt32, [UInt8]) = { withSlot, srgb in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let vw: UInt32 = 192
            let vh: UInt32 = 192
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb

            // Outer scroll container: (8.25, 8.75) size 72x72 scaled 1.125 around its centre at window scale 2x => k = 2.25 px/pt.
            // Scaled 72x72 -> 81x81 pt centred on (44.25, 44.75) => [3.75, 4.25] pt => [7.5, 8.5] px, size 162x162 px.
            let k: Float = 2.25
            let outerClip: [Float] = [7.5, 8.5, 169.5, 170.5]
            let outerOrigin: [Float] = [7.0, 8.0]
            let outerSize: [UInt32] = [163, 163]

            // Inner card inside stick-bottom scroll (68 - 68 = 0) with live_offset [-4.25, -3.75] at k = 2.25:
            // card rect in window px: [7.5 - 4.25 * 2.25, 8.5 - 3.75 * 2.25, 162, 162] = [-2.0625, 0.0625, 162, 162].
            let cardX: Float = 7.5 - 4.25 * k
            let cardY: Float = 8.5 - 3.75 * k
            let cardW: Float = 72.0 * k
            let cardH: Float = 72.0 * k
            let innerOrigin: [Float] = [max(cardX, outerClip[0]).rounded(.down), max(cardY, outerClip[1]).rounded(.down)]
            let innerRight = min(cardX + cardW, outerClip[2]).rounded(.up)
            let innerBottom = min(cardY + cardH, outerClip[3]).rounded(.up)
            let innerSize: [UInt32] = [UInt32(innerRight - innerOrigin[0]), UInt32(innerBottom - innerOrigin[1])]

            let slots: [SlotDesc] = withSlot
                ? [SlotDesc(rectPx: [cardX, cardY, cardW, cardH], radiusPx: 0.0, scale: k, clip: outerClip, backdrop: true)]
                : []
            let fx = prepareDuskSlots(
                device: device,
                queue: queue,
                viewport: [vw, vh],
                frameFormat: format,
                srgb: srgb,
                slots: slots,
                effect: { _ in Fx.distort(DistortParams.chromaSplit([1e-6, 0.0])) }
            )

            let innerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: innerSize[0], height: innerSize[1], format: WGPUTextureFormat_RGBA16Float)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: innerTex.view, clear: .zero)
            paintSolidRect(view: innerTex.view, origin: innerOrigin, rect: [cardX, cardY, cardW, cardH], hex: 0x804020, srgb: srgb)
            paintSolidRect(view: innerTex.view, origin: innerOrigin, rect: [cardX + 24.0 * k, cardY, 8.0 * k, cardH], hex: 0x00e5ff, srgb: srgb)
            if withSlot {
                var seen: [WGPUTextureFormat] = []
                executeSlot(
                    device: device,
                    queue: queue,
                    fx: fx,
                    slotIndex: 0,
                    slots: slots,
                    targetView: innerTex.view,
                    format: WGPUTextureFormat_RGBA16Float,
                    origin: innerOrigin,
                    size: innerSize,
                    inLayer: true,
                    viewport: [vw, vh],
                    seenFormats: &seen
                )
            }

            let outerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: outerSize[0], height: outerSize[1], format: WGPUTextureFormat_RGBA16Float)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: outerTex.view, clear: .zero)
            compositeIsolatedLayer(
                srcView: innerTex.view,
                srcOrigin: innerOrigin,
                dstView: outerTex.view,
                dstOrigin: outerOrigin,
                opacity: 0.6,
                clipRect: [outerClip[0], outerClip[1], outerClip[2] - outerClip[0], outerClip[3] - outerClip[1]]
            )

            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: vw, height: vh, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
            compositeIsolatedLayer(
                srcView: outerTex.view,
                srcOrigin: outerOrigin,
                dstView: target.view,
                opacity: 0.8
            )
            return (vw, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        for srgb in [false, true] {
            let (w, base) = renderMovedNested(false, srgb)
            let (_, slot) = renderMovedNested(true, srgb)
            for y: UInt32 in [40, 72, 104] {
                for x: UInt32 in [24, 48, 56, 64, 88, 120] {
                    let got = px(slot, w, x, y)
                    let want = px(base, w, x, y)
                    for ch in 0..<3 {
                        #expect(abs(Int(got[ch]) - Int(want[ch])) <= 3, "srgb=\(srgb) (\(x),\(y)): \(got) != \(want)")
                    }
                }
            }
        }
    }

    @Test("negative_layer_origins_copy_the_visible_region_at_all_window_edges")
    func negativeLayerOriginsCopyTheVisibleRegionAtAllWindowEdges() {
        let renderEdgeScene: (Bool, Bool) -> (UInt32, [UInt8]) = { withSlot, srgb in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let vw: UInt32 = 192
            let vh: UInt32 = 192
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let k: Float = 2.25
            // Card (-8.25, -9.75) size 112x112 scaled 1.125 around centre (47.75, 46.25) at 2x => 252x252 px from [-30.5, -33.5].
            let cardX: Float = (47.75 - 56.0 * 1.125) * 2.0
            let cardY: Float = (46.25 - 56.0 * 1.125) * 2.0
            let cardW: Float = 112.0 * k
            let cardH: Float = 112.0 * k
            // Layer has blur(3.0) at 2x => sigma = 6 px, support = 18 px => negative origin [-18, -18], size 228x228.
            let layerOrigin: [Float] = [-18.0, -18.0]
            let layerSize: [UInt32] = [228, 228]

            let slots: [SlotDesc] = withSlot
                ? [SlotDesc(rectPx: [cardX, cardY, cardW, cardH], radiusPx: 0.0, scale: k, backdrop: true)]
                : []
            let fx = prepareDuskSlots(
                device: device,
                queue: queue,
                viewport: [vw, vh],
                frameFormat: format,
                srgb: srgb,
                slots: slots,
                effect: { _ in Fx.distort(DistortParams.chromaSplit([1e-6, 0.0])) }
            )

            let layerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: layerSize[0], height: layerSize[1], format: WGPUTextureFormat_RGBA16Float)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: layerTex.view, clear: .zero)
            paintSolidRect(view: layerTex.view, origin: layerOrigin, rect: [cardX, cardY, cardW, cardH], hex: 0x804020, srgb: srgb)
            paintSolidRect(view: layerTex.view, origin: layerOrigin, rect: [cardX + 40.0 * k, cardY, 8.0 * k, cardH], hex: 0x00e5ff, srgb: srgb)
            if withSlot {
                var seen: [WGPUTextureFormat] = []
                executeSlot(
                    device: device,
                    queue: queue,
                    fx: fx,
                    slotIndex: 0,
                    slots: slots,
                    targetView: layerTex.view,
                    format: WGPUTextureFormat_RGBA16Float,
                    origin: layerOrigin,
                    size: layerSize,
                    inLayer: true,
                    viewport: [vw, vh],
                    seenFormats: &seen
                )
            }
            blurLayerInPlace(view: layerTex.view, sigma: 6.0)

            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: vw, height: vh, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
            compositeIsolatedLayer(
                srcView: layerTex.view,
                srcOrigin: layerOrigin,
                dstView: target.view,
                opacity: 0.6
            )
            return (vw, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        for srgb in [false, true] {
            let (w, base) = renderEdgeScene(false, srgb)
            let (_, slot) = renderEdgeScene(true, srgb)
            for y: UInt32 in [0, 1, 4, 64, 187, 190, 191] {
                for x: UInt32 in [0, 1, 4, 64, 187, 190, 191] {
                    let got = px(slot, w, x, y)
                    let want = px(base, w, x, y)
                    for ch in 0..<3 {
                        #expect(abs(Int(got[ch]) - Int(want[ch])) <= 3, "srgb=\(srgb) (\(x),\(y)): \(got) != \(want)")
                    }
                }
            }
        }
    }

    @Test("backdrop_slot_in_an_isolated_layer_reads_and_blurs_that_layers_target")
    func backdropSlotInAnIsolatedLayerReadsAndBlursThatLayersTarget() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let format = WGPUTextureFormat_RGBA8UnormSrgb
        let slots = [SlotDesc(rectPx: [16.0, 16.0, 64.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 1, backdrop: true)]
        let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: false, slots: slots, effect: frostedGlassFx)

        let layerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: 64, height: 64, format: WGPUTextureFormat_RGBA16Float)
        _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: layerTex.view, clear: .zero)
        paintSolidRect(view: layerTex.view, origin: [16.0, 16.0], rect: [16.0, 16.0, 32.0, 64.0], hex: 0x00e5ff, srgb: false)
        var seen: [WGPUTextureFormat] = []
        executeSlot(
            device: device,
            queue: queue,
            fx: fx,
            slotIndex: 0,
            slots: slots,
            targetView: layerTex.view,
            format: WGPUTextureFormat_RGBA16Float,
            origin: [16.0, 16.0],
            size: [64, 64],
            inLayer: true,
            viewport: [96, 96],
            seenFormats: &seen
        )

        let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
        _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: false))
        compositeIsolatedLayer(srcView: layerTex.view, srcOrigin: [16.0, 16.0], dstView: target.view, opacity: 0.5)
        let img = SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)

        #expect(seen.contains(WGPUTextureFormat_RGBA16Float), "isolated layer uses Rgba16Float: \(seen)")
        let blurredRight = px(img, 96, 52, 48)
        #expect(blurredRight[1] > 45 && blurredRight[2] > 50, "layer backdrop slot blurs the layer's stripe: \(blurredRight)")
        let fadedLeft = px(img, 96, 24, 48)
        #expect(fadedLeft[2] > 100 && fadedLeft[2] < 220, "isolated layer composites at 0.5 opacity: \(fadedLeft)")
    }

    @Test("srgb_blend_decodes_backdrop_without_double_encoding_on_frame_and_layer_targets")
    func srgbBlendDecodesBackdropWithoutDoubleEncodingOnFrameAndLayerTargets() {
        let renderMidtoneScene: (Bool) -> (UInt32, [UInt8]) = { srgb in
            let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let slots = [
                SlotDesc(rectPx: [16.0, 16.0, 20.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 1, backdrop: true),
                SlotDesc(rectPx: [36.0, 16.0, 20.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 2, backdrop: true),
                SlotDesc(rectPx: [56.0, 16.0, 24.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 3, backdrop: true),
            ]
            let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: srgb, slots: slots, effect: identityGlassAndDitherFx)
            let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: srgb))
            paintSolidRect(view: target.view, rect: [8.0, 8.0, 80.0, 80.0], hex: 0x804020, srgb: srgb)
            var seen: [WGPUTextureFormat] = []
            for k in 0..<3 {
                executeSlot(device: device, queue: queue, fx: fx, slotIndex: k, slots: slots, targetView: target.view, format: format, origin: [0.0, 0.0], size: [96, 96], inLayer: false, viewport: [96, 96], seenFormats: &seen)
            }
            return (96, SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture))
        }

        let (w, lin) = renderMidtoneScene(false)
        let (_, gam) = renderMidtoneScene(true)
        let pClearLin = px(lin, w, 24, 48)
        let pClearGam = px(gam, w, 24, 48)
        #expect(abs(Int(pClearLin[0]) - 128) <= 3 && abs(Int(pClearLin[1]) - 64) <= 3 && abs(Int(pClearLin[2]) - 32) <= 3, "linear clear glass preserves #804020: \(pClearLin)")
        #expect(abs(Int(pClearGam[0]) - 128) <= 3 && abs(Int(pClearGam[1]) - 64) <= 3 && abs(Int(pClearGam[2]) - 32) <= 3, "srgb_blend clear glass is not double-encoded: \(pClearGam)")

        let pFrostLin = px(lin, w, 46, 48)
        let pFrostGam = px(gam, w, 46, 48)
        for c in 0..<3 {
            #expect(abs(Int(pFrostLin[c]) - Int(pFrostGam[c])) <= 3, "frosted glass matches across blend modes: lin \(pFrostLin) vs gam \(pFrostGam)")
        }

        var ditherDiff = 0
        for y: UInt32 in 24..<72 {
            for x: UInt32 in 60..<76 {
                let a = px(lin, w, x, y)
                let b = px(gam, w, x, y)
                let sum = abs(Int(a[0]) - Int(b[0])) + abs(Int(a[1]) - Int(b[1])) + abs(Int(a[2]) - Int(b[2]))
                ditherDiff = max(ditherDiff, sum)
            }
        }
        #expect(ditherDiff <= 6, "backdrop dither tone matches between linear and srgb_blend (max channel sum diff \(ditherDiff))")

        // Isolated Rgba16Float layer in srgb_blend mode.
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let format = WGPUTextureFormat_RGBA8Unorm
        let slots = [
            SlotDesc(rectPx: [16.0, 16.0, 20.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 1, backdrop: true),
            SlotDesc(rectPx: [36.0, 16.0, 20.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 2, backdrop: true),
            SlotDesc(rectPx: [56.0, 16.0, 24.0, 64.0], radiusPx: 0.0, scale: 1.0, mark: 3, backdrop: true),
        ]
        let fx = prepareDuskSlots(device: device, queue: queue, viewport: [96, 96], frameFormat: format, srgb: true, slots: slots, effect: identityGlassAndDitherFx)
        let layerTex = SyntheticFXGPU.shared.createHeadlessTexture(width: 80, height: 80, format: WGPUTextureFormat_RGBA16Float)
        _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: layerTex.view, clear: .zero)
        paintSolidRect(view: layerTex.view, origin: [8.0, 8.0], rect: [8.0, 8.0, 80.0, 80.0], hex: 0x804020, srgb: true)
        var seen: [WGPUTextureFormat] = []
        for k in 0..<3 {
            executeSlot(device: device, queue: queue, fx: fx, slotIndex: k, slots: slots, targetView: layerTex.view, format: WGPUTextureFormat_RGBA16Float, origin: [8.0, 8.0], size: [80, 80], inLayer: true, viewport: [96, 96], seenFormats: &seen)
        }
        let target = SyntheticFXGPU.shared.createHeadlessTexture(width: 96, height: 96, format: format)
        _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: hexWorkingColor(0x202020, srgb: true))
        compositeIsolatedLayer(srcView: layerTex.view, srcOrigin: [8.0, 8.0], dstView: target.view, opacity: 0.85)
        let layerGam = SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)

        let outsideSlot = px(layerGam, 96, 12, 12)
        let insideClearGlass = px(layerGam, 96, 24, 48)
        let insideFrostGlass = px(layerGam, 96, 46, 48)
        for c in 0..<3 {
            #expect(abs(Int(insideClearGlass[c]) - Int(outsideSlot[c])) <= 3, "Rgba16Float layer clear glass in srgb_blend matches surrounding layer fill (\(insideClearGlass) vs \(outsideSlot))")
        }
        #expect(insideFrostGlass[0] < 135 && insideFrostGlass[1] < 70, "Rgba16Float layer frosted glass is not washed out: \(insideFrostGlass)")
    }

    @Test("plastic_matches_across_blend_modes")
    func plasticMatchesAcrossBlendModes() {
        let makePlastic: (Float) -> Fx = { roughness in
            var p = PlasticParams.glossy()
            p.color = rgb(0xffd60a)
            p.roughness = roughness
            return Fx.fill(p)
        }
        for roughness: Float in [0.05, 0.45, 1.0] {
            var f0: [WGPUTextureFormat] = []
            var f1: [WGPUTextureFormat] = []
            let (w, linear) = snapPlain(srgb: false, seenFormats: &f0, effect: { _ in makePlastic(roughness) })
            let (_, gamma) = snapPlain(srgb: true, seenFormats: &f1, effect: { _ in makePlastic(roughness) })
            var worst = 0
            for idx in 0..<linear.count {
                worst = max(worst, abs(Int(linear[idx]) - Int(gamma[idx])))
            }
            #expect(worst <= 3, "roughness \(roughness): modes differ by \(worst)")

            for srgb in [false, true] {
                let opaque = srgb ? gamma : linear
                var seen: [WGPUTextureFormat] = []
                let (_, faded) = snapFadedRounded(srgb: srgb, seenFormats: &seen, effect: { _ in makePlastic(roughness) })
                let bg: Float = 32.0 / 255.0
                for (x, y): (UInt32, UInt32) in [(40, 40), (30, 22), (60, 30), (48, 66)] {
                    let fill = px(opaque, w, x, y)
                    let want: [UInt8] = (0..<3).map { c in
                        let f = Float(fill[c]) / 255.0
                        let v = srgb
                            ? (0.5 * f + 0.5 * bg)
                            : RuneMotion.srgbEncode(0.5 * RuneMotion.srgbDecode(f) + 0.5 * RuneMotion.srgbDecode(bg))
                        return UInt8((v * 255.0).rounded())
                    }
                    let got = px(faded, w, x, y)
                    for ch in 0..<3 {
                        #expect(abs(Int(got[ch]) - Int(want[ch])) <= 4, "roughness \(roughness) srgb \(srgb) at (\(x), \(y)): got \(got), want \(want)")
                    }
                }
            }
        }
    }

    @Test("fx_blend_modes_over_cream_paper_and_fallback_without_backdrop")
    func fxBlendModesOverCreamPaperAndFallbackWithoutBackdrop() {
        let (device, queue) = SyntheticFXGPU.shared.makeHeadlessContext()
        let w: UInt32 = 96
        let h: UInt32 = 96
        let warmGlow = {
            Fx.glow(GlowParams(
                color: rgb(0xc85a14),
                core: rgb(0xe88c28),
                radius: 10.0,
                intensity: 1.15,
                inner: 0.8,
                hot: 0.35,
                reach: 2.5
            ))
            .on(Shape.rounded(32.0, 32.0, 32.0, 32.0, 10.0))
            .at(0.5)
        }

        for srgb in [false, true] {
            let format = srgb ? WGPUTextureFormat_RGBA8Unorm : WGPUTextureFormat_RGBA8UnormSrgb
            let fx = FxRenderer.new(device, format, FxOptions())
            fx.setSrgbBlend(srgb)

            let creamSrgb: [Float] = [Float(0xfa) / 255.0, Float(0xf7) / 255.0, Float(0xf2) / 255.0]
            let creamLin = creamSrgb.map { RuneMotion.srgbDecode($0) }
            let clear = srgb
                ? SIMD4<Float>(creamSrgb[0], creamSrgb[1], creamSrgb[2], 1.0)
                : SIMD4<Float>(creamLin[0], creamLin[1], creamLin[2], 1.0)

            let backdrop = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: format)
            _ = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: backdrop.view, clear: clear)

            let renderMode: (FxBlend, Bool) -> [UInt8] = { mode, withBackdrop in
                let target = SyntheticFXGPU.shared.createHeadlessTexture(width: w, height: h, format: format)
                let layers = [warmGlow()]
                let slots = [FxSlot.default().blend(mode).backdropSrgb(srgb)]
                let stats = fx.prepareWithSlots(
                    device,
                    queue,
                    FxFrame(
                        viewport: [w, h],
                        scale: 1.0,
                        layers: layers,
                        backdrop: withBackdrop ? backdrop.view : nil,
                        sources: []
                    ),
                    slots
                )
                #expect(stats.needsBackdrop == mode.needsBackdrop())
                let pass = SyntheticFXGPU.shared.beginHeadlessRenderPass(view: target.view, clear: clear)
                fx.drawLayer(pass, 0)
                return SyntheticFXGPU.shared.readHeadlessTextureRGBA8(target.texture)
            }

            let normal = renderMode(.normal, true)
            let multiply = renderMode(.multiply, true)
            let screen = renderMode(.screen, true)
            let overlay = renderMode(.overlay, true)
            let softLight = renderMode(.softLight, true)

            for out in [normal, multiply, screen, overlay, softLight] {
                let corner = px(out, w, 2, 2)
                #expect(
                    abs(Int(corner[0]) - 0xfa) <= 1 && abs(Int(corner[1]) - 0xf7) <= 1 && abs(Int(corner[2]) - 0xf2) <= 1,
                    "srgb=\(srgb) untouched cream paper at (2,2): \(corner)"
                )
            }

            let rimNorm = px(normal, w, 32, 48)
            let rimMul = px(multiply, w, 32, 48)
            let rimScr = px(screen, w, 32, 48)
            let rimOvl = px(overlay, w, 32, 48)
            let rimSoft = px(softLight, w, 32, 48)
            #expect(
                Int(rimMul[2]) + 40 < Int(rimNorm[2])
                    && Int(rimMul[1]) + 20 < Int(rimNorm[1])
                    && rimMul[0] > rimMul[1]
                    && rimMul[1] > rimMul[2],
                "srgb=\(srgb) Multiply deepens cream paper into warm amber (\(rimMul)) vs Normal (\(rimNorm))"
            )
            #expect(
                rimScr[0] >= 0xfa && rimScr[1] >= rimMul[1] && rimScr[2] >= rimMul[2],
                "srgb=\(srgb) Screen lifts above Multiply: screen=\(rimScr), mul=\(rimMul)"
            )
            #expect(rimOvl != rimNorm, "srgb=\(srgb) Overlay differs from Normal on cream paper")
            #expect(rimSoft != rimNorm, "srgb=\(srgb) SoftLight differs from Normal on cream paper")
            #expect(rimOvl != rimSoft, "srgb=\(srgb) Overlay and SoftLight are distinct")

            let overlayNoBd = renderMode(.overlay, false)
            let softNoBd = renderMode(.softLight, false)
            let multiplyNoBd = renderMode(.multiply, false)
            #expect(multiplyNoBd == normal, "srgb=\(srgb) Multiply without backdrop falls back to Normal")
            #expect(overlayNoBd == normal, "srgb=\(srgb) Overlay without backdrop falls back to Normal")
            #expect(softNoBd == normal, "srgb=\(srgb) SoftLight without backdrop falls back to Normal")
        }
    }

    @Test("write_demo_still", .disabled("Manual demo PNG writer matching upstream #[ignore] test"))
    func writeDemoStill() {
        var f0: [WGPUTextureFormat] = []
        var f1: [WGPUTextureFormat] = []
        let (w, linear) = snapFadedRounded(srgb: false, seenFormats: &f0, scale: 3)
        let (_, gamma) = snapFadedRounded(srgb: true, seenFormats: &f1, scale: 3)
        #expect(w == 288 && linear.count == gamma.count)
    }
}
