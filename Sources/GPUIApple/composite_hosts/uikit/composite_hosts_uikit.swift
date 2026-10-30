// Ported from: crates/gpui_apple/src/composite_hosts/uikit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if canImport(UIKit)
import UIKit

/// UIKit composite-host backend namespace matching `gpui_apple::composite_hosts::uikit`.
public enum UIKitCompositeHost {}
#endif
#endif
