// Ported from: crates/rune/src/text/decorations.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rects drawn under or over text: span backgrounds, underlines, strikethroughs, highlights
//! and link rings.

/// A rect drawn under or over text: span backgrounds and underlines (device px).
public struct Deco: Sendable, Equatable {
    public var rect: [Float]
    public var color: Color
    public var radius: Float

    public init(rect: [Float], color: Color, radius: Float) {
        self.rect = rect
        self.color = color
        self.radius = radius
    }
}

/// Internal paint metadata: keeps the public `Deco` representation unchanged while carrying
/// optional inset border ring and trailing source byte offset for streaming reveal.
struct PaintedDeco: Sendable, Equatable {
    var deco: Deco
    var ring: (Color, Float)?
    var byte: UInt32

    init(deco: Deco, ring: (Color, Float)? = nil, byte: UInt32 = 0) {
        self.deco = deco
        self.ring = ring
        self.byte = byte
    }

    var rect: [Float] {
        get { deco.rect }
        set { deco.rect = newValue }
    }

    var color: Color {
        get { deco.color }
        set { deco.color = newValue }
    }

    var radius: Float {
        get { deco.radius }
        set { deco.radius = newValue }
    }

    static func == (lhs: PaintedDeco, rhs: PaintedDeco) -> Bool {
        guard lhs.deco == rhs.deco, lhs.byte == rhs.byte else { return false }
        switch (lhs.ring, rhs.ring) {
        case (.none, .none):
            return true
        case (.some(let a), .some(let b)):
            return a.0 == b.0 && a.1 == b.1
        default:
            return false
        }
    }
}

private protocol DecorationOutput {
    init(deco: Deco, ring: (Color, Float)?, byte: UInt32)
    var decoRef: Deco { get set }
    var ringValue: (Color, Float)? { get }
    mutating func extendTo(_ byte: UInt32)
}

extension Deco: DecorationOutput {
    init(deco: Deco, ring: (Color, Float)?, byte: UInt32) {
        _ = (ring, byte)
        self = deco
    }
    var decoRef: Deco {
        get { self }
        set { self = newValue }
    }
    var ringValue: (Color, Float)? { nil }
    mutating func extendTo(_ byte: UInt32) { _ = byte }
}

extension PaintedDeco: DecorationOutput {
    var decoRef: Deco {
        get { deco }
        set { deco = newValue }
    }
    var ringValue: (Color, Float)? { ring }
    mutating func extendTo(_ byte: UInt32) {
        self.byte = max(self.byte, byte)
    }
}

private func ringsEqual(_ a: (Color, Float)?, _ b: (Color, Float)?) -> Bool {
    switch (a, b) {
    case (.none, .none): return true
    case (.some(let x), .some(let y)): return x.0 == y.0 && x.1 == y.1
    default: return false
    }
}

extension TextSystem {
    /// Backgrounds and underlines for `spans` (device px, layout top-left at `origin`). Touching
    /// runs with the same background merge into one rounded rect.
    public func decorations(
        _ layout: TextLayout,
        _ spans: [Span],
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [Deco]
    ) {
        decorationsInto(layout, spans, [], scale, origin, &out)
    }

    /// `decorations`, plus inset border `rings` (`(startByte, endByte, color, widthPt)`).
    func decorationsWithRings(
        _ layout: TextLayout,
        _ spans: [Span],
        _ rings: [(UInt32, UInt32, Color, Float)],
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [PaintedDeco]
    ) {
        decorationsInto(layout, spans, rings, scale, origin, &out)
    }

