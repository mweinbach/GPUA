// Tests ported from: crates/rune-motion/src/clock.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func scale_reanchors_without_a_jump() {
    var c = Clock.display()
    #expect(c.frame(100.0) == 0.0)
    #expect(abs(c.frame(101.0) - 1.0) < 1e-12)
    c.setScale(0.5, 101.0)
    #expect(abs(c.frame(101.0) - 1.0) < 1e-12)
    #expect(abs(c.frame(103.0) - 2.0) < 1e-12)
    c.pause(103.0)
    #expect(abs(c.frame(110.0) - 2.0) < 1e-12)
    c.resume(110.0)
    #expect(abs(c.frame(112.0) - 3.0) < 1e-12)
}

@Test func manual_steps_are_exact() {
    var c = Clock.manual(120.0)
    for _ in 0..<120 {
        c.step()
    }
    #expect(abs(c.now() - 1.0) < 1e-9)
}
