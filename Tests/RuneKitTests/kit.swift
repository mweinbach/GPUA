// Tests ported from: crates/rune-kit/src/kit.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private func hashOne<T: Hashable>(_ value: T) -> Int {
    var hasher = Hasher()
    value.hash(into: &hasher)
    return hasher.finalize()
}

@Test func equalTokensHashEqual() {
    let a = Kit.neutral(true)
    let b = Kit.neutral(true)
    let light = Kit.neutral(false)
    #expect(hashOne(a.c) == hashOne(b.c))
    #expect(hashOne(a.ty) == hashOne(b.ty))
    #expect(hashOne(a.radius) == hashOne(b.radius))
    #expect(hashOne(a.c) != hashOne(light.c))
    var negative = a.radius
    negative.xs = -0.0
    var zero = a.radius
    zero.xs = 0.0
    #expect(hashOne(zero) == hashOne(negative))
    var wider = a.radius
    wider.md = a.radius.md + 1.0
    #expect(hashOne(a.radius) != hashOne(wider))
    var ty = a.ty
    ty.ui = a.ty.ui.lh(a.ty.ui.lineHeight + 1.0)
    #expect(hashOne(a.ty) != hashOne(ty))
    #expect(hashOne(a.ty.ui.tracking(0.0)) == hashOne(a.ty.ui.tracking(-0.0)))
}
