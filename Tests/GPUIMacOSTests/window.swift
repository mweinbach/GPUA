// Tests ported from: crates/gpui_macos/src/window.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import AppKit
import GPUI
import GPUIMetal
import QuartzCore
import Testing
@testable import GPUIMacOS

// PORT NOTE: MockMacInputHandler exercises GPUIView's NSTextInputClient bridge deterministically on the main actor.
private final class MockMacInputHandler: PlatformInputHandlerProtocol, @unchecked Sendable {
    var buffer: String = "hello world"
    var selection: UTF16Selection? = UTF16Selection(range: 6 ..< 11, reversed: false)
    var marked: Range<Int>? = nil
    var lastReplacedRange: Range<Int>?? = nil
    var lastReplacedText: String? = nil
    var lastMarkedReplace: (Range<Int>?, String, Range<Int>?)? = nil
    var unmarkCount: Int = 0
    var candidateBounds: Bounds<Pixels> = Bounds(
        origin: point(px(20), px(30)),
        size: size(px(40), px(18))
    )
    var lastQueriedPoint: Point<Pixels>? = nil

    func dispatchInput(_ text: String, _ window: inout GPUI.Window, _ cx: inout App) {
        replaceTextInRange(rangeUtf16: nil, text: text)
    }

    func selectedTextRange(ignoreDisabledInput: Bool) -> UTF16Selection? {
        _ = ignoreDisabledInput
        return selection
    }

    func markedTextRange() -> Range<Int>? {
        marked
    }

    func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?) -> String? {
        let clampedUpper = min(rangeUtf16.upperBound, buffer.utf16.count)
        let clampedLower = min(max(0, rangeUtf16.lowerBound), clampedUpper)
        let clamped = clampedLower ..< clampedUpper
        if clamped != rangeUtf16 {
            adjustedRange = clamped
        }
        guard let strRange = IMEBridge.utf16RangeToStringRange(clamped, in: buffer) else {
            return nil
        }
        return String(buffer[strRange])
    }

    func replaceTextInRange(rangeUtf16: Range<Int>?, text: String) {
        lastReplacedRange = .some(rangeUtf16)
        lastReplacedText = text
        let target = rangeUtf16 ?? marked ?? selection?.range ?? (buffer.utf16.count ..< buffer.utf16.count)
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: buffer) {
            buffer.replaceSubrange(strRange, with: text)
            let newCaret = target.lowerBound + text.utf16.count
            selection = UTF16Selection(range: newCaret ..< newCaret, reversed: false)
            marked = nil
        }
    }

    func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?
    ) {
        lastMarkedReplace = (rangeUtf16, newText, newSelectedRange)
        let target = rangeUtf16 ?? marked ?? selection?.range ?? (buffer.utf16.count ..< buffer.utf16.count)
        if let strRange = IMEBridge.utf16RangeToStringRange(target, in: buffer) {
            buffer.replaceSubrange(strRange, with: newText)
            if newText.isEmpty {
                marked = nil
            } else {
                marked = target.lowerBound ..< (target.lowerBound + newText.utf16.count)
            }
            if let rel = newSelectedRange {
                let start = target.lowerBound + rel.lowerBound
                selection = UTF16Selection(range: start ..< (start + rel.count), reversed: false)
            }
        }
    }

    func unmarkText() {
        unmarkCount += 1
        marked = nil
    }

    func boundsForRange(rangeUtf16: Range<Int>) -> Bounds<Pixels>? {
        _ = rangeUtf16
        return candidateBounds
    }

    func characterIndexForPoint(point: Point<Pixels>) -> Int? {
        lastQueriedPoint = point
        return 4
    }
}

@Suite("GPUIMacOS Window Tests")
struct MacWindowTests {
    @Test("field_editor_shortcuts_include_cmd_backspace")
    func fieldEditorShortcutsIncludeCmdBackspace() {
        let keystroke = Keystroke(
            modifiers: .command(),
            key: "backspace"
        )
        #expect(isFieldEditorShortcut(keystroke))
    }

