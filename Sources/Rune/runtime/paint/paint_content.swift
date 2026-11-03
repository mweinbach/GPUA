// Ported from: crates/rune/src/runtime/paint/content.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Leaf content painting inside a box: vector shapes, images, icons, text fields, decorations, and glyphs.

import RuneMotion

struct LeafBox {
    var r: [Float]
    var rExact: [Float]
    var rawSize: [Float]
    var radii: [Float]
    var sc: Float
    var o: Float
    var draw: Float
    var clip: [Float]
    var fade: [Float]
    var gliding: Bool
    var caret: [Float]?
}

extension Runtime {
    func paintLeafContent(
        nodeIdx i: Int,
        box b: LeafBox,
        selectedByPath: [String: Range<Int>],
        into out: inout [Instance],
        glyphCount: inout Int
    ) {
        let s = max(env.scale, 0.001)
        let srgb = srgbBlend
        let now = t
        let r = b.r
        let rExact = b.rExact
        let w = max(r[2] - r[0], 0.0)
        let h = max(r[3] - r[1], 0.0)
        let wExact = max(rExact[2] - rExact[0], 0.0)
        let hExact = max(rExact[3] - rExact[1], 0.0)
        let sc = b.sc
        let o = b.o
        let clip = b.clip
        let fade = b.fade
        let kPx = sc * s

        let n = nodes[i]
        let nodeId = n.nodeId
        let cold = n.vis.cold.getIfSome

        // 1. Vector `Shape`
        if let shape = cold?.shape {
            let origin: [Float]
            let k: [Float]
            if let vb = shape.viewBoxSize, vb.count >= 2, vb[0] > 0.0, vb[1] > 0.0 {
                origin = [r[0], r[1]]
                k = [w / vb[0], h / vb[1]]
            } else {
                origin = [r[0] + (w - wExact) * 0.5, r[1] + (h - hExact) * 0.5]
                k = [kPx, kPx]
            }
            if b.draw < 1.0 {
                pushShape(&out, shape.drawn(b.draw), origin: origin, k: k, kPx: kPx, opacity: o, srgb: srgb, clip: clip, fade: fade)
            } else {
                pushShape(&out, shape, origin: origin, k: k, kPx: kPx, opacity: o, srgb: srgb, clip: clip, fade: fade)
            }
        }

        // 2. `Pixels` image buffer
        if let pixels = cold?.pixels {
            let snapU = min(max(1.0 - abs(sc - 1.0) * 32.0, 0.0), 1.0)
            let place = cold?.surfacePlace ?? SurfacePlace()
            let effectiveFit: SurfaceFit? = cold?.surface?.1 ?? (place.unscaled ? .fit : nil)
            let (imgRect, crop) = fitImageRect(effectiveFit, place, [r[0], r[1], w, h], pixels.size(), snapU)
            let spanW = max(crop[2] - crop[0], 1e-4)
            let spanH = max(crop[3] - crop[1], 1e-4)
            if let placed = images.place(pixels, [imgRect[2] / spanW, imgRect[3] / spanH]) {
                let ix = Float(placed.rect[0])
                let iy = Float(placed.rect[1])
                let iw = Float(placed.rect[2])
                let ih = Float(placed.rect[3])
                out.append(
                    Instance(
                        rect: imgRect,
                        radii: b.radii,
                        fill: [0.0, 0.0, 0.0, o],
                        border: [0.0, 0.0, 0.0, 0.0],
                        params: [Float(placed.page), KIND_IMAGE, placed.premultiplied ? 1.0 : 0.0, 1.0],
                        uv: [
                            ix + (crop[0] * iw).rounded(),
                            iy + (crop[1] * ih).rounded(),
                            spanW * iw,
                            spanH * ih,
                        ],
                        clip: clip,
                        fade: packFade(fade, clip, clip)
                    )
                )
            }
        }

        // 3. Vector `Icon`
        if let (ic, baseIconColor) = cold?.icon {
            _ = ic
            let color = sampledColor(nodeId, P_TEXT, baseIconColor)
            let baseTurn = cold?.iconTurn ?? 0.0
            let trackedTurn = scene.store().has(nodeId, P_ICON_TURN)
                ? (scene.get(nodeId, P_ICON_TURN) ?? baseTurn)
                : baseTurn
            let loopSpin: Float = {
                guard let lp = loops[nodeId], !lp.sleeping, case .rotation = lp.spec.kind else { return 0.0 }
                return Float(lp.phase) * 2.0 * Float.pi
            }()
            let turn = trackedTurn + loopSpin
            let exactSide = min(wExact, hExact)
            let rawSide = max(min(b.rawSize[0], b.rawSize[1]), 0.0) * s
            let snapU: Float = abs(rawSide - rawSide.rounded()) < (1.0 / 512.0)
                ? min(max(1.0 - abs(sc - 1.0) * 32.0, 0.0), 1.0)
                : 0.0
            let drawn = exactSide + (min(w, h) - exactSide) * snapU
            if drawn > 1e-4 {
                let px = max(1, Int(drawn.rounded()))
                let pos: [Float] = [(r[0] + r[2] - drawn) * 0.5, (r[1] + r[3] - drawn) * 0.5]
                let q = GlyphQuad(rect: [pos[0], pos[1], Float(px), Float(px)], uv: [0.0, 0.0])
                out.append(iconInst(q, pos, drawn, turn, premul(color, o, srgb), clip, fade))
            }
            return
        }

        // 4. Laid-out `TextSpec` + `InputSpec`
        guard let spec = n.textSpec, let layout = n.textLayout else { return }
        let baseTextColor = sampledColor(nodeId, P_TEXT, spec.color)
        let tk = sc
        let glide: [Float] = b.gliding ? [pixelSnapTextGlide(r[0]), pixelSnapTextGlide(r[1])] : [0.0, 0.0]

        var textOrigin: [Float] = [r[0], r[1]]
        var textClip = clip
        if let inp = n.input, inp.singleLine {
            let scrollOff = inputScrollOffsets[n.path] ?? 0.0
            textOrigin[0] -= scrollOff * s * tk
            if layout.width * s * tk > w {
                textClip = [max(textClip[0], r[0]), textClip[1], min(textClip[2], r[2]), textClip[3]]
            }
        }
        let restOrigin: [Float] = [textOrigin[0] - glide[0], textOrigin[1] - glide[1]]

        // Rich paragraph block decorations (code blocks, quotes, list bullets)
        if spec.blocks.contains(where: { $0 != .paragraph }) {
            emitRichBlockDecorations(
                instances: &out,
                spec: spec,
                layout: layout,
                origin: restOrigin,
                xRange: (r[0] - glide[0], r[2] - glide[0]),
                scale: s,
                tk: tk,
                glide: glide,
                textColor: baseTextColor,
                opacity: o,
                srgb: srgb,
                clip: textClip,
                fade: fade
            )
        }

        // Text field placeholder, selection, and preedit underline
        var caretToDraw: [Float]? = nil
        if let inp = n.input {
            let e = inp.edit
            let departing = activeTextFlights.contains { f in
                f.departs(n.path, n.key) && f.alphas(f.destination, now, reducedMotion).0 > 0.0
            }
            if e.text.isEmpty && e.preedit == nil && !inp.placeholder.isEmpty && !departing {
                let plSpec = TextSpec(content: inp.placeholder)
                var plCopy = plSpec
                plCopy.style = spec.style
                plCopy.color = inp.placeholderColor
                let plLayout = layoutTextSpec(plCopy, maxWidth: max(w / max(s * tk, 1e-4), 1.0), textSys: text, previouslyShapedText: nil)
                let pc = premul(inp.placeholderColor, o, srgb)
                for line in plLayout.lines {
                    for g in line.glyphs where g.advance > 0.0 {
                        let gx = textOrigin[0] + g.x * s * tk
                        let gy = textOrigin[1] + g.y * s * tk
                        let gw = g.advance * s * tk
                        let gh = g.height * s * tk
                        let q = GlyphQuad(rect: [gx, gy, gw, gh], uv: [0.0, 0.0], ink: 0, byte: UInt32(g.byteOffset))
                        out.append(glyphInst(q, pc, textClip, fade))
                        glyphCount += 1
                    }
                }
            }
            if e.focused && !departing {
                let (selA, selB) = e.range()
                if selA != selB && e.preedit == nil && !e.isHiddenMultiline {
                    let dispRange: (Int, Int) = {
                        if e.isSecure() && !e.isRevealed() {
                            let bulletBytes = "•".utf8.count
                            let cA = sliceUtf8Safely(e.text, 0..<selA).count * bulletBytes
                            let cB = sliceUtf8Safely(e.text, 0..<selB).count * bulletBytes
                            return (cA, cB)
                        }
                        return (selA, selB)
                    }()
                    let selFill = premul(inp.selection, o, srgb)
                    for lr in selectionRectsInTextLayout(layout, byteRange: dispRange.0..<dispRange.1) {
                        out.append(
                            rectInst(
                                [
                                    textOrigin[0] + lr[0] * s * tk,
                                    textOrigin[1] + lr[1] * s * tk,
                                    lr[2] * s * tk,
                                    lr[3] * s * tk,
                                ],
                                selFill,
                                2.0 * s * tk,
                                textClip,
                                fade
                            )
                        )
                    }
                }
                if let (_, preRange) = e.preedit {
                    let dispStart = e.anchor < e.focus ? e.anchor : e.focus
                    let len = preRange.map { $0.1 - $0.0 } ?? e.preedit!.0.utf8.count
                    for lr in selectionRectsInTextLayout(layout, byteRange: dispStart..<(dispStart + max(len, 1))) {
                        out.append(
                            rectInst(
                                [
                                    textOrigin[0] + lr[0] * s * tk,
                                    textOrigin[1] + (lr[1] + lr[3]) * s * tk - s,
                                    lr[2] * s * tk,
                                    s,
                                ],
                                premul(baseTextColor, o, srgb),
                                0.0,
                                textClip,
                                fade
                            )
                        )
                    }
                }
                caretToDraw = b.caret
            }
        }

        // Highlights (`spec.highlights`)
        for hl in spec.highlights {
            let hr = hl.range()
            guard hr.lowerBound < hr.upperBound else { continue }
            let padPx = hl.padValue * s * tk
            for lr in selectionRectsInTextLayout(layout, byteRange: hr) {
                let hRect: [Float] = [
                    textOrigin[0] + lr[0] * s * tk - padPx,
                    textOrigin[1] + lr[1] * s * tk,
                    lr[2] * s * tk + 2.0 * padPx,
                    lr[3] * s * tk,
                ]
                var inst = rectInst(hRect, premul(hl.bg, o, srgb), 3.0 * s * tk, textClip, fade)
                if let (ringColor, ringW) = hl.ringValue {
                    inst.border = premul(ringColor, o, srgb)
                    inst.params[0] = ringW * kPx
                }
                out.append(inst)
            }
        }

        // Active link hover / press / focus backgrounds & rings
        let activeLinkPaints: [(Range<Int>, LinkPaint)] = spec.links.enumerated().compactMap { linkIdx, link in
            let lr = Int(link.start)..<Int(link.end)
            if pressedLinkTarget?.0 == n.path && pressedLinkTarget?.1 == linkIdx, let pp = link.pressedPaint {
                return (lr, pp)
            }
            if hoveredPaths.contains(n.path), let lp = lastPointer {
                let localX = lp.0 - n.presentedRect[0]
                let localY = lp.1 - n.presentedRect[1]
                for box in selectionRectsInTextLayout(layout, byteRange: lr) {
                    if localX >= box[0] && localX <= box[0] + box[2] && localY >= box[1] && localY <= box[1] + box[3] {
                        if !link.hoverPaint.isEmpty {
                            return (lr, link.hoverPaint)
                        }
                    }
                }
            }
            return nil
        }
        for (lr, paint) in activeLinkPaints {
            if paint.bgValue != nil || paint.ringValue != nil {
                for box in selectionRectsInTextLayout(layout, byteRange: lr) {
                    let dRect: [Float] = [
                        textOrigin[0] + box[0] * s * tk - 1.5 * s * tk,
                        textOrigin[1] + box[1] * s * tk,
                        box[2] * s * tk + 3.0 * s * tk,
                        box[3] * s * tk,
                    ]
                    var inst = rectInst(dRect, premul(paint.bgValue ?? .TRANSPARENT, o, srgb), 3.0 * s * tk, textClip, fade)
                    if let (rc, rw) = paint.ringValue {
                        inst.border = premul(rc, o, srgb)
                        inst.params[0] = rw * kPx
                    }
                    out.append(inst)
                }
            }
            if let ul = paint.underlineValue {
                for box in selectionRectsInTextLayout(layout, byteRange: lr) {
                    out.append(
                        rectInst(
                            [
                                textOrigin[0] + box[0] * s * tk,
                                textOrigin[1] + (box[1] + box[3]) * s * tk - max(s, 1.0),
                                box[2] * s * tk,
                                max(s, 1.0),
                            ],
                            premul(ul, o, srgb),
                            0.0,
                            textClip,
                            fade
                        )
                    )
                }
            }
        }

        // Static selectable text highlight rects
        if spec.selectable, let selRange = selectedByPath[n.path] {
            let selFill = premul(spec.selection, o, srgb)
            for lr in selectionRectsInTextLayout(layout, byteRange: selRange) {
                out.append(
                    rectInst(
                        [
                            textOrigin[0] + lr[0] * s * tk,
                            textOrigin[1] + lr[1] * s * tk,
                            lr[2] * s * tk,
                            lr[3] * s * tk,
                        ],
                        selFill,
                        2.0 * s * tk,
                        textClip,
                        fade
                    )
                )
            }
        }

        // Span backgrounds & underlines, then glyphs
        let landsFlight = activeTextFlights.contains { $0.lands(n.path, n.key) }
        let revealProg = activeRevealProgress(for: i)
        let totalBytes = max(layout.text.utf8.count, 1)

        for line in layout.lines {
            // Span backgrounds
            for g in line.glyphs where g.advance > 0.0 {
                if let bg = g.bg {
                    let pad = g.bgPad * s * tk
                    out.append(
                        rectInst(
                            [
                                textOrigin[0] + g.x * s * tk - pad,
                                textOrigin[1] + g.y * s * tk,
                                g.advance * s * tk + 2.0 * pad,
                                g.height * s * tk,
                            ],
                            premul(bg, o * g.alpha, srgb),
                            3.0 * s * tk,
                            textClip,
                            fade
                        )
                    )
                }
                if let ul = g.underline {
                    out.append(
                        rectInst(
                            [
                                textOrigin[0] + g.x * s * tk,
                                textOrigin[1] + (g.y + g.height) * s * tk - max(s, 1.0),
                                g.advance * s * tk,
                                max(s, 1.0),
                            ],
                            premul(ul, o * g.alpha, srgb),
                            0.0,
                            textClip,
                            fade
                        )
                    )
                }
            }

            if landsFlight {
                continue
            }

            // Glyphs (replay cached flattened line when non-secret)
            let isSecretField = spec.redacted || (n.input?.edit.isSecure() == true)
            let replayItems: [CachedReplayGlyph]
            if isSecretField {
                replayItems = line.glyphs.compactMap { g in
                    guard g.advance > 0.0 else { return nil }
                    return CachedReplayGlyph(
                        byteOffset: UInt32(g.byteOffset),
                        relX: g.x * s * tk,
                        relY: g.y * s * tk,
                        gw: g.advance * s * tk,
                        gh: g.height * s * tk,
                        color: g.color,
                        alpha: g.alpha
                    )
                }
            } else {
                let lineIdx = layout.lines.firstIndex(where: { $0.byteStart == line.byteStart && $0.y == line.y }) ?? 0
                let rKey = GlyphReplayLineKey(
                    nodeId: nodeId,
                    lineIdx: lineIdx,
                    textHash: fnvTextHash(layout.displayText),
                    widthBits: layout.width.bitPattern,
                    sizeBits: (spec.style.size * s * tk).bitPattern
                )
                if let cached = glyphCache.lines[rKey] {
                    replayItems = cached
                } else {
                    glyphCache.flattened &+= 1
                    let built = line.glyphs.compactMap { g -> CachedReplayGlyph? in
                        guard g.advance > 0.0 else { return nil }
                        return CachedReplayGlyph(
                            byteOffset: UInt32(g.byteOffset),
                            relX: g.x * s * tk,
                            relY: g.y * s * tk,
                            gw: g.advance * s * tk,
                            gh: g.height * s * tk,
                            color: g.color,
                            alpha: g.alpha
                        )
                    }
                    glyphCache.lines[rKey] = built
                    replayItems = built
                }
            }

            for cg in replayItems {
                let x0 = textOrigin[0] + cg.relX
                let y0 = textOrigin[1] + cg.relY
                let gw = cg.gw
                let gh = cg.gh
                if y0 > textClip[3] || y0 + gh < textClip[1] || x0 > textClip[2] || x0 + gw < textClip[0] {
                    continue
                }

                // Streaming / reveal fade per byte offset
                let bOff = Int(cg.byteOffset)
                var revealAlpha: Float = 1.0
                if revealProg < 0.999 {
                    let byteFrac = Float(bOff) / Float(totalBytes)
                    if byteFrac > revealProg {
                        let feather: Float = 0.08
                        revealAlpha = max(0.0, 1.0 - (byteFrac - revealProg) / feather)
                        if revealAlpha <= 0.001 {
                            continue
                        }
                    }
                }

                var glyphColor = (cg.color == spec.color) ? baseTextColor : cg.color
                for hl in spec.highlights.reversed() {
                    if bOff >= Int(hl.start) && bOff < Int(hl.end), let fg = hl.fg {
                        glyphColor = fg
                        break
                    }
                }
                for (lr, paint) in activeLinkPaints {
                    if lr.contains(bOff), let lc = paint.colorValue {
                        glyphColor = lc
                        break
                    }
                }

                let fill = premul(glyphColor, o * cg.alpha * revealAlpha, srgb)
                if fill[3] <= 0.0005 {
                    continue
                }
                let q = GlyphQuad(
                    rect: [x0, y0, gw, gh],
                    uv: [0.0, 0.0],
                    ink: 0,
                    byte: cg.byteOffset,
                    color: 0
                )
                out.append(glyphInst(q, fill, textClip, fade))
                glyphCount += 1
            }
        }

        if let cRect = caretToDraw, let inp = n.input {
            out.append(rectInst(cRect, premul(inp.caret, o, srgb), 0.0, textClip, fade))
        }
    }

