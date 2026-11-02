// Tests ported from: crates/rune-motion/tests/scene.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

private let sceneHz: Double = 120.0

private func find(_ out: [Presented], _ id: NodeId) -> Presented? {
    out.first { $0.node == id }
}

private func spec(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> NodeSpec {
    NodeSpec.new(Rect.new(x, y, w, h))
}

/// Steps the scene at `sceneHz` until `until`, collecting every presented value of `id`.
private func run(
    _ s: Scene,
    _ from: Double,
    _ until: Double,
    _ id: NodeId
) -> ([(Double, Presented)], Double?) {
    var seen: [(Double, Presented)] = []
    var exitedAt: Double? = nil
    var t = from
    while t <= until + 1e-9 {
        let out = s.frameAt(t)
        if let p = find(out.changed, id) {
            seen.append((t, p))
        }
        if out.exited.contains(id) && exitedAt == nil {
            exitedAt = t
        }
        t += 1.0 / sceneHz
    }
    return (seen, exitedAt)
}

private func sameLook(_ a: Presented, _ b: Presented) {
    let close = { (x: Float, y: Float) -> Bool in abs(x - y) < 2e-3 }
    #expect(close(a.opacity, b.opacity), "opacity \(a.opacity) → \(b.opacity)")
    #expect(close(a.blur, b.blur), "blur \(a.blur) → \(b.blur)")
    #expect(close(a.transform.scale.x, b.transform.scale.x))
    #expect(close(a.rect.x, b.rect.x) && close(a.rect.y, b.rect.y), "\(a.rect) → \(b.rect)")
}

private func maxPathDeviation(
    _ points: [(Float, Float)],
    _ start: (Float, Float),
    _ end: (Float, Float)
) -> Float {
    let dx = end.0 - start.0
    let dy = end.1 - start.1
    let len = (dx * dx + dy * dy).squareRoot()
    var maxDev: Float = 0.0
    for (x, y) in points {
        let dev = abs((x - start.0) * dy - (y - start.1) * dx) / len
        maxDev = max(maxDev, dev)
    }
    return maxDev
}

@Test func pixel_scale_resnaps_settled_nodes_without_retargeting() {
    let make = { (scale: Float) -> Scene in
        let scene = Scene.new()
        scene.setPixelScale(scale)
        scene.insert(NodeId(1), spec(0.123, 0.137, 30.123, 20.137), .initial)
        scene.frameAt(0.0)
        return scene
    }
    let scene = make(1.0)
    for scale: Float in [2.0, 1.5, 1.0] {
        scene.setPixelScale(scale)
        #expect(scene.frameAt(0.0).changed.count == 1, "scale changes invalidate settled poses")
        let fresh = make(scale)
        #expect(scene.presented(NodeId(1))!.rect == fresh.presented(NodeId(1))!.rect)
        scene.setPixelScale(scale)
        #expect(scene.frameAt(0.0).changed.isEmpty, "an unchanged scale does no work")
    }
}

@Test func instant_frame_lands_an_unchanged_target_mid_flight() {
    let s = Scene.new()
    let id = NodeId(1)
    s.insert(id, spec(0.0, 0.0, 100.0, 40.0), .initial)
    s.frameAt(0.0)
    let target = Rect.new(30.0, 60.0, 200.0, 120.0)
    s.setFrame(id, target, Spring.new(0.32, 0.0))
    #expect(s.frameAt(0.05).animating)
    s.setFrame(id, target, LayoutAnim.instant)
    #expect(!s.frameAt(0.05).animating)
    #expect(s.presented(id)!.rect == target)
}

@Test func first_mount_does_not_animate() {
    let s = Scene.new()
    s.insert(NodeId(1), spec(0.0, 0.0, 100.0, 40.0).transition(Transition.blurReplace()), .initial)
    let out = s.frameAt(0.0)
    let p = find(out.changed, NodeId(1))!
    #expect(p.opacity == 1.0 && p.blur == 0.0 && p.transform.scale.x == 1.0)
    #expect(!out.animating)
    #expect(p.phase == .present)
}

@Test func blur_replace_enters_and_exits_and_never_unmounts_visible() {
    let s = Scene.new()
    let id = NodeId(2)
    s.insert(id, spec(0.0, 0.0, 200.0, 60.0).transition(Transition.blurReplace()), .animated)
    let (enter, _) = run(s, 0.0, 1.0, id)
    let first = enter[0].1
    #expect(
        first.opacity < 1e-3
            && abs(first.blur - 1.5) < 1e-3
            && abs(first.transform.scale.x - 0.96) < 1e-4
    )
    let last = enter.last!.1
    #expect(last.opacity == 1.0 && last.blur == 0.0 && last.transform.scale.x == 1.0, "rests exactly, no filter")
    #expect(s.phase(id) == .present)
    let enterTime = enter.last!.0

    s.setTime(2.0)
    s.remove(id)
    let (exit, exitedAtOpt) = run(s, 2.0, 3.0, id)
    let exitedAt = exitedAtOpt!
    // Drawn every frame until it's gone; the final presented frame is fully transparent.
    let finalFrame = exit.reversed().first { $0.0 <= exitedAt }!.1
    #expect(finalFrame.opacity < 1.0 / 255.0, "unmounted at opacity \(finalFrame.opacity)")
    for (_, p) in exit {
        #expect(p.blur <= 1.5 + 1e-3 && p.transform.scale.x >= 0.9)
        #expect(!p.inFlow, "popLayout: exiting nodes leave flow")
    }
    #expect(!s.contains(id))
    // Exits run shorter than entrances.
    #expect(exitedAt - 2.0 < enterTime, "exit \(exitedAt - 2.0) vs enter \(enterTime)")
}

