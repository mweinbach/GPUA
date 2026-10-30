// Ported from: crates/gpui_apple/src/objc/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

/// Namespace grouping Objective-C runtime helpers matching `gpui_apple::objc`.
public enum AppleObjC {
    public typealias ObjectId = GPUIApple.Id
    public typealias ObjCClass = GPUIApple.Class

    public static func lookupClass(_ name: String) -> ObjCClass? {
        GPUIApple.objcClass(name)
    }

    public static func retain(_ obj: ObjectId) {
        GPUIApple.retain(obj)
    }

    public static func release(_ obj: ObjectId) {
        GPUIApple.release(obj)
    }

    public static func nsString(_ string: String) -> NSString {
        GPUIApple.nsString(string)
    }
}
#endif
