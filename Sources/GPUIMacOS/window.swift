// Ported from: crates/gpui_macos/src/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import GPUI
import GPUIMetal
import QuartzCore

/// User preference for native macOS window tabbing (`AppleWindowTabbingMode`).
public enum UserTabbingPreference: Sendable, Equatable {
    case never
    case always
    case inFullScreen
}

/// Checks whether the running macOS version is at least `version`.
func isMacosVersionAtLeast(_ version: OperatingSystemVersion) -> Bool {
    ProcessInfo.processInfo.isOperatingSystemAtLeast(version)
}

/// Returns true for shortcuts that AppKit `NSTextView` field editors handle natively
/// (Copy, Paste, Cut, Select All, Undo, Redo, and Cmd+Backspace).
func isFieldEditorShortcut(_ ks: Keystroke) -> Bool {
    if !ks.modifiers.platform || ks.modifiers.control || ks.modifiers.alt || ks.modifiers.function {
        return false
    }
    switch ks.key {
    case "c", "v", "x", "a", "backspace":
        return !ks.modifiers.shift
    case "z":
        return true // Cmd+Z (undo) and Cmd+Shift+Z (redo)
    default:
        return false
    }
}

/// Returns true when the active keyboard input source is a non-ASCII-capable IME mode
/// (e.g. Japanese Romaji, Chinese Pinyin), matching upstream `is_ime_input_source_active()`.
func isImeInputSourceActive() -> Bool {
    guard let source = copyCurrentKeyboardInputSource() else {
        return false
    }
    let sourceType = inputSourceStringProperty(source, kTISPropertyInputSourceType)
    let isInputMode = (sourceType == (kTISTypeKeyboardInputMode as String))
    let isAsciiCapable = inputSourceBoolProperty(source, kTISPropertyInputSourceIsASCIICapable)
    return isInputMode && !isAsciiCapable
}

// MARK: - Native AppKit Views & Windows

final class BlurredView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .selection
        blendingMode = .behindWindow
        state = .followsWindowActiveState
        isEmphasized = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

protocol GPUIWindowContainer: NSWindow {
    var windowState: MacWindowState? { get set }
}

final class GPUIWindow: NSWindow, GPUIWindowContainer {
    weak var windowState: MacWindowState?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    @objc override func moveTabToNewWindow(_ sender: Any?) {
        super.moveTabToNewWindow(sender)
        windowState?.invokeMoveTabToNewWindowCallback()
    }

    @objc override func mergeAllWindows(_ sender: Any?) {
        super.mergeAllWindows(sender)
        windowState?.invokeMergeAllWindowsCallback()
    }

    @objc override func selectNextTab(_ sender: Any?) {
        windowState?.invokeSelectNextTabCallback()
    }

    @objc override func selectPreviousTab(_ sender: Any?) {
        windowState?.invokeSelectPreviousTabCallback()
    }

    @objc override func toggleTabBar(_ sender: Any?) {
        super.toggleTabBar(sender)
        windowState?.notifyButtonLayoutChanged()
        windowState?.invokeToggleTabBarCallback()
    }
}

