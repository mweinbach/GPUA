// Ported from: crates/rune/src/platform/macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! AppKit activation policy, overlay windows, and visibility without activation.

#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import QuartzCore

private let macOcclusionVisibleBit: UInt = 1 << 1

@MainActor
final class RuneOverlayPanel: NSPanel {
    var allowsKey: Bool = false
    var warming: Bool = false
    var revealing: Bool = false
    var constrainToScreen: Bool = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override var occlusionState: NSWindow.OcclusionState {
        if warming || revealing {
            return .visible
        }
        return super.occlusionState
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if constrainToScreen {
            return super.constrainFrameRect(frameRect, to: screen)
        }
        return frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        if macBridgeReattach(self) {
            fputs("rune: panel lost its view; reattached on input\n", stderr)
        }
        super.sendEvent(event)
    }
}

/// CoreGraphics queries are thread-safe; snapshot the display before queuing a UI request.
func macPointerDisplay() -> UInt32? {
    guard let event = CGEvent(source: nil) else { return nil }
    let point = event.location
    var id: CGDirectDisplayID = 0
    var count: UInt32 = 0
    let err = CGGetDisplaysWithPoint(point, 1, &id, &count)
    return (err == .success && count > 0) ? id : nil
}

func macDisplayBounds(_ id: UInt32) -> [Double] {
    let r = CGDisplayBounds(id)
    return [Double(r.origin.x), Double(r.origin.y), Double(r.size.width), Double(r.size.height)]
}

/// The gravity that keeps a layer's contents at the window's top left.
func macTopLeftContentsGravity(contentsFlipped: Bool) -> CALayerContentsGravity {
    contentsFlipped ? .bottomLeft : .topLeft
}

/// Pins a `CALayer` / `CAMetalLayer`'s contents to the window's top left at their own size
/// and tags the layer sRGB so wide-gamut displays color-match it properly.
func macPinLayerContentsTopLeft(_ layer: CALayer) {
    layer.contentsGravity = macTopLeftContentsGravity(contentsFlipped: layer.contentsAreFlipped())
    if let metalLayer = layer as? CAMetalLayer,
       let srgb = CGColorSpace(name: CGColorSpace.sRGB)
    {
        metalLayer.colorspace = srgb
    }
}

func macContainsAppkitRect(_ r: NSRect, _ pointer: NSPoint) -> Bool {
    pointer.x >= r.origin.x
        && pointer.x < r.origin.x + r.size.width
        && pointer.y > r.origin.y
        && pointer.y <= r.origin.y + r.size.height
}

