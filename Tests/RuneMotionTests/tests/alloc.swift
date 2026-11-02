// Tests ported from: crates/rune-motion/tests/alloc.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

// PORT NOTE: Swift does not expose a global allocator override like Rust's `#[global_allocator]`.
// These tests run the exact upstream steady-state workloads and verify that every internal
// storage buffer in `AnimationStore` and `Scene` keeps a constant `.capacity` after warmup.

private let allocXProp = Prop<Float>.custom(64, .spatial)

private func storeCapacities(_ s: AnimationStore) -> [Int] {
    [
        s.lTarget.capacity,
        s.lValue.capacity,
        s.lVel.capacity,
        s.lLayer.capacity,
        s.lMore.capacity,
        s.lPending.capacity,
        s.lCurve.capacity,
        s.tLane0.capacity,
        s.tN.capacity,
        s.tSettleAt.capacity,
        s.tNextDue.capacity,
        s.tSlot.capacity,
        s.tMeta.capacity,
        s.tClock.capacity,
        s.tHeld.capacity,
        s.activeIndices.capacity,
        s.touchedList.capacity,
        s.setTouchedList.capacity,
        s.extra.capacity,
        s.pending.capacity,
        s._events.capacity,
    ]
}

private func sceneCapacities(_ s: Scene) -> [Int] {
    [
        s.nodes.capacity,
        s.rests.capacity,
        s.free.capacity,
        s.order.capacity,
        s.out.capacity,
        s.exited.capacity,
        s.toRemove.capacity,
        s.travelling.capacity,
    ] + storeCapacities(s._store)
}

@Test func store_tick_allocates_nothing_in_steady_state() {
    let n: UInt64 = 5000
    let store = AnimationStore.withCapacity(2 * Int(n), 3)
    for i in 0..<n {
        let id = NodeId(i)
        store.set(id, allocXProp, 0.0)
        store.set(id, prop.frame, Rect.new(0.0, 0.0, 10.0, 10.0))
        // A spread of bounces and durations so tracks settle at different times.
        let s = Spring.new(0.3 + Float(i % 7) * 0.2, Float(i % 5) * 0.1)
        store.animate(id, allocXProp, 100.0 + Float(i), s)
        store.animate(id, prop.frame, Rect.new(5.0, 3.0, 20.0, 10.0), s.delay(Float(i % 3) * 0.05))
        if i % 4 == 0 {
            store.animate(id, allocXProp, -50.0, Curve.tween(0.4, .easeInOut))
        }
    }
    // Warm up: the first frames grow the event and touched buffers to the working-set size.
    var t = 0.0
    for _ in 0..<4 {
        t += 1.0 / 120.0
        store.tickAt(t)
    }
    let before = storeCapacities(store)
    var ticks = 0
    while store.activeLen() > 0 && ticks < 2000 {
        t += 1.0 / 120.0
        store.tickAt(t)
        ticks += 1
    }
    let after = storeCapacities(store)
    #expect(ticks > 100, "the animations should run for a while (\(ticks))")
    #expect(after == before, "buffer capacities grew over \(ticks) ticks: \(before) -> \(after)")
}

@Test func scene_frame_allocates_nothing_while_animating() {
    let scene = Scene.new()
    for i in 0..<UInt64(500) {
        scene.insert(NodeId(i), NodeSpec.new(Rect.new(0.0, Float(i) * 10.0, 100.0, 10.0)), .initial)
    }
    scene.frameAt(0.0)
    for i in 0..<UInt64(500) {
        scene.setFrame(NodeId(i), Rect.new(10.0, Float(i) * 12.0, 100.0, 12.0), motion.reflow)
        scene.animate(NodeId(i), prop.opacity, 0.5, motion.settle)
    }
    var t = 0.0
    for _ in 0..<3 {
        t += 1.0 / 120.0
        scene.frameAt(t)
    }
    let before = sceneCapacities(scene)
    for _ in 0..<40 {
        t += 1.0 / 120.0
        let out = scene.frameAt(t)
        #expect(out.animating && out.changed.count == 500)
    }
    #expect(sceneCapacities(scene) == before)
}
