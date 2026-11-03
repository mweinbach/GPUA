// Ported from: crates/rune/src/platform/macos/panel_bridge.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Forwards window readbacks and gated setters from a hidden source `NSWindow` to its adopted
//! `NSPanel`, while keeping foreign framework restyling (e.g. ReplayKit / AppKit) pointed at
//! the source window's own empty content.

#if os(macOS)
import AppKit
import Darwin
import Foundation
import ObjectiveC.runtime

struct MacBridgeSource {
    var view: UInt
    var panel: UInt
    var ordinary: Bool
}

private let macBridgeLock = LiveLock()
// PORT NOTE: Guarded by `macBridgeLock`, matching `WINDOWS`, `VIEWS`, `LOST`, `REATTACHED`, and `INSTALLED` in `panel_bridge.rs`.
nonisolated(unsafe) private var macBridgeWindows: [UInt: MacBridgeSource] = [:]
// PORT NOTE: Guarded by `macBridgeLock`.
nonisolated(unsafe) private var macBridgeViews: [UInt: MacOverlayPointerState] = [:]
// PORT NOTE: Guarded by `macBridgeLock`.
nonisolated(unsafe) private var macBridgeLostPanels: Set<UInt> = []
// PORT NOTE: Guarded by `macBridgeLock`.
nonisolated(unsafe) private var macBridgeReattachedTotal: Int = 0
// PORT NOTE: Guarded by `macBridgeLock` (`(classPtr, superclassPtr)`).
nonisolated(unsafe) private var macBridgeInstalledClasses: [(UInt, UInt)] = []

private func macBridgeSource(_ window: AnyObject) -> MacBridgeSource? {
    let key = UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque())
    return macBridgeLock.withLock { macBridgeWindows[key] }
}

private func macBridgePanel(_ window: AnyObject, ordinaryOnly: Bool) -> AnyObject? {
    guard let src = macBridgeSource(window), (src.ordinary || !ordinaryOnly),
          let ptr = UnsafeRawPointer(bitPattern: src.panel)
    else {
        return nil
    }
    return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
}

private func macBridgeBaseClass(_ object: AnyObject) -> AnyClass? {
    let installed = macBridgeLock.withLock { macBridgeInstalledClasses }
    var current: AnyClass? = object_getClass(object)
    while let cls = current {
        let clsAddr = UInt(bitPattern: ObjectIdentifier(cls))
        if let (_, parentAddr) = installed.first(where: { $0.0 == clsAddr }),
           let parentPtr = UnsafeRawPointer(bitPattern: parentAddr)
        {
            return unsafeBitCast(parentPtr, to: AnyClass.self)
        }
        current = class_getSuperclass(cls)
    }
    return nil
}

private func macBridgeSuperImp(_ object: AnyObject, _ cmd: Selector) -> IMP? {
    guard let base = macBridgeBaseClass(object),
          let method = class_getInstanceMethod(base, cmd)
    else {
        return nil
    }
    return method_getImplementation(method)
}

// PORT NOTE: Inspects `Thread.callStackReturnAddresses` with `dladdr` instead of inline `naked_asm!`.
// Direct callers in Rune / host app binaries reside outside `/System/Library/` and `/usr/lib/`, whereas
// AppKit, ReplayKit, and CoreFoundation (`NSInvocation`) originate from system frameworks.
private func macBridgeFromRune() -> Bool {
    let selfImageBase: UnsafeMutableRawPointer? = {
        var info = Dl_info()
        let sym = unsafeBitCast(macBridgeContentViewImp, to: UnsafeRawPointer.self)
        guard dladdr(sym, &info) != 0 else { return nil }
        return info.dli_fbase
    }()

    for num in Thread.callStackReturnAddresses.dropFirst() {
        guard let ptr = UnsafeRawPointer(bitPattern: num.uintValue) else { continue }
        var info = Dl_info()
        guard dladdr(ptr, &info) != 0, let fnamePtr = info.dli_fname else { continue }
        if info.dli_fbase == selfImageBase {
            if let snamePtr = info.dli_sname {
                let sname = String(cString: snamePtr)
                if sname.contains("macBridge") {
                    continue
                }
            }
            return true
        }
        let path = String(cString: fnamePtr)
        if path.contains("libobjc.") || path.contains("libswift") {
            continue
        }
        if path.hasPrefix("/System/Library/") || path.hasPrefix("/usr/lib/") {
            return false
        }
        return true
    }
    return false
}

