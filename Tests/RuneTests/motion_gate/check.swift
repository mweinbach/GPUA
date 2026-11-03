// Tests ported from: crates/rune/src/motion_gate/check.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/motion_gate/check.rs` delegates its `#[cfg(test)]` module via
// `#[path = "check_tests.rs"] mod tests;`, which is ported in full in `Tests/RuneTests/motion_gate/check_tests.swift`.
// Additional rule-table and ticker-shape invariants on `check.swift` are verified here.

import Testing
@testable import Rune

@Suite("MotionGateCheckRuleTests")
struct MotionGateCheckRuleTests {
    @Test("All motion gate rules have unique kinds and finite thresholds")
    func ruleTableInvariants() {
        var seen = Set<String>()
        for r in MOTION_GATE_RULES {
            #expect(!r.kind.isEmpty)
            #expect(!r.means.isEmpty)
            #expect(r.threshold.isFinite && r.threshold >= 0.0)
            #expect(seen.insert(r.kind).inserted)
            #expect(motionGateRule(r.kind) == r.threshold)
        }
        #expect(motionGateRule("nonexistent-rule-kind") == .infinity)
    }

    @Test("Ticker digit shape helper distinguishes numeric ticks from word swaps")
    func tickerShapeClassification() {
        #expect(motionGateTicks("9s", "10s"))
        #expect(motionGateTicks("Frame 1 / 120", "Frame 42 / 120"))
        #expect(!motionGateTicks("Read backoff.ts", "Grep retryBudget"))
    }
}
