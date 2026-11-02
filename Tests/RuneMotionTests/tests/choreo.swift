// Tests ported from: crates/rune-motion/tests/choreo.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func stagger_delays_ripple_from_the_origin() {
    let dFirst: [Float] = (0..<5).map { i in stagger(i, 5, 0.1, .first) }
    #expect(dFirst == [0.0, 0.1, 0.2, 0.3, 0.4])
    let dLast: [Float] = (0..<5).map { i in stagger(i, 5, 0.1, .last) }
    #expect(dLast == [0.4, 0.3, 0.2, 0.1, 0.0])
    let dCenter: [Float] = (0..<5).map { i in stagger(i, 5, 0.1, .center) }
    #expect(abs(dCenter[0] - 0.2) < 1e-6 && dCenter[2] == 0.0 && abs(dCenter[4] - 0.2) < 1e-6)
    let eased = Stagger.new(0.1).ease(.easeIn)
    // Eased stagger keeps the ends and bunches the start.
    #expect(eased.delay(0, 5) == 0.0 && abs(eased.delay(4, 5) - 0.4) < 1e-5)
    #expect(eased.delay(1, 5) < 0.1)
}

@Test func sequence_starts_on_arrival_not_on_physical_rest() {
    let store = AnimationStore.new()
    let (a, b, c) = (NodeId(1), NodeId(2), NodeId(3))
    for n in [a, b, c] {
        store.set(n, prop.opacity, 0.0)
    }
    var ch = Choreography.new()
    let s1 = ch.step(Cue.now()) { s in
        s.animate(a, prop.opacity, 1.0, motion.settle)
    }
    let s2 = ch.step(Cue.arrived(s1).after(0.05)) { s in
        s.animate(b, prop.opacity, 1.0, motion.settle)
    }
    let s3 = ch.step(Cue.settled(s2).notBefore(1.5)) { s in
        s.animate(c, prop.opacity, 1.0, motion.snap)
    }
    var t = 0.0
    while t < 4.0 {
        store.setTime(t)
        ch.tick(store)
        store.tick()
        t += 1.0 / 120.0
    }
    // Step 2 is scheduled exactly at s1's logical arrival (its 0.3 s duration) + 0.05.
    #expect(abs(ch.startTime(s2)! - 0.35) < 1e-6, "\(String(describing: ch.startTime(s2)))")
    // Step 3 waits for physical rest *and* the guard.
    #expect(ch.startTime(s3)! >= 1.5)
    #expect(ch.isDone(store))
    for n in [a, b, c] {
        #expect(store.get(n, prop.opacity) == 1.0)
    }
}

@Test func choreography_stagger_cascades_items() {
    let store = AnimationStore.new()
    let ids: [NodeId] = (0..<UInt64(4)).map { NodeId($0) }
    for n in ids {
        store.set(n, prop.offset, Vec2.new(0.0, 12.0))
    }
    var ch = Choreography.new()
    let steps = ch.stagger(Cue.now(), Stagger.new(0.04), ids) { s, n in
        s.animate(n, prop.offset, .zero, motion.settle)
    }
    store.setTime(0.0)
    ch.tick(store)
    for (i, s) in steps.enumerated() {
        #expect(abs(ch.startTime(s)! - 0.04 * Double(i)) < 1e-6)
    }
    store.tickAt(0.05)
    let y: [Float] = ids.map { n in store.get(n, prop.offset)!.y }
    #expect(y[0] < y[1] && y[1] < y[2] && y[2] == 12.0 && y[3] == 12.0, "\(y)")
}

@Test func phase_animator_cycles_and_holds_under_reduced_motion() {
    let pulse = { (store: AnimationStore, reduced: Bool) -> [Int] in
        store.setReducedMotion(reduced)
        let n = NodeId(1)
        var ph = PhaseAnimator.new()
            .phase { p in
                p.animate(n, prop.scale, 1.0, motion.settle)
            }
            .phase { p in
                p.animate(n, prop.scale, 1.04, motion.settle)
            }
            .advanceOn(.arrived)
        var phases: [Int] = []
        var t = 0.0
        while t < 2.0 {
            store.setTime(t)
            ph.tick(store)
            store.tick()
            phases.append(ph.current())
            t += 1.0 / 120.0
        }
        return phases
    }
    let phases = pulse(AnimationStore.new(), false)
    var switches = 0
    for i in 0..<(phases.count - 1) where phases[i] != phases[i + 1] {
        switches += 1
    }
    // 0.3 s per phase for 2 s ≈ 6 switches.
    #expect((5...7).contains(switches), "\(switches)")
    let held = pulse(AnimationStore.new(), true)
    #expect(held.allSatisfy { $0 == 0 })
}

