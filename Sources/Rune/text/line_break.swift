// Ported from: crates/rune/src/text/line_break.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Line breaking, monospace 4-column tab stops, block indentation, atomic pill chips,
//! Bidi visual ordering, and line alignment / justification.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#elseif os(WASI)
import WASILibc
#endif

@inline(__always)
func snap256(_ v: Float) -> Float {
    (v * 256.0).rounded(.toNearestOrAwayFromZero) / 256.0
}

private struct FlatClusterRef {
    var runIdx: Int
    var clusterIdx: Int
    var leadBoxes: [LayoutInlineBox]
    var trailBoxes: [LayoutInlineBox]
    var allowSoftBreakAfter: Bool
}

func breakLinesWithBlocks(
    layout: TextLayout,
    blocks: [Block],
    maxWidth: Float?,
    align: TextAlignment,
    wrapAnywhere: Bool
) {
    let scale = layout.scale
    let baseLineH = layout.baseStyle.linePx() * scale

    // Empty text still produces one empty line so caret geometry, height, and hit-testing work uniformly.
    if layout.shapedRuns.isEmpty || layout.byteLen == 0 {
        let indent = (blocks.first?.indentPt(layout.baseStyle.size) ?? 0.0) * scale
        let asc = (layout.baseStyle.size * scale * 0.8).rounded(.toNearestOrAwayFromZero)
        let desc = max(baseLineH - asc, (layout.baseStyle.size * scale * 0.2).rounded(.toNearestOrAwayFromZero))
        let lead = baseLineH - (asc + desc)
        let baseline = (asc + lead * 0.5).rounded(.toNearestOrAwayFromZero)
        let avail = maxWidth.map { max(0.0, $0 - indent) }
        let offset: Float
        if let av = avail {
            switch align {
            case .center: offset = av * 0.5
            case .end: offset = layout.isRtl ? 0.0 : av
            case .start, .justify: offset = layout.isRtl ? av : 0.0
            }
        } else {
            offset = 0.0
        }
        var items: [PositionedLayoutItem] = []
        var adv: Float = 0.0
        for ib in layout.inlineBoxesData {
            items.append(.inlineBox(PositionedInlineBox(
                id: ib.id,
                x: indent + offset + adv,
                y: baseline - ib.height,
                width: ib.width,
                height: ib.height
            )))
            adv += ib.width
        }
        let m = LayoutLineMetrics(
            ascent: asc,
            descent: desc,
            leading: lead,
            lineHeight: baseLineH,
            baseline: baseline,
            offset: offset,
            advance: adv,
            hangingAdvance: 0.0,
            inlineMinCoord: indent,
            blockMinCoord: 0.0,
            blockMaxCoord: baseLineH,
            contentBlockMinCoord: baseline - asc,
            contentBlockMaxCoord: baseline + desc
        )
        layout.linesData = [LayoutLine(textRangeVal: 0..<0, metricsVal: m, breakReasonVal: .none, itemsVal: items)]
        layout.widthVal = indent + adv
        layout.fullWidthVal = indent + adv
        layout.heightVal = baseLineH
        return
    }

    // Flatten shaped runs' clusters in logical byte order.
    var flat: [FlatClusterRef] = []
    for (rIdx, run) in layout.shapedRuns.enumerated() {
        for cIdx in run.clusters.indices {
            let cl = run.clusters[cIdx]
            flat.append(FlatClusterRef(
                runIdx: rIdx,
                clusterIdx: cIdx,
                leadBoxes: [],
                trailBoxes: [],
                allowSoftBreakAfter: cl.isSoftBreakAfter
            ))
        }
    }

    // Attach inline boxes (`lead` with `id & 1 == 0` at `start`, `trail` with `id & 1 == 1` at `end`).
    for ib in layout.inlineBoxesData {
        let isTrail = (ib.id & 1) == 1
        if !isTrail {
            if let idx = flat.firstIndex(where: { layout.shapedRuns[$0.runIdx].clusters[$0.clusterIdx].textRange.lowerBound >= ib.index }) {
                flat[idx].leadBoxes.append(ib)
            } else if !flat.isEmpty {
                flat[flat.count - 1].trailBoxes.append(ib)
            }
        } else {
            if let idx = flat.lastIndex(where: { layout.shapedRuns[$0.runIdx].clusters[$0.clusterIdx].textRange.upperBound <= ib.index }) {
                flat[idx].trailBoxes.append(ib)
            } else if !flat.isEmpty {
                flat[0].leadBoxes.append(ib)
            }
        }
    }

    // Split into logical paragraphs at hard line breaks (`isHardBreak`).
    var paragraphs: [Range<Int>] = []
    var pStart = 0
    for i in flat.indices {
        let cl = layout.shapedRuns[flat[i].runIdx].clusters[flat[i].clusterIdx]
        if cl.isHardBreak {
            paragraphs.append(pStart..<(i + 1))
            pStart = i + 1
        }
    }
    if pStart < flat.count {
        paragraphs.append(pStart..<flat.count)
    } else if let lastIdx = flat.indices.last,
              layout.shapedRuns[flat[lastIdx].runIdx].clusters[flat[lastIdx].clusterIdx].isHardBreak {
        // Trailing `\n` creates a final empty line at `byteLen..<byteLen`.
        paragraphs.append(flat.count..<flat.count)
    }

    var builtLines: [LayoutLine] = []
    var curBlockY: Float = 0.0
    var maxVisWidth: Float = 0.0
    var maxFullWidth: Float = 0.0

    for (paraIdx, paraRange) in paragraphs.enumerated() {
        let block: Block = (paraIdx < blocks.count) ? blocks[paraIdx] : .paragraph
        let inlineMin = (block.indentPt(layout.baseStyle.size) * scale).rounded(.toNearestOrAwayFromZero)
        let rightPad: Float = (block == .code) ? inlineMin : 0.0
        let availWidth: Float? = maxWidth.map { w in
            inlineMin > 0.0 ? max(1.0, w - inlineMin - rightPad) : max(0.0, w)
        }

        if paraRange.isEmpty {
            // Trailing empty line after explicit `\n`
            let lastRun = layout.shapedRuns.last!
            let fm = lastRun.fontMetrics
            let lh = max(lastRun.lineHeightPx, baseLineH)
            let lead = lh - (fm.ascent + fm.descent)
            let qa = fm.ascent.rounded(.toNearestOrAwayFromZero)
            let qd = fm.descent.rounded(.toNearestOrAwayFromZero)
            let halfLead = ((lh - (qa + qd)) * 0.5).rounded(.down)
            let base = (curBlockY + qa + halfLead).rounded(.toNearestOrAwayFromZero)
            let off: Float
            if let av = availWidth {
                switch align {
                case .center: off = av * 0.5
                case .end: off = layout.isRtl ? 0.0 : av
                case .start, .justify: off = layout.isRtl ? av : 0.0
                }
            } else {
                off = 0.0
            }
            let m = LayoutLineMetrics(
                ascent: fm.ascent,
                descent: fm.descent,
                leading: lead,
                lineHeight: lh,
                baseline: base,
                offset: off,
                advance: 0.0,
                hangingAdvance: 0.0,
                inlineMinCoord: inlineMin,
                blockMinCoord: curBlockY,
                blockMaxCoord: curBlockY + lh,
                contentBlockMinCoord: base - fm.ascent,
                contentBlockMaxCoord: base + fm.descent
            )
            builtLines.append(LayoutLine(
                textRangeVal: layout.byteLen..<layout.byteLen,
                metricsVal: m,
                breakReasonVal: .none,
                itemsVal: []
            ))
            curBlockY += lh
            maxVisWidth = max(maxVisWidth, inlineMin)
            maxFullWidth = max(maxFullWidth, inlineMin)
            continue
        }

        // Enforce atomic pill chips whenever the whole pill fits `availWidth`; when a pill is
        // wider than a line, break before its leading chip if preceded by earlier words on the line.
        var oversizedPillStarts = Set<Int>()
        if !layout.pillRanges.isEmpty {
            for (pStartByte, pEndByte) in layout.pillRanges {
                var pFirst: Int? = nil
                var pLast: Int? = nil
                var pillW: Float = 0.0
                for idx in paraRange {
                    let cl = layout.shapedRuns[flat[idx].runIdx].clusters[flat[idx].clusterIdx]
                    if cl.textRange.lowerBound >= pStartByte && cl.textRange.upperBound <= pEndByte {
                        if pFirst == nil { pFirst = idx }
                        pLast = idx
                        for b in flat[idx].leadBoxes { pillW += b.width }
                        pillW += cl.advance
                        for b in flat[idx].trailBoxes { pillW += b.width }
                    }
                }
                if let f = pFirst, let l = pLast {
                    let fitsLine = availWidth.map { pillW <= $0 + 0.5 } ?? true
                    if fitsLine && f < l {
                        for k in f..<l {
                            flat[k].allowSoftBreakAfter = false
                        }
                    } else if !fitsLine {
                        oversizedPillStarts.insert(f)
                    }
                }
            }
        }

        let utf8Bytes = Array(layout.text.utf8)
        @inline(__always)
        func scalarCount(_ range: Range<Int>) -> Int {
            let lo = max(0, min(range.lowerBound, utf8Bytes.count))
            let hi = max(lo, min(range.upperBound, utf8Bytes.count))
            var n = 0
            for b in lo..<hi where (utf8Bytes[b] & 0xC0) != 0x80 {
                n += 1
            }
            return max(n, 1)
        }

        // Break `paraRange` into visual line slices `(Range<Int>, LineBreakReason)`.
        var lineSlices: [(Range<Int>, LineBreakReason)] = []
        if let avail = availWidth {
            var lineStart = paraRange.lowerBound
            var idx = paraRange.lowerBound
            var xLine: Float = 0.0
            var monoCol: Int = 0
            var lastSoftBreak: Int? = nil

            func clusterEffectiveAdvance(_ k: Int, col: inout Int) -> (lead: Float, body: Float, trail: Float, isHanging: Bool, isHard: Bool) {
                let fc = flat[k]
                let run = layout.shapedRuns[fc.runIdx]
                let cl = run.clusters[fc.clusterIdx]
                var leadW: Float = 0.0
                for b in fc.leadBoxes { leadW += b.width }
                var trailW: Float = 0.0
                for b in fc.trailBoxes { trailW += b.width }
                let bodyW: Float
                if cl.isHardBreak {
                    bodyW = 0.0
                    col = 0
                } else if run.isMono {
                    if cl.isTab && run.monoSpaceAdvance > 0.0 {
                        let fill = 4 - (col % 4)
                        bodyW = Float(fill) * run.monoSpaceAdvance
                        col += fill
                    } else {
                        bodyW = cl.advance
                        col += scalarCount(cl.textRange)
                    }
                } else {
                    col = 0
                    bodyW = cl.advance
                }
                return (leadW, bodyW, trailW, cl.isHangingWhitespace && leadW == 0 && trailW == 0, cl.isHardBreak)
            }

            while idx < paraRange.upperBound {
                if idx > lineStart && oversizedPillStarts.contains(idx) && xLine >= 0.5 {
                    lineSlices.append((lineStart..<idx, .regular))
                    lineStart = idx
                    xLine = 0.0
                    monoCol = 0
                    lastSoftBreak = nil
                    continue
                }
                var nextCol = monoCol
                let piece = clusterEffectiveAdvance(idx, col: &nextCol)
                if piece.isHard {
                    lineSlices.append((lineStart..<(idx + 1), .explicit))
                    idx += 1
                    lineStart = idx
                    xLine = 0.0
                    monoCol = 0
                    lastSoftBreak = nil
                    continue
                }
                let nextX = xLine + piece.lead + piece.body + piece.trail
                let overflows = !piece.isHanging && (nextX > avail + 0.05) && (idx > lineStart)
                if overflows {
                    if let brk = lastSoftBreak, brk > lineStart {
                        lineSlices.append((lineStart..<brk, .regular))
                        lineStart = brk
                        idx = brk
                        xLine = 0.0
                        monoCol = 0
                        lastSoftBreak = nil
                        continue
                    } else if wrapAnywhere {
                        lineSlices.append((lineStart..<idx, .emergency))
                        lineStart = idx
                        xLine = 0.0
                        monoCol = 0
                        lastSoftBreak = nil
                        continue
                    }
                }
                xLine = nextX
                monoCol = nextCol
                if flat[idx].allowSoftBreakAfter {
                    lastSoftBreak = idx + 1
                }
                idx += 1
            }
            if lineStart < paraRange.upperBound {
                lineSlices.append((lineStart..<paraRange.upperBound, .none))
            }
        } else {
            let lastIdx = paraRange.upperBound - 1
            let isExplicit = layout.shapedRuns[flat[lastIdx].runIdx].clusters[flat[lastIdx].clusterIdx].isHardBreak
            lineSlices.append((paraRange, isExplicit ? .explicit : .none))
        }

        // Materialize each `LayoutLine` with tab widths, justification, alignment, and Bidi run items.
        for (sliceRange, reason) in lineSlices {
            var clusterAdvances = [Float](repeating: 0, count: sliceRange.count)
            var xCursor: Float = 0.0
            var monoColMat: Int = 0
            var maxAsc: Float = 0.0
            var maxDesc: Float = 0.0
            var maxRunLH: Float = baseLineH

            for (localIdx, globalIdx) in sliceRange.enumerated() {
                let fc = flat[globalIdx]
                let run = layout.shapedRuns[fc.runIdx]
                let cl = run.clusters[fc.clusterIdx]
                maxAsc = max(maxAsc, run.fontMetrics.ascent)
                maxDesc = max(maxDesc, run.fontMetrics.descent)
                maxRunLH = max(maxRunLH, run.lineHeightPx)

                for b in fc.leadBoxes { xCursor += b.width }
                let adv: Float
                if cl.isHardBreak {
                    adv = 0.0
                    monoColMat = 0
                } else if run.isMono {
                    if cl.isTab && run.monoSpaceAdvance > 0.0 {
                        let fill = 4 - (monoColMat % 4)
                        adv = Float(fill) * run.monoSpaceAdvance
                        monoColMat += fill
                    } else {
                        adv = cl.advance
                        monoColMat += scalarCount(cl.textRange)
                    }
                } else {
                    monoColMat = 0
                    adv = cl.advance
                }
                clusterAdvances[localIdx] = adv
                xCursor += adv
                for b in fc.trailBoxes { xCursor += b.width }
            }

            let totalAdvanceBeforeJustify = xCursor
            // Trailing hanging whitespace from the logical end of the line
            var hangingAdv: Float = 0.0
            var trailingStartLocal = sliceRange.count
            while trailingStartLocal > 0 {
                let local = trailingStartLocal - 1
                let global = sliceRange.lowerBound + local
                let fc = flat[global]
                let cl = layout.shapedRuns[fc.runIdx].clusters[fc.clusterIdx]
                if cl.isHardBreak {
                    trailingStartLocal -= 1
                    continue
                }
                if cl.isHangingWhitespace && fc.leadBoxes.isEmpty && fc.trailBoxes.isEmpty {
                    hangingAdv += clusterAdvances[local]
                    trailingStartLocal -= 1
                } else {
                    break
                }
            }

            var visibleAdv = max(0.0, totalAdvanceBeforeJustify - hangingAdv)
            var extraPerSpace: Float = 0.0
            var justifiedSpaces = 0
            if align == .justify,
               reason == .regular,
               let av = availWidth,
               av > visibleAdv + 0.01,
               trailingStartLocal > 0
            {
                for local in 0..<trailingStartLocal {
                    let global = sliceRange.lowerBound + local
                    let fc = flat[global]
                    let cl = layout.shapedRuns[fc.runIdx].clusters[fc.clusterIdx]
                    if cl.isWordSpace && fc.leadBoxes.isEmpty && fc.trailBoxes.isEmpty {
                        justifiedSpaces += 1
                    }
                }
                if justifiedSpaces > 0 {
                    extraPerSpace = (av - visibleAdv) / Float(justifiedSpaces)
                    for local in 0..<trailingStartLocal {
                        let global = sliceRange.lowerBound + local
                        let fc = flat[global]
                        let cl = layout.shapedRuns[fc.runIdx].clusters[fc.clusterIdx]
                        if cl.isWordSpace && fc.leadBoxes.isEmpty && fc.trailBoxes.isEmpty {
                            clusterAdvances[local] += extraPerSpace
                        }
                    }
                    visibleAdv = av
                }
            }
            let finalAdvance = visibleAdv + hangingAdv

            let lineOffset: Float
            if let av = availWidth {
                switch align {
                case .start:
                    lineOffset = layout.isRtl ? max(0.0, av - visibleAdv) : 0.0
                case .end:
                    lineOffset = layout.isRtl ? 0.0 : (av - visibleAdv)
                case .center:
                    lineOffset = (av - visibleAdv) * 0.5
                case .justify:
                    if justifiedSpaces > 0 {
                        lineOffset = 0.0
                    } else {
                        lineOffset = layout.isRtl ? max(0.0, av - visibleAdv) : 0.0
                    }
                }
            } else {
                lineOffset = 0.0
            }

            if maxAsc == 0.0 && maxDesc == 0.0 {
                maxAsc = (layout.baseStyle.size * scale * 0.8).rounded(.toNearestOrAwayFromZero)
                maxDesc = max(maxRunLH - maxAsc, 1.0)
            }
            let leading = maxRunLH - (maxAsc + maxDesc)
            // PORT NOTE: Matches Parley's `quantize: true` CSS inline line-box baseline snapping:
            // ascent and descent round to whole pixels first, and any odd pixel of leading goes below
            // the text (`floor` on top half-leading).
            let qa = maxAsc.rounded(.toNearestOrAwayFromZero)
            let qd = maxDesc.rounded(.toNearestOrAwayFromZero)
            let halfLeading = ((maxRunLH - (qa + qd)) * 0.5).rounded(.down)
            let baseline = (curBlockY + qa + halfLeading).rounded(.toNearestOrAwayFromZero)

            // Position items in visual order (left-to-right for LTR, reversed for RTL paragraph).
            let orderedIndices: [Int] = layout.isRtl
                ? Array((0..<sliceRange.count).reversed())
                : Array(0..<sliceRange.count)

            var items: [PositionedLayoutItem] = []
            var penX: Float = inlineMin + (layout.isRtl ? (lineOffset + visibleAdv) : lineOffset)
            if layout.isRtl {
                // In RTL, visual left edge of visible text starts at `inlineMin + lineOffset`.
                penX = inlineMin + lineOffset
            }

            var pendingRunIdx: Int? = nil
            var pendingRunStartX: Float = 0.0
            var pendingRunAdv: Float = 0.0
            var pendingRunMinByte: Int = Int.max
            var pendingRunMaxByte: Int = 0
            var pendingGlyphs: [LayoutGlyph] = []
            var pendingClusters: [PositionedCluster] = []

            func flushPendingRun() {
                guard let rIdx = pendingRunIdx else { return }
                let srcRun = layout.shapedRuns[rIdx]
                let tRange = (pendingRunMinByte <= pendingRunMaxByte)
                    ? (pendingRunMinByte..<pendingRunMaxByte)
                    : srcRun.textRange
                items.append(.glyphRun(PositionedGlyphRun(
                    font: srcRun.font,
                    fontSize: srcRun.fontSize,
                    fontMetrics: srcRun.fontMetrics,
                    ink: srcRun.ink,
                    textRange: tRange,
                    isRtl: srcRun.isRtl,
                    offsetVal: pendingRunStartX,
                    baselineVal: baseline,
                    advanceVal: pendingRunAdv,
                    glyphsVal: pendingGlyphs,
                    clustersVal: pendingClusters
                )))
                pendingRunIdx = nil
                pendingRunAdv = 0.0
                pendingRunMinByte = Int.max
                pendingRunMaxByte = 0
                pendingGlyphs.removeAll(keepingCapacity: true)
                pendingClusters.removeAll(keepingCapacity: true)
            }

            for localIdx in orderedIndices {
                let globalIdx = sliceRange.lowerBound + localIdx
                let fc = flat[globalIdx]
                let run = layout.shapedRuns[fc.runIdx]
                let cl = run.clusters[fc.clusterIdx]
                let isTrailingHanging = layout.isRtl && (localIdx >= trailingStartLocal)
                if isTrailingHanging {
                    // Hanging trailing spaces in RTL don't push visible RTL glyphs rightward
                    continue
                }

                let firstBoxes = layout.isRtl ? fc.trailBoxes : fc.leadBoxes
                let secondBoxes = layout.isRtl ? fc.leadBoxes : fc.trailBoxes

                if !firstBoxes.isEmpty {
                    flushPendingRun()
                    for ib in firstBoxes {
                        items.append(.inlineBox(PositionedInlineBox(
                            id: ib.id,
                            x: penX,
                            y: baseline - ib.height,
                            width: ib.width,
                            height: ib.height
                        )))
                        penX += ib.width
                    }
                }

                let adv = clusterAdvances[localIdx]
                if pendingRunIdx != fc.runIdx {
                    flushPendingRun()
                    pendingRunIdx = fc.runIdx
                    pendingRunStartX = penX
                }
                pendingRunMinByte = min(pendingRunMinByte, cl.textRange.lowerBound)
                pendingRunMaxByte = max(pendingRunMaxByte, cl.textRange.upperBound)
                pendingClusters.append(PositionedCluster(
                    textRange: cl.textRange,
                    advance: adv,
                    visualOffset: penX - inlineMin,
                    isRtl: cl.isRtl,
                    isHardLineBreak: cl.isHardBreak
                ))

                if !cl.isHardBreak && !cl.glyphRange.isEmpty {
                    let gCount = cl.glyphRange.count
                    let origAdv = cl.advance
                    let delta = adv - origAdv
                    for (gi, gIdx) in cl.glyphRange.enumerated() {
                        var g = run.glyphs[gIdx]
                        if gi + 1 == gCount && abs(delta) > 1e-6 {
                            g.advance += delta
                        }
                        pendingGlyphs.append(g)
                    }
                }

                pendingRunAdv += adv
                penX += adv

                if !secondBoxes.isEmpty {
                    flushPendingRun()
                    for ib in secondBoxes {
                        items.append(.inlineBox(PositionedInlineBox(
                            id: ib.id,
                            x: penX,
                            y: baseline - ib.height,
                            width: ib.width,
                            height: ib.height
                        )))
                        penX += ib.width
                    }
                }
            }

            // Emit any RTL hanging whitespace clusters with 0 visual displacement at the left edge so byte ranges remain complete
            if layout.isRtl && trailingStartLocal < sliceRange.count {
                for localIdx in trailingStartLocal..<sliceRange.count {
                    let globalIdx = sliceRange.lowerBound + localIdx
                    let fc = flat[globalIdx]
                    let run = layout.shapedRuns[fc.runIdx]
                    let cl = run.clusters[fc.clusterIdx]
                    if pendingRunIdx != fc.runIdx {
                        flushPendingRun()
                        pendingRunIdx = fc.runIdx
                        pendingRunStartX = inlineMin + lineOffset
                    }
                    pendingRunMinByte = min(pendingRunMinByte, cl.textRange.lowerBound)
                    pendingRunMaxByte = max(pendingRunMaxByte, cl.textRange.upperBound)
                    pendingClusters.append(PositionedCluster(
                        textRange: cl.textRange,
                        advance: clusterAdvances[localIdx],
                        visualOffset: lineOffset,
                        isRtl: cl.isRtl,
                        isHardLineBreak: cl.isHardBreak
                    ))
                }
            }
            flushPendingRun()

            let firstCluster = layout.shapedRuns[flat[sliceRange.lowerBound].runIdx].clusters[flat[sliceRange.lowerBound].clusterIdx]
            let lastCluster = layout.shapedRuns[flat[sliceRange.upperBound - 1].runIdx].clusters[flat[sliceRange.upperBound - 1].clusterIdx]
            let lineByteRange = firstCluster.textRange.lowerBound..<lastCluster.textRange.upperBound

            let m = LayoutLineMetrics(
                ascent: maxAsc,
                descent: maxDesc,
                leading: leading,
                lineHeight: maxRunLH,
                baseline: baseline,
                offset: lineOffset,
                advance: finalAdvance,
                hangingAdvance: hangingAdv,
                inlineMinCoord: inlineMin,
                blockMinCoord: curBlockY,
                blockMaxCoord: curBlockY + maxRunLH,
                contentBlockMinCoord: baseline - maxAsc,
                contentBlockMaxCoord: baseline + maxDesc
            )
            builtLines.append(LayoutLine(
                textRangeVal: lineByteRange,
                metricsVal: m,
                breakReasonVal: reason,
                itemsVal: items
            ))
            curBlockY += maxRunLH
            maxVisWidth = max(maxVisWidth, inlineMin + visibleAdv)
            maxFullWidth = max(maxFullWidth, inlineMin + finalAdvance)
        }
    }

    layout.linesData = builtLines
    layout.widthVal = maxVisWidth
    layout.fullWidthVal = maxFullWidth
    layout.heightVal = curBlockY
}
