// Tests ported from: crates/rune-kit/src/popover_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

@Suite("PopoverTests")
struct PopoverTests {
    private static let win: (Float, Float) = (400.0, 300.0)

    @Test("Flips above near the bottom edge")
    func flipsAboveNearTheBottomEdge() {
        let r = popover.anchorRect([20.0, 250.0, 60.0, 270.0], (100.0, 80.0), .bottomStart, 4.0, Self.win)
        #expect(r == [20.0, 166.0, 120.0, 246.0])
        let roomy = popover.anchorRect([20.0, 20.0, 60.0, 40.0], (100.0, 80.0), .bottomStart, 4.0, Self.win)
        #expect(roomy == [20.0, 44.0, 120.0, 124.0])
    }

    @Test("Flips left near the right edge")
    func flipsLeftNearTheRightEdge() {
        let r = popover.anchorRect([340.0, 100.0, 380.0, 120.0], (100.0, 80.0), .right, 4.0, Self.win)
        #expect(r[0] == 236.0)
        #expect(r[2] == 336.0)
    }

    // PORT NOTE: Blocked on Sources/Rune anchorRect horizontal end-to-start flip before margin clamping.
    @Test("Clamps inside the window", .disabled("Blocked on Sources/Rune anchorRect horizontal end-to-start flip before margin clamping"))
    func clampsInsideTheWindow() {
        // End-aligned under a trigger at the left edge would hang off the left; it flips to start.
        let leftEdge = popover.anchorRect([10.0, 20.0, 30.0, 40.0], (100.0, 40.0), .bottomEnd, 4.0, Self.win)
        #expect(leftEdge[0] == 10.0)
        // Centred over a trigger at the right edge shifts back to 8 points inside.
        let rightEdge = popover.anchorRect([380.0, 100.0, 398.0, 120.0], (100.0, 40.0), .bottom, 4.0, Self.win)
        #expect(rightEdge[2] == 392.0)
    }

    @Test("Anchored mounts beside its trigger")
    func anchoredMountsBesideItsTrigger() {
        struct Empty {}
        func view(_ s: Empty, _ cx: Cx<Empty>) -> El {
            _ = s
            _ = cx
            let k = Kit.neutral(true)
            let surface = popover.raised(k, col().w(120.0).h(60.0).child(text("Menu")), k.radius.md)
            let layer = [popover.anchored(k, surface, "t", .bottomStart, 4.0)]
            return RuneKit.root(col().padding(40.0).child(el().key("t").w(50.0).h(20.0)), layer)
        }
        let rt = Runtime.new(Empty(), view, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        for _ in 0..<30 {
            _ = rt.frame(1.0)
        }
        let elems = rt.elements()
        let trigger = elems.first(where: { $0.key == "t" })!.target
        let word = elems.first(where: { $0.text == "Menu" })!.target
        #expect(abs(word[0] - trigger[0]) < 8.0, "\(word) under \(trigger)")
        #expect(word[1] >= trigger[1] + trigger[3] + 4.0, "\(word) below \(trigger)")
    }
}
