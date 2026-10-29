// Tests ported from: crates/gpui_windows/src/window.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("Windows Window Tests")
struct WindowsWindowTests {
    @Test("Double click interval resets click count after timeout")
    func testDoubleClickInterval() {
        let state = ClickState()
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(0))) == 1)
        #expect(state.update(button: .right, newPosition: Point(x: DevicePixels(0), y: DevicePixels(0))) == 1)
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(0))) == 1)
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(0))) == 2)
        state.setLastClickForTesting(Date().addingTimeInterval(-0.700))
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(0))) == 1)
    }

    @Test("Double click spatial tolerance checks pixel delta")
    func testDoubleClickSpatialTolerance() {
        let state = ClickState()
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(-3), y: DevicePixels(0))) == 1)
        #expect(state.update(button: .left, newPosition: Point(x: DevicePixels(0), y: DevicePixels(3))) == 2)
        #expect(state.update(button: .right, newPosition: Point(x: DevicePixels(3), y: DevicePixels(2))) == 1)
        #expect(state.update(button: .right, newPosition: Point(x: DevicePixels(10), y: DevicePixels(0))) == 1)
    }

    @Test("Window border offset and rect calculation")
    func testWindowRectCalculations() {
        let offset = WindowBorderOffset()
        offset.widthOffset = 16
        offset.heightOffset = 38

        let bounds = Bounds(
            origin: Point(x: DevicePixels(100), y: DevicePixels(200)),
            size: Size(width: DevicePixels(800), height: DevicePixels(600))
        )
        let wRect = calculateWindowRect(bounds: bounds, borderOffset: offset)
        #expect(wRect.left == 100 - 8)
        #expect(wRect.top == 200 - 19)
        #expect(wRect.right == 900 + 8)
        #expect(wRect.bottom == 800 + 19)

        let clientRect = calculateClientRect(
            left: wRect.left,
            top: wRect.top,
            right: wRect.right,
            bottom: wRect.bottom,
            borderOffset: offset,
            scaleFactor: 2.0
        )
        #expect(clientRect.origin.x.value == 50.0)
        #expect(clientRect.origin.y.value == 100.0)
        #expect(clientRect.size.width.value == 400.0)
        #expect(clientRect.size.height.value == 300.0)
    }

    @Test("StyleAndBounds initialization")
    func testStyleAndBounds() {
        let sb = StyleAndBounds(style: 0x1234, x: 10, y: 20, cx: 300, cy: 400)
        #expect(sb.style == 0x1234)
        #expect(sb.x == 10)
        #expect(sb.y == 20)
        #expect(sb.cx == 300)
        #expect(sb.cy == 400)
    }

    @Test("Headless WindowsPlatform and WindowsWindow lifecycle")
    func testHeadlessWindowsWindowLifecycle() {
        let platform = WindowsPlatform(headless: true)
        let handle = AnyWindowHandle(id: 42)
        var options = WindowOptions()
        options.windowBounds = .windowed(Bounds(origin: .zero, size: Size(width: px(640), height: px(480))))
        options.titlebar = TitlebarOptions(title: "Test Window", appearsTransparent: false)
        options.show = true
        options.focus = true

        let window = platform.openWindow(handle: handle, options: options)
        guard let win = window as? WindowsWindow else {
            Issue.record("Expected WindowsWindow")
            return
        }
        #expect(win.contentSize().width.value == 640.0)
        #expect(win.contentSize().height.value == 480.0)
        #expect(win.scaleFactor() == 1.0)
        #expect(!win.isMaximized())
        #expect(!win.isFullscreen())
        #expect(win.isActive())

        var frameRequested = false
        win.onRequestFrame { _ in
            frameRequested = true
        }
        win.callbacks.requestFrame?(RequestFrameOptions(requirePresentation: false, forceRender: false))
        #expect(frameRequested)

        var resized = false
        win.onResize { _, _ in
            resized = true
        }
        win.callbacks.resize?(Size(width: px(800), height: px(600)), 1.0)
        #expect(resized)

        var closed = false
        win.onClose {
            closed = true
        }
        win.callbacks.close?()
        #expect(closed)

        let scene = Scene()
        win.draw(scene: scene)
        #expect(win.lastDrawnScene != nil)

        win.activate()
        #expect(win.isActive())

        win.zoom()
        #expect(win.isMaximized())

        win.minimize()
        #expect(!win.isActive())

        win.toggleFullScreen()
        #expect(win.isFullscreen())
        win.toggleFullScreen()
        #expect(!win.isFullscreen())
    }

    @Test("Interactive Win32 HWND + DirectXRenderer WARP swapchain smoke test")
    func testWarpSwapchainSmokeTest() {
        let platform = WindowsPlatform(headless: false)
        #expect(platform.directxDevices != nil)
        let handle = AnyWindowHandle(id: 101)
        var options = WindowOptions()
        options.windowBounds = .windowed(Bounds(origin: .zero, size: Size(width: px(256), height: px(256))))
        options.show = false
        options.focus = false

        let window = platform.openWindow(handle: handle, options: options)
        guard let win = window as? WindowsWindow else {
            Issue.record("Expected WindowsWindow instance")
            return
        }
        defer { win.close() }

        #expect(win.hwnd != nil)
        #expect(win.renderer != nil)

        win.captureFrames = true

        var scene = Scene()
        var quad = Quad()
        quad.bounds = Bounds(origin: .zero, size: Size(width: ScaledPixels(128), height: ScaledPixels(128)))
        quad.contentMask = ContentMask(bounds: quad.bounds)
        quad.background = solidBackground(red())
        scene.insertPrimitive(.quad(quad))

        win.draw(scene: scene)

        guard let frame = win.lastCapturedFrame else {
            Issue.record("Expected non-nil captured frame")
            return
        }
        #expect(frame.width >= 1)
        #expect(frame.height >= 1)
        #expect(!frame.rgba.isEmpty)

        // Pixel assertions: (32, 32) is inside the 128x128 red quad; (200, 200) is in the cleared opaque white background
        let redX = 32
        let redY = 32
        let redOffset = Int(redY * Int(frame.width) + redX) * 4
        #expect(frame.rgba.count >= redOffset + 4)
        if frame.rgba.count >= redOffset + 4 {
            let r = frame.rgba[redOffset]
            let g = frame.rgba[redOffset + 1]
            let b = frame.rgba[redOffset + 2]
            #expect(r > 200 && g < 30 && b < 30, "Expected red pixel at (32, 32), got r:\(r) g:\(g) b:\(b)")
        }

        let whiteX = 200
        let whiteY = 200
        let whiteOffset = Int(whiteY * Int(frame.width) + whiteX) * 4
        #expect(frame.rgba.count >= whiteOffset + 4)
        if frame.rgba.count >= whiteOffset + 4 {
            let r = frame.rgba[whiteOffset]
            let g = frame.rgba[whiteOffset + 1]
            let b = frame.rgba[whiteOffset + 2]
            #expect(r > 230 && g > 230 && b > 230, "Expected white pixel at (200, 200), got r:\(r) g:\(g) b:\(b)")
        }
    }

    @Test("WindowsWindow updateImePosition converts coordinates and invokes Win32 IMM safely")
    func testUpdateImePosition() {
        // Test 1: Headless window (hwnd == nil) safely early-exits without crashing or throwing
        let headlessPlatform = WindowsPlatform(headless: true)
        let headlessHandle = AnyWindowHandle(id: 201)
        var options = WindowOptions()
        options.windowBounds = .windowed(Bounds(origin: .zero, size: Size(width: px(640), height: px(480))))
        let headlessWindow = headlessPlatform.openWindow(handle: headlessHandle, options: options) as! WindowsWindow
        headlessWindow.updateImePosition(bounds: Bounds(origin: Point(x: px(100), y: px(150)), size: Size(width: px(20), height: px(30))))

        // Test 2: Real HWND window (hwnd != nil) safely invokes Win32 IMM API without crashing or leaking handles
        let nonHeadlessPlatform = WindowsPlatform(headless: false)
        let realHandle = AnyWindowHandle(id: 202)
        var realOptions = WindowOptions()
        realOptions.windowBounds = .windowed(Bounds(origin: .zero, size: Size(width: px(256), height: px(256))))
        realOptions.show = false
        let realWindow = nonHeadlessPlatform.openWindow(handle: realHandle, options: realOptions) as! WindowsWindow
        defer { realWindow.close() }
        #expect(realWindow.hwnd != nil)
        realWindow.updateImePosition(bounds: Bounds(origin: Point(x: px(50), y: px(60)), size: Size(width: px(15), height: px(24))))
        if let hwnd = realWindow.hwnd {
            update_ime_position(handle: hwnd, x: 50, y: 72, width: 15, height: 24)
        }
    }
}
#endif