@MainActor
func macScreenId(_ screen: NSScreen) -> UInt32 {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

@MainActor
func macOverlayRect(_ at: OverlayPlacementSpec, _ options: OverlayOptions) -> NSRect? {
    macOverlayRectOn(at, options, previous: nil)
}

@MainActor
func macOverlayRectOn(
    _ at: OverlayPlacementSpec,
    _ options: OverlayOptions,
    previous: UInt32?
) -> NSRect? {
    let screens = NSScreen.screens
    guard !screens.isEmpty else { return nil }
    let pointer = NSEvent.mouseLocation
    let matched = screens.first { screen in
        switch options.display {
        case .underPointer:
            return macContainsAppkitRect(screen.frame, pointer)
        case .id(let id):
            if case .macOS(let targetId) = id.nativeId() {
                return macScreenId(screen) == targetId
            }
            return false
        case .native(.macOS(let targetId)):
            return macScreenId(screen) == targetId
        case .native, .primary:
            return false
        }
    } ?? screens.first { screen in
        options.display == .underPointer && previous == macScreenId(screen)
    } ?? screens.first

    guard let screen = matched else { return nil }
    let frame = screen.frame
    let local = overlayLocalRect(
        at,
        options.placement,
        (Float(frame.size.width), Float(frame.size.height))
    )
    let x = local[0]
    let y = local[1]
    let w = local[2]
    let h = local[3]
    return NSRect(
        x: frame.origin.x + CGFloat(x),
        y: frame.origin.y + frame.size.height - CGFloat(y + h),
        width: CGFloat(w),
        height: CGFloat(h)
    )
}

@MainActor
func macPlaceWindow(_ window: NSWindow, size: (Float, Float), request: PlaceRequest) {
    let options = OverlayOptions(placement: request.placement, display: request.display)
    if let rect = macOverlayRect(PlaceRequest.at(size), options), window.frame != rect {
        window.setFrame(rect, display: true)
    }
}

/// A window's outer frame, the visible area of its screen and its backing scale, in
/// top-down global points (AppKit's are bottom-up from the primary screen).
@MainActor
func macWindowGeometry(_ ns: NSWindow) -> ([Float], [Float], Float)? {
    let screens = NSScreen.screens
    guard let primaryHeight = screens.first?.frame.size.height,
          let screen = ns.screen ?? NSScreen.main
    else {
        return nil
    }
    let flip: (NSRect) -> [Float] = { r in
        [
            Float(r.origin.x),
            Float(primaryHeight - r.origin.y - r.size.height),
            Float(r.size.width),
            Float(r.size.height),
        ]
    }
    return (flip(ns.frame), flip(screen.visibleFrame), Float(ns.backingScaleFactor))
}

@MainActor
func macContentOrigin(_ ns: NSWindow) -> (Float, Float)? {
    guard let primaryHeight = NSScreen.screens.first?.frame.size.height else { return nil }
    let r = ns.contentRect(forFrameRect: ns.frame)
    return (Float(r.origin.x), Float(primaryHeight - r.origin.y - r.size.height))
}

@MainActor
func macBackingScale(_ ns: NSWindow) -> Float {
    if ns.isVisible {
        return Float(ns.backingScaleFactor)
    }
    let f = ns.frame
    let screens: [([Double], Double)] = NSScreen.screens.map { s in
        let r = s.frame
        return ([Double(r.origin.x), Double(r.origin.y), Double(r.size.width), Double(r.size.height)], Double(s.backingScaleFactor))
    }
    let scale = overlayScaleUnder(
        [Double(f.origin.x), Double(f.origin.y), Double(f.size.width), Double(f.size.height)],
        screens
    )
    return Float(scale ?? Double(ns.backingScaleFactor))
}

@MainActor
func macOuterSize(_ ns: NSWindow, _ content: (Float, Float)) -> (Float, Float) {
    let frame = ns.frameRect(
        forContentRect: NSRect(x: 0, y: 0, width: CGFloat(content.0), height: CGFloat(content.1))
    )
    return (Float(frame.size.width), Float(frame.size.height))
}

@MainActor
func macSetWindowFrame(_ ns: NSWindow, _ rect: [Float]) {
    guard rect.count >= 4,
          let primaryHeight = NSScreen.screens.first?.frame.size.height
    else {
        return
    }
    let target = NSRect(
        x: CGFloat(rect[0]),
        y: primaryHeight - CGFloat(rect[1]) - CGFloat(rect[3]),
        width: CGFloat(rect[2]),
        height: CGFloat(rect[3])
    )
    if ns.frame != target {
        ns.setFrame(target, display: false)
    }
}

/// Regular (Dock icon and app menu) or accessory (menu-bar only). Called on the main thread.
func macSetDockIconVisible(_ visible: Bool) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        if visible {
            promoteDefaultMenu(app)
            app.setActivationPolicy(.regular)
        } else {
            app.setActivationPolicy(.accessory)
        }
    }
}

@MainActor
func macWindowOccluded(_ window: NSWindow) -> Bool {
    !window.occlusionState.contains(.visible)
}

@MainActor
func macConfigureWindow(_ window: NSWindow, _ options: MacWindowOptions) {
    macAppearanceInstall()
    if let shadow = options.shadowFlag {
        window.hasShadow = shadow
    }
    if let level = options.levelValue {
        window.level = NSWindow.Level(rawValue: level)
    }
    if let bits = options.collectionBehaviorBits {
        window.collectionBehavior = NSWindow.CollectionBehavior(rawValue: bits)
    }
    if let exclude = options.excludeFromCaptureFlag {
        macSetWindowSharing(window, exclude: exclude)
    }
}

@MainActor
func macSetWindowSharing(_ window: NSWindow, exclude: Bool) {
    window.sharingType = exclude ? .none : .readOnly
}

@MainActor
func macShowWithoutFocus(_ window: NSWindow) {
    window.orderFrontRegardless()
}

