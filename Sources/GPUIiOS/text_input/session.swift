// Ported from: crates/gpui_ios/src/text_input/session.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import GPUI
#if os(iOS) || os(visionOS)
import UIKit
#endif

// MARK: - Pure UTF-16 Text Diffing & Sanitization (Cross-Platform Testable)

// PORT NOTE: Pure UTF-16 diffing and range sanitization functions are compiled unconditionally
// so `Tests/GPUIiOSTests/text_input/session.swift` runs on macOS, Linux, and iOS Simulator alike,
// while the UIKit-backed `IosTextInputSession` and delegate live under `#if os(iOS) || os(visionOS)`.

/// Minimal UTF-16 edit span replacing `oldRangeUtf16` in the previous string with `newText`.
struct TextDiff: Sendable, Equatable {
    var oldRangeUtf16: Range<Int>
    var newText: String

    init(oldRangeUtf16: Range<Int>, newText: String) {
        self.oldRangeUtf16 = oldRangeUtf16
        self.newText = newText
    }
}

/// Returns the length of `value` in UTF-16 code units, matching upstream `utf16_len`.
func utf16Len(_ value: String) -> Int {
    value.utf16.count
}

/// Returns a minimal fallback IME anchor rectangle `(0, 0, 1, 1)` when the input handler does not
/// report explicit character bounds.
func defaultBounds() -> Bounds<Pixels> {
    Bounds.fromCorners(point(px(0.0), px(0.0)), point(px(1.0), px(1.0)))
}

/// Constructs a `UTF16Selection` from `range`, preserving `reversed == true` if and only if
/// `previous` had the exact same range and was reversed, matching upstream `selection_from_range`.
func selectionFromRange(_ range: Range<Int>, _ previous: UTF16Selection?) -> UTF16Selection {
    let reversed = previous.map { $0.range == range && $0.reversed } ?? false
    return UTF16Selection(range: range, reversed: reversed)
}

/// Sanitizes raw UTF-16 selection `(start, end)` offsets against `textLenUtf16`:
/// rejects reversed (`start > end`) or negative offsets (`nil`), and clamps stale offsets into
/// `0...textLenUtf16`, matching upstream `sanitize_selection_range`.
func sanitizeSelectionRange(start: Int, end: Int, textLenUtf16: Int) -> Range<Int>? {
    if start < 0 || end < 0 || start > end {
        return nil
    }
    let clampedLen = max(0, textLenUtf16)
    let clampedStart = min(start, clampedLen)
    let clampedEnd = min(end, clampedLen)
    return clampedStart..<clampedEnd
}

/// Overload accepting a Swift `Range<Int>` directly.
func sanitizeSelectionRange(_ range: Range<Int>, _ textLenUtf16: Int) -> Range<Int>? {
    sanitizeSelectionRange(
        start: range.lowerBound,
        end: range.upperBound,
        textLenUtf16: textLenUtf16
    )
}

/// Sanitizes raw UTF-16 marked-text `(start, end)` offsets against `textLenUtf16`:
/// drops reversed (`start > end`) or stale (`end > textLenUtf16`) marked ranges by returning `nil`,
/// matching upstream `sanitize_marked_range`.
func sanitizeMarkedRange(start: Int, end: Int, textLenUtf16: Int) -> Range<Int>? {
    let clampedLen = max(0, textLenUtf16)
    if start < 0 || end < 0 || start > end || end > clampedLen {
        return nil
    }
    return start..<end
}

/// Overload accepting a Swift `Range<Int>` directly.
func sanitizeMarkedRange(_ range: Range<Int>, _ textLenUtf16: Int) -> Range<Int>? {
    sanitizeMarkedRange(
        start: range.lowerBound,
        end: range.upperBound,
        textLenUtf16: textLenUtf16
    )
}

/// Sanitizes both selection and marked UTF-16 ranges against `text`, clamping stale selections
/// and dropping stale marked ranges, matching upstream `sanitize_text_state`.
func sanitizeTextState(
    _ text: String,
    _ selectionUtf16: Range<Int>?,
    _ markedRangeUtf16: Range<Int>?
) -> (Range<Int>?, Range<Int>?) {
    let len = utf16Len(text)
    return (
        selectionUtf16.flatMap { sanitizeSelectionRange($0, len) },
        markedRangeUtf16.flatMap { sanitizeMarkedRange($0, len) }
    )
}

