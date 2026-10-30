// Tests ported from: src/util/math.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("LHS Option<f32> RHS Option<f32>")
struct LhsOptionF32RhsOptionF32Tests {
    @Test func test_maybe_min() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMin(five) == 3.0)
        #expect(five.maybeMin(three) == 3.0)
        #expect(three.maybeMin(none) == 3.0)
        #expect(none.maybeMin(three) == nil)
        #expect(none.maybeMin(none) == nil)
    }

    @Test func test_maybe_max() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMax(five) == 5.0)
        #expect(five.maybeMax(three) == 5.0)
        #expect(three.maybeMax(none) == 3.0)
        #expect(none.maybeMax(three) == nil)
        #expect(none.maybeMax(none) == nil)
    }

    @Test func test_maybe_add() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeAdd(five) == 8.0)
        #expect(five.maybeAdd(three) == 8.0)
        #expect(three.maybeAdd(none) == 3.0)
        #expect(none.maybeAdd(three) == nil)
        #expect(none.maybeAdd(none) == nil)
    }

    @Test func test_maybe_sub() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeSub(five) == -2.0)
        #expect(five.maybeSub(three) == 2.0)
        #expect(three.maybeSub(none) == 3.0)
        #expect(none.maybeSub(three) == nil)
        #expect(none.maybeSub(none) == nil)
    }
}

@Suite("LHS Option<f32> RHS f32")
struct LhsOptionF32RhsF32Tests {
    @Test func test_maybe_min() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMin(5.0) == 3.0)
        #expect(five.maybeMin(3.0) == 3.0)
        #expect(none.maybeMin(3.0) == nil)
    }

    @Test func test_maybe_max() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMax(5.0) == 5.0)
        #expect(five.maybeMax(3.0) == 5.0)
        #expect(none.maybeMax(3.0) == nil)
    }

    @Test func test_maybe_add() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeAdd(5.0) == 8.0)
        #expect(five.maybeAdd(3.0) == 8.0)
        #expect(none.maybeAdd(3.0) == nil)
    }

    @Test func test_maybe_sub() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeSub(5.0) == -2.0)
        #expect(five.maybeSub(3.0) == 2.0)
        #expect(none.maybeSub(3.0) == nil)
    }
}

@Suite("LHS f32 RHS Option<f32>")
struct LhsF32RhsOptionF32Tests {
    @Test func test_maybe_min() {
        let three: Float = 3.0
        let five: Float = 5.0

        #expect(three.maybeMin(Float?.some(5.0)) == 3.0)
        #expect(five.maybeMin(Float?.some(3.0)) == 3.0)
        #expect(three.maybeMin(Float?.none) == 3.0)
    }

    @Test func test_maybe_max() {
        let three: Float = 3.0
        let five: Float = 5.0

        #expect(three.maybeMax(Float?.some(5.0)) == 5.0)
        #expect(five.maybeMax(Float?.some(3.0)) == 5.0)
        #expect(three.maybeMax(Float?.none) == 3.0)
    }

    @Test func test_maybe_add() {
        let three: Float = 3.0
        let five: Float = 5.0

        #expect(three.maybeAdd(Float?.some(5.0)) == 8.0)
        #expect(five.maybeAdd(Float?.some(3.0)) == 8.0)
        #expect(three.maybeAdd(Float?.none) == 3.0)
    }

    @Test func test_maybe_sub() {
        let three: Float = 3.0
        let five: Float = 5.0

        #expect(three.maybeSub(Float?.some(5.0)) == -2.0)
        #expect(five.maybeSub(Float?.some(3.0)) == 2.0)
        #expect(three.maybeSub(Float?.none) == 3.0)
    }
}
