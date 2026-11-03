// Ported from: crates/rune/src/text/cursor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Caret and selection geometry on a laid-out paragraph: cursor rects, hit testing, line
//! edges and moves, and selection boxes.

/// Which side of a cluster boundary a cursor associates with.
public enum TextAffinity: Sendable, Equatable, Hashable {
    case upstream
    case downstream
}

/// Axis-aligned bounding box in layout device pixels (`Double` precision matching Parley `BoundingBox`).
public struct TextBoundingBox: Sendable, Equatable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    public init(x0: Double = 0, y0: Double = 0, x1: Double = 0, y1: Double = 0) {
        self.x0 = x0
        self.y0 = y0
        self.x1 = x1
        self.y1 = y1
    }

    public func width() -> Double { x1 - x0 }
    public func height() -> Double { y1 - y0 }
}

/// Caret position in a `TextLayout` (`byte` index + `affinity`).
public struct TextCursor: Sendable, Equatable {
    public var index: Int
    public var affinity: TextAffinity

    public init(index: Int, affinity: TextAffinity = .downstream) {
        self.index = index
        self.affinity = affinity
    }

    public static func fromByteIndex(
        _ layout: TextLayout,
        _ index: Int,
        _ affinity: TextAffinity
    ) -> TextCursor {
        let clamped = min(max(index, 0), layout.byteLen)
        return TextCursor(index: clamped, affinity: affinity)
    }

    public static func fromPoint(_ layout: TextLayout, _ x: Float, _ y: Float) -> TextCursor {
        cursorFromPoint(layout, x, y)
    }

    public func geometry(_ layout: TextLayout, _ size: Float) -> TextBoundingBox {
        cursorGeometry(self, layout, size)
    }
}

private struct ResolvedCluster {
    var lineIdx: Int
    var line: LayoutLine
    var cluster: PositionedCluster
    /// Layout-space left x (`inlineMinCoord + cluster.visualOffset`).
    var layoutX: Float
}

private func collectVisualClusters(_ layout: TextLayout) -> [ResolvedCluster] {
    var out: [ResolvedCluster] = []
    for (lineIdx, line) in layout.lines().enumerated() {
        let inlineMin = line.metrics().inlineMinCoord
        for run in line.runs() {
            for cl in run.visualClusters() {
                out.append(ResolvedCluster(
                    lineIdx: lineIdx,
                    line: line,
                    cluster: cl,
                    layoutX: inlineMin + cl.visualOffset
                ))
            }
        }
    }
    return out
}

/// Find the cluster containing `byteIdx` (in logical byte order), if any.
func clusterFromByteIndex(_ layout: TextLayout, _ byteIdx: Int) -> (LayoutLine, PositionedCluster, Float)? {
    for line in layout.lines() {
        let inlineMin = line.metrics().inlineMinCoord
        for run in line.runs() {
            for cl in run.visualClusters() {
                if cl.textRange.contains(byteIdx) {
                    return (line, cl, inlineMin + cl.visualOffset)
                }
            }
        }
    }
    return nil
}