/// Converts a document-level `selection` UTF-16 range into a range relative to `markedRange`,
/// clamped to `0..<(markedRange.count)`, matching upstream `clamp_relative_selection`.
func clampRelativeSelection(_ selection: Range<Int>, _ markedRange: Range<Int>) -> Range<Int> {
    let markedLen = max(0, markedRange.upperBound - markedRange.lowerBound)
    let relStart = min(max(0, selection.lowerBound - markedRange.lowerBound), markedLen)
    let relEnd = min(max(relStart, selection.upperBound - markedRange.lowerBound), markedLen)
    return relStart..<relEnd
}

/// Computes the minimal character-aligned diff between `old` and `new` in UTF-16 coordinates
/// without splitting surrogate pairs, matching upstream `text_diff`.
func textDiff(_ old: String, _ new: String) -> TextDiff {
    let oldChars = Array(old)
    let newChars = Array(new)

    var prefixChars = 0
    var prefixUtf16 = 0
    let minCount = min(oldChars.count, newChars.count)

    while prefixChars < minCount && oldChars[prefixChars] == newChars[prefixChars] {
        prefixUtf16 += oldChars[prefixChars].utf16.count
        prefixChars += 1
    }

    var suffixChars = 0
    var suffixUtf16 = 0
    while (prefixChars + suffixChars) < oldChars.count
        && (prefixChars + suffixChars) < newChars.count
        && oldChars[oldChars.count - 1 - suffixChars] == newChars[newChars.count - 1 - suffixChars]
    {
        suffixUtf16 += oldChars[oldChars.count - 1 - suffixChars].utf16.count
        suffixChars += 1
    }

    let oldTotalUtf16 = utf16Len(old)
    let oldEndUtf16 = max(prefixUtf16, oldTotalUtf16 - suffixUtf16)
    let newSliceEnd = max(prefixChars, newChars.count - suffixChars)
    let replacement = String(newChars[prefixChars..<newSliceEnd])

    return TextDiff(
        oldRangeUtf16: prefixUtf16..<oldEndUtf16,
        newText: replacement
    )
}

#if os(iOS) || os(visionOS)

// MARK: - UIKit Text Input Delegate

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIiOSTextInputDelegate")` with a native
// Swift `NSObject` conforming to `UITextFieldDelegate` and `UITextViewDelegate` (ADR-0011).

@MainActor
final class GPUIiOSTextInputDelegate: NSObject, UITextFieldDelegate, UITextViewDelegate {
    weak var session: IosTextInputSession?

    init(session: IosTextInputSession? = nil) {
        self.session = session
        super.init()
    }

    // MARK: UITextFieldDelegate

    func textFieldDidBeginEditing(_ textField: UITextField) {
        _ = textField
        session?.receiveUiKitEvent(.focused)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        _ = textField
        session?.flushTextState()
        session?.receiveUiKitEvent(.blurred)
    }

    func textFieldDidChangeSelection(_ textField: UITextField) {
        _ = textField
        session?.receiveUiKitEvent(.selectionChanged)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        _ = textField
        session?.handleReturnKey()
        return false
    }

    // MARK: UITextViewDelegate

    func textViewDidBeginEditing(_ textView: UITextView) {
        _ = textView
        session?.receiveUiKitEvent(.focused)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        _ = textView
        session?.flushTextState()
        session?.receiveUiKitEvent(.blurred)
    }

    func textViewDidChange(_ textView: UITextView) {
        _ = textView
        guard let session else { return }
        if !session.allowTextChange {
            return
        }
        session.allowTextChange = true
        session.receiveUiKitEvent(.textChanged)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        _ = textView
        session?.receiveUiKitEvent(.selectionChanged)
    }

    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        _ = textView
        _ = range
        guard let session else { return true }
        if text == "\n" && session.lastConfig.submitBehavior != .insertNewline {
            session.handleReturnKey()
            return false
        }
        session.allowTextChange = true
        return true
    }
}

