// Tests ported from: crates/rune-motion/src/gesture.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func projection_matches_uikit() {
    // 1000 pt/s at the normal rate coasts 499 pt.
    #expect(abs(project(0.0, 1000.0, deceleration.normal) - 499.0) < 0.01)
}

@Test func rubber_band_is_sublinear_and_odd() {
    let d: Float = 800.0
    #expect(rubberBand(100.0, d) < 55.0 + 1e-3)
    #expect(rubberBand(100.0, d) > 0.0)
    #expect(rubberBand(-100.0, d) == -rubberBand(100.0, d))
    // Small overshoot ≈ 0.55 × overshoot.
    #expect(abs(rubberBand(1.0, d) - 0.55) < 1e-3)
    #expect(rubberBandClamp(50.0, 0.0, 100.0, d) == 50.0)
}

@Test func tracker_recovers_constant_velocity() {
    var tr = VelocityTracker<Float>.new()
    for i in 0..<30 {
        let t = Double(i) / 120.0
        tr.add(t, 300.0 * Float(t))
    }
    #expect(abs(tr.velocity() - 300.0) < 0.5)
    // A pause longer than 40 ms means stopped.
    tr.add(30.0 / 120.0 + 0.2, 75.0)
    #expect(tr.velocity() == 0.0)
}