@Test func an_exit_unmounts_once_it_fades_out_of_sight() {
    for transition in [Transition.opacity(), Transition.push(.bottom), Transition.scale(0.9)] {
        let s = Scene.new()
        let id = NodeId(4)
        s.insert(id, spec(0.0, 0.0, 120.0, 40.0).transition(transition), .initial)
        s.frameAt(0.0)
        s.remove(id)
        let (exit, exitedAtOpt) = run(s, 0.0, 1.0, id)
        let exitedAt = exitedAtOpt!
        let unseen = exit.first { $0.1.opacity < 1.0 / 255.0 }!.0
        #expect(exitedAt == unseen, "unmounts the frame it can no longer be seen")
    }
}

@Test func a_key_that_returns_mid_exit_revives_without_a_jump() {
    for transition in [Transition.blurReplace(), Transition.push(.bottom), Transition.scale(0.9)] {
        var s = Scene.new()
        let id = NodeId(3)
        let sp = spec(0.0, 0.0, 120.0, 40.0).transition(transition)
        s.insert(id, sp, .initial)
        s.frameAt(0.0)
        s.remove(id)
        let (_, gone) = run(s, 0.0, 0.1, id)
        #expect(gone == nil)
        var t = 0.1 + 1.0 / sceneHz
        let before = find(s.frameAt(t).changed, id)!
        s.insert(id, sp, .animated) // same key comes back
        let after = find(s.frameAt(t).changed, id)!
        sameLook(before, after)
        #expect(after.phase == .entering)
        // ... and lands exactly at rest.
        let (seen, gone2) = run(s, t, t + 1.5, id)
        #expect(gone2 == nil)
        let rest = seen.last!.1
        #expect(rest.opacity == 1.0 && rest.blur == 0.0 && rest.transform.scale.x == 1.0)
        #expect(rest.rect == Rect.new(0.0, 0.0, 120.0, 40.0))

        // The same, the other way round: removed mid-entrance.
        s = Scene.new()
        s.insert(NodeId(9), spec(0.0, 0.0, 10.0, 10.0), .initial)
        s.frameAt(0.0)
        s.insert(id, sp, .animated)
        _ = run(s, 0.0, 0.08, id)
        t = 0.08 + 1.0 / sceneHz
        let before2 = find(s.frameAt(t).changed, id)!
        s.remove(id)
        let after2 = find(s.frameAt(t).changed, id)!
        sameLook(before2, after2)
        let (seen2, gone3) = run(s, t, t + 1.0, id)
        #expect(gone3 != nil)
        #expect(seen2.last!.1.opacity < 1.0 / 255.0)
    }
}

