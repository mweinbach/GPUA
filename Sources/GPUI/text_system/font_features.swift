// Ported from: crates/gpui/src/text_system/font_features.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

/// The OpenType features that can be configured for a given font.
public struct FontFeatures: Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    public struct FeatureEntry: Sendable, Equatable, Hashable, Codable {
        public var tag: String
        public var value: UInt32

        public init(tag: String, value: UInt32) {
            self.tag = tag
            self.value = value
        }
    }

    public var entries: [FeatureEntry]

    public init() {
        self.entries = []
    }

    public init(_ features: [(String, UInt32)]) {
        self.entries = features.map { FeatureEntry(tag: $0.0, value: $0.1) }
    }

    public static func disableLigatures() -> FontFeatures {
        FontFeatures([("calt", 0)])
    }

    public func tagValueList() -> [(String, UInt32)] {
        entries.map { ($0.tag, $0.value) }
    }

    public func isCaltEnabled() -> Bool? {
        entries.first(where: { $0.tag == "calt" }).map { $0.value == 1 }
    }
}
