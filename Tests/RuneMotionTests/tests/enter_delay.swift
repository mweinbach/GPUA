// Tests ported from: crates/rune-motion/tests/enter_delay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

private let enterDelayHz: Double = 120.0
private let enterDelayRise: Float = 12.0

private func makeEnterDelaySpec() -> NodeSpec {
    NodeSpec.new(Rect.new(0.0, 0.0, 100.0, 40.0))
        .transition(Transition.offset(0.0, enterDelayRise).combined(Transition.opacity()))
}

private func makeEnterDelayScene() -> Scene {
    let s = Scene.new()
    s.setPixelScale(8.0)
    s.frameAt(0.0)
    return s
}

/// (time, offset progress, opacity) of `id` from `from` to `until`.
private func traceEnterDelay(
    _ s: Scene,
    _ from: Double,
    _ until: Double,
    _ id: NodeId
) -> [(Double, Float, Float)] {
    var out: [(Double, Float, Float)] = []
    var t = from
    while t <= until + 1e-9 {
        s.frameAt(t)
        let p = s.presented(id)!
        out.append((t, 1.0 - p.rect.y / enterDelayRise, p.opacity))
        t += 1.0 / enterDelayHz
    }
    return out
}

@Test func holds_the_insertion_effect_then_moves_every_part_together() {
    let s = makeEnterDelayScene()
    let id = NodeId(1)
    s.insertDelayed(id, makeEnterDelaySpec(), .animated, 0.3)
    for (t, offset, opacity) in traceEnterDelay(s, 0.0, 0.29, id) {
        #expect(offset == 0.0 && opacity == 0.0, "t=\(t): waits at the insertion effect")
    }
    let after = traceEnterDelay(s, 0.3, 1.5, id)
    #expect(after.contains { _, o, _ in o > 0.5 }, "it enters")
    for (t, offset, opacity) in after {
        #expect(
            abs(offset - opacity) < 2e-3,
            "t=\(t): offset \(offset) and opacity \(opacity) share one progress"
        )
    }
    #expect(s.presented(id)!.phase == .present)
}

@Test func only_waiting_isnt_running() {
    let s = makeEnterDelayScene()
    s.insertDelayed(NodeId(1), makeEnterDelaySpec(), .animated, 0.3)
    s.frameAt(0.1)
    #expect(abs(s.store().waitingUntil()! - 0.3) < 1e-6)
    s.frameAt(0.31)
    #expect(s.store().waitingUntil() == nil, "the entrance moves")
}

@Test func a_node_clock_stretches_the_delay() {
    let s = makeEnterDelayScene()
    let id = NodeId(1)
    s.insertDelayed(id, makeEnterDelaySpec(), .animated, 0.3)
    s.setTimeScale(id, 0.5)
    s.frameAt(0.1)
    #expect(abs(s.store().waitingUntil()! - 0.6) < 1e-6, "0.3 s at half speed")
    s.frameAt(0.59)
    #expect(s.presented(id)!.opacity == 0.0)
    s.frameAt(0.7)
    #expect(s.presented(id)!.opacity > 0.0)
}

@Test func removed_while_waiting_unseen_goes_at_once() {
    let s = makeEnterDelayScene()
    let id = NodeId(1)
    s.insertDelayed(id, makeEnterDelaySpec(), .animated, 0.3)
    s.frameAt(0.1)
    s.remove(id)
    #expect(s.frameAt(0.11).exited.contains(id), "nothing showed, so there's no exit to play")
    #expect(!s.frameAt(0.5).animating, "the cancelled start never runs")
}

@Test func a_visible_insertion_effect_fades_out_from_where_it_waits() {
    let s = makeEnterDelayScene()
    let id = NodeId(1)
    let slide = NodeSpec.new(Rect.new(0.0, 0.0, 100.0, 40.0))
        .transition(Transition.offset(0.0, enterDelayRise))
    s.insertDelayed(id, slide, .animated, 0.3)
    s.frameAt(0.1)
    #expect(s.presented(id)!.rect.y == enterDelayRise && s.presented(id)!.opacity == 1.0)
    s.remove(id)
    var last: Float = 1.0
    for (t, offset, opacity) in traceEnterDelay(s, 0.1, 0.25, id) {
        #expect(offset == 0.0, "t=\(t): it stays where it waited")
        #expect(opacity <= last, "t=\(t): fades out, \(opacity) after \(last)")
        last = opacity
    }
    #expect(last < 1.0)
}

@Test func entering_now_lands_a_waiting_entrance() {
    let s = makeEnterDelayScene()
    let id = NodeId(1)
    s.insertDelayed(id, makeEnterDelaySpec(), .animated, 0.3)
    s.frameAt(0.1)
    s.landWaiting(id)
    let out = s.frameAt(0.11)
    #expect(!out.animating)
    let p = s.presented(id)!
    #expect(p.rect.y == 0.0 && p.opacity == 1.0 && p.phase == .present)
}

@Test func reduce_motion_keeps_the_delay_and_only_fades() {
    let s = makeEnterDelayScene()
    s.setReducedMotion(true)
    let id = NodeId(1)
    s.insertDelayed(id, makeEnterDelaySpec(), .animated, 0.3)
    let steps = traceEnterDelay(s, 0.0, 1.0, id)
    for (t, offset, opacity) in steps {
        #expect(offset == 1.0, "t=\(t): nothing travels")
        if t < 0.3 - 1e-9 {
            #expect(opacity == 0.0, "t=\(t): the fade waits")
        }
    }
    let shown = steps.first { $0.2 >= 1.0 }!.0
    #expect(shown > 0.3 && shown < 0.6, "the short fade, after the delay: \(shown)")
}

@Test func a_staggered_list_of_five_enters_in_order() {
    let s = makeEnterDelayScene()
    let stg = Stagger.new(0.05)
    for i in 0..<5 {
        s.insertDelayed(NodeId(UInt64(i + 1)), makeEnterDelaySpec(), .animated, stg.delay(i, 5))
    }
    var starts = Array<Double?>(repeating: nil, count: 5)
    var t = 0.0
    while t < 1.5 {
        s.frameAt(t)
        for i in 0..<5 {
            let p = s.presented(NodeId(UInt64(i + 1)))!
            let offset = 1.0 - p.rect.y / enterDelayRise
            let opacity = p.opacity
            #expect(abs(offset - opacity) < 2e-3, "row \(i) t=\(t): \(offset) vs \(opacity)")
            if opacity > 0.0 && starts[i] == nil {
                starts[i] = t
            }
        }
        t += 1.0 / enterDelayHz
    }
    let unwrapped = starts.map { $0! }
    for i in 0..<4 {
        #expect(
            abs(unwrapped[i + 1] - unwrapped[i] - 0.05) < 1.5 / enterDelayHz,
            "row \(i + 1) starts 50 ms after row \(i): \(unwrapped)"
        )
    }
}
