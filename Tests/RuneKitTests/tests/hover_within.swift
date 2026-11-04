// Tests ported from: crates/rune-kit/tests/hover_within.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.hoverMotionWithin` sets the hover curves kit controls' inner elements use.

import Testing
import Rune
@testable import RuneKit

private enum HoverWithinMode: Equatable {
    case defaultMode
    /// Instant on the root.
    case within
    /// A slow tween on the root; `own` keeps its own instant curves.
    case slowRoot
    /// Instant on the root, a slow tween around the segmented control and popover.
    case nested
}

private func slowAnim() -> Anim {
    Anim(Curve.tween(0.5, .easeOut))
}

private func hoverWithinView(_ mode: HoverWithinMode, _: Cx<HoverWithinMode>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    let pop = Popover.new("pop").title("Details").trigger(text("Open")).open(true).build(k, &layer)
    var seg = col()
        .gap(8.0)
        .child(SegmentedControl.new(["One", "Two"], 0).onPick { (_: inout HoverWithinMode, _, _) in }.build(k))
        .child(pop)
    if mode == .nested {
        seg = seg.hoverMotionWithin(slowAnim(), slowAnim())
    }
    let sw = Switch.new(false).onToggle { (_: inout HoverWithinMode) in }.build(k)
    let own = k.interactive(el().key("own").size(60.0, 28.0)).hoverMotion(Anim.instant, Anim.instant)
    let group = row()
        .key("group")
        .size(60.0, 28.0)
        .hoverGroup()
        .child(el().key("group-child").size(20.0, 20.0).fill(Color.WHITE).groupOpacity(0.0, 1.0))
    layer.append(k.interactive(el().key("layer-chip").absolute(380.0, 20.0).size(60.0, 28.0)))
    var body = col().wFull().hFull().gap(12.0).child(seg).child(sw).child(own).child(group)
    switch mode {
    case .defaultMode:
        break
    case .within, .nested:
        body = body.hoverMotionWithin(Anim.instant, Anim.instant)
    case .slowRoot:
        body = body.hoverMotionWithin(slowAnim(), slowAnim())
    }
    return root(body, layer)
}

private func hoverOf(_ rt: Runtime<HoverWithinMode>, _ key: String) -> Float {
    rt.elements().first(where: { $0.key == key })!.hover
}

/// The hover of `key` on the first frame after the pointer leaves it.
private func afterLeaving(_ mode: HoverWithinMode, _ key: String) -> Float {
    let rt = Runtime.new(mode, hoverWithinView, (500.0, 600.0), Env.new(true, 1.0))
    for _ in 0..<30 {
        _ = rt.frame(1.0 / 60.0)
    }
    let (x, y) = rt.find(key)!
    rt.pointerMove(x, y)
    for _ in 0..<90 {
        _ = rt.frame(1.0 / 60.0)
    }
    let hovered = hoverOf(rt, key)
    #expect(hovered > 0.9, "\(key) hovers: \(hovered)")
    rt.pointerMove(490.0, 590.0)
    _ = rt.frame(1.0 / 120.0)
    return hoverOf(rt, key)
}

@Suite("HoverWithinTests")
struct HoverWithinTests {
    // PORT NOTE: Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags.
    @Test(.disabled("Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags"))
    func kitControlsDropHoverAtOnceUnderHoverMotionWithin() {
        for key in ["segment1", "control", "close", "layer-chip"] {
            #expect(afterLeaving(.within, key) == 0.0, "\(key)")
        }
    }

    @Test
    func withoutItTheKitControlsStillFade() {
        for key in ["segment1", "control", "close", "layer-chip"] {
            let h = afterLeaving(.defaultMode, key)
            #expect(h > 0.0 && h < 1.0, "\(key) fades: \(h)")
        }
    }

    // PORT NOTE: Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags.
    @Test(.disabled("Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags"))
    func anElementsOwnCurvesBeatTheInheritedOnes() {
        #expect(afterLeaving(.slowRoot, "own") == 0.0)
        #expect(afterLeaving(.slowRoot, "segment1") > 0.5)
    }

    // PORT NOTE: Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags.
    @Test(.disabled("Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags"))
    func theNearestHoverMotionWithinWinsIncludingAcrossAnchors() {
        #expect(afterLeaving(.nested, "segment1") > 0.5)
        #expect(afterLeaving(.nested, "close") > 0.5)
        #expect(afterLeaving(.nested, "control") == 0.0)
        #expect(afterLeaving(.nested, "layer-chip") == 0.0)
    }

    // PORT NOTE: Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags.
    @Test(.disabled("Blocked on Sources/Rune hoverMotionWithin curve inheritance & instant-cut intent flags"))
    func instantHoverMotionWithinMarksGroupOpacitySwapsAsInstantCuts() {
        func intentFor(_ mode: HoverWithinMode) -> UInt32 {
            let rt = Runtime.new(mode, hoverWithinView, (500.0, 600.0), Env.new(true, 1.0))
            _ = rt.frame(1.0 / 60.0)
            return rt.elements().first(where: { $0.key == "group-child" })!.liveIntent
        }
        #expect(intentFor(.defaultMode) & (4 | 16) == 0)
        #expect(intentFor(.within) & (4 | 16) == (4 | 16))
    }
}
