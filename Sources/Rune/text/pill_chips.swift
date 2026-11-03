// Ported from: crates/rune/src/text/pill_chips.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The chips drawn behind pill labels in a laid-out paragraph.

/// The chip behind each pill in `layout` (device px, at `origin`), and each leading icon with
/// its size in px and top-left corner. A pill whose label wraps draws one chip per line, the
/// first to its line's end and the rest from the line's start.
func pillChips(
    _ layout: TextLayout,
    _ pills: [PillChip],
    _ size: Float,
    _ scale: Float,
    _ origin: [Float],
    _ bg: Color,
    _ out: inout [PaintedDeco],
    _ icons: inout [(Icon, UInt32, [Float], Color?)]
) {
    if pills.isEmpty {
        return
    }
    let ox = origin.count > 0 ? origin[0] : 0.0
    let oy = origin.count > 1 ? origin[1] : 0.0
    let pm = PillMetrics(size)

    for line in layout.lines() {
        let m = line.metrics()
        var boxes: [PositionedInlineBox] = []
        for item in line.items() {
            if case .inlineBox(let b) = item, (b.id & PILL_BOX) != 0 {
                boxes.append(b)
            }
        }

        // Pills whose chip starts on this line, then those whose label wrapped onto it.
        var starts: [(Int, PositionedInlineBox?)] = []
        for b in boxes where (b.id & 1) == 0 {
            let pillIdx = Int((b.id & ~PILL_BOX) >> 1)
            starts.append((pillIdx, b))
        }
        let textRange = line.textRange()
        for (i, p) in pills.enumerated() {
            let inside = Int(p.start) < textRange.lowerBound && textRange.lowerBound < Int(p.end)
            if inside && !starts.contains(where: { $0.0 == i }) {
                starts.append((i, nil))
            }
        }

        let lineEnd = m.inlineMinCoord + m.offset + m.advance - m.hangingAdvance
        for (i, leadOpt) in starts {
            guard i >= 0 && i < pills.count else { continue }
            let pill = pills[i]
            let id = PILL_BOX | (UInt64(i) << 1)
            let trail = boxes.first { $0.id == (id | 1) }

            var asc: Float = 0.0
            var desc: Float = 0.0
            var grX0: Float = .infinity
            var grX1: Float = -.infinity
            for item in line.items() {
                if case .glyphRun(let gr) = item {
                    let r = gr.textRange
                    if r.lowerBound < Int(pill.end) && Int(pill.start) < r.upperBound {
                        let fm = gr.fontMetrics
                        asc = max(asc, fm.ascent)
                        desc = max(desc, abs(fm.descent))
                        grX0 = min(grX0, gr.offset())
                        grX1 = max(grX1, gr.offset() + gr.advance())
                    }
                }
            }

            let margin = pm.margin * scale
            let pad = pm.pad * scale

            guard let lead = leadOpt else {
                // A label carried on from the line above: its chip runs from the line's start,
                // flush with the label (no room was made before it), to its trail, or on to the
                // line's end if it wraps again.
                if grX0 > grX1 {
                    continue
                }
                let x1Base: Float
                if let t = trail, abs(t.x - grX1) < 1.0 {
                    x1Base = t.x + t.width - margin
                } else {
                    x1Base = grX1 + pad
                }
                let x1 = (trail == nil) ? lineEnd : x1Base
                let base = oy + m.baseline
                let top = (base - asc - 1.0 * scale).rounded(.toNearestOrAwayFromZero)
                let bot = (base + desc + 1.0 * scale).rounded(.toNearestOrAwayFromZero)
                let x0 = min(grX0, m.inlineMinCoord + m.offset)
                let rectW = max(0.0, x1 - x0).rounded(.toNearestOrAwayFromZero)
                let rectH = bot - top
                let rect: [Float] = [(ox + x0).rounded(.toNearestOrAwayFromZero), top, rectW, rectH]
                out.append(PaintedDeco(
                    deco: Deco(rect: rect, color: pill.bg ?? bg, radius: min(5.0 * scale, rectH * 0.5)),
                    ring: nil,
                    byte: 0
                ))
                continue
            }

            let rtlLead = grX0 <= grX1 && abs(lead.x - grX1) < 1.0
            let x0: Float
            if grX0 <= grX1 {
                if rtlLead {
                    x0 = grX0 - pad
                } else {
                    x0 = max(grX0 - (lead.width - margin), lead.x + margin)
                }
            } else {
                x0 = lead.x + margin
            }

            let x1: Float
            if grX0 <= grX1 {
                if let t = trail, abs(t.x - grX1) < 1.0 {
                    x1 = t.x + t.width - margin
                } else if rtlLead {
                    x1 = lead.x + lead.width - margin
                } else if trail == nil {
                    x1 = lineEnd
                } else {
                    x1 = grX1 + pad
                }
            } else {
                x1 = trail.map { $0.x + $0.width - margin } ?? lineEnd
            }

            if asc == 0.0 {
                asc = size * scale * 0.95
                desc = size * scale * 0.25
            }
            let base = oy + m.baseline
            let top = (base - asc - 1.0 * scale).rounded(.toNearestOrAwayFromZero)
            let bot = (base + desc + 1.0 * scale).rounded(.toNearestOrAwayFromZero)
            let rectW = max(0.0, x1 - x0).rounded(.toNearestOrAwayFromZero)
            let rectH = bot - top
            let rect: [Float] = [(ox + x0).rounded(.toNearestOrAwayFromZero), top, rectW, rectH]
            out.append(PaintedDeco(
                deco: Deco(rect: rect, color: pill.bg ?? bg, radius: min(5.0 * scale, rectH * 0.5)),
                ring: nil,
                byte: 0
            ))

            if let ic = pill.icon {
                let px = max((pm.icon * scale).rounded(.toNearestOrAwayFromZero), 1.0)
                let ix = rtlLead ? (rect[0] + rect[2] - pm.pad * scale - px) : (rect[0] + pm.pad * scale)
                let iy = ((top + bot - px) * 0.5).rounded(.toNearestOrAwayFromZero)
                icons.append((ic, UInt32(px), [ix.rounded(.toNearestOrAwayFromZero), iy], pill.fg))
            }
        }
    }
}
