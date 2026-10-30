// Tests ported from: src/util/resolve.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("MaybeResolveDimension")
struct MaybeResolveDimensionTests {
    @Test func resolve_auto() {
        #expect(Dimension.AUTO.maybeResolve(Float?.none) == nil)
        #expect(Dimension.AUTO.maybeResolve(Float(5.0)) == nil)
        #expect(Dimension.AUTO.maybeResolve(Float(-5.0)) == nil)
        #expect(Dimension.AUTO.maybeResolve(Float(0.0)) == nil)
    }

    @Test func resolve_length() {
        #expect(Dimension.fromLength(1.0).maybeResolve(Float?.none) == 1.0)
        #expect(Dimension.fromLength(1.0).maybeResolve(Float(5.0)) == 1.0)
        #expect(Dimension.fromLength(1.0).maybeResolve(Float(-5.0)) == 1.0)
        #expect(Dimension.fromLength(1.0).maybeResolve(Float(0.0)) == 1.0)
    }

    @Test func resolve_percent() {
        #expect(Dimension.fromPercent(1.0).maybeResolve(Float?.none) == nil)
        #expect(Dimension.fromPercent(1.0).maybeResolve(Float(5.0)) == 5.0)
        #expect(Dimension.fromPercent(1.0).maybeResolve(Float(-5.0)) == -5.0)
        #expect(Dimension.fromPercent(1.0).maybeResolve(Float(50.0)) == 50.0)
    }
}

@Suite("MaybeResolveSizeDimension")
struct MaybeResolveSizeDimensionTests {
    @Test func maybe_resolve_auto() {
        #expect(Size<Dimension>.auto().maybeResolve(Size<Float?>.NONE) == Size<Float?>.NONE)
        #expect(Size<Dimension>.auto().maybeResolve(Size<Float>(width: 5.0, height: 5.0)) == Size<Float?>.NONE)
        #expect(Size<Dimension>.auto().maybeResolve(Size<Float>(width: -5.0, height: -5.0)) == Size<Float?>.NONE)
        #expect(Size<Dimension>.auto().maybeResolve(Size<Float>(width: 0.0, height: 0.0)) == Size<Float?>.NONE)
    }

    @Test func maybe_resolve_length() {
        let expected = Size<Float?>(width: 5.0, height: 5.0)
        #expect(Size<Dimension>.fromLengths(width: 5.0, height: 5.0).maybeResolve(Size<Float?>.NONE) == expected)
        #expect(Size<Dimension>.fromLengths(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: 5.0, height: 5.0)) == expected)
        #expect(Size<Dimension>.fromLengths(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: -5.0, height: -5.0)) == expected)
        #expect(Size<Dimension>.fromLengths(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: 0.0, height: 0.0)) == expected)
    }

    @Test func maybe_resolve_percent() {
        #expect(Size<Dimension>.fromPercent(width: 5.0, height: 5.0).maybeResolve(Size<Float?>.NONE) == Size<Float?>.NONE)
        #expect(Size<Dimension>.fromPercent(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: 5.0, height: 5.0)) == Size<Float?>(width: 25.0, height: 25.0))
        #expect(Size<Dimension>.fromPercent(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: -5.0, height: -5.0)) == Size<Float?>(width: -25.0, height: -25.0))
        #expect(Size<Dimension>.fromPercent(width: 5.0, height: 5.0).maybeResolve(Size<Float>(width: 0.0, height: 0.0)) == Size<Float?>(width: 0.0, height: 0.0))
    }
}

@Suite("ResolveOrZeroDimensionToOptionF32")
struct ResolveOrZeroDimensionToOptionF32Tests {
    @Test func resolve_or_zero_auto() {
        #expect(Dimension.AUTO.resolveOrZero(Float?.none) == 0.0)
        #expect(Dimension.AUTO.resolveOrZero(Float(5.0)) == 0.0)
        #expect(Dimension.AUTO.resolveOrZero(Float(-5.0)) == 0.0)
        #expect(Dimension.AUTO.resolveOrZero(Float(0.0)) == 0.0)
    }

    @Test func resolve_or_zero_length() {
        #expect(Dimension.fromLength(5.0).resolveOrZero(Float?.none) == 5.0)
        #expect(Dimension.fromLength(5.0).resolveOrZero(Float(5.0)) == 5.0)
        #expect(Dimension.fromLength(5.0).resolveOrZero(Float(-5.0)) == 5.0)
        #expect(Dimension.fromLength(5.0).resolveOrZero(Float(0.0)) == 5.0)
    }

