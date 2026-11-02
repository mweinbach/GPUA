// Tests ported from: crates/rune-motion/tests/store.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

private let storeXProp = Prop<Float>.custom(64, .spatial)
private let storeNode = NodeId(7)

private struct Rng {
    var s: UInt64

    init(_ s: UInt64) {
        self.s = s
    }

    mutating func next() -> Float {
        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(s >> 40) / Float(UInt64(1) << 24)
    }

    mutating func range(_ a: Float, _ b: Float) -> Float {
        a + (b - a) * next()
    }
}

private func state(_ s: AnimationStore) -> (Float, Float) {
    (s.sample(storeNode, storeXProp)!, s.sampleVelocity(storeNode, storeXProp)!)
}

@Test func randomized_retargets_are_c1_continuous() {
    for seed in UInt64(1)...8 {
        var rng = Rng(seed)
        let store = AnimationStore.new()
        store.set(storeNode, storeXProp, 0.0)
        var t = 0.0
        for step in 0..<1500 {
            t += Double(rng.range(0.001, 0.06))
            store.setTime(t)
            if step % 3 == 0 {
                store.tick()
                // The tick's presented value is the exact sample.
                let (x, v) = state(store)
                #expect(abs(store.get(storeNode, storeXProp)! - x) < 1e-3)
                #expect(abs(store.velocity(storeNode, storeXProp)! - v) < 1e-2)
            }
            let (x0, v0) = state(store)
            let target = rng.range(-500.0, 500.0)
            let kind = rng.next()
            let anim: Anim
            if kind < 0.6 {
                anim = Spring.new(rng.range(0.1, 0.8), rng.range(-0.6, 0.7)).intoAnim()
            } else if kind < 0.85 {
                anim = Curve.tween(rng.range(0.05, 0.5), .easeInOut).intoAnim()
            } else if kind < 0.93 {
                anim = Curve.decay(.iosFast).intoAnim()
            } else {
                anim = Spring.new(rng.range(0.1, 0.8), 0.0).additive()
            }
            store.animate(storeNode, storeXProp, target, anim)
            let (x1, v1) = state(store)
            let scale: Float = 1.0 + max(abs(x0), abs(v0)) * 1e-5
            #expect(abs(x1 - x0) < 2e-3 * scale, "seed \(seed) step \(step): position jumped \(x0) → \(x1)")
            #expect(
                abs(v1 - v0) < 2e-2 * max(scale, 1.0 + abs(v0) * 1e-4),
                "seed \(seed) step \(step) (\(anim)): velocity jumped \(v0) → \(v1)"
            )
        }
        // Everything settles exactly on the last target, and the track goes dormant.
        store.tickAt(t + 200.0)
        store.tickAt(t + 200.1)
        #expect(store.activeLen() == 0)
        #expect(store.velocity(storeNode, storeXProp) == 0.0)
    }
}

@Test func additive_springs_equal_merged_springs() {
    // Springs are linear ODEs: stacking additive layers on one spring is the same motion as
    // sample-and-restart (research 06 §2.6). Prove it numerically.
    let s = motion.reflow
    let merged = AnimationStore.new()
    let added = AnimationStore.new()
    for st in [merged, added] {
        st.set(storeNode, storeXProp, 0.0)
    }
    var rng = Rng(42)
    var t = 0.0
    for _ in 0..<6 {
        let target = rng.range(-300.0, 300.0)
        merged.setTime(t)
        added.setTime(t)
        merged.animate(storeNode, storeXProp, target, s.merge())
        added.animate(storeNode, storeXProp, target, s.additive())
        for k in 0..<40 {
            let tt = t + Double(k) * 0.002
            merged.setTime(tt)
            added.setTime(tt)
            let (a, b) = (state(merged), state(added))
            #expect(abs(a.0 - b.0) < 2e-3, "\(a) vs \(b)")
            #expect(abs(a.1 - b.1) < 5e-2, "\(a) vs \(b)")
        }
        t += Double(rng.range(0.03, 0.2))
    }
}

@Test func unchanged_target_keeps_the_trajectory() {
    let a = AnimationStore.new()
    let b = AnimationStore.new()
    for s in [a, b] {
        s.set(storeNode, storeXProp, 0.0)
        s.animate(storeNode, storeXProp, 100.0, motion.settle)
    }
    b.setTime(0.1)
    b.animate(storeNode, storeXProp, 100.0, motion.drift) // same target: no restart, curve ignored
    for k in 1..<60 {
        let t = Double(k) / 120.0
        a.setTime(t)
        b.setTime(t)
        let sa = state(a)
        let sb = state(b)
        #expect(sa.0 == sb.0 && sa.1 == sb.1)
    }
}

