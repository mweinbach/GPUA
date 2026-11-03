// Ported from: crates/rune/src/text/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! macOS glyph rasterization pipeline entry point and pure-Swift OpenType/TrueType binary table reader
//! used across `trak`, `hidden_axes`, `macos/hint`, `macos/smoothing`, and cross-platform TrueType shaping.

// PORT NOTE: Upstream `macos.rs` re-exports `macos/smoothing.rs` and relies on `swash::FontRef` for
// binary table lookups (`STAT`, `trak`, `fvar`, `head`, `glyf`, `cmap`, `hmtx`). Because GPUA uses zero
// external font-parser crates (ADR), `SfntFont` provides a bounds-checked pure-Swift sfnt/ttc reader here
// so `Trak`, `hidden_axes`, `HintMetrics`, `designOutline`, and non-Apple TrueType shaping work identically
// on macOS, iOS, Linux, Windows, Android, and WASI.

enum SfntTag {
    static let ttcf: UInt32 = 0x7474_6366 // 'ttcf'
    static let head: UInt32 = 0x6865_6164 // 'head'
    static let hhea: UInt32 = 0x6868_6561 // 'hhea'
    static let hmtx: UInt32 = 0x686D_7478 // 'hmtx'
    static let maxp: UInt32 = 0x6D61_7870 // 'maxp'
    static let cmap: UInt32 = 0x636D_6170 // 'cmap'
    static let loca: UInt32 = 0x6C6F_6361 // 'loca'
    static let glyf: UInt32 = 0x676C_7966 // 'glyf'
    static let name: UInt32 = 0x6E61_6D65 // 'name'
    static let OS2:  UInt32 = 0x4F53_2F32 // 'OS/2'
    static let STAT: UInt32 = 0x5354_4154 // 'STAT'
    static let trak: UInt32 = 0x7472_616B // 'trak'
    static let fvar: UInt32 = 0x6676_6172 // 'fvar'
    static let wght: UInt32 = 0x7767_6874 // 'wght'
    static let opsz: UInt32 = 0x6F70_737A // 'opsz'

    static func fromString(_ s: String) -> UInt32? {
        let bytes = Array(s.utf8)
        guard bytes.count == 4 else { return nil }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) |
               (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }
}

struct SfntFvarAxis: Sendable, Equatable {
    var tag: UInt32
    var minValue: Float
    var defaultValue: Float
    var maxValue: Float
    var flags: UInt16

    var isHidden: Bool { (flags & 0x0001) != 0 }
}

struct SfntFvarInstance: Sendable, Equatable {
    var coords: [Float]
}

struct SfntFvar: Sendable, Equatable {
    var axes: [SfntFvarAxis]
    var instances: [SfntFvarInstance]
}

struct SfntFont: Sendable {
    let data: [UInt8]
    let directoryOffset: Int
    private let tables: [UInt32: Range<Int>]

    init?(data: [UInt8], index: Int = 0) {
        guard data.count >= 12, index >= 0 else { return nil }
        self.data = data

        func rU16(_ off: Int) -> UInt16? {
            guard off >= 0, off + 2 <= data.count else { return nil }
            return (UInt16(data[off]) << 8) | UInt16(data[off + 1])
        }
        func rU32(_ off: Int) -> UInt32? {
            guard off >= 0, off + 4 <= data.count else { return nil }
            return (UInt32(data[off]) << 24) | (UInt32(data[off + 1]) << 16) |
                   (UInt32(data[off + 2]) << 8) | UInt32(data[off + 3])
        }

        guard let sig = rU32(0) else { return nil }
        let dirOff: Int
        if sig == SfntTag.ttcf {
            guard let numFonts = rU32(8), index < Int(numFonts),
                  let fOff = rU32(12 + index * 4)
            else { return nil }
            dirOff = Int(fOff)
        } else {
            guard index == 0 else { return nil }
            dirOff = 0
        }
        guard let numTablesU16 = rU16(dirOff + 4) else { return nil }
        let numTables = Int(numTablesU16)
        guard dirOff + 12 + numTables * 16 <= data.count else { return nil }

        var map: [UInt32: Range<Int>] = [:]
        map.reserveCapacity(numTables)
        for i in 0..<numTables {
            let rec = dirOff + 12 + i * 16
            guard let tag = rU32(rec),
                  let tOff = rU32(rec + 8),
                  let tLen = rU32(rec + 12)
            else { continue }
            let start = Int(tOff)
            let end = start + Int(tLen)
            if start >= 0 && end >= start && end <= data.count {
                map[tag] = start..<end
            }
        }
        self.directoryOffset = dirOff
        self.tables = map
    }

