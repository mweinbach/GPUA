// Ported from: crates/rune/src/text/trak.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The AAT `trak` table: tracking that depends on the point size. Core Text applies it at track 0
//! to fonts that also have a `STAT` table (the macOS system font among them).

/// A font's horizontal track-0 tracking, in font units, at each point size its table lists.
final class Trak: Sendable, Equatable {
    let sizes: [(Float, Float)]
    let unitsPerEm: Float

    init(sizes: [(Float, Float)], unitsPerEm: Float) {
        self.sizes = sizes
        self.unitsPerEm = unitsPerEm
    }

    static func == (lhs: Trak, rhs: Trak) -> Bool {
        guard lhs.unitsPerEm == rhs.unitsPerEm, lhs.sizes.count == rhs.sizes.count else { return false }
        for (a, b) in zip(lhs.sizes, rhs.sizes) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }

    /// The table of a font that has both `STAT` and `trak`.
    static func of(_ sfnt: SfntFont) -> Trak? {
        guard sfnt.tableRange(SfntTag.STAT) != nil,
              let trakBytes = sfnt.tableBytes(SfntTag.trak),
              let upem = sfnt.unitsPerEm()
        else {
            return nil
        }
        return parse(trakBytes, upem)
    }

    /// Track 0 of a `trak` table, or the interpolation between the tracks around it, read the way
    /// HarfRust reads it: a table it can't read tracks nothing, and a track whose values it can't
    /// read tracks by 0. Fonts can be untrusted, so every offset is checked.
    static func parse(_ data: [UInt8], _ unitsPerEm: UInt16) -> Trak? {
        return data.withUnsafeBufferPointer { buf in
            parseBuffer(buf, unitsPerEm)
        }
    }

    static func parse(_ data: ArraySlice<UInt8>, _ unitsPerEm: UInt16) -> Trak? {
        return Array(data).withUnsafeBufferPointer { buf in
            parseBuffer(buf, unitsPerEm)
        }
    }

    private static func parseBuffer(_ data: UnsafeBufferPointer<UInt8>, _ unitsPerEm: UInt16) -> Trak? {
        guard unitsPerEm != 0 else { return nil }
        let n = data.count

        func hasRange(_ at: Int, _ len: Int) -> Bool {
            guard at >= 0, len >= 0 else { return false }
            let (end, ov) = at.addingReportingOverflow(len)
            return !ov && end <= n
        }

        func u16At(_ at: Int) -> UInt16? {
            guard hasRange(at, 2) else { return nil }
            return (UInt16(data[at]) << 8) | UInt16(data[at + 1])
        }

        func u32At(_ at: Int) -> UInt32? {
            guard hasRange(at, 4) else { return nil }
            return (UInt32(data[at]) << 24) | (UInt32(data[at + 1]) << 16) |
                   (UInt32(data[at + 2]) << 8) | UInt32(data[at + 3])
        }

        func fixedAt(_ at: Int) -> Float {
            let raw = Int32(bitPattern:
                (UInt32(data[at]) << 24) | (UInt32(data[at + 1]) << 16) |
                (UInt32(data[at + 2]) << 8) | UInt32(data[at + 3])
            )
            return Float(raw) / 65536.0
        }

        guard let horizU16 = u16At(6) else { return nil }
        let horizontal = Int(horizU16)
        guard horizontal != 0 else { return nil }

        guard let tracksU16 = u16At(horizontal),
              let sizesU16 = u16At(horizontal + 2),
              let sizeTableU32 = u32At(horizontal + 4)
        else { return nil }

        let tracks = Int(tracksU16)
        let sizes = Int(sizesU16)
        guard tracks > 0, sizes > 0 else { return nil }

        let entriesStart = horizontal + 8
        let (entriesLen, ov1) = tracks.multipliedReportingOverflow(by: 8)
        guard !ov1, hasRange(entriesStart, entriesLen) else { return nil }

        guard let sizeTable = Int(exactly: sizeTableU32) else { return nil }
        let (sizesBytesLen, ov2) = sizes.multipliedReportingOverflow(by: 4)
        guard !ov2, hasRange(sizeTable, sizesBytesLen) else { return nil }

        func entryOffset(_ idx: Int) -> Int {
            entriesStart + idx * 8
        }

        func trackValue(_ idx: Int) -> Float {
            fixedAt(entryOffset(idx))
        }

        func readValues(_ idx: Int) -> [Float] {
            let eo = entryOffset(idx)
            let at = Int((UInt16(data[eo + 6]) << 8) | UInt16(data[eo + 7]))
            let (vLen, ov) = sizes.multipliedReportingOverflow(by: 2)
            guard !ov, hasRange(at, vLen) else {
                return [Float](repeating: 0.0, count: sizes)
            }
            var out: [Float] = []
            out.reserveCapacity(sizes)
            for s in 0..<sizes {
                let off = at + s * 2
                let v = Int16(bitPattern: (UInt16(data[off]) << 8) | UInt16(data[off + 1]))
                out.append(Float(v))
            }
            return out
        }

        var i = 0
        while i + 1 < tracks && trackValue(i + 1) <= 0.0 {
            i += 1
        }
        var j = tracks - 1
        while j > 0 && trackValue(j - 1) >= 0.0 {
            j -= 1
        }
        let a = readValues(i)
        let b = (i == j) ? [] : readValues(j)
        let t0 = trackValue(i)
        let t1 = trackValue(j)
        let t: Float = (i == j || abs(t1 - t0) < Float.ulpOfOne) ? 0.0 : (-t0 / (t1 - t0))

        var resultSizes: [(Float, Float)] = []
        resultSizes.reserveCapacity(sizes)
        for s in 0..<sizes {
            let sz = fixedAt(sizeTable + s * 4)
            let av = a[s]
            let val = (s < b.count) ? (av + t * (b[s] - av)) : av
            resultSizes.append((sz, val))
        }
        return Trak(sizes: resultSizes, unitsPerEm: Float(unitsPerEm))
    }

