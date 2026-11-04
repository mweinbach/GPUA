// Ported from: crates/rune-kit/src/diff/myers.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Myers' O(ND) difference algorithm in linear space (divide and conquer on the middle snake),
//! over any sequence of comparable items: interned lines for a file, tokens for a line.

/// One run of an edit script, in order: `.equal` advances both sides, `.delete` the old side
/// and `.insert` the new side.
enum MyersOp: Equatable, Sendable {
    case equal(old: Int, new: Int, len: Int)
    case delete(old: Int, len: Int)
    case insert(new: Int, len: Int)
}

enum myers {
    /// Past this many edits in one subproblem the search stops and splits it where it got
    /// furthest: a file rewritten wholesale costs bounded time, and what it shows is no worse.
    static let MAX_D: Int = 1024

    /// The edit script turning `a` into `b`, with each run of equal items, deletions and
    /// insertions coalesced.
    static func diff<T: Equatable>(_ a: [T], _ b: [T]) -> [MyersOp] {
        var changedA = Array(repeating: false, count: a.count)
        var changedB = Array(repeating: false, count: b.count)
        let size = a.count + b.count + 3
        var v = Vs(
            f: Array(repeating: 0, count: size),
            b: Array(repeating: 0, count: size),
            off: b.count + 1
        )
        conquer(a, 0..<a.count, b, 0..<b.count, &v, &changedA, &changedB)
        return script(changedA, changedB)
    }

    /// The furthest-reaching x per diagonal (`x - y`), forward and backward, indexed from `-off`.
    private struct Vs {
        var f: [Int]
        var b: [Int]
        var off: Int

        @inline(__always)
        func i(_ k: Int) -> Int {
            k + off
        }
    }

    @inline(__always)
    private static func prefix<T: Equatable>(_ a: [T], _ ra: Range<Int>, _ b: [T], _ rb: Range<Int>) -> Int {
        let limit = min(ra.count, rb.count)
        var k = 0
        let aStart = ra.lowerBound
        let bStart = rb.lowerBound
        while k < limit && a[aStart + k] == b[bStart + k] {
            k += 1
        }
        return k
    }

    @inline(__always)
    private static func suffix<T: Equatable>(_ a: [T], _ ra: Range<Int>, _ b: [T], _ rb: Range<Int>) -> Int {
        let limit = min(ra.count, rb.count)
        var k = 0
        let aEnd = ra.upperBound - 1
        let bEnd = rb.upperBound - 1
        while k < limit && a[aEnd - k] == b[bEnd - k] {
            k += 1
        }
        return k
    }

    private static func conquer<T: Equatable>(
        _ a: [T],
        _ raIn: Range<Int>,
        _ b: [T],
        _ rbIn: Range<Int>,
        _ v: inout Vs,
        _ ca: inout [Bool],
        _ cb: inout [Bool]
    ) {
        var ra = raIn
        var rb = rbIn
        let p = prefix(a, ra, b, rb)
        ra = (ra.lowerBound + p)..<ra.upperBound
        rb = (rb.lowerBound + p)..<rb.upperBound
        let s = suffix(a, ra, b, rb)
        ra = ra.lowerBound..<(ra.upperBound - s)
        rb = rb.lowerBound..<(rb.upperBound - s)

        if ra.isEmpty {
            for idx in rb {
                cb[idx] = true
            }
        } else if rb.isEmpty {
            for idx in ra {
                ca[idx] = true
            }
        } else if let (x, y) = middleSnake(a, ra, b, rb, &v) {
            conquer(a, ra.lowerBound..<x, b, rb.lowerBound..<y, &v, &ca, &cb)
            conquer(a, x..<ra.upperBound, b, y..<rb.upperBound, &v, &ca, &cb)
        } else {
            for idx in ra {
                ca[idx] = true
            }
            for idx in rb {
                cb[idx] = true
            }
        }
    }

