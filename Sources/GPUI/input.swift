// Ported from: crates/gpui/src/input.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

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

/// Configuration for a platform-backed text input control.
public struct TextInputConfig: Sendable, Equatable {
    public var multiline: Bool
    public var secureEntry: Bool

    public init(multiline: Bool = false, secureEntry: Bool = false) {
        self.multiline = multiline
        self.secureEntry = secureEntry
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

