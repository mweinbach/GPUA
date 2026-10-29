// Ported from: crates/gpui_macros/src/derive_visual_context.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Protocol matching upstream `derive(VisualContext)` providing context delegation to an underlying window and app context.
public protocol VisualContextForwarding: AppContextForwarding {
    associatedtype TargetWindowContext
    var forwardedWindowContext: TargetWindowContext { get set }
}
