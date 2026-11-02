// Ported from: crates/rune/src/platform/accent.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The user's accent colour and keyboard focus ring colour.

/// The user's accent colour and the colour of keyboard focus rings, each for a light and a dark appearance.
public struct SystemAccent: Sendable, Equatable {
    private var accentColors: [Color]
    private var focusColors: [Color]

    /// macOS's default blue (`#007AFF` light, `#0A84FF` dark) and its focus ring at 50%.
    public static let DEFAULT = SystemAccent.new(
        Color(0.0, 0.194_618, 1.0, 1.0),
        Color(0.003_035, 0.230_74, 1.0, 1.0)
    )

    public init() {
        self = SystemAccent.DEFAULT
    }

    public init(light: Color, dark: Color) {
        self.accentColors = [light, dark]
        self.focusColors = [
            Color(light.r, light.g, light.b, light.a * 0.5),
            Color(dark.r, dark.g, dark.b, dark.a * 0.5),
        ]
    }

    public static func new(_ light: Color, _ dark: Color) -> SystemAccent {
        SystemAccent(light: light, dark: dark)
    }

    public func withFocus(_ light: Color, _ dark: Color) -> SystemAccent {
        var copy = self
        copy.focusColors = [light, dark]
        return copy
    }

    public func accent(_ dark: Bool) -> Color {
        accentColors[dark ? 1 : 0]
    }

    public func focus(_ dark: Bool) -> Color {
        focusColors[dark ? 1 : 0]
    }
}

/// The user's accent and focus ring colours.
public func systemAccent() -> SystemAccent {
    SystemAccent.DEFAULT
}