    /// A point on an optimal path through `a[ra]` x `b[rb]` that splits it into two smaller
    /// halves; past `MAX_D` edits, the furthest point reached on a path from the start.
    /// Both ranges are non-empty and differ at both ends.
    /// Diagonals are `x - y` in absolute indices; each search widens by one diagonal a step until
    /// it meets the box's edge, and a neighbour outside the band reads as never reached.
    private static func middleSnake<T: Equatable>(
        _ a: [T],
        _ ra: Range<Int>,
        _ b: [T],
        _ rb: Range<Int>,
        _ v: inout Vs
    ) -> (Int, Int)? {
        let (xoff, xlim, yoff, ylim) = (ra.lowerBound, ra.upperBound, rb.lowerBound, rb.upperBound)
        let (dmin, dmax) = (xoff - ylim, xlim - yoff)
        let (fmid, bmid) = (xoff - yoff, xlim - ylim)
        var (fmin, fmax, bmin, bmax) = (fmid, fmid, bmid, bmid)
        let odd = ((fmid - bmid) & 1) != 0

        v.f[v.i(fmid)] = xoff
        v.b[v.i(bmid)] = xlim

        for _ in 1...MAX_D {
            if fmin > dmin {
                fmin -= 1
                v.f[v.i(fmin - 1)] = -1
            } else {
                fmin += 1
            }
            if fmax < dmax {
                fmax += 1
                v.f[v.i(fmax + 1)] = -1
            } else {
                fmax -= 1
            }
            var d = fmax
            while d >= fmin {
                let lo = v.f[v.i(d - 1)]
                let hi = v.f[v.i(d + 1)]
                var x = lo >= hi ? (lo + 1) : hi
                var y = x - d
                while x < xlim && y < ylim && a[x] == b[y] {
                    x += 1
                    y += 1
                }
                let idx = v.i(d)
                v.f[idx] = x
                if odd && bmin <= d && d <= bmax && v.b[idx] <= x {
                    let cx = min(max(x, xoff), xlim)
                    let cy = min(max(y, yoff), ylim)
                    if (cx, cy) != (xlim, ylim) && (cx, cy) != (xoff, yoff) {
                        return (cx, cy)
                    }
                    return nil
                }
                d -= 2
            }

            if bmin > dmin {
                bmin -= 1
                v.b[v.i(bmin - 1)] = Int.max
            } else {
                bmin += 1
            }
            if bmax < dmax {
                bmax += 1
                v.b[v.i(bmax + 1)] = Int.max
            } else {
                bmax -= 1
            }
            d = bmax
            while d >= bmin {
                let lo = v.b[v.i(d - 1)]
                let hi = v.b[v.i(d + 1)]
                var x = lo < hi ? lo : (hi - 1)
                var y = x - d
                while xoff < x && yoff < y && a[x - 1] == b[y - 1] {
                    x -= 1
                    y -= 1
                }
                let idx = v.i(d)
                v.b[idx] = x
                if !odd && fmin <= d && d <= fmax && x <= v.f[idx] {
                    let cx = min(max(x, xoff), xlim)
                    let cy = min(max(y, yoff), ylim)
                    if (cx, cy) != (xlim, ylim) && (cx, cy) != (xoff, yoff) {
                        return (cx, cy)
                    }
                    return nil
                }
                d -= 2
            }
        }

        // Too costly to finish: split where the forward search got furthest, as xdiff does, so a
        // long file with many scattered edits still diffs line by line in bounded time.
        guard fmin <= fmax else { return nil }
        var best: (Int, Int)? = nil
        var bestScore = Int.min
        var d = fmin
        while d <= fmax {
            let x = v.f[v.i(d)]
            let score = 2 * x - d
            if best == nil || score >= bestScore {
                best = (x, d)
                bestScore = score
            }
            d += 2
        }
        guard let (bx, bd) = best else { return nil }
        let cx = min(max(bx, xoff), xlim)
        let cy = min(max(bx - bd, yoff), ylim)
        if (cx, cy) != (xlim, ylim) && (cx, cy) != (xoff, yoff) {
            return (cx, cy)
        }
        return nil
    }

