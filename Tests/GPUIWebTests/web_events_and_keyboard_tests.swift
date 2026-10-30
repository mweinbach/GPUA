// Swift-only: Behavioral unit tests for GPUIWeb keyboard, events, display, dispatcher, window, platform, and HTTP client logic

import Foundation
import GPUI
import HTTPClient
import Scheduler
import Testing
@testable import GPUIWeb

private final class MockWebImeHandler: PlatformInputHandlerProtocol {
    var replacedTexts: [(Range<Int>?, String)] = []
    var markedTexts: [(Range<Int>?, String, Range<Int>?)] = []
    var unmarkCount: Int = 0

    func dispatchInput(_ text: String, _ window: inout Window, _ cx: inout App) {
        replacedTexts.append((nil, text))
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text: String) {
        replacedTexts.append((rangeUtf16, text))
    }

    func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?
    ) {
        markedTexts.append((rangeUtf16, newText, newSelectedRange))
    }

    func unmarkText() {
        unmarkCount += 1
    }
}

@MainActor
private final class RecordingWebInputHandler: InputHandler {
    var text: String = ""
    var selection: Range<Int> = 0..<0
    var marked: Range<Int>? = nil
    var unmarkCount: Int = 0

    func selectedTextRange(ignoreDisabledInput: Bool, window: inout Window, cx: inout App) -> UTF16Selection? {
        UTF16Selection(range: selection, reversed: false)
    }

    func markedTextRange(window: inout Window, cx: inout App) -> Range<Int>? {
        marked
    }

    func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?, window: inout Window, cx: inout App) -> String? {
        text
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text replacement: String, window: inout Window, cx: inout App) {
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
        window: inout Window,
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

    func unmarkText(window: inout Window, cx: inout App) {
        marked = nil
        unmarkCount += 1
    }

    func setSelectedTextRange(selection: UTF16Selection?, window: inout Window, cx: inout App) {
        if let selection {
            self.selection = selection.range
        }
    }

    func boundsForRange(rangeUtf16: Range<Int>, window: inout Window, cx: inout App) -> Bounds<Pixels>? {
        Bounds(origin: point(px(10), px(20)), size: size(px(2), px(18)))
    }

    func characterIndexForPoint(point: Point<Pixels>, window: inout Window, cx: inout App) -> Int? {
        0
    }
}

private struct WebInputDummyView: Render {
    func render(_ window: inout Window, _ cx: inout Context<WebInputDummyView>) -> some IntoElement {
        div()
    }
}

private final class LockedRecorder<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }

    func snapshot() -> [T] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}

@Suite("GPUIWeb events, keyboard, platform, and HTTP tests")
struct WebEventsAndKeyboardTests {
    @Test("WebKeyboardLayout reports standard US layout defaults and custom IDs")
    func testKeyboardLayout() {
        let layout = WebKeyboardLayout.new()
        #expect(layout.id == "us")
        #expect(layout.name == "US")

        let custom = WebKeyboardLayout(id: "de", name: "German")
        #expect(custom.id == "de")
        #expect(custom.name == "German")
    }

    @Test("DOM KeyboardEvent.key maps faithfully onto GPUI key names")
    func testDomKeyMapping() {
        #expect(domKeyToGpuiKey("Enter") == "enter")
        #expect(domKeyToGpuiKey("Backspace") == "backspace")
        #expect(domKeyToGpuiKey("Tab") == "tab")
        #expect(domKeyToGpuiKey("Escape") == "escape")
        #expect(domKeyToGpuiKey("Delete") == "delete")
        #expect(domKeyToGpuiKey(" ") == "space")
        #expect(domKeyToGpuiKey("ArrowLeft") == "left")
        #expect(domKeyToGpuiKey("ArrowRight") == "right")
        #expect(domKeyToGpuiKey("ArrowUp") == "up")
        #expect(domKeyToGpuiKey("ArrowDown") == "down")
        #expect(domKeyToGpuiKey("Home") == "home")
        #expect(domKeyToGpuiKey("End") == "end")
        #expect(domKeyToGpuiKey("PageUp") == "pageup")
        #expect(domKeyToGpuiKey("PageDown") == "pagedown")
        #expect(domKeyToGpuiKey("Insert") == "insert")
        #expect(domKeyToGpuiKey("Control") == "control")
        #expect(domKeyToGpuiKey("Alt") == "alt")
        #expect(domKeyToGpuiKey("Shift") == "shift")
        #expect(domKeyToGpuiKey("Meta") == "platform")
        #expect(domKeyToGpuiKey("CapsLock") == "capslock")
        #expect(domKeyToGpuiKey("F1") == "f1")
        #expect(domKeyToGpuiKey("F12") == "f12")
        #expect(domKeyToGpuiKey("F35") == "f35")
        #expect(domKeyToGpuiKey("F36") == "f36")
        #expect(domKeyToGpuiKey("A") == "a")
        #expect(domKeyToGpuiKey("z") == "z")
    }

