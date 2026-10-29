// Ported from: crates/gpui_windows/src/events.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - Event Loop Constants

public let SIZE_MOVE_LOOP_TIMER_ID: Int = 1
public let WHEEL_DELTA: Float = 120.0
public let XBUTTON1: UInt16 = 0x0001
public let XBUTTON2: UInt16 = 0x0002

// MARK: - ClickState

// PORT NOTE: ClickState tracks spatial tolerance and interval for double/triple clicks on Win32.
public final class ClickState: @unchecked Sendable {
    private var button: MouseButton
    private var lastClick: Date
    private var lastPosition: Point<DevicePixels>
    private var doubleClickSpatialToleranceWidth: Int32
    private var doubleClickSpatialToleranceHeight: Int32
    private var doubleClickInterval: TimeInterval
    public private(set) var currentCount: Int

    public init() {
        var w: Int32 = 4
        var h: Int32 = 4
        cwin_win32_get_double_click_tolerance(&w, &h)
        self.doubleClickSpatialToleranceWidth = w
        self.doubleClickSpatialToleranceHeight = h
        let ms = cwin_win32_get_double_click_time()
        self.doubleClickInterval = Double(ms > 0 ? ms : 500) / 1000.0

        self.button = .left
        self.lastClick = Date()
        self.lastPosition = .zero
        self.currentCount = 0
    }

    /// Update state with a new click and return the click count (1 = single, 2 = double, 3+ = multi).
    @discardableResult
    public func update(button: MouseButton, newPosition: Point<DevicePixels>) -> Int {
        if self.button == button && isDoubleClick(newPosition: newPosition) {
            self.currentCount += 1
        } else {
            self.currentCount = 1
        }
        self.lastClick = Date()
        self.lastPosition = newPosition
        self.button = button
        return self.currentCount
    }

    public func systemUpdate(wparam: UInt) {
        switch wparam {
        case 29, 30: // SPI_SETDOUBLECLKWIDTH, SPI_SETDOUBLECLKHEIGHT
            var w: Int32 = 4
            var h: Int32 = 4
            cwin_win32_get_double_click_tolerance(&w, &h)
            self.doubleClickSpatialToleranceWidth = w
            self.doubleClickSpatialToleranceHeight = h
        case 32: // SPI_SETDOUBLECLICKTIME
            let ms = cwin_win32_get_double_click_time()
            self.doubleClickInterval = Double(ms > 0 ? ms : 500) / 1000.0
        default:
            break
        }
    }

    public func setLastClickForTesting(_ date: Date) {
        self.lastClick = date
    }

    private func isDoubleClick(newPosition: Point<DevicePixels>) -> Bool {
        let diffX = abs(self.lastPosition.x.value - newPosition.x.value)
        let diffY = abs(self.lastPosition.y.value - newPosition.y.value)
        let elapsed = Date().timeIntervalSince(self.lastClick)
        return elapsed < self.doubleClickInterval
            && diffX <= self.doubleClickSpatialToleranceWidth
            && diffY <= self.doubleClickSpatialToleranceHeight
    }
}

// MARK: - Modifiers and Capslock Tracking

@inline(__always)
public func is_virtual_key_pressed(_ vkey: UInt16) -> Bool {
    cwin_win32_get_key_state(Int32(vkey)) < 0
}

@inline(__always)
public func current_modifiers() -> Modifiers {
    Modifiers(
        control: is_virtual_key_pressed(VK_CONTROL),
        alt: is_virtual_key_pressed(VK_MENU),
        shift: is_virtual_key_pressed(VK_SHIFT),
        platform: is_virtual_key_pressed(VK_LWIN) || is_virtual_key_pressed(VK_RWIN),
        function: false
    )
}

@inline(__always)
public func current_capslock() -> Capslock {
    let on = (cwin_win32_get_key_state(Int32(VK_CAPITAL)) & 1) != 0
    return Capslock(on: on)
}

// MARK: - Key Event Translation

public func parse_immutable(_ vkey: UInt16) -> String? {
    switch vkey {
    case VK_SPACE: return "space"
    case VK_BACK: return "backspace"
    case VK_RETURN: return "enter"
    case VK_TAB: return "tab"
    case VK_UP: return "up"
    case VK_DOWN: return "down"
    case VK_RIGHT: return "right"
    case VK_LEFT: return "left"
    case VK_HOME: return "home"
    case VK_END: return "end"
    case VK_PRIOR: return "pageup"
    case VK_NEXT: return "pagedown"
    case VK_BROWSER_BACK: return "back"
    case VK_BROWSER_FORWARD: return "forward"
    case VK_ESCAPE: return "escape"
    case VK_INSERT: return "insert"
    case VK_DELETE: return "delete"
    case VK_APPS: return "menu"
    case VK_F1: return "f1"
    case VK_F2: return "f2"
    case VK_F3: return "f3"
    case VK_F4: return "f4"
    case VK_F5: return "f5"
    case VK_F6: return "f6"
    case VK_F7: return "f7"
    case VK_F8: return "f8"
    case VK_F9: return "f9"
    case VK_F10: return "f10"
    case VK_F11: return "f11"
    case VK_F12: return "f12"
    case VK_F13: return "f13"
    case VK_F14: return "f14"
    case VK_F15: return "f15"
    case VK_F16: return "f16"
    case VK_F17: return "f17"
    case VK_F18: return "f18"
    case VK_F19: return "f19"
    case VK_F20: return "f20"
    case VK_F21: return "f21"
    case VK_F22: return "f22"
    case VK_F23: return "f23"
    case VK_F24: return "f24"
    default: return nil
    }
}