/// Caret bounding box for `cursor` on `layout` with caret width `size` (device px), accounting
/// for paragraph block indentation (`inlineMinCoord`) and pill chip edges.
func cursorGeometry(_ cursor: TextCursor, _ layout: TextLayout, _ size: Float) -> TextBoundingBox {
    let lines = layout.lines()
    guard !lines.isEmpty else {
        return TextBoundingBox(x0: 0, y0: 0, x1: Double(size), y1: Double(layout.height()))
    }

    let at = min(max(cursor.index, 0), layout.byteLen)
    let all = collectVisualClusters(layout)

    // Locate `left` (cluster ending at `at`) and `right` (cluster starting at or containing `at`).
    var left: ResolvedCluster? = nil
    var right: ResolvedCluster? = nil
    for rc in all {
        let r = rc.cluster.textRange
        if r.upperBound == at {
            left = rc
        }
        if r.lowerBound == at || (r.lowerBound < at && at < r.upperBound) {
            if right == nil {
                right = rc
            }
        }
    }

    var chosenX: Float = 0.0
    var chosenLine: LayoutLine = lines[lines.count - 1]

    if let r = right, let l = left {
        if l.lineIdx != r.lineIdx {
            let onRight = l.line.breakReason() == .explicit
                || (!l.cluster.isRtl && cursor.affinity == .downstream)
                || (l.cluster.isRtl && cursor.affinity == .upstream)
            if onRight {
                chosenLine = r.line
                chosenX = r.cluster.isRtl ? (r.layoutX + r.cluster.advance) : r.layoutX
            } else {
                chosenLine = l.line
                chosenX = l.cluster.isRtl ? l.layoutX : (l.layoutX + (l.cluster.isHardLineBreak ? 0 : l.cluster.advance))
            }
        } else {
            chosenLine = r.line
            if cursor.affinity == .upstream {
                chosenX = l.cluster.isRtl ? l.layoutX : (l.layoutX + (l.cluster.isHardLineBreak ? 0 : l.cluster.advance))
            } else {
                chosenX = r.cluster.isRtl ? (r.layoutX + r.cluster.advance) : r.layoutX
            }
        }
    } else if let r = right {
        chosenLine = r.line
        if at > r.cluster.textRange.lowerBound && r.cluster.textRange.count > 0 {
            let frac = Float(at - r.cluster.textRange.lowerBound) / Float(r.cluster.textRange.count)
            chosenX = r.cluster.isRtl
                ? (r.layoutX + r.cluster.advance * (1.0 - frac))
                : (r.layoutX + r.cluster.advance * frac)
        } else {
            chosenX = r.cluster.isRtl ? (r.layoutX + r.cluster.advance) : r.layoutX
        }
    } else if let l = left {
        if l.line.breakReason() == .explicit && l.lineIdx + 1 < lines.count {
            // Trailing newline landing on the empty final line
            let nextLine = lines[l.lineIdx + 1]
            if nextLine.textRange().lowerBound == at && cursor.affinity == .downstream {
                chosenLine = nextLine
                chosenX = nextLine.metrics().inlineMinCoord + nextLine.metrics().offset
            } else {
                chosenLine = l.line
                chosenX = l.cluster.isRtl ? l.layoutX : (l.layoutX + (l.cluster.isHardLineBreak ? 0 : l.cluster.advance))
            }
        } else {
            chosenLine = l.line
            chosenX = l.cluster.isRtl ? l.layoutX : (l.layoutX + (l.cluster.isHardLineBreak ? 0 : l.cluster.advance))
        }
    } else {
        // Empty line or trailing empty line
        for line in lines where line.textRange().lowerBound == at && line.textRange().upperBound == at {
            chosenLine = line
            break
        }
        let m = chosenLine.metrics()
        chosenX = m.inlineMinCoord + m.offset + (layout.isRtl ? 0.0 : m.advance)
    }

    let cm = chosenLine.metrics()
    let y0 = Double(min(cm.blockMinCoord, cm.contentBlockMinCoord))
    let y1 = Double(max(cm.blockMaxCoord, cm.contentBlockMaxCoord))
    var bb = TextBoundingBox(x0: Double(chosenX), y0: y0, x1: Double(chosenX + size), y1: y1)

    // Move caret outside a pill chip if `at` sits at a pill's label start or end.
    let midY = Float((bb.y0 + bb.y1) * 0.5)
    if let px = pillEdge(layout, at, midY) {
        let w = bb.x1 - bb.x0
        bb.x0 = Double(px)
        bb.x1 = bb.x0 + w
    }
    return bb
}

/// The x just outside the pill chip whose label starts or ends at byte `at`, on the line at `y`.
private func pillEdge(_ layout: TextLayout, _ at: Int, _ y: Float) -> Float? {
    var ids: [UInt64] = []
    for b in layout.inlineBoxes() where b.index == at && (b.id & PILL_BOX) != 0 {
        ids.append(b.id)
    }
    if ids.isEmpty {
        return nil
    }
    guard let line = layout.lines().first(where: {
        let m = $0.metrics()
        return m.blockMinCoord <= y && y <= m.blockMaxCoord
    }) else {
        return nil
    }
    var boxes: [PositionedInlineBox] = []
    for item in line.items() {
        if case .inlineBox(let b) = item, ids.contains(b.id) {
            boxes.append(b)
        }
    }
    if let t = boxes.first(where: { ($0.id & 1) == 1 }) {
        return t.x + t.width
    }
    guard let lead = boxes.first else { return nil }
    guard let startByte = layout.inlineBoxes().first(where: { $0.id == lead.id })?.index else {
        return lead.x
    }
    var grX0: Float? = nil
    for item in line.items() {
        if case .glyphRun(let gr) = item, gr.textRange.contains(startByte) {
            grX0 = gr.offset()
            break
        }
    }
    if let gx = grX0, abs(lead.x + lead.width - gx) >= 1.0 {
        return gx - lead.width
    }
    return lead.x
}

