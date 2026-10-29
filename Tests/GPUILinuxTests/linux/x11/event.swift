// Tests ported from: crates/gpui_linux/src/linux/x11/event.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Testing
@testable import GPUILinux

@Suite("X11EventTests")
struct X11EventTests {
    @Test
    func testGetValuatorAxisIndex() {
        #expect(getValuatorAxisIndex([0b11], 0) == 0)
        #expect(getValuatorAxisIndex([0b11], 1) == 1)
        #expect(getValuatorAxisIndex([0b11], 2) == nil)

        #expect(getValuatorAxisIndex([0b100], 0) == nil)
        #expect(getValuatorAxisIndex([0b100], 1) == nil)
        #expect(getValuatorAxisIndex([0b100], 2) == 0)
        #expect(getValuatorAxisIndex([0b100], 3) == nil)

        #expect(getValuatorAxisIndex([0b1010, 0], 0) == nil)
        #expect(getValuatorAxisIndex([0b1010, 0], 1) == 0)
        #expect(getValuatorAxisIndex([0b1010, 0], 2) == nil)
        #expect(getValuatorAxisIndex([0b1010, 0], 3) == 1)

        #expect(getValuatorAxisIndex([0b1010, 0b1], 0) == nil)
        #expect(getValuatorAxisIndex([0b1010, 0b1], 1) == 0)
        #expect(getValuatorAxisIndex([0b1010, 0b1], 2) == nil)
        #expect(getValuatorAxisIndex([0b1010, 0b1], 3) == 1)
        #expect(getValuatorAxisIndex([0b1010, 0b1], 32) == 2)
        #expect(getValuatorAxisIndex([0b1010, 0b1], 33) == nil)

        #expect(getValuatorAxisIndex([0b1010, 0b101], 34) == 3)
    }

    @Test
    func testButtonOrScrollFromEventDetail() {
        #expect(buttonOrScrollFromEventDetail(1) == .button(.left))
        #expect(buttonOrScrollFromEventDetail(2) == .button(.middle))
        #expect(buttonOrScrollFromEventDetail(3) == .button(.right))
        #expect(buttonOrScrollFromEventDetail(4) == .scroll(.up))
        #expect(buttonOrScrollFromEventDetail(5) == .scroll(.down))
        #expect(buttonOrScrollFromEventDetail(6) == .scroll(.left))
        #expect(buttonOrScrollFromEventDetail(7) == .scroll(.right))
        #expect(buttonOrScrollFromEventDetail(8) == .button(.navigate(.back)))
        #expect(buttonOrScrollFromEventDetail(9) == .button(.navigate(.forward)))
        #expect(buttonOrScrollFromEventDetail(10) == nil)
    }

    @Test
    func testModifiersFromState() {
        let mods = modifiersFromState(x11ControlMask | x11ShiftMask)
        #expect(mods.control)
        #expect(mods.shift)
        #expect(!mods.alt)
        #expect(!mods.platform)
    }

    @Test
    func testPressedButtonFromMask() {
        #expect(pressedButtonFromMask(2) == .left)
        #expect(pressedButtonFromMask(4) == .middle)
        #expect(pressedButtonFromMask(8) == .right)
        #expect(pressedButtonFromMask(16) == nil)
    }
}
#endif