    static func faceCount(in data: [UInt8]) -> Int {
        guard data.count >= 12 else { return 0 }
        let sig = (UInt32(data[0]) << 24) | (UInt32(data[1]) << 16) | (UInt32(data[2]) << 8) | UInt32(data[3])
        if sig == SfntTag.ttcf {
            let n = (UInt32(data[8]) << 24) | (UInt32(data[9]) << 16) | (UInt32(data[10]) << 8) | UInt32(data[11])
            return Int(min(n, 256))
        }
        return 1
    }

    func tableRange(_ tag: UInt32) -> Range<Int>? {
        tables[tag]
    }

    func tableBytes(_ tag: UInt32) -> ArraySlice<UInt8>? {
        guard let r = tables[tag] else { return nil }
        return data[r]
    }

    @inline(__always)
    func u16(_ at: Int) -> UInt16? {
        guard at >= 0, at + 2 <= data.count else { return nil }
        return (UInt16(data[at]) << 8) | UInt16(data[at + 1])
    }

    @inline(__always)
    func i16(_ at: Int) -> Int16? {
        guard let v = u16(at) else { return nil }
        return Int16(bitPattern: v)
    }

    @inline(__always)
    func u32(_ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= data.count else { return nil }
        return (UInt32(data[at]) << 24) | (UInt32(data[at + 1]) << 16) |
               (UInt32(data[at + 2]) << 8) | UInt32(data[at + 3])
    }

    @inline(__always)
    func fixed(_ at: Int) -> Float? {
        guard let v = u32(at) else { return nil }
        return Float(Int32(bitPattern: v)) / 65536.0
    }

    func unitsPerEm() -> UInt16? {
        guard let head = tables[SfntTag.head], head.count >= 20 else { return nil }
        return u16(head.lowerBound + 18)
    }

    func headYMax() -> Int16? {
        guard let head = tables[SfntTag.head], head.count >= 44 else { return nil }
        return i16(head.lowerBound + 42)
    }

    func indexToLocFormat() -> Int16? {
        guard let head = tables[SfntTag.head], head.count >= 52 else { return nil }
        return i16(head.lowerBound + 50)
    }

    func numGlyphs() -> Int {
        guard let maxp = tables[SfntTag.maxp], maxp.count >= 6,
              let n = u16(maxp.lowerBound + 4)
        else { return 0 }
        return Int(n)
    }

    func hheaMetrics() -> (ascent: Int16, descent: Int16, lineGap: Int16, numHMetrics: UInt16)? {
        guard let hhea = tables[SfntTag.hhea], hhea.count >= 36,
              let asc = i16(hhea.lowerBound + 4),
              let desc = i16(hhea.lowerBound + 6),
              let gap = i16(hhea.lowerBound + 8),
              let nhm = u16(hhea.lowerBound + 34)
        else { return nil }
        return (asc, desc, gap, nhm)
    }

    func os2WeightAndItalic() -> (weight: UInt16, italic: Bool) {
        var weight: UInt16 = 400
        var italic = false
        if let os2 = tables[SfntTag.OS2], os2.count >= 64 {
            if let w = u16(os2.lowerBound + 4), w >= 1, w <= 1000 {
                weight = w
            }
            if let fsSelection = u16(os2.lowerBound + 62) {
                italic = (fsSelection & 0x0201) != 0 // ITALIC (bit 0) or OBLIQUE (bit 9)
            }
        } else if let head = tables[SfntTag.head], head.count >= 46, let macStyle = u16(head.lowerBound + 44) {
            if (macStyle & 1) != 0 { weight = 700 }
            if (macStyle & 2) != 0 { italic = true }
        }
        return (weight, italic)
    }

    func advanceWidth(_ glyph: UInt16) -> UInt16? {
        guard let hmtx = tables[SfntTag.hmtx],
              let hhea = hheaMetrics(),
              hhea.numHMetrics > 0
        else { return nil }
        let idx = min(Int(glyph), Int(hhea.numHMetrics) - 1)
        let off = hmtx.lowerBound + idx * 4
        guard off + 2 <= hmtx.upperBound else { return nil }
        return u16(off)
    }

