// Ported from: crates/gpui_ios/src/window.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import GPUI
import GPUIMetal
import QuartzCore
import UIKit

// MARK: - Mutable Main-Thread Window State

/// Main-actor state owned by an `IosWindow`, matching upstream `IosWindowState`.
@MainActor
public final class IosWindowState {
    public let handle: AnyWindowHandle
    public let display: IosDisplay
    public var uiWindow: UIWindow?
    public var viewController: GPUIiOSViewController?
    public var gpuiView: GPUIiOSView?
    public var blurView: UIVisualEffectView?
    public let renderer: MetalRenderer
    public let textInputSession: IosTextInputSession
    var displayLink: DisplayLink?
    var sceneObserver: GPUISceneObserver?
    var keyboardObserver: GPUIKeyboardFrameObserver?

    public var appearance: WindowAppearance
    public var backgroundAppearance: WindowBackgroundAppearance
    public var isActive: Bool = true
    public var isHovered: Bool = false
    public var mousePosition: Point<Pixels> = .zero
    public var modifiers: Modifiers = Modifiers.none()
    public var capslock: Capslock = Capslock()
    public var keyboardHeight: Pixels = .zero
    public var title: String = ""
    var scrollMomentum = ScrollMomentum()

    // GPUI Window Callbacks
    var requestFrameCallback: ((RequestFrameOptions) -> Void)?
    var inputCallback: ((PlatformInput) -> DispatchEventResult)?
    var activeStatusChangeCallback: ((Bool) -> Void)?
    var hoverStatusChangeCallback: ((Bool) -> Void)?
    var resizeCallback: ((Size<Pixels>, Float) -> Void)?
    var movedCallback: (() -> Void)?
    var shouldCloseCallback: (() -> Bool)?
    var hitTestWindowControlCallback: (() -> Bool?)?
    var closeCallback: (() -> Void)?
    var appearanceChangedCallback: (() -> Void)?

    init(
        handle: AnyWindowHandle,
        display: IosDisplay,
        renderer: MetalRenderer,
        appearance: WindowAppearance,
        backgroundAppearance: WindowBackgroundAppearance
    ) {
        self.handle = handle
        self.display = display
        self.renderer = renderer
        self.textInputSession = IosTextInputSession.new()
        self.appearance = appearance
        self.backgroundAppearance = backgroundAppearance
    }

    func bounds() -> Bounds<Pixels> {
        if let view = gpuiView, view.bounds.width > 0, view.bounds.height > 0 {
            let rect = view.bounds
            return Bounds(
                origin: Point(x: px(Float(rect.origin.x)), y: px(Float(rect.origin.y))),
                size: Size(width: px(Float(rect.size.width)), height: px(Float(rect.size.height)))
            )
        }
        if let win = uiWindow, win.bounds.width > 0, win.bounds.height > 0 {
            let rect = win.bounds
            return Bounds(
                origin: Point(x: px(Float(rect.origin.x)), y: px(Float(rect.origin.y))),
                size: Size(width: px(Float(rect.size.width)), height: px(Float(rect.size.height)))
            )
        }
        return display.bounds()
    }

    func contentSize() -> Size<Pixels> {
        let b = bounds()
        let effectiveHeight = max(0.0, b.size.height.value - keyboardHeight.value)
        return Size(width: b.size.width, height: px(effectiveHeight))
    }

    func scaleFactor() -> Float {
        #if !os(visionOS)
        if let screenScale = uiWindow?.windowScene?.screen.scale ?? gpuiView?.window?.windowScene?.screen.scale,
           screenScale > 0
        {
            return Float(screenScale)
        }
        #endif
        return display.scaleFactor()
    }

    func safeAreaInsets() -> Edges<Pixels> {
        let insets = gpuiView?.safeAreaInsets ?? uiWindow?.safeAreaInsets ?? .zero
        let bottomInset = max(Float(insets.bottom), keyboardHeight.value)
        return Edges(
            top: px(Float(insets.top)),
            right: px(Float(insets.right)),
            bottom: px(bottomInset),
            left: px(Float(insets.left))
        )
    }

    // MARK: - Kinetic Scroll Momentum

