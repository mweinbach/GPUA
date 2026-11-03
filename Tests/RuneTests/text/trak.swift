// Tests ported from: crates/rune/src/text/trak.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("AAT trak table parsing and spacing")
struct TrakTests {
    /// Part of the macOS system font's track-0 row.
    private func systemTrak() -> Trak {
        let sizes: [(Float, Float)] = [
            (12.0, 0.0),
            (13.0, -12.0),
            (14.0, -22.0),
            (24.0, 6.0),
            (28.0, 28.0),
            (32.0, 26.0),
            (36.0, 21.0)
        ]
        return Trak(sizes: sizes, unitsPerEm: 2048.0)
    }

    /// A `trak` table with one horizontal track per `(track, values)` at `sizes`.
    private func buildTable(_ tracks: [(Float, [Int16])], _ sizes: [Float]) -> [UInt8] {
        func fixed(_ v: Float) -> [UInt8] {
            let raw = UInt32(bitPattern: Int32(v * 65536.0))
            return [UInt8((raw >> 24) & 0xff), UInt8((raw >> 16) & 0xff), UInt8((raw >> 8) & 0xff), UInt8(raw & 0xff)]
        }
        func be16(_ v: UInt16) -> [UInt8] {
            [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        }
        func be32(_ v: UInt32) -> [UInt8] {
            [UInt8((v >> 24) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
        }
        let sizeTable = 12 + 8 + tracks.count * 8
        let values = sizeTable + sizes.count * 4
        var t: [UInt8] = [0, 1, 0, 0, 0, 0, 0, 12, 0, 0, 0, 0]
        t.append(contentsOf: be16(UInt16(tracks.count)))
        t.append(contentsOf: be16(UInt16(sizes.count)))
        t.append(contentsOf: be32(UInt32(sizeTable)))
        for (i, (track, _)) in tracks.enumerated() {
            t.append(contentsOf: fixed(track))
            t.append(contentsOf: [0, 0])
            t.append(contentsOf: be16(UInt16(values + i * sizes.count * 2)))
        }
        for s in sizes {
            t.append(contentsOf: fixed(s))
        }
        for (_, vals) in tracks {
            for v in vals {
                t.append(contentsOf: be16(UInt16(bitPattern: v)))
            }
        }
        return t
    }

    private func put(_ t: inout [UInt8], _ at: Int, _ bytes: [UInt8]) {
        for (k, b) in bytes.enumerated() {
            t[at + k] = b
        }
    }

    @discardableResult
    private func sane(_ t: Trak?) -> Float {
        let spacing = t.map { $0.spacing(28.0, 14.0, true) + $0.spacing(9.0, 9.0, false) } ?? 0.0
        #expect(spacing.isFinite)
        return spacing
    }

    private func assertSizes(_ trak: Trak?, _ want: [(Float, Float)]) {
        #expect(trak != nil)
        guard let trak else { return }
        #expect(trak.sizes.count == want.count)
        for (a, b) in zip(trak.sizes, want) {
            #expect(a.0 == b.0)
            #expect(a.1 == b.1)
        }
    }

    @Test("spacing_moves_tracking_from_the_pixel_size_to_the_point_size")
    func spacingMovesTrackingFromPixelSizeToPointSize() {
        let t = systemTrak()
        // 14 pt at 2x: HarfRust tracked 28 px by +28 units; 14 pt wants -22.
        #expect(abs(t.spacing(28.0, 14.0, true) - (-22.0 - 28.0) * 28.0 / 2048.0) < 1e-5)
        // At 1x, listed sizes need nothing.
        #expect(t.spacing(14.0, 14.0, true) == 0.0)
        // Off removes what HarfRust applied.
        #expect(abs(t.spacing(14.0, 14.0, false) - 22.0 * 14.0 / 2048.0) < 1e-5)
        // Between listed sizes Core Text truncates and HarfRust rounds: 33 pt is 24.75 units.
        #expect(abs(t.spacing(33.0, 33.0, true) - (24.0 - 25.0) * 33.0 / 2048.0) < 1e-5)
        // An explicit optical size of 14 pt at 28 pt, 2x: 14 pt's -22 units, at the real size.
        #expect(abs(t.spacing(56.0, 14.0, true) - (-22.0 - t.units(56.0).rounded(.toNearestOrAwayFromZero)) * 56.0 / 2048.0) < 1e-5)
        // Beyond the table the ends hold.
        #expect(t.units(8.0) == 0.0)
        #expect(t.units(500.0) == 21.0)
    }

    @Test("parse_reads_track_zero_or_interpolates_around_it")
    func parseReadsTrackZeroOrInterpolatesAroundIt() {
        let sizes: [Float] = [12.0, 24.0]
        let t1 = Trak.parse(buildTable([(-1.0, [-40, -20]), (0.0, [0, 10]), (1.0, [40, 20])], sizes), 2048)
        assertSizes(t1, [(12.0, 0.0), (24.0, 10.0)])

        let t2 = Trak.parse(buildTable([(-1.0, [-40, -20]), (1.0, [40, 60])], sizes), 2048)
        assertSizes(t2, [(12.0, 0.0), (24.0, 20.0)])

        let t3 = Trak.parse(buildTable([(0.5, [8, 16])], sizes), 2048)
        assertSizes(t3, [(12.0, 8.0), (24.0, 16.0)])
    }

    @Test("malformed_tables_track_nothing_without_panicking")
    func malformedTablesTrackNothingWithoutPanicking() {
        let good = buildTable([(-1.0, [-40, -20]), (0.0, [0, 10]), (1.0, [40, 20])], [12.0, 24.0])
        #expect(Trak.parse(good, 0) == nil)
        for len in 0..<good.count {
            sane(Trak.parse(good[0..<len], 2048))
        }
        var hugeOffsets = good
        put(&hugeOffsets, 6, [0xff, 0xff])
        #expect(Trak.parse(hugeOffsets, 2048) == nil)

        var hugeSizeTable = good
        put(&hugeSizeTable, 16, [0xff, 0xff, 0xff, 0xff])
        #expect(Trak.parse(hugeSizeTable, 2048) == nil)

        var hugeCounts = good
        put(&hugeCounts, 12, [0xff, 0xff, 0xff, 0xff])
        #expect(Trak.parse(hugeCounts, 2048) == nil)

        // Track 0's values out of bounds: it tracks by 0, as in HarfRust.
        var badValues = good
        put(&badValues, 20 + 8 + 6, [0xff, 0xff])
        assertSizes(Trak.parse(badValues, 2048), [(12.0, 0.0), (24.0, 0.0)])

        // A bad offset on a track that isn't used doesn't spoil the table.
        var badUnused = good
        put(&badUnused, 20 + 6, [0xff, 0xff])
        assertSizes(Trak.parse(badUnused, 2048), [(12.0, 0.0), (24.0, 10.0)])

        for at in 0..<good.count {
            var corrupted = good
            corrupted[at] = 0xff
            sane(Trak.parse(corrupted, 2048))
        }
    }
}