    /// Text-only clipping leaves the box's fill/border and descendants untouched.
    func clipTextInstances(
        nodeIdx i: Int,
        firstInstance: Int,
        into out: inout [Instance],
        r: [Float],
        sc: Float,
        clip: [Float],
        fade: [Float],
        fadeOrigin: [Float]
    ) {
        let s = max(env.scale, 0.001)
        let n = nodes[i]
        guard let spec = n.textSpec, let layout = n.textLayout,
              spec.truncateFade || spec.live != nil
        else { return }

        let bounds = r
        let textClip = intersectClips(clip, bounds)
        var widths = fade
        var origins = fadeOrigin
        if spec.truncateFade && layout.width * s * sc > (bounds[2] - bounds[0]) + 0.5 * sc {
            let fadeWidth = min(spec.style.size * spec.fadeEm * sc * s, max(bounds[2] - bounds[0], 0.0))
            let own: [Float] = spec.align == .end
                ? [fadeWidth, 0.0, 0.0, 0.0]
                : [0.0, 0.0, fadeWidth, 0.0]
            inheritFade(&widths, &origins, bounds, own)
        }
        guard firstInstance < out.count else { return }
        let packed = packFade(widths, origins, textClip)
        for idx in firstInstance..<out.count where out[idx].params[1] == KIND_GLYPH {
            out[idx].clip = textClip
            out[idx].fade = packed
        }
    }
}
