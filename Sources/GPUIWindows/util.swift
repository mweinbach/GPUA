// Ported from: crates/gpui_windows/src/util.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import GPUI
import GPUIUtil
import ZedUtil
#if canImport(CWinSys)
import CWinSys
#endif

// MARK: - HiLoWord Protocol & Helpers

public protocol HiLoWord {
    func hiword() -> UInt16
    func loword() -> UInt16
    func signedHiword() -> Int16
    func signedLoword() -> Int16
}

extension UInt: HiLoWord {
    public func hiword() -> UInt16 {
        UInt16((self >> 16) & 0xFFFF)
    }

    public func loword() -> UInt16 {
        UInt16(self & 0xFFFF)
    }

    public func signedHiword() -> Int16 {
        Int16(bitPattern: UInt16((self >> 16) & 0xFFFF))
    }

    public func signedLoword() -> Int16 {
        Int16(bitPattern: UInt16(self & 0xFFFF))
    }
}

extension Int: HiLoWord {
    public func hiword() -> UInt16 {
        UInt(bitPattern: self).hiword()
    }

    public func loword() -> UInt16 {
        UInt(bitPattern: self).loword()
    }

    public func signedHiword() -> Int16 {
        UInt(bitPattern: self).signedHiword()
    }

    public func signedLoword() -> Int16 {
        UInt(bitPattern: self).signedLoword()
    }
}

extension UInt32: HiLoWord {
    public func hiword() -> UInt16 {
        UInt16((self >> 16) & 0xFFFF)
    }

    public func loword() -> UInt16 {
        UInt16(self & 0xFFFF)
    }

    public func signedHiword() -> Int16 {
        Int16(bitPattern: UInt16((self >> 16) & 0xFFFF))
    }

    public func signedLoword() -> Int16 {
        Int16(bitPattern: UInt16(self & 0xFFFF))
    }
}

extension Int32: HiLoWord {
    public func hiword() -> UInt16 {
        UInt32(bitPattern: self).hiword()
    }

    public func loword() -> UInt16 {
        UInt32(bitPattern: self).loword()
    }

    public func signedHiword() -> Int16 {
        UInt32(bitPattern: self).signedHiword()
    }

    public func signedLoword() -> Int16 {
        UInt32(bitPattern: self).signedLoword()
    }
}

extension UInt64: HiLoWord {
    public func hiword() -> UInt16 {
        UInt16((self >> 16) & 0xFFFF)
    }

    public func loword() -> UInt16 {
        UInt16(self & 0xFFFF)
    }

    public func signedHiword() -> Int16 {
        Int16(bitPattern: UInt16((self >> 16) & 0xFFFF))
    }

    public func signedLoword() -> Int16 {
        Int16(bitPattern: UInt16(self & 0xFFFF))
    }
}

// MARK: - WinHandle Typealias

public typealias WinHandle = UnsafeMutableRawPointer

public let GWLP_USERDATA: Int32 = -21
public let GWL_STYLE: Int32 = -16
public let GWL_EXSTYLE: Int32 = -20
public let GWLP_WNDPROC: Int32 = -4

// MARK: - WindowLong Helpers

public func getWindowLong(hwnd: WinHandle?, nindex: Int32) -> Int {
    guard let hwnd = hwnd else { return 0 }
    var val: intptr_t = 0
    _ = cwin_win32_get_window_long_ptr(hwnd, Int32(nindex), &val)
    return Int(val)
}

public func setWindowLong(hwnd: WinHandle?, nindex: Int32, dwnewlong: Int) -> Int {
    guard let hwnd = hwnd else { return 0 }
    var old: intptr_t = 0
    _ = cwin_win32_set_window_long_ptr(hwnd, Int32(nindex), intptr_t(dwnewlong), &old)
    return Int(old)
}

public func getWindowLongPointer(hwnd: WinHandle?, nindex: Int32) -> WinHandle? {
    guard let hwnd = hwnd else { return nil }
    var val: intptr_t = 0
    _ = cwin_win32_get_window_long_ptr(hwnd, Int32(nindex), &val)
    return UnsafeMutableRawPointer(bitPattern: Int(val))
}

public func setWindowLongPointer(hwnd: WinHandle?, nindex: Int32, pointer: WinHandle?) -> WinHandle? {
    guard let hwnd = hwnd else { return nil }
    var old: intptr_t = 0
    let val = intptr_t(bitPattern: pointer)
    _ = cwin_win32_set_window_long_ptr(hwnd, Int32(nindex), val, &old)
    return UnsafeMutableRawPointer(bitPattern: Int(old))
}

// MARK: - Credentials & URLs

public func windowsCredentialsTargetName(url: String) -> String {
    "zed:url=\(url)"
}

// MARK: - Cursor Loading

public func loadCursor(style: CursorStyle) -> WinHandle? {
    let styleId: UInt32
    switch style {
    case .arrow:
        styleId = 0
    case .iBeam:
        styleId = 1
    case .crosshair:
        styleId = 2
    case .pointingHand, .openHand, .closedHand:
        styleId = 3
    case .resizeLeft, .resizeRight, .resizeLeftRight:
        styleId = 5
    case .resizeUp, .resizeDown, .resizeUpDown:
        styleId = 8
    case .resizeUpLeft, .resizeDownRight, .resizeUpLeftDownRight:
        styleId = 11
    case .resizeUpRight, .resizeDownLeft, .resizeUpRightDownLeft:
        styleId = 13
    case .notAllowed:
        styleId = 15
    case .wait, .progress:
        styleId = 16
    case .none:
        return nil
    default:
        styleId = 0
    }
    return cwin_win32_load_cursor(styleId)
}

// MARK: - DWM Dark Mode Configuration

public func configureDwmDarkMode(hwnd: WinHandle?, appearance: WindowAppearance) {
    guard let hwnd = hwnd else { return }
    let isDark: Int32 = switch appearance {
    case .dark, .vibrantDark: 1
    case .light, .vibrantLight: 0
    }
    _ = cwin_win32_dwm_set_dark_mode(hwnd, isDark)
}

// MARK: - Coordinate Conversion

@inline(__always)
public func logicalPoint(x: Float, y: Float, scaleFactor: Float) -> Point<Pixels> {
    Point(
        x: px(x / scaleFactor),
        y: px(y / scaleFactor)
    )
}

// MARK: - System Appearance

public func systemAppearance() -> WindowAppearance {
    var darkMode: Int32 = 0
    if cwin_win32_get_system_appearance(&darkMode) == 0 && darkMode == 1 {
        return .dark
    }
    return .light
}

// MARK: - Wide String Helpers

public func toWideString(_ string: String) -> [UInt16] {
    Array(string.utf16) + [0]
}

public func fromWideString(_ ptr: UnsafePointer<UInt16>?, length: Int? = nil) -> String {
    guard let ptr = ptr else { return "" }
    let maxLen = length ?? Int.max
    var len = 0
    while len < maxLen && ptr[len] != 0 {
        len += 1
    }
    return String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF16.self)
}

public func fromWideBuffer(_ buffer: [UInt16]) -> String {
    var count = buffer.count
    while count > 0 && buffer[count - 1] == 0 {
        count -= 1
    }
    return String(decoding: buffer.prefix(count), as: UTF16.self)
}

#endif
