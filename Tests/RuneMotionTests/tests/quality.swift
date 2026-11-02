// Tests ported from: crates/rune-motion/tests/quality.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func jittered_sampling_and_retarget_audit_stay_bounded() {
    let scene = Scene.new()
    scene.storeMut().auditRetargets(true)
    scene.insert(NodeId(1), NodeSpec.new(Rect.new(0.0, 0.0, 200.0, 200.0)), .initial)
    scene.insert(NodeId(2), NodeSpec.new(Rect.new(10.0, 10.0, 50.0, 50.0)).parent(NodeId(1)), .initial)
    scene.frameAt(0.0)
    var now = 0.0
    var seed: UInt32 = 7
    for i in 0..<300 {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        now += 1.0 / 120.0 + Double(seed % 12000) / 1e6
        scene.setTime(now)
        if i % 7 == 0 {
            let x = Float(seed % 300)
            scene.setFrame(NodeId(1), Rect.new(x, x / 2.0, 200.0, 200.0), Spring.new(0.4, 0.0))
            scene.setFrame(NodeId(2), Rect.new(x / 4.0, x / 3.0, 50.0, 50.0), Spring.new(0.3, 0.0))
        }
        scene.frame()
        let (samples, error) = scene.samplingError()
        #expect(samples == 8)
        #expect(error < 0.016, "analytic edge error \(error)px at \(now)")
    }
    let audit = scene.storeMut().takeRetargetAudit()
    #expect(audit.lanes > 100)
    #expect(audit.maxVelocityError < 0.001, "\(audit)")
}
