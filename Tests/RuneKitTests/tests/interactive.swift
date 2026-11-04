// Tests ported from: crates/rune-kit/tests/interactive.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Kit.interactive` gives an app's own element the kit's hover and press look, and
//! `Kit.elevate` its shadows.

import Testing
import Rune
@testable import RuneKit

private func interactiveView(_: UInt32, _ cx: Cx<UInt32>) -> El {
    let k = Kit.neutral(cx.systemDark())
    let row = k.interactive(el().key("row").size(100.0, 28.0).onPress { (n: inout UInt32) in n += 1 })
    let card = k.elevate(el().key("card").size(100.0, 28.0), k.elevation.floating)
    return col().wFull().hFull().child(row).child(card)
}

@Suite("InteractiveTests")
struct InteractiveTests {
    @Test
    func anInteractiveElementShowsHoverAndPress() {
        let rt = Runtime.new(UInt32(0), interactiveView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        func info(_ rt: Runtime<UInt32>) -> ElementInfo {
            rt.elements().first(where: { $0.key == "row" })!
        }
        #expect((info(rt).hover, info(rt).press) == (0.0, 0.0))
        rt.pointerMove(50.0, 14.0)
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(info(rt).hover > 0.9, "hover: \(info(rt).hover)")
        _ = rt.pointerDown(50.0, 14.0)
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(info(rt).press > 0.9, "press: \(info(rt).press)")
        rt.pointerUp(50.0, 14.0)
        _ = rt.frame(0.0)
        #expect(rt.state == 1)
    }

    @Test
    func elevatePaintsTheLayersAsShadows() {
        let k = Kit.neutral(true)
        #expect(!k.elevation.floating.isEmpty)
        let rt = Runtime.new(UInt32(0), interactiveView, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let plain = Runtime.new(
            UInt32(0),
            { (_: UInt32, _: Cx<UInt32>) in
                col().child(el().size(100.0, 28.0)).child(el().size(100.0, 28.0))
            },
            (200.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = plain.frame(0.0)
        #expect(rt.instances.count >= plain.instances.count + k.elevation.floating.count, "shadow layers draw")
    }
}