@Test func delays_hold_then_start_exactly_and_newer_animations_cancel_them() {
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 100.0, motion.settle.delay(0.1))
    s.tickAt(0.05)
    #expect(s.get(storeNode, storeXProp) == 0.0)
    s.tickAt(0.1 + 0.15)
    let expectedVal = motion.settle.sample(0.0, 0.0, 100.0, 0.15).0
    #expect(abs(s.get(storeNode, storeXProp)! - expectedVal) < 1e-3)
    // A delayed retarget, then an immediate one: the delayed one never happens.
    s.animate(storeNode, storeXProp, -100.0, motion.settle.delay(0.2))
    s.setTime(0.3)
    s.animate(storeNode, storeXProp, 50.0, motion.settle)
    s.tickAt(10.0)
    #expect(s.get(storeNode, storeXProp) == 50.0)
    #expect(s.target(storeNode, storeXProp) == 50.0)
}

@Test func set_is_immediate_and_first_animate_doesnt_animate() {
    let s = AnimationStore.new()
    s.animate(storeNode, storeXProp, 40.0, motion.settle) // first sight: set, no motion
    s.tickAt(0.0)
    #expect(s.get(storeNode, storeXProp) == 40.0)
    #expect(!s.isAnimating(storeNode, storeXProp))
    s.animate(storeNode, storeXProp, 80.0, motion.settle)
    s.tickAt(0.05)
    #expect(s.isAnimating(storeNode, storeXProp))
    s.set(storeNode, storeXProp, 10.0) // the user's hand: 1:1, cancels
    s.tickAt(0.06)
    #expect(s.get(storeNode, storeXProp) == 10.0)
    #expect(!s.isAnimating(storeNode, storeXProp))
}

@Test func settle_and_completion_events() {
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 1.0, motion.snap.completion(11))
    s.setTime(0.05)
    s.animate(storeNode, storeXProp, 2.0, motion.snap.completion(12)) // replaces 11
    var events: [MotionEvent] = []
    for k in 0..<400 {
        s.tickAt(0.05 + Double(k) / 120.0)
        events.append(contentsOf: s.events())
    }
    let completed: [(UInt64, Bool)] = events.compactMap { e in
        if case .completed(let token, _, _, let finished) = e {
            return (token, finished)
        }
        return nil
    }
    #expect(completed.count == 2)
    #expect(completed[0].0 == 11 && completed[0].1 == false)
    #expect(completed[1].0 == 12 && completed[1].1 == true)
    let settles = events.filter {
        if case .settled = $0 { return true }
        return false
    }.count
    #expect(settles == 1)
    #expect(s.get(storeNode, storeXProp) == 2.0)
    // Settle snaps below the 1/64 px quantum: the last moving frame was already that close.
    #expect(s.activeLen() == 0)
}

@Test func removing_an_animating_track_completes_it_unfinished() {
    let completions = { (s: AnimationStore) -> [(UInt64, Bool)] in
        s.events().compactMap { e in
            if case .completed(let token, _, _, let finished) = e {
                return (token, finished)
            }
            return nil
        }
    }
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 1.0, motion.snap.completion(21))
    s.tickAt(0.02)
    #expect(s.isAnimating(storeNode, storeXProp))
    s.removeNode(storeNode)
    s.tickAt(0.03)
    let c1 = completions(s)
    #expect(c1.count == 1 && c1[0].0 == 21 && c1[0].1 == false, "the node unmounted mid-animation")

    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 1.0, motion.snap.completion(22))
    s.tickAt(0.04)
    s.remove(storeNode, storeXProp)
    s.tickAt(0.05)
    let c2 = completions(s)
    #expect(c2.count == 1 && c2[0].0 == 22 && c2[0].1 == false, "the property's track went")

    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 1.0, motion.snap.completion(23))
    var done: [(UInt64, Bool)] = []
    for k in 0..<400 {
        s.tickAt(0.06 + Double(k) / 120.0)
        done.append(contentsOf: completions(s))
    }
    s.removeNode(storeNode)
    s.tickAt(10.0)
    done.append(contentsOf: completions(s))
    #expect(done.count == 1 && done[0].0 == 23 && done[0].1 == true, "a finished animation completes once")
}

