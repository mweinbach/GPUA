// Ported from: crates/gpui_apple/src/composite_hosts/appkit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if os(macOS)
import AppKit

/// AppKit composite-host backend namespace matching `gpui_apple::composite_hosts::appkit`.
public enum AppKitCompositeHost {}
#endif
#endif