    func nameString(nameId: UInt16) -> String? {
        guard let name = tables[SfntTag.name], name.count >= 6,
              let countU16 = u16(name.lowerBound + 2),
              let stringOffU16 = u16(name.lowerBound + 4)
        else { return nil }
        let count = Int(countU16)
        let storage = name.lowerBound + Int(stringOffU16)
        var fallback: String? = nil
        for i in 0..<count {
            let rec = name.lowerBound + 6 + i * 12
            guard rec + 12 <= name.upperBound,
                  let platform = u16(rec),
                  let encoding = u16(rec + 2),
                  let nid = u16(rec + 6),
                  let length = u16(rec + 8),
                  let offset = u16(rec + 10)
            else { continue }
            if nid != nameId { continue }
            let sStart = storage + Int(offset)
            let sEnd = sStart + Int(length)
            guard sStart >= name.lowerBound, sEnd <= name.upperBound else { continue }
            if platform == 3 || platform == 0 {
                // UTF-16BE
                var u16s: [UInt16] = []
                u16s.reserveCapacity(Int(length) / 2)
                var p = sStart
                while p + 2 <= sEnd {
                    u16s.append((UInt16(data[p]) << 8) | UInt16(data[p + 1]))
                    p += 2
                }
                let decoded = String(decoding: u16s, as: UTF16.self)
                if !decoded.isEmpty {
                    return decoded
                }
            } else if platform == 1 && encoding == 0 && fallback == nil {
                let decoded = String(decoding: data[sStart..<sEnd], as: UTF8.self)
                if !decoded.isEmpty {
                    fallback = decoded
                }
            }
        }
        return fallback
    }

    func familyName() -> String? {
        // Typographic family (16) preferred over legacy family (1)
        nameString(nameId: 16) ?? nameString(nameId: 1)
    }

    func fullName() -> String? {
        nameString(nameId: 4)
    }

    func postScriptName() -> String? {
        nameString(nameId: 6)
    }

    func parseFvar() -> SfntFvar? {
        guard let fvar = tables[SfntTag.fvar], fvar.count >= 16,
              let axesOffsetU16 = u16(fvar.lowerBound + 4),
              let axisCountU16 = u16(fvar.lowerBound + 8),
              let axisSizeU16 = u16(fvar.lowerBound + 10),
              let instanceCountU16 = u16(fvar.lowerBound + 12),
              let instanceSizeU16 = u16(fvar.lowerBound + 14)
        else { return nil }
        let axesStart = fvar.lowerBound + Int(axesOffsetU16)
        let axisCount = Int(axisCountU16)
        let axisSize = Int(axisSizeU16)
        let instanceCount = Int(instanceCountU16)
        let instanceSize = Int(instanceSizeU16)
        guard axisCount > 0, axisSize >= 20, instanceSize >= 4 + axisCount * 4 else { return nil }
        let instancesStart = axesStart + axisCount * axisSize
        guard instancesStart <= fvar.upperBound else { return nil }

        var axes: [SfntFvarAxis] = []
        axes.reserveCapacity(axisCount)
        for i in 0..<axisCount {
            let off = axesStart + i * axisSize
            guard off + 20 <= fvar.upperBound,
                  let tag = u32(off),
                  let minV = fixed(off + 4),
                  let defV = fixed(off + 8),
                  let maxV = fixed(off + 12),
                  let flags = u16(off + 16)
            else { return nil }
            axes.append(SfntFvarAxis(tag: tag, minValue: minV, defaultValue: defV, maxValue: maxV, flags: flags))
        }

        var instances: [SfntFvarInstance] = []
        instances.reserveCapacity(instanceCount)
        for i in 0..<instanceCount {
            let off = instancesStart + i * instanceSize
            guard off + 4 + axisCount * 4 <= fvar.upperBound else { break }
            var coords: [Float] = []
            coords.reserveCapacity(axisCount)
            for a in 0..<axisCount {
                guard let c = fixed(off + 4 + a * 4) else { break }
                coords.append(c)
            }
            if coords.count == axisCount {
                instances.append(SfntFvarInstance(coords: coords))
            }
        }
        return SfntFvar(axes: axes, instances: instances)
    }