@Test func fling_into_a_bound_hands_off_velocity_smoothly() {
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.release(
        storeNode,
        storeXProp,
        3000.0,
        .decayClamped(decay: .iosNormal, min: 0.0, max: 500.0, spring: motion.glide)
    )
    // Find the handoff by walking finely; velocity must stay continuous across it.
    var prev = state(s)
    var maxDv: Float = 0.0
    let dt = 1.0 / 2000.0
    for k in 1..<8000 {
        s.tickAt(Double(k) * dt)
        let cur = (s.get(storeNode, storeXProp)!, s.velocity(storeNode, storeXProp)!)
        maxDv = max(maxDv, abs(cur.1 - prev.1))
        prev = cur
    }
    // Decay deceleration is k·v ≈ 6000/s² → 3 per step; the spring's is larger but bounded.
    #expect(maxDv < 60.0, "velocity jumped by \(maxDv)")
    #expect(s.get(storeNode, storeXProp) == 500.0)
}

@Test func rubber_band_then_spring_back() {
    let s = AnimationStore.new()
    let over = rubberBandClamp(-120.0, 0.0, 500.0, 800.0)
    #expect(over < 0.0 && over > -120.0 * 0.55)
    s.set(storeNode, storeXProp, over)
    s.release(
        storeNode,
        storeXProp,
        0.0,
        .decayClamped(decay: .iosNormal, min: 0.0, max: 500.0, spring: motion.glide)
    )
    s.tickAt(5.0)
    s.tickAt(5.1)
    #expect(s.get(storeNode, storeXProp) == 0.0)
}

@Test func keyframes_hit_values_and_keep_velocity_through_cubics() {
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    let kf = Keyframes<Float>.new()
        .linear(10.0, 0.1)
        .cubic(30.0, 0.2)
        .cubic(20.0, 0.2)
        .cubic(40.0, 0.2)
        .spring(0.0, motion.settle)
    s.playKeyframes(storeNode, storeXProp, kf)
    let at = { (t: Double) -> (Float, Float) in
        s.tickAt(t)
        return (s.get(storeNode, storeXProp)!, s.velocity(storeNode, storeXProp)!)
    }
    #expect(abs(at(0.05).0 - 5.0) < 1e-3, "linear halfway")
    #expect(abs(at(0.1).0 - 10.0) < 1e-3)
    #expect(abs(at(0.3).0 - 30.0) < 1e-3)
    // C¹ at the cubic joins: velocity just before and after 0.5 s agree.
    let before = at(0.5 - 1e-4).1
    let after = at(0.5 + 1e-4).1
    #expect(abs(before - after) < 0.5, "\(before) vs \(after)")
    #expect(abs(at(0.7).0 - 40.0) < 1e-3)
    _ = at(3.0)
    #expect(at(3.1).0 == 0.0)
}

@Test func reduced_motion_maps_by_property_class() {
    let s = AnimationStore.new()
    s.setReducedMotion(true)
    s.set(storeNode, prop.offset, .zero)
    s.set(storeNode, prop.opacity, 0.0)
    s.set(storeNode, prop.blur, 4.0)
    s.animate(storeNode, prop.offset, Vec2.new(100.0, 0.0), motion.glide)
    s.animate(storeNode, prop.opacity, 1.0, motion.glide)
    s.animate(storeNode, prop.blur, 0.0, motion.glide)
    s.tickAt(0.0)
    #expect(s.get(storeNode, prop.offset) == Vec2.new(100.0, 0.0), "travel jumps")
    #expect(s.get(storeNode, prop.blur) == 0.0, "blur jumps")
    s.tickAt(0.09)
    let o = s.get(storeNode, prop.opacity)!
    #expect(o > 0.3 && o < 0.7, "opacity takes the short fade: \(o)")
    s.tickAt(0.18)
    #expect(s.get(storeNode, prop.opacity) == 1.0)
    // Gestures are the user's own motion and are untouched.
    s.set(storeNode, prop.scroll, .zero)
    s.release(storeNode, prop.scroll, Vec2.new(0.0, 1000.0), .decay(.iosNormal))
    s.tickAt(0.3)
    #expect(s.get(storeNode, prop.scroll)!.y > 50.0)
}