    /// Tracking at `points`, in font units: interpolated between the listed sizes and held beyond them.
    func units(_ points: Float) -> Float {
        guard let i = sizes.firstIndex(where: { $0.0 >= points }) else {
            return sizes.last?.1 ?? 0.0
        }
        if i == 0 {
            return sizes[0].1
        }
        let (s0, v0) = sizes[i - 1]
        let (s1, v1) = sizes[i]
        if abs(s1 - s0) < Float.ulpOfOne {
            return (v0 + v1) * 0.5
        }
        return v0 + (points - s0) / (s1 - s0) * (v1 - v0)
    }

    /// Letter spacing, in device px, that turns the tracking HarfRust applied to a run at `px`
    /// device pixels into Core Text's tracking for `points`-point text scaled to the run, or
    /// removes it when `on` is false. HarfRust rounds tracking to whole font units; Core Text truncates.
    func spacing(_ px: Float, _ points: Float, _ on: Bool) -> Float {
        let applied = units(px).rounded(.toNearestOrAwayFromZero)
        let wanted: Float = on ? units(points).rounded(.towardZero) : 0.0
        return (wanted - applied) * px / unitsPerEm
    }

    /// Core Text tracking in points for `points`-point lookup rendered at `fontPoints` size.
    func coreTextPoints(_ fontPoints: Float, _ lookupPoints: Float) -> Float {
        units(lookupPoints).rounded(.towardZero) * fontPoints / unitsPerEm
    }
}

struct FontBlobKey: Sendable, Equatable, Hashable {
    var id: UInt64
    var index: UInt32

    init(_ id: UInt64, _ index: UInt32) {
        self.id = id
        self.index = index
    }
}

typealias Traks = [FontBlobKey: Trak?]

func fontTrak(_ traks: inout Traks, _ id: UInt64, _ data: [UInt8], _ index: UInt32) -> Trak? {
    let key = FontBlobKey(id, index)
    if let cached = traks[key] {
        return cached
    }
    let parsed = SfntFont(data: data, index: Int(index)).flatMap { Trak.of($0) }
    traks[key] = .some(parsed)
    return parsed
}