private let macBridgeContentViewImp: @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer? = { window, cmd in
    if let src = macBridgeSource(window), macBridgeFromRune() {
        return UnsafeMutableRawPointer(bitPattern: src.view)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return nil }
    typealias Fn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeVisibleImp: @convention(c) (AnyObject, Selector) -> ObjCBool = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: false),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeOcclusionImp: @convention(c) (AnyObject, Selector) -> UInt = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: false),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return 0 }
    typealias Fn = @convention(c) (AnyObject, Selector) -> UInt
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeScaleImp: @convention(c) (AnyObject, Selector) -> CGFloat = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: false),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> CGFloat
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return 1.0 }
    typealias Fn = @convention(c) (AnyObject, Selector) -> CGFloat
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeScreenImp: @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer? = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: false),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return nil }
    typealias Fn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeInvalidateCursorRectsImp: @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void = { window, cmd, view in
    if let panel = macBridgePanel(window, ordinaryOnly: false),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, view)
        return
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return }
    typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
    unsafeBitCast(imp, to: Fn.self)(window, cmd, view)
}

private let macBridgeFrameImp: @convention(c) (AnyObject, Selector) -> NSRect = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: true),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> NSRect
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return .zero }
    typealias Fn = @convention(c) (AnyObject, Selector) -> NSRect
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeKeyImp: @convention(c) (AnyObject, Selector) -> ObjCBool = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: true),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeLiveResizeImp: @convention(c) (AnyObject, Selector) -> ObjCBool = { window, cmd in
    if let panel = macBridgePanel(window, ordinaryOnly: true),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
        return unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd)
    }
    guard let imp = macBridgeSuperImp(window, cmd) else { return false }
    typealias Fn = @convention(c) (AnyObject, Selector) -> ObjCBool
    return unsafeBitCast(imp, to: Fn.self)(window, cmd)
}

private let macBridgeSetTitleImp: @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void = { window, cmd, title in
    if let panel = macBridgePanel(window, ordinaryOnly: true),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, title)
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, title)
    }
}

private let macBridgeSetFrameImp: @convention(c) (AnyObject, Selector, NSRect, ObjCBool) -> Void = { window, cmd, rect, display in
    if let panel = macBridgePanel(window, ordinaryOnly: true), macBridgeFromRune(),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, NSRect, ObjCBool) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, rect, display)
        return
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSRect, ObjCBool) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, rect, display)
    }
}

private let macBridgeSetOriginImp: @convention(c) (AnyObject, Selector, NSPoint) -> Void = { window, cmd, point in
    if let panel = macBridgePanel(window, ordinaryOnly: true), macBridgeFromRune(),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, NSPoint) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, point)
        return
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSPoint) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, point)
    }
}

private let macBridgeSetSizeImp: @convention(c) (AnyObject, Selector, NSSize) -> Void = { window, cmd, size in
    if let panel = macBridgePanel(window, ordinaryOnly: true), macBridgeFromRune(),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, NSSize) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, size)
        return
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, NSSize) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, size)
    }
}

private let macBridgeSetLevelImp: @convention(c) (AnyObject, Selector, Int) -> Void = { window, cmd, level in
    if let panel = macBridgePanel(window, ordinaryOnly: true), macBridgeFromRune(),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, level)
        return
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, Int) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, level)
    }
}

private let macBridgeSetHitImp: @convention(c) (AnyObject, Selector, ObjCBool) -> Void = { window, cmd, ignore in
    if let panel = macBridgePanel(window, ordinaryOnly: true), macBridgeFromRune(),
       let cls = object_getClass(panel),
       let m = class_getInstanceMethod(cls, cmd)
    {
        typealias Fn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(method_getImplementation(m), to: Fn.self)(panel, cmd, ignore)
        return
    }
    if let imp = macBridgeSuperImp(window, cmd) {
        typealias Fn = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(imp, to: Fn.self)(window, cmd, ignore)
    }
}

private let macBridgeHitTestImp: @convention(c) (NSView, Selector, NSPoint) -> UnsafeMutableRawPointer? = { view, cmd, point in
    let key = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
    let state = macBridgeLock.withLock { macBridgeViews[key] }
    if let state, Thread.isMainThread {
        let hit = MainActor.assumeIsolated { () -> Bool in
            let local = view.convert(point, from: view.superview)
            let bounds = view.bounds
            let y = view.isFlipped
                ? (local.y - bounds.origin.y)
                : (bounds.origin.y + bounds.size.height - local.y)
            return state.hit(Float(local.x - bounds.origin.x), Float(y))
        }
        if !hit {
            return nil
        }
    }
    guard let imp = macBridgeSuperImp(view, cmd) else { return nil }
    typealias Fn = @convention(c) (NSView, Selector, NSPoint) -> UnsafeMutableRawPointer?
    return unsafeBitCast(imp, to: Fn.self)(view, cmd, point)
}

