// Ported from: crates/gpui_macros/src/derive_app_context.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Protocol matching upstream `derive(AppContext)` providing context delegation to an underlying AppContext.
public protocol AppContextForwarding {
    associatedtype TargetAppContext
    var forwardedAppContext: TargetAppContext { get set }
}

/// Generic container that forwards context operations.
public struct ContextForwarder<C>: Sendable where C: Sendable {
    public var context: C

    public init(_ context: C) {
        self.context = context
    }
}