@Test func a_cue_on_a_frozen_step_waits_and_scaled_steps_keep_one_clock() {
    // A frozen first step: the second waits for its arrival instead of never running.
    var store = AnimationStore.new()
    let (a, b) = (NodeId(1), NodeId(2))
    for n in [a, b] {
        store.set(n, prop.opacity, 0.0)
    }
    store.setNodeTimeScale(a, 0.0)
    var ch = Choreography.new()
    let s1 = ch.step(Cue.now()) { s in
        s.animate(a, prop.opacity, 1.0, motion.settle)
    }
    let s2 = ch.step(Cue.arrived(s1)) { s in
        s.animate(b, prop.opacity, 1.0, motion.settle)
    }
    for i in 0...480 {
        store.setTime(Double(i) / 120.0)
        if i == 120 {
            store.setNodeTimeScale(a, 1.0)
        }
        ch.tick(store)
        store.tick()
        if i == 119 {
            #expect(ch.startTime(s2) == nil, "waits while its cue is frozen")
        }
    }
    // Resumed at 1 s, `a` arrives 0.3 s later.
    #expect(abs(ch.startTime(s2)! - 1.3) < 1e-3, "\(String(describing: ch.startTime(s2)))")
    #expect(store.get(b, prop.opacity) == 1.0)

    // Both at half speed: `b` starts when `a` arrives, 0.6 s in, and runs on the same curve.
    store = AnimationStore.new()
    for n in [a, b] {
        store.set(n, prop.opacity, 0.0)
        store.setNodeTimeScale(n, 0.5)
    }
    ch = Choreography.new()
    let s1Half = ch.step(Cue.now()) { s in
        s.animate(a, prop.opacity, 1.0, motion.settle)
    }
    ch.step(Cue.arrived(s1Half)) { s in
        s.animate(b, prop.opacity, 1.0, motion.settle)
    }
    var aAt: Float = 0.0
    var bAt: Float = 0.0
    for i in 0...120 {
        store.setTime(Double(i) / 120.0)
        ch.tick(store)
        store.tick()
        if i == 24 {
            aAt = store.get(a, prop.opacity)!
        }
        if i == 96 {
            bAt = store.get(b, prop.opacity)!
        }
    }
    #expect(aAt > 0.05 && abs(aAt - bAt) < 1e-3, "b at 0.8 s \(bAt) vs a at 0.2 s \(aAt)")
}

@Test func a_phase_started_frozen_advances_after_resuming() {
    let store = AnimationStore.new()
    let n = NodeId(1)
    store.setNodeTimeScale(n, 0.0)
    var ph = PhaseAnimator.new()
        .phase { p in
            p.animate(n, prop.scale, 1.0, motion.settle)
        }
        .phase { p in
            p.animate(n, prop.scale, 1.04, motion.settle)
        }
    var phases: [Int] = []
    for i in 0...480 {
        store.setTime(Double(i) / 120.0)
        if i == 120 {
            store.setNodeTimeScale(n, 1.0)
        }
        ph.tick(store)
        store.tick()
        phases.append(ph.current())
    }
    let switches = { (slice: ArraySlice<Int>) -> Int in
        let arr = Array(slice)
        guard arr.count >= 2 else { return 0 }
        var count = 0
        for i in 0..<(arr.count - 1) where arr[i] != arr[i + 1] {
            count += 1
        }
        return count
    }
    #expect(switches(phases[1..<120]) == 0, "frozen in its first animated phase")
    // 0.3 s per phase for 3 s ≈ 10 switches.
    #expect(switches(phases[120...]) >= 8, "\(switches(phases[120...]))")
}
