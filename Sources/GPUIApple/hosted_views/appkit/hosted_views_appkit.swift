// Ported from: crates/gpui_apple/src/hosted_views/appkit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if os(macOS)
import AppKit

/// AppKit hosted-view backend namespace matching `gpui_apple::hosted_views::appkit`.
public enum AppKitHostedViews {}
#endif
#endif
