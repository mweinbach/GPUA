// Ported from: crates/gpui/src/colors.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// The appearance of the window, as defined by the operating system.
public enum WindowAppearance: Sendable, Equatable, Hashable, Codable {
    /// A light appearance.
    case light
    /// A light appearance with vibrant colors.
    case vibrantLight
    /// A dark appearance.
    case dark
    /// A dark appearance with vibrant colors.
    case vibrantDark
}

/// The appearance of the base GPUI colors, used to style GPUI elements.
public enum DefaultAppearance: Sendable, Equatable, Hashable, Codable {
    /// Use the set of colors for light appearances.
    case light
    /// Use the set of colors for dark appearances.
    case dark

    public init(appearance: WindowAppearance) {
        switch appearance {
        case .light, .vibrantLight:
            self = .light
        case .dark, .vibrantDark:
            self = .dark
        }
    }
}

/// The default set of colors for gpui.
///
/// These are used for styling base components, examples and more.
public struct Colors: Sendable, Equatable, Hashable {
    /// Text color
    public var text: Rgba
    /// Selected text color
    public var selectedText: Rgba
    /// Background color
    public var background: Rgba
    /// Disabled color
    public var disabled: Rgba
    /// Selected color
    public var selected: Rgba
    /// Border color
    public var border: Rgba
    /// Separator color
    public var separator: Rgba
    /// Container color
    public var container: Rgba

    public init(
        text: Rgba,
        selectedText: Rgba,
        background: Rgba,
        disabled: Rgba,
        selected: Rgba,
        border: Rgba,
        separator: Rgba,
        container: Rgba
    ) {
        self.text = text
        self.selectedText = selectedText
        self.background = background
        self.disabled = disabled
        self.selected = selected
        self.border = border
        self.separator = separator
        self.container = container
    }

    /// Returns the default dark colors.
    public static func dark() -> Colors {
        Colors(
            text: rgb(0xffffff),
            selectedText: rgb(0xffffff),
            background: rgb(0x222222),
            disabled: rgb(0x565656),
            selected: rgb(0x2457ca),
            border: rgb(0x000000),
            separator: rgb(0xd9d9d9),
            container: rgb(0x262626)
        )
    }

    /// Returns the default light colors.
    public static func light() -> Colors {
        Colors(
            text: rgb(0x252525),
            selectedText: rgb(0xffffff),
            background: rgb(0xffffff),
            disabled: rgb(0xb0b0b0),
            selected: rgb(0x2a63d9),
            border: rgb(0xd9d9d9),
            separator: rgb(0xe6e6e6),
            container: rgb(0xf4f5f5)
        )
    }

    /// Returns the default colors for the given window appearance.
    public static func forAppearance(_ appearance: WindowAppearance) -> Colors {
        switch appearance {
        case .light, .vibrantLight:
            return light()
        case .dark, .vibrantDark:
            return dark()
        }
    }
}

/// Global wrapper for default colors.
public struct GlobalColors: Global, Default, Sendable, Equatable {
    public var colors: Colors

    public init(_ colors: Colors = Colors.dark()) {
        self.colors = colors
    }

    public static func `default`() -> GlobalColors {
        GlobalColors(Colors.dark())
    }
}