private func lineForOffset(_ layout: TextLayout, _ offset: Float) -> (Int, LayoutLine)? {
    if offset < 0.0 {
        guard let first = layout.get(0) else { return nil }
        return (0, first)
    }
    for (i, line) in layout.lines().enumerated() {
        let m = line.metrics()
        if offset >= m.blockMinCoord && offset < m.blockMaxCoord {
            return (i, line)
        }
    }
    return nil
}

/// Hit-tests `(x, y)` (layout device px) to a `TextCursor`, accounting for line indentation
/// and pill inline boxes.
func cursorFromPoint(_ layout: TextLayout, _ x: Float, _ y: Float) -> TextCursor {
    if layout.len() == 0 {
        return TextCursor.fromByteIndex(layout, 0, .downstream)
    }
    let first = layout.get(0)!
    let fm = first.metrics()
    if y <= fm.blockMinCoord && x <= fm.inlineMinCoord + fm.offset {
        return TextCursor.fromByteIndex(layout, 0, .downstream)
    }
    let lastIdx = layout.len() - 1
    let last = layout.get(lastIdx)!
    let lm = last.metrics()
    if y >= lm.blockMaxCoord && x >= lm.inlineMinCoord + lm.offset + lm.advance {
        return TextCursor.fromByteIndex(layout, last.textRange().upperBound, .upstream)
    }
    let line: LayoutLine
    if y <= fm.blockMinCoord {
        line = first
    } else if y >= lm.blockMaxCoord {
        line = last
    } else {
        line = lineForOffset(layout, y)?.1 ?? last
    }
    let m = line.metrics()
    let r = line.textRange()
    if x <= m.inlineMinCoord + m.offset {
        let edgeByte = layout.isRtl ? r.upperBound : r.lowerBound
        let aff: TextAffinity = layout.isRtl ? .upstream : .downstream
        return TextCursor.fromByteIndex(layout, edgeByte, aff)
    }
    for item in line.items() {
        if case .inlineBox(let b) = item,
           (b.id & PILL_BOX) != 0,
           x >= b.x && x <= b.x + b.width,
           let ib = layout.inlineBoxes().first(where: { $0.id == b.id })
        {
            let aff: TextAffinity = ((b.id & 1) == 0) ? .downstream : .upstream
            return TextCursor.fromByteIndex(layout, ib.index, aff)
        }
    }
    for run in line.runs() {
        let vClusters = run.visualClusters()
        var cx = m.inlineMinCoord + (vClusters.first?.visualOffset ?? m.offset)
        for cl in vClusters {
            let adv = cl.advance
            if x <= cx + adv {
                let leading = (x - cx) <= adv * 0.5
                let idx: Int
                let aff: TextAffinity
                if cl.isRtl {
                    if leading {
                        idx = cl.textRange.upperBound
                        aff = .upstream
                    } else {
                        idx = cl.textRange.lowerBound
                        aff = .downstream
                    }
                } else if leading || cl.isHardLineBreak {
                    idx = cl.textRange.lowerBound
                    aff = .downstream
                } else {
                    idx = cl.textRange.upperBound
                    aff = .upstream
                }
                return TextCursor.fromByteIndex(layout, idx, aff)
            }
            cx += adv
        }
    }
    if line.breakReason() == .explicit && r.upperBound > r.lowerBound {
        if let (_, cl, _) = clusterFromByteIndex(layout, r.upperBound - 1) {
            return TextCursor.fromByteIndex(layout, cl.textRange.lowerBound, .downstream)
        }
    }
    let endByte = layout.isRtl ? r.lowerBound : r.upperBound
    let endAff: TextAffinity = layout.isRtl ? .downstream : .upstream
    return TextCursor.fromByteIndex(layout, endByte, endAff)
}

/// Start (`!end`) or end (`end`) byte of the visual line containing `byte`.
func lineEdge(_ layout: TextLayout, _ byte: Int, _ end: Bool) -> Int {
    let cur = TextCursor.fromByteIndex(layout, byte, .downstream)
    let bb = cursorGeometry(cur, layout, 0.0)
    let y = Float((bb.y0 + bb.y1) * 0.5)
    let resolved: (Int, LayoutLine)?
    if let hit = lineForOffset(layout, y) {
        resolved = hit
    } else if layout.len() > 0, let lastLine = layout.get(layout.len() - 1) {
        resolved = (layout.len() - 1, lastLine)
    } else {
        resolved = nil
    }
    guard let (_, line) = resolved else { return byte }
    let r = line.textRange()
    if !end {
        return r.lowerBound
    }
    if line.breakReason() == .explicit && r.upperBound > r.lowerBound {
        if let (_, cl, _) = clusterFromByteIndex(layout, r.upperBound - 1) {
            return cl.textRange.lowerBound
        }
        return r.upperBound - 1
    }
    return r.upperBound
}

