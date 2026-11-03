// Ported from: crates/rune/src/runtime/paint/helpers.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Free paint helpers for clip intersection, rectangle/glyph scaling, loop opacity queries, and rich block decorations.

import RuneMotion

@inline(__always)
func intersectClips(_ a: [Float], _ b: [Float]) -> [Float] {
    [
        max(a[0], b[0]),
        max(a[1], b[1]),
        min(a[2], b[2]),
        min(a[3], b[3]),
    ]
}

@inline(__always)
func rectIntersectsClip(_ rectXYWH: [Float], _ clip: [Float], margin: Float = 0.0) -> Bool {
    let x0 = rectXYWH[0]
    let y0 = rectXYWH[1]
    let x1 = x0 + rectXYWH[2]
    let y1 = y0 + rectXYWH[3]
    return x1 >= clip[0] - margin
        && x0 <= clip[2] + margin
        && y1 >= clip[1] - margin
        && y0 <= clip[3] + margin
}

@inline(__always)
func loopFadesOpacity(_ spec: LoopSpec?) -> Bool {
    guard let spec else { return false }
    switch spec.kind {
    case .opacity, .opacityCycle, .sequence:
        return true
    default:
        return false
    }
}

@inline(__always)
func scaleAbout(_ rect: [Float], _ origin: [Float], _ rOrigin: [Float], _ k: Float) -> [Float] {
    [
        origin[0] + (rect[0] - rOrigin[0]) * k,
        origin[1] + (rect[1] - rOrigin[1]) * k,
        rect[2] * k,
        rect[3] * k,
    ]
}

@inline(__always)
func zoomGlyph(_ gIn: Instance, _ origin: [Float], _ rOrigin: [Float], _ k: Float) -> Instance {
    if k == 1.0 && origin == rOrigin {
        return gIn
    }
    var g = gIn
    if g.params[1] == KIND_GLYPH && g.uv[2] == 0.0 {
        g.uv[2] = g.rect[2]
        g.uv[3] = g.rect[3]
    }
    g.rect = [
        origin[0] + (g.rect[0] - rOrigin[0]) * k,
        origin[1] + (g.rect[1] - rOrigin[1]) * k,
        g.rect[2] * k,
        g.rect[3] * k,
    ]
    return g
}

@inline(__always)
func rectInst(_ rect: [Float], _ fill: [Float], _ radius: Float, _ clip: [Float], _ fade: [Float]) -> Instance {
    Instance(
        rect: rect,
        radii: [radius, radius, radius, radius],
        fill: fill,
        border: [0.0, 0.0, 0.0, 0.0],
        params: [0.0, KIND_RECT, 0.0, 1.0],
        uv: [0.0, 0.0, 0.0, 0.0],
        clip: clip,
        fade: packFade(fade, clip, clip)
    )
}

func emitRichBlockDecorations(
    instances: inout [Instance],
    spec: TextSpec,
    layout: RtTextLayout,
    origin: [Float],
    xRange: (Float, Float),
    scale s: Float,
    tk: Float,
    glide: [Float],
    textColor: Color,
    opacity o: Float,
    srgb: Bool,
    clip: [Float],
    fade: [Float]
) {
    guard !spec.blocks.isEmpty else { return }
    let lineHDefault = spec.style.linePx() * s * tk
    let boxW = max(max(xRange.1 - xRange.0, layout.width * s * tk), 40.0 * s * tk)

    var codeRun: (Float, Float)? = nil
    var quoteRun: (Float, Float)? = nil

    func flushCode() {
        guard let (top, bot) = codeRun else { return }
        codeRun = nil
        let padY = tk == 1.0 ? (2.0 * s).rounded() : (2.0 * s * tk)
        instances.append(
            rectInst(
                [xRange.0 + glide[0], top - padY + glide[1], boxW, (bot - top) + 2.0 * padY],
                premul(spec.richStyle.codeBlockBg, o, srgb),
                6.0 * s * tk,
                clip,
                fade
            )
        )
    }

    func flushQuote() {
        guard let (top, bot) = quoteRun else { return }
        quoteRun = nil
        let barW = tk == 1.0 ? max((3.0 * s).rounded(), 2.0) : max(3.0 * s * tk, 2.0 * tk)
        let barX = (tk == 1.0 ? (origin[0] + 2.0 * s).rounded() : (origin[0] + 2.0 * s * tk)) + glide[0]
        let insetY = tk == 1.0 ? (2.0 * s).rounded() : (2.0 * s * tk)
        instances.append(
            rectInst(
                [barX, top + insetY + glide[1], barW, max(bot - top - 2.0 * insetY, 4.0 * s * tk)],
                premul(spec.richStyle.quoteBar, o, srgb),
                barW * 0.5,
                clip,
                fade
            )
        )
    }

    for (lineIdx, line) in layout.lines.enumerated() {
        let blk = lineIdx < spec.blocks.count ? spec.blocks[lineIdx] : .paragraph
        let top = origin[1] + line.y * s * tk
        let bot = top + max(line.height * s * tk, lineHDefault)
        switch blk {
        case .code:
            flushQuote()
            if let existing = codeRun {
                codeRun = (existing.0, bot)
            } else {
                codeRun = (top, bot)
            }
        case .quote:
            flushCode()
            if let existing = quoteRun {
                quoteRun = (existing.0, bot)
            } else {
                quoteRun = (top, bot)
            }
        case .bullet(let lvl):
            flushCode()
            flushQuote()
            let markerColor = spec.richStyle.marker ?? textColor.alpha(0.68)
            let d = tk == 1.0 ? max((4.5 * s).rounded(), 3.0) : max(4.5 * s * tk, 3.0 * tk)
            let indentPx = (blk.indentPt(spec.style.size) * s).rounded()
            let cx = origin[0] + (indentPx - (7.0 * s).rounded()) * tk - d
            let cy = top + 0.46 * spec.style.size * s * tk - d * 0.5
            let radius = lvl >= 2 ? (1.0 * s * tk) : (d * 0.5)
            let col = lvl == 1 ? premul(markerColor.alpha(markerColor.a * 0.65), o, srgb) : premul(markerColor, o, srgb)
            instances.append(rectInst([cx + glide[0], cy + glide[1], d, d], col, radius, clip, fade))
        case .numbered:
            flushCode()
            flushQuote()
            let markerColor = spec.richStyle.marker ?? textColor.alpha(0.68)
            let d = max(3.5 * s * tk, 2.5)
            let indentPx = (blk.indentPt(spec.style.size) * s).rounded()
            let cx = origin[0] + (indentPx - (7.0 * s).rounded()) * tk - d
            let cy = top + 0.46 * spec.style.size * s * tk - d * 0.5
            instances.append(rectInst([cx + glide[0], cy + glide[1], d, d], premul(markerColor, o, srgb), d * 0.5, clip, fade))
        case .paragraph:
            flushCode()
            flushQuote()
        }
    }
    flushCode()
    flushQuote()
}
