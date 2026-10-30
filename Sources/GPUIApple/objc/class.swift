// Ported from: crates/gpui_apple/src/objc/class.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Objective-C runtime `Class` type alias matching upstream `objc::runtime::Class`.
public typealias Class = AnyClass

/// Looks up a registered Objective-C class by name.
public func objcClass(_ name: String) -> Class? {
    let resolved: AnyClass? = NSClassFromString(name)
    return resolved
}

/// Upstream parity alias for `objc::class!`.
public func `class`(_ name: String) -> Class? {
    objcClass(name)
}
#endif
