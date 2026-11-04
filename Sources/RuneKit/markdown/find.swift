// Ported from: crates/rune-kit/src/markdown/find.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Rendered-text search over Markdown documents, returning source UTF-8 byte ranges for
//! ``Markdown/highlights(_:)-([Range<Int>])``.

import Rune

/// Case sensitivity for ``find(_:_:_:)`` (and ``Markdown/find(_:_:_:)``).
public enum Case: Sendable, Equatable, Hashable {
    /// Case-insensitive matching using per-character Unicode lowercase folding
    /// (with Greek final `'ς'` folded to `'σ'`).
    case insensitive
    /// Exact code-point matching.
    case sensitive

    public init() {
        self = .insensitive
    }

    public static let `default`: Case = .insensitive
}

/// Finds non-overlapping matches of `query` in the rendered text of `src`, in document order.
public func find(_ src: String, _ query: String, _ caseSensitivity: Case) -> [[Range<Int>]] {
    findMarkdown(src, query, caseSensitivity)
}

func findMarkdown(_ src: String, _ query: String, _ caseSensitivity: Case) -> [[Range<Int>]] {
    if src.isEmpty || query.isEmpty {
        return []
    }
    let doc = docCached(src)
    let srcBytes = Array(src.utf8)
    let needle = Needle(query, caseSensitivity)
    var out: [[Range<Int>]] = []
    findInBlocks(srcBytes, doc.blocks, doc.maps, needle, &out)
    return out
}

extension Markdown {
    /// Finds non-overlapping matches of `query` in the rendered text of `src` (see ``find(_:_:_:)``).
    public static func find(_ src: String, _ query: String, _ caseSensitivity: Case) -> [[Range<Int>]] {
        findMarkdown(src, query, caseSensitivity)
    }
}

private enum Needle {
    case sensitive([UInt8])
    case insensitive(folded: [UInt8], ascii: Bool)

    init(_ query: String, _ caseSensitivity: Case) {
        switch caseSensitivity {
        case .sensitive:
            self = .sensitive(Array(query.utf8))
        case .insensitive:
            let qBytes = Array(query.utf8)
            let isAscii = qBytes.allSatisfy { $0 < 0x80 }
            if isAscii {
                let lower = qBytes.map { ($0 >= 0x41 && $0 <= 0x5A) ? ($0 + 32) : $0 }
                self = .insensitive(folded: lower, ascii: true)
            } else {
                var foldedStr = ""
                foldedStr.reserveCapacity(qBytes.count)
                for sc in query.unicodeScalars {
                    pushFolded(&foldedStr, sc)
                }
                self = .insensitive(folded: Array(foldedStr.utf8), ascii: false)
            }
        }
    }
}

private func pushFolded(_ out: inout String, _ sc: UnicodeScalar) {
    if sc == "\u{03C2}" { // 'ς' -> 'σ'
        out.unicodeScalars.append("\u{03C3}")
    } else {
        out.append(sc.properties.lowercaseMapping)
    }
}

private func findInBlocks(
    _ srcBytes: [UInt8],
    _ blocks: [MarkdownBlock],
    _ maps: [BlockMap],
    _ needle: Needle,
    _ out: inout [[Range<Int>]]
) {
    for (idx, b) in blocks.enumerated() {
        let map = idx < maps.count ? maps[idx] : .none
        switch (b, map) {
        case (.para(let inl), .inline(let m)), (.heading(_, let inl), .inline(let m)):
            findInText(srcBytes, inl.text, m, needle, &out)
        case (.code(let code), .code(let m)), (.diff(let code), .code(let m)):
            findInText(srcBytes, code, m, needle, &out)
        case (.mermaid(let code), .code(let m)):
            if mermaid.supported(code) {
                continue
            }
            findInText(srcBytes, code, m, needle, &out)
        case (.table(let t), .table(let head, let rows)):
            findInTable(srcBytes, t, head, rows, needle, &out)
        case (.list(_, let items), .list(let itemMaps)):
            for (item, imap) in zip(items, itemMaps) {
                findInBlocks(srcBytes, item, imap, needle, &out)
            }
        case (.quote(let inner), .quote(let innerMaps)):
            findInBlocks(srcBytes, inner, innerMaps, needle, &out)
        default:
            break
        }
    }
}