final class MacOverlayPointerState {
    var input: OverlayInput
    var regions: [[Float]] = []
    var pending: (Float, Float)? = nil
    var captured: Bool = false
    var last: (Float, Float)? = nil
    var inside: Bool = false
    var display: UInt32? = nil
    var follow: Bool
    var clicks: [(Bool, Float, Float)] = []
    var releaseSince: (RuneInstant, (Float, Float))? = nil
    var recoveredRelease: (Float, Float)? = nil
    var cursor: Cursor? = nil

    init(input: OverlayInput = .legacy, follow: Bool = false) {
        self.input = input
        self.follow = follow
    }

    func hit(_ x: Float, _ y: Float) -> Bool {
        if captured { return true }
        switch input {
        case .all:
            return true
        case .regions:
            return regions.contains { overlayContains($0, x, y) }
        case .legacy, .none:
            return false
        }
    }

    func recordClick(_ down: Bool, _ x: Float, _ y: Float) {
        guard hit(x, y) else { return }
        if down {
            captured = true
            releaseSince = nil
        }
        clicks.append((down, x, y))
    }

    func released() {
        captured = clicks.contains { $0.0 }
        releaseSince = nil
    }

    func observeRelease(_ buttons: UInt, _ now: RuneInstant, _ point: (Float, Float)) {
        if !captured || (buttons & 1) != 0 {
            releaseSince = nil
            return
        }
        let queuedUp = clicks.contains { !$0.0 }
        let grace: Duration = queuedUp ? .seconds(2) : .milliseconds(100)
        let since: RuneInstant
        let releasedAt: (Float, Float)
        if let existing = releaseSince {
            since = existing.0
            releasedAt = existing.1
        } else {
            releaseSince = (now, point)
            since = now
            releasedAt = point
        }
        if now.durationSince(since) < grace {
            return
        }
        captured = false
        clicks.removeAll()
        releaseSince = nil
        recoveredRelease = releasedAt
    }

    func viewLost() {
        captured = false
        clicks.removeAll()
        releaseSince = nil
        if let last {
            recoveredRelease = last
        }
    }

    func wanted() -> Bool {
        input != .none || follow || captured || cursor != nil
    }

    @MainActor
    func reapplyCursor(_ panel: NSPanel) {
        guard let cursor else { return }
        let pointer = NSEvent.mouseLocation
        let frame = panel.frame
        let x = Float(pointer.x - frame.origin.x)
        let y = Float(frame.origin.y + frame.size.height - pointer.y)
        let isInside = x >= 0.0 && y >= 0.0 && x < Float(frame.size.width) && y < Float(frame.size.height)
        if isInside && hit(x, y) {
            macSetNsCursor(cursor)
        } else {
            self.cursor = nil
            macSetNsCursor(.default)
        }
    }

    @MainActor
    func observe(_ panel: NSPanel, wake: Waker?) {
        let pointer = NSEvent.mouseLocation
        let buttons = NSEvent.pressedMouseButtons
        let frame = panel.frame
        let x = Float(pointer.x - frame.origin.x)
        let y = Float(frame.origin.y + frame.size.height - pointer.y)
        observeRelease(UInt(buttons), .now(), (x, y))
        let ignore = !hit(x, y)
        if panel.ignoresMouseEvents != ignore {
            panel.ignoresMouseEvents = ignore
        }
        let isInside = x >= 0.0 && y >= 0.0 && x < Float(frame.size.width) && y < Float(frame.size.height)
        let wasInside = inside
        inside = isInside
        var displayChanged = false
        if follow {
            if let screen = NSScreen.screens.first(where: { macContainsAppkitRect($0.frame, pointer) }) {
                let sid = macScreenId(screen)
                if display != sid {
                    display = sid
                    displayChanged = true
                }
            }
        }
        let prevLast = last
        if isInside || wasInside || captured || displayChanged {
            let changed = prevLast.map { $0.0 != x || $0.1 != y } ?? true
            last = (x, y)
            if changed {
                pending = (x, y)
                wake?()
            }
        }
    }
}

// PORT NOTE: Synchronized via `LiveLock` so `@MainActor` monitor lifecycle and `nonisolated deinit` safely drain `NSEvent` monitor tokens.
private final class MacMonitorTokenBox: @unchecked Sendable {
    private let lock = LiveLock()
    private var tokens: [Any] = []