public func process_key(_ vkey: UInt16, scanCode: UInt16) -> (keyChar: String?, preferCharacterInput: Bool) {
    var keyboardState = [UInt8](repeating: 0, count: 256)
    if cwin_win32_get_keyboard_state(&keyboardState) != 0 {
        return (nil, false)
    }

    var bufferC = [UInt16](repeating: 0, count: 8)
    let resultC = cwin_win32_to_unicode(UInt32(vkey), UInt32(scanCode), keyboardState, &bufferC, 8, 0x4)
    if resultC == 0 {
        return (nil, false)
    }

    let len = Int(abs(resultC))
    let text = fromWideString(bufferC, length: len)
    let keyChar: String?
    if let scalar = text.unicodeScalars.first, !((scalar.value <= 0x1F) || (scalar.value >= 0x7F && scalar.value <= 0x9F)) {
        keyChar = text
    } else {
        keyChar = nil
    }

    if resultC < 0 {
        return (keyChar, true)
    }
    if keyChar == nil {
        return (nil, false)
    }

    let ctrlDown = (keyboardState[Int(VK_CONTROL)] & 0x80) != 0
    let altDown = (keyboardState[Int(VK_MENU)] & 0x80) != 0
    let winDown = (keyboardState[Int(VK_LWIN)] & 0x80) != 0 || (keyboardState[Int(VK_RWIN)] & 0x80) != 0

    let hasModifiers = ctrlDown || altDown || winDown
    if !hasModifiers {
        return (keyChar, false)
    }

    var stateNoModifiers = keyboardState
    stateNoModifiers[Int(VK_CONTROL)] = 0
    stateNoModifiers[Int(VK_LCONTROL)] = 0
    stateNoModifiers[Int(VK_RCONTROL)] = 0
    stateNoModifiers[Int(VK_MENU)] = 0
    stateNoModifiers[Int(VK_LMENU)] = 0
    stateNoModifiers[Int(VK_RMENU)] = 0
    stateNoModifiers[Int(VK_LWIN)] = 0
    stateNoModifiers[Int(VK_RWIN)] = 0

    var bufferCNoModifiers = [UInt16](repeating: 0, count: 8)
    let resultCNoModifiers = cwin_win32_to_unicode(UInt32(vkey), UInt32(scanCode), stateNoModifiers, &bufferCNoModifiers, 8, 0x4)
    let diff = (resultC != resultCNoModifiers) || (bufferC != bufferCNoModifiers)
    return (keyChar, diff)
}

public func parse_normal_key(
    _ vkey: UInt16,
    lparam: Int,
    modifiers: inout Modifiers
) -> (keystroke: Keystroke, preferCharacterInput: Bool)? {
    let scanCode = UInt16((lparam >> 16) & 0xFFFF)
    let (keyChar, preferCharacterInput) = process_key(vkey, scanCode: scanCode)

    guard let key = parse_immutable(vkey) ?? ({
        let code = UInt32(scanCode & 0xFF)
        return get_keystroke_key(vkey: vkey, scanCode: code, modifiers: &modifiers)
    })() else {
        return nil
    }

    let keystroke = Keystroke(
        modifiers: modifiers,
        key: key,
        keyChar: keyChar,
        nativeKeyCode: vkey
    )
    return (keystroke, preferCharacterInput)
}

public func handle_key_event(
    wparam: UInt,
    lparam: Int,
    lastReportedModifiers: inout Modifiers?,
    lastReportedCapslock: inout Capslock?,
    buildInput: (Keystroke, Bool) -> PlatformInput
) -> PlatformInput? {
    let virtualKey = UInt16(wparam & 0xFFFF)
    var modifiers = current_modifiers()

    switch virtualKey {
    case VK_SHIFT, VK_CONTROL, VK_MENU, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN:
        if let prev = lastReportedModifiers, prev == modifiers {
            return nil
        }
        lastReportedModifiers = modifiers
        return PlatformInput.modifiersChanged(ModifiersChangedEvent(
            modifiers: modifiers,
            capslock: current_capslock()
        ))
    case 0xE7: // VK_PACKET
        return nil
    case VK_CAPITAL:
        let capslock = current_capslock()
        if let prev = lastReportedCapslock, prev == capslock {
            return nil
        }
        lastReportedCapslock = capslock
        return PlatformInput.modifiersChanged(ModifiersChangedEvent(
            modifiers: modifiers,
            capslock: capslock
        ))
    default:
        guard let (keystroke, preferChar) = parse_normal_key(virtualKey, lparam: lparam, modifiers: &modifiers) else {
            return nil
        }
        return buildInput(keystroke, preferChar)
    }
}