@Test func a_key_that_returns_mid_exit_on_an_initial_mount_lands_at_rest() {
    for transition in [Transition.opacity(), Transition.blurReplace(), Transition.push(.bottom)] {
        let s = Scene.new()
        let id = NodeId(5)
        let sp = spec(0.0, 0.0, 120.0, 40.0).transition(transition)
        s.insert(id, sp, .initial)
        s.frameAt(0.0)
        s.remove(id)
        // Deep in the exit tail.
        let (seen, gone) = run(s, 0.0, 0.2, id)
        #expect(gone == nil && seen.last!.1.opacity < 0.2)
        let t = 0.2 + 1.0 / sceneHz
        let moved = Rect.new(10.0, 30.0, 140.0, 40.0)
        s.insert(id, NodeSpec.new(moved).transition(transition), .initial)
        let out = s.frameAt(t)
        #expect(!out.animating, "nothing left to animate")
        let p = find(out.changed, id)!
        #expect(p.opacity == 1.0 && p.blur == 0.0 && p.transform.scale.x == 1.0 && p.phase == .present)
        #expect(p.rect == moved, "at its final layout")
        // The stale exit never retires it.
        let (seen2, gone2) = run(s, t, t + 1.0, id)
        #expect(gone2 == nil && s.contains(id))
        #expect(seen2.allSatisfy { $0.1.opacity == 1.0 && $0.1.rect == moved })
    }
}

@Test func an_initial_mount_revive_lands_motion_toward_the_same_frame_and_screen_travel() {
    for screen in [false, true] {
        let s = Scene.new()
        let id = NodeId(6)
        let target = Rect.new(60.0, 80.0, 120.0, 40.0)
        s.insert(id, spec(0.0, 0.0, 120.0, 40.0).transition(Transition.opacity()), .initial)
        s.frameAt(0.0)
        let slow = LayoutAnim.new(Spring.new(1.0, 0.0))
        s.setFrame(id, target, screen ? slow.screen() : slow)
        s.frameAt(0.05)
        s.remove(id)
        let (seen, gone) = run(s, 0.05, 0.15, id)
        #expect(gone == nil && seen.last!.1.rect != target, "still travelling")
        let t = 0.15 + 1.0 / sceneHz
        s.insert(id, NodeSpec.new(target).transition(Transition.opacity()), .initial)
        let out = s.frameAt(t)
        #expect(!out.animating, "nothing left to animate (screen: \(screen))")
        let p = find(out.changed, id)!
        #expect(p.opacity == 1.0 && p.rect == target && p.phase == .present)
        let (seen2, _) = run(s, t, t + 1.0, id)
        #expect(seen2.allSatisfy { $0.1.opacity == 1.0 && $0.1.rect == target })
    }
}

@Test func stationary_edges_never_move_and_width_leads() {
    let s = Scene.new()
    let id = NodeId(4)
    s.insert(id, spec(0.0, 0.0, 100.0, 50.0), .initial)
    s.frameAt(0.0)
    s.setFrame(id, Rect.new(0.0, 20.0, 300.0, 30.0), LayoutAnim.new(motion.reflow).widthLeads())
    let (seen, _) = run(s, 0.0, 1.5, id)
    #expect(seen.count > 30)
    var xAhead = 0
    for (_, p) in seen {
        #expect(p.rect.x == 0.0, "left edge is stationary")
        #expect(p.rect.y + p.rect.h == 50.0, "bottom edge is stationary")
        let xp = (p.rect.right() - 100.0) / 200.0
        let yp = p.rect.y / 20.0
        if xp > yp + 1e-3 {
            xAhead += 1
        }
    }
    #expect(xAhead > 10, "width leads (\(xAhead) frames ahead)")
    #expect(seen.last!.1.rect == Rect.new(0.0, 20.0, 300.0, 30.0))
}