    func glyphId(for scalar: UnicodeScalar) -> UInt16? {
        guard let cmap = tables[SfntTag.cmap], cmap.count >= 4,
              let numSub = u16(cmap.lowerBound + 2)
        else { return nil }
        let cp = scalar.value
        var format12Off: Int? = nil
        var format4Off: Int? = nil

        for i in 0..<Int(numSub) {
            let rec = cmap.lowerBound + 4 + i * 8
            guard rec + 8 <= cmap.upperBound,
                  let platform = u16(rec),
                  let encoding = u16(rec + 2),
                  let subOffU32 = u32(rec + 4)
            else { continue }
            let subOff = cmap.lowerBound + Int(subOffU32)
            guard subOff + 2 <= cmap.upperBound, let fmt = u16(subOff) else { continue }
            let unicodePlatform = (platform == 0) || (platform == 3 && (encoding == 1 || encoding == 10))
            if unicodePlatform {
                if fmt == 12 && format12Off == nil { format12Off = subOff }
                if fmt == 4 && format4Off == nil { format4Off = subOff }
            }
        }

        if let sub = format12Off, sub + 16 <= cmap.upperBound, let nGroups = u32(sub + 12) {
            let groupsStart = sub + 16
            var lo = 0
            var hi = Int(nGroups)
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                let gOff = groupsStart + mid * 12
                guard gOff + 12 <= cmap.upperBound,
                      let startCode = u32(gOff),
                      let endCode = u32(gOff + 4),
                      let startGlyph = u32(gOff + 8)
                else { break }
                if cp < startCode {
                    hi = mid
                } else if cp > endCode {
                    lo = mid + 1
                } else {
                    return UInt16(truncatingIfNeeded: startGlyph &+ (cp &- startCode))
                }
            }
        }

        if cp <= 0xFFFF, let sub = format4Off, sub + 14 <= cmap.upperBound, let segCountX2 = u16(sub + 6) {
            let segCount = Int(segCountX2) / 2
            let endCodes = sub + 14
            let startCodes = endCodes + segCount * 2 + 2
            let idDeltas = startCodes + segCount * 2
            let idRangeOffsets = idDeltas + segCount * 2
            guard idRangeOffsets + segCount * 2 <= cmap.upperBound else { return nil }
            let cp16 = UInt16(cp)
            var lo = 0
            var hi = segCount
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                guard let endC = u16(endCodes + mid * 2) else { return nil }
                if cp16 > endC {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            if lo < segCount,
               let endC = u16(endCodes + lo * 2),
               let startC = u16(startCodes + lo * 2),
               cp16 >= startC && cp16 <= endC,
               let delta = i16(idDeltas + lo * 2),
               let rangeOff = u16(idRangeOffsets + lo * 2)
            {
                if rangeOff == 0 {
                    return UInt16(truncatingIfNeeded: Int(cp16) + Int(delta))
                } else {
                    let glyphOff = idRangeOffsets + lo * 2 + Int(rangeOff) + Int(cp16 - startC) * 2
                    guard glyphOff + 2 <= cmap.upperBound, let gid = u16(glyphOff) else { return 0 }
                    if gid == 0 { return 0 }
                    return UInt16(truncatingIfNeeded: Int(gid) + Int(delta))
                }
            }
        }

        return 0
    }

    private func glyfSlice(_ glyph: UInt16) -> Range<Int>? {
        guard let loca = tables[SfntTag.loca],
              let glyf = tables[SfntTag.glyf],
              let locFmt = indexToLocFormat()
        else { return nil }
        let gid = Int(glyph)
        let off0: Int
        let off1: Int
        if locFmt == 0 {
            let p = loca.lowerBound + gid * 2
            guard p + 4 <= loca.upperBound,
                  let a = u16(p),
                  let b = u16(p + 2)
            else { return nil }
            off0 = Int(a) * 2
            off1 = Int(b) * 2
        } else {
            let p = loca.lowerBound + gid * 4
            guard p + 8 <= loca.upperBound,
                  let a = u32(p),
                  let b = u32(p + 4)
            else { return nil }
            off0 = Int(a)
            off1 = Int(b)
        }
        guard off1 >= off0, glyf.lowerBound + off1 <= glyf.upperBound else { return nil }
        return (glyf.lowerBound + off0)..<(glyf.lowerBound + off1)
    }