    func startScrollMomentum(velocityX: Float, velocityY: Float, position: Point<Pixels>) {
        scrollMomentum = ScrollMomentum(
            velocityX: velocityX,
            velocityY: velocityY,
            position: position,
            lastTick: ContinuousClock.now,
            active: true
        )
    }

    func cancelScrollMomentum() {
        if scrollMomentum.active {
            let pos = scrollMomentum.position
            scrollMomentum.active = false
            scrollMomentum.velocityX = 0.0
            scrollMomentum.velocityY = 0.0
            scrollMomentum.lastTick = nil
            _ = inputCallback?(
                .scrollWheel(
                    ScrollWheelEvent(
                        position: pos,
                        delta: .pixels(.zero),
                        modifiers: modifiers,
                        touchPhase: .ended
                    )
                )
            )
        }
    }

    /// Advances kinetic scroll momentum by one vsync tick using UIScrollView's normal deceleration
    /// rate (`0.998` per millisecond), matching upstream `IosWindow::tick_scroll_momentum`.
    func tickScrollMomentum() {
        guard scrollMomentum.active else { return }

        let now = ContinuousClock.now
        let previous = scrollMomentum.lastTick ?? now
        scrollMomentum.lastTick = now

        let elapsed = previous.duration(to: now)
        let dtSeconds = max(
            0.0,
            min(
                0.1,
                Float(elapsed.components.seconds) + Float(elapsed.components.attoseconds) * 1e-18
            )
        )
        guard dtSeconds > 0.0 else { return }

        let dtMs = dtSeconds * 1000.0
        let decay = powf(0.998, dtMs)
        scrollMomentum.velocityX *= decay
        scrollMomentum.velocityY *= decay

        let speed = hypot(scrollMomentum.velocityX, scrollMomentum.velocityY)
        if speed < 5.0 {
            let endPos = scrollMomentum.position
            scrollMomentum.active = false
            scrollMomentum.velocityX = 0.0
            scrollMomentum.velocityY = 0.0
            scrollMomentum.lastTick = nil
            _ = inputCallback?(
                .scrollWheel(
                    ScrollWheelEvent(
                        position: endPos,
                        delta: .pixels(.zero),
                        modifiers: modifiers,
                        touchPhase: .ended
                    )
                )
            )
            return
        }

        let dx = scrollMomentum.velocityX * dtSeconds
        let dy = scrollMomentum.velocityY * dtSeconds
        _ = inputCallback?(
            .scrollWheel(
                ScrollWheelEvent(
                    position: scrollMomentum.position,
                    delta: .pixels(Point(x: px(dx), y: px(dy))),
                    modifiers: modifiers,
                    touchPhase: .moved
                )
            )
        )
    }

    func updateBackgroundAppearance(_ newAppearance: WindowBackgroundAppearance) {
        backgroundAppearance = newAppearance
        let isTransparent = newAppearance != .opaque
        renderer.updateTransparency(isTransparent)
        gpuiView?.isOpaque = !isTransparent
        gpuiView?.metalLayer?.isOpaque = !isTransparent

        if newAppearance == .blurred {
            if blurView == nil, let container = viewController?.view, let gpuiView {
                let effect = UIBlurEffect(style: .systemMaterial)
                let blur = UIVisualEffectView(effect: effect)
                blur.frame = container.bounds
                blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.insertSubview(blur, belowSubview: gpuiView)
                blurView = blur
            }
        } else if let existingBlur = blurView {
            existingBlur.removeFromSuperview()
            blurView = nil
        }
    }
}

// MARK: - iOS PlatformWindow Implementation (`IosWindow`)

/// UIKit + `CAMetalLayer` + `CADisplayLink` implementation of `PlatformWindow` for iOS and visionOS.
// PORT NOTE: Synchronizes access to `@MainActor` `IosWindowState` via `onMain` helper so `PlatformWindow`
// satisfies `Sendable` under Swift 6 strict concurrency while executing all UIKit/Metal work on main.
public final class IosWindow: PlatformWindow, @unchecked Sendable {
    public let handle: AnyWindowHandle
    private let state: IosWindowState

