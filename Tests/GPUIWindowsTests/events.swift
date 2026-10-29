// Swift-only: Unit tests for Windows input events, ClickState, and mouse wheel decoding

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("WindowsEventsTests")
struct WindowsEventsTests {
    @Test
    func testDoubleClickInterval() {
        let state = ClickState()
        let origin = Point(x: DevicePixels(0), y: DevicePixels(0))

        #expect(state.update(button: .left, newPosition: origin) == 1)
        #expect(state.update(button: .right, newPosition: origin) == 1)
        #expect(state.update(button: .left, newPosition: origin) == 1)
        #expect(state.update(button: .left, newPosition: origin) == 2)

        // Simulate 700ms passage of time to exceed default double-click interval
        state.setLastClickForTesting(Date().addingTimeInterval(-0.7))
        #expect(state.update(button: .left, newPosition: origin) == 1)
    }

    @Test
    func testDoubleClickSpatialTolerance() {
        let state = ClickState()

        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(-3), y: DevicePixels(0))) == 1)
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(3))) == 2)
        #expect(state.update(button: .right, newPosition: Point(x: DevicePixels(3), y: DevicePixels(2))) == 1)
        #expect(state.update(button: .right, newPosition: Point(x: DevicePixels(10), y: DevicePixels(0))) == 1)
    }

    @Test
    func testParseImmutableKeys() {
        #expect(parse_immutable(VK_SPACE) == "space")
        #expect(parse_immutable(VK_BACK) == "backspace")
        #expect(parse_immutable(VK_RETURN) == "enter")
        #expect(parse_immutable(VK_TAB) == "tab")
        #expect(parse_immutable(VK_ESCAPE) == "escape")
        #expect(parse_immutable(VK_UP) == "up")
        #expect(parse_immutable(VK_DOWN) == "down")
        #expect(parse_immutable(VK_LEFT) == "left")
        #expect(parse_immutable(VK_RIGHT) == "right")
        #expect(parse_immutable(VK_F1) == "f1")
        #expect(parse_immutable(VK_F12) == "f12")
        #expect(parse_immutable(0x41) == nil) // 'A' is not immutable
    }

    @Test
    func testMouseWheelDecoding() {
        // Vertical wheel scroll down (positive delta = 120)
        let wparam: UInt = UInt(120 << 16)
        let lparam: Int = (200 << 16) | 100 // x = 100, y = 200
        let event = decode_mouse_wheel(
            wparam: wparam,
            lparam: lparam,
            scaleFactor: 2.0,
            isHorizontal: false,
            scrollAmount: 3.0
        )

        #expect(event.position.x.value == 50.0) // 100 / 2.0
        #expect(event.position.y.value == 100.0) // 200 / 2.0
        if case .lines(let pt) = event.delta {
            #expect(pt.y == 3.0)
            #expect(pt.x == 0.0)
        } else {
            Issue.record("Expected .lines delta")
        }
    }

    @Test
    func testNegativeCoordinatesAndWheelDelta() {
        let wparam: UInt = UInt(UInt16(bitPattern: -120)) << 16
        let lparam: Int = (Int(Int16(bitPattern: -20)) << 16) | Int(UInt16(bitPattern: -10))
        let event = decode_mouse_wheel(
            wparam: wparam,
            lparam: lparam,
            scaleFactor: 1.0,
            isHorizontal: false,
            scrollAmount: 3.0
        )

        #expect(event.position.x.value == -10.0)
        #expect(event.position.y.value == -20.0)
        if case .lines(let pt) = event.delta {
            #expect(pt.y == -3.0)
            #expect(pt.x == 0.0)
        } else {
            Issue.record("Expected .lines delta")
        }

        let moveEvent = decode_mouse_move(lparam: lparam, scaleFactor: 1.0, pressedButton: nil)
        #expect(moveEvent.position.x.value == -10.0)
        #expect(moveEvent.position.y.value == -20.0)
    }
}

#endif