    @Test("field_editor_shortcuts_do_not_treat_general_cmd_shortcuts_as_native")
    func fieldEditorShortcutsDoNotTreatGeneralCmdShortcutsAsNative() {
        let keystroke = Keystroke(
            modifiers: .command(),
            key: "l"
        )
        #expect(!isFieldEditorShortcut(keystroke))
    }

    @Test("nstextinputclient_bridges_insert_marked_selection_substring_bounds_and_docommand")
    @MainActor
    func nsTextInputClientBridgesToInputHandler() {
        let hostWin = GPUIWindow(
            contentRect: NSRect(x: 100, y: 200, width: 400, height: 300),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        let renderer = GPUIMetal.newRenderer(
            GPUIMetal.Context(),
            Unmanaged.passUnretained(hostWin as AnyObject).toOpaque(),
            nil,
            Size(width: 400.0, height: 300.0),
            false
        )
        let state = MacWindowState(
            handle: AnyWindowHandle(id: 99),
            foregroundExecutor: nil,
            backgroundExecutor: nil,
            renderer: renderer,
            backgroundAppearance: .opaque,
            transparentTitlebar: true,
            trafficLightPosition: nil
        )
        let view = GPUIView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), metalLayer: renderer.layer())
        view.windowState = state
        hostWin.contentView = view
        state.nativeWindow = hostWin
        state.nativeView = view

        let mock = MockMacInputHandler()
        state.inputHandler = mock

        // 1. Selection & substring queries
        #expect(view.selectedRange() == NSRange(location: 6, length: 5))
        #expect(!view.hasMarkedText())
        #expect(view.markedRange().location == NSNotFound)

        var actual = NSRange(location: 0, length: 0)
        let sub = view.attributedSubstring(forProposedRange: NSRange(location: 6, length: 20), actualRange: &actual)
        #expect(sub?.string == "world")
        #expect(actual == NSRange(location: 6, length: 5))

        // 2. IME composition (`setMarkedText` + `markedRange` + `unmarkText`)
        view.setMarkedText(
            "かな",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: 6, length: 5)
        )
        #expect(mock.buffer == "hello かな")
        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 6, length: 2))
        #expect(view.selectedRange() == NSRange(location: 8, length: 0))

        view.unmarkText()
        #expect(mock.unmarkCount == 1)
        #expect(!view.hasMarkedText())

        // 3. Committed text (`insertText` with explicit UTF-16 replacementRange)
        view.insertText("GPUI!", replacementRange: NSRange(location: 6, length: 2))
        #expect(mock.buffer == "hello GPUI!")
        #expect(mock.lastReplacedText == "GPUI!")
        #expect(mock.lastReplacedRange == .some(6 ..< 8))

        // 4. Candidate rect & hit-test coordinate conversion (top-left GPUI <-> bottom-left AppKit screen)
        let screenRect = view.firstRect(forCharacterRange: NSRange(location: 6, length: 1), actualRange: nil)
        #expect(screenRect.origin.x == 120)
        #expect(screenRect.origin.y == 452)
        #expect(screenRect.size.width == 40)
        #expect(screenRect.size.height == 18)

        let charIdx = view.characterIndex(for: NSPoint(x: 125, y: 460))
        #expect(charIdx == 4)
        #expect(mock.lastQueriedPoint == point(px(25), px(40)))

        // 5. `doCommand(by:)` dispatches `keystrokeForDoCommand` through `eventCallback`
        var dispatchedKey: KeyDownEvent? = nil
        state.eventCallback = { (input: PlatformInput) -> DispatchEventResult in
            if case .keyDown(let kd) = input {
                dispatchedKey = kd
                return DispatchEventResult(propagate: false, defaultPrevented: true)
            }
            return DispatchEventResult(propagate: true, defaultPrevented: false)
        }
        state.keystrokeForDoCommand = Keystroke(modifiers: .none(), key: "escape")
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        #expect(dispatchedKey?.keystroke.key == "escape")
        #expect(state.doCommandHandled == true)
    }
}
#endif
