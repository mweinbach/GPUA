// Ported from: crates/rune/src/runtime/paint/blend.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! sRGB vs linear-light premultiplication, clear color resolution, and glyph/icon `Instance` builders.

@inline(__always)
func premul(_ c: Color, _ opacity: Float, _ srgb: Bool) -> [Float] {
    srgb ? c.premulSrgb(opacity) : c.premul(opacity)
}

@inline(__always)
func colorToGpuPremul(_ color: Color, opacity: Float, srgb: Bool) -> [Float] {
    premul(color, opacity, srgb)
}

@inline(__always)
func glyphUvPage(_ uv: [Float]) -> ([Float], Float) {
    let u0 = uv.count > 0 ? uv[0] : 0.0
    let u1 = uv.count > 1 ? uv[1] : 0.0
    let page = UInt32(max(u1, 0.0)) / ATLAS_SIZE
    return ([u0, u1 - Float(page * ATLAS_SIZE)], Float(page))
}

func glyphInst(_ q: GlyphQuad, _ fill: [Float], _ clip: [Float], _ fade: [Float]) -> Instance {
    let (uv, page) = glyphUvPage(q.uv)
    return Instance(
        rect: q.rect,
        radii: [0.0, 0.0, 0.0, 0.0],
        fill: fill,
        border: [0.0, 0.0, 0.0, 0.0],
        params: [0.0, KIND_GLYPH, page, 1.0],
        uv: [uv[0], uv[1], 0.0, 0.0],
        clip: clip,
        fade: packFade(fade, clip, clip)
    )
}

func iconInst(
    _ q: GlyphQuad,
    _ pos: [Float],
    _ drawn: Float,
    _ turn: Float,
    _ fill: [Float],
    _ clip: [Float],
    _ fade: [Float]
) -> Instance {
    let (uv, page) = glyphUvPage(q.uv)
    let px = max(q.rect[2], 1.0)
    @inline(__always)
    func near(_ v: Float) -> Bool {
        abs(v - v.rounded()) < (1.0 / 512.0)
    }

    let rect: [Float]
    let outUv: [Float]
    if turn == 0.0 && near(pos[0]) && near(pos[1]) && abs(drawn - px) < (1.0 / 512.0) {
        rect = [pos[0].rounded(), pos[1].rounded(), px, px]
        outUv = [uv[0], uv[1], 0.0, 0.0]
    } else {
        let t = drawn / px
        rect = [pos[0] - t, pos[1] - t, drawn + 2.0 * t, drawn + 2.0 * t]
        outUv = [uv[0] - 1.0, uv[1] - 1.0, px + 2.0, px + 2.0]
    }
    return Instance(
        rect: rect,
        radii: [0.0, 0.0, 0.0, 0.0],
        fill: fill,
        border: [0.0, 0.0, 0.0, 0.0],
        params: [turn, KIND_GLYPH, page, 1.0],
        uv: outUv,
        clip: clip,
        fade: packFade(fade, clip, clip)
    )
}

extension Runtime {
    public func clearColor() -> [Float] {
        if transparent {
            return [0.0, 0.0, 0.0, 0.0]
        }
        guard let root = nodes.first else {
            return [0.0, 0.0, 0.0, 1.0]
        }
        let c = sampledColor(root.nodeId, P_FILL, root.vis.fill)
        if srgbBlend {
            return [srgbEncode(c.r), srgbEncode(c.g), srgbEncode(c.b), 1.0]
        } else {
            return [c.r, c.g, c.b, 1.0]
        }
    }
}