    func glyphMaxY(_ glyph: UInt16) -> Double? {
        let pts = rawGlyphPoints(glyph, depth: 0)
        guard let points = pts, !points.isEmpty else { return nil }
        var maxY = -Double.infinity
        for contour in points {
            for p in contour {
                if p.y > maxY { maxY = p.y }
            }
        }
        return maxY.isFinite ? maxY : nil
    }

    func glyphOutline(_ glyph: UInt16, ppem: Double) -> MacosPath? {
        guard let upem = unitsPerEm(), upem > 0 else { return nil }
        guard let contours = rawGlyphPoints(glyph, depth: 0) else { return nil }
        if contours.isEmpty { return [] }
        let scale = ppem / Double(upem)
        let sc = { (x: Double, y: Double) -> MacosPoint in
            MacosPoint(Double(Float(x)) * scale, Double(Float(y)) * scale)
        }

        var path: MacosPath = []
        for contour in contours {
            let m = contour.count
            guard m > 0 else { continue }
            let firstPt: (x: Double, y: Double)
            let startIdx: Int
            let endIdx: Int
            if contour[0].onCurve {
                firstPt = (contour[0].x, contour[0].y)
                startIdx = 1
                endIdx = m
            } else if contour[m - 1].onCurve {
                firstPt = (contour[m - 1].x, contour[m - 1].y)
                startIdx = 0
                endIdx = m - 1
            } else {
                firstPt = (
                    0.5 * (contour[m - 1].x + contour[0].x),
                    0.5 * (contour[m - 1].y + contour[0].y)
                )
                startIdx = 0
                endIdx = m
            }
            path.append(.move(sc(firstPt.x, firstPt.y)))
            var pendingOff: (x: Double, y: Double)? = nil
            if startIdx < endIdx {
                for idx in startIdx..<endIdx {
                    let pt = contour[idx]
                    if pt.onCurve {
                        if let ctrl = pendingOff {
                            path.append(.quad(sc(ctrl.x, ctrl.y), sc(pt.x, pt.y)))
                            pendingOff = nil
                        } else {
                            path.append(.line(sc(pt.x, pt.y)))
                        }
                    } else {
                        if let ctrl = pendingOff {
                            let mid = (0.5 * (ctrl.x + pt.x), 0.5 * (ctrl.y + pt.y))
                            path.append(.quad(sc(ctrl.x, ctrl.y), sc(mid.0, mid.1)))
                        }
                        pendingOff = (pt.x, pt.y)
                    }
                }
            }
            if let ctrl = pendingOff {
                path.append(.quad(sc(ctrl.x, ctrl.y), sc(firstPt.x, firstPt.y)))
            }
            path.append(.close)
        }
        return path
    }

    private struct RawContourPoint {
        var x: Double
        var y: Double
        var onCurve: Bool
    }

