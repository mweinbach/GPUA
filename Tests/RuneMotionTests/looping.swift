// Tests ported from: crates/rune-motion/src/looping.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func sequence_delays_interpolates_holds_and_finishes_without_restarting() {
    let beats: [Beat] = [
        Beat.new(0.0).opacity(0.0).scale(0.8),
        Beat.new(0.3).easing(.linear),
        Beat.new(0.6).opacity(0.5).scale(1.1).easing(.linear),
        Beat.new(0.9).easing(.linear),
    ]
    let spec = LoopSpec.sequence(Sequence.new(beats).delay(0.2))
    var track = LoopTrack.new(spec, 4.0)
    #expect(track.pendingStart(4.0) == 4.2)
    #expect(!track.active(4.1))
    let pose = track.pose(4.35, false)!
    #expect(abs(pose.opacity - 0.5) < 1e-5 && abs(pose.scale - 0.9) < 1e-5)
    track.retime(spec, 4.35)
    #expect(track.pose(4.35, false)! == pose)
    #expect(track.active(4.35))
    #expect(!track.active(5.2))
    #expect(track.pose(5.2, false)!.opacity == 1.0)
    #expect(track.pose(4.35, true)!.scale == 1.0)
    track.finish()
    #expect(!track.active(4.35))
    #expect(track.pendingStart(4.0) == nil)
    #expect(track.pose(4.35, false)!.scale == 1.0)
}

@Test func cycle_preserves_wall_phase_stops_still_and_cadence() {
    let c = Cycle(
        period: 1.7,
        phase: 0.3,
        stops: [(0.0, 0.2), (0.2, 1.0), (0.7, 0.1), (1.0, 0.2)],
        still: 0.4,
        fps: 30.0
    )
    let track = LoopTrack.new(LoopSpec.cycle(c), 4.0)
    for i in 0..<200 {
        let wall = Double(i) * 0.037
        #expect(track.sampleAt(4.0, wall, false) == c.sample(wall))
        #expect(track.sampleAt(4.0, wall, true) == c.still)
    }
    #expect(track.frameInterval() == Double(Float(1.0) / Float(30.0)))
}

@Test func delay_has_one_wake_and_no_active_frames() {
    let track = LoopTrack.new(LoopSpec.opacity(1.0, 2.0, 0.0, 1.0), 3.0)
    #expect(track.pendingStart(3.0) == 5.0)
    #expect(!track.active(4.999))
    #expect(track.sample(4.999, false) == 0.0)
    #expect(track.pendingStart(5.0) == nil)
    #expect(track.active(5.0))
    #expect(track.phase(5.0) == 0.0)
}

@Test func phase_continuity_and_clock_sampling() {
    var t = LoopTrack.new(LoopSpec.rotation(0.9), 4.0)
    for i in 0..<200 {
        let now = 4.0 + Double(i) * 0.037
        let before = t.phase(now)
        t.retime(LoopSpec.rotation(0.2 + Double(i % 9) * 0.1), now)
        #expect(abs(before - t.phase(now)) < 1e-12)
        #expect(t.sample(now, false) == t.sample(now, false))
    }
    #expect(t.sample(100.0, true) == 0.0)
}

@Test func slide_sweeps_wraps_holds_midpoint_reduced_and_cools_to_rest() {
    var t = LoopTrack.new(LoopSpec.slide(2.0, [-1.0, 0.0], [3.0, 0.0]), 0.0)
    #expect(t.offset(0.0, false) == [-1.0, 0.0])
    #expect(t.offset(1.0, false) == [1.0, 0.0])
    #expect(t.offset(2.0, false) == t.offset(0.0, false))
    let xs: [Float] = (0..<200).map { i in t.offset(Double(i) * 0.01, false)![0] }
    for i in 0..<(xs.count - 1) {
        #expect(xs[i + 1] >= xs[i], "a sweep only moves forward within a period")
    }
    #expect(t.offset(0.37, true) == [1.0, 0.0])
    #expect(t.sample(0.37, false) == 1.0, "a slide never changes opacity")
    #expect(LoopTrack.new(LoopSpec.rotation(1.0), 0.0).offset(0.5, false) == nil)
    t.enabled(false, 1.0)
    #expect(t.active(1.01))
    #expect(!t.active(10.0))
    #expect(t.offset(10.0, false) == [0.0, 0.0])
}

@Test func a_linear_slide_sweeps_at_a_constant_speed_and_holds_its_midpoint_reduced() {
    let spec = LoopSpec.slide(2.0, [-1.0, 0.0], [3.0, 0.0]).easing(.linear)
    let t = LoopTrack.new(spec, 0.0)
    // 240 frames at 120 Hz: one period, each frame the same step forward.
    let xs: [Float] = (0..<240).map { i in t.offset(Double(i) / 120.0, false)![0] }
    #expect(xs[0] == -1.0)
    for i in 0..<(xs.count - 1) {
        #expect(abs(xs[i + 1] - xs[i] - 4.0 / 240.0) < 1e-4, "step \(xs[i]) -> \(xs[i + 1])")
    }
    #expect(t.offset(2.0, false) == [-1.0, 0.0], "wraps after a period")
    #expect(t.offset(0.37, true) == [1.0, 0.0], "reduced motion holds the midpoint")
    #expect(t.sample(0.37, false) == 1.0)
    // The default stays ease-in-out, and naming it is the same spec.
    let eased = LoopSpec.slide(2.0, [-1.0, 0.0], [3.0, 0.0])
    #expect(
        eased.easing(.linear).easing(.easeInOut).kind
            == .slideEased(from: [-1.0, 0.0], to: [3.0, 0.0], easing: .easeInOut)
    )
    let e = LoopTrack.new(eased, 0.0)
    let rawOffsets: [Float] = (0..<121).map { i in e.offset(Double(i) / 120.0, false)![0] }
    let stepDeltas: [Float] = (0..<120).map { i in rawOffsets[i + 1] - rawOffsets[i] }
    #expect(stepDeltas[60] > stepDeltas[0] * 4.0, "ease-in-out starts slow")
    #expect(LoopSpec.rotation(1.0).easing(.linear) == LoopSpec.rotation(1.0), "only slides take a curve")
}

@Test func cooling_keeps_phase_and_settles() {
    var t = LoopTrack.new(LoopSpec.opacity(1.0, 0.0, 0.15, 0.65), 0.0)
    let before = t.sample(0.3, false)
    t.enabled(false, 0.3)
    #expect(t.sample(0.3, false) == before)
    #expect(t.active(0.31))
    #expect(!t.active(10.0))
    #expect(t.sample(10.0, false) == 0.15)
}

@Test func clock_pause_scale_step_and_seek_match_reference() {
    let spec = LoopSpec.rotation(0.9)
    let t = LoopTrack.new(spec, 0.0)
    var clock = Clock.manual(120.0)
    for _ in 0..<17 { clock.step() }
    let first = t.sample(clock.now(), false)
    clock.pause(0.0)
    for _ in 0..<40 { clock.step() }
    #expect(t.sample(clock.now(), false) == first)
    clock.resume(0.0)
    clock.setScale(0.25, 0.0)
    clock.step()
    let reference = Float((17.0 / 120.0 + 0.25 / 120.0) / 0.9) * Float(6.28318530717958647692528676655900577)
    #expect(abs(t.sample(clock.now(), false) - reference) < 1e-6)
    clock.seek(0.45)
    #expect(abs(t.sample(clock.now(), false) - Float.pi) < 1e-6)
}
