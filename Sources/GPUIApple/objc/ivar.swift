// Ported from: crates/gpui_apple/src/objc/ivar.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC

// PORT NOTE: Interns associated-object keys per ivar name under `NSLock` so Swift/Objective-C
// helper objects can store and retrieve typed values without unsafe manual ivar layout math,
// while also supporting genuine dynamically registered Objective-C ivars when present.
private enum IvarKeyRegistry {
    private static let lock = NSLock()
    // PORT NOTE: Protected exclusively by `IvarKeyRegistry.lock`; pointers remain stable for process lifetime.
    nonisolated(unsafe) private static var keysByName: [String: UnsafeRawPointer] = [:]

    static func key(for name: String) -> UnsafeRawPointer {
        lock.lock()
        defer { lock.unlock() }
        if let existing = keysByName[name] {
            return existing
        }
        let allocated = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        allocated.initialize(to: 0)
        let raw = UnsafeRawPointer(allocated)
        keysByName[name] = raw
        return raw
    }
}

private final class AssociatedValueBox<T> {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

/// Reads a stored value or Objective-C ivar from `obj`.
public func getIvar<T>(_ obj: Id, _ name: String) -> T {
    guard let ptr = obj else {
        preconditionFailure("Attempted to read ivar '\(name)' from nil Objective-C object")
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    if let value: T = getIvar(object: object, name: name) {
        return value
    }
    preconditionFailure("Missing or mismatched ivar '\(name)' of type \(T.self)")
}

/// Writes a value or Objective-C ivar on `obj`.
public func setIvar<T>(_ obj: Id, _ name: String, _ value: T) {
    guard let ptr = obj else {
        return
    }
    let object = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    setIvar(object: object, name: name, value: value)
}

/// Safe Swift overload reading an associated or dynamic ivar value from an `AnyObject`.
public func getIvar<T>(object: AnyObject, name: String) -> T? {
    let key = IvarKeyRegistry.key(for: name)
    if let box = objc_getAssociatedObject(object, key) as? AssociatedValueBox<T> {
        return box.value
    }
    if let cls = object_getClass(object),
       let ivar = name.withCString({ class_getInstanceVariable(cls, $0) }),
       _isPOD(T.self) {
        let offset = ivar_getOffset(ivar)
        let base = Unmanaged.passUnretained(object).toOpaque()
        return base.advanced(by: offset).assumingMemoryBound(to: T.self).pointee
    }
    return nil
}

/// Safe Swift overload writing an associated or dynamic ivar value onto an `AnyObject`.
public func setIvar<T>(object: AnyObject, name: String, value: T) {
    if let cls = object_getClass(object),
       let ivar = name.withCString({ class_getInstanceVariable(cls, $0) }),
       _isPOD(T.self) {
        let offset = ivar_getOffset(ivar)
        let base = Unmanaged.passUnretained(object).toOpaque()
        base.advanced(by: offset).assumingMemoryBound(to: T.self).pointee = value
    }
    let key = IvarKeyRegistry.key(for: name)
    objc_setAssociatedObject(
        object,
        key,
        AssociatedValueBox(value),
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
}
#endif