private func findInTable(
    _ srcBytes: [UInt8],
    _ t: MarkdownTable,
    _ headMaps: [SpanMap],
    _ rowMaps: [[SpanMap]],
    _ needle: Needle,
    _ out: inout [[Range<Int>]]
) {
    for (cell, map) in zip(t.head, headMaps) {
        findInText(srcBytes, cell.text, map, needle, &out)
    }
    for (row, rmaps) in zip(t.rows, rowMaps) {
        for (cell, map) in zip(row, rmaps) {
            findInText(srcBytes, cell.text, map, needle, &out)
        }
    }
}

private struct Seg {
    var src: Range<Int>
    var out: Range<Int>
    var linear: Bool
}

private func isLinearSeg(_ srcBytes: [UInt8], _ visBytes: [UInt8], _ sSeg: Range<Int>, _ oSeg: Range<Int>) -> Bool {
    guard sSeg.count == oSeg.count,
          sSeg.lowerBound >= 0, sSeg.upperBound <= srcBytes.count,
          oSeg.lowerBound >= 0, oSeg.upperBound <= visBytes.count
    else {
        return false
    }
    if srcBytes[sSeg].elementsEqual(visBytes[oSeg]) {
        return true
    }
    return sSeg.isEmpty || srcBytes[sSeg.lowerBound] != 0x26 // '&'
}

private func findInText(
    _ srcBytes: [UInt8],
    _ text: String,
    _ map: SpanMap,
    _ needle: Needle,
    _ out: inout [[Range<Int>]]
) {
    let textBytes = Array(text.utf8)
    if textBytes.isEmpty || map.pairs.isEmpty {
        return
    }
    var contiguous = map.pairs[0].1.lowerBound == 0
        && map.pairs[map.pairs.count - 1].1.upperBound == textBytes.count
    if contiguous && map.pairs.count >= 2 {
        for k in 0..<(map.pairs.count - 1) where map.pairs[k].1.upperBound != map.pairs[k + 1].1.lowerBound {
            contiguous = false
            break
        }
    }

    var segments: [Seg] = []
    segments.reserveCapacity(map.pairs.count)
    let visBytes: [UInt8]
    let visStr: String
    if contiguous {
        for (srcR, outR) in map.pairs {
            let linear = isLinearSeg(srcBytes, textBytes, srcR, outR)
            segments.append(Seg(src: srcR, out: outR, linear: linear))
        }
        visBytes = textBytes
        visStr = text
    } else {
        var ownedBytes: [UInt8] = []
        ownedBytes.reserveCapacity(textBytes.count)
        for (srcR, outR) in map.pairs {
            if outR.lowerBound >= 0, outR.upperBound <= textBytes.count,
               outR.lowerBound < outR.upperBound,
               isUtf8Boundary(textBytes, outR.lowerBound),
               isUtf8Boundary(textBytes, outR.upperBound)
            {
                let start = ownedBytes.count
                ownedBytes.append(contentsOf: textBytes[outR])
                let newOut = start..<ownedBytes.count
                let linear = isLinearSeg(srcBytes, ownedBytes, srcR, newOut)
                segments.append(Seg(src: srcR, out: newOut, linear: linear))
            }
        }
        visBytes = ownedBytes
        visStr = String(decoding: ownedBytes, as: UTF8.self)
    }

    if visBytes.isEmpty {
        return
    }

    var segIdx = 0
    switch needle {
    case .sensitive(let q):
        for v0 in matchIndicesBytes(visBytes, q) {
            let ranges = mapVisRange(srcBytes, segments, &segIdx, v0..<(v0 + q.count))
            if !ranges.isEmpty {
                out.append(ranges)
            }
        }
    case .insensitive(let q, let isAscii) where isAscii && visBytes.allSatisfy({ $0 < 0x80 }):
        let lower = visBytes.map { ($0 >= 0x41 && $0 <= 0x5A) ? ($0 + 32) : $0 }
        for v0 in matchIndicesBytes(lower, q) {
            let ranges = mapVisRange(srcBytes, segments, &segIdx, v0..<(v0 + q.count))
            if !ranges.isEmpty {
                out.append(ranges)
            }
        }
    case .insensitive(let q, _):
        findFolded(srcBytes, visStr, visBytes.count, segments, q, &segIdx, &out)
    }
}