@Test func screen_travel_takes_one_straight_path() {
    let childPath = { (screen: Bool) -> ([(Float, Float)], (Float, Float), Scene) in
        let s = Scene.new()
        let (p, c) = (NodeId(10), NodeId(11))
        s.insert(p, spec(0.0, 0.0, 400.0, 400.0), .initial)
        s.insert(c, spec(10.0, 10.0, 50.0, 50.0).parent(p), .initial)
        s.frameAt(0.0)
        // One commit: the parent glides, the child moves inside it on a different spring.
        s.setFrame(p, Rect.new(200.0, 100.0, 400.0, 400.0), motion.glide)
        let child = LayoutAnim.new(motion.drift)
        s.setFrame(c, Rect.new(100.0, 200.0, 50.0, 50.0), screen ? child.screen() : child)
        let (seen, _) = run(s, 0.0, 3.0, c)
        let pts = seen.map { ($0.1.rect.x, $0.1.rect.y) }
        let last = pts.last!
        return (pts, last, s)
    }
    let (pts, last, s) = childPath(true)
    #expect(last.0 == 300.0 && last.1 == 300.0)
    let dev = maxPathDeviation(pts, (10.0, 10.0), (300.0, 300.0))
    #expect(dev < 0.05, "screen travel deviates \(dev) pt from a straight line")
    // Monotone: never reverses.
    for i in 0..<(pts.count - 1) {
        #expect(pts[i + 1].0 >= pts[i].0 - 1e-3 && pts[i + 1].1 >= pts[i].1 - 1e-3)
    }
    // Once there, the child rides its parent again.
    s.setFrame(NodeId(10), Rect.new(0.0, 0.0, 400.0, 400.0), Anim.instant)
    let out = s.frameAt(3.1)
    #expect(find(out.changed, NodeId(11))!.rect.origin() == Vec2.new(100.0, 200.0))

    let (ptsParent, _, _) = childPath(false)
    let devParent = maxPathDeviation(ptsParent, (10.0, 10.0), (300.0, 300.0))
    #expect(devParent > 2.0, "parent-space travel with mixed springs dog-legs (\(devParent) pt): the test bites")
}

@Test func matched_geometry_morphs_one_surface() {
    let s = Scene.new()
    let (chip, panel) = (NodeId(20), NodeId(21))
    let red = Color.hex(0xff3b30)
    let white = Color.white
    s.insert(chip, spec(10.0, 10.0, 80.0, 30.0).radius(15.0).fill(red), .initial)
    let before = find(s.frameAt(0.0).changed, chip)!
    s.setTime(1.0 / sceneHz)
    s.insert(panel, spec(0.0, 100.0, 300.0, 200.0).radius(12.0).fill(white), .initial)
    s.matchGeometry(chip, panel, LayoutAnim.new(motion.morph).widthLeads())
    let out = s.frameAt(1.0 / sceneHz)
    #expect(out.exited.contains(chip))
    let first = find(out.changed, panel)!
    #expect(first.rect == before.rect, "starts exactly where the chip was seen")
    #expect(first.radius == Corners.all(15.0))
    #expect(abs(first.fill.r - red.r) < 2e-3 && first.opacity == 1.0)
    let (seen, _) = run(s, 2.0 / sceneHz, 2.0, panel)
    let last = seen.last!.1
    #expect(last.rect == Rect.new(0.0, 100.0, 300.0, 200.0))
    #expect(last.radius == Corners.all(12.0))
}

