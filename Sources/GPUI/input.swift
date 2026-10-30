// Ported from: crates/gpui/src/input.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
#if canImport(Dispatch)
import Dispatch
#endif

// MARK: - UTF-16 Selection & Text Input Configuration

/// A struct representing a selection in a text buffer, in UTF-16 code units.
/// The head may be before the tail if reversed is true.
public struct UTF16Selection: Sendable, Equatable {
    /// The range of text in the document this selection corresponds to in UTF-16 code units.
    public var range: Range<Int>
    /// Whether the head of this selection is at the start (true) or end (false) of the range.
    public var reversed: Bool

    public init(range: Range<Int>, reversed: Bool = false) {
        self.range = range
        self.reversed = reversed
    }
}

/// Return key behavior for platform-backed text input controls.
public enum TextInputSubmitBehavior: Sendable, Equatable {
    /// Insert a newline into the document.
    case insertNewline
    /// Notify the input handler that the field was submitted.
    case submit
    /// Notify the input handler, then blur the control.
    case submitAndBlur
}

/// Controls whether the platform should present the software keyboard.
public enum TextInputSoftKeyboardPolicy: Sendable, Equatable {
    case automatic
    case hidden
}

/// Configuration for a platform-backed text input control.
public struct TextInputConfig: Sendable, Equatable {
    public var multiline: Bool
    public var secureEntry: Bool
    public var submitBehavior: TextInputSubmitBehavior
    public var enablesReturnKeyAutomatically: Bool
    public var softKeyboard: TextInputSoftKeyboardPolicy

    public init(
        multiline: Bool = false,
        secureEntry: Bool = false,
        submitBehavior: TextInputSubmitBehavior = .submit,
        enablesReturnKeyAutomatically: Bool = false,
        softKeyboard: TextInputSoftKeyboardPolicy = .automatic
    ) {
        self.multiline = multiline
        self.secureEntry = secureEntry
        self.submitBehavior = submitBehavior
        self.enablesReturnKeyAutomatically = enablesReturnKeyAutomatically
        self.softKeyboard = softKeyboard
    }
}

// MARK: - UTF-16 ↔ UTF-8 IME Conversion Helpers

/// Utilities to convert between 0-based UTF-16 offsets and Swift String indices / UTF-8 offsets.
public enum IMEBridge {
    /// Convert a UTF-16 range into a Swift String range.
    public static func utf16RangeToStringRange(_ range: Range<Int>, in text: String) -> Range<String.Index>? {
        let utf16 = text.utf16
        guard range.lowerBound >= 0,
              range.upperBound <= utf16.count,
              range.lowerBound <= range.upperBound else {
            return nil
        }
        guard let start16 = utf16.index(utf16.startIndex, offsetBy: range.lowerBound, limitedBy: utf16.endIndex),
              let end16 = utf16.index(utf16.startIndex, offsetBy: range.upperBound, limitedBy: utf16.endIndex),
              let start = String.Index(start16, within: text),
              let end = String.Index(end16, within: text) else {
            return nil
        }
        return start..<end
    }

    /// Convert a Swift String range to a 0-based UTF-16 range.
    public static func stringRangeToUtf16Range(_ range: Range<String.Index>, in text: String) -> Range<Int> {
        let utf16 = text.utf16
        let start16 = range.lowerBound.samePosition(in: utf16) ?? utf16.startIndex
        let end16 = range.upperBound.samePosition(in: utf16) ?? utf16.endIndex
        let lower = utf16.distance(from: utf16.startIndex, to: start16)
        let upper = utf16.distance(from: utf16.startIndex, to: end16)
        return lower..<upper
    }
}

// MARK: - InputHandler Protocol

