// Tests ported from: crates/rune-motion/src/value.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

// PORT NOTE: Uses `AnimatablePair` and `AnimatableArray` in place of Rust tuples and `[T; N]`.
@Test func oklab_round_trips() {
    for c in [Color.hex(0xff3b30), Color.hex(0x34c759), Color.hex(0x007aff), Color.white] {
        let l = lanes(c)
        let back = l.withBuffer(count: 4) { Color.readLanes($0) }
        for (x, y) in [(c.r, back.r), (c.g, back.g), (c.b, back.b), (c.a, back.a)] {
            #expect(abs(x - y) < 1e-3, "\(c) → \(back)")
        }
    }
}

@Test func rect_lanes_are_edges() {
    let r = Rect.new(10.0, 20.0, 100.0, 50.0)
    let l = lanes(r)
    #expect([l[0], l[1], l[2], l[3]] == [10.0, 20.0, 110.0, 70.0])
    #expect(Rect.readLanes([10.0, 20.0, 110.0, 70.0]) == r)
}

@Test func tuples_and_arrays() {
    let v = AnimatablePair<Float, Vec2>(1.0, Vec2.new(2.0, 3.0))
    #expect(AnimatablePair<Float, Vec2>.lanes == 3)
    #expect(v.add(v) == AnimatablePair(2.0, Vec2.new(4.0, 6.0)))
    let a = AnimatableArray<Vec2, Count3>(repeating: Vec2.new(1.0, 1.0))
    #expect(AnimatableArray<Vec2, Count3>.lanes == 6)
    let zero = AnimatableArray<Vec2, Count3>(repeating: .zero)
    #expect(abs(a.distance(zero) - Float(6.0).squareRoot()) < 1e-6)
}

@Test func affine_rotates_about_anchor() {
    let t = Transform(translate: .zero, scale: Vec2(1.0, 1.0), rotate: .pi / 2.0)
    let m = t.toAffine(Vec2.new(10.0, 10.0))
    let (a, b, c, d, tx, ty) = (m[0], m[1], m[2], m[3], m[4], m[5])
    // The anchor stays put.
    let (x, y) = (a * 10.0 + c * 10.0 + tx, b * 10.0 + d * 10.0 + ty)
    #expect(abs(x - 10.0) < 1e-4 && abs(y - 10.0) < 1e-4)
}
