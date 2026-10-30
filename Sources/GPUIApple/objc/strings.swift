// Ported from: crates/gpui_apple/src/objc/strings.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Bridges a Swift `String` to an `NSString` instance for Objective-C host APIs.
public func nsString(_ string: String) -> NSString {
    let bridged = NSString(string: string)
    return bridged
}

/// Returns an unretained Objective-C `Id` pointer for an `NSString` bridged from `string`.
public func nsStringId(_ string: String) -> Id {
    let bridged = NSString(string: string)
    return Unmanaged.passUnretained(bridged).toOpaque()
}
#endif