// MARK: - Bidirectional iOS Text Input Session

/// Coordinates GPUI's `PlatformInputHandlerProtocol` / `InputHandler` with a hidden UIKit
/// `GPUIBackedTextField` or `UITextView` so software keyboard, dictation, Scribble, emoji,
/// and CJK IME composition synchronize cleanly per frame.
@MainActor
public final class IosTextInputSession {
    private var inputHandler: (any PlatformInputHandlerProtocol)?
    private var hadHandlerThisFrame: Bool = false
    let backedInput = IosBackedTextInput()
    lazy var delegate = GPUIiOSTextInputDelegate(session: self)
    private var suppressDelegateEvents: Bool = false
    var allowTextChange: Bool = true
    var lastConfig: TextInputConfig = TextInputConfig()
    private var shadowText: String = ""
    private var shadowSelection: UTF16Selection? = UTF16Selection(range: 0..<0, reversed: false)
    private var shadowMarkedRange: Range<Int>?
    private var imeBounds: Bounds<Pixels> = defaultBounds()
    private weak var hostView: UIView?
    private weak var windowState: IosWindowState?

    /// Optional observer callbacks invoked alongside `PlatformInputHandlerProtocol` dispatch.
    var onCommitTextChange: ((_ diff: TextDiff, _ markedRange: Range<Int>?, _ selectedRange: Range<Int>?) -> Void)?
    var onEmptyBackspace: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onSelectionChange: ((_ selection: UTF16Selection?) -> Void)?

    public init() {}

    /// Creates a new `IosTextInputSession` matching upstream `IosTextInputSession::new()`.
    public static func new() -> IosTextInputSession {
        IosTextInputSession()
    }

    /// Attaches the host `GPUIView` inside which backing UIKit text controls are mounted.
    func attachHostView(_ view: UIView, windowState: IosWindowState? = nil) {
        self.hostView = view
        if let windowState {
            self.windowState = windowState
        }
    }

    /// Installs the active GPUI `PlatformInputHandlerProtocol` for the current frame, synchronizes
    /// authoritative GPUI state into the backing UIKit control, and focuses it when appropriate.
    public func setInputHandler(_ handler: any PlatformInputHandlerProtocol) {
        self.hadHandlerThisFrame = true
        self.inputHandler = handler
        syncFromGpui()
        if hostView != nil && handler.queryAcceptsTextInput() && !backedInput.isFocused {
            suppressDelegateEvents = true
            let policy: IosTextInputSoftKeyboardPolicy = (lastConfig.softKeyboard == .hidden) ? .hidden : .automatic
            backedInput.focus(softKeyboardPolicy: policy)
            suppressDelegateEvents = false
        }
    }

