// Ported from: crates/gpui_macros/src/gpui_macros.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// PORT NOTE: gpui_macros crate is ported as pure-Swift runtime metadata, descriptors,
// registries, and test harness traits per ADR-0007, avoiding compiler macro cross-compile
// issues on Android, Windows, and Linux CI.

/// Version metadata for GPUIMacros support library.
public enum GPUIMacrosInfo {
    public static let version = "0.1.0"
}