final class GPUIPanel: NSPanel, GPUIWindowContainer {
    weak var windowState: MacWindowState?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class GPUIWindowDelegate: NSObject, NSWindowDelegate {
    weak var windowState: MacWindowState?

    init(windowState: MacWindowState) {
        self.windowState = windowState
    }

    func windowDidResize(_ notification: Notification) {
        windowState?.updateWindowScaleFactorAndSize()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        windowState?.updateWindowScaleFactorAndSize()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let state = windowState else { return }
        state.restartDisplayLink()
        state.updateWindowScaleFactorAndSize()
        state.notifyButtonLayoutChanged()
    }

    func windowDidMove(_ notification: Notification) {
        windowState?.invokeMovedCallback()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let state = windowState, let win = state.nativeWindow else { return }
        if !win.isKeyWindow {
            win.resignKey()
            return
        }
        state.notifyButtonLayoutChanged()
        state.handleActiveStatusChange(isActive: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let state = windowState else { return }
        state.notifyButtonLayoutChanged()
        state.handleActiveStatusChange(isActive: false)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        windowState?.saveFullscreenRestoreBounds()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        windowState?.notifyButtonLayoutChanged()
        windowState?.updateWindowScaleFactorAndSize()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        windowState?.notifyButtonLayoutChanged()
        windowState?.updateWindowScaleFactorAndSize()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        windowState?.invokeShouldCloseCallback() ?? true
    }

    func windowWillClose(_ notification: Notification) {
        windowState?.handleWindowWillClose()
    }
}

final class GPUIView: NSView, @preconcurrency NSTextInputClient, @preconcurrency CALayerDelegate {
    private let metalLayerInstance: CAMetalLayer
    weak var windowState: MacWindowState?
    private var appearanceObservation: NSKeyValueObservation?

    init(frame frameRect: NSRect, metalLayer: CAMetalLayer) {
        self.metalLayerInstance = metalLayer
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .duringViewResize
        metalLayer.delegate = self

        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType")])

        self.appearanceObservation = observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.windowState?.invokeAppearanceChangedCallback()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func makeBackingLayer() -> CALayer {
        metalLayerInstance
    }

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        windowState?.markFirstMouse()
        return true
    }

    func display(_ layer: CALayer) {
        _ = layer
        windowState?.displayLayerSynchronous()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        windowState?.invokeAppearanceChangedCallback()
    }

    private func isHostedFieldEditorActive() -> Bool {
        guard let firstResponder = window?.firstResponder as? NSTextView else {
            return false
        }
        return firstResponder !== self
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isHostedFieldEditorActive() {
            let ks = parseKeystroke(event)
            if isFieldEditorShortcut(ks) {
                return false
            }
        }
        return windowState?.handleKeyEvent(event, isKeyEquivalent: true, view: self) ?? false
    }

    override func keyDown(with event: NSEvent) {
        if isHostedFieldEditorActive() {
            return
        }
        _ = windowState?.handleKeyEvent(event, isKeyEquivalent: false, view: self)
    }

    override func keyUp(with event: NSEvent) {
        _ = windowState?.handleKeyEvent(event, isKeyEquivalent: false, view: self)
    }

    override func flagsChanged(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        if isHostedFieldEditorActive() {
            window?.makeFirstResponder(nil)
        }
        _ = inputContext?.handleEvent(event)
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if isHostedFieldEditorActive() {
            window?.makeFirstResponder(nil)
        }
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func rightMouseUp(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func otherMouseDown(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func otherMouseUp(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func mouseMoved(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func mouseEntered(with event: NSEvent) {
        windowState?.handleHoverStatusChange(isHovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        windowState?.handleHoverStatusChange(isHovered: false)
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func magnify(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func pressureChange(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    override func swipe(with event: NSEvent) {
        windowState?.handleMouseOrModifierEvent(event)
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let plain: String
        if let attr = string as? NSAttributedString {
            plain = attr.string
        } else if let str = string as? String {
            plain = str
        } else {
            return
        }
        let range = replacementRange.toRange()
        _ = windowState?.withInputHandler { handler in
            handler.replaceTextInRange(rangeUtf16: range, text: plain)
        }
    }

    override func doCommand(by selector: Selector) {
        windowState?.handleDoCommand(selector: selector)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let plain: String
        if let attr = string as? NSAttributedString {
            plain = attr.string
        } else if let str = string as? String {
            plain = str
        } else {
            plain = ""
        }
        let selRange = selectedRange.toRange()
        let repRange = replacementRange.toRange()
        _ = windowState?.withInputHandler { handler in
            handler.replaceAndMarkTextInRange(
                rangeUtf16: repRange,
                newText: plain,
                newSelectedRange: selRange
            )
        }
    }

    func unmarkText() {
        _ = windowState?.withInputHandler { handler in
            handler.unmarkText()
        }
    }

    func selectedRange() -> NSRange {
        guard let selection = windowState?.withInputHandler({ $0.selectedTextRange(ignoreDisabledInput: false) }) ?? nil else {
            return .invalid
        }
        return NSRange(gpuiRange: selection.range)
    }

    func markedRange() -> NSRange {
        guard let range = windowState?.withInputHandler({ $0.markedTextRange() }) ?? nil else {
            return .invalid
        }
        return NSRange(gpuiRange: range)
    }

    func hasMarkedText() -> Bool {
        (windowState?.withInputHandler({ $0.markedTextRange() }) ?? nil) != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let proposed = range.toRange(), !proposed.isEmpty else {
            return nil
        }
        return windowState?.withInputHandler { handler -> NSAttributedString? in
            var adjusted: Range<Int>? = nil
            guard let selectedText = handler.textForRange(rangeUtf16: proposed, adjustedRange: &adjusted) else {
                return nil
            }
            if let adjusted, adjusted != proposed {
                actualRange?.pointee = NSRange(gpuiRange: adjusted)
            }
            return NSAttributedString(string: selectedText)
        } ?? nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        _ = actualRange
        guard let state = windowState,
              let utf16Range = range.toRange(),
              let bounds = state.withInputHandler({ $0.boundsForRange(rangeUtf16: utf16Range) }) ?? nil
        else {
            return .zero
        }
        let frame = state.contentFrameInScreen()
        return NSRect(
            x: frame.origin.x + CGFloat(bounds.origin.x.value),
            y: frame.origin.y + frame.size.height - CGFloat(bounds.origin.y.value) - CGFloat(bounds.size.height.value),
            width: CGFloat(bounds.size.width.value),
            height: CGFloat(bounds.size.height.value)
        )
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let state = windowState else {
            return NSNotFound
        }
        let gpuiPoint = state.screenPointToGpuiPoint(point)
        guard let index = state.withInputHandler({ $0.characterIndexForPoint(point: gpuiPoint) }) ?? nil else {
            return NSNotFound
        }
        return index
    }

    // MARK: - NSDraggingDestination

    private func draggingPosition(_ sender: any NSDraggingInfo) -> Point<Pixels> {
        let winLoc = sender.draggingLocation
        let local = convert(winLoc, from: nil)
        return point(px(Float(local.x)), px(Float(local.y)))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pboard = Pasteboard(sender.draggingPasteboard)
        guard let item = pboard.read() else { return [] }
        for entry in item.entries {
            if case .externalPaths(let externalPaths) = entry {
                let pos = draggingPosition(sender)
                windowState?.markExternalFilesDragged(true)
                _ = windowState?.dispatchInput(.fileDrop(.entered(position: pos, paths: externalPaths)))
                return .copy
            }
        }
        return []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard windowState?.externalFilesDragged == true else { return [] }
        let pos = draggingPosition(sender)
        _ = windowState?.dispatchInput(.fileDrop(.pending(position: pos)))
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        _ = sender
        guard windowState?.externalFilesDragged == true else { return }
        windowState?.markExternalFilesDragged(false)
        _ = windowState?.dispatchInput(.fileDrop(.exited))
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard windowState?.externalFilesDragged == true else { return false }
        let pos = draggingPosition(sender)
        windowState?.markExternalFilesDragged(false)
        _ = windowState?.dispatchInput(.fileDrop(.submit(position: pos)))
        return true
    }
}

// MARK: - MacWindowState

/// Shared state backing a `MacWindow`, its `NSWindow` delegate, its `GPUIView`, and any child `GpuiSurface`s.
// PORT NOTE: Synchronized via NSLock and AppKit main-thread dispatch matching upstream `Arc<Mutex<MacWindowState>>`.
public final class MacWindowState: @unchecked Sendable {
    let lock = NSLock()
    public let handle: AnyWindowHandle
    let foregroundExecutor: ForegroundExecutor?
    let backgroundExecutor: BackgroundExecutor?
    let renderer: Renderer

    var nativeWindow: (any GPUIWindowContainer)?
    var windowDelegate: GPUIWindowDelegate?
    var nativeView: GPUIView?
    var blurredView: BlurredView?
    var sheetParent: NSWindow?

    var backgroundAppearance: WindowBackgroundAppearance
    var transparentTitlebar: Bool
    var trafficLightPosition: Point<Pixels>?
    var displayLink: DisplayLink?
    var inputHandler: (any PlatformInputHandlerProtocol)?

    var requestFrameCallback: ((RequestFrameOptions) -> Void)?
    var eventCallback: ((PlatformInput) -> DispatchEventResult)?
    var surfaceEventCallback: ((UnsafeMutableRawPointer, PlatformInput) -> Void)?
    var activateCallback: ((Bool) -> Void)?
    var hoverCallback: ((Bool) -> Void)?
    var resizeCallback: ((Size<Pixels>, Float) -> Void)?
    var movedCallback: (() -> Void)?
    var shouldCloseCallback: (() -> Bool)?
    var closeCallback: (() -> Void)?
    var appearanceChangedCallback: (() -> Void)?
    var buttonLayoutChangedCallback: (() -> Void)?
    var moveTabToNewWindowCallback: (() -> Void)?
    var mergeAllWindowsCallback: (() -> Void)?
    var selectNextTabCallback: (() -> Void)?
    var selectPreviousTabCallback: (() -> Void)?
    var toggleTabBarCallback: (() -> Void)?

    var previousModifiersChangedEvent: PlatformInput?
    var lastKeyEquivalent: KeyDownEvent?
    var keystrokeForDoCommand: Keystroke?
    var doCommandHandled: Bool?
    var externalFilesDragged: Bool = false
    var firstMouse: Bool = false
    var isHoveredState: Bool = false
    var fullscreenRestoreBounds: Bounds<Pixels> = .zero
    var activatedLeastOnce: Bool = false
    var isClosed: Bool = false
    var pendingResizeCallback: Bool = false

    public var captureFrames: Bool = false
    public var lastCapturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])?

    init(
        handle: AnyWindowHandle,
        foregroundExecutor: ForegroundExecutor?,
        backgroundExecutor: BackgroundExecutor?,
        renderer: Renderer,
        backgroundAppearance: WindowBackgroundAppearance,
        transparentTitlebar: Bool,
        trafficLightPosition: Point<Pixels>?
    ) {
        self.handle = handle
        self.foregroundExecutor = foregroundExecutor
        self.backgroundExecutor = backgroundExecutor
        self.renderer = renderer
        self.backgroundAppearance = backgroundAppearance
        self.transparentTitlebar = transparentTitlebar
        self.trafficLightPosition = trafficLightPosition
    }

    func contentSize() -> Size<Pixels> {
        let readOnMain: () -> Size<Pixels> = {
            MainActor.assumeIsolated {
                guard let contentView = self.nativeWindow?.contentView else {
                    return .zero
                }
                let sz = contentView.frame.size
                return size(px(Float(sz.width)), px(Float(sz.height)))
            }
        }
        if Thread.isMainThread {
            return readOnMain()
        } else {
            return DispatchQueue.main.sync(execute: readOnMain)
        }
    }

    func scaleFactor() -> Float {
        let readOnMain: () -> Float = {
            MainActor.assumeIsolated {
                if let win = self.nativeWindow {
                    let factor = Float(win.backingScaleFactor)
                    return factor > 0 ? factor : 2.0
                }
                if let screen = NSScreen.main {
                    return Float(screen.backingScaleFactor)
                }
                return 2.0
            }
        }
        if Thread.isMainThread {
            return readOnMain()
        } else {
            return DispatchQueue.main.sync(execute: readOnMain)
        }
    }

    func bounds() -> Bounds<Pixels> {
        let readOnMain: () -> Bounds<Pixels> = {
            MainActor.assumeIsolated {
                guard let win = self.nativeWindow else {
                    return .zero
                }
                let windowFrame = win.frame
                let screenFrame = win.screen?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
                let originX = windowFrame.origin.x - screenFrame.origin.x
                let originY = screenFrame.origin.y + screenFrame.size.height - windowFrame.origin.y - windowFrame.size.height
                return Bounds(
                    origin: point(px(Float(originX)), px(Float(originY))),
                    size: size(px(Float(windowFrame.size.width)), px(Float(windowFrame.size.height)))
                )
            }
        }
        if Thread.isMainThread {
            return readOnMain()
        } else {
            return DispatchQueue.main.sync(execute: readOnMain)
        }
    }

    func positionTrafficLights() {
        let act: () -> Void = {
            MainActor.assumeIsolated {
                guard let win = self.nativeWindow, let tlPos = self.trafficLightPosition else {
                    return
                }
                guard self.transparentTitlebar else { return }

                let closeButton = win.standardWindowButton(.closeButton)
                let miniaturizeButton = win.standardWindowButton(.miniaturizeButton)
                let zoomButton = win.standardWindowButton(.zoomButton)
                guard let closeBtn = closeButton,
                      let minBtn = miniaturizeButton,
                      let zoomBtn = zoomButton,
                      let titlebarContainer = closeBtn.superview
                else {
                    return
                }

                let buttonHeight = closeBtn.frame.size.height
                let titlebarHeight = titlebarContainer.frame.size.height
                let yCoord = titlebarContainer.isFlipped
                    ? CGFloat(tlPos.y.value)
                    : (titlebarHeight - CGFloat(tlPos.y.value) - buttonHeight)

                let spacing = minBtn.frame.origin.x - closeBtn.frame.origin.x
                let zoomSpacing = zoomBtn.frame.origin.x - minBtn.frame.origin.x
                let baseX = CGFloat(tlPos.x.value)

                closeBtn.setFrameOrigin(NSPoint(x: baseX, y: yCoord))
                minBtn.setFrameOrigin(NSPoint(x: baseX + spacing, y: yCoord))
                zoomBtn.setFrameOrigin(NSPoint(x: baseX + spacing + zoomSpacing, y: yCoord))
            }
        }
        if Thread.isMainThread {
            act()
        } else {
            DispatchQueue.main.sync(execute: act)
        }
    }

    func updateWindowScaleFactorAndSize() {
        let scale = scaleFactor()
        let cSize = contentSize()
        let drawableSize = Size(
            width: DevicePixels(Int32((cSize.width.value * scale).rounded(.up))),
            height: DevicePixels(Int32((cSize.height.value * scale).rounded(.up)))
        )

        MainActor.assumeIsolated {
            renderer.layer().contentsScale = CGFloat(scale)
            positionTrafficLights()
        }
        renderer.updateDrawableSize(drawableSize)

        lock.lock()
        let cb = resizeCallback
        lock.unlock()
        cb?(cSize, scale)
    }

    func restartDisplayLink() {
        lock.lock()
        let oldLink = displayLink
        displayLink = nil
        let closed = isClosed
        lock.unlock()

        try? oldLink?.stop()
        guard !closed else { return }

        let displayId: CGDirectDisplayID = MainActor.assumeIsolated {
            if let screen = nativeWindow?.screen, let id = MacDisplay.screenNumber(for: screen) {
                return id
            }
            return CGMainDisplayID()
        }

        if let newLink = try? DisplayLink.new(displayId: displayId, callback: { [weak self] in
            self?.stepDisplayLink()
        }) {
            lock.lock()
            let hasCallback = (requestFrameCallback != nil)
            displayLink = newLink
            lock.unlock()
            if hasCallback {
                try? newLink.start()
            }
        }
    }

    private func stepDisplayLink() {
        lock.lock()
        let cb = requestFrameCallback
        lock.unlock()
        cb?(RequestFrameOptions())
    }

    func displayLayerSynchronous() {
        lock.lock()
        try? displayLink?.stop()
        let cb = requestFrameCallback
        lock.unlock()

        guard let cb else { return }
        renderer.setPresentsWithTransaction(true)
        cb(RequestFrameOptions(requirePresentation: true, forceRender: false))
        renderer.setPresentsWithTransaction(false)

        lock.lock()
        try? displayLink?.start()
        lock.unlock()
    }

    func markFirstMouse() {
        lock.lock()
        firstMouse = true
        lock.unlock()
    }

    func markExternalFilesDragged(_ dragged: Bool) {
        lock.lock()
        externalFilesDragged = dragged
        lock.unlock()
    }

    /// Temporarily takes `inputHandler` out of `MacWindowState` while unlocked so re-entrant
    /// `App`/`Window` updates cannot deadlock `lock`, then restores it if unreplaced,
    /// matching upstream `with_input_handler` (`window.rs`).
    func withInputHandler<R>(_ body: (any PlatformInputHandlerProtocol) -> R) -> R? {
        lock.lock()
        guard let handler = inputHandler else {
            lock.unlock()
            return nil
        }
        inputHandler = nil
        lock.unlock()

        let result = body(handler)

        lock.lock()
        if inputHandler == nil {
            inputHandler = handler
        }
        lock.unlock()
        return result
    }

    /// Computes the window's content frame in AppKit screen coordinates (bottom-left origin),
    /// matching upstream `get_frame` (`window.rs`).
    func contentFrameInScreen() -> NSRect {
        let readOnMain: () -> NSRect = {
            MainActor.assumeIsolated {
                guard let win = self.nativeWindow else {
                    return .zero
                }
                var frame = win.frame
                let contentLayoutRect = win.contentLayoutRect
                if !win.styleMask.contains(.fullSizeContentView) {
                    frame.origin.y -= frame.size.height - contentLayoutRect.size.height
                }
                return frame
            }
        }
        return Thread.isMainThread ? readOnMain() : DispatchQueue.main.sync(execute: readOnMain)
    }

    /// Converts an AppKit screen point (bottom-left origin) into a GPUI window point (top-left origin),
    /// matching upstream `screen_point_to_gpui_point` (`window.rs`).
    func screenPointToGpuiPoint(_ position: NSPoint) -> Point<Pixels> {
        let frame = contentFrameInScreen()
        let windowX = position.x - frame.origin.x
        let windowY = frame.size.height - (position.y - frame.origin.y)
        return point(px(Float(windowX)), px(Float(windowY)))
    }

    func handleDoCommand(selector: Selector) {
        _ = selector
        lock.lock()
        let keystroke = keystrokeForDoCommand
        keystrokeForDoCommand = nil
        let cb = eventCallback
        eventCallback = nil
        lock.unlock()

        var handledResult: Bool? = nil
        if let keystroke, let cb {
            let result = cb(.keyDown(KeyDownEvent(
                keystroke: keystroke,
                isHeld: false,
                preferCharacterInput: false
            )))
            handledResult = !result.propagate || result.defaultPrevented
        }

        lock.lock()
        if let handledResult {
            doCommandHandled = handledResult
        }
        if eventCallback == nil {
            eventCallback = cb
        }
        lock.unlock()
    }

    @discardableResult
    func dispatchInput(_ input: PlatformInput) -> DispatchEventResult {
        lock.lock()
        let cb = eventCallback
        lock.unlock()
        return cb?(input) ?? DispatchEventResult(propagate: true, defaultPrevented: false)
    }

    func dispatchSurfaceEvent(nativeViewPtr: UnsafeMutableRawPointer, input: PlatformInput) {
        lock.lock()
        let cb = surfaceEventCallback
        lock.unlock()
        cb?(nativeViewPtr, input)
    }

    func handleMouseOrModifierEvent(_ nativeEvent: NSEvent) {
        let cSize = contentSize()
        guard var input = platformInputFromNative(
            nativeEvent,
            windowHeight: cSize.height,
            nativeView: nativeView
        ) else {
            return
        }

        lock.lock()
        let wasFirstMouse = firstMouse
        firstMouse = false
        lock.unlock()

        switch input {
        case .mouseDown(var down):
            if down.button == .left && down.modifiers.control {
                down.button = .right
                down.modifiers.control = false
                down.clickCount = 1
            }
            down.firstMouse = wasFirstMouse
            input = .mouseDown(down)

        case .mouseUp(var up):
            if up.button == .left && up.modifiers.control {
                up.button = .right
                up.modifiers.control = false
            }
            input = .mouseUp(up)

        case .modifiersChanged:
            lock.lock()
            let duplicate = (previousModifiersChangedEvent == input)
            previousModifiersChangedEvent = input
            lock.unlock()
            if duplicate {
                return
            }

        default:
            break
        }

        _ = dispatchInput(input)
    }

    @MainActor
    func handleKeyEvent(_ nativeEvent: NSEvent, isKeyEquivalent: Bool, view: GPUIView? = nil) -> Bool {
        let cSize = contentSize()
        guard let input = platformInputFromNative(
            nativeEvent,
            windowHeight: cSize.height,
            nativeView: nil
        ) else {
            return false
        }

        let runCallback: (PlatformInput) -> Bool = { event in
            self.lock.lock()
            let cb = self.eventCallback
            self.eventCallback = nil
            self.lock.unlock()

            let handled: Bool
            if let cb {
                let res = cb(event)
                handled = !res.propagate || res.defaultPrevented
            } else {
                handled = false
            }

            self.lock.lock()
            if self.eventCallback == nil {
                self.eventCallback = cb
            }
            self.lock.unlock()
            return handled
        }

        let sendToInputContext: () -> Bool = {
            guard let targetView = view ?? self.nativeView else {
                return false
            }
            if let inputContext = targetView.inputContext {
                return inputContext.handleEvent(nativeEvent)
            }
            targetView.interpretKeyEvents([nativeEvent])
            return true
        }

        switch input {
        case .keyDown(let keyDownEvent):
            lock.lock()
            if isKeyEquivalent {
                lastKeyEquivalent = keyDownEvent
            } else {
                let prevEquiv = lastKeyEquivalent
                lastKeyEquivalent = nil
                if prevEquiv == keyDownEvent {
                    lock.unlock()
                    return false
                }
            }
            lock.unlock()

            let isComposing = (withInputHandler { $0.markedTextRange() } ?? nil) != nil
            let hasPrintableKeyChar: Bool = {
                guard let kc = keyDownEvent.keystroke.keyChar, !kc.isEmpty else { return false }
                return kc.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            }()
            let isImePrintableKey = !isComposing
                && hasPrintableKeyChar
                && !keyDownEvent.keystroke.modifiers.control
                && !keyDownEvent.keystroke.modifiers.function
                && !keyDownEvent.keystroke.modifiers.platform
                && isImeInputSourceActive()
                && (withInputHandler { $0.queryPrefersImeForPrintableKeys() } ?? false)

            if isComposing
                || isImePrintableKey
                || (keyDownEvent.keystroke.keyChar == nil
                    && !keyDownEvent.keystroke.modifiers.control
                    && !keyDownEvent.keystroke.modifiers.function
                    && !keyDownEvent.keystroke.modifiers.platform)
            {
                lock.lock()
                keystrokeForDoCommand = keyDownEvent.keystroke
                doCommandHandled = nil
                lock.unlock()

                let contextHandled = sendToInputContext()

                lock.lock()
                keystrokeForDoCommand = nil
                let cmdHandled = doCommandHandled
                doCommandHandled = nil
                lock.unlock()

                if let cmdHandled {
                    return cmdHandled
                } else if contextHandled {
                    return true
                }
                return runCallback(.keyDown(keyDownEvent))
            }

            if runCallback(.keyDown(keyDownEvent)) {
                return true
            }

            if keyDownEvent.isHeld, let keyChar = keyDownEvent.keystroke.keyChar {
                let repeatHandled = withInputHandler { handler -> Bool in
                    if !handler.applePressAndHoldEnabled() {
                        handler.replaceTextInRange(rangeUtf16: nil, text: keyChar)
                        return true
                    }
                    return false
                }
                if repeatHandled == true {
                    return true
                }
            }

            if isKeyEquivalent && keyDownEvent.keystroke.modifiers != Modifiers(function: true) {
                return false
            }

            return sendToInputContext()

        case .keyUp:
            return runCallback(input)

        default:
            return false
        }
    }

    func handleActiveStatusChange(isActive: Bool) {
        lock.lock()
        if isActive {
            activatedLeastOnce = true
        }
        let cb = activateCallback
        lock.unlock()
        cb?(isActive)
    }

    func handleHoverStatusChange(isHovered: Bool) {
        lock.lock()
        isHoveredState = isHovered
        let cb = hoverCallback
        lock.unlock()
        cb?(isHovered)
    }

    func saveFullscreenRestoreBounds() {
        let current = bounds()
        lock.lock()
        fullscreenRestoreBounds = current
        lock.unlock()
    }

    func invokeMovedCallback() {
        lock.lock()
        let cb = movedCallback
        lock.unlock()
        cb?()
    }

    func invokeAppearanceChangedCallback() {
        lock.lock()
        let cb = appearanceChangedCallback
        lock.unlock()
        cb?()
    }

    func notifyButtonLayoutChanged() {
        lock.lock()
        let cb = buttonLayoutChangedCallback
        lock.unlock()
        cb?()
    }

    func invokeShouldCloseCallback() -> Bool {
        lock.lock()
        let cb = shouldCloseCallback
        lock.unlock()
        return cb?() ?? true
    }

    func invokeMoveTabToNewWindowCallback() {
        lock.lock()
        let cb = moveTabToNewWindowCallback
        lock.unlock()
        cb?()
    }

    func invokeMergeAllWindowsCallback() {
        lock.lock()
        let cb = mergeAllWindowsCallback
        lock.unlock()
        cb?()
    }

    func invokeSelectNextTabCallback() {
        lock.lock()
        let cb = selectNextTabCallback
        lock.unlock()
        cb?()
    }

    func invokeSelectPreviousTabCallback() {
        lock.lock()
        let cb = selectPreviousTabCallback
        lock.unlock()
        cb?()
    }

    func invokeToggleTabBarCallback() {
        lock.lock()
        let cb = toggleTabBarCallback
        lock.unlock()
        cb?()
    }

    func handleWindowWillClose() {
        lock.lock()
        isClosed = true
        let link = displayLink
        displayLink = nil
        let cb = closeCallback
        closeCallback = nil
        lock.unlock()

        try? link?.stop()
        cb?()
    }
}

// MARK: - MacWindow

/// Native macOS `PlatformWindow` backed by `NSWindow` (`GPUIWindow` / `GPUIPanel`), `GPUIView`, and `MetalRenderer`.
// PORT NOTE: Synchronized via `MacWindowState`'s lock and main-thread AppKit dispatch.
public final class MacWindow: PlatformWindow, @unchecked Sendable {
    public let state: MacWindowState

    private init(state: MacWindowState) {
        self.state = state
    }

    /// When enabled, `draw(scene:)` also captures the rendered `BGRA8Unorm` frame into `lastCapturedFrame` as `RGBA8`.
    public var captureFrames: Bool {
        get {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.captureFrames
        }
        set {
            state.lock.lock()
            state.captureFrames = newValue
            state.lock.unlock()
        }
    }

    /// Most recent `RGBA8` frame read back from Metal when `captureFrames == true`.
    public var lastCapturedFrame: (width: UInt32, height: UInt32, rgba: [UInt8])? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.lastCapturedFrame
    }

    /// Opens a new native macOS window configured with `options` and backed by `MetalRenderer`.
    public static func open(
        handle: AnyWindowHandle,
        options: WindowOptions,
        foregroundExecutor: ForegroundExecutor?,
        backgroundExecutor: BackgroundExecutor?,
        rendererContext: RendererContext
    ) -> MacWindow {
        let createOnMain: () -> MacWindow = {
            MainActor.assumeIsolated {
                // Ensure NSApplication connection to WindowServer is initialized.
                _ = GPUIApplication.shared

                let targetDisplay: MacDisplay
                if let displayId = options.displayId, let matched = MacDisplay.findById(displayId) {
                    targetDisplay = matched
                } else {
                    targetDisplay = MacDisplay.primary()
                }

                let screen = targetDisplay.nsScreen() ?? NSScreen.main ?? NSScreen.screens.first
                let screenFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
                let visibleFrame = screen?.visibleFrame ?? screenFrame

                let requestedBounds: Bounds<Pixels>
                let shouldZoomAfterOpen: Bool
                let shouldFullscreenAfterOpen: Bool
                switch options.windowBounds {
                case .windowed(let b):
                    requestedBounds = b
                    shouldZoomAfterOpen = false
                    shouldFullscreenAfterOpen = false
                case .maximized(let b):
                    requestedBounds = b
                    shouldZoomAfterOpen = true
                    shouldFullscreenAfterOpen = false
                case .fullscreen(let b):
                    requestedBounds = b
                    shouldZoomAfterOpen = false
                    shouldFullscreenAfterOpen = true
                case .none:
                    let defaultW: Float = 800.0
                    let defaultH: Float = 600.0
                    let cx = max(0.0, (Float(visibleFrame.size.width) - defaultW) * 0.5)
                    let cy = max(0.0, (Float(visibleFrame.size.height) - defaultH) * 0.5)
                    requestedBounds = Bounds(
                        origin: point(px(cx), px(cy)),
                        size: size(px(defaultW), px(defaultH))
                    )
                    shouldZoomAfterOpen = false
                    shouldFullscreenAfterOpen = false
                }

                let contentRect = NSRect(
                    x: screenFrame.origin.x + CGFloat(requestedBounds.origin.x.value),
                    y: screenFrame.origin.y + screenFrame.size.height
                        - CGFloat(requestedBounds.origin.y.value)
                        - CGFloat(requestedBounds.size.height.value),
                    width: max(1.0, CGFloat(requestedBounds.size.width.value)),
                    height: max(1.0, CGFloat(requestedBounds.size.height.value))
                )

                let transparentTitlebar = options.titlebar?.appearsTransparent ?? true
                var styleMask: NSWindow.StyleMask = []
                switch options.kind {
                case .normal:
                    styleMask = [.titled, .closable, .miniaturizable, .resizable]
                    if transparentTitlebar {
                        styleMask.insert(.fullSizeContentView)
                    }
                case .popUpMenu:
                    styleMask = [.borderless, .nonactivatingPanel]
                case .modal:
                    styleMask = [.titled, .resizable]
                    if transparentTitlebar {
                        styleMask.insert(.fullSizeContentView)
                    }
                }

                let nativeWindow: any GPUIWindowContainer
                switch options.kind {
                case .normal:
                    nativeWindow = GPUIWindow(
                        contentRect: contentRect,
                        styleMask: styleMask,
                        backing: .buffered,
                        defer: false,
                        screen: screen
                    )
                case .popUpMenu, .modal:
                    nativeWindow = GPUIPanel(
                        contentRect: contentRect,
                        styleMask: styleMask,
                        backing: .buffered,
                        defer: false,
                        screen: screen
                    )
                }

                let isTransparent = options.windowBackground != .opaque
                let renderer = newRenderer(
                    rendererContext,
                    Unmanaged.passUnretained(nativeWindow as AnyObject).toOpaque(),
                    nil,
                    Size(
                        width: requestedBounds.size.width.value,
                        height: requestedBounds.size.height.value
                    ),
                    isTransparent
                )

                let windowState = MacWindowState(
                    handle: handle,
                    foregroundExecutor: foregroundExecutor,
                    backgroundExecutor: backgroundExecutor,
                    renderer: renderer,
                    backgroundAppearance: options.windowBackground,
                    transparentTitlebar: transparentTitlebar,
                    trafficLightPosition: options.titlebar?.trafficLightPosition
                )

                let delegate = GPUIWindowDelegate(windowState: windowState)
                windowState.nativeWindow = nativeWindow
                windowState.windowDelegate = delegate
                nativeWindow.windowState = windowState
                nativeWindow.delegate = delegate
                nativeWindow.isReleasedWhenClosed = false

                guard let containerView = nativeWindow.contentView else {
                    return MacWindow(state: windowState)
                }

                let gpuiView = GPUIView(frame: containerView.bounds, metalLayer: renderer.layer())
                gpuiView.autoresizingMask = [.width, .height]
                gpuiView.windowState = windowState
                windowState.nativeView = gpuiView

                if options.windowBackground == .blurred {
                    let blur = BlurredView(frame: containerView.bounds)
                    blur.autoresizingMask = [.width, .height]
                    containerView.addSubview(blur)
                    windowState.blurredView = blur
                }
                containerView.addSubview(gpuiView)
                nativeWindow.makeFirstResponder(gpuiView)

                if isTransparent {
                    nativeWindow.isOpaque = false
                    nativeWindow.backgroundColor = .clear
                } else {
                    nativeWindow.isOpaque = true
                    nativeWindow.backgroundColor = .windowBackgroundColor
                }

                if let title = options.titlebar?.title {
                    nativeWindow.title = title
                }
                nativeWindow.isMovable = options.isMovable

                if let minSize = options.windowMinSize {
                    nativeWindow.contentMinSize = NSSize(
                        width: CGFloat(minSize.width.value),
                        height: CGFloat(minSize.height.value)
                    )
                }

                if transparentTitlebar && styleMask.contains(.titled) {
                    nativeWindow.titlebarAppearsTransparent = true
                    nativeWindow.titleVisibility = .hidden
                }

                let trackingOptions: NSTrackingArea.Options = [
                    .mouseEnteredAndExited,
                    .mouseMoved,
                    .activeAlways,
                    .inVisibleRect,
                ]
                let trackingArea = NSTrackingArea(
                    rect: .zero,
                    options: trackingOptions,
                    owner: gpuiView,
                    userInfo: nil
                )
                gpuiView.addTrackingArea(trackingArea)

                switch options.kind {
                case .normal:
                    nativeWindow.level = .normal
                    nativeWindow.acceptsMouseMovedEvents = true
                    nativeWindow.tabbingIdentifier = ""
                case .popUpMenu:
                    nativeWindow.level = .popUpMenu
                    nativeWindow.animationBehavior = .utilityWindow
                    nativeWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                case .modal:
                    nativeWindow.acceptsMouseMovedEvents = true
                    if let parent = NSApp?.mainWindow, parent !== nativeWindow {
                        windowState.sheetParent = parent
                    }
                }

                // Set initial content size & backing scale on the Metal layer immediately.
                windowState.updateWindowScaleFactorAndSize()
                windowState.restartDisplayLink()

                if options.show {
                    if options.kind == .modal, let parent = windowState.sheetParent {
                        parent.beginSheet(nativeWindow)
                    } else if options.focus {
                        nativeWindow.makeKeyAndOrderFront(nil)
                    } else {
                        nativeWindow.orderFront(nil)
                    }
                }

                if shouldZoomAfterOpen && !nativeWindow.isZoomed {
                    nativeWindow.zoom(nil)
                }
                if shouldFullscreenAfterOpen {
                    nativeWindow.toggleFullScreen(nil)
                }

                windowState.positionTrafficLights()
                return MacWindow(state: windowState)
            }
        }

        if Thread.isMainThread {
            return createOnMain()
        } else {
            return DispatchQueue.main.sync(execute: createOnMain)
        }
    }

    deinit {
        let windowState = state
        let closeOnMain: @Sendable () -> Void = {
            MainActor.assumeIsolated {
                windowState.lock.lock()
                windowState.isClosed = true
                let link = windowState.displayLink
                windowState.displayLink = nil
                let win = windowState.nativeWindow
                let sheetParent = windowState.sheetParent
                windowState.nativeWindow = nil
                windowState.windowDelegate = nil
                windowState.lock.unlock()

                try? link?.stop()
                if let win {
                    win.delegate = nil
                    if let sheetParent {
                        sheetParent.endSheet(win)
                    }
                    win.orderOut(nil)
                    win.close()
                }
                windowState.renderer.destroy()
            }
        }

        if Thread.isMainThread {
            closeOnMain()
        } else {
            DispatchQueue.main.async(execute: closeOnMain)
        }
    }

    // MARK: - Static Window Queries

    /// Returns the `AnyWindowHandle` of the currently active key window if managed by GPUI.
    public static func activeWindow() -> AnyWindowHandle? {
        let query: () -> AnyWindowHandle? = {
            MainActor.assumeIsolated {
                guard let keyWin = NSApp?.keyWindow as? (any GPUIWindowContainer) else {
                    return nil
                }
                return keyWin.windowState?.handle
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    /// Returns all GPUI windows ordered front-to-back as reported by AppKit.
    public static func orderedWindows() -> [AnyWindowHandle] {
        let query: () -> [AnyWindowHandle] = {
            MainActor.assumeIsolated {
                guard let windows = NSApp?.orderedWindows else {
                    return []
                }
                var handles: [AnyWindowHandle] = []
                for win in windows {
                    if let gpuiWin = win as? (any GPUIWindowContainer),
                       let h = gpuiWin.windowState?.handle
                    {
                        handles.append(h)
                    }
                }
                return handles
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    /// Reads the user's system-wide macOS window tabbing preference.
    public static func getUserTabbingPreference() -> UserTabbingPreference {
        let query: () -> UserTabbingPreference = {
            MainActor.assumeIsolated {
                let pref = NSWindow.userTabbingPreference
                switch pref {
                case .manual:
                    return .never
                case .always:
                    return .always
                case .inFullScreen:
                    return .inFullScreen
                @unknown default:
                    return .inFullScreen
                }
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    // MARK: - Callback Registrations

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        state.lock.lock()
        state.requestFrameCallback = callback
        let link = state.displayLink
        state.lock.unlock()
        try? link?.start()
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        state.lock.lock()
        state.eventCallback = callback
        state.lock.unlock()
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        state.lock.lock()
        state.activateCallback = callback
        state.lock.unlock()
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        state.lock.lock()
        state.hoverCallback = callback
        state.lock.unlock()
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        state.lock.lock()
        state.resizeCallback = callback
        state.lock.unlock()
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.movedCallback = callback
        state.lock.unlock()
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        state.lock.lock()
        state.shouldCloseCallback = callback
        state.lock.unlock()
    }

    public func onClose(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.closeCallback = callback
        state.lock.unlock()
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.appearanceChangedCallback = callback
        state.lock.unlock()
    }

    public func onButtonLayoutChanged(_ callback: @escaping () -> Void) {
        state.lock.lock()
        state.buttonLayoutChangedCallback = callback
        state.lock.unlock()
    }

    public func onSurfaceEvent(_ callback: @escaping (UnsafeMutableRawPointer, PlatformInput) -> Void) {
        state.lock.lock()
        state.surfaceEventCallback = callback
        state.lock.unlock()
    }

    // MARK: - PlatformWindow Conformance

    public func bounds() -> Bounds<Pixels> {
        state.bounds()
    }

    public func contentSize() -> Size<Pixels> {
        state.contentSize()
    }

    public func scaleFactor() -> Float {
        state.scaleFactor()
    }

    public func appearance() -> WindowAppearance {
        let query: () -> WindowAppearance = {
            MainActor.assumeIsolated {
                windowAppearanceFromNative(self.state.nativeView?.effectiveAppearance ?? NSApp?.effectiveAppearance)
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func mousePosition() -> Point<Pixels> {
        let query: () -> Point<Pixels> = {
            MainActor.assumeIsolated {
                guard let win = self.state.nativeWindow, let view = self.state.nativeView else {
                    return .zero
                }
                let screenLoc = NSEvent.mouseLocation
                let winRect = win.convertFromScreen(NSRect(origin: screenLoc, size: .zero))
                let local = view.convert(winRect.origin, from: nil)
                return point(px(Float(local.x)), px(Float(local.y)))
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func modifiers() -> Modifiers {
        let flags = NSEvent.modifierFlags
        return Modifiers(
            control: flags.contains(.control),
            alt: flags.contains(.option),
            shift: flags.contains(.shift),
            platform: flags.contains(.command),
            function: flags.contains(.function)
        )
    }

    public func capslock() -> Capslock {
        Capslock(on: NSEvent.modifierFlags.contains(.capsLock))
    }

    public func activate() {
        let act: () -> Void = {
            MainActor.assumeIsolated {
                self.state.nativeWindow?.makeKeyAndOrderFront(nil)
            }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func isMaximized() -> Bool {
        let query: () -> Bool = {
            MainActor.assumeIsolated { self.state.nativeWindow?.isZoomed ?? false }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func isActive() -> Bool {
        let query: () -> Bool = {
            MainActor.assumeIsolated { self.state.nativeWindow?.isKeyWindow ?? false }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func isHovered() -> Bool {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.isHoveredState
    }

    public func isFullscreen() -> Bool {
        let query: () -> Bool = {
            MainActor.assumeIsolated {
                guard let win = self.state.nativeWindow else { return false }
                return win.styleMask.contains(.fullScreen)
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func minimize() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.miniaturize(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func zoom() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.zoom(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func toggleFullScreen() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.toggleFullScreen(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func draw(scene: Scene) {
        let scale = scaleFactor()
        let cSize = contentSize()
        let drawableSize = Size(
            width: DevicePixels(max(1, Int32((cSize.width.value * scale).rounded(.up)))),
            height: DevicePixels(max(1, Int32((cSize.height.value * scale).rounded(.up))))
        )

        let updateLayerScale: () -> Void = {
            MainActor.assumeIsolated {
                if self.state.renderer.layer().contentsScale != CGFloat(scale) {
                    self.state.renderer.layer().contentsScale = CGFloat(scale)
                }
            }
        }
        if Thread.isMainThread {
            updateLayerScale()
        } else {
            DispatchQueue.main.sync(execute: updateLayerScale)
        }

        let currentDrawable = state.renderer.layer().drawableSize
        if Int32(currentDrawable.width.rounded(.up)) != drawableSize.width.value
            || Int32(currentDrawable.height.rounded(.up)) != drawableSize.height.value
        {
            state.renderer.updateDrawableSize(drawableSize)
        }

        state.renderer.draw(scene)

        state.lock.lock()
        let shouldCapture = state.captureFrames
        state.lock.unlock()

        if shouldCapture,
           let captured = try? state.renderer.renderToTexture(scene, size: drawableSize, background: nil)
        {
            state.lock.lock()
            state.lastCapturedFrame = (
                width: UInt32(captured.width),
                height: UInt32(captured.height),
                rgba: captured.rgba
            )
            state.lock.unlock()
        }
    }

    public func spriteAtlas() -> any PlatformAtlas {
        state.renderer.spriteAtlas()
    }

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        state.lock.lock()
        state.inputHandler = handler
        state.lock.unlock()
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        state.lock.lock()
        defer { state.lock.unlock() }
        let current = state.inputHandler
        state.inputHandler = nil
        return current
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.inputHandler
    }

    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? {
        guard let view = state.nativeView else { return nil }
        return Unmanaged.passUnretained(view).toOpaque()
    }

    public func display() -> (any PlatformDisplay)? {
        let query: () -> MacDisplay? = {
            MainActor.assumeIsolated {
                guard let screen = self.state.nativeWindow?.screen,
                      let id = MacDisplay.screenNumber(for: screen)
                else {
                    return MacDisplay.primary()
                }
                return MacDisplay(id)
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func gpuSpecs() -> GpuSpecs? {
        state.renderer.gpuSpecs()
    }

    public func setEdited(_ edited: Bool) {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.isDocumentEdited = edited }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func showCharacterPalette() {
        let act: () -> Void = {
            MainActor.assumeIsolated { NSApp?.orderFrontCharacterPalette(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func startWindowMove() {
        let act: () -> Void = {
            MainActor.assumeIsolated {
                guard let win = self.state.nativeWindow, let currentEvent = NSApp?.currentEvent else { return }
                win.performDrag(with: currentEvent)
            }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func tabbedWindows() -> [AnyWindowHandle]? {
        let query: () -> [AnyWindowHandle]? = {
            MainActor.assumeIsolated {
                guard let tabs = self.state.nativeWindow?.tabbedWindows else { return nil }
                var handles: [AnyWindowHandle] = []
                for tab in tabs {
                    if let gpuiTab = tab as? (any GPUIWindowContainer),
                       let h = gpuiTab.windowState?.handle
                    {
                        handles.append(h)
                    }
                }
                return handles
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func tabBarVisible() -> Bool {
        let query: () -> Bool = {
            MainActor.assumeIsolated {
                guard let group = self.state.nativeWindow?.tabGroup else { return false }
                return group.isTabBarVisible
            }
        }
        return Thread.isMainThread ? query() : DispatchQueue.main.sync(execute: query)
    }

    public func mergeAllWindows() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.mergeAllWindows(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func moveTabToNewWindow() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.moveTabToNewWindow(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func toggleWindowTabOverview() {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.toggleTabOverview(nil) }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func setTabbingIdentifier(_ identifier: String) {
        let act: () -> Void = {
            MainActor.assumeIsolated { self.state.nativeWindow?.tabbingIdentifier = identifier }
        }
        if Thread.isMainThread { act() } else { DispatchQueue.main.sync(execute: act) }
    }

    public func renderToImage(scene: Scene) -> GPUI.Image? {
        try? state.renderer.renderToImage(scene)
    }
}
#endif