@Test func reduced_motion_swaps_travel_for_a_short_fade() {
    let s = Scene.new()
    s.setReducedMotion(true)
    let id = NodeId(30)
    s.insert(NodeId(31), spec(0.0, 0.0, 10.0, 10.0), .initial)
    s.frameAt(0.0)
    s.insert(
        id,
        spec(0.0, 0.0, 100.0, 40.0).transition(Transition.blurReplace().combined(Transition.push(.top))),
        .animated
    )
    let first = find(s.frameAt(0.0).changed, id)!
    #expect(
        first.blur == 0.0 && first.transform.scale.x == 1.0 && first.rect.y == 0.0,
        "no blur, scale or travel"
    )
    #expect(first.opacity < 1e-3)
    let mid = find(s.frameAt(0.09).changed, id)!
    #expect(mid.opacity > 0.3 && mid.opacity < 0.7, "\(mid.opacity)")
    #expect(find(s.frameAt(0.18).changed, id)!.opacity == 1.0)
    s.setFrame(id, Rect.new(50.0, 50.0, 100.0, 40.0), motion.glide)
    #expect(find(s.frameAt(0.2).changed, id)!.rect.origin() == Vec2.new(50.0, 50.0), "layout jumps")
}

@Test func children_ride_their_parent_in_and_out() {
    let s = Scene.new()
    let (p, c) = (NodeId(40), NodeId(41))
    s.insert(NodeId(1), spec(0.0, 0.0, 1.0, 1.0), .initial)
    s.frameAt(0.0)
    s.insert(p, spec(0.0, 0.0, 100.0, 100.0).transition(Transition.moveEdge(.leading)), .animated)
    s.insert(c, spec(10.0, 10.0, 20.0, 20.0).parent(p), .animated)
    let out = s.frameAt(0.0)
    let (pp, cp) = (find(out.changed, p)!, find(out.changed, c)!)
    #expect(cp.phase == .present, "rides the entering parent instead of animating itself")
    #expect(cp.rect.x == pp.rect.x + 10.0, "moves with the parent's presence offset")
    s.setTime(1.0)
    s.remove(p)
    let (_, gone) = run(s, 1.0, 2.0, p)
    #expect(gone != nil)
    #expect(!s.contains(c))
}

@Test func a_child_mounted_after_its_parent_visibly_arrives_enters_on_its_own() {
    let s = Scene.new()
    let (p, c) = (NodeId(42), NodeId(43))
    s.insert(NodeId(1), spec(0.0, 0.0, 1.0, 1.0), .initial)
    s.frameAt(0.0)
    s.insert(p, spec(0.0, 0.0, 100.0, 100.0), .animated)
    var t = 0.0
    while true {
        t += 1.0 / sceneHz
        let out = s.frameAt(t)
        if let pp = find(out.changed, p), pp.opacity >= 1.0 - 1.0 / 255.0 {
            break
        }
        #expect(t < 2.0, "the parent arrives")
    }
    #expect(s.phase(p) == .entering, "its presence is still settling")
    s.setTime(t + 1.0 / sceneHz)
    s.insert(c, spec(10.0, 10.0, 20.0, 20.0).parent(p), .animated)
    let cp = find(s.frame().changed, c)!
    #expect(cp.phase == .entering, "fades in instead of popping in on a finished entrance")
    #expect(cp.opacity < 0.5, "\(cp.opacity)")
}

@Test func a_child_mounted_late_in_its_parents_entrance_enters_on_its_own() {
    let s = Scene.new()
    let (p, c) = (NodeId(44), NodeId(45))
    s.insert(NodeId(1), spec(0.0, 0.0, 1.0, 1.0), .initial)
    s.frameAt(0.0)
    s.insert(p, spec(0.0, 0.0, 100.0, 100.0), .animated)
    var t = 0.0
    while true {
        t += 1.0 / sceneHz
        let out = s.frameAt(t)
        if let pp = find(out.changed, p), pp.opacity >= 0.9 {
            break
        }
        #expect(t < 2.0, "the parent arrives")
    }
    s.setTime(t + 1.0 / sceneHz)
    s.insert(c, spec(10.0, 10.0, 20.0, 20.0).parent(p), .animated)
    let cp = find(s.frame().changed, c)!
    #expect(cp.phase == .entering, "fades in instead of appearing at the parent's 90%")
    #expect(cp.opacity < 0.5, "\(cp.opacity)")
}

