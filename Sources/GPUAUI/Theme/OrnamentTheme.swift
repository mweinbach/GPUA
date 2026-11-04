// Swift-only: Unified Shadcn-style UI ornaments across GPUI and Rune (ADR-0015).

import GPUI
import Rune
import RuneKit
import RuneKnobs
import RuneLight
import RuneMermaid
import RuneMotion
import RuneThemeOpenCode

// MARK: - Appearance & Color Bridge

/// Light or dark color scheme for an ``OrnamentTheme``.
public enum OrnamentAppearance: String, Sendable, Equatable, Hashable, CaseIterable {
    case light
    case dark

    public var isDark: Bool {
        self == .dark
    }
}

/// Engine-neutral sRGB color (with straight alpha in `0...1`) that bridges losslessly between
/// ``GPUI`` (`Hsla` / `Rgba` in gamma-encoded sRGB) and ``Rune`` (`Rune.Color` in linear sRGB).
public struct OrnamentColor: Sendable, Equatable, Hashable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    @inline(__always)
    private static func clamp01(_ v: Float) -> Float {
        if v < 0.0 { return 0.0 }
        if v > 1.0 { return 1.0 }
        return v
    }

    public init(srgbR r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = Self.clamp01(r)
        self.g = Self.clamp01(g)
        self.b = Self.clamp01(b)
        self.a = Self.clamp01(a)
    }

    /// Creates a color from a 24-bit `0xRRGGBB` hex literal and optional `alpha`.
    public init(hex: UInt32, alpha: Float = 1.0) {
        let r = Float((hex >> 16) & 0xFF) / 255.0
        let g = Float((hex >> 8) & 0xFF) / 255.0
        let b = Float(hex & 0xFF) / 255.0
        self.init(srgbR: r, g: g, b: b, a: alpha)
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA` CSS hex strings.
    public init?(hexString: String) {
        guard let parsed = Rune.color.hex(hexString) else {
            return nil
        }
        self.init(runeColor: parsed)
    }

    /// Converts a linear-sRGB ``Rune/Color`` into gamma-encoded ``OrnamentColor``.
    public init(runeColor c: Rune.Color) {
        self.init(
            srgbR: Rune.srgbEncode(Self.clamp01(c.r)),
            g: Rune.srgbEncode(Self.clamp01(c.g)),
            b: Rune.srgbEncode(Self.clamp01(c.b)),
            a: Self.clamp01(c.a)
        )
    }

    /// Converts a ``GPUI/Hsla`` color into ``OrnamentColor``.
    public init(gpuiHsla hsla: GPUI.Hsla) {
        let rgb = hsla.toRgb()
        self.init(srgbR: rgb.r, g: rgb.g, b: rgb.b, a: rgb.a)
    }

    public static let transparent = OrnamentColor(srgbR: 0.0, g: 0.0, b: 0.0, a: 0.0)
    public static let white = OrnamentColor(srgbR: 1.0, g: 1.0, b: 1.0, a: 1.0)
    public static let black = OrnamentColor(srgbR: 0.0, g: 0.0, b: 0.0, a: 1.0)

    /// Returns a copy with alpha replaced by `alpha`.
    public func withAlpha(_ alpha: Float) -> OrnamentColor {
        OrnamentColor(srgbR: r, g: g, b: b, a: alpha)
    }

    /// Perceptual OKLab interpolation `t` (`0...1`) toward `other`.
    public func mixed(with other: OrnamentColor, _ t: Float) -> OrnamentColor {
        let aLab = toRuneColor().toOklab()
        let bLab = other.toRuneColor().toOklab()
        let u = Self.clamp01(t)
        let blended = Rune.Color.fromOklab([
            aLab[0] + (bLab[0] - aLab[0]) * u,
            aLab[1] + (bLab[1] - aLab[1]) * u,
            aLab[2] + (bLab[2] - aLab[2]) * u,
            a + (other.a - a) * u,
        ])
        return OrnamentColor(runeColor: blended)
    }

    /// Relative WCAG luminance in linear light (`0...1`).
    public func luminance() -> Float {
        toRuneColor().luminance()
    }

    /// WCAG 2.1 contrast ratio (`1...21`) against `other`.
    public func contrastRatio(with other: OrnamentColor) -> Float {
        let l1 = luminance()
        let l2 = other.luminance()
        return (Swift.max(l1, l2) + 0.05) / (Swift.min(l1, l2) + 0.05)
    }

    /// Converts to ``GPUI/Rgba`` (gamma-encoded sRGB).
    public func toGPUIRgba() -> GPUI.Rgba {
        GPUI.Rgba(r: r, g: g, b: b, a: a)
    }

    /// Converts to ``GPUI/Hsla`` (gamma-encoded sRGB).
    public func toGPUIHsla() -> GPUI.Hsla {
        GPUI.Hsla(rgba: toGPUIRgba())
    }

    /// Converts to ``Rune/Color`` (linear sRGB).
    public func toRuneColor() -> Rune.Color {
        Rune.Color(
            r: Rune.srgbDecode(r),
            g: Rune.srgbDecode(g),
            b: Rune.srgbDecode(b),
            a: a
        )
    }
}

// MARK: - Radii, Glass & Motion Tokens

/// Corner radius scale matching shadcn/ui (`--radius` and derived steps).
public struct OrnamentRadii: Sendable, Equatable, Hashable {
    public var xs: Float
    public var sm: Float
    public var md: Float
    public var lg: Float
    public var xl: Float
    public var full: Float

    public init(
        xs: Float = 4.0,
        sm: Float = 6.0,
        md: Float = 8.0,
        lg: Float = 12.0,
        xl: Float = 16.0,
        full: Float = 9999.0
    ) {
        self.xs = xs
        self.sm = sm
        self.md = md
        self.lg = lg
        self.xl = xl
        self.full = full
    }
}

/// Optical and backdrop parameters for frosted-glass ornaments (`UIGlassCard`, `UIFrostedBar`),
/// bridging directly to ``RuneLight/Glass`` and ``Rune`` backdrop blur.
public struct OrnamentGlassTokens: Sendable, Equatable, Hashable {
    public var blurRadius: Float
    public var tintOpacity: Float
    public var rimOpacity: Float
    public var ior: Float
    public var dispersion: Float
    public var frost: Float
    public var thickness: Float
    public var bevel: Float
    public var gap: Float

    public init(
        blurRadius: Float = 22.0,
        tintOpacity: Float = 0.68,
        rimOpacity: Float = 0.28,
        ior: Float = 1.52,
        dispersion: Float = 0.30,
        frost: Float = 0.26,
        thickness: Float = 24.0,
        bevel: Float = 18.0,
        gap: Float = 6.0
    ) {
        self.blurRadius = blurRadius
        self.tintOpacity = tintOpacity
        self.rimOpacity = rimOpacity
        self.ior = ior
        self.dispersion = dispersion
        self.frost = frost
        self.thickness = thickness
        self.bevel = bevel
        self.gap = gap
    }

    /// Constructs a physical ``RuneLight/Glass`` pane for `RuneLight.Scene` GI & refraction passes.
    public func toRuneLightGlass(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        radius: Float,
        surfaceTint: OrnamentColor
    ) -> RuneLight.Glass {
        let lin = surfaceTint.toRuneColor()
        return RuneLight.Glass.rounded(x, y, width, height, radius)
            .ior(ior)
            .dispersion(dispersion)
            .frost(frost)
            .thickness(thickness)
            .bevel(bevel)
            .gap(gap)
            .tint(lin.r, lin.g, lin.b, tintOpacity)
    }
}

/// Spring presets shared across `Rune` and `GPUI` ornament transitions.
public struct OrnamentMotionTokens: Sendable, Equatable, Hashable {
    public var snappy: RuneMotion.Spring
    public var bouncy: RuneMotion.Spring
    public var gentle: RuneMotion.Spring

    public init(
        snappy: RuneMotion.Spring = RuneMotion.Spring.snappy,
        bouncy: RuneMotion.Spring = RuneMotion.Spring.bouncy,
        gentle: RuneMotion.Spring = RuneMotion.Spring.smooth
    ) {
        self.snappy = snappy
        self.bouncy = bouncy
        self.gentle = gentle
    }
}

// MARK: - OrnamentTheme

/// Unified shadcn/ui semantic design-token theme shared across ``GPUI`` and ``Rune``.
public struct OrnamentTheme: Sendable, Equatable, Hashable {
    /// Task-local default theme used when an ornament renders via `GPUI.IntoElement.intoElement()`
    /// or `renderRune()` without an explicit theme parameter.
    @TaskLocal public static var current: OrnamentTheme = .zinc(.dark)

    /// Scopes `OrnamentTheme.current` for the duration of `operation`.
    public static func withTheme<R>(_ theme: OrnamentTheme, _ operation: () throws -> R) rethrows -> R {
        try $current.withValue(theme, operation: operation)
    }

    public var name: String
    public var appearance: OrnamentAppearance

    // Shadcn semantic color roles
    public var background: OrnamentColor
    public var foreground: OrnamentColor
    public var card: OrnamentColor
    public var cardForeground: OrnamentColor
    public var popover: OrnamentColor
    public var popoverForeground: OrnamentColor
    public var primary: OrnamentColor
    public var primaryForeground: OrnamentColor
    public var secondary: OrnamentColor
    public var secondaryForeground: OrnamentColor
    public var muted: OrnamentColor
    public var mutedForeground: OrnamentColor
    public var accent: OrnamentColor
    public var accentForeground: OrnamentColor
    public var destructive: OrnamentColor
    public var destructiveForeground: OrnamentColor
    public var success: OrnamentColor
    public var successForeground: OrnamentColor
    public var warning: OrnamentColor
    public var warningForeground: OrnamentColor
    public var info: OrnamentColor
    public var infoForeground: OrnamentColor
    public var border: OrnamentColor
    public var input: OrnamentColor
    public var ring: OrnamentColor

    public var radii: OrnamentRadii
    public var glass: OrnamentGlassTokens
    public var motion: OrnamentMotionTokens
    public var fontSans: String
    public var fontMono: String

    public init(
        name: String,
        appearance: OrnamentAppearance,
        background: OrnamentColor,
        foreground: OrnamentColor,
        card: OrnamentColor,
        cardForeground: OrnamentColor,
        popover: OrnamentColor,
        popoverForeground: OrnamentColor,
        primary: OrnamentColor,
        primaryForeground: OrnamentColor,
        secondary: OrnamentColor,
        secondaryForeground: OrnamentColor,
        muted: OrnamentColor,
        mutedForeground: OrnamentColor,
        accent: OrnamentColor,
        accentForeground: OrnamentColor,
        destructive: OrnamentColor,
        destructiveForeground: OrnamentColor,
        success: OrnamentColor,
        successForeground: OrnamentColor,
        warning: OrnamentColor,
        warningForeground: OrnamentColor,
        info: OrnamentColor,
        infoForeground: OrnamentColor,
        border: OrnamentColor,
        input: OrnamentColor,
        ring: OrnamentColor,
        radii: OrnamentRadii = OrnamentRadii(),
        glass: OrnamentGlassTokens? = nil,
        motion: OrnamentMotionTokens = OrnamentMotionTokens(),
        fontSans: String = ".SystemUIFont",
        fontMono: String = "Menlo"
    ) {
        self.name = name
        self.appearance = appearance
        self.background = background
        self.foreground = foreground
        self.card = card
        self.cardForeground = cardForeground
        self.popover = popover
        self.popoverForeground = popoverForeground
        self.primary = primary
        self.primaryForeground = primaryForeground
        self.secondary = secondary
        self.secondaryForeground = secondaryForeground
        self.muted = muted
        self.mutedForeground = mutedForeground
        self.accent = accent
        self.accentForeground = accentForeground
        self.destructive = destructive
        self.destructiveForeground = destructiveForeground
        self.success = success
        self.successForeground = successForeground
        self.warning = warning
        self.warningForeground = warningForeground
        self.info = info
        self.infoForeground = infoForeground
        self.border = border
        self.input = input
        self.ring = ring
        self.radii = radii
        self.glass = glass ?? OrnamentGlassTokens(
            blurRadius: 24.0,
            tintOpacity: appearance.isDark ? 0.66 : 0.76,
            rimOpacity: appearance.isDark ? 0.24 : 0.55
        )
        self.motion = motion
        self.fontSans = fontSans
        self.fontMono = fontMono
    }

    // MARK: - Curated Shadcn Presets

    /// Shadcn **Zinc** preset in `.dark` or `.light`.
    public static func zinc(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        switch appearance {
        case .dark:
            return OrnamentTheme(
                name: "Zinc",
                appearance: .dark,
                background: OrnamentColor(hex: 0x09090B),
                foreground: OrnamentColor(hex: 0xFAFAFA),
                card: OrnamentColor(hex: 0x111114),
                cardForeground: OrnamentColor(hex: 0xFAFAFA),
                popover: OrnamentColor(hex: 0x141418),
                popoverForeground: OrnamentColor(hex: 0xFAFAFA),
                primary: OrnamentColor(hex: 0xFAFAFA),
                primaryForeground: OrnamentColor(hex: 0x18181B),
                secondary: OrnamentColor(hex: 0x27272A),
                secondaryForeground: OrnamentColor(hex: 0xFAFAFA),
                muted: OrnamentColor(hex: 0x1F1F23),
                mutedForeground: OrnamentColor(hex: 0xA1A1AA),
                accent: OrnamentColor(hex: 0x27272A),
                accentForeground: OrnamentColor(hex: 0xFAFAFA),
                destructive: OrnamentColor(hex: 0xEF4444),
                destructiveForeground: OrnamentColor(hex: 0xFAFAFA),
                success: OrnamentColor(hex: 0x22C55E),
                successForeground: OrnamentColor(hex: 0x052E16),
                warning: OrnamentColor(hex: 0xF59E0B),
                warningForeground: OrnamentColor(hex: 0x451A03),
                info: OrnamentColor(hex: 0x38BDF8),
                infoForeground: OrnamentColor(hex: 0x082F49),
                border: OrnamentColor(hex: 0x27272A),
                input: OrnamentColor(hex: 0x27272A),
                ring: OrnamentColor(hex: 0xD4D4D8)
            )
        case .light:
            return OrnamentTheme(
                name: "Zinc",
                appearance: .light,
                background: OrnamentColor(hex: 0xFFFFFF),
                foreground: OrnamentColor(hex: 0x09090B),
                card: OrnamentColor(hex: 0xFFFFFF),
                cardForeground: OrnamentColor(hex: 0x09090B),
                popover: OrnamentColor(hex: 0xFFFFFF),
                popoverForeground: OrnamentColor(hex: 0x09090B),
                primary: OrnamentColor(hex: 0x18181B),
                primaryForeground: OrnamentColor(hex: 0xFAFAFA),
                secondary: OrnamentColor(hex: 0xF4F4F5),
                secondaryForeground: OrnamentColor(hex: 0x18181B),
                muted: OrnamentColor(hex: 0xF4F4F5),
                mutedForeground: OrnamentColor(hex: 0x71717A),
                accent: OrnamentColor(hex: 0xF4F4F5),
                accentForeground: OrnamentColor(hex: 0x18181B),
                destructive: OrnamentColor(hex: 0xDC2626),
                destructiveForeground: OrnamentColor(hex: 0xFAFAFA),
                success: OrnamentColor(hex: 0x16A34A),
                successForeground: OrnamentColor(hex: 0xFFFFFF),
                warning: OrnamentColor(hex: 0xD97706),
                warningForeground: OrnamentColor(hex: 0xFFFFFF),
                info: OrnamentColor(hex: 0x0284C7),
                infoForeground: OrnamentColor(hex: 0xFFFFFF),
                border: OrnamentColor(hex: 0xE4E4E7),
                input: OrnamentColor(hex: 0xE4E4E7),
                ring: OrnamentColor(hex: 0x18181B)
            )
        }
    }

    /// Shadcn **Slate** cool blue-gray preset in `.dark` or `.light`.
    public static func slate(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        switch appearance {
        case .dark:
            return OrnamentTheme(
                name: "Slate",
                appearance: .dark,
                background: OrnamentColor(hex: 0x020617),
                foreground: OrnamentColor(hex: 0xF8FAFC),
                card: OrnamentColor(hex: 0x0F172A),
                cardForeground: OrnamentColor(hex: 0xF8FAFC),
                popover: OrnamentColor(hex: 0x0F172A),
                popoverForeground: OrnamentColor(hex: 0xF8FAFC),
                primary: OrnamentColor(hex: 0xF8FAFC),
                primaryForeground: OrnamentColor(hex: 0x0F172A),
                secondary: OrnamentColor(hex: 0x1E293B),
                secondaryForeground: OrnamentColor(hex: 0xF8FAFC),
                muted: OrnamentColor(hex: 0x1E293B),
                mutedForeground: OrnamentColor(hex: 0x94A3B8),
                accent: OrnamentColor(hex: 0x1E293B),
                accentForeground: OrnamentColor(hex: 0xF8FAFC),
                destructive: OrnamentColor(hex: 0xEF4444),
                destructiveForeground: OrnamentColor(hex: 0xF8FAFC),
                success: OrnamentColor(hex: 0x22C55E),
                successForeground: OrnamentColor(hex: 0x052E16),
                warning: OrnamentColor(hex: 0xF59E0B),
                warningForeground: OrnamentColor(hex: 0x451A03),
                info: OrnamentColor(hex: 0x38BDF8),
                infoForeground: OrnamentColor(hex: 0x082F49),
                border: OrnamentColor(hex: 0x1E293B),
                input: OrnamentColor(hex: 0x1E293B),
                ring: OrnamentColor(hex: 0xCBD5E1)
            )
        case .light:
            return OrnamentTheme(
                name: "Slate",
                appearance: .light,
                background: OrnamentColor(hex: 0xFFFFFF),
                foreground: OrnamentColor(hex: 0x020617),
                card: OrnamentColor(hex: 0xFFFFFF),
                cardForeground: OrnamentColor(hex: 0x020617),
                popover: OrnamentColor(hex: 0xFFFFFF),
                popoverForeground: OrnamentColor(hex: 0x020617),
                primary: OrnamentColor(hex: 0x0F172A),
                primaryForeground: OrnamentColor(hex: 0xF8FAFC),
                secondary: OrnamentColor(hex: 0xF1F5F9),
                secondaryForeground: OrnamentColor(hex: 0x0F172A),
                muted: OrnamentColor(hex: 0xF1F5F9),
                mutedForeground: OrnamentColor(hex: 0x64748B),
                accent: OrnamentColor(hex: 0xF1F5F9),
                accentForeground: OrnamentColor(hex: 0x0F172A),
                destructive: OrnamentColor(hex: 0xDC2626),
                destructiveForeground: OrnamentColor(hex: 0xF8FAFC),
                success: OrnamentColor(hex: 0x16A34A),
                successForeground: OrnamentColor(hex: 0xFFFFFF),
                warning: OrnamentColor(hex: 0xD97706),
                warningForeground: OrnamentColor(hex: 0xFFFFFF),
                info: OrnamentColor(hex: 0x0284C7),
                infoForeground: OrnamentColor(hex: 0xFFFFFF),
                border: OrnamentColor(hex: 0xE2E8F0),
                input: OrnamentColor(hex: 0xE2E8F0),
                ring: OrnamentColor(hex: 0x0F172A)
            )
        }
    }

    /// Shadcn **Neutral** pure achromatic preset in `.dark` or `.light`.
    public static func neutral(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        switch appearance {
        case .dark:
            return OrnamentTheme(
                name: "Neutral",
                appearance: .dark,
                background: OrnamentColor(hex: 0x0A0A0A),
                foreground: OrnamentColor(hex: 0xFAFAFA),
                card: OrnamentColor(hex: 0x141414),
                cardForeground: OrnamentColor(hex: 0xFAFAFA),
                popover: OrnamentColor(hex: 0x171717),
                popoverForeground: OrnamentColor(hex: 0xFAFAFA),
                primary: OrnamentColor(hex: 0xE5E5E5),
                primaryForeground: OrnamentColor(hex: 0x171717),
                secondary: OrnamentColor(hex: 0x262626),
                secondaryForeground: OrnamentColor(hex: 0xFAFAFA),
                muted: OrnamentColor(hex: 0x202020),
                mutedForeground: OrnamentColor(hex: 0xA3A3A3),
                accent: OrnamentColor(hex: 0x262626),
                accentForeground: OrnamentColor(hex: 0xFAFAFA),
                destructive: OrnamentColor(hex: 0xEF4444),
                destructiveForeground: OrnamentColor(hex: 0xFAFAFA),
                success: OrnamentColor(hex: 0x22C55E),
                successForeground: OrnamentColor(hex: 0x052E16),
                warning: OrnamentColor(hex: 0xF59E0B),
                warningForeground: OrnamentColor(hex: 0x451A03),
                info: OrnamentColor(hex: 0x3B82F6),
                infoForeground: OrnamentColor(hex: 0xFFFFFF),
                border: OrnamentColor(hex: 0x262626),
                input: OrnamentColor(hex: 0x262626),
                ring: OrnamentColor(hex: 0xD4D4D4)
            )
        case .light:
            return OrnamentTheme(
                name: "Neutral",
                appearance: .light,
                background: OrnamentColor(hex: 0xFFFFFF),
                foreground: OrnamentColor(hex: 0x0A0A0A),
                card: OrnamentColor(hex: 0xFFFFFF),
                cardForeground: OrnamentColor(hex: 0x0A0A0A),
                popover: OrnamentColor(hex: 0xFFFFFF),
                popoverForeground: OrnamentColor(hex: 0x0A0A0A),
                primary: OrnamentColor(hex: 0x171717),
                primaryForeground: OrnamentColor(hex: 0xFAFAFA),
                secondary: OrnamentColor(hex: 0xF5F5F5),
                secondaryForeground: OrnamentColor(hex: 0x171717),
                muted: OrnamentColor(hex: 0xF5F5F5),
                mutedForeground: OrnamentColor(hex: 0x737373),
                accent: OrnamentColor(hex: 0xF5F5F5),
                accentForeground: OrnamentColor(hex: 0x171717),
                destructive: OrnamentColor(hex: 0xDC2626),
                destructiveForeground: OrnamentColor(hex: 0xFAFAFA),
                success: OrnamentColor(hex: 0x16A34A),
                successForeground: OrnamentColor(hex: 0xFFFFFF),
                warning: OrnamentColor(hex: 0xD97706),
                warningForeground: OrnamentColor(hex: 0xFFFFFF),
                info: OrnamentColor(hex: 0x2563EB),
                infoForeground: OrnamentColor(hex: 0xFFFFFF),
                border: OrnamentColor(hex: 0xE5E5E5),
                input: OrnamentColor(hex: 0xE5E5E5),
                ring: OrnamentColor(hex: 0x171717)
            )
        }
    }

    /// Shadcn **Rose** vibrant crimson-pink accent preset in `.dark` or `.light`.
    public static func rose(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        var base = zinc(appearance)
        base.name = "Rose"
        switch appearance {
        case .dark:
            base.primary = OrnamentColor(hex: 0xE11D48)
            base.primaryForeground = OrnamentColor(hex: 0xFFF1F2)
            base.ring = OrnamentColor(hex: 0xFB7185)
            base.accent = OrnamentColor(hex: 0x2D161E)
            base.accentForeground = OrnamentColor(hex: 0xFFE4E6)
        case .light:
            base.primary = OrnamentColor(hex: 0xE11D48)
            base.primaryForeground = OrnamentColor(hex: 0xFFF1F2)
            base.ring = OrnamentColor(hex: 0xE11D48)
            base.accent = OrnamentColor(hex: 0xFFF1F2)
            base.accentForeground = OrnamentColor(hex: 0x881337)
        }
        return base
    }

    /// Shadcn **Blue** cobalt accent preset in `.dark` or `.light`.
    public static func blue(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        var base = slate(appearance)
        base.name = "Blue"
        switch appearance {
        case .dark:
            base.primary = OrnamentColor(hex: 0x3B82F6)
            base.primaryForeground = OrnamentColor(hex: 0xEFF6FF)
            base.ring = OrnamentColor(hex: 0x60A5FA)
            base.accent = OrnamentColor(hex: 0x172554)
            base.accentForeground = OrnamentColor(hex: 0xDBEAFE)
        case .light:
            base.primary = OrnamentColor(hex: 0x2563EB)
            base.primaryForeground = OrnamentColor(hex: 0xEFF6FF)
            base.ring = OrnamentColor(hex: 0x2563EB)
            base.accent = OrnamentColor(hex: 0xEFF6FF)
            base.accentForeground = OrnamentColor(hex: 0x1E3A8A)
        }
        return base
    }

    /// **OpenCode** theme bridged directly from ``RuneThemeOpenCode/kit(_:)``.
    public static func openCode(_ appearance: OrnamentAppearance = .dark) -> OrnamentTheme {
        let dark = appearance.isDark
        let kit = RuneThemeOpenCode.kit(dark)
        let brand = OrnamentColor(runeColor: RuneThemeOpenCode.brand(dark))
        return fromRuneKit(name: "OpenCode", kit: kit, brandOverride: brand)
    }

    /// Derives a full contrast-checked ``OrnamentTheme`` from three seed colors (`bg`, `fg`, `accent`)
    /// using ``RuneKit/Kit/fromPaletteFocus(_:_:)`` OKLab contrast-floor search.
    public static func fromSeed(
        name: String = "Custom",
        bg: OrnamentColor,
        fg: OrnamentColor,
        accent: OrnamentColor
    ) -> OrnamentTheme {
        let seed = RuneKit.PaletteSeed(
            bg: bg.toRuneColor(),
            fg: fg.toRuneColor(),
            accent: accent.toRuneColor()
        )
        let kit = RuneKit.Kit.fromPaletteFocus(seed, .accent)
        return fromRuneKit(name: name, kit: kit, brandOverride: accent)
    }

    /// All 6 built-in preset builders for galleries and theme switchers.
    public static func allPresets(_ appearance: OrnamentAppearance = .dark) -> [OrnamentTheme] {
        [
            .zinc(appearance),
            .slate(appearance),
            .neutral(appearance),
            .rose(appearance),
            .blue(appearance),
            .openCode(appearance),
        ]
    }

    private static func fromRuneKit(
        name: String,
        kit: RuneKit.Kit,
        brandOverride: OrnamentColor? = nil
    ) -> OrnamentTheme {
        let c = kit.c
        let appearance: OrnamentAppearance = kit.dark ? .dark : .light
        let primary = brandOverride ?? OrnamentColor(runeColor: c.bgAccent)
        let primaryFg: OrnamentColor = primary.luminance() > 0.36
            ? OrnamentColor(hex: 0x09090B)
            : OrnamentColor(hex: 0xFAFAFA)
        return OrnamentTheme(
            name: name,
            appearance: appearance,
            background: OrnamentColor(runeColor: c.bgBase),
            foreground: OrnamentColor(runeColor: c.textBase),
            card: OrnamentColor(runeColor: c.layer01),
            cardForeground: OrnamentColor(runeColor: c.textBase),
            popover: OrnamentColor(runeColor: c.layer02),
            popoverForeground: OrnamentColor(runeColor: c.textBase),
            primary: primary,
            primaryForeground: primaryFg,
            secondary: OrnamentColor(runeColor: c.layer02),
            secondaryForeground: OrnamentColor(runeColor: c.textBase),
            muted: OrnamentColor(runeColor: c.layer01),
            mutedForeground: OrnamentColor(runeColor: c.textMuted),
            accent: OrnamentColor(runeColor: c.layer03),
            accentForeground: OrnamentColor(runeColor: c.textBase),
            destructive: OrnamentColor(runeColor: c.danger.icon),
            destructiveForeground: OrnamentColor(hex: 0xFAFAFA),
            success: OrnamentColor(runeColor: c.success.icon),
            successForeground: appearance.isDark ? OrnamentColor(hex: 0x052E16) : .white,
            warning: OrnamentColor(runeColor: c.warning.icon),
            warningForeground: appearance.isDark ? OrnamentColor(hex: 0x451A03) : .white,
            info: OrnamentColor(runeColor: c.info.icon),
            infoForeground: .white,
            border: OrnamentColor(runeColor: c.borderBase),
            input: OrnamentColor(runeColor: c.borderStrong),
            ring: OrnamentColor(runeColor: c.borderFocus),
            radii: OrnamentRadii(
                xs: kit.radius.xs,
                sm: kit.radius.sm,
                md: kit.radius.md,
                lg: kit.radius.lg,
                xl: kit.radius.xl,
                full: 9999.0
            )
        )
    }

    // MARK: - Engine Bridges (RuneKit, RuneMermaid, RuneKnobs, GPUI)

    /// Bridges this ``OrnamentTheme`` into a full ``RuneKit/Kit`` token bundle.
    public func runeKit() -> RuneKit.Kit {
        if name == "OpenCode" {
            return RuneThemeOpenCode.kit(appearance.isDark)
        }
        let seed = RuneKit.PaletteSeed(
            bg: background.toRuneColor(),
            fg: foreground.toRuneColor(),
            accent: primary.toRuneColor()
        )
        var kit = RuneKit.Kit.fromPaletteFocus(seed, .custom(ring.toRuneColor()))
        kit.c.bgBase = background.toRuneColor()
        kit.c.page = background.toRuneColor()
        kit.c.layer01 = card.toRuneColor()
        kit.c.layer02 = secondary.toRuneColor()
        kit.c.layer03 = accent.toRuneColor()
        kit.c.textBase = foreground.toRuneColor()
        kit.c.textMuted = mutedForeground.toRuneColor()
        kit.c.borderBase = border.toRuneColor()
        kit.c.borderMuted = border.toRuneColor()
        kit.c.borderStrong = input.toRuneColor()
        kit.c.borderFocus = ring.toRuneColor()
        kit.c.bgAccent = primary.toRuneColor()
        kit.c.textContrast = primaryForeground.toRuneColor()
        kit.c.bgContrast = primary.toRuneColor()
        kit.radius.xs = radii.xs
        kit.radius.sm = radii.sm
        kit.radius.md = radii.md
        kit.radius.lg = radii.lg
        kit.radius.xl = radii.xl
        return kit
    }

    /// Bridges this ``OrnamentTheme`` into a ``RuneMermaid/DiagramStyle``.
    public func mermaidStyle(maxWidth: Float = 640.0) -> RuneMermaid.DiagramStyle {
        let dark = appearance.isDark
        let fg = foreground.toRuneColor()
        return RuneMermaid.DiagramStyle(
            text: fg,
            muted: mutedForeground.toRuneColor(),
            surface: card.toRuneColor(),
            surfaceBorder: border.toRuneColor(),
            nodeFill: secondary.toRuneColor(),
            nodeBorder: ring.withAlpha(dark ? 0.45 : 0.35).toRuneColor(),
            line: mutedForeground.withAlpha(0.78).toRuneColor(),
            clusterFill: muted.withAlpha(dark ? 0.55 : 0.65).toRuneColor(),
            noteFill: warning.withAlpha(dark ? 0.16 : 0.14).toRuneColor(),
            noteBorder: warning.withAlpha(0.45).toRuneColor(),
            font: Rune.TextStyle.new(12.5, 500.0).lh(17.0),
            maxWidth: maxWidth
        )
    }

    /// Bridges this ``OrnamentTheme`` into a ``RuneKnobs/Style`` for live tuning panels.
    public func knobsStyle() -> RuneKnobs.Style {
        var st = appearance.isDark ? RuneKnobs.Style.dark() : RuneKnobs.Style.light()
        st.bg = card.toRuneColor()
        st.inset = muted.toRuneColor()
        st.raised = secondary.toRuneColor()
        st.fg = foreground.toRuneColor()
        st.fg2 = foreground.mixed(with: mutedForeground, 0.35).toRuneColor()
        st.fg3 = mutedForeground.toRuneColor()
        st.fill = muted.toRuneColor()
        st.fillHover = accent.toRuneColor()
        st.fillSelected = secondary.toRuneColor()
        st.slider = primary.withAlpha(appearance.isDark ? 0.55 : 0.38).toRuneColor()
        st.sliderHover = primary.withAlpha(appearance.isDark ? 0.72 : 0.55).toRuneColor()
        st.sliderActive = primary.toRuneColor()
        st.handle = foreground.toRuneColor()
        st.border = border.toRuneColor()
        st.rim = foreground.withAlpha(appearance.isDark ? 0.12 : 0.5).toRuneColor()
        return st
    }

    /// Bridges this ``OrnamentTheme`` into a ``RuneKit/SyntaxTheme`` for code & diff highlighting.
    public func syntaxTheme() -> RuneKit.SyntaxTheme {
        RuneKit.SyntaxTheme.fromKit(runeKit())
    }

    /// Bridges this ``OrnamentTheme`` into a ``RuneKit/MarkdownStyle``.
    public func markdownStyle() -> RuneKit.MarkdownStyle {
        RuneKit.MarkdownStyle.fromKit(runeKit())
    }

    /// Subtle Shadcn card shadow stack for ``GPUI``.
    public func gpuiCardShadows() -> [GPUI.BoxShadow] {
        let alpha: Float = appearance.isDark ? 0.38 : 0.07
        return [
            GPUI.BoxShadow(
                color: OrnamentColor.black.withAlpha(alpha).toGPUIHsla(),
                offset: GPUI.point(GPUI.px(0.0), GPUI.px(2.0)),
                blurRadius: GPUI.px(8.0),
                spreadRadius: GPUI.px(0.0)
            ),
        ]
    }

    /// Elevated popover/dropdown/toolbar shadow stack for ``GPUI``.
    public func gpuiPopoverShadows() -> [GPUI.BoxShadow] {
        let a1: Float = appearance.isDark ? 0.52 : 0.12
        let a2: Float = appearance.isDark ? 0.28 : 0.06
        return [
            GPUI.BoxShadow(
                color: OrnamentColor.black.withAlpha(a1).toGPUIHsla(),
                offset: GPUI.point(GPUI.px(0.0), GPUI.px(10.0)),
                blurRadius: GPUI.px(24.0),
                spreadRadius: GPUI.px(-4.0)
            ),
            GPUI.BoxShadow(
                color: OrnamentColor.black.withAlpha(a2).toGPUIHsla(),
                offset: GPUI.point(GPUI.px(0.0), GPUI.px(3.0)),
                blurRadius: GPUI.px(8.0),
                spreadRadius: GPUI.px(-2.0)
            ),
        ]
    }

    /// Deep modal/command-palette shadow stack for ``GPUI``.
    public func gpuiModalShadows() -> [GPUI.BoxShadow] {
        let a1: Float = appearance.isDark ? 0.68 : 0.20
        return [
            GPUI.BoxShadow(
                color: OrnamentColor.black.withAlpha(a1).toGPUIHsla(),
                offset: GPUI.point(GPUI.px(0.0), GPUI.px(20.0)),
                blurRadius: GPUI.px(44.0),
                spreadRadius: GPUI.px(-8.0)
            ),
        ]
    }
}
