// Tests ported from: crates/rune/src/runtime/bands_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("BandsTests")
struct BandsTests {
    private func makeShadow(_ rect: [Float], _ sigma: Float) -> Instance {
        Instance(
            rect: rect,
            radii: [16.0, 16.0, 16.0, 16.0],
            fill: [0.0, 0.0, 0.0, 0.3],
            border: [0.0, 0.0, 0.0, 0.0],
            params: [0.0, KIND_SHADOW, sigma, 1.0],
            uv: [0.0, 0.0, 0.0, 0.0],
            clip: NO_CLIP,
            fade: [0, 0, 0, 0]
        )
    }

    private func windows(_ out: [Instance], _ grow: Float) -> [[Float]] {
        out.map { i in
            let x = i.rect[0], y = i.rect[1], w = i.rect[2], h = i.rect[3]
            let u0 = i.uv[0], v0 = i.uv[1], u1 = i.uv[2], v1 = i.uv[3]
            #expect(u1 < 0.0)
            return [
                max(x - grow, x + u0),
                max(y - grow, y + v0),
                min(x + w + grow, x - u1),
                min(y + h + grow, y + v1),
            ]
        }
    }

    private func area(_ r: [Float]) -> Float {
        max(0.0, r[2] - r[0]) * max(0.0, r[3] - r[1])
    }

    @Test("A big shadow draws as four non-overlapping bands around the box")
    func bigShadowDrawsAsFourBands() {
        var out: [Instance] = []
        let caster: [Float] = [100.0, 100.0, 1000.0, 600.0]
        pushShadowBands(&out, makeShadow([100.0, 104.0, 1000.0, 600.0], 4.0), caster, [16.0, 16.0, 16.0, 16.0])
        #expect(out.count == 4)

        let grow: Float = 4.0 * 3.0 + 1.0
        let bands = windows(out, grow)
        let quad: [Float] = [100.0 - grow, 104.0 - grow, 1100.0 + grow, 704.0 + grow]
        let hole: [Float] = [117.0, 117.0, 1083.0, 683.0]
        let total = bands.reduce(Float(0.0)) { $0 + area($1) }
        #expect(abs(total - (area(quad) - area(hole))) < 0.01)

        for k in 0..<bands.count {
            for j in (k + 1)..<bands.count {
                let a = bands[k], b = bands[j]
                let inter = area([max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])])
                #expect(inter == 0.0)
            }
        }
    }

    @Test("A small shadow or pre-holed shadow stays one quad")
    func smallOrPreHoledShadowStaysOneQuad() {
        var out: [Instance] = []
        pushShadowBands(&out, makeShadow([0.0, 2.0, 120.0, 80.0], 4.0), [0.0, 0.0, 120.0, 80.0], [8.0, 8.0, 8.0, 8.0])
        #expect(out.count == 1)
        #expect(out[0].uv == [0.0, 0.0, 0.0, 0.0])

        var holedOut: [Instance] = []
        var preHoled = makeShadow([0.0, 0.0, 1000.0, 600.0], 4.0)
        preHoled.uv = [0.0, 0.0, 1000.0, 600.0]
        pushShadowBands(&holedOut, preHoled, [0.0, 0.0, 1000.0, 600.0], [8.0, 8.0, 8.0, 8.0])
        #expect(holedOut.count == 1)
    }

    @Test("A big border ring draws as four non-overlapping bands")
    func bigBorderRingDrawsAsBands() {
        var out: [Instance] = []
        let ring = Instance(
            rect: [10.0, 10.0, 800.0, 500.0],
            radii: [-16.0, -16.0, -16.0, -16.0],
            fill: [0.0, 0.0, 0.0, 0.0],
            border: [1.0, 1.0, 1.0, 1.0],
            params: [1.0, KIND_RECT, 0.0, 1.0],
            uv: [0.0, 0.0, 0.0, 0.0],
            clip: NO_CLIP,
            fade: [0, 0, 0, 0]
        )
        pushRingBands(&out, ring)
        #expect(out.count == 4)
        let bands = windows(out, 1.0)
        let e: Float = 16.0 * 1.528665 + 1.0 + 0.5 + 1.0
        let hole: [Float] = [10.0 + e, 10.0 + e, 810.0 - e, 510.0 - e]
        let total = bands.reduce(Float(0.0)) { $0 + area($1) }
        #expect(abs(total - (area([9.0, 9.0, 811.0, 511.0]) - area(hole))) < 1.0)
    }
}
