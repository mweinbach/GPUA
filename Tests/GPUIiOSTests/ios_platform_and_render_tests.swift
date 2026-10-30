// Swift-only: iOS Simulator UIKit, CoreText, and Metal behavioral tests

#if os(iOS) || os(visionOS)
import CoreGraphics
import CoreText
import Foundation
import GPUI
import GPUIMetal
import QuartzCore
import Testing
import UIKit
@testable import GPUIiOS

@Suite("GPUIiOS Platform, CoreText, UIKit & Metal Behavioral Tests", .serialized)
struct IosPlatformAndRenderTests {
    private func pixel(
        in rendered: (width: Int, height: Int, rgba: [UInt8]),
        x: Int,
        y: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = (y * rendered.width + x) * 4
        return (
            rendered.rgba[offset],
            rendered.rgba[offset + 1],
            rendered.rgba[offset + 2],
            rendered.rgba[offset + 3]
        )
    }

    @Test("IosPlatform lifecycle, compositor, pasteboard round-trip, C ABI demo catalog, and URL callback")
    @MainActor
    func platformPasteboardAndBridgeBehavior() throws {
        let platform = IosPlatform.new()
        #expect(platform.compositorName() == "Metal")
        #expect(platform.shouldAutoHideScrollbars() == true)

        let appearance = platform.windowAppearance()
        #expect(
            appearance == .light || appearance == .dark
                || appearance == .vibrantLight || appearance == .vibrantDark
        )