/// Core input handling interface matching upstream GPUI `InputHandler`.
@MainActor
public protocol InputHandler: AnyObject {
    func selectedTextRange(ignoreDisabledInput: Bool, window: inout Window, cx: inout App) -> UTF16Selection?
    func markedTextRange(window: inout Window, cx: inout App) -> Range<Int>?
    func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?, window: inout Window, cx: inout App) -> String?
    func replaceTextInRange(rangeUtf16: Range<Int>?, text: String, window: inout Window, cx: inout App)
    func deleteBackward(window: inout Window, cx: inout App)
    func replaceAndMarkTextInRange(rangeUtf16: Range<Int>?, newText: String, newSelectedRange: Range<Int>?, window: inout Window, cx: inout App)
    func unmarkText(window: inout Window, cx: inout App)
    func setSelectedTextRange(selection: UTF16Selection?, window: inout Window, cx: inout App)
    func boundsForRange(rangeUtf16: Range<Int>, window: inout Window, cx: inout App) -> Bounds<Pixels>?
    func characterIndexForPoint(point: Point<Pixels>, window: inout Window, cx: inout App) -> Int?
    func acceptsTextInput(window: inout Window, cx: inout App) -> Bool
    func prefersImeForPrintableKeys(window: inout Window, cx: inout App) -> Bool
    nonisolated func applePressAndHoldEnabled() -> Bool
    func textInputConfig(window: inout Window, cx: inout App) -> TextInputConfig
    func submitTextInput(window: inout Window, cx: inout App)
}

extension InputHandler {
    public func deleteBackward(window: inout Window, cx: inout App) {
        replaceTextInRange(rangeUtf16: nil, text: "", window: &window, cx: &cx)
    }

    public func acceptsTextInput(window: inout Window, cx: inout App) -> Bool {
        true
    }

    public func prefersImeForPrintableKeys(window: inout Window, cx: inout App) -> Bool {
        acceptsTextInput(window: &window, cx: &cx)
    }

    nonisolated public func applePressAndHoldEnabled() -> Bool {
        true
    }

    public func textInputConfig(window: inout Window, cx: inout App) -> TextInputConfig {
        TextInputConfig()
    }

    public func submitTextInput(window: inout Window, cx: inout App) {}
}

// MARK: - EntityInputHandler Protocol

/// Implement this protocol to allow views to handle textual input when implementing an editor, field, etc.
@MainActor
public protocol EntityInputHandler: AnyObject {
    func textForRange(
        _ range: Range<Int>,
        adjustedRange: inout Range<Int>?,
        window: inout Window,
        cx: inout Context<Self>
    ) -> String?

    func selectedTextRange(
        ignoreDisabledInput: Bool,
        window: inout Window,
        cx: inout Context<Self>
    ) -> UTF16Selection?

    func markedTextRange(
        window: inout Window,
        cx: inout Context<Self>
    ) -> Range<Int>?

    func unmarkText(window: inout Window, cx: inout Context<Self>)

    func setSelectedTextRange(
        _ selection: UTF16Selection?,
        window: inout Window,
        cx: inout Context<Self>
    )

    func replaceTextInRange(
        _ range: Range<Int>?,
        text: String,
        window: inout Window,
        cx: inout Context<Self>
    )

    func deleteBackward(window: inout Window, cx: inout Context<Self>)

    func replaceAndMarkTextInRange(
        _ range: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?,
        window: inout Window,
        cx: inout Context<Self>
    )

    func boundsForRange(
        _ rangeUtf16: Range<Int>,
        elementBounds: Bounds<Pixels>,
        window: inout Window,
        cx: inout Context<Self>
    ) -> Bounds<Pixels>?

    func characterIndexForPoint(
        _ point: Point<Pixels>,
        window: inout Window,
        cx: inout Context<Self>
    ) -> Int?

    func acceptsTextInput(window: inout Window, cx: inout Context<Self>) -> Bool
    func textInputConfig(window: inout Window, cx: inout Context<Self>) -> TextInputConfig
    func submitTextInput(window: inout Window, cx: inout Context<Self>)
}

extension EntityInputHandler {
    public func setSelectedTextRange(_ selection: UTF16Selection?, window: inout Window, cx: inout Context<Self>) {}

