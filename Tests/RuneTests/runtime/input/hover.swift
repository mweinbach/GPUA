// Tests ported from: crates/rune/src/runtime/input/hover.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("InputHoverUnitTests")
struct InputHoverUnitTests {
    @Test("Pointer hover enters, updates cursor, and leaves on pointerLeave")
    func pointerHoverEntersAndLeaves() {
        let rt: Runtime<[String]> = Runtime.new([String](), { (_: [String], _: Cx<[String]>) in
            col().wFull().hFull().child(
                rtWithHover(
                    el().key("btn").size(80.0, 40.0).bg(oklch(0.5, 0.1, 200.0))
                        .onPress { (_: inout [String], _) in },
                    { (log: inout [String], hovered: Bool, _: inout Tx) in
                        log.append(hovered ? "enter" : "leave")
                    }
                )
            )
        }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        rt.pointerMove(20.0, 20.0)
        #expect(rt.state == ["enter"])
        #expect(rt.currentCursor == .pointer)

        rt.pointerLeave()
        _ = rt.frame(0.0)
        #expect(rt.state == ["enter", "leave"])
        #expect(rt.currentCursor == .default)
    }
}
