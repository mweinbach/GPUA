// Ported from: crates/gpui_apple/src/objc/memory.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import ObjectiveC

/// Untyped Objective-C object pointer matching upstream `gpui_apple::objc::memory::id`.
public typealias Id = UnsafeMutableRawPointer?

/// Retains an Objective-C object pointer if non-nil.
public func retain(_ obj: Id) {
    guard let ptr = obj else { return }
    _ = Unmanaged<AnyObject>.fromOpaque(ptr).retain()
}

/// Releases an Objective-C object pointer if non-nil.
public func release(_ obj: Id) {
    guard let ptr = obj else { return }
    Unmanaged<AnyObject>.fromOpaque(ptr).release()
}

/// Retains a Swift/Objective-C object and returns an opaque pointer with +1 retain count.
public func retainObject(_ object: AnyObject) -> UnsafeMutableRawPointer {
    Unmanaged.passRetained(object).toOpaque()
}
#endif