    public func deleteBackward(window: inout Window, cx: inout Context<Self>) {
        replaceTextInRange(nil, text: "", window: &window, cx: &cx)
    }

    public func acceptsTextInput(window: inout Window, cx: inout Context<Self>) -> Bool {
        true
    }

    public func textInputConfig(window: inout Window, cx: inout Context<Self>) -> TextInputConfig {
        TextInputConfig()
    }

    public func submitTextInput(window: inout Window, cx: inout Context<Self>) {}
}

// MARK: - ElementInputHandler

/// The canonical implementation of [`PlatformInputHandlerProtocol`] / [`InputHandler`].
/// Call [`Window::handle_input`] with an instance during your element's paint.
// PORT NOTE: ElementInputHandler mediates main-actor Entity/Window state access during IME events.
@MainActor
public final class ElementInputHandler<V: EntityInputHandler>: InputHandler, @unchecked Sendable {
    public let view: Entity<V>
    public let elementBounds: Bounds<Pixels>

    public init(elementBounds: Bounds<Pixels>, view: Entity<V>) {
        self.elementBounds = elementBounds
        self.view = view
    }

    public static func new(elementBounds: Bounds<Pixels>, view: Entity<V>) -> ElementInputHandler<V> {
        ElementInputHandler(elementBounds: elementBounds, view: view)
    }

    // MARK: - InputHandler conformance

