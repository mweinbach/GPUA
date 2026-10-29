// Ported from: crates/gpui_windows/src/system_settings.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
#if canImport(CWinSys)
import CWinSys
#endif

public let SPI_GETWHEELSCROLLLINES: UInt32 = 0x0068
public let SPI_GETWHEELSCROLLCHARS: UInt32 = 0x006C

// PORT NOTE: MouseWheelSettings encapsulates mouse wheel scroll lines and characters settings queried via Win32 SystemParametersInfo.
public final class MouseWheelSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var _wheelScrollChars: UInt32 = 3
    private var _wheelScrollLines: UInt32 = 3

    public init() {
        update()
    }

    public var wheelScrollChars: UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return _wheelScrollChars
    }

    public var wheelScrollLines: UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return _wheelScrollLines
    }

    public func update() {
        var lines: UInt32 = 3
        var chars: UInt32 = 3
        if cwin_win32_get_wheel_scroll_lines(&lines) == 0 {
            lock.lock()
            _wheelScrollLines = lines
            lock.unlock()
        }
        if cwin_win32_get_wheel_scroll_chars(&chars) == 0 {
            lock.lock()
            _wheelScrollChars = chars
            lock.unlock()
        }
    }
}

// PORT NOTE: WindowsSystemSettings synchronizes system parameter settings pulled from Win32 SPI messages.
public final class WindowsSystemSettings: @unchecked Sendable {
    public let mouseWheelSettings: MouseWheelSettings

    public init() {
        self.mouseWheelSettings = MouseWheelSettings()
    }

    public func update(wparam: UInt) {
        let action = UInt32(wparam & 0xFFFF)
        if action == SPI_GETWHEELSCROLLLINES || action == SPI_GETWHEELSCROLLCHARS {
            mouseWheelSettings.update()
        }
    }
}

#endif
