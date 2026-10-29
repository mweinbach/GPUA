// Ported from: crates/gpui/src/text_system/font_fallbacks.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// The fallback fonts that can be configured for a given font.
/// Fallback font family names are stored here.
public struct FontFallbacks: Sendable, Equatable, Hashable, Codable {
    public var fallbacks: [String]

    public init(_ fallbacks: [String] = []) {
        self.fallbacks = fallbacks
    }

    /// Get the fallback fonts family names.
    public func fallbackList() -> [String] {
        fallbacks
    }

    /// Create a font fallback from a list of strings.
    public static func fromFonts(_ fonts: [String]) -> FontFallbacks {
        FontFallbacks(fonts)
    }
}