/// Byte index on the previous (`!down`) or next (`down`) visual line at `byte`'s x coordinate,
/// or `nil` when already on the last line moving down.
func moveLine(_ layout: TextLayout, _ byte: Int, _ down: Bool) -> Int? {
    if layout.len() == 0 {
        return nil
    }
    let cur = TextCursor.fromByteIndex(layout, byte, .downstream)
    let bb = cursorGeometry(cur, layout, 0.0)
    let y = Float((bb.y0 + bb.y1) * 0.5)
    let limit = layout.len() - 1
    let idx = lineForOffset(layout, y)?.0 ?? limit
    if !down && idx == 0 {
        return 0
    }
    if down && idx >= limit {
        return nil
    }
    let targetIdx = down ? (idx + 1) : (idx - 1)
    guard let line = layout.get(targetIdx) else { return nil }
    let m = line.metrics()
    return cursorFromPoint(layout, Float(bb.x0), (m.blockMinCoord + m.blockMaxCoord) * 0.5).index
}

/// Line boxes (`(TextBoundingBox, lineIdx)`) covering bytes `a..b` of `layout`.
func rangeBoxes(
    _ layout: TextLayout,
    _ a: Int,
    _ b: Int,
    _ pillBoxes: Bool
) -> [(TextBoundingBox, Int)] {
    if a >= b {
        return []
    }
    let range = a..<b
    var rects: [(TextBoundingBox, Int)] = []

    for (lineIx, line) in layout.lines().enumerated() {
        let lr = line.textRange()
        if lr.upperBound <= a || lr.lowerBound >= b {
            continue
        }
        let m = line.metrics()
        let lineMin = Double(min(m.blockMinCoord, m.contentBlockMinCoord))
        let lineMax = Double(max(m.blockMaxCoord, m.contentBlockMaxCoord))
        let newlineWs: Double
        if line.breakReason() == .explicit && lr.upperBound > lr.lowerBound && range.contains(lr.upperBound - 1) {
            if let firstRun = line.runs().first {
                let fm = firstRun.fontMetrics
                newlineWs = Double(fm.ascent + fm.descent) * 0.25
            } else {
                newlineWs = Double(m.lineHeight) * 0.25
            }
        } else {
            newlineWs = 0.0
        }

        var intervals: [(Double, Double)] = []
        for run in line.runs() {
            let vClusters = run.visualClusters()
            var cx = Double(m.inlineMinCoord + (vClusters.first?.visualOffset ?? m.offset))
            for cl in vClusters {
                let adv = Double(cl.advance)
                if range.contains(cl.textRange.lowerBound) && adv > 0.0 && !cl.isHardLineBreak {
                    intervals.append((cx, cx + adv))
                }
                cx += adv
            }
        }

        if pillBoxes {
            for item in line.items() {
                if case .inlineBox(let ib) = item,
                   (ib.id & PILL_BOX) != 0,
                   ib.width > 0.0,
                   let bSpec = layout.inlineBoxes().first(where: { $0.id == ib.id })
                {
                    let included = ((ib.id & 1) == 0)
                        ? range.contains(bSpec.index)
                        : (bSpec.index > 0 && range.contains(bSpec.index - 1))
                    if included {
                        intervals.append((Double(ib.x), Double(ib.x + ib.width)))
                    }
                }
            }
        }

        intervals.sort { p, q in p.0 < q.0 }
        var merged: [(Double, Double)] = []
        for (x0, x1) in intervals {
            if let last = merged.last, x0 <= last.1 + 0.5 {
                merged[merged.count - 1].1 = max(last.1, x1)
            } else {
                merged.append((x0, x1))
            }
        }
        if !merged.isEmpty {
            merged[merged.count - 1].1 += newlineWs
        } else if newlineWs > 0.0 {
            let x0 = Double(m.inlineMinCoord + m.offset + m.advance)
            merged.append((x0, x0 + newlineWs))
        }
        for (x0, x1) in merged where x1 > x0 {
            rects.append((TextBoundingBox(x0: x0, y0: lineMin, x1: x1, y1: lineMax), lineIx))
        }
    }
    return rects
}
