// Ported from: crates/gpui_apple/src/support/attach.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if canImport(ObjectiveC)
import Foundation
import ObjectiveC
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// View attachment helpers shared by AppKit and UIKit hosted-view backends.
public enum AppleSupportAttach {
    public typealias Id = GPUIApple.Id
}

/// Attaches `child` as a subview of `parent` for the active Apple platform framework.
public func attachSubview(_ parent: Id, _ child: Id) {
    guard let parentPtr = parent, let childPtr = child else { return }
    let parentObj = Unmanaged<AnyObject>.fromOpaque(parentPtr).takeUnretainedValue()
    let childObj = Unmanaged<AnyObject>.fromOpaque(childPtr).takeUnretainedValue()

    #if os(macOS)
    if let parentView = parentObj as? NSView, let childView = childObj as? NSView {
        MainActor.assumeIsolated {
            parentView.addSubview(childView)
        }
    }
    #elseif canImport(UIKit)
    if let parentView = parentObj as? UIView, let childView = childObj as? UIView {
        MainActor.assumeIsolated {
            parentView.addSubview(childView)
        }
    }
    #endif
}

/// Detaches `child` from its current superview.
public func detachFromParent(_ child: Id) {
    guard let childPtr = child else { return }
    let childObj = Unmanaged<AnyObject>.fromOpaque(childPtr).takeUnretainedValue()

    #if os(macOS)
    if let childView = childObj as? NSView {
        MainActor.assumeIsolated {
            childView.removeFromSuperview()
        }
    }
    #elseif canImport(UIKit)
    if let childView = childObj as? UIView {
        MainActor.assumeIsolated {
            childView.removeFromSuperview()
        }
    }
    #endif
}

#if os(macOS)
/// Typed AppKit overload attaching `child` to `parent`.
@MainActor
public func attachSubview(_ parent: NSView, _ child: NSView) {
    parent.addSubview(child)
}

/// Typed AppKit overload detaching `child` from its superview.
@MainActor
public func detachFromParent(_ child: NSView) {
    child.removeFromSuperview()
}
#elseif canImport(UIKit)
/// Typed UIKit overload attaching `child` to `parent`.
@MainActor
public func attachSubview(_ parent: UIView, _ child: UIView) {
    parent.addSubview(child)
}

/// Typed UIKit overload detaching `child` from its superview.
@MainActor
public func detachFromParent(_ child: UIView) {
    child.removeFromSuperview()
}
#endif
#endif
