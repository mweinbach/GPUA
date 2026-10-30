// Swift-only: Android ANativeWindow, WgpuRenderer, AChoreographer vsync, and IME window bridge per ADR-0012

import Foundation
import GPUI
#if os(Android)
import CAndroidSys
import CWebGPU
import GPUIWGPU
#endif

// MARK: - Window Callbacks

/// Event and lifecycle callbacks registered on an `AndroidWindow`.
// PORT NOTE: Stores UI-thread window event callbacks matching GPUI platform window conventions.
public struct AndroidWindowCallbacks: @unchecked Sendable {
    public var requestFrame: ((RequestFrameOptions) -> Void)?
    public var input: ((PlatformInput) -> DispatchEventResult)?
    public var activeStatusChange: ((Bool) -> Void)?
    public var hoverStatusChange: ((Bool) -> Void)?
    public var resize: ((Size<Pixels>, Float) -> Void)?
    public var moved: (() -> Void)?
    public var shouldClose: (() -> Bool)?
    public var close: (() -> Void)?
    public var appearanceChanged: (() -> Void)?

    public init(
        requestFrame: ((RequestFrameOptions) -> Void)? = nil,
        input: ((PlatformInput) -> DispatchEventResult)? = nil,
        activeStatusChange: ((Bool) -> Void)? = nil,
        hoverStatusChange: ((Bool) -> Void)? = nil,
        resize: ((Size<Pixels>, Float) -> Void)? = nil,
        moved: (() -> Void)? = nil,
        shouldClose: (() -> Bool)? = nil,
        close: (() -> Void)? = nil,
        appearanceChanged: (() -> Void)? = nil
    ) {
        self.requestFrame = requestFrame
        self.input = input
        self.activeStatusChange = activeStatusChange
        self.hoverStatusChange = hoverStatusChange
        self.resize = resize
        self.moved = moved
        self.shouldClose = shouldClose
        self.close = close
        self.appearanceChanged = appearanceChanged
    }
}

#if os(Android)
// PORT NOTE: Retained for the duration of a single AChoreographer_postFrameCallback64 tick
// and consumed via Unmanaged.takeRetainedValue() on the UI looper thread.
private final class ChoreographerFrameTrampoline: @unchecked Sendable {
    weak var window: AndroidWindow?

    init(window: AndroidWindow) {
        self.window = window
    }
}
#endif

// MARK: - AndroidWindow

/// Android implementation of `PlatformWindow` backed by `ANativeWindow`, `WgpuRenderer` (Vulkan),
/// and `AChoreographer` vsync callbacks.
// PORT NOTE: Synchronized via NSLock so JNI surface/input/vsync callbacks safely coordinate state.
public final class AndroidWindow: PlatformWindow, @unchecked Sendable {
    public let handle: AnyWindowHandle

    private let lock = NSLock()
    private let displayRef: AndroidDisplay
    private var windowAppearance: WindowAppearance
    private var isWindowActive: Bool
    private var isWindowHovered: Bool = false
    private var isWindowFullscreen: Bool = true
    private var windowTitle: String = ""
    private var transparentBackground: Bool
    private var currentInputHandler: (any PlatformInputHandlerProtocol)?
    private var imeVisibleState: Bool = false
    private var touchProcessor = AndroidTouchInputProcessor()
    private var keyTranslator = AndroidKeyEventTranslator()
    private var callbacks = AndroidWindowCallbacks()
    private var frameScheduled: Bool = false
    private var lastFrameTimeNanos: Int64?
    private let fallbackAtlas: any PlatformAtlas = TestAtlas.new()
    private var drawnScene: Scene?
    private var committedImeHistory: [String] = []

    #if os(Android)
    private let gpuContext: GpuContext
    private var nativeWindowPtr: OpaquePointer?
    private var wgpuSurface: WGPUSurface?
    private var renderer: WgpuRenderer?
    #endif

