// Tests ported from: crates/gpui_linux/src/linux/platform.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import Testing
@testable import GPUILinux
import GPUI
import GPUIWGPU
import CLinuxSys
import CWebGPU

@Suite("LinuxPlatformTests")
struct LinuxPlatformTests {
    @Test
    func testIsWithinClickDistance() {
        let zero = Point<Pixels>(x: px(0.0), y: px(0.0))
        #expect(isWithinClickDistance(zero, Point(x: px(5.0), y: px(5.0))))
        #expect(isWithinClickDistance(zero, Point(x: px(-4.9), y: px(5.0))))
        #expect(isWithinClickDistance(Point(x: px(3.0), y: px(2.0)), Point(x: px(-2.0), y: px(-2.0))))
        #expect(!isWithinClickDistance(zero, Point(x: px(5.0), y: px(5.1))))
    }

    @Test
    func testGuessCompositor() {
        let comp = guessCompositor()
        #expect(["Wayland", "X11", "Headless"].contains(comp))
    }

    private static func loadFontFixture() -> Data? {
        let candidates = [
            "Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            "/workspace/Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
        ]
        for path in candidates {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    @Test
    func testX11WindowWebGPURenderingSmoke() throws {
        // Only run when DISPLAY is available (e.g. under xvfb-run or real X11)
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        let client = try X11Client.new()
        let displays = client.displays()
        #expect(!displays.isEmpty)

        let window = try client.openWindow(
            handle: AnyWindowHandle(id: 42),
            options: WindowOptions(
                windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(128), height: px(128)))),
                kind: .normal
            )
        )
        guard let x11Window = window as? X11Window else {
            Issue.record("Expected window to be X11Window")
            return
        }

        // Map window and synchronize with X server before drawing
        guard let conn = x11Window.ptr.connection else {
            Issue.record("Missing XCB connection")
            return
        }
        xcb_map_window(conn, x11Window.ptr.xWindow)
        xcb_flush(conn)
        if let display = client.ptr.state.x11Display {
            XSync(display, 0)
        }

        // Initialize CosmicTextSystem to shape real text from font fixture
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let glyphA = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"), "Failed to find glyph for 'A'")

        var scene = Scene()

