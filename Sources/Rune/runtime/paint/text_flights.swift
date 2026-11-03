// Ported from: crates/rune/src/runtime/paint/text_flights.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Text flights drawn as an overlay of glyph instances, from their source text to their landed text.

import RuneMotion

extension Runtime {
    /// Draw active text flight overlays over this frame's completed layout/scroll geometries.
    /// Returns `true` if one or more flights remain in flight.
    func drawTextFlights(into out: inout [Instance], glyphCount: inout Int) -> Bool {
        guard !activeTextFlights.isEmpty else { return false }
        let s = max(env.scale, 0.001)
        let srgb = srgbBlend
        let now = t
        let reduced = reducedMotion
        let vpClip: [Float] = [0.0, 0.0, viewport.0, viewport.1]

        // Retain only flights whose target element is still mounted and not exiting
        activeTextFlights.removeAll { f in
            !nodes.contains { n in
                if !f.lands(n.path, n.key) { return false }
                if case .exiting = scene.phase(n.nodeId) { return false }
                return true
            }
        }
        guard !activeTextFlights.isEmpty else { return false }

        var doneIndices: [Int] = []
        for fi in activeTextFlights.indices {
            guard let nodeIdx = nodes.indices.first(where: { activeTextFlights[fi].lands(nodes[$0].path, nodes[$0].key) }) else {
                doneIndices.append(fi)
                continue
            }
            let n = nodes[nodeIdx]
            guard let spec = n.textSpec, let layout = n.textLayout else {
                doneIndices.append(fi)
                continue
            }

            let drawn = n.presentedRect
            let targetW = max(min(layout.width, drawn[2]), 1.0)
            let targetH = max(min(layout.height, drawn[3]), 1.0)
            let target = RuneMotion.Rect(drawn[0], drawn[1], targetW, targetH)
            if activeTextFlights[fi].measure(target, now, reduced) {
                doneIndices.append(fi)
            }

            let quantum: Float = 1.0 / (64.0 * s)
            if abs(activeTextFlights[fi].presented.w - target.w) < quantum {
                activeTextFlights[fi].presented.w = target.w
            }
            if abs(activeTextFlights[fi].presented.h - target.h) < quantum {
                activeTextFlights[fi].presented.h = target.h
            }
            let edges = activeTextFlights[fi].presented.edges().map { RuneMotion.snap.grid($0, s) }
            activeTextFlights[fi].presented = RuneMotion.Rect(
                edges[0],
                edges[1],
                edges[2] - edges[0],
                edges[3] - edges[1]
            )

            let p = activeTextFlights[fi].progressAt(now, reduced)
            let (sourceAlpha, targetAlpha) = activeTextFlights[fi].alphas(target, now, reduced)
            let rawClip = n.clipBounds
            let actualClip: [Float] = [
                max(rawClip[0], 0.0),
                max(rawClip[1], 0.0),
                min(rawClip[2], vpClip[2]),
                min(rawClip[3], vpClip[3]),
            ]
            let current = activeTextFlights[fi].presented
            let src = activeTextFlights[fi].source
            let srcClip = activeTextFlights[fi].sourceClip
            let zoom = current.w / max(src.w, 1e-3)
            let startClip: [Float] = [
                current.x + (srcClip[0] - src.x) * zoom,
                current.y + (srcClip[1] - src.y) * zoom,
                current.x + (srcClip[2] - src.x) * zoom,
                current.y + (srcClip[3] - src.y) * zoom,
            ]
            let clip: [Float] = (0..<4).map { j in
                startClip[j] + (vpClip[j] - startClip[j]) * p
            }
            activeTextFlights[fi].clip = reduced ? actualClip : clip
            activeTextFlights[fi].sourceAlpha = sourceAlpha
            activeTextFlights[fi].targetAlpha = targetAlpha
            let zeroFade: [Float] = [0.0, 0.0, 0.0, 0.0]

            if sourceAlpha > 0.0 {
                let sourceRect = reduced ? src : current
                let sourceClip = reduced ? srcClip : clip
                for q in activeTextFlights[fi].glyphs {
                    out.append(
                        transformedFlightInstance(
                            q,
                            src,
                            sourceRect,
                            activeTextFlights[fi].scale,
                            sourceAlpha,
                            sourceClip,
                            zeroFade
                        )
                    )
                    glyphCount += 1
                }
            }

            if targetAlpha > 0.0 {
                let baseColor = sampledColor(n.nodeId, P_TEXT, spec.color)
                let targetClip = reduced ? actualClip : clip
                for line in layout.lines {
                    for g in line.glyphs where g.advance > 0.0 {
                        let q = GlyphQuad(
                            rect: [(target.x + g.x) * s, (target.y + g.y) * s, g.advance * s, g.height * s],
                            uv: [0.0, 0.0],
                            ink: 0,
                            byte: UInt32(g.byteOffset),
                            color: 0
                        )
                        let c = g.color == spec.color ? baseColor : g.color
                        let inst = glyphInst(q, premul(c, g.alpha, srgb), NO_CLIP, zeroFade)
                        out.append(
                            transformedFlightInstance(
                                inst,
                                target,
                                current,
                                s,
                                targetAlpha,
                                targetClip,
                                zeroFade
                            )
                        )
                        glyphCount += 1
                    }
                }
            }
        }

        for idx in doneIndices.reversed() where activeTextFlights.indices.contains(idx) {
            activeTextFlights.remove(at: idx)
        }
        return !activeTextFlights.isEmpty
    }
}
