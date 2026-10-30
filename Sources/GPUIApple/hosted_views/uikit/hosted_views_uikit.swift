// Ported from: crates/gpui_apple/src/hosted_views/uikit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if canImport(UIKit)
import UIKit

/// UIKit hosted-view backend namespace matching `gpui_apple::hosted_views::uikit`.
public enum UIKitHostedViews {}
#endif
#endif