    /// The runs of an edit script from each side's changed flags. Deletions come before the
    /// insertions they pair with.
    private static func script(_ ca: [Bool], _ cb: [Bool]) -> [MyersOp] {
        var out: [MyersOp] = []
        var i = 0
        var j = 0
        while i < ca.count || j < cb.count {
            let si = i
            let sj = j
            while i < ca.count && j < cb.count && !ca[i] && !cb[j] {
                i += 1
                j += 1
            }
            if i > si {
                out.append(.equal(old: si, new: sj, len: i - si))
            }
            let di = i
            while i < ca.count && ca[i] {
                i += 1
            }
            if i > di {
                out.append(.delete(old: di, len: i - di))
            }
            let dj = j
            while j < cb.count && cb[j] {
                j += 1
            }
            if j > dj {
                out.append(.insert(new: dj, len: j - dj))
            }
            if i == si && j == sj {
                // Unchanged items left on one side only can't happen in a valid script; stop safely.
                break
            }
        }
        return out
    }

    /// Byte ranges of `old` and `new` that differ, by words: runs of letters, digits and `_`,
    /// runs of whitespace, and single other characters. Changes separated only by whitespace join
    /// into one range. Empty when the lines share too little for word changes to mean anything.
    static func words(_ old: String, _ new: String) -> ([Range<Int>], [Range<Int>]) {
        if old == new || old.utf8.count > 1000 || new.utf8.count > 1000 {
            return ([], [])
        }
        let oldBytes = Array(old.utf8)
        let newBytes = Array(new.utf8)
        let ta = tokens(old)
        let tb = tokens(new)
        let sa: [ArraySlice<UInt8>] = ta.map { oldBytes[$0.range] }
        let sb: [ArraySlice<UInt8>] = tb.map { newBytes[$0.range] }
        let ops = diff(sa, sb)
        var shared = 0
        var ra: [Range<Int>] = []
        var rb: [Range<Int>] = []
        for op in ops {
            switch op {
            case .equal(let o, _, let len):
                for idx in o..<(o + len) where !ta[idx].isSpace {
                    shared += ta[idx].range.count
                }
            case .delete(let o, let len):
                ra.append(ta[o].range.lowerBound..<ta[o + len - 1].range.upperBound)
            case .insert(let n, let len):
                rb.append(tb[n].range.lowerBound..<tb[n + len - 1].range.upperBound)
            }
        }
        func contentCount(_ s: String) -> Int {
            var n = 0
            for scalar in s.unicodeScalars where !scalar.properties.isWhitespace {
                n += 1
            }
            return max(n, 1)
        }
        if shared * 4 < max(contentCount(old), contentCount(new)) {
            return ([], [])
        }
        return (join(oldBytes, ra), join(newBytes, rb))
    }

    private struct TokenSpan {
        var range: Range<Int>
        var isSpace: Bool
    }

    private static func join(_ bytes: [UInt8], _ ranges: [Range<Int>]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        for r in ranges {
            if let last = out.last, allWhitespace(bytes, last.upperBound..<r.lowerBound) {
                out[out.count - 1] = last.lowerBound..<r.upperBound
            } else {
                out.append(r)
            }
        }
        return out
    }

    private static func allWhitespace(_ bytes: [UInt8], _ range: Range<Int>) -> Bool {
        if range.isEmpty {
            return true
        }
        let sub = String(decoding: bytes[range], as: UTF8.self)
        for scalar in sub.unicodeScalars where !scalar.properties.isWhitespace {
            return false
        }
        return true
    }

    private static func tokens(_ s: String) -> [TokenSpan] {
        enum K: Equatable {
            case word
            case space
            case other
        }
        var out: [TokenSpan] = []
        var prev: K? = nil
        var byteOffset = 0
        for scalar in s.unicodeScalars {
            let len = scalar.utf8.count
            let k: K
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil || scalar == "_" {
                k = .word
            } else if scalar.properties.isWhitespace {
                k = .space
            } else {
                k = .other
            }
            if !out.isEmpty, prev == k, k != .other {
                let lastIdx = out.count - 1
                out[lastIdx].range = out[lastIdx].range.lowerBound..<(byteOffset + len)
            } else {
                out.append(TokenSpan(range: byteOffset..<(byteOffset + len), isSpace: k == .space))
            }
            prev = k
            byteOffset += len
        }
        return out
    }
}