    private func decorationsInto<D: DecorationOutput>(
        _ layout: TextLayout,
        _ spans: [Span],
        _ rings: [(UInt32, UInt32, Color, Float)],
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [D]
    ) {
        if spans.allSatisfy({ $0.bg == nil && $0.underline == nil }) {
            return
        }
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let radius = 4.0 * scale
        var lastBg: Int? = nil

        for line in layout.lines() {
            let m = line.metrics()
            for item in line.items() {
                guard case .glyphRun(let gr) = item else { continue }
                let ink = gr.ink.rawValue
                if ink == 0 {
                    continue
                }
                let spanIdx = Int(ink) - 1
                guard spanIdx >= 0 && spanIdx < spans.count else { continue }
                let s = spans[spanIdx]
                let x0 = ox + gr.offset()
                let w = gr.advance()

                if let bg = s.bg {
                    let sStart = UInt32(clamping: max(s.start, 0))
                    let sEnd = UInt32(clamping: max(s.end, 0))
                    var ring: (Color, Float)? = nil
                    for (ra, rb, rc, rw) in rings.reversed() {
                        if rw > 0.0 && ra < sEnd && sStart < rb {
                            ring = (rc, rw * scale)
                            break
                        }
                    }
                    let pad = s.bgPad * scale
                    let cap = gr.fontMetrics.capHeight ?? (gr.fontSize * 0.7)
                    let base = oy + m.baseline
                    let top = (base - cap * 1.35).rounded(.toNearestOrAwayFromZero)
                    let bot = (base + cap * 0.55).rounded(.toNearestOrAwayFromZero)
                    let l = (x0 - pad).rounded(.toNearestOrAwayFromZero)
                    let r = (x0 + w + pad).rounded(.toNearestOrAwayFromZero)
                    let rect: [Float] = [l, top, r - l, bot - top]
                    let endByte = min(UInt32(clamping: gr.textRange.upperBound), sEnd)
                    let byte = endByte > 0 ? (endByte - 1) : 0

                    let shouldMerge: Bool
                    if let idx = lastBg {
                        let d = out[idx].decoRef
                        let oldRing = out[idx].ringValue
                        shouldMerge = d.color == bg
                            && ringsEqual(oldRing, ring)
                            && abs(d.radius - radius) < 1e-3
                            && d.rect[1] < bot
                            && top < d.rect[1] + d.rect[3]
                            && abs(d.rect[0] + d.rect[2] - rect[0] - 2.0 * pad) < 1.5
                    } else {
                        shouldMerge = false
                    }

                    if shouldMerge, let idx = lastBg {
                        var d = out[idx].decoRef
                        if rect[2] > d.rect[2] {
                            d.rect[1] = rect[1]
                            d.rect[3] = rect[3]
                        }
                        d.rect[2] = rect[0] + rect[2] - d.rect[0]
                        out[idx].decoRef = d
                        out[idx].extendTo(byte)
                    } else {
                        lastBg = out.count
                        out.append(D(deco: Deco(rect: rect, color: bg, radius: radius), ring: ring, byte: byte))
                    }
                }

                if let uc = s.underline, uc.a > 0.0 {
                    let y = (oy + m.baseline + 2.0 * scale).rounded(.toNearestOrAwayFromZero)
                    let (l, r) = underlineEdges(line, ox, gr.offset(), gr.offset() + w)
                    out.append(D(
                        deco: Deco(rect: [l, y, r - l, max(scale, 1.0)], color: uc, radius: 0.0),
                        ring: nil,
                        byte: 0
                    ))
                }
            }
        }
    }