@Test func flags_mark_intent_for_motion_lint() {
    let s = Scene.new()
    let id = NodeId(50)
    s.insert(id, spec(0.0, 0.0, 100.0, 40.0), .initial)
    s.frameAt(0.0)
    s.setFrame(id, Rect.new(0.0, 80.0, 100.0, 40.0), motion.settle)
    let p = find(s.frameAt(0.05).changed, id)!
    #expect(p.flags & flags.animated != 0)
    #expect((p.flags >> 8) & Intent.position != 0)
}

@Test func trace_writes_motion_lint_jsonl() {
    let s = Scene.new()
    let header = TraceHeader(launch: "test", width: 400.0, height: 300.0, hz: 120.0, scale: 2.0)
    let (trace, buf) = MotionTrace.inMemory(header)
    s.setTrace(trace)
    s.insert(NodeId(1), spec(0.0, 0.0, 10.0, 10.0), .initial)
    s.frameAt(0.0)
    s.insert(NodeId(2), spec(0.0, 20.0, 100.0, 40.0).transition(Transition.blurReplace()), .animated)
    _ = run(s, 0.0, 0.6, NodeId(2))
    s.remove(NodeId(2))
    _ = run(s, 0.6, 1.4, NodeId(2))
    _ = s.takeTrace()
    let text = buf.contents()
    let lines = text.split(separator: "\n").map(String.init)
    #expect(lines[0].hasPrefix(#"{"type":"header","launch":"test""#))
    #expect(lines.contains { $0.contains(#""e":[[2,"#) }, "elements")
    #expect(lines.contains { $0.contains(#""ai":[[2,"#) }, "intents")
    #expect(lines.contains { $0.contains(#""g":[2]"#) }, "gone after exit")
    #expect(lines.allSatisfy { $0.hasPrefix("{") && $0.hasSuffix("}") })
}

@Test func scale_stays_above_point_nine_unless_a_small_glyph_opts_in() {
    let start = { (t: Transition) -> Float in
        let s = Scene.new()
        s.insert(NodeId(9), spec(0.0, 0.0, 16.0, 16.0).transition(t), .animated)
        return find(s.frameAt(0.0).changed, NodeId(9))!.transform.scale.x
    }
    #expect(abs(start(Transition.scale(0.6)) - 0.9) < 1e-4, "the default rule")
    #expect(abs(start(Transition.scale(0.6).allowSmallScale()) - 0.6) < 1e-4)
    #expect(abs(start(Transition.scale(0.0).allowSmallScale()) - smallScaleFloor) < 1e-4, "never from 0")
    #expect(abs(start(Transition.scale(0.6).allowSmallScale().combined(Transition.opacity())) - 0.6) < 1e-4)

    // The removal leaves at the small scale too, still fading out.
    let s = Scene.new()
    let id = NodeId(10)
    s.insert(id, spec(0.0, 0.0, 16.0, 16.0).transition(Transition.scale(0.6).allowSmallScale()), .initial)
    s.frameAt(0.0)
    s.remove(id)
    let (exit, exitedAtOpt) = run(s, 0.0, 1.0, id)
    let exitedAt = exitedAtOpt!
    let last = exit.reversed().first { $0.0 <= exitedAt }!.1
    #expect(last.transform.scale.x < 0.65 && last.opacity < 1.0 / 255.0, "\((last.transform.scale.x, last.opacity))")
}