        let thermal = platform.thermalState()
        #expect(
            thermal == .nominal || thermal == .fair
                || thermal == .serious || thermal == .critical
        )

        // UIPasteboard round-trip with structured metadata
        let metaBytes = Data("{\"source\":\"GPUIiOSTests\"}".utf8)
        let testItem = ClipboardItem(
            text: "GPUA iOS Pasteboard Verification 🚀",
            data: metaBytes
        )
        platform.writeToClipboard(testItem)
        if let readBack = platform.readFromClipboard() {
            #expect(readBack.text == "GPUA iOS Pasteboard Verification 🚀")
            #expect(readBack.data == metaBytes)
        }

        // C ABI demo catalog round-trip (newline-separated matching upstream `gpui_ios_list_demos`)
        let rawListPtr = gpuiIosListDemos()
        let nonNullPtr = try #require(rawListPtr)
        let rawCatalog = String(cString: nonNullPtr)
        gpuiIosFreeString(nonNullPtr)
        let demos = rawCatalog.split(separator: "\n").map(String.init)
        #expect(demos.count == 17)
        #expect(demos.contains("hello_world"))
        #expect(demos.contains("text"))
        #expect(demos.contains("scrollable"))
        #expect(demos.contains("input"))

        // URL forwarding via C ABI bridge
        var receivedUrls: [String] = []
        platform.onOpenUrls { urls in
            receivedUrls.append(contentsOf: urls)
        }
        "gpui://open-demo/hello_world".withCString { cStr in
            gpuiIosHandleOpenUrl(cStr)
        }
        #expect(receivedUrls == ["gpui://open-demo/hello_world"])
    }

    @Test("IosDisplay primary screen bounds, safeArea visibleBounds, scaleFactor, and UUID")
    @MainActor
    func displayMetricsAndIdentifiers() throws {
        let primary = IosDisplay.primary()
        let allDisplays = IosDisplay.all()
        #expect(!allDisplays.isEmpty)

        let bounds = primary.bounds()
        #expect(bounds.size.width.value > 0)
        #expect(bounds.size.height.value > 0)

        let visible = primary.visibleBounds()
        #expect(visible.size.width.value > 0)
        #expect(visible.size.height.value > 0)
        #expect(visible.size.width.value <= bounds.size.width.value)
        #expect(visible.size.height.value <= bounds.size.height.value)

        #expect(primary.scaleFactor() >= 1.0)

        let displayUuid = try primary.uuid()
        #expect(displayUuid != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test("IosDispatcher main thread detection, background dispatch, timer, and realtime thread")
    func dispatcherQueuesAndRealtimeThread() async throws {
        let dispatcher = IosDispatcher.new()

        let mainFlag = await MainActor.run {
            dispatcher.isMainThread()
        }
        #expect(mainFlag == true)

        // Background dispatch
        let bgCompleted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            dispatcher.dispatch(
                {
                    continuation.resume(returning: !dispatcher.isMainThread())
                },
                priority: .medium
            )
        }
        #expect(bgCompleted == true)

        // Timer dispatchAfter
        let timerFired = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            dispatcher.dispatchAfter(duration: 0.015) {
                continuation.resume(returning: true)
            }
        }
        #expect(timerFired == true)

        // Realtime thread name check
        let realtimeThreadName = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            dispatcher.spawnRealtime {
                continuation.resume(returning: Thread.current.name ?? "")
            }
        }
        #expect(realtimeThreadName == "gpui-ios-realtime")
    }

    @Test("IosKeyboardLayout, international IosKeyboardMapper equivalents, and USB HID keycode mapping")
    @MainActor
    func keyboardLayoutMapperAndHidTranslation() {
        let layout = IosKeyboardLayout.current()
        #expect(!layout.id.isEmpty)
        #expect(!layout.name.isEmpty)

        // French AZERTY: key 'a' reports key equivalent 'q' (and 'q' -> 'a')
        let azertyMapper = IosKeyboardMapper("fr_FR@sw=AZERTY")
        let mappedAzertyQ = azertyMapper.mapKeyEquivalent(
            keystroke: Keystroke(modifiers: Modifiers(control: true), key: "q"),
            useKeyEquivalents: true
        )
        #expect(mappedAzertyQ.key == "a")

        // German QWERTZ: key 'z' reports key equivalent 'y'
        let qwertzMapper = IosKeyboardMapper("de_DE")
        let mappedQwertzZ = qwertzMapper.mapKeyEquivalent(
            keystroke: Keystroke(modifiers: Modifiers(platform: true), key: "z"),
            useKeyEquivalents: true
        )
        #expect(mappedQwertzZ.key == "y")

        // Turkish-F: key 'f' reports key equivalent 'a'
        let turkishFMapper = IosKeyboardMapper("tr-F")
        let mappedTurkishF = turkishFMapper.mapKeyEquivalent(
            keystroke: Keystroke(modifiers: Modifiers(platform: true), key: "f"),
            useKeyEquivalents: true
        )
        #expect(mappedTurkishF.key == "a")

        // US QWERTY: identity mapping
        let usMapper = IosKeyboardMapper("en_US")
        let mappedUs = usMapper.mapKeyEquivalent(
            keystroke: Keystroke(modifiers: Modifiers(platform: true), key: "z"),
            useKeyEquivalents: true
        )
        #expect(mappedUs.key == "z")

        // USB HID keycode translation
        #expect(keycodeToKeyName(0x04, charactersIgnoringModifiers: "A") == "a")
        #expect(keycodeToKeyName(0x28, charactersIgnoringModifiers: "\r") == "enter")
        #expect(keycodeToKeyName(0x29, charactersIgnoringModifiers: "\u{1B}") == "escape")
        #expect(keycodeToKeyName(0x2A, charactersIgnoringModifiers: "\u{08}") == "backspace")
        #expect(keycodeToKeyName(0x4F, charactersIgnoringModifiers: "") == "right")
        #expect(isHidModifierKey(0xE0) == true)
        #expect(isHidModifierKey(0x04) == false)
    }

    @Test("IosTextSystem CoreText font discovery, metrics, UTF-8/UTF-16 emoji shaping, and glyph rasterization")
    func coreTextFontShapingAndGlyphRasterization() throws {
        let textSystem = IosTextSystem.new()
        let families = textSystem.allFontNames()
        #expect(!families.isEmpty)

        let sysFontId = try textSystem.fontId(descriptor: Font(family: ".SystemUIFont"))
        let boldFontId = try textSystem.fontId(descriptor: Font(family: ".SystemUIFont").bold())
        #expect(sysFontId != boldFontId)

        let metrics = textSystem.fontMetrics(fontId: sysFontId)
        #expect(metrics.unitsPerEm > 0)
        #expect(metrics.ascent > 0)
        #expect(metrics.descent < 0)
        #expect(metrics.capHeight > 0)

        let glyphA = try #require(textSystem.glyphForChar(fontId: sysFontId, ch: "A"))
        let advA = try textSystem.advance(fontId: sysFontId, glyphId: glyphA)
        #expect(advA.width > 0)

        // Shape mixed ASCII + surrogate-pair emoji line and verify UTF-8 byte offsets
        let sample = "Hi 😀 OK"
        let layout = textSystem.layoutLine(
            text: sample,
            fontSize: px(20.0),
            runs: [FontRun(len: sample.utf8.count, fontId: sysFontId)]
        )
        #expect(layout.width.value > 0)
        #expect(layout.len == sample.utf8.count)
        let allGlyphs = layout.runs.flatMap(\.glyphs)
        #expect(allGlyphs.count >= 6)
        // "Hi " is 3 UTF-8 bytes, "😀" is 4 UTF-8 bytes -> " " after emoji starts at UTF-8 byte 7
        #expect(allGlyphs.contains(where: { $0.isEmoji && $0.index == 3 }))
        #expect(allGlyphs.contains(where: { !$0.isEmoji && $0.index == 7 }))

        // Rasterize monochrome 'A' glyph and verify non-zero alpha coverage
        let monoParams = RenderGlyphParams(
            fontId: sysFontId,
            glyphId: glyphA,
            fontSize: px(24.0),
            scaleFactor: 2.0,
            isEmoji: false
        )
        let monoBounds = try textSystem.glyphRasterBounds(params: monoParams)
        #expect(monoBounds.size.width.value > 0)
        #expect(monoBounds.size.height.value > 0)

        let (monoSize, monoData) = try textSystem.rasterizeGlyph(
            params: monoParams,
            rasterBounds: monoBounds
        )
        #expect(Int(monoSize.width.value * monoSize.height.value) == monoData.count)
        #expect(monoData.contains(where: { $0 > 0 }))
    }

    @Test("GPUIiOSView CAMetalLayer backing, IosTextInputSession, and IosWindow + MetalRenderer offscreen quad & glyph rendering")
    @MainActor
    func iosWindowViewAndMetalOffscreenQuadAndGlyphRender() throws {
        #expect(GPUIiOSView.layerClass === CAMetalLayer.self)

        // Verify UIKit text input trait helper & session lifecycle
        let singleLineCfg = IosTextInputTraitsConfig(base: TextInputConfig(multiline: false))
        let multiLineCfg = IosTextInputTraitsConfig(base: TextInputConfig(multiline: true))
        #expect(shouldUseTextView(singleLineCfg) == false)
        #expect(shouldUseTextView(multiLineCfg) == true)

        let windowOptions = WindowOptions(
            windowBounds: .windowed(
                Bounds(
                    origin: Point(x: px(0), y: px(0)),
                    size: Size(width: px(128), height: px(96))
                )
            ),
            focus: false,
            show: false
        )
        let iosWindow = try IosWindow.new(AnyWindowHandle(id: 9001), windowOptions)
        #expect(iosWindow.rawNativeViewPtr() != nil)
        #expect(iosWindow.gpuSpecs()?.driverName == "Metal")

        // Rasterize a real CoreText glyph ('M') and upload to IosWindow's Metal spriteAtlas
        let textSystem = IosTextSystem.new()
        let fontId = try textSystem.fontId(descriptor: Font(family: ".SystemUIFont").bold())
        let glyphM = try #require(textSystem.glyphForChar(fontId: fontId, ch: "M"))
        let glyphParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphM,
            fontSize: px(32.0),
            scaleFactor: 1.0,
            isEmoji: false
        )
        let glyphBounds = try textSystem.glyphRasterBounds(params: glyphParams)
        let (glyphBitmapSize, glyphBytes) = try textSystem.rasterizeGlyph(
            params: glyphParams,
            rasterBounds: glyphBounds
        )
        let atlas = iosWindow.spriteAtlas()
        let glyphTile = try #require(
            try atlas.getOrInsertWith(key: .glyph(glyphParams)) {
                (glyphBitmapSize, glyphBytes)
            }
        )

        let targetSize = Size(width: DevicePixels(96), height: DevicePixels(64))
        let mask = ContentMask(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                size: Size(width: ScaledPixels(96), height: ScaledPixels(64))
            )
        )

        var scene = Scene()

        // Left half (0..48, 0..64): pure red Quad via GPUI.red()
        scene.insertQuad(
            Quad(
                bounds: Bounds(
                    origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                    size: Size(width: ScaledPixels(48), height: ScaledPixels(64))
                ),
                contentMask: mask,
                background: solidBackground(red())
            )
        )

        // Right half (54.., 12..): bright green CoreText-rasterized 'M' MonochromeSprite
        let glyphW = Float(glyphBitmapSize.width.value)
        let glyphH = Float(glyphBitmapSize.height.value)
        scene.insertMonochromeSprite(
            MonochromeSprite(
                bounds: Bounds(
                    origin: Point(x: ScaledPixels(54), y: ScaledPixels(12)),
                    size: Size(width: ScaledPixels(glyphW), height: ScaledPixels(glyphH))
                ),
                contentMask: mask,
                color: Hsla(rgba: rgb(0x00FF00)),
                tile: glyphTile,
                transformation: .unit
            )
        )

        scene.finish()

        let rendered = try iosWindow.renderToTexture(
            scene,
            size: targetSize,
            background: black()
        )
        #expect(rendered.width == 96)
        #expect(rendered.height == 64)

        // Verify red quad pixel at (24, 32) — GPUI.red() is non-zero red over black background
        let quadCenter = pixel(in: rendered, x: 24, y: 32)
        #expect(quadCenter.r >= 180 && quadCenter.r > quadCenter.g && quadCenter.r > quadCenter.b && quadCenter.a == 255)

        // Verify CoreText glyph sprite region (54..<(54+w), 12..<(12+h)) painted green pixels
        var greenGlyphPixels = 0
        let maxX = min(95, 54 + Int(glyphW))
        let maxY = min(63, 12 + Int(glyphH))
        for py in 12..<maxY {
            for pxX in 54..<maxX {
                let p = pixel(in: rendered, x: pxX, y: py)
                if p.g >= 80 && p.r <= 15 && p.b <= 15 {
                    greenGlyphPixels += 1
                }
            }
        }
        #expect(greenGlyphPixels >= 20)
    }

    @Test("IosTextInputSession bridges GPUI.PlatformInputHandler end-to-end across UIKit typing, selection, backspace, return submit, and blur flush")
    @MainActor
    func iosTextInputSessionBridgesPlatformInputHandlerEndToEnd() throws {
        final class RecordingIosInputHandler: InputHandler {
            var text: String = "hi"
            var selection: UTF16Selection = UTF16Selection(range: 2..<2, reversed: false)
            var marked: Range<Int>? = nil
            var config: TextInputConfig = TextInputConfig(multiline: false, submitBehavior: .submit)
            var deleteBackwardCount: Int = 0
            var submitCount: Int = 0

            func selectedTextRange(ignoreDisabledInput: Bool, window: inout Window, cx: inout App) -> UTF16Selection? {
                selection
            }

            func markedTextRange(window: inout Window, cx: inout App) -> Range<Int>? {
                marked
            }

            func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?, window: inout Window, cx: inout App) -> String? {
                let clampedEnd = min(rangeUtf16.upperBound, text.utf16.count)
                let clampedStart = min(max(0, rangeUtf16.lowerBound), clampedEnd)
                let clamped = clampedStart..<clampedEnd
                adjustedRange = clamped
                guard let strRange = IMEBridge.utf16RangeToStringRange(clamped, in: text) else {
                    return nil
                }
                return String(text[strRange])
            }

            func replaceTextInRange(rangeUtf16: Range<Int>?, text replacement: String, window: inout Window, cx: inout App) {
                let target = rangeUtf16 ?? marked ?? selection.range
                if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
                    text.replaceSubrange(strRange, with: replacement)
                    let cursor = target.lowerBound + replacement.utf16.count
                    selection = UTF16Selection(range: cursor..<cursor, reversed: false)
                }
                marked = nil
            }

            func deleteBackward(window: inout Window, cx: inout App) {
                deleteBackwardCount += 1
            }

            func replaceAndMarkTextInRange(
                rangeUtf16: Range<Int>?,
                newText: String,
                newSelectedRange: Range<Int>?,
                window: inout Window,
                cx: inout App
            ) {
                let target = rangeUtf16 ?? marked ?? selection.range
                if let strRange = IMEBridge.utf16RangeToStringRange(target, in: text) {
                    text.replaceSubrange(strRange, with: newText)
                    let start = target.lowerBound
                    let end = start + newText.utf16.count
                    marked = newText.isEmpty ? nil : (start..<end)
                    selection = UTF16Selection(range: end..<end, reversed: false)
                }
            }

            func unmarkText(window: inout Window, cx: inout App) {
                marked = nil
            }

            func setSelectedTextRange(selection: UTF16Selection?, window: inout Window, cx: inout App) {
                if let selection {
                    self.selection = selection
                }
            }

            func boundsForRange(rangeUtf16: Range<Int>, window: inout Window, cx: inout App) -> Bounds<Pixels>? {
                Bounds(origin: Point(x: px(12), y: px(24)), size: Size(width: px(2), height: px(20)))
            }

            func characterIndexForPoint(point: Point<Pixels>, window: inout Window, cx: inout App) -> Int? {
                0
            }

            func textInputConfig(window: inout Window, cx: inout App) -> TextInputConfig {
                config
            }

            func submitTextInput(window: inout Window, cx: inout App) {
                submitCount += 1
            }
        }

        struct DummyIosInputView: Render {
            func render(_ window: inout GPUI.Window, _ cx: inout GPUI.Context<DummyIosInputView>) -> some IntoElement {
                div()
            }
        }

        let platform = IosPlatform.new()
        let app = App.newApp(platform: platform)
        let winOpts = WindowOptions(
            windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(200), height: px(120)))),
            focus: false,
            show: false
        )
        let handle = try app.openWindow(winOpts) { _, cx in
            cx.new { _ in DummyIosInputView() }
        }
        let iosWindow = try #require(
            try app.updateWindow(handle.anyHandle) { _, win, _ in win.platformWindow as? IosWindow }
        )

        let recorder = RecordingIosInputHandler()
        let platformHandler = PlatformInputHandler(
            windowHandle: handle.anyHandle,
            app: app,
            handler: recorder
        )

        // 1. Installing `PlatformInputHandler` synchronizes GPUI text ("hi") into UIKit backing control
        iosWindow.setInputHandler(platformHandler)
        let session = iosWindow.textInputSession
        #expect(session.backedInput.text() == "hi")

        // 2. Typing into UIKit backing control propagates diff into `PlatformInputHandler`
        session.backedInput.setText("hi!")
        session.backedInput.setSelectedRangeUtf16(3..<3)
        session.receiveUiKitEvent(.textChanged)
        #expect(recorder.text == "hi!")
        #expect(recorder.selection.range == 3..<3)

        // 3. Selection change propagates to `PlatformInputHandler`
        session.backedInput.setSelectedRangeUtf16(0..<2)
        session.receiveUiKitEvent(.selectionChanged)
        #expect(recorder.selection.range == 0..<2)

        // 4. Empty backspace calls `InputHandler.deleteBackward`
        session.receiveEmptyBackspace()
        #expect(recorder.deleteBackwardCount == 1)

        // 5. Return key submits via `InputHandler.submitTextInput`
        if case .textField(let tf) = session.backedInput.control {
            _ = session.delegate.textFieldShouldReturn(tf)
        }
        #expect(recorder.submitCount == 1)

        // 6. Switch to multiline `UITextView` with `.submit` behavior: `\n` intercepts as submit,
        //    and `textViewDidEndEditing` flushes pending edits to `PlatformInputHandler`.
        recorder.config = TextInputConfig(multiline: true, submitBehavior: .submit)
        iosWindow.setInputHandler(platformHandler)
        if case .textView(let tv) = session.backedInput.control {
            let allowNewline = session.delegate.textView(
                tv,
                shouldChangeTextIn: NSRange(location: 3, length: 0),
                replacementText: "\n"
            )
            #expect(allowNewline == false)
            #expect(recorder.submitCount == 2)

            tv.text = "hi! flushed"
            session.delegate.textViewDidEndEditing(tv)
            #expect(recorder.text == "hi! flushed")
        } else {
            Issue.record("Expected multiline TextInputConfig to rebuild backing control into UITextView")
        }
    }
}
#endif