func macBridgeWindowForwards() -> [(Selector, IMP)] {
    [
        (NSSelectorFromString("contentView"), unsafeBitCast(macBridgeContentViewImp, to: IMP.self)),
        (NSSelectorFromString("isVisible"), unsafeBitCast(macBridgeVisibleImp, to: IMP.self)),
        (NSSelectorFromString("occlusionState"), unsafeBitCast(macBridgeOcclusionImp, to: IMP.self)),
        (NSSelectorFromString("backingScaleFactor"), unsafeBitCast(macBridgeScaleImp, to: IMP.self)),
        (NSSelectorFromString("screen"), unsafeBitCast(macBridgeScreenImp, to: IMP.self)),
        (NSSelectorFromString("invalidateCursorRectsForView:"), unsafeBitCast(macBridgeInvalidateCursorRectsImp, to: IMP.self)),
        (NSSelectorFromString("frame"), unsafeBitCast(macBridgeFrameImp, to: IMP.self)),
        (NSSelectorFromString("isKeyWindow"), unsafeBitCast(macBridgeKeyImp, to: IMP.self)),
        (NSSelectorFromString("inLiveResize"), unsafeBitCast(macBridgeLiveResizeImp, to: IMP.self)),
        (NSSelectorFromString("setFrame:display:"), unsafeBitCast(macBridgeSetFrameImp, to: IMP.self)),
        (NSSelectorFromString("setFrameOrigin:"), unsafeBitCast(macBridgeSetOriginImp, to: IMP.self)),
        (NSSelectorFromString("setContentSize:"), unsafeBitCast(macBridgeSetSizeImp, to: IMP.self)),
        (NSSelectorFromString("setTitle:"), unsafeBitCast(macBridgeSetTitleImp, to: IMP.self)),
        (NSSelectorFromString("setLevel:"), unsafeBitCast(macBridgeSetLevelImp, to: IMP.self)),
        (NSSelectorFromString("setIgnoresMouseEvents:"), unsafeBitCast(macBridgeSetHitImp, to: IMP.self)),
    ]
}

func macBridgeInstall(
    cls: AnyClass,
    appkit: AnyClass,
    methods: [(Selector, IMP)]
) -> Bool {
    let key = UInt(bitPattern: ObjectIdentifier(cls))
    return macBridgeLock.withLock {
        if macBridgeInstalledClasses.contains(where: { $0.0 == key }) {
            return true
        }
        if cls === appkit {
            return false
        }
        guard let parent = class_getSuperclass(cls) else {
            return false
        }
        for (selector, _) in methods {
            guard let m = class_getInstanceMethod(cls, selector),
                  m == class_getInstanceMethod(parent, selector)
            else {
                return false
            }
        }
        let parentAddr = UInt(bitPattern: ObjectIdentifier(parent))
        macBridgeInstalledClasses.append((key, parentAddr))
        for (selector, imp) in methods {
            guard let m = class_getInstanceMethod(cls, selector),
                  let types = method_getTypeEncoding(m)
            else {
                return false
            }
            if !class_addMethod(cls, selector, imp, types) {
                return false
            }
        }
        return true
    }
}

func macBridgeInsertForTests(window: UInt, view: UInt, panel: UInt, ordinary: Bool) {
    macBridgeLock.withLock {
        macBridgeWindows[window] = MacBridgeSource(view: view, panel: panel, ordinary: ordinary)
    }
}

func macBridgeRemoveForTests(window: UInt) {
    macBridgeLock.withLock {
        _ = macBridgeWindows.removeValue(forKey: window)
    }
}

