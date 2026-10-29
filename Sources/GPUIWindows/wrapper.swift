// Ported from: crates/gpui_windows/src/wrapper.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation

// PORT NOTE: WinHandle (UnsafeMutableRawPointer?) wraps Windows HCURSOR handle across threads.
public struct SafeCursor: @unchecked Sendable, Equatable {
    public let raw: WinHandle?

    public init(raw: WinHandle?) {
        self.raw = raw
    }
}

// PORT NOTE: WinHandle (UnsafeMutableRawPointer?) wraps Windows HWND handle across threads.
public struct SafeHwnd: @unchecked Sendable, Equatable {
    public let raw: WinHandle?

    public init(raw: WinHandle?) {
        self.raw = raw
    }

    public func asRaw() -> WinHandle? {
        raw
    }
}
#endif