    private func rawGlyphPoints(_ glyph: UInt16, depth: Int) -> [[RawContourPoint]]? {
        guard depth < 16, let slice = glyfSlice(glyph) else { return nil }
        if slice.isEmpty { return [] }
        guard slice.count >= 10, let nContours = i16(slice.lowerBound) else { return nil }
        if nContours == 0 { return [] }

        if nContours > 0 {
            let count = Int(nContours)
            let endsBase = slice.lowerBound + 10
            guard endsBase + count * 2 + 2 <= slice.upperBound else { return nil }
            var endPts: [Int] = []
            endPts.reserveCapacity(count)
            for i in 0..<count {
                guard let ep = u16(endsBase + i * 2) else { return nil }
                endPts.append(Int(ep))
            }
            guard let lastPt = endPts.last, lastPt >= 0 else { return [] }
            let numPts = lastPt + 1
            guard let instrLen = u16(endsBase + count * 2) else { return nil }
            var p = endsBase + count * 2 + 2 + Int(instrLen)
            guard p <= slice.upperBound else { return nil }

            var flags: [UInt8] = []
            flags.reserveCapacity(numPts)
            while flags.count < numPts {
                guard p < slice.upperBound else { return nil }
                let f = data[p]
                p += 1
                flags.append(f)
                if (f & 0x08) != 0 {
                    guard p < slice.upperBound else { return nil }
                    let rep = Int(data[p])
                    p += 1
                    for _ in 0..<rep where flags.count < numPts {
                        flags.append(f)
                    }
                }
            }

            var xs = [Double](repeating: 0, count: numPts)
            var curX = 0
            for i in 0..<numPts {
                let f = flags[i]
                if (f & 0x02) != 0 {
                    guard p < slice.upperBound else { return nil }
                    let dx = Int(data[p])
                    p += 1
                    curX += ((f & 0x10) != 0) ? dx : -dx
                } else if (f & 0x10) == 0 {
                    guard let dx = i16(p), p + 2 <= slice.upperBound else { return nil }
                    p += 2
                    curX += Int(dx)
                }
                xs[i] = Double(curX)
            }

            var ys = [Double](repeating: 0, count: numPts)
            var curY = 0
            for i in 0..<numPts {
                let f = flags[i]
                if (f & 0x04) != 0 {
                    guard p < slice.upperBound else { return nil }
                    let dy = Int(data[p])
                    p += 1
                    curY += ((f & 0x20) != 0) ? dy : -dy
                } else if (f & 0x20) == 0 {
                    guard let dy = i16(p), p + 2 <= slice.upperBound else { return nil }
                    p += 2
                    curY += Int(dy)
                }
                ys[i] = Double(curY)
            }

            var contours: [[RawContourPoint]] = []
            contours.reserveCapacity(count)
            var start = 0
            for end in endPts {
                guard end >= start, end < numPts else { return nil }
                var c: [RawContourPoint] = []
                c.reserveCapacity(end - start + 1)
                for k in start...end {
                    c.append(RawContourPoint(x: xs[k], y: ys[k], onCurve: (flags[k] & 0x01) != 0))
                }
                contours.append(c)
                start = end + 1
            }
            return contours
        } else {
            // Composite glyph (`nContours < 0`)
            var p = slice.lowerBound + 10
            var allContours: [[RawContourPoint]] = []
            while true {
                guard p + 4 <= slice.upperBound,
                      let flags = u16(p),
                      let subGid = u16(p + 2)
                else { return nil }
                p += 4
                let argsAreWords = (flags & 0x0001) != 0
                let argsAreXY = (flags & 0x0002) != 0
                var dx = 0.0
                var dy = 0.0
                if argsAreWords {
                    guard p + 4 <= slice.upperBound, let a = i16(p), let b = i16(p + 2) else { return nil }
                    p += 4
                    if argsAreXY { dx = Double(a); dy = Double(b) }
                } else {
                    guard p + 2 <= slice.upperBound else { return nil }
                    let a = Int8(bitPattern: data[p])
                    let b = Int8(bitPattern: data[p + 1])
                    p += 2
                    if argsAreXY { dx = Double(a); dy = Double(b) }
                }
                var xx = 1.0, xy = 0.0, yx = 0.0, yy = 1.0
                let readF2Dot14 = { (off: Int) -> Double? in
                    guard let v = i16(off) else { return nil }
                    return Double(v) / 16384.0
                }
                if (flags & 0x0008) != 0 {
                    guard p + 2 <= slice.upperBound, let s = readF2Dot14(p) else { return nil }
                    p += 2
                    xx = s; yy = s
                } else if (flags & 0x0040) != 0 {
                    guard p + 4 <= slice.upperBound, let sx = readF2Dot14(p), let sy = readF2Dot14(p + 2) else { return nil }
                    p += 4
                    xx = sx; yy = sy
                } else if (flags & 0x0080) != 0 {
                    guard p + 8 <= slice.upperBound,
                          let a = readF2Dot14(p), let b = readF2Dot14(p + 2),
                          let c = readF2Dot14(p + 4), let d = readF2Dot14(p + 6)
                    else { return nil }
                    p += 8
                    xx = a; xy = b; yx = c; yy = d
                }
                if let subContours = rawGlyphPoints(subGid, depth: depth + 1) {
                    for contour in subContours {
                        allContours.append(contour.map { pt in
                            RawContourPoint(
                                x: pt.x * xx + pt.y * yx + dx,
                                y: pt.x * xy + pt.y * yy + dy,
                                onCurve: pt.onCurve
                            )
                        })
                    }
                }
                if (flags & 0x0020) == 0 { // MORE_COMPONENTS
                    break
                }
            }
            return allContours
        }
    }
}
