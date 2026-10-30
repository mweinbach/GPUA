// Ported from: crates/gpui_apple/src/presentations/uikit/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
#if canImport(UIKit)
import UIKit

/// UIKit presentation backend namespace matching `gpui_apple::presentations::uikit`.
public enum UIKitPresentations {}
#endif
#endif