    @Test("computeKeyChar handles printable keys, space, and command/control suppression")
    func testComputeKeyChar() {
        #expect(computeKeyChar(rawKey: "a", gpuiKey: "a", modifiers: .none()) == "a")
        #expect(computeKeyChar(rawKey: "A", gpuiKey: "a", modifiers: .shift()) == "A")
        #expect(computeKeyChar(rawKey: " ", gpuiKey: "space", modifiers: .none()) == " ")
        #expect(computeKeyChar(rawKey: "c", gpuiKey: "c", modifiers: .command()) == nil)
        #expect(computeKeyChar(rawKey: "c", gpuiKey: "c", modifiers: .control()) == nil)
        #expect(computeKeyChar(rawKey: "Shift", gpuiKey: "shift", modifiers: .shift()) == nil)
        #expect(computeKeyChar(rawKey: "Enter", gpuiKey: "enter", modifiers: .none()) == nil)
    }

    @Test("DOM mouse buttons map onto GPUI MouseButton variants")
    func testMouseButtonMapping() {
        #expect(domMouseButtonToGpui(0) == .left)
        #expect(domMouseButtonToGpui(1) == .middle)
        #expect(domMouseButtonToGpui(2) == .right)
        #expect(domMouseButtonToGpui(3) == .navigate(.back))
        #expect(domMouseButtonToGpui(4) == .navigate(.forward))
        #expect(domMouseButtonToGpui(99) == .left)
    }

    @Test("ClickState counts multi-clicks within 400ms and 5px and resets otherwise")
    func testClickStateMultiClick() {
        var state = ClickState.default()
        let p1 = Point(x: px(100), y: px(100))
        let pNear = Point(x: px(103), y: px(103)) // distance = sqrt(18) ~= 4.24 < 5
        let pFar = Point(x: px(110), y: px(100))  // distance = 10 >= 5

        #expect(state.registerClick(p1, 1000.0) == 1)
        #expect(state.registerClick(pNear, 1250.0) == 2)
        #expect(state.registerClick(pNear, 1500.0) == 3)
        // Timeout >= 400ms resets count
        #expect(state.registerClick(pNear, 1900.0) == 1)
        // Distance >= 5px resets count even within 400ms
        #expect(state.registerClick(pFar, 2000.0) == 1)
    }

    @Test("Wheel deltas negate browser coordinates and distinguish pixel, line, and page modes")
    func testWheelDeltaMapping() {
        let pixelDelta = wheelDeltaToGpui(
            deltaX: 12.0,
            deltaY: -24.0,
            deltaMode: DOM_DELTA_PIXEL,
            pageSize: nil
        )
        #expect(pixelDelta == .pixels(Point(x: px(-12.0), y: px(24.0))))

        let lineDelta = wheelDeltaToGpui(
            deltaX: 0.0,
            deltaY: 3.0,
            deltaMode: DOM_DELTA_LINE,
            pageSize: nil
        )
        #expect(lineDelta == .lines(Point(x: 0.0, y: -3.0)))

        let pageDelta = wheelDeltaToGpui(
            deltaX: 0.0,
            deltaY: 1.0,
            deltaMode: DOM_DELTA_PAGE,
            pageSize: Size(width: px(800), height: px(600))
        )
        #expect(pageDelta == .pixels(Point(x: px(0.0), y: px(-600.0))))
    }