// MARK: - Geometry & Mouse Decoding

@inline(__always)
public func logical_point(x: Float, y: Float, scaleFactor: Float) -> Point<Pixels> {
    let sf = scaleFactor > 0 ? scaleFactor : 1.0
    return Point(x: Pixels(x / sf), y: Pixels(y / sf))
}

public func decode_mouse_down(
    button: MouseButton,
    lparam: Int,
    scaleFactor: Float,
    clickState: ClickState
) -> MouseDownEvent {
    let x = Int16(truncatingIfNeeded: lparam)
    let y = Int16(truncatingIfNeeded: lparam >> 16)
    let physicalPoint = Point(x: DevicePixels(Int32(x)), y: DevicePixels(Int32(y)))
    let clickCount = clickState.update(button: button, newPosition: physicalPoint)
    return MouseDownEvent(
        button: button,
        position: logical_point(x: Float(x), y: Float(y), scaleFactor: scaleFactor),
        modifiers: current_modifiers(),
        clickCount: clickCount,
        firstMouse: false
    )
}

public func decode_mouse_up(
    button: MouseButton,
    lparam: Int,
    scaleFactor: Float,
    clickCount: Int
) -> MouseUpEvent {
    let x = Float(Int16(truncatingIfNeeded: lparam))
    let y = Float(Int16(truncatingIfNeeded: lparam >> 16))
    return MouseUpEvent(
        button: button,
        position: logical_point(x: x, y: y, scaleFactor: scaleFactor),
        modifiers: current_modifiers(),
        clickCount: clickCount
    )
}

public func decode_mouse_move(
    lparam: Int,
    scaleFactor: Float,
    pressedButton: MouseButton?
) -> MouseMoveEvent {
    let x = Float(Int16(truncatingIfNeeded: lparam))
    let y = Float(Int16(truncatingIfNeeded: lparam >> 16))
    return MouseMoveEvent(
        position: logical_point(x: x, y: y, scaleFactor: scaleFactor),
        pressedButton: pressedButton,
        modifiers: current_modifiers()
    )
}

public func decode_mouse_wheel(
    wparam: UInt,
    lparam: Int,
    scaleFactor: Float,
    isHorizontal: Bool,
    scrollAmount: Float
) -> ScrollWheelEvent {
    let rawDelta = Float(Int16(truncatingIfNeeded: wparam >> 16))
    let x = Float(Int16(truncatingIfNeeded: lparam))
    let y = Float(Int16(truncatingIfNeeded: lparam >> 16))
    let position = logical_point(x: x, y: y, scaleFactor: scaleFactor)
    let modifiers = current_modifiers()

    if isHorizontal {
        let wheelDistance = (-rawDelta / WHEEL_DELTA) * scrollAmount
        return ScrollWheelEvent(
            position: position,
            delta: .lines(Point(x: wheelDistance, y: 0.0)),
            modifiers: modifiers,
            touchPhase: .moved
        )
    } else {
        let wheelDistance = (rawDelta / WHEEL_DELTA) * scrollAmount
        if modifiers.shift {
            return ScrollWheelEvent(
                position: position,
                delta: .lines(Point(x: wheelDistance, y: 0.0)),
                modifiers: modifiers,
                touchPhase: .moved
            )
        } else {
            return ScrollWheelEvent(
                position: position,
                delta: .lines(Point(x: 0.0, y: wheelDistance)),
                modifiers: modifiers,
                touchPhase: .moved
            )
        }
    }
}

// MARK: - Window Frame and System Metrics

@inline(__always)
public func get_frame_thicknessx(dpi: UInt32) -> Int32 {
    cwin_win32_get_frame_thickness_x(dpi)
}

@inline(__always)
public func get_frame_thicknessy(dpi: UInt32) -> Int32 {
    cwin_win32_get_frame_thickness_y(dpi)
}

@inline(__always)
public func notify_frame_changed(handle: WinHandle) {
    cwin_win32_notify_frame_changed(handle)
}

// MARK: - IME Positioning

// PORT NOTE: update_ime_position positions Win32 IME composition and candidate windows via ImmSetCompositionWindow and ImmSetCandidateWindow.
@inline(__always)
public func update_ime_position(handle: WinHandle, x: Int32, y: Int32, width: Int32 = 0, height: Int32 = 0) {
    _ = cwin_win32_set_ime_position(handle, x, y, width, height)
}

#endif
