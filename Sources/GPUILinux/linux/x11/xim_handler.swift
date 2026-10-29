// Ported from: crates/gpui_linux/src/linux/x11/xim_handler.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation

public enum XimCallbackEvent: Sendable {
    case ximXEvent(any Sendable)
    case ximPreeditEvent(UInt32, String)
    case ximCommitEvent(UInt32, String)
}

public struct XimHandler: Sendable {
    public var imId: UInt16
    public var icId: UInt16
    public var connected: Bool
    public var window: UInt32
    public var lastCallbackEvent: XimCallbackEvent?

    public init(
        imId: UInt16 = 0,
        icId: UInt16 = 0,
        connected: Bool = false,
        window: UInt32 = 0,
        lastCallbackEvent: XimCallbackEvent? = nil
    ) {
        self.imId = imId
        self.icId = icId
        self.connected = connected
        self.window = window
        self.lastCallbackEvent = lastCallbackEvent
    }

    public static func new() -> XimHandler {
        XimHandler()
    }
}
#endif
