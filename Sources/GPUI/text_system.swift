// Ported from: crates/gpui/src/text_system.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Refineable

/// Font weight values ranging from 100 (thin) to 900 (black).
public struct FontWeight: Sendable, Equatable, Hashable, Comparable, Codable, ExpressibleByFloatLiteral, DefaultInitializable {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public init(floatLiteral value: Float) {
        self.value = value
    }

    public init() {
        self.value = 400.0
    }

    public static let thin = FontWeight(100.0)
    public static let extraLight = FontWeight(200.0)
    public static let light = FontWeight(300.0)
    public static let normal = FontWeight(400.0)
    public static let medium = FontWeight(500.0)
    public static let semibold = FontWeight(600.0)
    public static let bold = FontWeight(700.0)
    public static let extraBold = FontWeight(800.0)
    public static let black = FontWeight(900.0)

    public static let all: [FontWeight] = [
        .thin, .extraLight, .light, .normal, .medium, .semibold, .bold, .extraBold, .black
    ]

    public static func < (lhs: FontWeight, rhs: FontWeight) -> Bool {
        lhs.value < rhs.value
    }
}

/// Allows italic or oblique faces to be selected.
public enum FontStyle: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// A face that is neither italic nor obliqued.
    case normal
    /// A form that is cursive in nature.
    case italic
    /// A typically-sloped version of the regular face.
    case oblique

    public init() {
        self = .normal
    }
}

/// OpenType font feature settings.
public struct FontFeatures: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    public init() {}
}

/// Fallback fonts to use when glyphs are missing from the primary font family.
public struct FontFallbacks: Sendable, Equatable, Hashable, Codable {
    public var fallbacks: [SharedString]

    public init(fallbacks: [SharedString] = []) {
        self.fallbacks = fallbacks
    }
}

/// Configuration details identifying a specific font.
public struct Font: Sendable, Equatable, Hashable {
    /// The font family name. The special name ".SystemUIFont" identifies the system UI font.
    public var family: SharedString
    /// The font features to use.
    public var features: FontFeatures
    /// The fallback fonts to use.
    public var fallbacks: FontFallbacks?
    /// The font weight.
    public var weight: FontWeight
    /// The font style.
    public var style: FontStyle

    public init(
        family: SharedString = ".SystemUIFont",
        features: FontFeatures = FontFeatures(),
        fallbacks: FontFallbacks? = nil,
        weight: FontWeight = .normal,
        style: FontStyle = .normal
    ) {
        self.family = family
        self.features = features
        self.fallbacks = fallbacks
        self.weight = weight
        self.style = style
    }
}

/// A styled run of text.
public struct TextRun: Sendable, Equatable {
    public var len: Int
    public var font: Font
    public var color: Hsla
    public var backgroundColor: Hsla?
    public var underline: UnderlineStyle?
    public var strikethrough: StrikethroughStyle?

    public init(
        len: Int = 0,
        font: Font = Font(),
        color: Hsla = black(),
        backgroundColor: Hsla? = nil,
        underline: UnderlineStyle? = nil,
        strikethrough: StrikethroughStyle? = nil
    ) {
        self.len = len
        self.font = font
        self.color = color
        self.backgroundColor = backgroundColor
        self.underline = underline
        self.strikethrough = strikethrough
    }
}