    @Test("CursorStyle maps onto standard CSS cursor keywords")
    func testCursorStyleCssMapping() {
        #expect(cursorStyleToCss(.arrow) == "default")
        #expect(cursorStyleToCss(.iBeam) == "text")
        #expect(cursorStyleToCss(.pointingHand) == "pointer")
        #expect(cursorStyleToCss(.openHand) == "grab")
        #expect(cursorStyleToCss(.closedHand) == "grabbing")
        #expect(cursorStyleToCss(.resizeLeftRight) == "ew-resize")
        #expect(cursorStyleToCss(.resizeUpDown) == "ns-resize")
        #expect(cursorStyleToCss(.resizeUpLeftDownRight) == "nesw-resize")
        #expect(cursorStyleToCss(.resizeUpRightDownLeft) == "nwse-resize")
        #expect(cursorStyleToCss(.notAllowed) == "not-allowed")
        #expect(cursorStyleToCss(.none) == "none")
    }

    @Test("WebDisplay computes bounds, visibleBounds, and centered 75% defaultBounds")
    func testWebDisplayGeometry() throws {
        let display = WebDisplay(
            screenSize: Size(width: px(2560), height: px(1440)),
            viewportSize: Size(width: px(1600), height: px(1000))
        )
        #expect(display.id() == DisplayId(1))
        _ = try display.uuid()
        #expect(display.bounds() == Bounds(origin: .zero, size: Size(width: px(2560), height: px(1440))))
        #expect(display.visibleBounds() == Bounds(origin: .zero, size: Size(width: px(1600), height: px(1000))))

        let def = display.defaultBounds()
        #expect(def.size == Size(width: px(1200), height: px(750)))
        #expect(def.origin == Point(x: px(200), y: px(125)))
    }

