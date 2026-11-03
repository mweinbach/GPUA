// Ported from: crates/rune/src/runtime/paint/bands.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Band splitting for outer shadows under opaque boxes and border-only rings so interior pixels
//! are not shaded across large panels (`uv = [x0, y0, -x1, y1]`).

/// The middle must be at least this many device pixels both ways for bands to pay.
let MIN_BAND_HOLE: Float = 96.0

/// Pushes the outer shadow `inst` of an opaque box at `caster` (device px, `x, y, w, h`) with
/// corner `radii` (negative for continuous corners): the box hides the shadow inside it.
func pushShadowBands(_ out: inout [Instance], _ inst: Instance, _ caster: [Float], _ radii: [Float]) {
    let e = radii.reduce(Float(0.0)) { max($0, cornerExtent($1)) } + 1.0
    let x = caster[0] - inst.rect[0]
    let y = caster[1] - inst.rect[1]
    pushBandSplit(
        &out,
        inst,
        [x + e, y + e, x + caster[2] - e, y + caster[3] - e],
        inst.params[2] * 3.0 + 1.0
    )
}

/// Pushes the border-only `inst` (its fill clear): nothing draws past its ring.
func pushRingBands(_ out: inout [Instance], _ inst: Instance) {
    let e = inst.radii.reduce(Float(0.0)) { max($0, cornerExtent($1)) }
        + inst.params[0]
        + max(inst.params[2], 0.5)
        + 1.0
    let w = inst.rect[2]
    let h = inst.rect[3]
    pushBandSplit(&out, inst, [e, e, w - e, h - e], 1.0 + inst.params[2] * 2.0)
}

/// `inst` whole, or as four bands around `hole` (`x0, y0, x1, y1` relative to its rect) when that
/// hole is at least `MIN_BAND_HOLE` device pixels wide and tall.
func pushBandSplit(_ out: inout [Instance], _ inst: Instance, _ hole: [Float], _ grow: Float) {
    let hx0 = hole[0], hy0 = hole[1], hx1 = hole[2], hy1 = hole[3]
    let qx0 = -grow, qy0 = -grow
    let qx1 = inst.rect[2] + grow, qy1 = inst.rect[3] + grow

    if hx1 - hx0 < MIN_BAND_HOLE
        || hy1 - hy0 < MIN_BAND_HOLE
        || hx0 < 1.0
        || hy0 <= qy0
        || hx1 >= qx1
        || hy1 >= qy1
        || inst.uv != [0.0, 0.0, 0.0, 0.0]
    {
        out.append(inst)
        return
    }

    let bands: [[Float]] = [
        [qx0, qy0, qx1, hy0],
        [qx0, hy0, hx0, hy1],
        [hx1, hy0, qx1, hy1],
        [qx0, hy1, qx1, qy1],
    ]
    for b in bands {
        var copy = inst
        copy.uv = [b[0], b[1], -b[2], b[3]]
        out.append(copy)
    }
}
