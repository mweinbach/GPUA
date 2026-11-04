// Ported from: crates/rune-mermaid/src/sequence_draw.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Sequence diagram drawing: participants across the top, events down the page.

import Rune

enum sequenceDraw {
    private static let BAR: Float = 10.0

    private struct Frame {
        var kind: Measured?
        var label: Measured
        var fill: Color?
        var top: Float
        var dividers: [(Float, Measured)]
        var x: [Float]
    }

    static func draw(_ s: sequence.Sequence, _ paint: DiagramStyle) -> Scene? {
        let font = paint.font
        var small = font
        small.size -= 1.0
        small.lineHeight -= 2.0
        var bold = small
        bold.weight = 600.0
        var numFont = font
        numFont.size = 10.0
        numFont.lineHeight = 12.0
        numFont.weight = 600.0

        let n = s.participants.count
        guard n > 0 else { return nil }
        let heads: [Measured] = s.participants.map { measure($0.label, font) }
        let boxes: [[Float]] = zip(s.participants, heads).map { (p, m) in headSize(p.kind, m.size) }
        let boxTitles: [Measured] = s.boxes.map { measure($0.title, bold) }
        let boxLead: Float
        if s.boxes.isEmpty {
            boxLead = 0.0
        } else {
            var th: Float = 0.0
            for t in boxTitles { th = max(th, t.size[1]) }
            boxLead = th > 0.0 ? th + 18.0 : 10.0
        }
        var maxHeadH: Float = 0.0
        for b in boxes { maxHeadH = max(maxHeadH, b[1]) }
        let topH = boxLead + maxHeadH

        let texts: [Measured?] = s.events.map { e in
            switch e {
            case .message(let m):
                return measure(m.text, small)
            case .note(_, let t):
                return measure(t, small)
            case .open(_, let t, _), .else(let t):
                return measure(t.isEmpty ? "" : "[\(t)]", small)
            default:
                return nil
            }
        }
        func widthOf(_ i: Int) -> Float {
            texts[i]?.size[0] ?? 0.0
        }

        let numRoom: Float = s.autonumber ? 20.0 : 0.0
        var need: [(Int, Int, Float)] = []
        for (i, e) in s.events.enumerated() {
            switch e {
            case .message(let m) where m.from != m.to:
                need.append((min(m.from, m.to), max(m.from, m.to), widthOf(i) + 32.0 + numRoom))
            case .message(let m) where m.from + 1 < n:
                need.append((m.from, m.from + 1, widthOf(i) + 48.0))
            case .note(.right(let a), _) where a + 1 < n:
                need.append((a, a + 1, widthOf(i) + 40.0))
            case .note(.left(let a), _) where a > 0:
                need.append((a - 1, a, widthOf(i) + 40.0))
            default:
                break
            }
        }
        var cx = [Float](
            repeating: boxes[0][0] / 2.0 + (s.participants[0].group != nil ? 10.0 : 0.0),
            count: n
        )
        if n > 1 {
            for j in 1..<n {
                let boundaryGap: Float = s.participants[j - 1].group != s.participants[j].group ? 20.0 : 0.0
                cx[j] = cx[j - 1] + (boxes[j - 1][0] + boxes[j][0]) / 2.0 + 24.0 + boundaryGap
                for (a, b, d) in need where b == j {
                    cx[j] = max(cx[j], cx[a] + d)
                }
            }
        }

        var groupsBg = Canvas()
        var back = Canvas()
        var lifelines = Canvas()
        var bars = Canvas()
        var front = Canvas()
        var tops = Canvas()
        var tabs = Canvas()
        var active: [[Float]] = Array(repeating: [], count: n)
        var frames: [Frame] = []
        var y = topH + 20.0
        var number: (UInt32, UInt32)? = nil
        // Where each lifeline starts and ends, and who goes at their next message.
        var starts = [Float](repeating: topH, count: n)
        var ends: [Float?] = Array(repeating: nil, count: n)
        var doomed: [Int] = []

        func edgeX(_ i: Int, _ right: Bool) -> Float {
            let d = active[i].count
            if d == 0 {
                return cx[i]
            } else {
                return cx[i] + Float(d - 1) * 4.0 + (right ? BAR / 2.0 : -BAR / 2.0)
            }
        }

        func closeBar(_ i: Int, _ yAt: Float) {
            let d = active[i].count
            if let top = active[i].popLast() {
                let x = cx[i] + Float(d - 1) * 4.0
                let k = bars.marks.count
                bars.part(.key(.frame, "bar\(k)"))
                bars.shape(
                    roundedRect(x - BAR / 2.0, top, x + BAR / 2.0, max(yAt, top + 8.0), 1.0),
                    paint.nodeFill,
                    paint.nodeBorder,
                    1.0
                )
            }
        }

        func touch(_ x0: Float, _ x1: Float) {
            for idx in 0..<frames.count {
                frames[idx].x = [min(frames[idx].x[0], x0), max(frames[idx].x[1], x1)]
            }
        }

        for (i, e) in s.events.enumerated() {
            switch e {
            case .message(let m):
                front.part(.key(.edge, "m\(i)"))
                let t = texts[i] ?? Measured()
                if m.activate {
                    active[m.to].append(y + t.size[1] + 6.0)
                }
                let lineY: Float
                if m.from == m.to {
                    let x = edgeX(m.from, true)
                    front.labelAt(t, [x + 8.0, y], small, paint.muted, .start)
                    lineY = y + t.size[1] + 6.0
                    let pts: [[Float]] = [
                        [x, lineY],
                        [x + 30.0, lineY],
                        [x + 30.0, lineY + 18.0],
                        [x + 2.0 + tipLen(m.tip), lineY + 18.0],
                    ]
                    strokeLine(&front, pts, m.dotted, paint)
                    drawTip(&front, m.tip, [x, lineY + 18.0], [-1.0, 0.0], paint)
                    touch(cx[m.from] - BAR, max(x + 30.0, x + 8.0 + t.size[0]))
                    y = lineY + 18.0 + 16.0
                } else {
                    let right = m.to > m.from
                    let sx = edgeX(m.from, right)
                    let ex = edgeX(m.to, !right)
                    let dir: Float = right ? 1.0 : -1.0
                    let mid = (sx + ex) / 2.0
                    let hasText = !t.text.isEmpty
                    front.label(t, [mid, y + t.size[1] / 2.0], small, paint.muted, .center)
                    lineY = y + (hasText ? t.size[1] + 6.0 : 4.0)
                    let a = m.both ? sx + dir * tipLen(m.tip) : sx
                    strokeLine(&front, [[a, lineY], [ex - dir * tipLen(m.tip), lineY]], m.dotted, paint)
                    drawTip(&front, m.tip, [ex, lineY], [dir, 0.0], paint)
                    if m.both {
                        drawTip(&front, m.tip, [sx, lineY], [-dir, 0.0], paint)
                    }
                    if let (k, step) = number {
                        let mNum = measure("\(k)", numFont)
                        let rx = max(mNum.size[0] / 2.0 + 4.0, 8.0)
                        front.shape(
                            roundedRect(sx - rx, lineY - 8.0, sx + rx, lineY + 8.0, 8.0),
                            paint.line,
                            paint.line,
                            1.0
                        )
                        front.label(mNum, [sx, lineY], numFont, paint.surface, .center)
                        let (nextK, over) = k.addingReportingOverflow(step)
                        number = (over ? UInt32.max : nextK, step)
                    }
                    let lo = min(cx[m.from], cx[m.to]) - BAR
                    let hi = max(cx[m.from], cx[m.to]) + BAR
                    touch(min(lo, mid - t.size[0] / 2.0), max(hi, mid + t.size[0] / 2.0))
                    y = lineY + 16.0
                }
                if m.deactivate {
                    closeBar(m.from, lineY)
                }
                let endY = m.from == m.to ? lineY + 18.0 : lineY
                var remainingDoomed: [Int] = []
                for d in doomed {
                    if d == m.from || d == m.to {
                        ends[d] = endY + 14.0
                        drawCross(&front, [cx[d], endY + 14.0], paint)
                        y = max(y, endY + 30.0)
                    } else {
                        remainingDoomed.append(d)
                    }
                }
                doomed = remainingDoomed
            case .create(let a):
                let w = boxes[a][0]
                let h = boxes[a][1]
                let top = y
                tops.part(.key(.node, "p\(a)"))
                drawHead(&tops, s.participants[a].kind, heads[a], [cx[a], top], [w, h], paint)
                starts[a] = top + h
                touch(cx[a] - w / 2.0, cx[a] + w / 2.0)
                y = top + h + 14.0
            case .destroy(let a):
                doomed.append(a)
            case .number(let on):
                number = on
            case .note(let pos, _):
                let t = texts[i] ?? Measured()
                let w = t.size[0] + 20.0
                let x0: Float
                let x1: Float
                switch pos {
                case .left(let a):
                    x0 = cx[a] - 12.0 - w
                    x1 = cx[a] - 12.0
                case .right(let a):
                    x0 = cx[a] + 12.0
                    x1 = cx[a] + 12.0 + w
                case .over(let a, let b):
                    let span = max(cx[b] - cx[a] + 40.0, w)
                    let mid = (cx[a] + cx[b]) / 2.0
                    x0 = mid - span / 2.0
                    x1 = mid + span / 2.0
                }
                let h = t.size[1] + 14.0
                y += 2.0
                front.part(.key(.node, "note\(i)"))
                front.shape(roundedRect(x0, y, x1, y + h, 2.0), paint.noteFill, paint.noteBorder, 1.0)
                front.label(t, [(x0 + x1) / 2.0, y + h / 2.0], small, paint.text, .center)
                touch(x0, x1)
                y += h + 14.0
            case .activate(let a):
                active[a].append(y - 8.0)
            case .deactivate(let a):
                closeBar(a, y - 8.0)
            case .open(let kind, _, let fill):
                let label = texts[i] ?? Measured()
                let kindM = kind.map { measure($0, bold) }
                let h: Float
                if let k = kindM {
                    h = max(k.size[1], label.size[1]) + 14.0
                } else {
                    h = fill != nil ? 8.0 : 0.0
                }
                frames.append(
                    Frame(
                        kind: kindM,
                        label: label,
                        fill: fill,
                        top: y,
                        dividers: [],
                        x: [.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
                    )
                )
                y += h
            case .else:
                let label = texts[i] ?? Measured()
                let h = label.size[1] + 14.0
                if !frames.isEmpty {
                    frames[frames.count - 1].dividers.append((y, label))
                }
                y += h
            case .end:
                guard var f = frames.popLast() else { continue }
                if f.x[0] > f.x[1] {
                    f.x = [cx[0], cx[n - 1]]
                }
                let x0 = f.x[0] - 12.0
                let tabW: Float = f.kind.map { $0.size[0] + 18.0 } ?? 0.0
                let x1 = max(f.x[1] + 12.0, x0 + tabW + f.label.size[0] + 20.0)
                let bottom = y - 4.0
                let key = "frame\(back.marks.count)"
                back.part(.key(.frame, key))
                tabs.part(.key(.frame, key))
                if let kindM = f.kind {
                    let th = max(kindM.size[1], f.label.size[1]) + 6.0
                    back.stroke([[x0, f.top], [x1, f.top], [x1, bottom], [x0, bottom]], true, 1.0, paint.nodeBorder)
                    let tab: [[Float]] = [
                        [x0, f.top],
                        [x0 + tabW, f.top],
                        [x0 + tabW, f.top + th - 6.0],
                        [x0 + tabW - 6.0, f.top + th],
                        [x0, f.top + th],
                    ]
                    tabs.shape(tab, paint.nodeFill, paint.nodeBorder, 1.0)
                    tabs.labelAt(kindM, [x0 + 9.0, f.top + 3.0], bold, paint.text, .start)
                    tabs.labelAt(f.label, [x0 + tabW + 8.0, f.top + 3.0], small, paint.muted, .start)
                    for (dy, divLabel) in f.dividers {
                        back.dashed([[x0, dy], [x1, dy]], 1.0, paint.nodeBorder, 4.0, 3.0)
                        tabs.labelAt(divLabel, [x0 + 9.0, dy + 4.0], small, paint.muted, .start)
                    }
                } else if let rectCol = f.fill {
                    let band = adaptFill(paint.surface, rectCol, 0.04, 0.03).alpha(0.55)
                    back.fill(roundedRect(x0, f.top - 2.0, x1, bottom, 4.0), band)
                }
                touch(x0, x1)
                y = bottom + 16.0
            }
        }
        let end = y + 4.0
        for a in 0..<n {
            while !active[a].isEmpty {
                closeBar(a, end - 8.0)
            }
        }

        // Participant `box` columns behind everything else.
        let boxBorder = groupBorder(paint)
        for (bIdx, b) in s.boxes.enumerated() {
            let members: [Int] = (0..<n).filter { s.participants[$0].group == bIdx }
            guard let first = members.first, let last = members.last else { continue }
            var x0 = cx[first] - boxes[first][0] / 2.0 - 10.0
            var x1 = cx[last] + boxes[last][0] / 2.0 + 10.0
            let title = boxTitles[bIdx]
            if x1 - x0 < title.size[0] + 20.0 {
                let mid = (x0 + x1) / 2.0
                x0 = mid - title.size[0] / 2.0 - 10.0
                x1 = mid + title.size[0] / 2.0 + 10.0
            }
            let fill = b.color.map { adaptFill(paint.surface, $0, 0.035, 0.03) } ?? paint.clusterFill
            groupsBg.part(.key(.frame, "box\(bIdx)"))
            groupsBg.shape(roundedRect(x0, 0.0, x1, end + maxHeadH + 10.0, 6.0), fill, boxBorder, 1.0)
            groupsBg.label(title, [(x0 + x1) / 2.0, 7.0 + title.size[1] / 2.0], bold, paint.muted, .center)
        }

        let created: [Bool] = (0..<n).map { i in
            s.events.contains { e in
                if case .create(let a) = e { return a == i }
                return false
            }
        }
        for (i, p) in s.participants.enumerated() {
            let size = boxes[i]
            let stop = ends[i] ?? end
            lifelines.part(.key(.frame, "life\(i)"))
            lifelines.stroke([[cx[i], starts[i]], [cx[i], stop]], false, 1.0, paint.nodeBorder)
            if !created[i] {
                tops.part(.key(.node, "p\(i)"))
                drawHead(&tops, p.kind, heads[i], [cx[i], topH - size[1]], size, paint)
            }
            if ends[i] == nil {
                tops.part(.key(.node, "p\(i).end"))
                drawHead(&tops, p.kind, heads[i], [cx[i], end], size, paint)
            }
        }

        var c = groupsBg
        for layer in [back, lifelines, bars, tabs, front, tops] {
            c.append(layer)
        }
        return c.finishFit(paint)
    }

    private static func tipLen(_ t: sequence.Tip) -> Float {
        switch t {
        case .filled: return 8.0
        case .none, .open, .cross: return 0.0
        }
    }

    private static func strokeLine(_ c: inout Canvas, _ pts: [[Float]], _ dotted: Bool, _ paint: DiagramStyle) {
        if dotted {
            c.dashed(pts, 1.25, paint.line, 4.0, 3.0)
        } else {
            c.stroke(pts, false, 1.25, paint.line)
        }
    }

    private static func drawTip(
        _ c: inout Canvas,
        _ t: sequence.Tip,
        _ at: [Float],
        _ d: [Float],
        _ paint: DiagramStyle
    ) {
        func back(_ by: Float, _ side: Float) -> [Float] {
            [at[0] - d[0] * by - d[1] * side, at[1] - d[1] * by + d[0] * side]
        }
        switch t {
        case .none:
            break
        case .filled:
            c.fill(arrowhead(at, d, 9.0, 8.0), paint.line)
        case .open:
            c.stroke([back(8.0, 4.5), at, back(8.0, -4.5)], false, 1.25, paint.line)
        case .cross:
            c.stroke([back(9.0, 4.0), back(1.0, -4.0)], false, 1.5, paint.line)
            c.stroke([back(9.0, -4.0), back(1.0, 4.0)], false, 1.5, paint.line)
        }
    }

    private static func headSize(_ kind: sequence.Kind, _ t: [Float]) -> [Float] {
        switch kind {
        case .box: return [max(t[0] + 24.0, 72.0), t[1] + 16.0]
        case .actor: return [max(t[0], 40.0), 40.0 + t[1]]
        case .boundary, .control, .entity: return [max(t[0], 44.0), 36.0 + t[1]]
        case .database: return nodeSize(.cylinder, t)
        case .collections: return nodeSize(.stackedRect, t)
        case .queue: return nodeSize(.hCylinder, t)
        }
    }

    /// A participant's head, `size` wide and tall, its top centre at `top`.
    private static func drawHead(
        _ c: inout Canvas,
        _ kind: sequence.Kind,
        _ label: Measured,
        _ top: [Float],
        _ size: [Float],
        _ paint: DiagramStyle
    ) {
        let x = top[0]
        let y = top[1]
        let w = size[0]
        let h = size[1]
        func ring(_ c: inout Canvas, _ at: [Float], _ r: Float) {
            c.shape(ellipse(at, r, r), paint.nodeFill, paint.line, 1.25)
        }
        func under(_ c: inout Canvas, _ glyph: Float) {
            c.label(label, [x, y + glyph + label.size[1] / 2.0], paint.font, paint.text, .center)
        }
        let colors = [paint.nodeFill, paint.nodeBorder, paint.text]
        switch kind {
        case .box:
            c.shape(roundedRect(x - w / 2.0, y, x + w / 2.0, y + h, 4.0), paint.nodeFill, paint.nodeBorder, 1.0)
            c.label(label, [x, y + h / 2.0], paint.font, paint.text, .center)
        case .actor:
            drawActor(&c, top, paint)
            under(&c, 40.0)
        case .boundary:
            ring(&c, [x + 5.0, y + 15.0], 11.0)
            c.stroke([[x - 14.0, y + 4.0], [x - 14.0, y + 26.0]], false, 1.25, paint.line)
            c.stroke([[x - 14.0, y + 15.0], [x - 6.0, y + 15.0]], false, 1.25, paint.line)
            under(&c, 36.0)
        case .control:
            ring(&c, [x, y + 17.0], 12.0)
            c.stroke([[x + 4.0, y + 1.0], [x - 1.0, y + 5.0], [x + 4.0, y + 9.0]], false, 1.25, paint.line)
            under(&c, 36.0)
        case .entity:
            ring(&c, [x, y + 14.0], 12.0)
            c.stroke([[x - 12.0, y + 29.0], [x + 12.0, y + 29.0]], false, 1.25, paint.line)
            under(&c, 36.0)
        case .database:
            drawShape(&c, .cylinder, label, [x, y + h / 2.0], size, colors, paint)
        case .collections:
            drawShape(&c, .stackedRect, label, [x, y + h / 2.0], size, colors, paint)
        case .queue:
            drawShape(&c, .hCylinder, label, [x, y + h / 2.0], size, colors, paint)
        }
    }

    /// The X that ends a destroyed participant's lifeline.
    private static func drawCross(_ c: inout Canvas, _ at: [Float], _ paint: DiagramStyle) {
        let x = at[0]
        let y = at[1]
        c.stroke([[x - 7.0, y - 7.0], [x + 7.0, y + 7.0]], false, 2.0, paint.line)
        c.stroke([[x - 7.0, y + 7.0], [x + 7.0, y - 7.0]], false, 2.0, paint.line)
    }

    private static func drawActor(_ c: inout Canvas, _ top: [Float], _ paint: DiagramStyle) {
        let x = top[0]
        let y = top[1]
        c.shape(ellipse([x, y + 7.0], 7.0, 7.0), paint.nodeFill, paint.line, 1.25)
        c.stroke([[x, y + 14.0], [x, y + 26.0]], false, 1.25, paint.line)
        c.stroke([[x - 10.0, y + 18.0], [x + 10.0, y + 18.0]], false, 1.25, paint.line)
        c.stroke([[x - 8.0, y + 36.0], [x, y + 26.0], [x + 8.0, y + 36.0]], false, 1.25, paint.line)
    }
}
