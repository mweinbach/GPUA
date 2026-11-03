// Tests ported from: crates/rune/src/color.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private func hashValue<T: Hashable>(_ x: T) -> Int {
    var hasher = Hasher()
    x.hash(into: &hasher)
    return hasher.finalize()
}

@Suite("ColorTests")
struct ColorTests {
    @Test("equal colours hash equal")
    func equalColoursHashEqual() {
        let a = oklcha(0.6, 0.1, 250.0, 0.5)
        #expect(hashValue(a) == hashValue(oklcha(0.6, 0.1, 250.0, 0.5)))

        let zero = Color(r: 0.0, g: Color.BLACK.g, b: Color.BLACK.b, a: Color.BLACK.a)
        let negative = Color(r: -0.0, g: Color.BLACK.g, b: Color.BLACK.b, a: Color.BLACK.a)
        #expect(zero == negative)
        #expect(hashValue(zero) == hashValue(negative))

        #expect(hashValue(a) != hashValue(a.alpha(0.6)))
        let nanPos = Color(r: a.r, g: a.g, b: a.b, a: .nan)
        let nanNeg = Color(r: a.r, g: a.g, b: a.b, a: -.nan)
        #expect(hashValue(nanPos) == hashValue(nanNeg))
    }

    @Test("hex parsing, formatting, oklab roundtrip, and source-over")
    func hexOklabAndOver() {
        #expect(hex("#fff") == Color.WHITE)
        #expect(hex("#000000") == Color.BLACK)
        #expect(hex("#00000000") == Color.TRANSPARENT)
        #expect(hex("invalid") == nil)
        #expect(hex("#12345") == nil)
        #expect(Color.WHITE.hex() == "#ffffffff")
        #expect(Color.TRANSPARENT.hex() == "#00000000")

        let c = oklcha(0.65, 0.12, 140.0, 0.75)
        let roundtrip = Color.fromOklab(c.toOklab())
        #expect(abs(roundtrip.r - c.r) < 1e-4)
        #expect(abs(roundtrip.g - c.g) < 1e-4)
        #expect(abs(roundtrip.b - c.b) < 1e-4)
        #expect(abs(roundtrip.a - c.a) < 1e-6)

        let comp = over(Color.WHITE.premul(0.5), Color.BLACK.premul(1.0))
        #expect(abs(comp[0] - 0.5) < 1e-5)
        #expect(abs(comp[3] - 1.0) < 1e-5)
    }
}
