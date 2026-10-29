// Ported from: crates/gpui/src/platform/layer_shell.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// The Wayland layer a layer-shell surface should occupy.
public enum Layer: Sendable, Equatable, Hashable, CaseIterable {
    /// Render behind normal windows, typically for wallpapers.
    case background
    /// Render below normal windows but above the background layer.
    case bottom
    /// Render above normal windows.
    case top
    /// Render above all other layers.
    case overlay

    public static let `default`: Layer = .top
}

/// Edge anchors for a Wayland layer-shell surface.
public struct Anchor: OptionSet, Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Anchor to the top edge of the output.
    public static let top = Anchor(rawValue: 1 << 0)
    /// Anchor to the bottom edge of the output.
    public static let bottom = Anchor(rawValue: 1 << 1)
    /// Anchor to the left edge of the output.
    public static let left = Anchor(rawValue: 1 << 2)
    /// Anchor to the right edge of the output.
    public static let right = Anchor(rawValue: 1 << 3)
}

/// Keyboard focus behavior for a Wayland layer-shell surface.
public enum KeyboardInteractivity: Sendable, Equatable, Hashable, CaseIterable {
    /// Never receive keyboard focus.
    case none
    /// Exclusively receive keyboard focus when shown.
    case exclusive
    /// Receive keyboard focus only when demanded by the compositor.
    case onDemand

    public static let `default`: KeyboardInteractivity = .none
}

/// Options for creating a Wayland layer-shell window.
public struct LayerShellOptions: Sendable, Equatable {
    /// The namespace reported to the compositor for this surface.
    public var namespace: String
    /// Which compositor layer should host the surface.
    public var layer: Layer
    /// Which output edges the surface should stay attached to.
    public var anchor: Anchor
    /// Optional top, right, bottom, left margins.
    public var margin: (Pixels, Pixels, Pixels, Pixels)?
    /// Optional compositor-reserved exclusive zone.
    public var exclusiveZone: Pixels?
    /// Optional edge used for exclusive zone calculations.
    public var exclusiveEdge: Anchor?
    /// How keyboard focus should be handled.
    public var keyboardInteractivity: KeyboardInteractivity

    public init(
        namespace: String = "",
        layer: Layer = .top,
        anchor: Anchor = [],
        margin: (Pixels, Pixels, Pixels, Pixels)? = nil,
        exclusiveZone: Pixels? = nil,
        exclusiveEdge: Anchor? = nil,
        keyboardInteractivity: KeyboardInteractivity = .none
    ) {
        self.namespace = namespace
        self.layer = layer
        self.anchor = anchor
        self.margin = margin
        self.exclusiveZone = exclusiveZone
        self.exclusiveEdge = exclusiveEdge
        self.keyboardInteractivity = keyboardInteractivity
    }

    public static func == (lhs: LayerShellOptions, rhs: LayerShellOptions) -> Bool {
        guard lhs.namespace == rhs.namespace,
              lhs.layer == rhs.layer,
              lhs.anchor == rhs.anchor,
              lhs.exclusiveZone == rhs.exclusiveZone,
              lhs.exclusiveEdge == rhs.exclusiveEdge,
              lhs.keyboardInteractivity == rhs.keyboardInteractivity else {
            return false
        }
        switch (lhs.margin, rhs.margin) {
        case (nil, nil):
            return true
        case (.some(let m1), .some(let m2)):
            return m1.0 == m2.0 && m1.1 == m2.1 && m1.2 == m2.2 && m1.3 == m2.3
        default:
            return false
        }
    }
}
