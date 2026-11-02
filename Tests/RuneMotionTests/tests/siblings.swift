// Tests ported from: crates/rune-motion/tests/siblings.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func sibling_order_matches_reference_after_removal_and_slot_reuse() {
    for nested in [false, true] {
        let scene = Scene.new()
        let parent = NodeId(1000)
        if nested {
            scene.insert(parent, NodeSpec.new(.zero), .initial)
        }
        var expected: [NodeId] = []
        var seed: UInt32 = 1
        for step in 0..<UInt64(300) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            if !expected.isEmpty && seed % 3 != 0 {
                let i = Int(seed) % expected.count
                scene.unmount(expected.remove(at: i))
            } else {
                let id = NodeId(step)
                let spec = NodeSpec.new(Rect.new(0.0, 0.0, 10.0, 10.0))
                scene.insert(id, nested ? spec.parent(parent) : spec, .initial)
                expected.append(id)
            }
            // Force every surviving node into the changed list to observe traversal order.
            for id in expected {
                scene.set(id, prop.opacity, step % 2 == 0 ? 0.8 : 1.0)
            }
            let out = scene.frameAt(Double(step) / 120.0)
            let actual = out.changed.filter { $0.node != parent }.map { $0.node }
            #expect(actual == expected, "step \(step), nested \(nested)")
        }
    }
}
