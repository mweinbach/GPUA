// Ported from: crates/gpui_ios/src/text_input/backed_view.rs
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(iOS) || os(visionOS)
import CoreGraphics
import Foundation
import GPUI
import UIKit

// MARK: - Custom UITextField Subclass Intercepting Empty Backspace

// PORT NOTE: Replaces upstream ObjC runtime `ClassDecl("GPUIBackedTextField")` with a native
// Swift `UITextField` subclass overriding `deleteBackward()` (ADR-0011).

/// Single-line backing `UITextField` that notifies `IosTextInputSession` when backspace is
/// pressed while the text buffer is empty (which `UITextField.editingChanged` otherwise suppresses).
@MainActor
final class GPUIBackedTextField: UITextField {
    var onEmptyBackspace: (() -> Void)?
    var onEditingChanged: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    private func configureAppearance() {
        borderStyle = .none
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        clipsToBounds = true
        alpha = 0.01
        addTarget(self, action: #selector(handleEditingChanged), for: .editingChanged)
    }

    @objc private func handleEditingChanged() {
        onEditingChanged?()
    }

    override func deleteBackward() {
        let wasEmpty = (text ?? "").isEmpty && markedTextRange == nil
        super.deleteBackward()
        if wasEmpty {
            onEmptyBackspace?()
        }
    }
}

// MARK: - Backing Control Wrapper

@MainActor
enum BackedTextInputControl {
    case textField(GPUIBackedTextField)
    case textView(UITextView)

    var view: UIView {
        switch self {
        case .textField(let field):
            return field
        case .textView(let tv):
            return tv
        }
    }

    var textInput: any UITextInput {
        switch self {
        case .textField(let field):
            return field
        case .textView(let tv):
            return tv
        }
    }

    var usesTextView: Bool {
        if case .textView = self {
            return true
        }
        return false
    }
}

/// Manages a hidden UIKit `GPUIBackedTextField` or `UITextView` mounted inside `GPUIView` so
/// iOS IME composition, dictation, Scribble, autofill, and selection handles integrate natively
/// with GPUI's `InputHandler`.
@MainActor
final class IosBackedTextInput {
    private(set) var control: BackedTextInputControl?
    private lazy var suppressedInputView = UIView(frame: .zero)

    init() {}

