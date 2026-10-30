// Ported from: crates/gpui_apple/src/support/lifetime.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Scoped retain/release handle managing an Objective-C `Id` across hosted backend boundaries.
// PORT NOTE: Wraps an opaque retained Objective-C object pointer with explicit ARC-style
// `deinit` release, matching upstream `gpui_apple::support::lifetime::{id, retain, release}`.
public final class AppleObjectLifetime: @unchecked Sendable {
    public private(set) var ptr: Id

    public init(retaining obj: Id) {
        GPUIApple.retain(obj)
        self.ptr = obj
    }

    public init(adoptingRetained obj: Id) {
        self.ptr = obj
    }

    deinit {
        if let current = ptr {
            GPUIApple.release(current)
        }
    }
}
#endif
