// Ported from: crates/gpui/src/scene.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: in-progress

import Foundation
import Refineable

/// The style of a border.
public enum BorderStyle: UInt32, Sendable, Equatable, Hashable, Codable, DefaultInitializable {
    /// A solid border.
    case solid = 0
    /// A dashed border.
    case dashed = 1

    public init() {
        self = .solid
    }
}