    public init(
        handle: AnyWindowHandle,
        options: WindowOptions,
        instanceBufferPool: InstanceBufferPool = InstanceBufferPool()
    ) {
        self.handle = handle
        self.state = Self.onMain {
            Self.createStateOnMain(
                handle: handle,
                options: options,
                instanceBufferPool: instanceBufferPool
            )
        }
    }

    /// Creates a new `IosWindow` matching upstream `IosWindow::new(handle, options)`.
    public static func new(
        _ handle: AnyWindowHandle,
        _ options: WindowOptions
    ) throws -> IosWindow {
        IosWindow(handle: handle, options: options)
    }

    @MainActor
    private static func createStateOnMain(
        handle: AnyWindowHandle,
        options: WindowOptions,
        instanceBufferPool: InstanceBufferPool
    ) -> IosWindowState {
        let display = IosDisplay.primary()
        let initialAppearance = detectSystemAppearance()
        let isTransparent = options.windowBackground != .opaque
        let renderer = MetalRenderer.new(instanceBufferPool, isTransparent)

        let windowState = IosWindowState(
            handle: handle,
            display: display,
            renderer: renderer,
            appearance: initialAppearance,
            backgroundAppearance: options.windowBackground
        )
        if let title = options.titlebar?.title {
            windowState.title = title
        }

        // Resolve active UIWindowScene if running inside a UIKit application host.
        var activeWindowScene: UIWindowScene?
        for scene in UIApplication.shared.connectedScenes {
            if let ws = scene as? UIWindowScene {
                if ws.activationState == .foregroundActive {
                    activeWindowScene = ws
                    break
                }
                if activeWindowScene == nil {
                    activeWindowScene = ws
                }
            }
        }

        let displayBounds = options.windowBounds?.bounds ?? display.bounds()
        let initialFrame = CGRect(
            x: CGFloat(displayBounds.origin.x.value),
            y: CGFloat(displayBounds.origin.y.value),
            width: max(1.0, CGFloat(displayBounds.size.width.value)),
            height: max(1.0, CGFloat(displayBounds.size.height.value))
        )

        let uiWindow: UIWindow
        if let windowScene = activeWindowScene {
            // Reuse scene's existing window if unconfigured or create a dedicated window in the scene.
            uiWindow = UIWindow(windowScene: windowScene)
            if uiWindow.bounds.width > 0 && uiWindow.bounds.height > 0 {
                // Keep scene-assigned full-screen bounds on iPhone/iPad.
            } else {
                uiWindow.frame = initialFrame
            }
        } else {
            uiWindow = UIWindow(frame: initialFrame)
        }

        let gpuiView = GPUIiOSView(frame: uiWindow.bounds.width > 0 ? uiWindow.bounds : initialFrame)
        let viewController = GPUIiOSViewController(gpuiView: gpuiView, windowState: windowState)

        windowState.uiWindow = uiWindow
        windowState.gpuiView = gpuiView
        windowState.viewController = viewController

        gpuiView.attach(windowState: windowState)
        windowState.textInputSession.attachHostView(gpuiView, windowState: windowState)

        // Bind GPUI's `MetalRenderer` directly onto `GPUIiOSView`'s `CAMetalLayer`.
        if let metalLayer = gpuiView.metalLayer {
            let scale = windowState.scaleFactor()
            metalLayer.contentsScale = CGFloat(scale)
            renderer.replaceLayer(metalLayer)
            let w = max(1.0, Float(gpuiView.bounds.width))
            let h = max(1.0, Float(gpuiView.bounds.height))
            renderer.updateDrawableSize(
                Size(
                    width: DevicePixels(Int32((w * scale).rounded(.up))),
                    height: DevicePixels(Int32((h * scale).rounded(.up)))
                )
            )
        }

        uiWindow.rootViewController = viewController
        windowState.updateBackgroundAppearance(options.windowBackground)

        if options.show {
            if options.focus {
                uiWindow.makeKeyAndVisible()
            } else {
                uiWindow.isHidden = false
            }
            _ = gpuiView.becomeFirstResponder()
        }

        // Attach CADisplayLink vsync driver and lifecycle observers.
        let link = DisplayLink { [weak windowState] in
            guard let windowState else { return }
            windowState.tickScrollMomentum()
            windowState.requestFrameCallback?(RequestFrameOptions())
        }
        windowState.displayLink = link
        windowState.sceneObserver = GPUISceneObserver(windowState: windowState, scene: activeWindowScene)
        windowState.keyboardObserver = GPUIKeyboardFrameObserver(windowState: windowState)
        link.start()

        return windowState
    }

