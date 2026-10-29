// Ported from: crates/gpui_linux/src/linux/keyboard.rs
// Upstream commit: 650aab59d54f
// Port status: in-progress

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import GPUI

// PORT NOTE: LinuxKeyboardLayout wraps immutable Sendable SharedString.
public struct LinuxKeyboardLayout: PlatformKeyboardLayout, @unchecked Sendable {
    private let _name: SharedString

    public var id: String {
        _name.value
    }

    public var name: String {
        _name.value
    }

    public init(name: SharedString) {
        self._name = name
    }

    public static func new(_ name: SharedString) -> LinuxKeyboardLayout {
        LinuxKeyboardLayout(name: name)
    }
}
#endif