    /// Removes and returns the currently installed `PlatformInputHandlerProtocol`, if any.
    public func takeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        hadHandlerThisFrame = false
        let current = inputHandler
        inputHandler = nil
        return current
    }

    /// Returns the currently installed `PlatformInputHandlerProtocol` without removing it.
    public func activeInputHandler() -> (any PlatformInputHandlerProtocol)? {
        inputHandler
    }

    /// Returns `true` when an input handler is currently active.
    public func hasActiveHandler() -> Bool {
        inputHandler != nil
    }

    /// Updates the logical bounds of the hidden UIKit input control (used by iOS to position
    /// autocorrect bubbles, dictation popovers, and software keyboard scroll avoidance).
    public func updateImePosition(_ bounds: Bounds<Pixels>) {
        self.imeBounds = bounds
        suppressDelegateEvents = true
        backedInput.updateBounds(bounds)
        suppressDelegateEvents = false
    }

    /// Called at the end of every GPUI paint pass: if no focused element registered an input
    /// handler during the frame, resigns first responder to dismiss the software keyboard.
    public func completedFrame() {
        if hadHandlerThisFrame {
            hadHandlerThisFrame = false
            allowTextChange = true
            return
        }
        if inputHandler == nil {
            if backedInput.isFocused {
                suppressDelegateEvents = true
                backedInput.blur()
                suppressDelegateEvents = false
            }
            _ = hostView?.becomeFirstResponder()
            shadowText = ""
            shadowSelection = nil
            shadowMarkedRange = nil
        }
    }

    /// Synchronizes authoritative GPUI document text, selection, marked range, and config from
    /// `PlatformInputHandlerProtocol` into the backing UIKit control, matching upstream `sync_from_gpui()`.
    public func syncFromGpui() {
        guard let handler = inputHandler else { return }

        if !handler.queryAcceptsTextInput() {
            suppressDelegateEvents = true
            backedInput.blur()
            suppressDelegateEvents = false
            return
        }

        let config = handler.textInputConfig()
        let rawSelection = handler.selectedTextRange(ignoreDisabledInput: false)
        let rawMarked = handler.markedTextRange()
        var adjusted: Range<Int>? = nil
        let docText = handler.textForRange(
            rangeUtf16: 0..<(Int.max / 2),
            adjustedRange: &adjusted
        ) ?? ""

        let (sanitizedSelectionRange, sanitizedMarked) = sanitizeTextState(
            docText,
            rawSelection?.range,
            rawMarked
        )
        let sanitizedSelection = sanitizedSelectionRange.map { selectionFromRange($0, rawSelection) }

        let caretRange: Range<Int>
        if let sel = sanitizedSelection {
            caretRange = sel.reversed
                ? sel.range.lowerBound..<sel.range.lowerBound
                : sel.range.upperBound..<sel.range.upperBound
        } else {
            caretRange = 0..<0
        }
        let bounds = handler.boundsForRange(rangeUtf16: caretRange) ?? defaultBounds()
        self.imeBounds = bounds
        self.lastConfig = config

        suppressDelegateEvents = true
        defer { suppressDelegateEvents = false }

        if let hostView {
            _ = backedInput.ensureControl(
                in: hostView,
                config: config,
                delegate: delegate,
                onEditingChanged: { [weak self] in
                    self?.receiveUiKitEvent(.textChanged)
                },
                onEmptyBackspace: { [weak self] in
                    self?.receiveEmptyBackspace()
                }
            )
            backedInput.updateBounds(bounds)

            if sanitizedMarked == nil && backedInput.markedRangeUtf16() != nil {
                backedInput.unmarkText()
            }
            if backedInput.text() != docText {
                backedInput.setText(docText)
            }
            if sanitizedMarked == nil, let sel = sanitizedSelection {
                if backedInput.selectedRangeUtf16() != sel.range {
                    backedInput.setSelectedRangeUtf16(sel.range)
                }
            }
        }

        shadowText = docText
        if let sel = sanitizedSelection {
            shadowSelection = sel
        }
        shadowMarkedRange = sanitizedMarked
    }

    /// Overload preserving source compatibility with callers passing `Window` & `App`.
    public func syncFromGpui(window: inout Window, cx: inout App) {
        _ = window
        _ = cx
        syncFromGpui()
    }

    // MARK: - UIKit Event Ingestion

    func receiveEmptyBackspace() {
        guard !suppressDelegateEvents else { return }
        if let handler = withTakenInputHandler({ h in h.deleteBackward(); return true }), handler {
            // Dispatched to InputHandler.deleteBackward
        } else {
            _ = windowState?.inputCallback?(
                .keyDown(KeyDownEvent(keystroke: Keystroke(key: "backspace"), isHeld: false))
            )
        }
        onEmptyBackspace?()
    }

    func handleReturnKey() {
        guard !suppressDelegateEvents else { return }
        switch lastConfig.submitBehavior {
        case .insertNewline:
            if lastConfig.multiline {
                _ = withTakenInputHandler { handler in
                    handler.replaceTextInRange(rangeUtf16: nil, text: "\n")
                }
            }
        case .submit:
            _ = withTakenInputHandler { handler in
                handler.submitTextInput()
            }
            receiveUiKitEvent(.submit)
        case .submitAndBlur:
            _ = withTakenInputHandler { handler in
                handler.submitTextInput()
            }
            receiveUiKitEvent(.submit)
            suppressDelegateEvents = true
            backedInput.blur()
            suppressDelegateEvents = false
        }
    }

    func flushTextState() {
        guard !suppressDelegateEvents else { return }
        let currentText = backedInput.text()
        let (selectionUtf16, markedUtf16) = sanitizeTextState(
            currentText,
            backedInput.selectedRangeUtf16(),
            backedInput.markedRangeUtf16()
        )
        if currentText != shadowText
            || selectionUtf16 != shadowSelection?.range
            || markedUtf16 != shadowMarkedRange
        {
            propagateTextChange(
                newText: currentText,
                selectionUtf16: selectionUtf16,
                markedRangeUtf16: markedUtf16
            )
        }
    }

    private func withTakenInputHandler<R>(
        _ body: (inout any PlatformInputHandlerProtocol) -> R
    ) -> R? {
        guard var handler = inputHandler else { return nil }
        inputHandler = nil
        let result = body(&handler)
        if inputHandler == nil {
            inputHandler = handler
        }
        return result
    }

    private func propagateTextChange(
        newText: String,
        selectionUtf16: Range<Int>?,
        markedRangeUtf16: Range<Int>?
    ) {
        let diff: TextDiff
        if let prevMarked = shadowMarkedRange, markedRangeUtf16 != nil {
            let newMarkedText: String
            if let currentMarked = markedRangeUtf16,
               let strRange = IMEBridge.utf16RangeToStringRange(currentMarked, in: newText)
            {
                newMarkedText = String(newText[strRange])
            } else {
                newMarkedText = textDiff(shadowText, newText).newText
            }
            diff = TextDiff(oldRangeUtf16: prevMarked, newText: newMarkedText)
        } else {
            diff = textDiff(shadowText, newText)
        }

        let relativeSelected: Range<Int>?
        if let marked = markedRangeUtf16, let sel = selectionUtf16 {
            relativeSelected = clampRelativeSelection(sel, marked)
        } else {
            relativeSelected = nil
        }

        let propagatedSelection = selectionUtf16.map { selectionFromRange($0, shadowSelection) }
        let hadPreviousMarked = (shadowMarkedRange != nil)

        shadowText = newText
        shadowSelection = propagatedSelection
        shadowMarkedRange = markedRangeUtf16

        _ = withTakenInputHandler { handler in
            if markedRangeUtf16 != nil {
                handler.replaceAndMarkTextInRange(
                    rangeUtf16: diff.oldRangeUtf16,
                    newText: diff.newText,
                    newSelectedRange: relativeSelected
                )
            } else {
                handler.replaceTextInRange(
                    rangeUtf16: diff.oldRangeUtf16,
                    text: diff.newText
                )
                if hadPreviousMarked {
                    handler.unmarkText()
                }
            }
            handler.setSelectedTextRange(selection: propagatedSelection)
        }

        onCommitTextChange?(diff, markedRangeUtf16, relativeSelected ?? selectionUtf16)
    }

    func receiveUiKitEvent(_ event: IosTextInputEvent) {
        guard !suppressDelegateEvents else { return }

        switch event {
        case .focused:
            break

        case .blurred:
            shadowMarkedRange = nil

        case .submit:
            onSubmit?()

        case .textChanged:
            let newText = backedInput.text()
            let (sanitizedSelection, sanitizedMarked) = sanitizeTextState(
                newText,
                backedInput.selectedRangeUtf16(),
                backedInput.markedRangeUtf16()
            )
            propagateTextChange(
                newText: newText,
                selectionUtf16: sanitizedSelection,
                markedRangeUtf16: sanitizedMarked
            )

        case .selectionChanged:
            let currentText = backedInput.text()
            let (sanitizedSelection, sanitizedMarked) = sanitizeTextState(
                currentText,
                backedInput.selectedRangeUtf16(),
                backedInput.markedRangeUtf16()
            )
            shadowMarkedRange = sanitizedMarked
            let updated = sanitizedSelection.map { selectionFromRange($0, shadowSelection) }
            if updated != shadowSelection {
                shadowSelection = updated
                _ = withTakenInputHandler { handler in
                    handler.setSelectedTextRange(selection: updated)
                }
                onSelectionChange?(updated)
            }
        }
    }

    func tearDown() {
        suppressDelegateEvents = true
        backedInput.tearDown()
        suppressDelegateEvents = false
        inputHandler = nil
    }
}
#endif
