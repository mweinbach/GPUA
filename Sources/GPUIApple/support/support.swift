// Ported from: crates/gpui_apple/src/support/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Shared support namespace for hosted Apple view attachment, callback, and lifetime utilities.
public enum AppleSupport {
    public static var callbackKey: String { callbackIvar }

    public static func attach(_ parent: Id, _ child: Id) {
        attachSubview(parent, child)
    }

    public static func detach(_ child: Id) {
        detachFromParent(child)
    }
}
#endif