        // 1. Red background quad covering entire 128x128 window
        let bgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: Size(width: ScaledPixels(128), height: ScaledPixels(128))
        )
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: bgBounds,
            contentMask: ContentMask(bounds: bgBounds),
            background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        // 2. Contrasting green quad in center (32..96, 32..96)
        let fgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(32), y: ScaledPixels(32)),
            size: Size(width: ScaledPixels(64), height: ScaledPixels(64))
        )
        let fgQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: fgBounds,
            contentMask: ContentMask(bounds: fgBounds),
            background: solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(fgQuad)

        // 3. Rasterize real glyph 'A' through CosmicTextSystem and render into atlas
        let renderer = x11Window.ptr.state.renderer
        let atlas = renderer.spriteAtlas()
        let glyphParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphA,
            fontSize: px(24),
            subpixelVariant: Point(x: 0, y: 0),
            scaleFactor: 1.0,
            isEmoji: false,
            subpixelRendering: false
        )
        let glyphBounds = try textSystem.glyphRasterBounds(params: glyphParams)
        let (glyphSize, glyphBitmap) = try textSystem.rasterizeGlyph(params: glyphParams, rasterBounds: glyphBounds)
        #expect(glyphSize.width.value > 0 && glyphSize.height.value > 0)
        #expect(glyphBitmap.contains(where: { $0 > 0 }))

        let tile = try #require(try atlas.getOrInsertWith(key: AtlasKey.glyph(glyphParams), build: {
            (glyphSize, glyphBitmap)
        }))

        let spriteBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(48), y: ScaledPixels(48)),
            size: Size(width: ScaledPixels(Float(glyphSize.width.value)), height: ScaledPixels(Float(glyphSize.height.value)))
        )
        let sprite = MonochromeSprite(
            order: DrawOrder(3),
            bounds: spriteBounds,
            contentMask: ContentMask(bounds: spriteBounds),
            color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)),
            tile: tile
        )
        scene.insertMonochromeSprite(sprite)

        // Draw and present the scene with a retry poll loop for Xvfb presentation under concurrent test load
        var bgR: UInt8 = 0
        var bgG: UInt8 = 0
        var bgB: UInt8 = 0
        var fgR: UInt8 = 0
        var fgG: UInt8 = 0
        var fgB: UInt8 = 0
        var foundBlueGlyphPixel = false

        for _ in 0..<20 {
            x11Window.draw(scene: scene)

            xcb_flush(conn)
            if let display = client.ptr.state.x11Display {
                XSync(display, 0)
            }
            try? client.processX11Events(conn)

            // Verify window rendered pixels via xcb_get_image
            let cookie = xcb_get_image(
                conn,
                UInt8(XCB_IMAGE_FORMAT_Z_PIXMAP.rawValue),
                x11Window.ptr.xWindow,
                0,
                0,
                128,
                128,
                UInt32.max
            )
            guard let reply = xcb_get_image_reply(conn, cookie, nil) else {
                usleep(10_000)
                continue
            }

            let len = Int(xcb_get_image_data_length(reply))
            guard len >= 128 * 128 * 4, let data = xcb_get_image_data(reply) else {
                free(reply)
                usleep(10_000)
                continue
            }

            // Assert specific rendered pixel colors in 32-bit BGRX/BGRA (little-endian X11):
            // Pixel at (x, y): offset = (y * 128 + x) * 4
            // data[offset + 0] = B, data[offset + 1] = G, data[offset + 2] = R

            // 1. Red background at (10, 10): R > 200, G < 50, B < 50
            let bgOffset = (10 * 128 + 10) * 4
            bgB = data[bgOffset]
            bgG = data[bgOffset + 1]
            bgR = data[bgOffset + 2]

            // 2. Green inner quad at (36, 36): G > 200, R < 50, B < 50
            let fgOffset = (36 * 128 + 36) * 4
            fgB = data[fgOffset]
            fgG = data[fgOffset + 1]
            fgR = data[fgOffset + 2]

            // 3. Blue-blended glyph pixel inside the sprite bounds: at least one pixel with B > 100
            foundBlueGlyphPixel = false
            for y in 48..<min(128, 48 + Int(glyphSize.height.value)) {
                for x in 48..<min(128, 48 + Int(glyphSize.width.value)) {
                    let offset = (y * 128 + x) * 4
                    let b = data[offset]
                    if b > 100 {
                        foundBlueGlyphPixel = true
                        break
                    }
                }
                if foundBlueGlyphPixel { break }
            }

            free(reply)

            if bgR > 200 && fgG > 200 && foundBlueGlyphPixel {
                break
            }
            usleep(15_000)
        }

        #expect(bgR > 200 && bgG < 50 && bgB < 50, "Expected red background at (10, 10), got R:\(bgR) G:\(bgG) B:\(bgB)")
        #expect(fgG > 200 && fgR < 50 && fgB < 50, "Expected green quad at (36, 36), got R:\(fgR) G:\(fgG) B:\(fgB)")
        #expect(foundBlueGlyphPixel, "Expected at least one blue glyph pixel with B > 100 inside sprite region")
    }

    @Test
    func testX11InputTranslationAndStateTracking() throws {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        let client = try X11Client.new()
        let window = try client.openWindow(
            handle: AnyWindowHandle(id: 101),
            options: WindowOptions(
                windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(300), height: px(200)))),
                kind: .normal
            )
        )
        guard let x11Window = window as? X11Window else {
            Issue.record("Expected X11Window")
            return
        }
        guard let conn = x11Window.ptr.connection else {
            Issue.record("Missing connection")
            return
        }
        xcb_map_window(conn, x11Window.ptr.xWindow)
        xcb_flush(conn)

        // Verify window state tracking defaults
        #expect(!x11Window.isHovered())
        #expect(!x11Window.isFullscreen())
        #expect(!x11Window.isMaximized())

        // Test window actions
        x11Window.activate()
        #expect(x11Window.isActive())

        x11Window.zoom()
        #expect(x11Window.isMaximized())

        x11Window.toggleFullScreen()
        #expect(x11Window.isFullscreen())

        x11Window.minimize()
        #expect(x11Window.ptr.state.hidden)

        // Capture received input events
        var receivedInputs: [PlatformInput] = []
        x11Window.onInput { input in
            receivedInputs.append(input)
            return DispatchEventResult()
        }

        // 1. Send KeyPress (e.g. keycode 38)
        var keyPressEv = xcb_key_press_event_t(
            response_type: UInt8(XCB_KEY_PRESS),
            detail: 38,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 50,
            root_y: 50,
            event_x: 50,
            event_y: 50,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &keyPressEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_KEY_PRESS.rawValue), baseAddress)
            }
        }

        // 2. Send KeyRelease (keycode 38)
        var keyReleaseEv = xcb_key_release_event_t(
            response_type: UInt8(XCB_KEY_RELEASE),
            detail: 38,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 50,
            root_y: 50,
            event_x: 50,
            event_y: 50,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &keyReleaseEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_KEY_RELEASE.rawValue), baseAddress)
            }
        }

        // 3. Send MotionNotify at (120, 80)
        var motionEv = xcb_motion_notify_event_t(
            response_type: UInt8(XCB_MOTION_NOTIFY),
            detail: 0,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 120,
            root_y: 80,
            event_x: 120,
            event_y: 80,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &motionEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_POINTER_MOTION.rawValue), baseAddress)
            }
        }

        // 4. Send ButtonPress button 1 (left mouse down)
        var btnPressEv = xcb_button_press_event_t(
            response_type: UInt8(XCB_BUTTON_PRESS),
            detail: 1,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 120,
            root_y: 80,
            event_x: 120,
            event_y: 80,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &btnPressEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_BUTTON_PRESS.rawValue), baseAddress)
            }
        }

        // 5. Send ButtonRelease button 1 (left mouse up)
        var btnReleaseEv = xcb_button_release_event_t(
            response_type: UInt8(XCB_BUTTON_RELEASE),
            detail: 1,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 120,
            root_y: 80,
            event_x: 120,
            event_y: 80,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &btnReleaseEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_BUTTON_RELEASE.rawValue), baseAddress)
            }
        }

        // 6. Send ButtonPress button 4 (scroll wheel up)
        var scrollEv = xcb_button_press_event_t(
            response_type: UInt8(XCB_BUTTON_PRESS),
            detail: 4,
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 120,
            root_y: 80,
            event_x: 120,
            event_y: 80,
            state: 0,
            same_screen: 1,
            pad0: 0
        )
        withUnsafeBytes(of: &scrollEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_BUTTON_PRESS.rawValue), baseAddress)
            }
        }

        // 7. Send EnterNotify
        var enterEv = xcb_enter_notify_event_t(
            response_type: UInt8(XCB_ENTER_NOTIFY),
            detail: UInt8(XCB_NOTIFY_DETAIL_ANCESTOR.rawValue),
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 100,
            root_y: 100,
            event_x: 100,
            event_y: 100,
            state: 0,
            mode: UInt8(XCB_NOTIFY_MODE_NORMAL.rawValue),
            same_screen_focus: 1
        )
        withUnsafeBytes(of: &enterEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_ENTER_WINDOW.rawValue), baseAddress)
            }
        }

        // 8. Send LeaveNotify
        var leaveEv = xcb_leave_notify_event_t(
            response_type: UInt8(XCB_LEAVE_NOTIFY),
            detail: UInt8(XCB_NOTIFY_DETAIL_ANCESTOR.rawValue),
            sequence: 0,
            time: UInt32(XCB_CURRENT_TIME),
            root: x11Window.ptr.state.xRootWindow,
            event: x11Window.ptr.xWindow,
            child: 0,
            root_x: 0,
            root_y: 0,
            event_x: 0,
            event_y: 0,
            state: 0,
            mode: UInt8(XCB_NOTIFY_MODE_NORMAL.rawValue),
            same_screen_focus: 1
        )
        withUnsafeBytes(of: &leaveEv) { rawBuf in
            if let baseAddress = rawBuf.baseAddress?.assumingMemoryBound(to: CChar.self) {
                xcb_send_event(conn, 0, x11Window.ptr.xWindow, UInt32(XCB_EVENT_MASK_LEAVE_WINDOW.rawValue), baseAddress)
            }
        }

        xcb_flush(conn)

        // Process events with retry poll
        for _ in 0..<20 {
            try? client.processX11Events(conn)
            if receivedInputs.count >= 7 {
                break
            }
            usleep(10_000)
        }

        #expect(receivedInputs.count >= 7, "Expected at least 7 translated input events, got \(receivedInputs.count)")

        // Verify key down
        let hasKeyDown = receivedInputs.contains { input in
            if case .keyDown = input { return true }
            return false
        }
        #expect(hasKeyDown, "Missing keyDown event")

        // Verify key up
        let hasKeyUp = receivedInputs.contains { input in
            if case .keyUp = input { return true }
            return false
        }
        #expect(hasKeyUp, "Missing keyUp event")

        // Verify mouse move
        let hasMouseMove = receivedInputs.contains { input in
            if case .mouseMove = input { return true }
            return false
        }
        #expect(hasMouseMove, "Missing mouseMove event")

        // Verify mouse down (left button)
        let hasMouseDown = receivedInputs.contains { input in
            if case .mouseDown(let ev) = input, ev.button == .left { return true }
            return false
        }
        #expect(hasMouseDown, "Missing mouseDown(left) event")

        // Verify mouse up (left button)
        let hasMouseUp = receivedInputs.contains { input in
            if case .mouseUp(let ev) = input, ev.button == .left { return true }
            return false
        }
        #expect(hasMouseUp, "Missing mouseUp(left) event")

        // Verify scroll wheel
        let hasScrollWheel = receivedInputs.contains { input in
            if case .scrollWheel = input { return true }
            return false
        }
        #expect(hasScrollWheel, "Missing scrollWheel event")

        // Verify mouse exited
        let hasMouseExited = receivedInputs.contains { input in
            if case .mouseExited = input { return true }
            return false
        }
        #expect(hasMouseExited, "Missing mouseExited event")

        // Verify mouse position was tracked
        #expect(x11Window.mousePosition() == Point(x: px(0), y: px(0)))
        #expect(!x11Window.isHovered())
    }

    @Test
    func testTwoConnectionX11ClipboardTransfer() throws {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        // Instance A on its own connection & event loop
        let clipA = try X11Clipboard.new()
        let messageFromA = "Authentic X11 Clipboard Data From A 🚀"
        try clipA.setText(messageFromA, selection: .clipboard)
        #expect(clipA.isOwner(selection: .clipboard))

        // Instance B on a separate independent XCB connection
        let clipB = try X11Clipboard.new()
        #expect(!clipB.isOwner(selection: .clipboard))

        // Instance B reads from Instance A over X11 selection protocol
        let itemReceivedByB = try clipB.getAny(selection: .clipboard)
        #expect(itemReceivedByB.text == messageFromA)

        // Now Instance B takes ownership with new text
        let messageFromB = "Replaced by Connection B ✨"
        try clipB.setText(messageFromB, selection: .clipboard)
        #expect(clipB.isOwner(selection: .clipboard))

        // Give X server a brief moment to deliver XCB_SELECTION_CLEAR to Instance A
        for _ in 0..<20 {
            if !clipA.isOwner(selection: .clipboard) {
                break
            }
            usleep(10_000)
        }
        #expect(!clipA.isOwner(selection: .clipboard))

        // Instance A reads from Instance B over X11 selection protocol
        let itemReceivedByA = try clipA.getAny(selection: .clipboard)
        #expect(itemReceivedByA.text == messageFromB)

        // Also test PRIMARY selection transfer between connections
        let primaryFromA = "Primary selection test data"
        try clipA.setText(primaryFromA, selection: .primary)
        #expect(clipA.isOwner(selection: .primary))

        let primaryReceivedByB = try clipB.getAny(selection: .primary)
        #expect(primaryReceivedByB.text == primaryFromA)
    }

    @Test
    func testLinuxKeyboardMapper() throws {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }
        let client = try X11Client.new()
        let platform = LinuxPlatform(inner: client)
        let mapper = platform.keyboardMapper()
        let keystroke = Keystroke(modifiers: Modifiers(control: true), key: "c")
        let keybinding = mapper.mapKeyEquivalent(keystroke: keystroke, useKeyEquivalents: false)
        #expect(keybinding.key == "c")
        #expect(keybinding.modifiers.control == true)
    }

    @Test("GPUI.PlatformInputHandler receives X11 keyDown printable characters and IME preedit/commit/delete/unmark")
    @MainActor
    func testX11PlatformInputHandlerEndToEnd() throws {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }
        let client = try X11Client.new()
        let platform = LinuxPlatform(inner: client)
        let app = App.newApp(platform: platform)
        let handle = try app.openWindow(WindowOptions()) { _, cx in
            cx.new { _ in LinuxInputDummyView() }
        }
        let x11Window = try #require(
            try app.updateWindow(handle.anyHandle) { _, win, _ in win.platformWindow as? X11Window }
        )

        let recorder = RecordingLinuxInputHandler()
        let platformHandler = PlatformInputHandler(
            windowHandle: handle.anyHandle,
            app: app,
            handler: recorder
        )
        x11Window.setInputHandler(platformHandler)
        x11Window.onInput { _ in
            DispatchEventResult(propagate: true, defaultPrevented: false)
        }

        // 1. Printable keyDown (plain + Shift) routes into PlatformInputHandler
        _ = x11Window.ptr.handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(key: "h", keyChar: "h"))))
        _ = x11Window.ptr.handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(modifiers: .shift(), key: "i", keyChar: "I"))))
        // Control-modified keystroke must NOT insert text
        _ = x11Window.ptr.handleInput(.keyDown(KeyDownEvent(keystroke: Keystroke(modifiers: .control(), key: "c", keyChar: "c"))))
        #expect(recorder.text == "hI")

        // 2. XIM preedit -> getImeArea -> delete marked -> preedit + commit -> unmark
        x11Window.ptr.handleImePreedit("にほ")
        #expect(recorder.text == "hIにほ")
        #expect(recorder.marked == 2..<4)
        let imeArea = x11Window.ptr.getImeArea()
        #expect(imeArea == Bounds(origin: point(px(14), px(28)), size: size(px(2), px(20))))

        x11Window.ptr.handleImeDelete()
        #expect(recorder.text == "hI")
        #expect(recorder.marked == nil)

        x11Window.ptr.handleImePreedit("かん")
        x11Window.ptr.handleImeCommit("漢")
        #expect(recorder.text == "hI漢")
        #expect(recorder.marked == nil)

        x11Window.ptr.handleImePreedit("かな")
        x11Window.ptr.handleImeUnmark()
        #expect(recorder.text == "hI漢かな")
        #expect(recorder.marked == nil)
        #expect(recorder.unmarkCount == 1)
    }
}