private func matchIndicesBytes(_ hay: [UInt8], _ pat: [UInt8]) -> [Int] {
    let m = pat.count
    guard m > 0, m <= hay.count else { return [] }
    var hits: [Int] = []
    var i = 0
    let limit = hay.count - m
    while i <= limit {
        var ok = true
        for k in 0..<m where hay[i + k] != pat[k] {
            ok = false
            break
        }
        if ok {
            hits.append(i)
            i += m
        } else {
            i += 1
        }
    }
    return hits
}

private func findFolded(
    _ srcBytes: [UInt8],
    _ vis: String,
    _ visByteLen: Int,
    _ segments: [Seg],
    _ q: [UInt8],
    _ segIdx: inout Int,
    _ out: inout [[Range<Int>]]
) {
    var foldedStr = ""
    foldedStr.reserveCapacity(visByteLen)
    var fToV: [Int] = []
    fToV.reserveCapacity(visByteLen + 1)
    var multiChar = false
    var vByte = 0

    for sc in vis.unicodeScalars {
        fToV.append(vByte)
        if sc == "\u{03C2}" {
            foldedStr.unicodeScalars.append("\u{03C3}")
        } else {
            let mapped = sc.properties.lowercaseMapping
            var count = 0
            for msc in mapped.unicodeScalars {
                foldedStr.unicodeScalars.append(msc)
                count += 1
            }
            if count > 1 {
                multiChar = true
            }
        }
        let fLen = foldedStr.utf8.count
        while fToV.count < fLen {
            fToV.append(Int.max)
        }
        vByte += sc.utf8.count
    }
    fToV.append(visByteLen)
    let foldedBytes = Array(foldedStr.utf8)

    if !multiChar {
        for f0 in matchIndicesBytes(foldedBytes, q) {
            let v0 = fToV[f0]
            let v1 = fToV[f0 + q.count]
            if v0 != Int.max && v1 != Int.max && v0 < v1 {
                let ranges = mapVisRange(srcBytes, segments, &segIdx, v0..<v1)
                if !ranges.isEmpty {
                    out.append(ranges)
                }
            }
        }
        return
    }

    let m = q.count
    guard m > 0 else { return }
    var pi = [Int](repeating: 0, count: m)
    var len = 0
    for i in 1..<m {
        while len > 0 && q[len] != q[i] {
            len = pi[len - 1]
        }
        if q[len] == q[i] {
            len += 1
        }
        pi[i] = len
    }

    var matched = 0
    for (i, b) in foldedBytes.enumerated() {
        while matched > 0 && q[matched] != b {
            matched = pi[matched - 1]
        }
        if q[matched] == b {
            matched += 1
        }
        if matched == m {
            let f0 = i + 1 - m
            let f1 = i + 1
            let v0 = fToV[f0]
            let v1 = fToV[f1]
            if v0 != Int.max && v1 != Int.max && v0 < v1 {
                let ranges = mapVisRange(srcBytes, segments, &segIdx, v0..<v1)
                if !ranges.isEmpty {
                    out.append(ranges)
                }
                matched = 0
            } else {
                matched = pi[matched - 1]
            }
        }
    }
}

