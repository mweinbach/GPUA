// Ported from: crates/gpui_apple/src/hosted_views/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation

/// Hosted Apple view backends, split by platform family (`AppKit` on macOS, `UIKit` on iOS/visionOS).
public enum AppleHostedViews {}
#endif