@Test func multi_lane_values_share_timing() {
    let s = AnimationStore.new()
    s.set(storeNode, prop.fill, Color.hex(0xff0000))
    s.animate(storeNode, prop.fill, Color.hex(0x0000ff), motion.settle)
    s.tickAt(0.15)
    let mid = s.get(storeNode, prop.fill)!
    // All four lanes ride one spring: the colour is the OKLab interpolation at that progress.
    let p = motion.settle.sample(0.0, 0.0, 1.0, 0.15).0
    let a = Color.hex(0xff0000).toOklab()
    let b = Color.hex(0x0000ff).toOklab()
    let want = Color.fromOklab((0..<3).map { k in a[k] + (b[k] - a[k]) * p }, 1.0)
    for (x, y) in [(mid.r, want.r), (mid.g, want.g), (mid.b, want.b), (mid.a, want.a)] {
        #expect(abs(x - y) < 2e-3, "\(mid) vs \(want)")
    }
    s.tickAt(5.0)
    let end = s.get(storeNode, prop.fill)!
    #expect(abs(end.b - 1.0) < 1e-3 && end.r < 1e-3)
}

@Test func retune_respring_keeps_position_and_velocity() {
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.animate(storeNode, storeXProp, 100.0, motion.drift)
    s.setTime(0.2)
    let before = state(s)
    s.tick()
    s.retune(motion.drift, motion.snap)
    let after = state(s)
    #expect(abs(before.0 - after.0) < 1e-3 && abs(before.1 - after.1) < 1e-2)
    s.tickAt(0.2 + Double(motion.snap.settlingDuration(1e-4)) + 0.1)
    #expect(s.get(storeNode, storeXProp) == 100.0)
}

@Test func removing_and_reusing_tracks_is_generational() {
    let s = AnimationStore.new()
    let a = s.set(NodeId(1), storeXProp, 1.0)
    s.removeNode(NodeId(1))
    #expect(!s.contains(a))
    let b = s.set(NodeId(2), storeXProp, 2.0)
    #expect(s.contains(b) && !s.contains(a))
    #expect(s.get(NodeId(2), storeXProp) == 2.0)
    #expect(s.get(NodeId(1), storeXProp) == nil)
}

@Test func a_removed_track_leaves_touched_even_when_its_slot_is_reused() {
    let s = AnimationStore.new()
    s.set(NodeId(1), storeXProp, 1.0)
    s.set(NodeId(3), storeXProp, 3.0)
    s.tick()
    let touched = { (store: AnimationStore) -> [UInt64] in
        store.touched().map { $0.0.rawValue }
    }
    #expect(touched(s) == [1, 3])
    s.removeNode(NodeId(1))
    #expect(touched(s) == [3])
    s.set(NodeId(1), storeXProp, 1.0)
    s.removeNode(NodeId(1))
    // Node 2's track takes the freed slot; the old track's entry doesn't count for it.
    s.set(NodeId(2), storeXProp, 2.0)
    s.tick()
    #expect(touched(s) == [2])
}

@Test func node_time_scale_holds_slows_and_resumes_in_place() {
    let m = NodeId(8)
    let s = AnimationStore.new()
    s.set(storeNode, storeXProp, 0.0)
    s.set(m, storeXProp, 0.0)
    s.setNodeTimeScale(m, 0.5)
    s.animate(storeNode, storeXProp, 100.0, motion.settle)
    s.animate(m, storeXProp, 100.0, motion.settle.delay(0.1))
    s.tickAt(0.1)
    let reference = s.get(storeNode, storeXProp)!
    #expect(s.get(m, storeXProp) == 0.0, "the delay runs at half speed too")
    s.tickAt(0.4)
    #expect(abs(s.get(m, storeXProp)! - reference) < 1e-3)
    // Stopped: nothing moves and nothing counts as running, pending or not.
    s.setNodeTimeScale(storeNode, 0.0)
    s.setNodeTimeScale(m, 0.0)
    let held = (s.get(storeNode, storeXProp)!, s.get(m, storeXProp)!)
    s.tickAt(5.0)
    #expect(s.get(storeNode, storeXProp)! == held.0 && s.get(m, storeXProp)! == held.1)
    #expect(!s.running() && s.activeLen() == 2)
    // Resumed: carries on from the same place on the same curve.
    s.setNodeTimeScale(m, 1.0)
    s.tick()
    #expect(s.get(m, storeXProp)! == held.1)
    #expect(s.running())
    s.tickAt(5.15)
    #expect(abs(s.get(m, storeXProp)! - motion.settle.sample(0.0, 0.0, 100.0, 0.25).0) < 1e-3)
    #expect(s.nodeTimeScale(storeNode) == 0.0)
    #expect(s.nodeTimeScale(m) == 1.0)
}
