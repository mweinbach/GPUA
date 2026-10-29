// Ported from: crates/gpui/src/composite_hosts/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Low-level primitives for window-integrated composite hosts.
///
/// Composite hosts own the explicit mixing boundary between GPUI-rendered
/// surfaces and platform-hosted container structures such as sidebars and split
/// hosts.
public enum CompositeHosts {}