    #if os(Android)
    public init(
        handle: AnyWindowHandle,
        options: WindowOptions,
        display: AndroidDisplay,
        appearance: WindowAppearance = .dark,
        isActive: Bool = true,
        gpuContext: GpuContext
    ) {
        self.handle = handle
        self.displayRef = display
        self.windowAppearance = appearance
        self.isWindowActive = isActive
        self.transparentBackground = options.windowBackground != .opaque
        self.windowTitle = options.titlebar?.title.map { String(describing: $0) } ?? ""
        self.gpuContext = gpuContext
    }
    #endif

    public init(
        handle: AnyWindowHandle = AnyWindowHandle(id: 1),
        options: WindowOptions = WindowOptions(),
        display: AndroidDisplay = AndroidDisplay(),
        appearance: WindowAppearance = .dark,
        isActive: Bool = true
    ) {
        self.handle = handle
        self.displayRef = display
        self.windowAppearance = appearance
        self.isWindowActive = isActive
        self.transparentBackground = options.windowBackground != .opaque
        self.windowTitle = options.titlebar?.title.map { String(describing: $0) } ?? ""
        #if os(Android)
        self.gpuContext = GpuContext()
        #endif
    }

    deinit {
        detachSurface()
    }

    // MARK: - PlatformWindow Conformance

    public func bounds() -> Bounds<Pixels> {
        displayRef.visibleBounds()
    }

    /// Full physical display bounds in logical `Pixels` prior to safe-area inset subtraction.
    public func fullBounds() -> Bounds<Pixels> {
        displayRef.bounds()
    }

    public func contentSize() -> Size<Pixels> {
        displayRef.visibleBounds().size
    }

    public func scaleFactor() -> Float {
        displayRef.scaleFactor()
    }

    public func appearance() -> WindowAppearance {
        lock.lock()
        defer { lock.unlock() }
        return windowAppearance
    }

    public func mousePosition() -> Point<Pixels> {
        lock.lock()
        defer { lock.unlock() }
        return touchProcessor.lastMousePosition
    }

    public func modifiers() -> Modifiers {
        lock.lock()
        defer { lock.unlock() }
        return keyTranslator.modifiers
    }

    public func capslock() -> Capslock {
        lock.lock()
        defer { lock.unlock() }
        return keyTranslator.capslock
    }

    public func activate() {
        setActiveStatus(true)
    }

    public func isMaximized() -> Bool {
        true
    }

