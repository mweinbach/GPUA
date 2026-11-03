// Ported from: crates/rune/src/platform/macos/traffic_lights.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The traffic lights at the app's own spot (`Chrome.trafficLights`).

#if os(macOS)
import AppKit
import Foundation
import ObjectiveC.runtime

// PORT NOTE: Main-thread map of window addresses to traffic-light `(x, y)` spots, matching `SPOTS` and `PLACING` in `traffic_lights.rs`.
nonisolated(unsafe) private var macTrafficLightSpots: [UInt: (CGFloat, CGFloat)] = [:]
// PORT NOTE: Main-thread re-entrancy guard while setting button/container frames during `-layout`.
nonisolated(unsafe) private var macTrafficLightsPlacing: Bool = false

/// Drops its window's spot when the window goes, so a later window at the same address
/// doesn't inherit it.
final class MacTrafficLightSpot: Sendable {
    private let key: UInt

    init(window: NSWindow?) {
        if let window {
            self.key = UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque())
        } else {
            self.key = 0
        }
    }

    deinit {
        if key != 0 && Thread.isMainThread {
            macTrafficLightSpots.removeValue(forKey: key)
        }
    }
}

/// Electron's `trafficLightPosition`: the titlebar container grows to the buttons' height
/// plus twice `y`, and the buttons sit `x, y` from the top-left at AppKit's own pitch.
@MainActor
func macPlaceTrafficLights(window: NSWindow, spot: (Float, Float)) {
    let key = UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque())
    let cgSpot = (CGFloat(spot.0), CGFloat(spot.1))
    macTrafficLightSpots[key] = cgSpot
    macPlaceTrafficLightsIn(window: window, spot: cgSpot)
}

@MainActor
private func macPlaceTrafficLightsIn(window: NSWindow, spot: (CGFloat, CGFloat)) {
    if window.styleMask.contains(.fullScreen) {
        return
    }
    guard let close = window.standardWindowButton(.closeButton),
          let mini = window.standardWindowButton(.miniaturizeButton),
          let zoom = window.standardWindowButton(.zoomButton),
          let parent = close.superview,
          let container = parent.superview
    else {
        return
    }
    macHoldTrafficLightView(parent)
    macHoldTrafficLightView(container)
    if macTrafficLightsPlacing {
        return
    }
    macTrafficLightsPlacing = true
    defer { macTrafficLightsPlacing = false }

    let (x, y) = spot
    let pitch = mini.frame.origin.x - close.frame.origin.x
    var frame = container.frame
    frame.size.height = close.frame.size.height + 2.0 * y
    frame.origin.y = window.frame.size.height - frame.size.height
    container.frame = frame
    for (i, b) in [close, mini, zoom].enumerated() {
        b.setFrameOrigin(NSPoint(x: x + CGFloat(i) * pitch, y: y))
    }
}

private func macHeldTrafficLightClass(_ view: NSView) -> AnyClass? {
    var current: AnyClass? = object_getClass(view)
    while let cls = current {
        let name = String(cString: class_getName(cls))
        if name.hasPrefix("RuneTrafficLights_") {
            return cls
        }
        current = class_getSuperclass(cls)
    }
    return nil
}

private let macTrafficLightLayoutImp: @convention(c) (NSView, Selector) -> Void = { view, cmd in
    if let held = macHeldTrafficLightClass(view),
       let base = class_getSuperclass(held),
       let method = class_getInstanceMethod(base, cmd)
    {
        typealias LayoutFn = @convention(c) (NSView, Selector) -> Void
        let imp = method_getImplementation(method)
        let fn = unsafeBitCast(imp, to: LayoutFn.self)
        fn(view, cmd)
    }
    if macTrafficLightsPlacing || !Thread.isMainThread {
        return
    }
    MainActor.assumeIsolated {
        guard let win = view.window else { return }
        let key = UInt(bitPattern: Unmanaged.passUnretained(win).toOpaque())
        guard let spot = macTrafficLightSpots[key] else { return }
        macPlaceTrafficLightsIn(window: win, spot: spot)
    }
}

@MainActor
private func macHoldTrafficLightView(_ view: NSView) {
    if macHeldTrafficLightClass(view) != nil {
        return
    }
    guard let base: AnyClass = object_getClass(view) else { return }
    let baseName = String(cString: class_getName(base))
    let subName = "RuneTrafficLights_\(baseName)"
    let subclass: AnyClass
    if let existing = objc_getClass(subName) as? AnyClass {
        subclass = existing
    } else {
        guard let allocated = objc_allocateClassPair(base, subName, 0) else { return }
        let sel = NSSelectorFromString("layout")
        let imp = unsafeBitCast(macTrafficLightLayoutImp, to: IMP.self)
        _ = "v@:".withCString { class_addMethod(allocated, sel, imp, $0) }
        objc_registerClassPair(allocated)
        subclass = allocated
    }
    object_setClass(view, subclass)
}
#endif
