// Ported from: crates/gpui_linux/src/linux/wayland/layer_shell.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import GPUI

public enum ZwlrLayerShellV1Layer: UInt32, Sendable {
    case background = 0
    case bottom = 1
    case top = 2
    case overlay = 3
}

public struct ZwlrLayerSurfaceV1Anchor: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    public static let top = ZwlrLayerSurfaceV1Anchor(rawValue: 1)
    public static let bottom = ZwlrLayerSurfaceV1Anchor(rawValue: 2)
    public static let left = ZwlrLayerSurfaceV1Anchor(rawValue: 4)
    public static let right = ZwlrLayerSurfaceV1Anchor(rawValue: 8)
}

public enum ZwlrLayerSurfaceV1KeyboardInteractivity: UInt32, Sendable {
    case none = 0
    case exclusive = 1
    case onDemand = 2
}

public func waylandLayer(_ layer: Layer) -> ZwlrLayerShellV1Layer {
    switch layer {
    case .background:
        return .background
    case .bottom:
        return .bottom
    case .top:
        return .top
    case .overlay:
        return .overlay
    }
}

public func waylandAnchor(_ anchor: Anchor) -> ZwlrLayerSurfaceV1Anchor {
    ZwlrLayerSurfaceV1Anchor(rawValue: anchor.rawValue)
}

public func waylandKeyboardInteractivity(
    _ value: KeyboardInteractivity
) -> ZwlrLayerSurfaceV1KeyboardInteractivity {
    switch value {
    case .none:
        return .none
    case .exclusive:
        return .exclusive
    case .onDemand:
        return .onDemand
    }
}
#endif