private func mapVisRange(
    _ srcBytes: [UInt8],
    _ segments: [Seg],
    _ segIdx: inout Int,
    _ vRange: Range<Int>
) -> [Range<Int>] {
    while segIdx < segments.count && segments[segIdx].out.upperBound <= vRange.lowerBound {
        segIdx += 1
    }
    var ranges: [Range<Int>] = []
    var j = segIdx
    while j < segments.count && segments[j].out.lowerBound < vRange.upperBound {
        let seg = segments[j]
        let sSeg = seg.src
        let oSeg = seg.out
        let o0 = max(vRange.lowerBound, oSeg.lowerBound)
        let o1 = min(vRange.upperBound, oSeg.upperBound)
        if o0 < o1 {
            let rel0 = o0 - oSeg.lowerBound
            let rel1 = o1 - oSeg.lowerBound
            var s0: Int
            var s1: Int
            if seg.linear
                && isUtf8Boundary(srcBytes, sSeg.lowerBound + rel0)
                && isUtf8Boundary(srcBytes, sSeg.lowerBound + rel1)
            {
                s0 = sSeg.lowerBound + rel0
                s1 = sSeg.lowerBound + rel1
            } else {
                s0 = sSeg.lowerBound
                s1 = sSeg.upperBound
            }
            s0 = floorUtf8Boundary(srcBytes, min(max(s0, sSeg.lowerBound), min(sSeg.upperBound, srcBytes.count)))
            s1 = ceilUtf8Boundary(srcBytes, min(max(s1, sSeg.lowerBound), min(sSeg.upperBound, srcBytes.count)))
            if s0 < s1 {
                if let last = ranges.last, last.upperBound == s0 {
                    ranges[ranges.count - 1] = last.lowerBound..<s1
                } else if ranges.last == nil || ranges[ranges.count - 1].upperBound < s0 {
                    ranges.append(s0..<s1)
                }
            }
        }
        if oSeg.upperBound <= vRange.upperBound {
            segIdx = j + 1
        } else {
            segIdx = j
        }
        j += 1
    }
    return ranges
}

func isUtf8Boundary(_ bytes: [UInt8], _ index: Int) -> Bool {
    if index == 0 || index == bytes.count {
        return true
    }
    guard index > 0 && index < bytes.count else {
        return false
    }
    return (bytes[index] & 0xC0) != 0x80
}

func floorUtf8Boundary(_ bytes: [UInt8], _ index: Int) -> Int {
    var pos = min(max(index, 0), bytes.count)
    while pos > 0 && pos < bytes.count && (bytes[pos] & 0xC0) == 0x80 {
        pos -= 1
    }
    return pos
}

func ceilUtf8Boundary(_ bytes: [UInt8], _ index: Int) -> Int {
    var pos = min(max(index, 0), bytes.count)
    while pos < bytes.count && (bytes[pos] & 0xC0) == 0x80 {
        pos += 1
    }
    return pos
}

func normalizeRanges(_ raw: [Range<Int>]) -> [Range<Int>] {
    var ranges = raw.filter { $0.lowerBound < $0.upperBound }
    if ranges.count <= 1 {
        return ranges
    }
    var alreadyDisjointOrdered = true
    for k in 0..<(ranges.count - 1) where ranges[k].upperBound >= ranges[k + 1].lowerBound {
        alreadyDisjointOrdered = false
        break
    }
    if alreadyDisjointOrdered {
        return ranges
    }
    ranges.sort { a, b in
        if a.lowerBound != b.lowerBound { return a.lowerBound < b.lowerBound }
        return a.upperBound < b.upperBound
    }
    var merged: [Range<Int>] = []
    merged.reserveCapacity(ranges.count)
    for r in ranges {
        if let last = merged.last, last.upperBound >= r.lowerBound {
            merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
        } else {
            merged.append(r)
        }
    }
    return merged
}

