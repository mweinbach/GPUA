// Ported from: crates/gpui_web/src/keyboard.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(WASI)
import CWebSys
#endif

/// Keyboard layout implementation for browser environments.
public struct WebKeyboardLayout: PlatformKeyboardLayout, Sendable {
    private let layoutId: String
    private let layoutName: String

    public init() {
        #if os(WASI)
        var buffer = [UInt8](repeating: 0, count: 64)
        let length = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return cwebsys_keyboard_layout_id(base, ptr.count)
        }
        if length > 0, length <= buffer.count {
            let detected = String(decoding: buffer.prefix(length), as: UTF8.self)
            self.layoutId = detected
            self.layoutName = detected.uppercased()
        } else {
            self.layoutId = "us"
            self.layoutName = "US"
        }
        #else
        self.layoutId = "us"
        self.layoutName = "US"
        #endif
    }

    public init(id: String, name: String) {
        self.layoutId = id
        self.layoutName = name
    }

    public static func new() -> WebKeyboardLayout {
        WebKeyboardLayout()
    }

    public var id: String {
        layoutId
    }

    public var name: String {
        layoutName
    }
}