    /// Strikethrough lines for `strikes` (`(startByte, endByte, color)`) in device px.
    func strikeDecorations(
        _ layout: TextLayout,
        _ spans: [Span],
        _ strikes: [(UInt32, UInt32, Color?)],
        _ defaultColor: Color,
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [PaintedDeco]
    ) {
        if strikes.isEmpty {
            return
        }
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        for (sStart, sEnd, sc) in strikes {
            let a = Int(sStart)
            let b = Int(sEnd)
            if a >= b {
                continue
            }
            let spanColor = sc ?? spans.first(where: { $0.start <= a && b <= $0.end && $0.color != nil })?.color
            let color = spanColor ?? defaultColor
            for (bb, lineIdx) in rangeBoxes(layout, a, b, false) {
                let w = Float(bb.x1 - bb.x0)
                if w <= 0.0 {
                    continue
                }
                guard let line = layout.get(lineIdx) else { continue }
                let m = line.metrics()
                var strikeOff = m.lineHeight * 0.25
                var h = max(scale.rounded(.toNearestOrAwayFromZero), 1.0)
                for item in line.items() {
                    if case .glyphRun(let gr) = item {
                        let fm = gr.fontMetrics
                        strikeOff = (fm.strikethroughOffset != 0.0) ? fm.strikethroughOffset : (fm.ascent * 0.32)
                        h = max(max(fm.strikethroughSize, scale).rounded(.toNearestOrAwayFromZero), 1.0)
                        break
                    }
                }
                let x0 = ox + Float(bb.x0)
                let y = (oy + m.baseline - strikeOff).rounded(.toNearestOrAwayFromZero)
                out.append(PaintedDeco(deco: Deco(rect: [x0, y, w, h], color: color, radius: 0.0), ring: nil, byte: 0))
            }
        }
    }

    /// Rounded background fills and rings for `highlights` in device px.
    func highlightDecorations(
        _ layout: TextLayout,
        _ highlights: [TextHighlight],
        _ len: Int,
        _ scale: Float,
        _ origin: [Float],
        _ out: inout [PaintedDeco]
    ) {
        if highlights.isEmpty {
            return
        }
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let radius = 4.0 * scale

        for h in highlights {
            let a = min(Int(h.start), len)
            let b = min(Int(h.end), len)
            if a >= b || (h.bg.a <= 0.0 && h.ringValue == nil) {
                continue
            }
            let pad = h.padValue * scale
            let ring = h.ringValue.map { ($0.0, $0.1 * scale) }
            var last: (Int, Int)? = nil

            for (bb, lineIdx) in rangeBoxes(layout, a, b, false) {
                let w = Float(bb.x1 - bb.x0)
                if w <= 0.0 {
                    continue
                }
                let x0 = ox + Float(bb.x0)
                var top = (oy + Float(bb.y0)).rounded(.toNearestOrAwayFromZero)
                var bot = (oy + Float(bb.y1)).rounded(.toNearestOrAwayFromZero)
                if let l = layout.get(lineIdx) {
                    let base = oy + l.metrics().baseline
                    var asc: Float = 0.0
                    var desc: Float = 0.0
                    for run in l.runs() {
                        let r = run.textRange
                        if r.lowerBound < b && a < r.upperBound {
                            let fm = run.fontMetrics
                            asc = max(asc, fm.ascent)
                            desc = max(desc, abs(fm.descent))
                        }
                    }
                    if asc > 0.0 || desc > 0.0 {
                        top = (base - asc - 1.0 * scale).rounded(.toNearestOrAwayFromZero)
                        bot = (base + desc + 1.0 * scale).rounded(.toNearestOrAwayFromZero)
                    }
                }
                let rect: [Float] = [x0 - pad, top, w + 2.0 * pad, max(0.0, bot - top)]
                let shouldMerge: Bool
                if let (li, k) = last, li == lineIdx {
                    let d = out[k].deco
                    shouldMerge = abs(d.rect[0] + d.rect[2] - rect[0] - 2.0 * pad) < 1.0
                } else {
                    shouldMerge = false
                }
                if shouldMerge, let (_, k) = last {
                    if rect[3] > out[k].deco.rect[3] {
                        out[k].deco.rect[1] = rect[1]
                        out[k].deco.rect[3] = rect[3]
                    }
                    out[k].deco.rect[2] = rect[0] + rect[2] - out[k].deco.rect[0]
                } else {
                    last = (lineIdx, out.count)
                    let endByte = b > 0 ? UInt32(b - 1) : 0
                    out.append(PaintedDeco(deco: Deco(rect: rect, color: h.bg, radius: radius), ring: ring, byte: endByte))
                }
            }
        }
    }
}