extension SpanMap {
    func mapRanges(_ queries: [Range<Int>], _ outText: String) -> [Range<Int>] {
        let outBytes = Array(outText.utf8)
        if queries.isEmpty || pairs.isEmpty || outBytes.isEmpty {
            return []
        }
        var isNormalized = queries.allSatisfy { $0.lowerBound < $0.upperBound }
        if isNormalized && queries.count >= 2 {
            for k in 0..<(queries.count - 1) where queries[k].upperBound >= queries[k + 1].lowerBound {
                isNormalized = false
                break
            }
        }
        let qs: [Range<Int>] = isNormalized ? queries : normalizeRanges(queries)
        if qs.isEmpty {
            return []
        }
        if qs[qs.count - 1].upperBound <= pairs[0].0.lowerBound
            || pairs[pairs.count - 1].0.upperBound <= qs[0].lowerBound
        {
            return []
        }

        var mapped: [Range<Int>] = []
        // Binary search `partition_point(|(src, _)| src.end <= qs[0].start)`.
        var lo = 0
        var hi = pairs.count
        let firstTarget = qs[0].lowerBound
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if pairs[mid].0.upperBound <= firstTarget {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var idx = lo

        for q in qs {
            while idx < pairs.count && pairs[idx].0.upperBound <= q.lowerBound {
                idx += 1
            }
            if idx >= pairs.count {
                break
            }
            var j = idx
            while j < pairs.count && pairs[j].0.lowerBound < q.upperBound {
                let (src, out) = pairs[j]
                if let r = mapSegment(q, src, out, outBytes) {
                    if let prev = mapped.last,
                       prev.upperBound >= r.lowerBound || isPadOnly(outBytes, prev.upperBound..<r.lowerBound)
                    {
                        mapped[mapped.count - 1] = prev.lowerBound..<max(prev.upperBound, r.upperBound)
                    } else {
                        mapped.append(r)
                    }
                }
                if src.upperBound <= q.upperBound {
                    idx = j + 1
                } else {
                    idx = j
                }
                j += 1
            }
        }
        return mapped
    }
}

private func mapSegment(
    _ query: Range<Int>,
    _ src: Range<Int>,
    _ out: Range<Int>,
    _ outBytes: [UInt8]
) -> Range<Int>? {
    let s0 = max(query.lowerBound, src.lowerBound)
    let s1 = min(query.upperBound, src.upperBound)
    guard s0 < s1 else { return nil }
    var o0: Int
    var o1: Int
    if src.count == out.count {
        o0 = out.lowerBound + (s0 - src.lowerBound)
        o1 = out.lowerBound + (s1 - src.lowerBound)
    } else {
        let a: Int
        if s0 <= src.lowerBound {
            a = out.lowerBound
        } else {
            a = out.lowerBound + ((s0 - src.lowerBound) * out.count) / src.count
        }
        let b: Int
        if s1 >= src.upperBound {
            b = out.upperBound
        } else {
            let num = (s1 - src.lowerBound) * out.count
            let divCeil = (num + src.count - 1) / src.count
            b = max(out.lowerBound + divCeil, a + 1)
        }
        o0 = a
        o1 = b
    }
    o0 = floorUtf8Boundary(outBytes, min(max(o0, out.lowerBound), min(out.upperBound, outBytes.count)))
    o1 = ceilUtf8Boundary(outBytes, min(max(o1, out.lowerBound), min(out.upperBound, outBytes.count)))
    return o0 < o1 ? (o0..<o1) : nil
}

private func isPadOnly(_ outBytes: [UInt8], _ range: Range<Int>) -> Bool {
    guard range.lowerBound >= 0,
          range.upperBound <= outBytes.count,
          range.lowerBound < range.upperBound,
          (range.count % 3) == 0
    else {
        return false
    }
    var i = range.lowerBound
    while i < range.upperBound {
        // U+202F in UTF-8 is 0xE2 0x80 0xAF.
        if outBytes[i] != 0xE2 || outBytes[i + 1] != 0x80 || outBytes[i + 2] != 0xAF {
            return false
        }
        i += 3
    }
    return true
}

func spanBounds(_ ranges: [Range<Int>]) -> Range<Int> {
    var result: Range<Int>? = nil
    for r in ranges where r.lowerBound < r.upperBound {
        if let acc = result {
            result = min(acc.lowerBound, r.lowerBound)..<max(acc.upperBound, r.upperBound)
        } else {
            result = r
        }
    }
    return result ?? (0..<0)
}

extension Range: HighlightItem where Bound == Int {
    public func intoHighlight() -> (Range<Int>, Highlight) {
        (self, Highlight.new())
    }
}

extension Array: HighlightItem where Element == Range<Int> {
    public func intoHighlight() -> (Range<Int>, Highlight) {
        (spanBounds(self), Highlight.new())
    }

    public func intoRanges() -> ([Range<Int>], Highlight) {
        (normalizeRanges(self), Highlight.new())
    }
}

extension ArraySlice: HighlightItem where Element == Range<Int> {
    public func intoHighlight() -> (Range<Int>, Highlight) {
        let arr = Array(self)
        return (spanBounds(arr), Highlight.new())
    }

    public func intoRanges() -> ([Range<Int>], Highlight) {
        (normalizeRanges(Array(self)), Highlight.new())
    }
}