    @Test func resolve_or_zero_percent() {
        #expect(Dimension.fromPercent(5.0).resolveOrZero(Float?.none) == 0.0)
        #expect(Dimension.fromPercent(5.0).resolveOrZero(Float(5.0)) == 25.0)
        #expect(Dimension.fromPercent(5.0).resolveOrZero(Float(-5.0)) == -25.0)
        #expect(Dimension.fromPercent(5.0).resolveOrZero(Float(0.0)) == 0.0)
    }
}

@Suite("ResolveOrZeroRectDimensionToRect")
struct ResolveOrZeroRectDimensionToRectTests {
    @Test func resolve_or_zero_auto() {
        let zeroRect = Rect<Float>.ZERO
        #expect(Rect<Dimension>.auto().resolveOrZero(Size<Float?>.NONE) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Size<Float>(width: 5.0, height: 5.0)) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Size<Float>(width: -5.0, height: -5.0)) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Size<Float>(width: 0.0, height: 0.0)) == zeroRect)
    }

    @Test func resolve_or_zero_length() {
        let expected = Rect<Float>(left: 5.0, right: 5.0, top: 5.0, bottom: 5.0)
        let rect = Rect<Dimension>(left: .fromLength(5.0), right: .fromLength(5.0), top: .fromLength(5.0), bottom: .fromLength(5.0))
        #expect(rect.resolveOrZero(Size<Float?>.NONE) == expected)
        #expect(rect.resolveOrZero(Size<Float>(width: 5.0, height: 5.0)) == expected)
        #expect(rect.resolveOrZero(Size<Float>(width: -5.0, height: -5.0)) == expected)
        #expect(rect.resolveOrZero(Size<Float>(width: 0.0, height: 0.0)) == expected)
    }

    @Test func resolve_or_zero_percent() {
        let rect = Rect<Dimension>(left: .fromPercent(5.0), right: .fromPercent(5.0), top: .fromPercent(5.0), bottom: .fromPercent(5.0))
        #expect(rect.resolveOrZero(Size<Float?>.NONE) == Rect<Float>.ZERO)
        #expect(rect.resolveOrZero(Size<Float>(width: 5.0, height: 5.0)) == Rect<Float>(left: 25.0, right: 25.0, top: 25.0, bottom: 25.0))
        #expect(rect.resolveOrZero(Size<Float>(width: -5.0, height: -5.0)) == Rect<Float>(left: -25.0, right: -25.0, top: -25.0, bottom: -25.0))
        #expect(rect.resolveOrZero(Size<Float>(width: 0.0, height: 0.0)) == Rect<Float>.ZERO)
    }
}

@Suite("ResolveOrZeroRectDimensionToRectF32ViaOption")
struct ResolveOrZeroRectDimensionToRectF32ViaOptionTests {
    @Test func resolve_or_zero_auto() {
        let zeroRect = Rect<Float>.ZERO
        #expect(Rect<Dimension>.auto().resolveOrZero(Float?.none) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Float(5.0)) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Float(-5.0)) == zeroRect)
        #expect(Rect<Dimension>.auto().resolveOrZero(Float(0.0)) == zeroRect)
    }

    @Test func resolve_or_zero_length() {
        let expected = Rect<Float>(left: 5.0, right: 5.0, top: 5.0, bottom: 5.0)
        let rect = Rect<Dimension>(left: .fromLength(5.0), right: .fromLength(5.0), top: .fromLength(5.0), bottom: .fromLength(5.0))
        #expect(rect.resolveOrZero(Float?.none) == expected)
        #expect(rect.resolveOrZero(Float(5.0)) == expected)
        #expect(rect.resolveOrZero(Float(-5.0)) == expected)
        #expect(rect.resolveOrZero(Float(0.0)) == expected)
    }

    @Test func resolve_or_zero_percent() {
        let rect = Rect<Dimension>(left: .fromPercent(5.0), right: .fromPercent(5.0), top: .fromPercent(5.0), bottom: .fromPercent(5.0))
        #expect(rect.resolveOrZero(Float?.none) == Rect<Float>.ZERO)
        #expect(rect.resolveOrZero(Float(5.0)) == Rect<Float>(left: 25.0, right: 25.0, top: 25.0, bottom: 25.0))
        #expect(rect.resolveOrZero(Float(-5.0)) == Rect<Float>(left: -25.0, right: -25.0, top: -25.0, bottom: -25.0))
        #expect(rect.resolveOrZero(Float(0.0)) == Rect<Float>.ZERO)
    }
}