    func append(_ token: Any) {
        lock.withLock { tokens.append(token) }
    }

    var isEmpty: Bool {
        lock.withLock { tokens.isEmpty }
    }

    var count: Int {
        lock.withLock { tokens.count }
    }

    func removeAll() {
        let taken: [Any] = lock.withLock {
            let out = tokens
            tokens.removeAll()
            return out
        }
        for token in taken {
            NSEvent.removeMonitor(token)
        }
    }
}

@MainActor
final class MacOverlayPanelHost {
    let panel: RuneOverlayPanel
    let view: NSView
    let pointer: MacOverlayPointerState
    private var options: OverlayOptions
    private var followPointer: Bool
    private var visible: Bool = false
    private var pointerPoll: RuneInstant? = nil
    private var presence: MacOverlayPresence
    private let monitorBox = MacMonitorTokenBox()
    private let wake: Waker?

    init?(
        contentView: NSView,
        at: OverlayPlacementSpec,
        interactive: Bool,
        options: OverlayOptions,
        wake: Waker?
    ) {
        macAppearanceInstall()
        let rect = NSRect(x: 0, y: 0, width: CGFloat(at.size.0), height: CGFloat(at.size.1))
        let p = RuneOverlayPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.allowsKey = (options.keys == .onDemand)
        p.isReleasedWhenClosed = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = (options.keys == .none)
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
            .canJoinAllApplications,
        ]
        let levelValue: Int
        switch options.level {
        case .status: levelValue = 25
        case .aboveStatus: levelValue = 26
        case .aboveOverlays: levelValue = 27
        }
        macConfigureWindow(p, MacWindowOptions().shadow(false).level(levelValue))
        p.isOpaque = false
        p.ignoresMouseEvents = (options.input.resolved(interactive) != .all)
        p.acceptsMouseMovedEvents = true
        if options.prewarm {
            p.alphaValue = 0.0
            p.ignoresMouseEvents = true
        }
        guard p.windowNumber > 0 else { return nil }
        p.contentView = contentView

