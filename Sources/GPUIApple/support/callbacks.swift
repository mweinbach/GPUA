// Ported from: crates/gpui_apple/src/support/callbacks.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Standard ivar / associated-object key name used to store callback bridge pointers on Objective-C helper objects.
public let callbackIvar: String = "callbackPtr"

/// Upstream constant alias (`gpui_apple::support::callbacks::CALLBACK_IVAR`).
public let CALLBACK_IVAR: String = callbackIvar

/// Reference-counted box for storing a Swift callback closure on an Objective-C helper object.
public final class AppleCallbackBox<Closure> {
    public let closure: Closure

    public init(_ closure: Closure) {
        self.closure = closure
    }

    public func store(on object: AnyObject, key: String = callbackIvar) {
        setIvar(object: object, name: key, value: self)
    }

    public static func load(from object: AnyObject, key: String = callbackIvar) -> AppleCallbackBox<Closure>? {
        getIvar(object: object, name: key)
    }
}
#endif
