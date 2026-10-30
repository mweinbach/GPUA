// Ported from: crates/gpui_apple/src/composite_hosts/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation

/// Hosted Apple composite-host backends, split by platform family (`AppKit` on macOS, `UIKit` on iOS/visionOS).
public enum AppleCompositeHosts {}
#endif
