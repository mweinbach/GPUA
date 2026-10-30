// Ported from: crates/gpui_apple/src/presentations/appkit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if os(macOS)
import AppKit

/// AppKit presentation backend namespace matching `gpui_apple::presentations::appkit`.
public enum AppKitPresentations {}
#endif
#endif
