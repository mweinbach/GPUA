// Ported from: crates/rune/src/platform/macos/appearance.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Guards `effectiveAppearance` KVO observers against transient `NSNull` values when AppKit
//! rebuilds a window's frame view (e.g. ReplayKit / ScreenCaptureKit calling `setStyleMask:`).

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime

private let macAppearanceLock = LiveLock()
// PORT NOTE: Guarded by `macAppearanceLock`, matching `ORIGINAL: AtomicUsize` in `appearance.rs`.
nonisolated(unsafe) private var macOriginalAppearanceObserver: IMP? = nil
// PORT NOTE: Static address used as Objective-C associated-object key, matching `LAST_APPEARANCE` in `appearance.rs`.
nonisolated(unsafe) private var macLastAppearanceAssocKey: UInt8 = 0

private let macObserveAppearanceImp: @convention(c) (
    AnyObject,
    Selector,
    AnyObject?,
    AnyObject?,
    AnyObject?,
    UnsafeMutableRawPointer?
) -> Void = { receiver, cmd, keyPath, window, change, context in
    guard let origImp = macAppearanceLock.withLock({ macOriginalAppearanceObserver }) else { return }
    typealias ObserveFn = @convention(c) (
        AnyObject,
        Selector,
        AnyObject?,
        AnyObject?,
        AnyObject?,
        UnsafeMutableRawPointer?
    ) -> Void
    let original = unsafeBitCast(origImp, to: ObserveFn.self)

    guard let keyPathStr = keyPath as? String,
          keyPathStr == "effectiveAppearance",
          let window,
          let dict = change as? NSDictionary
    else {
        original(receiver, cmd, keyPath, window, change, context)
        return
    }

    let oldVal = dict[NSKeyValueChangeKey.oldKey] as AnyObject?
    let newVal = dict[NSKeyValueChangeKey.newKey] as AnyObject?
    let oldIsAppearance = oldVal is NSAppearance
    let newIsAppearance = newVal is NSAppearance

    switch (oldIsAppearance, newIsAppearance) {
    case (true, true):
        withUnsafePointer(to: &macLastAppearanceAssocKey) { keyPtr in
            objc_setAssociatedObject(window, keyPtr, newVal, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        original(receiver, cmd, keyPath, window, change, context)
    case (let oldKnown, false):
        if oldKnown {
            withUnsafePointer(to: &macLastAppearanceAssocKey) { keyPtr in
                objc_setAssociatedObject(window, keyPtr, oldVal, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    case (false, true):
        let last = withUnsafePointer(to: &macLastAppearanceAssocKey) { keyPtr in
            objc_getAssociatedObject(window, keyPtr) as AnyObject?
        }
        let patched = NSMutableDictionary(dictionary: dict)
        patched[NSKeyValueChangeKey.oldKey] = last ?? newVal!
        withUnsafePointer(to: &macLastAppearanceAssocKey) { keyPtr in
            objc_setAssociatedObject(window, keyPtr, newVal, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        original(receiver, cmd, keyPath, window, patched, context)
    }
}

/// Installs the `effectiveAppearance` KVO nil-transition guard once per process if a
/// `WinitWindowDelegate` class is present.
public func macAppearanceInstall() {
    let alreadyInstalled = macAppearanceLock.withLock { macOriginalAppearanceObserver != nil }
    if alreadyInstalled { return }
    guard let delegateClass = objc_getClass("WinitWindowDelegate") as? AnyClass,
          let objectClass = objc_getClass("NSObject") as? AnyClass
    else {
        return
    }
    let selector = NSSelectorFromString("observeValueForKeyPath:ofObject:change:context:")
    guard let method = class_getInstanceMethod(delegateClass, selector),
          method != class_getInstanceMethod(objectClass, selector)
    else {
        return
    }
    let replacement = unsafeBitCast(macObserveAppearanceImp, to: IMP.self)
    macAppearanceLock.withLock {
        if macOriginalAppearanceObserver == nil {
            macOriginalAppearanceObserver = method_getImplementation(method)
            _ = method_setImplementation(method, replacement)
        }
    }
}
#endif
