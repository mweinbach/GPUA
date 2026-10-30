// Ported from: crates/gpui_macos/src/gpui_surface.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import Foundation
import GPUI
import GPUIMetal
import QuartzCore

/// Secondary `NSView` backed by a `SurfaceRenderer`'s `CAMetalLayer` that forwards input to the host window.
final class GPUISurfaceView: NSView {
    private let metalLayerInstance: CAMetalLayer
    weak var windowState: MacWindowState?

    init(frame frameRect: NSRect, metalLayer: CAMetalLayer) {
        self.metalLayerInstance = metalLayer
        super.init(frame: frameRect)
        self.wantsLayer = true
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

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas.reversed() {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect,
        ]
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    private func handleSurfaceViewEvent(_ nativeEvent: NSEvent) {
        guard let windowState else { return }
        let viewHeight = px(Float(bounds.size.height))
        guard var event = platformInputFromNative(
            nativeEvent,
            windowHeight: viewHeight,
            nativeView: self
        ) else {
            return
        }

        let isMouseDown: Bool
        if case .mouseDown = event {
            isMouseDown = true
        } else {
            isMouseDown = false
        }

        // Convert Control + Left-Click into Right-Click matching main window behavior.
        switch event {
        case .mouseDown(var down) where down.button == .left && down.modifiers.control:
            down.button = .right
            down.modifiers.control = false
            down.clickCount = 1
            event = .mouseDown(down)
        case .mouseUp(var up) where up.button == .left && up.modifiers.control:
            up.button = .right
            up.modifiers.control = false
            event = .mouseUp(up)
        default:
            break
        }

        let nativeViewPtr = Unmanaged.passUnretained(self).toOpaque()
        windowState.dispatchSurfaceEvent(nativeViewPtr: nativeViewPtr, input: event)

        if isMouseDown, let hostWindow = window, let mainView = windowState.nativeView {
            hostWindow.makeFirstResponder(mainView)
        }
    }

    override func mouseDown(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func mouseUp(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func rightMouseDown(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func rightMouseUp(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func otherMouseDown(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func otherMouseUp(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func mouseMoved(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func mouseExited(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func mouseDragged(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func rightMouseDragged(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func otherMouseDragged(with event: NSEvent) { handleSurfaceViewEvent(event) }
    override func scrollWheel(with event: NSEvent) { handleSurfaceViewEvent(event) }

    override func keyDown(with event: NSEvent) {
        windowState?.nativeView?.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        windowState?.nativeView?.keyUp(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        windowState?.nativeView?.flagsChanged(with: event)
    }
}

/// Secondary GPUI rendering surface embeddable inside any container `NSView`.
// PORT NOTE: Owns a GPUISurfaceView and SurfaceRenderer manipulated on the main thread via MacWindowState.
public final class GpuiSurface: @unchecked Sendable {
    private let renderer: SurfaceRenderer
    private let nativeView: GPUISurfaceView
    private var retainedWindowState: Unmanaged<MacWindowState>?

    public init(shared: SharedRenderResources, transparent: Bool) {
        let renderer = SurfaceRenderer.new(shared, transparent)
        let view = MainActor.assumeIsolated {
            GPUISurfaceView(
                frame: NSRect(x: 0.0, y: 0.0, width: 100.0, height: 100.0),
                metalLayer: renderer.layer()
            )
        }
        self.renderer = renderer
        self.nativeView = view
        self.retainedWindowState = nil
    }

    public static func new(_ shared: SharedRenderResources, _ transparent: Bool) -> GpuiSurface {
        GpuiSurface(shared: shared, transparent: transparent)
    }

    public func nativeViewPtr() -> UnsafeMutableRawPointer {
        Unmanaged.passUnretained(nativeView).toOpaque()
    }

    public func layerPtr() -> UnsafeMutableRawPointer {
        renderer.layerPtr()
    }

    public func draw(_ scene: Scene) {
        renderer.draw(scene)
    }

    public func updateDrawableSize(_ size: Size<DevicePixels>) {
        renderer.updateDrawableSize(size)
    }

    public func updateTransparency(_ transparent: Bool) {
        renderer.updateTransparency(transparent)
    }

    public func contentSize() -> Size<Pixels> {
        let frame = MainActor.assumeIsolated { nativeView.frame }
        return size(px(Float(frame.size.width)), px(Float(frame.size.height)))
    }

    public func scaleFactor() -> Float {
        MainActor.assumeIsolated {
            if let window = nativeView.window {
                return Float(window.backingScaleFactor)
            }
            if let screen = NSScreen.main {
                return Float(screen.backingScaleFactor)
            }
            return 2.0
        }
    }

    public func setContentsScale(_ scale: Double) {
        MainActor.assumeIsolated {
            nativeView.layer?.contentsScale = CGFloat(scale)
        }
    }

    public func setWindowState(_ rawStatePtr: UnsafeRawPointer?) {
        if let prev = retainedWindowState {
            prev.release()
            retainedWindowState = nil
        }
        if let rawStatePtr {
            let mutablePtr = UnsafeMutableRawPointer(mutating: rawStatePtr)
            let unmanaged = Unmanaged<MacWindowState>.fromOpaque(mutablePtr)
            let state = unmanaged.takeUnretainedValue()
            retainedWindowState = unmanaged
            MainActor.assumeIsolated {
                nativeView.windowState = state
            }
        } else {
            MainActor.assumeIsolated {
                nativeView.windowState = nil
            }
        }
    }

    deinit {
        if let prev = retainedWindowState {
            prev.release()
            retainedWindowState = nil
        }
        let view = nativeView
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                view.removeFromSuperview()
            }
        } else {
            let transferredView = view
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    transferredView.removeFromSuperview()
                }
            }
        }
    }
}
#endif