@Test func a_frozen_ancestor_holds_screen_travel_without_frames() {
    let s = Scene.new()
    let (p, c) = (NodeId(10), NodeId(11))
    s.insert(p, spec(0.0, 0.0, 400.0, 400.0), .initial)
    s.insert(c, spec(10.0, 10.0, 50.0, 50.0).parent(p), .initial)
    s.frameAt(0.0)
    s.setFrame(p, Rect.new(200.0, 100.0, 400.0, 400.0), motion.glide)
    s.setFrame(c, Rect.new(100.0, 200.0, 50.0, 50.0), LayoutAnim.new(motion.drift).screen())
    s.frameAt(0.05)
    s.setTimeScale(p, 0.0)
    var t = 0.05
    while t < 3.0 {
        t += 1.0 / sceneHz
        s.frameAt(t)
    }
    #expect(!s.frameAt(t).animating, "the child arrived and its frozen parent asks for no frames")
    s.setTimeScale(p, 1.0)
    let (seen, _) = run(s, t, t + 3.0, c)
    #expect(!s.frameAt(t + 3.1).animating)
    #expect(seen.last!.1.rect.origin() == Vec2.new(300.0, 300.0))
}

@Test func a_trailing_child_rests_where_its_parent_does() {
    let (p, c) = (NodeId(1), NodeId(2))
    let s = Scene.new()
    s.insert(p, spec(0.0, 0.0, 40.0, 20.0), .initial)
    s.insert(c, spec(30.0, 4.0, 6.0, 6.0).parent(p), .initial)
    s.setRideTrailing(c, true)
    s.frameAt(0.0)
    s.setFrame(p, Rect.new(0.0, 0.0, 70.0, 20.0), Spring.new(0.3, 0.0))
    s.frameAt(0.05)
    let shown = s.presented(c)!
    let rest = s.rest(c)
    #expect(shown.rect.x > 30.0 && shown.rect.x < 60.0, "\(shown.rect)")
    #expect(rest == Rect.new(60.0, 4.0, 6.0, 6.0), "the child comes to rest against the parent's new edge")
}

@Test func a_static_node_keeps_no_tracks_and_an_unchanged_commit_leaves_it_clean() {
    let id = NodeId(1)
    let frame = Rect.new(0.0, 0.0, 100.0, 40.0)
    let s = Scene.new()
    s.insert(id, NodeSpec.new(frame).opacity(0.5).radius(Corners(4.0, 4.0, 4.0, 4.0)), .initial)
    s.frameAt(0.0)
    #expect(s.store().trackLen() == 0, "a node that never moves keeps no tracks, presence included")
    for k in 1..<3 {
        s.setFrame(id, frame, Spring.new(0.3, 0.0))
        s.animate(id, prop.opacity, 0.5, Spring.new(0.3, 0.0))
        s.set(id, prop.radius, Corners(4.0, 4.0, 4.0, 4.0))
        #expect(s.frameAt(Double(k) / sceneHz).changed.isEmpty, "nothing changed, so nothing presents again")
    }
    #expect(s.store().trackLen() == 0)
}

@Test func a_settled_track_set_to_its_value_stays_clean() {
    let id = NodeId(1)
    let s = Scene.new()
    s.insert(id, spec(0.0, 0.0, 100.0, 40.0), .initial)
    s.frameAt(0.0)
    s.animate(id, prop.opacity, 0.2, Spring.new(0.2, 0.0))
    let half = s.frameAt(0.05)
    let o = find(half.changed, id)!.opacity
    #expect(o < 1.0 && o > 0.2, "the first animation starts from the base value: \(o)")
    var t = 0.05
    while s.frameAt(t).animating {
        t += 1.0 / sceneHz
    }
    s.set(id, prop.opacity, 0.2)
    s.animate(id, prop.opacity, 0.2, Spring.new(0.2, 0.0))
    #expect(s.frameAt(t + 1.0 / sceneHz).changed.isEmpty)
}

@Test func a_node_without_a_presence_track_still_fades_out() {
    let id = NodeId(1)
    let s = Scene.new()
    s.insert(id, spec(0.0, 0.0, 100.0, 40.0), .initial)
    s.frameAt(0.0)
    s.remove(id)
    let o = find(s.frameAt(0.05).changed, id)!.opacity
    #expect(o > 0.0 && o < 1.0, "the exit plays: \(o)")
    var t = 0.05
    var gone = false
    while t < 3.0 && !gone {
        t += 1.0 / sceneHz
        gone = s.frameAt(t).exited.contains(id)
    }
    #expect(gone)
}