/// Returns `view` to `panel` if anything took it, and reports whether it had to.
@MainActor
func macBridgeReattach(_ panel: NSPanel) -> Bool {
    let panelKey = UInt(bitPattern: Unmanaged.passUnretained(panel).toOpaque())
    let found = macBridgeLock.withLock { () -> (UInt, MacBridgeSource)? in
        guard let pair = macBridgeWindows.first(where: { $0.value.panel == panelKey }) else { return nil }
        return (pair.key, pair.value)
    }
    guard let (sourceAddr, entry) = found,
          let viewPtr = UnsafeRawPointer(bitPattern: entry.view),
          let sourcePtr = UnsafeRawPointer(bitPattern: sourceAddr)
    else {
        return false
    }
    let view = Unmanaged<NSView>.fromOpaque(viewPtr).takeUnretainedValue()
    let source = Unmanaged<NSWindow>.fromOpaque(sourcePtr).takeUnretainedValue()
    if panel.contentView === view && view.window === panel {
        return false
    }
    if let superImp = macBridgeSuperImp(source, NSSelectorFromString("contentView")) {
        typealias Fn = @convention(c) (AnyObject, Selector) -> UnsafeMutableRawPointer?
        let realContent = unsafeBitCast(superImp, to: Fn.self)(source, NSSelectorFromString("contentView"))
        if realContent == UnsafeMutableRawPointer(bitPattern: entry.view) {
            source.contentView = nil
        }
    }
    view.removeFromSuperview()
    if panel.contentView === view {
        panel.contentView = nil
    }
    panel.contentView = view
    if panel.isKeyWindow {
        _ = panel.makeFirstResponder(view)
    }
    macBridgeLock.withLock {
        macBridgeReattachedTotal += 1
        macBridgeLostPanels.insert(panelKey)
    }
    return true
}

func macBridgeTakeReattached(_ panel: NSPanel) -> Bool {
    let panelKey = UInt(bitPattern: Unmanaged.passUnretained(panel).toOpaque())
    return macBridgeLock.withLock {
        macBridgeLostPanels.remove(panelKey) != nil
    }
}

/// How many times a panel has had to take its view back. Tests assert the view was never taken.
public func macPanelBridgeReattachCount() -> Int {
    macBridgeLock.withLock { macBridgeReattachedTotal }
}

final class MacPanelBridge {
    private let sourceAddr: UInt
    private let viewAddr: UInt?

    private init(sourceAddr: UInt, viewAddr: UInt?) {
        self.sourceAddr = sourceAddr
        self.viewAddr = viewAddr
    }

    @MainActor
    static func new(
        source: NSWindow,
        panel: NSPanel,
        view: NSView,
        filter: MacOverlayPointerState?
    ) -> MacPanelBridge? {
        newKind(source: source, panel: panel, view: view, filter: filter, ordinary: false)
    }

    @MainActor
    static func newWindow(
        source: NSWindow,
        panel: NSPanel,
        view: NSView
    ) -> MacPanelBridge? {
        newKind(source: source, panel: panel, view: view, filter: nil, ordinary: true)
    }

    @MainActor
    private static func newKind(
        source: NSWindow,
        panel: NSPanel,
        view: NSView,
        filter: MacOverlayPointerState?,
        ordinary: Bool
    ) -> MacPanelBridge? {
        let winClass: AnyClass = type(of: source)
        guard macBridgeInstall(cls: winClass, appkit: NSWindow.self, methods: macBridgeWindowForwards()) else {
            return nil
        }
        if filter != nil {
            let vClass: AnyClass = type(of: view)
            let hitMethods = [(NSSelectorFromString("hitTest:"), unsafeBitCast(macBridgeHitTestImp, to: IMP.self))]
            guard macBridgeInstall(cls: vClass, appkit: NSView.self, methods: hitMethods) else {
                return nil
            }
        }
        let sAddr = UInt(bitPattern: Unmanaged.passUnretained(source).toOpaque())
        let pAddr = UInt(bitPattern: Unmanaged.passUnretained(panel).toOpaque())
        let vAddr = UInt(bitPattern: Unmanaged.passUnretained(view).toOpaque())
        macBridgeLock.withLock {
            macBridgeWindows[sAddr] = MacBridgeSource(view: vAddr, panel: pAddr, ordinary: ordinary)
            if let filter {
                macBridgeViews[vAddr] = filter
            }
        }
        return MacPanelBridge(sourceAddr: sAddr, viewAddr: filter != nil ? vAddr : nil)
    }

    deinit {
        macBridgeLock.withLock {
            if let entry = macBridgeWindows.removeValue(forKey: sourceAddr) {
                macBridgeLostPanels.remove(entry.panel)
            }
            if let vAddr = viewAddr {
                _ = macBridgeViews.removeValue(forKey: vAddr)
            }
        }
    }
}
#endif