    public func selectedTextRange(
        ignoreDisabledInput: Bool,
        window: inout Window,
        cx: inout App
    ) -> UTF16Selection? {
        var win = window
        let result = view.update(&cx) { v, c in
            v.selectedTextRange(ignoreDisabledInput: ignoreDisabledInput, window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func markedTextRange(window: inout Window, cx: inout App) -> Range<Int>? {
        var win = window
        let result = view.update(&cx) { v, c in
            v.markedTextRange(window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func textForRange(
        rangeUtf16: Range<Int>,
        adjustedRange: inout Range<Int>?,
        window: inout Window,
        cx: inout App
    ) -> String? {
        var win = window
        var adj = adjustedRange
        let result = view.update(&cx) { v, c in
            v.textForRange(rangeUtf16, adjustedRange: &adj, window: &win, cx: &c)
        }
        window = win
        adjustedRange = adj
        return result
    }

    public func replaceTextInRange(
        rangeUtf16: Range<Int>?,
        text: String,
        window: inout Window,
        cx: inout App
    ) {
        var win = window
        view.update(&cx) { v, c in
            v.replaceTextInRange(rangeUtf16, text: text, window: &win, cx: &c)
        }
        window = win
    }

    public func deleteBackward(window: inout Window, cx: inout App) {
        var win = window
        view.update(&cx) { v, c in
            v.deleteBackward(window: &win, cx: &c)
        }
        window = win
    }

    public func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?,
        window: inout Window,
        cx: inout App
    ) {
        var win = window
        view.update(&cx) { v, c in
            v.replaceAndMarkTextInRange(rangeUtf16, newText: newText, newSelectedRange: newSelectedRange, window: &win, cx: &c)
        }
        window = win
    }

    public func unmarkText(window: inout Window, cx: inout App) {
        var win = window
        view.update(&cx) { v, c in
            v.unmarkText(window: &win, cx: &c)
        }
        window = win
    }

    public func setSelectedTextRange(
        selection: UTF16Selection?,
        window: inout Window,
        cx: inout App
    ) {
        var win = window
        view.update(&cx) { v, c in
            v.setSelectedTextRange(selection, window: &win, cx: &c)
        }
        window = win
    }

    public func boundsForRange(
        rangeUtf16: Range<Int>,
        window: inout Window,
        cx: inout App
    ) -> Bounds<Pixels>? {
        var win = window
        let bounds = self.elementBounds
        let result = view.update(&cx) { v, c in
            v.boundsForRange(rangeUtf16, elementBounds: bounds, window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func characterIndexForPoint(
        point: Point<Pixels>,
        window: inout Window,
        cx: inout App
    ) -> Int? {
        var win = window
        let result = view.update(&cx) { v, c in
            v.characterIndexForPoint(point, window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func acceptsTextInput(window: inout Window, cx: inout App) -> Bool {
        var win = window
        let result = view.update(&cx) { v, c in
            v.acceptsTextInput(window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func prefersImeForPrintableKeys(window: inout Window, cx: inout App) -> Bool {
        acceptsTextInput(window: &window, cx: &cx)
    }

    public func textInputConfig(window: inout Window, cx: inout App) -> TextInputConfig {
        var win = window
        let result = view.update(&cx) { v, c in
            v.textInputConfig(window: &win, cx: &c)
        }
        window = win
        return result
    }

    public func submitTextInput(window: inout Window, cx: inout App) {
        var win = window
        view.update(&cx) { v, c in
            v.submitTextInput(window: &win, cx: &c)
        }
        window = win
    }

    nonisolated public func applePressAndHoldEnabled() -> Bool {
        true
    }
}

// MARK: - PlatformInputHandlerProtocol Conformance

extension ElementInputHandler: @preconcurrency PlatformInputHandlerProtocol {
    public func acceptsTextInput(window: Window, cx: App) -> Bool {
        true
    }

    public func dispatchInput(_ text: String, _ window: inout Window, _ cx: inout App) {
        replaceTextInRange(rangeUtf16: nil, text: text, window: &window, cx: &cx)
    }
}

// MARK: - PlatformInputHandler

private struct TextRangeResult: Sendable {
    let text: String?
    let adjustedRange: Range<Int>?
}

#if canImport(Dispatch) && !os(WASI)
// PORT NOTE: DispatchSpecificKey is an immutable opaque pointer key for libdispatch queue-specific storage; wrapping it makes static storage Sendable across Apple and swift-corelibs-libdispatch SDKs.
private final class MainQueueKeyBox: @unchecked Sendable {
    let key = DispatchSpecificKey<Bool>()

    init() {
        DispatchQueue.main.setSpecific(key: key, value: true)
    }
}
#endif

/// Context-bound wrapper pairing an `InputHandler` with its owning `App` and `AnyWindowHandle`,
/// matching upstream `gpui::PlatformInputHandler` (`crates/gpui/src/platform.rs`).
// PORT NOTE: PlatformInputHandler hops onto MainActor before touching `app` or `handler`, matching upstream's main-thread `AsyncWindowContext` invariant.
public final class PlatformInputHandler: PlatformInputHandlerProtocol, @unchecked Sendable {
    #if canImport(Dispatch) && !os(WASI)
    private static let mainQueueMarker = MainQueueKeyBox()

    private static func runOnMain<R: Sendable>(_ work: @Sendable () -> R) -> R {
        if Thread.isMainThread || DispatchQueue.getSpecific(key: mainQueueMarker.key) == true {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }
    #endif

    public let windowHandle: AnyWindowHandle
    public weak var app: App?
    public let handler: any InputHandler

    public init(windowHandle: AnyWindowHandle, app: App?, handler: any InputHandler) {
        self.windowHandle = windowHandle
        self.app = app
        self.handler = handler
    }

    private func withWindowAndApp<R: Sendable>(_ body: @MainActor (any InputHandler, inout Window, inout App) -> R) -> R? {
        withoutActuallyEscaping(body) { escapingBody in
            let work: @Sendable () -> R? = {
                MainActor.assumeIsolated {
                    guard let app = self.app else { return nil }
                    return try? app.updateWindow(self.windowHandle) { _, window, cx in
                        var mutableApp = cx
                        return escapingBody(self.handler, &window, &mutableApp)
                    }
                }
            }
            #if canImport(Dispatch) && !os(WASI)
            return Self.runOnMain(work)
            #else
            return work()
            #endif
        }
    }

    public func acceptsTextInput(window: Window, cx: App) -> Bool {
        withWindowAndApp { handler, win, app in
            handler.acceptsTextInput(window: &win, cx: &app)
        } ?? true
    }

    public func queryAcceptsTextInput() -> Bool {
        withWindowAndApp { handler, win, app in
            handler.acceptsTextInput(window: &win, cx: &app)
        } ?? true
    }

    public func textInputConfig() -> TextInputConfig {
        withWindowAndApp { handler, win, app in
            handler.textInputConfig(window: &win, cx: &app)
        } ?? TextInputConfig()
    }

    public func submitTextInput() {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.submitTextInput(window: &win, cx: &app)
            return true
        }
    }

    public func dispatchInput(_ text: String, _ window: inout Window, _ cx: inout App) {
        MainActor.assumeIsolated {
            handler.replaceTextInRange(rangeUtf16: nil, text: text, window: &window, cx: &cx)
        }
    }

    public func selectedTextRange(ignoreDisabledInput: Bool) -> UTF16Selection? {
        withWindowAndApp { handler, win, app in
            handler.selectedTextRange(ignoreDisabledInput: ignoreDisabledInput, window: &win, cx: &app)
        } ?? nil
    }

    public func markedTextRange() -> Range<Int>? {
        withWindowAndApp { handler, win, app in
            handler.markedTextRange(window: &win, cx: &app)
        } ?? nil
    }

    public func queryPrefersImeForPrintableKeys() -> Bool {
        withWindowAndApp { handler, win, app in
            handler.prefersImeForPrintableKeys(window: &win, cx: &app)
        } ?? false
    }

    public func textForRange(rangeUtf16: Range<Int>, adjustedRange: inout Range<Int>?) -> String? {
        let initialAdjusted = adjustedRange
        guard let result = withWindowAndApp({ handler, win, app -> TextRangeResult in
            var localAdjusted = initialAdjusted
            let text = handler.textForRange(rangeUtf16: rangeUtf16, adjustedRange: &localAdjusted, window: &win, cx: &app)
            return TextRangeResult(text: text, adjustedRange: localAdjusted)
        }) else {
            return nil
        }
        adjustedRange = result.adjustedRange
        return result.text
    }

    public func replaceTextInRange(rangeUtf16: Range<Int>?, text: String) {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.replaceTextInRange(rangeUtf16: rangeUtf16, text: text, window: &win, cx: &app)
            return true
        }
    }

    public func deleteBackward() {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.deleteBackward(window: &win, cx: &app)
            return true
        }
    }

    public func replaceAndMarkTextInRange(
        rangeUtf16: Range<Int>?,
        newText: String,
        newSelectedRange: Range<Int>?
    ) {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.replaceAndMarkTextInRange(
                rangeUtf16: rangeUtf16,
                newText: newText,
                newSelectedRange: newSelectedRange,
                window: &win,
                cx: &app
            )
            return true
        }
    }

    public func unmarkText() {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.unmarkText(window: &win, cx: &app)
            return true
        }
    }

    public func setSelectedTextRange(selection: UTF16Selection?) {
        _ = withWindowAndApp { handler, win, app -> Bool in
            handler.setSelectedTextRange(selection: selection, window: &win, cx: &app)
            return true
        }
    }

    public func boundsForRange(rangeUtf16: Range<Int>) -> Bounds<Pixels>? {
        withWindowAndApp { handler, win, app in
            handler.boundsForRange(rangeUtf16: rangeUtf16, window: &win, cx: &app)
        } ?? nil
    }

    public func characterIndexForPoint(point: Point<Pixels>) -> Int? {
        withWindowAndApp { handler, win, app in
            handler.characterIndexForPoint(point: point, window: &win, cx: &app)
        } ?? nil
    }

    public func applePressAndHoldEnabled() -> Bool {
        let query: @Sendable () -> Bool = {
            MainActor.assumeIsolated {
                self.handler.applePressAndHoldEnabled()
            }
        }
        #if canImport(Dispatch) && !os(WASI)
        return Self.runOnMain(query)
        #else
        return query()
        #endif
    }
}