        self.panel = p
        self.view = contentView
        self.pointer = MacOverlayPointerState(
            input: options.input.resolved(interactive),
            follow: options.followPointer
        )
        self.options = options
        self.followPointer = options.followPointer
        self.presence = MacOverlayPresence.new(options.excludeFromCapture)
        self.wake = wake
    }

    func windowNumber() -> UInt32 {
        UInt32(max(0, panel.windowNumber))
    }

    func place(_ at: OverlayPlacementSpec, _ options: OverlayOptions) {
        guard let rect = macOverlayRectOn(at, options, previous: panel.screen.map(macScreenId)) else { return }
        if panel.frame != rect {
            panel.setFrame(rect, display: true)
            if visible {
                pointer.observe(panel, wake: wake)
            }
        }
    }

    func occluded() -> Bool {
        macWindowOccluded(panel)
    }

    func show(_ fade: Duration) {
        visible = true
        refreshMonitors()
        pointer.observe(panel, wake: wake)
        let generation = updatePresence { $0.show() }
        let fadeSecs = Double(fade.components.seconds) + Double(fade.components.attoseconds) * 1e-18
        if !options.prewarm && !panel.isVisible {
            if fadeSecs > 0 {
                panel.alphaValue = 0.0
            }
            panel.orderFrontRegardless()
        }
        fadeTo(alpha: 1.0, duration: fadeSecs, orderOut: false, generation: generation)
    }

    func hide(_ fade: Duration) {
        visible = false
        panel.revealing = false
        pointerPoll = nil
        stopMonitors()
        pointer.captured = false
        pointer.pending = nil
        pointer.last = nil
        pointer.inside = false
        pointer.clicks.removeAll()
        pointer.releaseSince = nil
        pointer.recoveredRelease = nil
        setCursor(nil)
        panel.ignoresMouseEvents = true

        let fadeSecs = Double(fade.components.seconds) + Double(fade.components.attoseconds) * 1e-18
        let generation = presence.hide(fadeSecs > 0)
        if options.prewarm {
            fadeTo(alpha: 0.0, duration: fadeSecs, orderOut: false, generation: generation)
            panel.resignKey()
        } else if fadeSecs <= 0 {
            panel.orderOut(nil)
        } else {
            panel.resignKey()
            fadeTo(alpha: 0.0, duration: fadeSecs, orderOut: true, generation: generation)
        }
        macSetWindowSharing(panel, exclude: presence.excluded())
    }

    func setLevel(_ level: Int) {
        panel.level = NSWindow.Level(rawValue: level)
    }

    func captureExclusion() -> OverlaySupport {
        presence.requested() ? .requested : .unknown
    }

    @discardableResult
    func setCaptureExclusion(_ exclude: Bool) -> OverlaySupport {
        updatePresence { $0.request(exclude) }
        return captureExclusion()
    }

    func globalPointer() -> OverlaySupport {
        if (followPointer || pointer.input == .regions) && monitorBox.count != 2 {
            return .failed
        }
        return .supported
    }

    func requestKeys() {
        if options.keys == .onDemand {
            _ = panel.makeFirstResponder(view)
            panel.makeKey()
        }
    }

    func setInput(_ input: OverlayInput) {
        pointer.input = input
        refreshMonitors()
        if visible {
            pointer.observe(panel, wake: wake)
        }
    }

    func setCursor(_ cursor: Cursor?) {
        let was = pointer.cursor
        pointer.cursor = cursor
        if let cursor {
            macSetNsCursor(cursor)
        } else if was != nil {
            macSetNsCursor(.default)
        }
        if (was != nil) != (cursor != nil) {
            refreshMonitors()
        }
    }

    func setFollowPointer(_ follow: Bool) {
        followPointer = follow
        pointer.follow = follow
        refreshMonitors()
    }

    func setRegions(_ regions: [[Float]]) {
        guard pointer.regions != regions else { return }
        pointer.regions = regions
        if visible {
            pointer.observe(panel, wake: nil)
        }
    }

    private func updatePresence<R>(_ change: (inout MacOverlayPresence) -> R) -> R {
        let result = change(&presence)
        macSetWindowSharing(panel, exclude: presence.excluded())
        return result
    }

    private func fadeTo(alpha: CGFloat, duration: Double, orderOut: Bool, generation: UInt64) {
        let hiding = alpha == 0.0
        let fading = duration > 0.0
        panel.revealing = fading
        if fading {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                panel.animator().alphaValue = alpha
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard self.presence.fadeDone(generation, hiding) else { return }
                    self.panel.revealing = false
                    if orderOut {
                        self.panel.orderOut(nil)
                    }
                    if hiding {
                        macSetWindowSharing(self.panel, exclude: self.presence.excluded())
                    }
                }
            })
        } else {
            panel.alphaValue = alpha
            if orderOut {
                panel.orderOut(nil)
            }
        }
    }

    private func needsMonitors() -> Bool {
        followPointer || pointer.input == .regions || pointer.captured || pointer.cursor != nil
    }

    private func refreshMonitors() {
        guard visible else { return }
        if pointer.input == .regions {
            if pointerPoll == nil { pointerPoll = .now() }
        } else {
            pointerPoll = nil
        }
        if needsMonitors() {
            startMonitors()
        } else {
            stopMonitors()
        }
    }

    private func startMonitors() {
        guard monitorBox.isEmpty && needsMonitors() else { return }
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .leftMouseUp,
        ]
        if let globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointer.reapplyCursor(self.panel)
                self.wake?()
            }
        }) {
            monitorBox.append(globalToken)
        }
        if let localToken = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pointer.reapplyCursor(self.panel)
                if (event.type == .leftMouseDown || event.type == .leftMouseUp) && event.window === self.panel {
                    let pt = event.locationInWindow
                    let frame = self.panel.frame
                    let x = Float(pt.x)
                    let y = Float(frame.size.height - pt.y)
                    self.pointer.recordClick(event.type == .leftMouseDown, x, y)
                }
                self.wake?()
            }
            return event
        }) {
            monitorBox.append(localToken)
        }
        pointer.observe(panel, wake: wake)
    }

    private func stopMonitors() {
        monitorBox.removeAll()
    }

    deinit {
        let box = monitorBox
        let p = panel
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                box.removeAll()
                p.delegate = nil
                p.orderOut(nil)
                p.contentView = nil
            }
        }
    }
}
#endif