    @Test("WebDispatcher routes realtime priorities to microtasks and standard tasks to timeouts")
    func testWebDispatcherScheduling() {
        let recorded = LockedRecorder<WebDispatchScheduleKind>()
        let executed = LockedRecorder<String>()

        let dispatcher = WebDispatcher(allowThreads: false) { kind, runnable in
            recorded.append(kind)
            runnable()
        }

        #expect(dispatcher.isMainThread())
        dispatcher.dispatch({ executed.append("default") }, priority: .medium)
        dispatcher.dispatchOnMainThread({ executed.append("audio") }, priority: .realtimeAudio)
        dispatcher.dispatchAfter(duration: 0.25) { executed.append("delayed") }
        dispatcher.spawnRealtime { executed.append("realtime") }

        #expect(recorded.snapshot() == [
            .timeout(delayMs: 0),
            .microtask,
            .timeout(delayMs: 250),
            .microtask,
        ])
        #expect(executed.snapshot() == ["default", "audio", "delayed", "realtime"])
    }

    @Test("WebWindow dispatches pointer, keyboard, IME composition, file drop, and resize events")
    func testWebWindowEventAndImeDispatch() {
        let window = WebWindow(
            handle: AnyWindowHandle(id: 42),
            options: WindowOptions(titlebar: TitlebarOptions(title: "Hello Web")),
            initialDpr: 2.0,
            hasDevicePixelSupport: true,
            isMac: true
        )

        var receivedInputs: [PlatformInput] = []
        var propagateKeyDown = true
        window.onInput { input in
            receivedInputs.append(input)
            return DispatchEventResult(propagate: propagateKeyDown, defaultPrevented: false)
        }

        let ime = MockWebImeHandler()
        window.setInputHandler(ime)

        // ResizeObserver + animation frame reconciliation
        var resizedTo: (Size<Pixels>, Float)? = nil
        window.onResize { size, scale in
            resizedTo = (size, scale)
        }
        window.inner.handleResizeObserver(
            physicalWidth: 1600,
            physicalHeight: 1200,
            logicalWidth: 800,
            logicalHeight: 600,
            dpr: 2.0
        )
        window.inner.reconcileEnvironment(overrideDpr: 2.0)
        #expect(resizedTo?.0 == Size(width: px(800), height: px(600)))
        #expect(resizedTo?.1 == 2.0)
        #expect(window.contentSize() == Size(width: px(800), height: px(600)))

        // Pointer down -> move -> up
        let clickPos = Point(x: px(50), y: px(60))
        window.inner.handlePointerDown(button: 0, position: clickPos, modifiersFlags: WEB_MOD_SHIFT, timestampMs: 100.0)
        window.inner.handlePointerMove(position: Point(x: px(55), y: px(65)), modifiersFlags: WEB_MOD_SHIFT)
        window.inner.handlePointerUp(button: 0, position: Point(x: px(55), y: px(65)), modifiersFlags: WEB_MOD_SHIFT)

        #expect(receivedInputs.count == 3)
        if case .mouseMove(let moveEvent) = receivedInputs[1] {
            #expect(moveEvent.pressedButton == .left)
            #expect(moveEvent.modifiers.shift)
        } else {
            Issue.record("Expected mouseMove event")
        }

        // Printable keydown forwards to IME handler when propagate == true
        let prevented = window.inner.handleKeyDown(
            rawKey: "x",
            modifiersFlags: 0,
            isRepeat: false,
            eventIsComposing: false
        )
        #expect(prevented)
        #expect(ime.replacedTexts.count == 1)
        #expect(ime.replacedTexts.first?.1 == "x")

        // When GPUI consumes keybinding (propagate == false), character insertion is skipped
        propagateKeyDown = false
        _ = window.inner.handleKeyDown(
            rawKey: "y",
            modifiersFlags: 0,
            isRepeat: false,
            eventIsComposing: false
        )
        #expect(ime.replacedTexts.count == 1)
        propagateKeyDown = true

        // IME composition lifecycle
        window.inner.handleCompositionStart()
        window.inner.handleCompositionUpdate(data: "に")
        window.inner.handleCompositionEnd(data: "日本")
        #expect(ime.markedTexts.count == 1)
        #expect(ime.markedTexts.first?.1 == "に")
        #expect(ime.replacedTexts.last?.1 == "日本")
        #expect(ime.unmarkCount == 1)

        // File drop lifecycle
        receivedInputs.removeAll()
        let dropPos = Point(x: px(120), y: px(140))
        window.inner.handleDragOver(position: dropPos)
        window.inner.handleDrop(position: dropPos, fileNames: ["readme.md", "main.swift"])
        window.inner.handleDragLeave()
        #expect(receivedInputs == [
            .fileDrop(.pending(position: dropPos)),
            .fileDrop(.entered(position: dropPos, paths: ExternalPaths(paths: ["readme.md", "main.swift"]))),
            .fileDrop(.submit(position: dropPos)),
            .fileDrop(.exited),
        ])
    }

    @Test("WebPlatform exposes Web compositor, clipboard cache, cursor CSS, and unsupported desktop errors")
    func testWebPlatformBehavior() async {
        let platform = WebPlatform.new(false)
        #expect(platform.compositorName() == "Web")
        #expect(platform.shouldAutoHideScrollbars())
        #expect(platform.thermalState() == .nominal)
        #expect(!platform.canSelectMixedFilesAndDirs())
        #expect(platform.displays().count == 1)
        #expect(platform.primaryDisplay() != nil)

        platform.setCursorStyle(.pointingHand)
        #expect(platform.lastAppliedCssCursor == "pointer")

        let clip = ClipboardItem(text: "gpui-web-clipboard")
        platform.writeToClipboard(clip)
        #expect(platform.readFromClipboard() == clip)

        let winHandle = AnyWindowHandle(id: 7)
        let opened = platform.openWindow(handle: winHandle, options: WindowOptions())
        #expect(platform.activeWindow() == winHandle)
        let webWin = try? #require(opened as? WebWindow)
        #expect(webWin?.windowDecorations() == .server)
        #expect(webWin?.windowControls() == WindowControls())

        #expect(throws: WebPlatformError.self) {
            _ = try platform.appPath()
        }
        await #expect(throws: WebPlatformError.self) {
            _ = try await platform.promptForPaths(options: PathPromptOptions())
        }
    }

    @Test("FetchHttpClient validates ASCII headers, maps redirect policy, and decodes responses")
    func testFetchHttpClient() async throws {
        let captured = LockedRecorder<PreparedFetchRequest>()
        let client = try FetchHttpClient(userAgent: "GPUA-Web/1.0") { prepared in
            captured.append(prepared)
            let encoded = FetchHttpClient.encodeHeaderPairs([
                ("content-type", "application/json"),
                ("x-gpui-test", "ok"),
            ])
            return RawFetchResponse(
                status: 201,
                encodedHeaders: encoded,
                body: Data("{\"ok\":true}".utf8)
            )
        }

        #expect(client.userAgent() == "GPUA-Web/1.0")
        #expect(client.proxy() == nil)

        let req = HttpRequest(
            method: "POST",
            uri: "https://example.com/api",
            headers: ["X-Custom": "value"],
            body: .fromBytes(Data("hello".utf8)),
            redirectPolicy: .followAll
        )
        let resp = try await client.send(req)
        #expect(resp.status == 201)
        #expect(resp.headers["content-type"] == "application/json")
        #expect(resp.headers["x-gpui-test"] == "ok")
        let respBody = try await resp.body.readToBytes()
        #expect(String(decoding: respBody, as: UTF8.self) == "{\"ok\":true}")

        let sentList = captured.snapshot()
        #expect(sentList.count == 1)
        #expect(sentList[0].redirectMode == .follow)
        #expect(sentList[0].body == Data("hello".utf8))
        #expect(sentList[0].headers.contains(where: { $0.0 == "User-Agent" && $0.1 == "GPUA-Web/1.0" }))

        // Non-ASCII header value must be rejected matching upstream http_client.rs
        let badReq = HttpRequest(
            method: "GET",
            uri: "https://example.com",
            headers: ["X-Bad": "café"],
            redirectPolicy: .noFollow
        )
        await #expect(throws: FetchHttpError.self) {
            _ = try await client.send(badReq)
        }
    }

    @Test("GPUI.PlatformInputHandler receives Web keydown printable characters, IME composition, and preserves re-entrant replacement")
    @MainActor
    func testPlatformInputHandlerEndToEndOnWeb() throws {
        let platform = WebPlatform.new(false)
        let app = App.newApp(platform: platform)
        let handle = try app.openWindow(WindowOptions()) { _, cx in
            cx.new { _ in WebInputDummyView() }
        }
        let webWindow = try #require(
            try app.updateWindow(handle.anyHandle) { _, win, _ in win.platformWindow as? WebWindow }
        )

        let recorder = RecordingWebInputHandler()
        let platformHandler = PlatformInputHandler(
            windowHandle: handle.anyHandle,
            app: app,
            handler: recorder
        )
        webWindow.setInputHandler(platformHandler)

        // Override `onInput` so keyDown propagates (`propagate: true`) into the input handler path
        webWindow.onInput { _ in
            DispatchEventResult(propagate: true, defaultPrevented: false)
        }

        // 1. Printable typing (`a`, `B`) dispatches directly to `PlatformInputHandler`
        _ = webWindow.inner.handleKeyDown(
            rawKey: "a",
            code: "KeyA",
            modifiersFlags: 0,
            isRepeat: false,
            eventIsComposing: false
        )
        _ = webWindow.inner.handleKeyDown(
            rawKey: "B",
            code: "KeyB",
            modifiersFlags: WEB_MOD_SHIFT,
            isRepeat: false,
            eventIsComposing: false
        )
        #expect(recorder.text == "aB")

        // 2. Browser IME composition (`compositionstart` -> `compositionupdate` -> `compositionend`)
        webWindow.inner.handleCompositionStart()
        webWindow.inner.handleCompositionUpdate(data: "にほ")
        #expect(recorder.text == "aBにほ")
        #expect(recorder.marked == 2..<4)

        webWindow.inner.handleCompositionEnd(data: "日本")
        #expect(recorder.text == "aB日本")
        #expect(recorder.marked == nil)
        #expect(recorder.unmarkCount == 1)

        // 3. Re-entrantly installing a new handler inside `withInputHandler` must NOT be overwritten
        let replacement = MockWebImeHandler()
        _ = webWindow.inner.withInputHandler { _ in
            webWindow.setInputHandler(replacement)
        }
        #expect(webWindow.activeInputHandler() === replacement)
    }
}
