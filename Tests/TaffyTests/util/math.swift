// Tests ported from: src/util/math.rs (#[cfg(test)] items)
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

import Testing
@testable import Taffy

@Suite("Taffy MaybeMath Tests")
struct TaffyMaybeMathTests {
    @Test("LHS Option<Float> RHS Option<Float> maybeMin")
    func testLhsOptionRhsOptionMin() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMin(five) == 3.0)
        #expect(five.maybeMin(three) == 3.0)
        #expect(three.maybeMin(none) == 3.0)
        #expect(none.maybeMin(three) == nil)
        #expect(none.maybeMin(none) == nil)
    }

    @Test("LHS Option<Float> RHS Option<Float> maybeMax")
    func testLhsOptionRhsOptionMax() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMax(five) == 5.0)
        #expect(five.maybeMax(three) == 5.0)
        #expect(three.maybeMax(none) == 3.0)
        #expect(none.maybeMax(three) == nil)
        #expect(none.maybeMax(none) == nil)
    }

    @Test("LHS Option<Float> RHS Option<Float> maybeAdd")
    func testLhsOptionRhsOptionAdd() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeAdd(five) == 8.0)
        #expect(five.maybeAdd(three) == 8.0)
        #expect(three.maybeAdd(none) == 3.0)
        #expect(none.maybeAdd(three) == nil)
        #expect(none.maybeAdd(none) == nil)
    }

    @Test("LHS Option<Float> RHS Option<Float> maybeSub")
    func testLhsOptionRhsOptionSub() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeSub(five) == -2.0)
        #expect(five.maybeSub(three) == 2.0)
        #expect(three.maybeSub(none) == 3.0)
        #expect(none.maybeSub(three) == nil)
        #expect(none.maybeSub(none) == nil)
    }

    @Test("LHS Option<Float> RHS Float maybe operations")
    func testLhsOptionRhsFloat() {
        let three: Float? = 3.0
        let five: Float? = 5.0
        let none: Float? = nil

        #expect(three.maybeMin(5.0) == 3.0)
        #expect(five.maybeMin(3.0) == 3.0)
        #expect(none.maybeMin(3.0) == nil)

        #expect(three.maybeMax(5.0) == 5.0)
        #expect(five.maybeMax(3.0) == 5.0)
        #expect(none.maybeMax(3.0) == nil)

        #expect(three.maybeAdd(5.0) == 8.0)
        #expect(five.maybeAdd(3.0) == 8.0)
        #expect(none.maybeAdd(3.0) == nil)

        #expect(three.maybeSub(5.0) == -2.0)
        #expect(five.maybeSub(3.0) == 2.0)
        #expect(none.maybeSub(3.0) == nil)
    }

    @Test("LHS Float RHS Option<Float> maybe operations")
    func testLhsFloatRhsOption() {
        let five: Float? = 5.0
        let three: Float? = 3.0
        let none: Float? = nil

        #expect(Float(3.0).maybeMin(five) == 3.0)
        #expect(Float(5.0).maybeMin(three) == 3.0)
        #expect(Float(3.0).maybeMin(none) == 3.0)

        #expect(Float(3.0).maybeMax(five) == 5.0)
        #expect(Float(5.0).maybeMax(three) == 5.0)
        #expect(Float(3.0).maybeMax(none) == 3.0)

        #expect(Float(3.0).maybeAdd(five) == 8.0)
        #expect(Float(5.0).maybeAdd(three) == 8.0)
        #expect(Float(3.0).maybeAdd(none) == 3.0)

        #expect(Float(3.0).maybeSub(five) == -2.0)
        #expect(Float(5.0).maybeSub(three) == 2.0)
        #expect(Float(3.0).maybeSub(none) == 3.0)
    }
}