    /// Ensures a backing control matching `config` (`GPUIBackedTextField` for single-line / secure
    /// entry, `UITextView` for multiline) is mounted inside `parentView`.
    func ensureControl(
        in parentView: UIView,
        config: TextInputConfig,
        delegate: GPUIiOSTextInputDelegate,
        onEditingChanged: @escaping () -> Void,
        onEmptyBackspace: @escaping () -> Void
    ) -> BackedTextInputControl {
        let wantsTextView = shouldUseTextView(config)

        if let existing = control, existing.usesTextView == wantsTextView {
            if existing.view.superview !== parentView {
                parentView.addSubview(existing.view)
            }
            applyTextInputTraits(existing.view, config)
            return existing
        }

        tearDown()

        let created: BackedTextInputControl
        if wantsTextView {
            let tv = UITextView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            tv.backgroundColor = .clear
            tv.textColor = .clear
            tv.tintColor = .clear
            tv.isScrollEnabled = false
            tv.textContainerInset = .zero
            tv.textContainer.lineFragmentPadding = 0
            tv.clipsToBounds = true
            tv.alpha = 0.01
            tv.delegate = delegate
            parentView.addSubview(tv)
            created = .textView(tv)
        } else {
            let tf = GPUIBackedTextField(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            tf.delegate = delegate
            tf.onEditingChanged = onEditingChanged
            tf.onEmptyBackspace = onEmptyBackspace
            parentView.addSubview(tf)
            created = .textField(tf)
        }

        applyTextInputTraits(created.view, config)
        self.control = created
        return created
    }

    var isFocused: Bool {
        control?.view.isFirstResponder ?? false
    }

    func focus(softKeyboardPolicy: IosTextInputSoftKeyboardPolicy = .automatic) {
        guard let control else { return }
        switch control {
        case .textField(let tf):
            tf.inputView = (softKeyboardPolicy == .hidden) ? suppressedInputView : nil
            tf.reloadInputViews()
            if !tf.isFirstResponder {
                _ = tf.becomeFirstResponder()
            }
        case .textView(let tv):
            tv.inputView = (softKeyboardPolicy == .hidden) ? suppressedInputView : nil
            tv.reloadInputViews()
            if !tv.isFirstResponder {
                _ = tv.becomeFirstResponder()
            }
        }
    }

    func blur() {
        guard let control else { return }
        if control.view.isFirstResponder {
            _ = control.view.resignFirstResponder()
        }
    }

    func text() -> String {
        guard let control else { return "" }
        switch control {
        case .textField(let tf):
            return tf.text ?? ""
        case .textView(let tv):
            return tv.text ?? ""
        }
    }

    func setText(_ newText: String) {
        guard let control else { return }
        switch control {
        case .textField(let tf):
            if tf.text != newText {
                tf.text = newText
            }
        case .textView(let tv):
            if tv.text != newText {
                tv.text = newText
            }
        }
    }

    func selectedRangeUtf16() -> Range<Int>? {
        guard let ti = control?.textInput,
              let range = ti.selectedTextRange else {
            return nil
        }
        let beginning = ti.beginningOfDocument
        let start = max(0, ti.offset(from: beginning, to: range.start))
        let end = max(start, ti.offset(from: beginning, to: range.end))
        return start..<end
    }

    func setSelectedRangeUtf16(_ range: Range<Int>) {
        guard let ti = control?.textInput else { return }
        let beginning = ti.beginningOfDocument
        guard let startPos = ti.position(from: beginning, offset: range.lowerBound),
              let endPos = ti.position(from: beginning, offset: range.upperBound),
              let textRange = ti.textRange(from: startPos, to: endPos) else {
            return
        }
        ti.selectedTextRange = textRange
    }

    func markedRangeUtf16() -> Range<Int>? {
        guard let ti = control?.textInput,
              let range = ti.markedTextRange else {
            return nil
        }
        let beginning = ti.beginningOfDocument
        let start = max(0, ti.offset(from: beginning, to: range.start))
        let end = max(start, ti.offset(from: beginning, to: range.end))
        return start..<end
    }

    func unmarkText() {
        control?.textInput.unmarkText()
    }

    func updateBounds(_ bounds: Bounds<Pixels>) {
        guard let view = control?.view else { return }
        let frame = CGRect(
            x: CGFloat(bounds.origin.x.value),
            y: CGFloat(bounds.origin.y.value),
            width: max(1.0, CGFloat(bounds.size.width.value)),
            height: max(1.0, CGFloat(bounds.size.height.value))
        )
        if view.frame != frame {
            view.frame = frame
        }
    }

    func firstRect(forRangeUtf16 range: Range<Int>, in hostView: UIView) -> Bounds<Pixels>? {
        guard let control else { return nil }
        let ti = control.textInput
        let beginning = ti.beginningOfDocument
        guard let startPos = ti.position(from: beginning, offset: range.lowerBound),
              let endPos = ti.position(from: beginning, offset: range.upperBound),
              let textRange = ti.textRange(from: startPos, to: endPos) else {
            return nil
        }
        let localRect = ti.firstRect(for: textRange)
        if localRect.isNull || localRect.isInfinite {
            return nil
        }
        let converted = control.view.convert(localRect, to: hostView)
        return Bounds(
            origin: Point(x: px(Float(converted.origin.x)), y: px(Float(converted.origin.y))),
            size: Size(width: px(Float(converted.size.width)), height: px(Float(converted.size.height)))
        )
    }

    func caretRect(forOffsetUtf16 offset: Int, in hostView: UIView) -> Bounds<Pixels>? {
        guard let control else { return nil }
        let ti = control.textInput
        let beginning = ti.beginningOfDocument
        guard let pos = ti.position(from: beginning, offset: offset) else {
            return nil
        }
        let localRect = ti.caretRect(for: pos)
        if localRect.isNull || localRect.isInfinite {
            return nil
        }
        let converted = control.view.convert(localRect, to: hostView)
        return Bounds(
            origin: Point(x: px(Float(converted.origin.x)), y: px(Float(converted.origin.y))),
            size: Size(width: px(Float(converted.size.width)), height: px(Float(converted.size.height)))
        )
    }

    func characterIndex(forPoint point: Point<Pixels>, in hostView: UIView) -> Int? {
        guard let control else { return nil }
        let ti = control.textInput
        let hostPoint = CGPoint(x: CGFloat(point.x.value), y: CGFloat(point.y.value))
        let localPoint = hostView.convert(hostPoint, to: control.view)
        guard let closest = ti.closestPosition(to: localPoint) else {
            return nil
        }
        let offset = ti.offset(from: ti.beginningOfDocument, to: closest)
        return offset >= 0 ? offset : nil
    }

    func tearDown() {
        guard let existing = control else { return }
        if existing.view.isFirstResponder {
            _ = existing.view.resignFirstResponder()
        }
        existing.view.removeFromSuperview()
        self.control = nil
    }
}
#endif
