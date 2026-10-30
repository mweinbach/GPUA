// Ported from: crates/gpui_apple/src/lib.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Shared Apple host infrastructure namespace bridging AppKit (macOS) and UIKit (iOS/visionOS).
public enum GPUIAppleModule {
    /// Indicates whether the current Apple host uses AppKit (`true` on macOS) or UIKit (`false`).
    public static var isAppKit: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}
#endif
