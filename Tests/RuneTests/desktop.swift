// Tests ported from: crates/rune/src/desktop.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("DesktopCoordinatorTests")
struct DesktopCoordinatorTests {
    @Test("Desk routes clicks to topmost window and switches key focus")
    func deskRoutesClicksToTopmostWindowAndSwitchesKeyFocus() throws {
        var optsA = WindowOptions()
        optsA.position = (50, 50)
        var optsB = WindowOptions()
        optsB.position = (150, 50)

        let wA = WindowSpec.new(
            "alpha",
            AppSpec<Int>("Alpha", (200.0, 200.0), { 0 }, { _, _ in
                el().size(200.0, 200.0).bg(Color(1.0, 0.0, 0.0, 1.0)).onPress { (n: inout Int, _: inout Tx) in n += 1 }
            })
        ).options(optsA)

        let wB = WindowSpec.new(
            "beta",
            AppSpec<Int>("Beta", (200.0, 200.0), { 0 }, { _, _ in
                el().size(200.0, 200.0).bg(Color(0.0, 0.0, 1.0, 1.0)).onPress { (n: inout Int, _: inout Tx) in n += 10 }
            })
        ).options(optsB)

        let desk = try runDesktop(windows: [wA.boxed(), wB.boxed()], displaysSpec: "800x600")
        #expect(desk.keyWindowId() == "beta")

        // Overlap at (200, 100) hits topmost window `beta`
        desk.click(200, 100)
        let memberA = desk.members[0] as! DesktopWindow<Int>
        let memberB = desk.members[1] as! DesktopWindow<Int>
        #expect(memberB.host.rt.state == 10)
        #expect(memberA.host.rt.state == 0)

        // Clicking uncovered part of `alpha` at (80, 100) focuses and raises `alpha`
        desk.click(80, 100)
        #expect(desk.keyWindowId() == "alpha")
        #expect(memberA.host.rt.state == 1)

        // Now overlap at (200, 100) hits `alpha` because it was raised!
        desk.click(200, 100)
        #expect(memberA.host.rt.state == 2)

        let (sw, sh, rgba) = desk.snapshotRgba()
        #expect(sw == 800 && sh == 600)
        #expect(rgba.count == 800 * 600 * 4)
    }
}
