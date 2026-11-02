// Tests ported from: crates/rune-motion/src/math.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import RuneMotion

@Test func exp_matches_std() {
    var x: Float = -87.0
    while x < 88.0 {
        let ours = Double(math.exp(x))
        let theirs = Foundation.exp(Double(x))
        #expect(abs((ours - theirs) / theirs) < 4e-7, "exp(\(x)) = \(ours), std \(theirs)")
        x += 0.0137
    }
    #expect(math.exp(0.0) == 1.0)
    #expect(math.exp(-100.0) == 0.0)
    #expect(math.exp(100.0) == .infinity)
}

@Test func sin_cos_match_std() {
    var x: Float = -2000.0
    while x < 2000.0 {
        let (s, c) = math.sinCos(x)
        let xd = Double(x)
        #expect(abs(Double(s) - Foundation.sin(xd)) < 4e-7, "sin(\(x)) \(s) vs \(Foundation.sin(xd))")
        #expect(abs(Double(c) - Foundation.cos(xd)) < 4e-7, "cos(\(x)) \(c) vs \(Foundation.cos(xd))")
        x += 0.0731
    }
}
