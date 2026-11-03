// Ported from: crates/rune/src/text/glyph_emit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Glyph emission: walking a laid-out paragraph's glyphs into atlas quads.

/// Positions per device pixel that the glyphs of a gliding box draw at down the screen
/// (`TextSystem.setGlide`): a glyph has at most this many masks for each x phase.
let GLIDE_PHASES: UInt8 = 4

/// What `TextSystem.pushGlyph` drew: an atlas mask or nothing at an `[x, y]` phase, which a
/// later frame can replay at those phases, or a quad (colour emoji / unplaced) it must ask for again.
enum PlacedGlyphResult: Sendable {
    case atlas(AtlasGlyph, [UInt8])
    case empty([UInt8])
    case other
}

struct EmitFace: Sendable {
    var font: ShapedFontFace
    var size: Float
    var ink: UInt16
    var baseline: Float

    static func of(_ glyphRun: PositionedGlyphRun) -> EmitFace {
        EmitFace(
            font: glyphRun.font,
            size: glyphRun.fontSize,
            ink: glyphRun.ink.rawValue,
            baseline: glyphRun.baseline()
        )
    }
}

/// Where a glyph with its resting pen at `at` draws at `ppem` device px, gliding by `glide`: its
/// quad's whole-pixel pen and its x phase (sixtieths, `PHASES`) and y phase (`GLIDE_PHASES` a pixel).
func place(_ at: [Float], _ ppem: Float, _ glide: [Float]) -> ([Float], [UInt8]) {
    let ax = at.count > 0 ? at[0] : 0.0
    let ay = at.count > 1 ? at[1] : 0.0
    let glx = glide.count > 0 ? glide[0] : 0.0
    let gly = glide.count > 1 ? glide[1] : 0.0

    let (rx, rSubpx) = glyphX(ax, ppem)
    let n = Float(GLIDE_PHASES)
    let gx = rx * GLYPH_X_PHASES + Float(rSubpx) + (glx * n).rounded(.toNearestOrAwayFromZero) * (GLYPH_X_PHASES / n)
    var fx = (gx / GLYPH_X_PHASES).rounded(.down)
    var remX = Int((gx - fx * GLYPH_X_PHASES).rounded(.toNearestOrAwayFromZero))
    if remX >= Int(GLYPH_X_PHASES) {
        fx += 1.0
        remX = 0
    } else if remX < 0 {
        remX = 0
    }
    let subpx = UInt8(remX)

    let y = ay.rounded(.toNearestOrAwayFromZero) * n + (gly * n).rounded(.toNearestOrAwayFromZero)
    var fy = (y / n).rounded(.down)
    var remY = Int((y - fy * n).rounded(.toNearestOrAwayFromZero))
    if remY >= Int(GLIDE_PHASES) {
        fy += 1.0
        remY = 0
    } else if remY < 0 {
        remY = 0
    }
    let subpy = UInt8(remY)

    return ([fx, fy], [subpx, subpy])
}

/// The quad of atlas mask `a` for a pen at whole-pixel x `fx` and baseline `gy`.
func atlasQuad(_ a: AtlasGlyph, _ fx: Float, _ gy: Float, _ ink: UInt16, _ byte: UInt32) -> GlyphQuad {
    GlyphQuad(
        rect: [
            fx + Float(a.left),
            gy.rounded(.toNearestOrAwayFromZero) - Float(a.top),
            Float(a.w),
            Float(a.h)
        ],
        uv: [
            Float(a.x),
            Float(UInt32(a.page) * ATLAS_SIZE + a.y)
        ],
        ink: ink,
        byte: byte,
        color: 0
    )
}

