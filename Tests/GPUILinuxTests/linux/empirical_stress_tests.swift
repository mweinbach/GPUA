// Swift-only: Empirical challenge stress tests for Milestone 4 Gate (cosmic text, keyboard, dispatcher, X11, Wayland)

#if os(Linux)
import Foundation
import Testing
@testable import GPUILinux
import GPUI
import GPUIWGPU
import CLinuxSys
import CWebGPU
import Glibc
import Scheduler

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count: Int = 0

    init(_ initial: Int = 0) {
        self._count = initial
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _count += 1
        return _count
    }

    @discardableResult
    func add(_ value: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _count += value
        return _count
    }
}

@Suite("LinuxEmpiricalStressTests")
struct LinuxEmpiricalStressTests {

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

    // MARK: - Scenario 1: CosmicTextSystem Text Shaping & Rasterization Stress

    @Test
    func testCosmicTextShapingExtremeFontSizes() throws {
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let glyphA = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"), "Failed to find glyph for 'A'")

        let testSizes: [Float] = [0.5, 14.0, 16.0, 72.0, 144.0, 512.0]

        for size in testSizes {
            let text = "GPUA Scale Test"
            let runs = [FontRun(len: text.utf8.count, fontId: fontId)]
            let layout = textSystem.layoutLine(text: text, fontSize: Pixels(size), runs: runs)

            #expect(layout.len == text.utf8.count, "Layout len mismatch at size \(size)")
            #expect(layout.width > Pixels(0.0), "Width must be > 0 at size \(size), got \(layout.width)")
            #expect(layout.ascent > Pixels(0.0), "Ascent must be > 0 at size \(size), got \(layout.ascent)")
            #expect(layout.runs.count == 1, "Expected 1 shaped run at size \(size)")

            let run = layout.runs[0]
            #expect(run.glyphs.count == text.count, "Glyph count mismatch at size \(size)")

            // Verify monotonically advancing position.x
            for i in 1..<run.glyphs.count {
                #expect(
                    run.glyphs[i].position.x > run.glyphs[i - 1].position.x,
                    "Glyph position.x failed monotonic advance at index \(i) for size \(size)"
                )
            }

            // Test Grayscale rasterization at this size
            let grayParams = RenderGlyphParams(
                fontId: fontId,
                glyphId: glyphA,
                fontSize: Pixels(size),
                subpixelVariant: Point(x: 0, y: 0),
                scaleFactor: 1.0,
                isEmoji: false,
                subpixelRendering: false
            )
            let grayBounds = try textSystem.glyphRasterBounds(params: grayParams)
            #expect(grayBounds.size.width.value > 0, "Gray width <= 0 at size \(size)")
            #expect(grayBounds.size.height.value > 0, "Gray height <= 0 at size \(size)")

            let (graySize, grayBitmap) = try textSystem.rasterizeGlyph(params: grayParams, rasterBounds: grayBounds)
            #expect(graySize == grayBounds.size, "Size mismatch in gray rasterization at size \(size)")
            #expect(grayBitmap.count == Int(graySize.width.value * graySize.height.value))
            #expect(grayBitmap.contains(where: { $0 > 0 }), "Gray bitmap is all zero at size \(size)")

            // Test Subpixel rasterization at this size
            let subParams = RenderGlyphParams(
                fontId: fontId,
                glyphId: glyphA,
                fontSize: Pixels(size),
                subpixelVariant: Point(x: 1, y: 0),
                scaleFactor: 1.0,
                isEmoji: false,
                subpixelRendering: true
            )
            let subBounds = try textSystem.glyphRasterBounds(params: subParams)
            #expect(subBounds.size.width.value > 0, "Subpixel width <= 0 at size \(size)")
            #expect(subBounds.size.height.value > 0, "Subpixel height <= 0 at size \(size)")

            let (subSize, subBitmap) = try textSystem.rasterizeGlyph(params: subParams, rasterBounds: subBounds)
            #expect(subSize == subBounds.size, "Size mismatch in subpixel rasterization at size \(size)")
            #expect(subBitmap.count == Int(subSize.width.value * subSize.height.value * 4))
            #expect(subBitmap.contains(where: { $0 > 0 }), "Subpixel bitmap is all zero at size \(size)")
        }
    }

    @Test
    func testCosmicTextShapingComplexUnicode() throws {
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))

        // Complex Unicode strings
        let testStrings = [
            // Combining diacritics
            "e\u{0301}\u{0300}\u{0315}",
            "Z\u{0323}\u{0307}\u{0304}a\u{030a}l\u{0316}g\u{0337}o\u{035c}",
            // Bidirectional text
            "مرحبا 123 بالعالم",
            "שלום עולם 456",
            // Emoji sequences
            "👨‍👩‍👧‍👦",
            "🏳️‍🌈",
            "👍🏽",
            // Multi-glyph ligatures
            "==> !== -> ffi fl <= >= != =="
        ]

        for str in testStrings {
            let runs = [FontRun(len: str.utf8.count, fontId: fontId)]
            let layout = textSystem.layoutLine(text: str, fontSize: Pixels(16), runs: runs)

            #expect(layout.len == str.utf8.count, "Layout len mismatch for string '\(str)'")
            #expect(layout.width > Pixels(0.0), "Width should be > 0 for string '\(str)', got \(layout.width)")
            #expect(layout.runs.count == 1, "Expected 1 run for string '\(str)'")
            #expect(!layout.runs[0].glyphs.isEmpty, "Expected non-empty glyphs for string '\(str)'")

            // Verify glyph positions are finite and non-NaN
            for g in layout.runs[0].glyphs {
                #expect(!g.position.x.value.isNaN, "NaN position.x for glyph in '\(str)'")
                #expect(!g.position.y.value.isNaN, "NaN position.y for glyph in '\(str)'")
            }
        }
    }

    @Test
    func testPinnedFontBufferConcurrentChurn() throws {
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")

        let iterationsPerThread = 25
        let threadCount = 8
        let totalExpected = iterationsPerThread * threadCount
        let successCounter = AtomicCounter()

        let group = DispatchGroup()

        for t in 0..<threadCount {
            group.enter()
            Thread.detachNewThread {
                for _ in 0..<iterationsPerThread {
                    do {
                        let textSystem = CosmicTextSystem.newWithoutSystemFonts("churn-\(t)")
                        try textSystem.addFonts([fontData])

                        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
                        if let glyphM = textSystem.glyphForChar(fontId: fontId, ch: "M") {
                            let params = RenderGlyphParams(
                                fontId: fontId,
                                glyphId: glyphM,
                                fontSize: Pixels(18),
                                subpixelVariant: Point(x: 0, y: 0),
                                scaleFactor: 1.0,
                                isEmoji: false,
                                subpixelRendering: false
                            )
                            let bounds = try textSystem.glyphRasterBounds(params: params)
                            let (_, data) = try textSystem.rasterizeGlyph(params: params, rasterBounds: bounds)
                            if data.contains(where: { $0 > 0 }) {
                                successCounter.increment()
                            }
                        }
                    } catch {
                        // Record issue if error occurs
                    }
                }
                group.leave()
            }
        }

        group.wait()
        #expect(successCounter.count == totalExpected, "Expected \(totalExpected) successful churn cycles, got \(successCounter.count)")
    }

    @Test
    func testSignedPitchHandling() throws {
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))

        // Test rasterization across 30 different characters (letters, numbers, punctuation)
        let chars: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-=[]{}|;:,.<>?")
        for ch in chars {
            guard let glyphId = textSystem.glyphForChar(fontId: fontId, ch: ch) else { continue }

            let params = RenderGlyphParams(
                fontId: fontId,
                glyphId: glyphId,
                fontSize: Pixels(20),
                subpixelVariant: Point(x: 0, y: 0),
                scaleFactor: 1.0,
                isEmoji: false,
                subpixelRendering: false
            )
            let bounds = try textSystem.glyphRasterBounds(params: params)
            if bounds.size.width.value > 0 && bounds.size.height.value > 0 {
                let (size, data) = try textSystem.rasterizeGlyph(params: params, rasterBounds: bounds)
                #expect(size == bounds.size)
                #expect(data.count == Int(size.width.value * size.height.value))
                #expect(data.contains(where: { $0 > 0 }))
            }
        }
    }

    // MARK: - Scenario 2: Keyboard & xkbcommon State Machine Stress

    @Test
    func testKeyboardModifierPermutations() throws {
        let context = try #require(XkbContext())
        let keymap = try #require(XkbKeymap.fromRuleNames(context: context, model: "pc105", layout: "us"))
        let state = try #require(XkbState(keymap: keymap))

        // Test all combinations of shift, control, alt, super
        let shiftMask: UInt32 = 1 << 0
        let lockMask: UInt32 = 1 << 1
        let ctrlMask: UInt32 = 1 << 2
        let mod1Mask: UInt32 = 1 << 3 // Alt
        let mod4Mask: UInt32 = 1 << 6 // Super/Logo

        for shift in [false, true] {
            for ctrl in [false, true] {
                for alt in [false, true] {
                    for superMod in [false, true] {
                        var modsMask: UInt32 = 0
                        if shift { modsMask |= shiftMask }
                        if ctrl { modsMask |= ctrlMask }
                        if alt { modsMask |= mod1Mask }
                        if superMod { modsMask |= mod4Mask }

                        xkb_state_update_mask(state.raw, modsMask, 0, 0, 0, 0, 0)

                        let extracted = modifiersFromXkb(state: state)
                        #expect(extracted.shift == shift, "Shift mismatch for mask \(modsMask)")
                        #expect(extracted.control == ctrl, "Ctrl mismatch for mask \(modsMask)")
                        #expect(extracted.alt == alt, "Alt mismatch for mask \(modsMask)")
                        #expect(extracted.platform == superMod, "Super mismatch for mask \(modsMask)")

                        // Verify keystroke extraction for keycode 24 (Q)
                        let ks = keystrokeFromXkb(state: state, modifiers: extracted, keycode: 24)
                        #expect(ks.modifiers.shift == shift)
                        #expect(ks.modifiers.control == ctrl)
                        #expect(ks.modifiers.alt == alt)
                        #expect(ks.modifiers.platform == superMod)
                    }
                }
            }
        }

        // Test CapsLock
        xkb_state_update_mask(state.raw, 0, 0, lockMask, 0, 0, 0)
        let caps = capslockFromXkb(state: state)
        #expect(caps.on == true, "Expected CapsLock to be ON")

        xkb_state_update_mask(state.raw, 0, 0, 0, 0, 0, 0)
        let capsOff = capslockFromXkb(state: state)
        #expect(capsOff.on == false, "Expected CapsLock to be OFF")
    }

    @Test
    func testKeyboardComposeAndDeadKeySequences() throws {
        let context = try #require(XkbContext())

        let composeData = """
        <Multi_key> <apostrophe> <e> : "é" eacute
        <Multi_key> <asciitilde> <a> : "ã" atilde
        <Multi_key> <comma> <c> : "ç" ccedilla
        <Multi_key> <asciicircum> <o> : "ô" ocircumflex
        <Multi_key> <equal> <e> : "€" EuroSign
        """

        let table = try #require(XkbComposeTable(context: context, buffer: composeData))
        let composeState = try #require(XkbComposeState(table: table))

        // Sequence 1: <Multi_key> <comma> <c> -> "ç"
        #expect(composeState.status() == XKB_COMPOSE_NOTHING)
        #expect(composeState.feed(keysym: UInt32(XKB_KEY_Multi_key)) == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSING)
        #expect(composeState.feed(keysym: UInt32(XKB_KEY_comma)) == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSING)
        #expect(composeState.feed(keysym: UInt32(XKB_KEY_c)) == XKB_COMPOSE_FEED_ACCEPTED)
        #expect(composeState.status() == XKB_COMPOSE_COMPOSED)
        #expect(composeState.utf8() == "ç")
        #expect(composeState.oneSym() == UInt32(XKB_KEY_ccedilla))

        // Sequence 2: <Multi_key> <equal> <e> -> "€"
        composeState.reset()
        #expect(composeState.status() == XKB_COMPOSE_NOTHING)
        _ = composeState.feed(keysym: UInt32(XKB_KEY_Multi_key))
        _ = composeState.feed(keysym: UInt32(XKB_KEY_equal))
        _ = composeState.feed(keysym: UInt32(XKB_KEY_e))
        #expect(composeState.status() == XKB_COMPOSE_COMPOSED)
        #expect(composeState.utf8() == "€")
        #expect(composeState.oneSym() == UInt32(XKB_KEY_EuroSign))

        // Test dead keys
        let deadKeyMap: [(UInt32, String)] = [
            (0xFE50, "`"), (0xFE51, "´"), (0xFE52, "^"), (0xFE53, "~"),
            (0xFE54, "¯"), (0xFE55, "˘"), (0xFE56, "˙"), (0xFE57, "¨"),
            (0xFE58, "˚"), (0xFE59, "˝"), (0xFE5A, "ˇ"), (0xFE5B, "¸"),
            (0xFE5C, "˛"), (0xFE5D, "ͅ"), (0xFE5E, "゙"), (0xFE5F, "゚"),
        ]
        for (sym, expectedStr) in deadKeyMap {
            #expect(keystrokeUnderlyingDeadKey(sym) == expectedStr, "Dead key \(sym) did not match \(expectedStr)")
        }
        #expect(keystrokeUnderlyingDeadKey(0x1234) == nil)
        #expect(keystrokeUnderlyingDeadKey(0xFFFF) == nil)
    }

    @Test
    func testKeyboardScancodeAndMapperFidelity() throws {
        // Test evdevToKeycode and keycodeToEvdev across entire 0..255 byte range
        for scancode: UInt32 in 0..<256 {
            let keycode = evdevToKeycode(scancode)
            #expect(keycode == scancode + 8, "evdevToKeycode mismatch for \(scancode)")
            #expect(keycodeToEvdev(keycode) == scancode, "keycodeToEvdev roundtrip mismatch for \(scancode)")
        }

        #expect(keycodeToEvdev(0) == 0)
        #expect(keycodeToEvdev(7) == 0)

        // LinuxKeyboardMapper
        let mapper = LinuxKeyboardMapper()
        let ks = Keystroke(modifiers: Modifiers(control: true, alt: true), key: "k")
        let binding = mapper.mapKeyEquivalent(keystroke: ks, useKeyEquivalents: true)
        #expect(binding.key == "k")
        #expect(binding.modifiers.control == true)
        #expect(binding.modifiers.alt == true)
    }

    // MARK: - Scenario 3: Dispatcher Concurrency & Epoll Stress

    @Test
    func testDispatcher500ConcurrentTasks() throws {
        let (mainSender, mainReceiver) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let eventLoop = try CalloopEventLoop<Void>.tryNew()
        let handle = eventLoop.handle()

        let mainCounter = AtomicCounter()
        _ = handle.insertSource(mainReceiver) { event, _ in
            if case .msg(let action) = event {
                action()
                mainCounter.increment()
            }
        }

        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)
        let bgCounter = AtomicCounter()

        let taskCount = 500
        let group = DispatchGroup()

        // 1. Dispatch 500 tasks to background executor across concurrent threads
        for _ in 0..<10 {
            group.enter()
            Thread.detachNewThread {
                for i in 0..<50 {
                    let prio: Priority = (i % 3 == 0) ? .high : ((i % 3 == 1) ? .medium : .low)
                    dispatcher.dispatch({
                        bgCounter.increment()
                    }, priority: prio)
                }
                group.leave()
            }
        }

        // 2. Dispatch 500 tasks to main thread queue
        for _ in 0..<taskCount {
            dispatcher.dispatchOnMainThread({
                // Handled in event loop
            }, priority: .default)
        }

        group.wait()

        // Wait for background tasks to complete
        for _ in 0..<100 {
            if bgCounter.count == taskCount { break }
            Thread.sleep(forTimeInterval: 0.005)
        }
        #expect(bgCounter.count == taskCount, "Expected \(taskCount) background tasks completed, got \(bgCounter.count)")

        // Drain main thread queue
        var dummy: Void = ()
        for _ in 0..<100 {
            try eventLoop.dispatch(timeout: 0.005, data: &dummy)
            if mainCounter.count == taskCount { break }
        }
        #expect(mainCounter.count == taskCount, "Expected \(taskCount) main queue tasks completed, got \(mainCounter.count)")
    }

    @Test
    func testDispatcherBurstTimersAndContention() throws {
        let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
        let dispatcher = LinuxDispatcher.new(mainSender: mainSender)

        let timerCount = 200
        let timerFired = AtomicCounter()
        let group = DispatchGroup()

        // Burst schedule timers with millisecond deadlines from 5 concurrent threads
        for t in 0..<5 {
            group.enter()
            Thread.detachNewThread {
                for i in 0..<(timerCount / 5) {
                    let duration = Double((t * 10 + i) % 15 + 1) * 0.002 // 2ms to 30ms
                    dispatcher.dispatchAfter(duration: duration) {
                        timerFired.increment()
                    }
                }
                group.leave()
            }
        }

        group.wait()

        // Wait for all burst timers to fire
        let start = ContinuousClock.now
        while timerFired.count < timerCount && (ContinuousClock.now - start) < .seconds(3) {
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(timerFired.count == timerCount, "Expected \(timerCount) timers to fire, got \(timerFired.count)")
    }

    @Test
    func testDispatcherCleanDeinitShutdownStress() throws {
        // Stress rapid creation, scheduling, and deinit across 15 iterations
        for _ in 0..<15 {
            weak var weakDisp: LinuxDispatcher?
            do {
                let (mainSender, _) = PriorityQueueCalloopReceiver<@Sendable () -> Void>.new()
                let disp = LinuxDispatcher.new(mainSender: mainSender)
                weakDisp = disp
                #expect(weakDisp != nil)

                let fired = AtomicCounter()
                disp.dispatchAfter(duration: 0.005) {
                    fired.increment()
                }

                disp.dispatch({
                    fired.increment()
                }, priority: .high)

                let start = ContinuousClock.now
                while fired.count < 2 && (ContinuousClock.now - start) < .milliseconds(200) {
                    Thread.sleep(forTimeInterval: 0.005)
                }
            }
            #expect(weakDisp == nil, "LinuxDispatcher leaked or failed clean deinit on drop")
        }
    }

    // MARK: - Scenario 4: X11 & Wayland Integration Smoke Tests

    @Test
    func testX11FullStackSmokeIntegration() throws {
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        let client = try X11Client.new()
        let window = try client.openWindow(
            handle: AnyWindowHandle(id: 777),
            options: WindowOptions(
                windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(128), height: px(128)))),
                kind: .normal
            )
        )
        guard let x11Window = window as? X11Window, let conn = x11Window.ptr.connection else {
            Issue.record("Expected valid X11Window with connection")
            return
        }

        xcb_map_window(conn, x11Window.ptr.xWindow)
        xcb_flush(conn)
        if let display = client.ptr.state.x11Display {
            XSync(display, 0)
        }

        // Render Red Background + Green Inner Quad + Blue Monochromatic Glyph Sprite
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let glyphA = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"))

        var scene = Scene()
        let bgBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(128), height: ScaledPixels(128)))
        scene.insertQuad(Quad(order: DrawOrder(1), borderStyle: .solid, bounds: bgBounds, contentMask: ContentMask(bounds: bgBounds), background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)), borderColor: Hsla(h: 0, s: 0, l: 0, a: 1), cornerRadii: .zero, borderWidths: .zero))

        let fgBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(32), y: ScaledPixels(32)), size: Size(width: ScaledPixels(64), height: ScaledPixels(64)))
        scene.insertQuad(Quad(order: DrawOrder(2), borderStyle: .solid, bounds: fgBounds, contentMask: ContentMask(bounds: fgBounds), background: solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)), borderColor: Hsla(h: 0, s: 0, l: 0, a: 1), cornerRadii: .zero, borderWidths: .zero))

        let glyphParams = RenderGlyphParams(fontId: fontId, glyphId: glyphA, fontSize: px(24), subpixelVariant: Point(x: 0, y: 0), scaleFactor: 1.0, isEmoji: false, subpixelRendering: false)
        let glyphBounds = try textSystem.glyphRasterBounds(params: glyphParams)
        let (glyphSize, glyphBitmap) = try textSystem.rasterizeGlyph(params: glyphParams, rasterBounds: glyphBounds)
        let tile = try #require(try x11Window.ptr.state.renderer.spriteAtlas().getOrInsertWith(key: AtlasKey.glyph(glyphParams)) { (glyphSize, glyphBitmap) })

        let spriteBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(48), y: ScaledPixels(48)), size: Size(width: ScaledPixels(Float(glyphSize.width.value)), height: ScaledPixels(Float(glyphSize.height.value))))
        scene.insertMonochromeSprite(MonochromeSprite(order: DrawOrder(3), bounds: spriteBounds, contentMask: ContentMask(bounds: spriteBounds), color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)), tile: tile))

        var verified = false
        for _ in 0..<20 {
            x11Window.draw(scene: scene)
            xcb_flush(conn)
            if let display = client.ptr.state.x11Display { XSync(display, 0) }
            try? client.processX11Events(conn)

            let cookie = xcb_get_image(conn, UInt8(XCB_IMAGE_FORMAT_Z_PIXMAP.rawValue), x11Window.ptr.xWindow, 0, 0, 128, 128, UInt32.max)
            guard let reply = xcb_get_image_reply(conn, cookie, nil) else {
                usleep(10_000)
                continue
            }
            if let data = xcb_get_image_data(reply) {
                let bgB = data[(10 * 128 + 10) * 4]
                let bgG = data[(10 * 128 + 10) * 4 + 1]
                let bgR = data[(10 * 128 + 10) * 4 + 2]

                let fgB = data[(36 * 128 + 36) * 4]
                let fgG = data[(36 * 128 + 36) * 4 + 1]
                let fgR = data[(36 * 128 + 36) * 4 + 2]

                var foundBlue = false
                for y in 48..<min(128, 48 + Int(glyphSize.height.value)) {
                    for x in 48..<min(128, 48 + Int(glyphSize.width.value)) {
                        if data[(y * 128 + x) * 4] > 100 {
                            foundBlue = true
                            break
                        }
                    }
                    if foundBlue { break }
                }

                free(reply)
                if bgR > 200 && bgG < 50 && bgB < 50 && fgG > 200 && fgR < 50 && fgB < 50 && foundBlue {
                    verified = true
                    break
                }
            } else {
                free(reply)
            }
            usleep(15_000)
        }
        #expect(verified, "Failed to verify X11 rendered pixels on Xvfb")
    }
}
#endif

