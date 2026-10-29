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

// MARK: - WindowLong Helpers

public func getWindowLong(hwnd: OpaquePointer?, nindex: Int32) -> Int {
    guard let hwnd = hwnd else { return 0 }
    var val: intptr_t = 0
    _ = cwin_win32_get_window_long_ptr(hwnd, Int32(nindex), &val)
    return Int(val)
}

public func setWindowLong(hwnd: OpaquePointer?, nindex: Int32, dwnewlong: Int) -> Int {
    guard let hwnd = hwnd else { return 0 }
    var old: intptr_t = 0
    _ = cwin_win32_set_window_long_ptr(hwnd, Int32(nindex), intptr_t(dwnewlong), &old)
    return Int(old)
}

// MARK: - Credentials & URLs

public func windowsCredentialsTargetName(url: String) -> String {
    "zed:url=\(url)"
}

// MARK: - Cursor Loading

public func loadCursor(style: CursorStyle) -> OpaquePointer? {
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

public func configureDwmDarkMode(hwnd: OpaquePointer?, appearance: WindowAppearance) {
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
    if let len = length {
        return String(decoding: UnsafeBufferPointer(start: ptr, count: len), as: UTF16.self)
    }
    var len = 0
    while ptr[len] != 0 {
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
