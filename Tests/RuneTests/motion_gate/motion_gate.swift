// Tests ported from: crates/rune/src/motion_gate/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune/src/motion_gate/mod.rs` wires `#[cfg(test)] mod tests;` and
// `#[cfg(test)] mod loop_tests;`, which are ported in `motion_gate_tests.swift` and `loop_tests.swift`.
// Additional `MotionGateRun` / `motionGate` namespace smoke tests live here.

import Testing
@testable import Rune

@Suite("MotionGateModuleTests")
struct MotionGateModuleTests {
    @Test("MotionGateRun quiet marker and short path helper behave as specified")
    func runQuietAndShortPath() {
        let rt = Runtime.new(0, { _, _ in col().wFull().hFull().child(el().key("item").size(40, 20).bg(Color.WHITE)) }, (200, 100), Env.new(true, 1.0))
        let run = motionGate.Run.new(rt, 60.0)
        run.stepN(3)
        #expect(run.rec.frames == 3)
        run.quiet()
        #expect(run.rec.quietFrom == 3)
        #expect(motionGate.short("root/0/1/item") == "1/item")
    }

    @Test("MotionGate dump and contact sheet render valid output")
    func dumpAndContactSheet() {
        let rt = Runtime.new(0, { _, _ in col().wFull().hFull().child(el().key("card").size(80, 40).bg(oklch(0.6, 0.1, 220))) }, (240, 120), Env.new(true, 1.0))
        let run = motionGate.Run.new(rt, 60.0)
        run.stepN(4)
        let dumpText = motionGate.dump(run.rec, "card", 0, 4)
        #expect(dumpText.contains("card"))
        let sheet = motionGate.sheet(run.rec, 2, "card")
        #expect(sheet.width > 0 && sheet.height > 0)
        #expect(sheet.rgb.count == Int(sheet.width) * Int(sheet.height) * 3)
    }
}
