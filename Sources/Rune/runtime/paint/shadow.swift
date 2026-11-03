// Ported from: crates/rune/src/runtime/paint/shadow.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Painter-stream instances for outer (`KIND_SHADOW`) and inset (`KIND_INSET`) box shadows (`El.boxShadow`).

struct ShadowCaster {
    var rect: [Float]
    var radii: [Float]
    var shape: [Float]
    var kPx: Float
    var scale: Float
    var opacity: Float
    var srgb: Bool
    var clip: [Float]
    var fade: [Float]
    var hole: Float?
    var opaque: Bool
}

func pushOuterShadow(_ out: inout [Instance], _ sh: Shadow, _ c: Color, _ cast: ShadowCaster) {
    let x = cast.rect[0], y = cast.rect[1], w = cast.rect[2], h = cast.rect[3]
    let sp = sh.spread * cast.kPx
    let rect: [Float] = [x + sh.x * cast.kPx - sp, y + sh.y * cast.kPx - sp, w + 2.0 * sp, h + 2.0 * sp]
    let sradii = cast.radii.map { v in v > 0.0 ? max(v + sp, 0.0) : 0.0 }
    let clip = cast.clip
    let fade = packFade(cast.fade, clip, clip)
    let fill = premul(c, cast.opacity, cast.srgb)
    let ring = (sh.x == 0.0 && sh.y == 0.0)

    if sh.blur <= 0.0 && (ring || cast.hole == nil) {
        if ring && sp <= 0.0 {
            return
        }
        out.append(
            Instance(
                rect: rect,
                radii: sradii,
                fill: ring ? [0.0, 0.0, 0.0, 0.0] : fill,
                border: ring ? fill : [0.0, 0.0, 0.0, 0.0],
                params: [ring ? sp : 0.0, KIND_RECT, 0.0, 1.0],
                uv: [0.0, 0.0, 0.0, 0.0],
                clip: clip,
                fade: fade
            )
        )
        return
    }

    let radii: [Float]
    let uv: [Float]
    if let hole = cast.hole {
        radii = [sradii[0], sradii[1], sradii[2], hole]
        uv = [x - rect[0], y - rect[1], w, h]
    } else {
        radii = sradii
        uv = [0.0, 0.0, 0.0, 0.0]
    }

    let inst = Instance(
        rect: rect,
        radii: radii,
        fill: fill,
        border: [0.0, 0.0, 0.0, 0.0],
        params: [0.0, KIND_SHADOW, max(sh.blur * cast.scale * 0.5, 0.5), 1.0],
        uv: uv,
        clip: clip,
        fade: fade
    )
    if cast.opaque {
        pushShadowBands(&out, inst, cast.rect, cast.shape)
    } else {
        out.append(inst)
    }
}

func pushInsetShadow(
    _ out: inout [Instance],
    _ sh: Shadow,
    _ c: Color,
    rect: [Float],
    radii: [Float],
    kPx: Float,
    scale: Float,
    opacity: Float,
    srgb: Bool,
    clip: [Float],
    fade: [Float]
) {
    out.append(
        Instance(
            rect: rect,
            radii: radii,
            fill: premul(c, opacity, srgb),
            border: [0.0, 0.0, 0.0, 0.0],
            params: [sh.spread * kPx, KIND_INSET, sh.blur > 0.0 ? max(sh.blur * scale * 0.5, 0.5) : 0.0, 1.0],
            uv: [sh.x * kPx, sh.y * kPx, 0.0, 0.0],
            clip: clip,
            fade: packFade(fade, clip, clip)
        )
    )
}