func partitionClusterTable(_ table: [(Float, UInt32)], _ target: Float) -> UInt32 {
    guard !table.isEmpty else { return 0 }
    var lo = 0
    var hi = table.count
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        if table[mid].0 <= target {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    return table[max(lo - 1, 0)].1
}

extension Smoothing {
    func key() -> UInt8 {
        pipeline.bits()
    }

    func radius(_ ink: UInt16, _ ppem: Float) -> Double {
        dilation(ink, ppem).1
    }
}

extension TextSystem {
    /// Glyph quads for single-line `text` with its layout box's top-left at `origin` (device px).
    public func glyphs(
        _ text: String,
        _ style: TextStyle,
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [GlyphQuad]
    ) {
        let l = layoutRich(text, [], style, scale, nil)
        glyphsForLayout(l, scale, origin, false, &out)
    }

    /// Glyph quads for a cached `TextLayout` with its top-left at `origin` (device px). When
    /// `bytes` is set, each quad carries the byte offset of its cluster.
    public func glyphsForLayout(
        _ layout: TextLayout,
        _ scale: Float,
        _ origin: [Float],
        _ bytes: Bool,
        _ out: inout [GlyphQuad]
    ) {
        _ = scale
        glyphsForLayoutScaled(layout, origin, 1.0, bytes, &out)
    }

    /// `glyphsForLayout` with the layout magnified `k` times about `origin`: pen positions
    /// scale and each glyph rasterizes at `k` times its size, so it stays crisp.
    func glyphsForLayoutScaled(
        _ layout: TextLayout,
        _ origin: [Float],
        _ k: Float,
        _ bytes: Bool,
        _ out: inout [GlyphQuad]
    ) {
        glyphsInBand(layout, origin, k, bytes, (-.infinity)..<(Float.infinity), &out)
    }

    /// `glyphsForLayoutScaled` for only the lines whose box meets `band` (device px before `k`),
    /// located via binary search.
    func glyphsInBand(
        _ layout: TextLayout,
        _ origin: [Float],
        _ k: Float,
        _ bytes: Bool,
        _ band: Range<Float>,
        _ out: inout [GlyphQuad]
    ) {
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        var table = clusterScratch
        clusterScratch = []

        var lo = 0
        if band.lowerBound > 0.0 {
            var hi = layout.len()
            while lo < hi {
                let mid = (lo + hi) / 2
                if let l = layout.get(mid), l.metrics().blockMaxCoord < band.lowerBound {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
        }

        var i = lo
        while i < layout.len(), let line = layout.get(i), line.metrics().blockMinCoord <= band.upperBound {
            if bytes {
                table.removeAll(keepingCapacity: true)
                var x = line.metrics().inlineMinCoord + line.metrics().offset
                for run in line.runs() {
                    let vClusters = run.visualClusters()
                    if let first = vClusters.first {
                        x = line.metrics().inlineMinCoord + first.visualOffset
                    }
                    for cl in vClusters {
                        table.append((x, UInt32(clamping: cl.textRange.lowerBound)))
                        x += cl.advance
                    }
                }
                if table.count > 1 {
                    table.sort { $0.0 < $1.0 }
                }
            }

            for item in line.items() {
                guard case .glyphRun(let glyphRun) = item else { continue }
                let face = EmitFace.of(glyphRun)
                let baseline = (oy + face.baseline * k).rounded(.toNearestOrAwayFromZero)
                var rel = glyphRun.offset()
                for g in glyphRun.glyphs() {
                    let byte: UInt32 = bytes ? partitionClusterTable(table, rel + 0.01) : 0
                    let at: [Float] = (k == 1.0)
                        ? [ox + rel + g.x, baseline + g.y]
                        : [ox + (rel + g.x) * k, baseline + g.y * k]
                    _ = pushGlyph(face, UInt32(g.id), at, k, byte, &out)
                    rel += g.advance
                }
            }
            i += 1
        }
        clusterScratch = table
    }

    /// Glyph quads for the grapheme at byte `at` of a shaped run, with the run's top-left at `origin`.
    public func glyphsIn(
        _ run: RunLayout,
        _ at: Int,
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [GlyphQuad]
    ) {
        _ = scale
        guard let i = run.grapheme(at) else { return }
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let gStart = Int(run.graphemes[i].2)
        let gEnd = Int(run.graphemes[i + 1].2)
        guard gStart <= gEnd && gEnd <= run.glyphs.count else { return }
        for g in run.glyphs[gStart..<gEnd] {
            let rf = run.faces[Int(g.face)]
            let emitFace = EmitFace(font: rf.font, size: rf.size, ink: rf.ink, baseline: rf.baseline)
            let baseline = (oy + rf.baseline).rounded(.toNearestOrAwayFromZero)
            _ = pushGlyph(emitFace, UInt32(g.id), [ox + g.x, baseline + g.y], 1.0, UInt32(clamping: at), &out)
        }
    }

    /// Rasterizes (once) and appends one glyph at device position `at`, `k` times its size.
    func pushGlyph(
        _ face: EmitFace,
        _ glyph: UInt32,
        _ at: [Float],
        _ k: Float,
        _ byte: UInt32,
        _ out: inout [GlyphQuad]
    ) -> PlacedGlyphResult {
        let gx = at.count > 0 ? at[0] : 0.0
        let gy = at.count > 1 ? at[1] : 0.0
        let font = face.font
        let fontSize = face.size * k
        let ink = face.ink
        let skew = font.skewDegrees
        let radius = smoothingState.radius(ink, fontSize)
        let (fPos, sub) = place(at, fontSize, glide)
        let fx = fPos[0]
        let fy = fPos[1]
        let subpx = sub[0]
        let subpy = sub[1]

        let key = GlyphKey(
            font: font.fontId,
            index: font.index,
            glyph: glyph,
            size: fontSize.bitPattern,
            coords: font.coordsHash,
            subpx: subpx,
            subpy: subpy,
            dilation: Float(radius).bitPattern,
            apple: smoothingState.key(),
            skew: skew
        )

        let resolved: AtlasGlyph?
        if let existing = atlas.map[key] {
            if let a = existing {
                atlas.touch(a.page, a.w * a.h)
            }
            resolved = existing
        } else {
            // Colour glyphs sit on whole pixels and ignore emboldening and obliques.
            var colorKey = key
            colorKey.subpx = 0
            colorKey.subpy = 0
            colorKey.dilation = 0
            colorKey.apple = 0
            colorKey.skew = 0
            if var c = colorGlyphs[colorKey] {
                c.used = true
                colorGlyphs[colorKey] = c
                out.append(c.quad(gx, gy, glide, ink, byte))
                return .other
            }

            if font.isColorEmoji, let (pixels, placement) = rasterizeColorGlyph(font: font, glyph: UInt16(truncatingIfNeeded: glyph), ppem: fontSize) {
                let addedBytes = Int(placement.w) * Int(placement.h) * 4
                let (sumBytes, overflow) = colorBytes.addingReportingOverflow(addedBytes)
                colorBytes = overflow ? Int.max : sumBytes
                colorPixels.append(pixels)
                let index = UInt32(colorPixels.count)
                let c = ColorGlyph(
                    index: index,
                    used: true,
                    left: placement.left,
                    top: placement.top,
                    w: placement.w,
                    h: placement.h
                )
                colorGlyphs[colorKey] = c
                out.append(c.quad(gx, gy, glide, ink, byte))
                return .other
            }

            let placed = rasterizeGreyscaleGlyph(
                font: font,
                glyph: UInt16(truncatingIfNeeded: glyph),
                ppem: fontSize,
                phaseX: Float(subpx) / GLYPH_X_PHASES,
                shiftY: Float(subpy) / Float(GLIDE_PHASES),
                radius: radius,
                skewDegrees: skew
            )
            switch placed {
            case .placed(let g):
                atlas.map[key] = .some(g)
                resolved = g
            case .empty:
                atlas.map[key] = .some(nil)
                resolved = nil
            case .unplaced:
                return .other
            }
        }

        if let a = resolved {
            out.append(atlasQuad(a, fx, fy, ink, byte))
            return .atlas(a, [subpx, subpy])
        } else {
            return .empty([subpx, subpy])
        }
    }

    /// Moves the glyphs placed from here on by `glide` device px (`[x, y]`, each within half a
    /// pixel), in at least `GLIDE_PHASES` steps per pixel on any gliding axis.
    func setGlide(_ glide: [Float]) {
        if glide.count >= 2 {
            self.glide = [glide[0], glide[1]]
        } else if glide.count == 1 {
            self.glide = [0.0, glide[0]]
        } else {
            self.glide = [0.0, 0.0]
        }
    }

    /// Single-axis vertical glide convenience.
    func setGlide(_ shiftY: Float) {
        self.glide = [0.0, shiftY]
    }
}
