// Tests ported from: crates/rune-motion/src/easing.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func css_bezier_known_values() {
    // Chrome: getComputedTiming for `ease` at 50 % progress is ~0.8024.
    let y = Easing.ease.eval(0.5)
    #expect(abs(y - 0.802_4) < 1e-3, "\(y)")
    let yInOut = Easing.easeInOut.eval(0.5)
    #expect(abs(yInOut - 0.5) < 1e-5)
    #expect(Easing.easeOut.eval(0.0) == 0.0)
    #expect(Easing.easeOut.eval(1.0) == 1.0)
    // The overshoot curve rises above 1.
    #expect((0..<100).contains { i in Easing.overshoot.eval(Float(i) / 100.0) > 1.05 })
}

@Test func bezier_is_monotone_in_x_and_solves_exactly() {
    let b = CubicBezier.new(0.2, 0.8, 0.2, 1.0)
    let (ax, bx, cx) = CubicBezier.coefficients(b.x1, b.x2)
    for i in 1..<1000 {
        let x = Float(i) / 1000.0
        let t = b.solveT(x)
        let back = ((ax * t + bx) * t + cx) * t
        #expect(abs(back - x) < 1e-5)
    }
}

@Test func steps_follow_css() {
    #expect(steps(0.0, 4, .end) == 0.0)
    #expect(steps(0.3, 4, .end) == 0.25)
    #expect(steps(0.3, 4, .start) == 0.5)
    #expect(steps(0.5, 2, .none) == 1.0)
    #expect(steps(0.4, 2, .both) == Float(1.0) / Float(3.0))
    #expect(steps(1.0, 3, .both) == 1.0)
}

@Test func piecewise_linear() {
    let e = Easing.piecewise([[0.0, 0.0], [0.5, 0.8], [1.0, 1.0]])
    #expect(abs(e.eval(0.25) - 0.4) < 1e-6)
    #expect(abs(e.eval(0.75) - 0.9) < 1e-6)
    #expect(e.evalWithSlope(0.25).1 == 1.6)
}