    deinit {
        let windowState = state
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                windowState.displayLink?.stop()
                windowState.textInputSession.tearDown()
                windowState.closeCallback?()
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    windowState.displayLink?.stop()
                    windowState.textInputSession.tearDown()
                    windowState.closeCallback?()
                }
            }
        }
    }

    // PORT NOTE: Transports main-thread return values from `MainActor.assumeIsolated` without
    // requiring `T: Sendable` (e.g., `UnsafeMutableRawPointer?` or `any PlatformInputHandlerProtocol`).
    private struct MainResultBox<T>: @unchecked Sendable {
        let value: T
    }

    private static func onMain<T>(_ work: @MainActor () throws -> T) rethrows -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                MainResultBox(value: try work())
            }.value
        } else {
            return try DispatchQueue.main.sync {
                try MainActor.assumeIsolated {
                    MainResultBox(value: try work())
                }
            }.value
        }
    }

    private func withState<T>(_ work: @MainActor (IosWindowState) throws -> T) rethrows -> T {
        try Self.onMain {
            try work(self.state)
        }
    }

    // MARK: - Upstream `IosWindow` Public Helpers

    /// Returns the window's root `UIViewController` (`GPUIiOSViewController`) for presenting
    /// system modals (`UIDocumentPickerViewController`, share sheets, etc.), matching upstream
    /// `IosWindow::root_view_controller`.
    @MainActor
    public func rootViewController() -> UIViewController? {
        state.viewController
    }

    /// Re-binds `UIScene` activation/backgrounding observers to the window's current `UIWindowScene`,
    /// matching upstream `IosWindow::register_scene_notifications`.
    public func registerSceneNotifications() {
        withState { st in
            st.sceneObserver = GPUISceneObserver(
                windowState: st,
                scene: st.uiWindow?.windowScene
            )
        }
    }

    /// Accesses the window's `IosTextInputSession` on the main actor.
    @MainActor
    public var textInputSession: IosTextInputSession {
        state.textInputSession
    }

    /// Returns the window's current safe-area insets (including software keyboard overlap on bottom).
    public func safeAreaInsets() -> Edges<Pixels> {
        withState { $0.safeAreaInsets() }
    }

    /// Returns `WindowBounds.fullscreen(bounds())` matching iOS full-window presentation.
    public func windowBounds() -> WindowBounds {
        .fullscreen(bounds())
    }

    /// Notifies the window that a frame draw completed so `IosTextInputSession` can dismiss the
    /// software keyboard when no focused element claimed text input during paint.
    public func completedFrame() {
        withState { st in
            st.textInputSession.completedFrame()
        }
    }

    /// Updates the logical anchor rectangle for the backing UIKit text input view.
    public func updateImePosition(_ bounds: Bounds<Pixels>) {
        withState { st in
            st.textInputSession.updateImePosition(bounds)
        }
    }

    public func setTitle(_ title: String) {
        withState { st in
            st.title = title
            st.viewController?.title = title
        }
    }

    public func backgroundAppearance() -> WindowBackgroundAppearance {
        withState { $0.backgroundAppearance }
    }

    public func setBackgroundAppearance(_ appearance: WindowBackgroundAppearance) {
        withState { st in
            st.updateBackgroundAppearance(appearance)
        }
    }

    public func isSubpixelRenderingSupported() -> Bool {
        false
    }

    // MARK: - Callback Registration (`PlatformWindow` / Upstream Parity)

    public func onRequestFrame(_ callback: @escaping (RequestFrameOptions) -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.requestFrameCallback = box.value }
    }

    public func onInput(_ callback: @escaping (PlatformInput) -> DispatchEventResult) {
        let box = MainResultBox(value: callback)
        withState { $0.inputCallback = box.value }
    }

    public func onActiveStatusChange(_ callback: @escaping (Bool) -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.activeStatusChangeCallback = box.value }
    }

    public func onHoverStatusChange(_ callback: @escaping (Bool) -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.hoverStatusChangeCallback = box.value }
    }

    public func onResize(_ callback: @escaping (Size<Pixels>, Float) -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.resizeCallback = box.value }
    }

    public func onMoved(_ callback: @escaping () -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.movedCallback = box.value }
    }

    public func onShouldClose(_ callback: @escaping () -> Bool) {
        let box = MainResultBox(value: callback)
        withState { $0.shouldCloseCallback = box.value }
    }

    public func onHitTestWindowControl(_ callback: @escaping () -> Bool?) {
        let box = MainResultBox(value: callback)
        withState { $0.hitTestWindowControlCallback = box.value }
    }

    public func onClose(_ callback: @escaping () -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.closeCallback = box.value }
    }

    public func onAppearanceChanged(_ callback: @escaping () -> Void) {
        let box = MainResultBox(value: callback)
        withState { $0.appearanceChangedCallback = box.value }
    }

    // MARK: - PlatformWindow Conformance

    public func bounds() -> Bounds<Pixels> {
        withState { $0.bounds() }
    }

    public func contentSize() -> Size<Pixels> {
        withState { $0.contentSize() }
    }

    public func scaleFactor() -> Float {
        withState { $0.scaleFactor() }
    }

    public func appearance() -> WindowAppearance {
        withState { $0.appearance }
    }

    public func mousePosition() -> Point<Pixels> {
        withState { $0.mousePosition }
    }

    public func modifiers() -> Modifiers {
        withState { $0.modifiers }
    }

    public func capslock() -> Capslock {
        withState { $0.capslock }
    }

    public func activate() {
        withState { st in
            st.uiWindow?.makeKeyAndVisible()
            st.isActive = true
        }
    }

    public func isMaximized() -> Bool {
        true
    }

    public func isActive() -> Bool {
        withState { $0.isActive }
    }

    public func isHovered() -> Bool {
        withState { $0.isHovered }
    }

    public func isFullscreen() -> Bool {
        true
    }

    public func minimize() {
        // iOS windows are managed by UIWindowScene and cannot be minimized programmatically.
    }

    public func zoom() {
        // iOS windows fill their UIWindowScene container.
    }

    public func toggleFullScreen() {
        // iOS windows are always full-container within their scene.
    }

    public func draw(scene: Scene) {
        withState { st in
            st.renderer.draw(scene)
            st.textInputSession.completedFrame()
        }
    }

    public func spriteAtlas() -> any PlatformAtlas {
        withState { $0.renderer.spriteAtlas() }
    }

    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        let box = MainResultBox(value: handler)
        withState { st in
            st.textInputSession.setInputHandler(box.value)
        }
    }

    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        withState { st in
            st.textInputSession.takeInputHandler()
        }
    }

    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        withState { st in
            st.textInputSession.activeInputHandler()
        }
    }

    public func rawNativeViewPtr() -> UnsafeMutableRawPointer? {
        withState { st in
            guard let view = st.gpuiView else { return nil }
            return Unmanaged.passUnretained(view).toOpaque()
        }
    }

    public func display() -> (any PlatformDisplay)? {
        withState { $0.display }
    }

    public func gpuSpecs() -> GpuSpecs? {
        withState { $0.renderer.gpuSpecs() }
    }

    public func renderToImage(scene: Scene) -> Image? {
        withState { st in
            try? st.renderer.renderToImage(scene)
        }
    }

    /// Renders `scene` offscreen to RGBA8 bytes via `MetalRenderer.renderToTexture` (useful for
    /// behavioral verification tests on iOS Simulator as well as snapshot capture).
    public func renderToTexture(
        _ scene: Scene,
        size: Size<DevicePixels>,
        background: Hsla? = nil
    ) throws -> (width: Int, height: Int, rgba: [UInt8]) {
        try withState { st in
            try st.renderer.renderToTexture(scene, size: size, background: background)
        }
    }
}
#endif
