// Tests ported from: crates/rune/src/runtime/pixel_snap_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("PixelSnapTests")
struct PixelSnapTests {
    private func snap(_ r: [Float], _ motion: [Float] = [0, 0, 0, 0], _ rigid: [Float] = [0, 0]) -> [Float] {
        pixelSnapEdges(r, motion, rigid, nil) { _, c in c }.0
    }

    private func isWhole(_ v: Float) -> Bool {
        abs(v - v.rounded()) < 1e-5
    }

    @Test("Shared edges round alike without leaving a seam")
    func sharedEdgesRoundAlike() {
        let a = snap([0.0, 10.3, 50.0, 30.5])
        let b = snap([0.0, 30.5, 50.0, 52.7])
        #expect(a[3] == b[1])
        #expect(a == [0.0, 10.0, 50.0, 31.0])
    }

    @Test("Keeps at least one pixel for >= 0.5 px spans and leaves sub-half-pixel hairlines untouched")
    func keepsPixelAndThinRects() {
        let s = snap([0.0, 4.6, 9.0, 5.4])
        #expect((s[1], s[3]) == (5.0, 6.0))
        let thin = snap([0.0, 4.6, 9.0, 4.9])
        #expect((thin[1], thin[3]) == (4.6, 4.9))
    }

    @Test("Motion carries the resting sub-pixel correction smoothly")
    func motionCarriesRestingCorrection() {
        let moving = snap([0.0, 15.55, 9.0, 25.55], [0.0, 5.25, 0.0, 5.25])
        #expect(abs(moving[1] - 15.25) < 1e-4)
        #expect(abs(moving[3] - 25.25) < 1e-4)
    }

    @Test("Rigid scroll translation snaps rows as one with constant whole-pixel spacing")
    func rigidTranslationSnapsAsOne() {
        for k in 0..<64 {
            let d = -Float(k) * 0.37
            let a = snap([0.0, 10.0 + d, 9.0, 20.0 + d], [0, 0, 0, 0], [0.0, d])
            let b = snap([0.0, 22.2 + d, 9.0, 32.2 + d], [0, 0, 0, 0], [0.0, d])
            #expect(b[1] - a[3] == 2.0)
            #expect(isWhole(a[1]))
        }
    }

    @Test("Layout rects remain exact fractional points while resting painted instances snap to whole device pixels")
    func layoutRectsStayFractionalWhilePaintSnapsToWholePixels() {
        let rt = Runtime.new((), { _, _ in
            col().gap(1.1).pad(0.3).children((0..<6).map { i in
                el().key("r\(i)").size(20.0, 7.3).bg(.WHITE)
            })
        }, (24.0, 52.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)

        for k in 0..<6 {
            let e = rtElement(rt, "r\(k)")!
            let expectedY = 0.3 + Float(k) * 8.4
            #expect(abs(e.rect[1] - expectedY) < 0.02)
        }
        let paintedRects = rt.instances.filter { $0.params[1] == KIND_RECT && $0.fill[3] > 0.0 }.map(\.rect)
        #expect(paintedRects.count == 6)
        for r in paintedRects {
            #expect(r.allSatisfy(isWhole))
        }
    }
}