    public func isActive() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isWindowActive
    }

    public func isHovered() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isWindowHovered || touchProcessor.isHovering
    }

    public func isFullscreen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isWindowFullscreen
    }

    public func minimize() {}

    public func zoom() {}

    public func toggleFullScreen() {
        lock.lock()
        isWindowFullscreen.toggle()
        lock.unlock()
    }

    public func draw(scene: Scene) {
        lock.lock()
        drawnScene = scene
        #if os(Android)
        let activeRenderer = renderer
        #endif
        lock.unlock()

        #if os(Android)
        activeRenderer?.draw(scene)
        #endif
    }

    public func spriteAtlas() -> any PlatformAtlas {
        #if os(Android)
        lock.lock()
        let activeRenderer = renderer
        lock.unlock()
        if let activeRenderer {
            return activeRenderer.spriteAtlas()
        }
        #endif
        return fallbackAtlas
    }

    public func display() -> (any PlatformDisplay)? {
        displayRef
    }

    public func gpuSpecs() -> GpuSpecs? {
        #if os(Android)
        lock.lock()
        let activeRenderer = renderer
        lock.unlock()
        return activeRenderer?.gpuSpecs()
        #else
        return nil
        #endif
    }

    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? {
        #if os(Android)
        lock.lock()
        let ptr = nativeWindowPtr
        lock.unlock()
        return ptr.map { UnsafeMutableRawPointer($0) }
        #else
        return nil
        #endif
    }

    // MARK: - IME & Text Input Handler

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        lock.lock()
        currentInputHandler = handler
        let shouldShowIme = !imeVisibleState
        imeVisibleState = true
        lock.unlock()

        if shouldShowIme {
            #if os(Android)
            _ = candroid_host_set_ime_visible(true)
            #endif
        }
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        let existing = currentInputHandler
        currentInputHandler = nil
        return existing
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        return currentInputHandler
    }

    @discardableResult
    public func withInputHandler<R>(_ body: (any PlatformInputHandlerProtocol) -> R) -> R? {
        lock.lock()
        guard let handler = currentInputHandler else {
            lock.unlock()
            return nil
        }
        currentInputHandler = nil
        lock.unlock()
        defer {
            lock.lock()
            if currentInputHandler == nil {
                currentInputHandler = handler
            }
            lock.unlock()
        }
        return body(handler)
    }

    /// Explicitly clears the input handler and requests the Android `InputMethodManager` to hide the soft keyboard.
    public func dismissIme() {
        lock.lock()
        currentInputHandler = nil
        let wasVisible = imeVisibleState
        imeVisibleState = false
        lock.unlock()

        if wasVisible {
            #if os(Android)
            _ = candroid_host_set_ime_visible(false)
            #endif
        }
    }

    public var isImeVisible: Bool {
        lock.lock()
        defer { lock.unlock() }
        return imeVisibleState
    }

    public var lastDrawnScene: Scene? {
        lock.lock()
        defer { lock.unlock() }
        return drawnScene
    }

    public var committedImeTexts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return committedImeHistory
    }

    // MARK: - Callback Registration

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        lock.lock()
        callbacks.requestFrame = callback
        lock.unlock()
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        lock.lock()
        callbacks.input = callback
        lock.unlock()
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        lock.lock()
        callbacks.activeStatusChange = callback
        lock.unlock()
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        lock.lock()
        callbacks.hoverStatusChange = callback
        lock.unlock()
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        lock.lock()
        callbacks.resize = callback
        lock.unlock()
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.moved = callback
        lock.unlock()
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        lock.lock()
        callbacks.shouldClose = callback
        lock.unlock()
    }

    public func onClose(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.close = callback
        lock.unlock()
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        lock.lock()
        callbacks.appearanceChanged = callback
        lock.unlock()
    }

    // MARK: - Surface Lifecycle (ANativeWindow + Vulkan WGPUSurface)

    #if os(Android)
    /// Attaches an `ANativeWindow` from `SurfaceHolder.Callback.surfaceCreated`, retaining the window
    /// and initializing a Vulkan-backed `WgpuRenderer`.
    public func attachSurface(
        nativeWindow: OpaquePointer,
        widthPx: Int32 = 0,
        heightPx: Int32 = 0,
        format: Int32 = 0
    ) {
        detachSurface()

        candroid_native_window_acquire(nativeWindow)
        let resolvedW = widthPx > 0 ? widthPx : max(1, candroid_native_window_get_width(nativeWindow))
        let resolvedH = heightPx > 0 ? heightPx : max(1, candroid_native_window_get_height(nativeWindow))
        _ = format

        displayRef.updateSize(widthPx: resolvedW, heightPx: resolvedH)

        lock.lock()
        self.nativeWindowPtr = nativeWindow
        let transparent = self.transparentBackground
        let sharedGpu = self.gpuContext
        let resizeCb = self.callbacks.resize
        lock.unlock()

        let instance = sharedGpu.context?.instance ?? WgpuContext.instance()
        if let surface = WgpuContext.createAndroidSurface(
            instance: instance,
            window: UnsafeMutableRawPointer(nativeWindow)
        ) {
            let config = WgpuSurfaceConfig(
                size: Size(width: DevicePixels(resolvedW), height: DevicePixels(resolvedH)),
                transparent: transparent
            )
            do {
                let createdRenderer = try WgpuRenderer.new(
                    gpuContext: sharedGpu,
                    window: surface,
                    config: config
                )
                lock.lock()
                self.wgpuSurface = surface
                self.renderer = createdRenderer
                lock.unlock()
            } catch {
                androidLog(.error, "AndroidWindow failed to create WgpuRenderer: \(error)")
                wgpuSurfaceRelease(surface)
            }
        }

        resizeCb?(contentSize(), scaleFactor())
        requestFrame()
    }
    #endif

    /// Handles `SurfaceHolder.Callback.surfaceChanged` or simulated resize updates.
    public func surfaceChanged(
        widthPx: Int32,
        heightPx: Int32,
        format: Int32 = 0,
        density: Float? = nil,
        refreshRateHz: Float? = nil
    ) {
        _ = format
        let clampedW = max(1, widthPx)
        let clampedH = max(1, heightPx)
        displayRef.updateSize(
            widthPx: clampedW,
            heightPx: clampedH,
            density: density,
            refreshRateHz: refreshRateHz
        )

        lock.lock()
        #if os(Android)
        let activeRenderer = renderer
        #endif
        let resizeCb = callbacks.resize
        lock.unlock()

        #if os(Android)
        activeRenderer?.updateDrawableSize(
            Size(width: DevicePixels(clampedW), height: DevicePixels(clampedH))
        )
        #endif

        resizeCb?(contentSize(), scaleFactor())
        requestFrame()
    }

    /// Immediately tears down the `WGPUSurface` and releases the `ANativeWindow` reference
    /// while preserving the shared `WgpuContext` (`WGPUDevice` + `WGPUQueue`) across surface recreation.
    public func detachSurface() {
        lock.lock()
        touchProcessor.cancelMomentum()
        frameScheduled = false
        lastFrameTimeNanos = nil
        #if os(Android)
        let oldRenderer = renderer
        let oldSurface = wgpuSurface
        let oldNativeWindow = nativeWindowPtr
        renderer = nil
        wgpuSurface = nil
        nativeWindowPtr = nil
        #endif
        lock.unlock()

        #if os(Android)
        oldRenderer?.unconfigureSurface()
        oldRenderer?.destroy()
        if let oldSurface {
            wgpuSurfaceRelease(oldSurface)
        }
        if let oldNativeWindow {
            candroid_native_window_release(oldNativeWindow)
        }
        #endif
    }

    // MARK: - Vsync Scheduling (AChoreographer)

    /// Schedules a single vsync callback via `AChoreographer_postFrameCallback64` (or Kotlin host fallback).
    public func requestFrame() {
        lock.lock()
        if frameScheduled {
            lock.unlock()
            return
        }
        frameScheduled = true
        lock.unlock()

        #if os(Android)
        if let choreographer = candroid_choreographer_get_instance() {
            let trampoline = ChoreographerFrameTrampoline(window: self)
            let rawPtr = Unmanaged.passRetained(trampoline).toOpaque()
            candroid_choreographer_post_frame_callback64(
                choreographer,
                { frameTimeNanos, userData in
                    guard let userData else { return }
                    let tramp = Unmanaged<ChoreographerFrameTrampoline>.fromOpaque(userData).takeRetainedValue()
                    tramp.window?.stepFrame(frameTimeNanos: frameTimeNanos)
                },
                rawPtr
            )
        } else {
            _ = candroid_host_request_frame()
        }
        #endif
    }

    /// Advances inertial scroll momentum and invokes the registered frame callback for a vsync tick.
    public func stepFrame(
        frameTimeNanos: Int64,
        options: RequestFrameOptions = RequestFrameOptions()
    ) {
        let defaultDt = Float(displayRef.currentMetrics().vsyncInterval)

        lock.lock()
        frameScheduled = false
        let dt: Float
        if let prevNanos = lastFrameTimeNanos, frameTimeNanos > prevNanos {
            let deltaSec = Double(frameTimeNanos - prevNanos) / 1_000_000_000.0
            dt = Float(min(max(deltaSec, 0.001), 0.1))
        } else {
            dt = defaultDt
        }
        lastFrameTimeNanos = frameTimeNanos

        let liveMods = keyTranslator.modifiers
        let momentumEvent = touchProcessor.stepMomentum(dt: dt, modifiers: liveMods)
        let hasRemainingMomentum = touchProcessor.scrollMomentum != nil
        let inputCb = callbacks.input
        let frameCb = callbacks.requestFrame
        lock.unlock()

        if let momentumEvent {
            _ = inputCb?(.scrollWheel(momentumEvent))
        }

        frameCb?(options)

        if hasRemainingMomentum {
            requestFrame()
        }
    }

    public var isFrameScheduled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return frameScheduled
    }

    // MARK: - Input, Safe-Area Insets & Appearance Dispatch

    /// Translates and dispatches an Android touch/pointer `MotionEvent`.
    @discardableResult
    public func handleTouchEvent(
        rawAction: Int32,
        pointers: [AndroidPointerSample],
        metaState: Int32 = 0,
        buttonState: Int32 = 0,
        vScroll: Float = 0.0,
        hScroll: Float = 0.0,
        eventTimeSeconds: Double = 0.0
    ) -> [PlatformInput] {
        let scale = displayRef.scaleFactor()

        lock.lock()
        let wasHovering = isWindowHovered || touchProcessor.isHovering
        let liveMods: Modifiers? = metaState != 0 ? nil : keyTranslator.modifiers
        let events = touchProcessor.processMotionEvent(
            rawAction: rawAction,
            pointers: pointers,
            scaleFactor: scale,
            metaState: metaState,
            buttonState: buttonState,
            vScroll: vScroll,
            hScroll: hScroll,
            eventTimeSeconds: eventTimeSeconds,
            liveModifiers: liveMods
        )
        let nowHovering = isWindowHovered || touchProcessor.isHovering
        let hasMomentum = touchProcessor.scrollMomentum != nil
        let hoverCb = (wasHovering != nowHovering) ? callbacks.hoverStatusChange : nil
        let inputCb = callbacks.input
        lock.unlock()

        hoverCb?(nowHovering)
        for event in events {
            _ = inputCb?(event)
        }
        if !events.isEmpty || hasMomentum {
            requestFrame()
        }
        return events
    }

    /// Translates and dispatches an Android hardware or soft `KeyEvent`.
    @discardableResult
    public func handleKeyEvent(
        action: Int32,
        keyCode: Int32,
        metaState: Int32 = 0,
        repeatCount: Int32 = 0,
        unicodeChar: Int32 = 0,
        scanCode: Int32 = 0
    ) -> [PlatformInput] {
        lock.lock()
        let events = keyTranslator.translate(
            action: action,
            keyCode: keyCode,
            metaState: metaState,
            repeatCount: repeatCount,
            unicodeChar: unicodeChar,
            scanCode: scanCode
        )
        let inputCb = callbacks.input
        lock.unlock()

        for event in events {
            let result = inputCb?(event) ?? DispatchEventResult()
            if result.propagate,
               case .keyDown(let keyDown) = event,
               keyDown.keystroke.modifiers.isSubset(of: .shift()),
               let keyChar = keyDown.keystroke.keyChar,
               !keyChar.isEmpty,
               !keyChar.unicodeScalars.contains(where: { $0.value < 0x20 || (0x7F...0x9F).contains($0.value) }) {
                _ = withInputHandler { handler in
                    if handler.queryAcceptsTextInput() {
                        handler.replaceTextInRange(rangeUtf16: nil, text: keyChar)
                    }
                }
            }
        }
        if !events.isEmpty {
            requestFrame()
        }
        return events
    }

    /// Commits composed UTF-8 text from Android's `InputConnection.commitText`.
    public func commitImeText(_ text: String) {
        guard !text.isEmpty else { return }

        lock.lock()
        committedImeHistory.append(text)
        let inputCb = callbacks.input
        lock.unlock()

        let routedToInputHandler = withInputHandler { handler -> Bool in
            guard handler.queryAcceptsTextInput() else { return false }
            handler.replaceTextInRange(rangeUtf16: nil, text: text)
            return true
        } ?? false

        if routedToInputHandler {
            requestFrame()
            return
        }

        let keystroke = Keystroke(
            modifiers: .none(),
            key: text,
            keyChar: text,
            nativeKeyCode: nil
        )
        let event = PlatformInput.keyDown(
            KeyDownEvent(
                keystroke: keystroke,
                isHeld: false,
                preferCharacterInput: true
            )
        )
        _ = inputCb?(event)
        requestFrame()
    }

    /// Updates marked composition preedit text from Android's `InputConnection.setComposingText`.
    public func setComposingText(_ text: String, newSelectedRangeUtf16: Range<Int>? = nil) {
        _ = withInputHandler { handler in
            guard handler.queryAcceptsTextInput() else { return }
            handler.replaceAndMarkTextInRange(
                rangeUtf16: nil,
                newText: text,
                newSelectedRange: newSelectedRangeUtf16
            )
        }
        requestFrame()
    }

    /// Commits/unmarks active preedit text from Android's `InputConnection.finishComposingText`.
    public func finishComposingText() {
        _ = withInputHandler { handler in
            guard handler.queryAcceptsTextInput() else { return }
            handler.unmarkText()
        }
        requestFrame()
    }

    /// Handles Android `InputConnection.deleteSurroundingText` from soft keyboards.
    public func deleteSurroundingText(beforeLength: Int, afterLength: Int) {
        guard beforeLength > 0 || afterLength > 0 else { return }
        lock.lock()
        let inputCb = callbacks.input
        lock.unlock()

        if beforeLength > 0 {
            let bs = Keystroke(modifiers: .none(), key: "backspace", keyChar: nil)
            for _ in 0..<beforeLength {
                _ = inputCb?(.keyDown(KeyDownEvent(keystroke: bs, isHeld: false)))
                _ = inputCb?(.keyUp(KeyUpEvent(keystroke: bs)))
            }
        }
        if afterLength > 0 {
            let del = Keystroke(modifiers: .none(), key: "delete", keyChar: nil)
            for _ in 0..<afterLength {
                _ = inputCb?(.keyDown(KeyDownEvent(keystroke: del, isHeld: false)))
                _ = inputCb?(.keyUp(KeyUpEvent(keystroke: del)))
            }
        }
        requestFrame()
    }

    /// Updates safe-area insets (`WindowInsets`: status bar, navigation bar, display cutout, IME)
    /// and notifies GPUI of the resulting logical viewport resize.
    public func updateSafeAreaInsets(topPx: Int32, leftPx: Int32, bottomPx: Int32, rightPx: Int32) {
        displayRef.updateSafeAreaInsets(
            topPx: topPx,
            leftPx: leftPx,
            bottomPx: bottomPx,
            rightPx: rightPx
        )
        lock.lock()
        let resizeCb = callbacks.resize
        lock.unlock()

        resizeCb?(contentSize(), scaleFactor())
        requestFrame()
    }

    /// Updates dark/light `WindowAppearance` from Android `Configuration.uiMode`.
    public func updateAppearance(_ newAppearance: WindowAppearance) {
        lock.lock()
        guard windowAppearance != newAppearance else {
            lock.unlock()
            return
        }
        windowAppearance = newAppearance
        let appearanceCb = callbacks.appearanceChanged
        lock.unlock()

        appearanceCb?()
        requestFrame()
    }

    /// Updates window active focus state from Activity `onResume` / `onPause`.
    public func setActiveStatus(_ active: Bool) {
        lock.lock()
        guard isWindowActive != active else {
            lock.unlock()
            return
        }
        isWindowActive = active
        if !active {
            touchProcessor.cancelMomentum()
        }
        let activeCb = callbacks.activeStatusChange
        lock.unlock()

        activeCb?(active)
        if active {
            requestFrame()
        }
    }

    /// Invokes close callbacks when the hosting Activity is finishing.
    public func notifyClose() {
        lock.lock()
        let closeCb = callbacks.close
        lock.unlock()
        closeCb?()
    }
}