@MainActor
final class RecordingLinuxInputHandler: InputHandler {
    var text: String = ""
    var selection: Range<Int> = 0..<0
    var marked: Range<Int>? = nil
    var unmarkCount: Int = 0

    func selectedTextRange(ignoreDisabledInput: Bool, window: inout GPUI.Window, cx: inout App) -> UTF16Selection? {
        UTF16Selection(range: selection, reversed: false)
    }

    func markedTextRange(window: inout GPUI.Window, cx: inout App) -> Range<Int>? {
        marked
    }

    func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?, window: inout GPUI.Window, cx: inout App) -> String? {
        text
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text replacement: String, window: inout GPUI.Window, cx: inout App) {
        let target = rangeUtf16 ?? marked ?? selection
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
            text.replaceSubrange(strRange, with: replacement)
            let cursor = target.lowerBound + replacement.utf16.count
            selection = cursor..<cursor
        }
        marked = nil
    }

    func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?,
        window: inout GPUI.Window,
        cx: inout App
    ) {
        let target = rangeUtf16 ?? marked ?? selection
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
            text.replaceSubrange(strRange, with: newText)
            let start = target.lowerBound
            let end = start + newText.utf16.count
            marked = newText.isEmpty ? nil : (start..<end)
            selection = end..<end
        }
    }

    func unmarkText(window: inout GPUI.Window, cx: inout App) {
        marked = nil
        unmarkCount += 1
    }

    func setSelectedTextRange(selection: UTF16Selection?, window: inout GPUI.Window, cx: inout App) {
        if let selection {
            self.selection = selection.range
        }
    }

    func boundsForRange(rangeUtf16: Range<Int>, window: inout GPUI.Window, cx: inout App) -> Bounds<Pixels>? {
        Bounds(origin: point(px(14), px(28)), size: size(px(2), px(20)))
    }

    func characterIndexForPoint(point: Point<Pixels>, window: inout GPUI.Window, cx: inout App) -> Int? {
        0
    }
}

struct LinuxInputDummyView: Render {
    func render(_ window: inout GPUI.Window, _ cx: inout Context<LinuxInputDummyView>) -> some IntoElement {
        div()
    }
}
#endif
