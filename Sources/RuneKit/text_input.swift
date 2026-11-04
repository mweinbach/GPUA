// Ported from: crates/rune-kit/src/text_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! TextInput and Textarea (`@opencode/ui` forms/text-input, forms/textarea), and the older
//! TextField (`components/text-field`).

import Rune

private func kitRichStyle(_ k: Kit) -> RichStyle {
    RichStyle(
        codeFg: nil,
        codeBg: k.c.layer03,
        codeBlockBg: k.c.layer02,
        link: k.c.textAccent,
        quoteBar: k.c.borderStrong,
        marker: k.c.textMuted
    )
}

/// Shared shell painting: sheen over the base, button elevation, hover overlay, focus/invalid
/// outline, disabled dimming.
private func inputShell(
    _ k: Kit,
    _ elIn: El,
    _ sheen: (Float, Float),
    _ state: State,
    _ invalid: Bool,
    _ focused: Bool
) -> El {
    let c = k.c
    let hover = state == .hover && !invalid && !focused
    var e = elIn
        .radius(k.radius.md)
        .fill(hover ? over(c.hover, c.bgBase) : c.bgBase)
        .gradient(k.light(sheen.0), k.light(sheen.1))
        .motion(k.motion.control)
    if state == .disabled {
        return shadows(k, e, k.elevation.buttonNeutral).dim(0.5)
    }
    if invalid {
        e = e.outline(1.0, 0.0, c.danger.fg)
    } else if focused || state == .focus {
        e = e.outline(1.0, 0.0, c.borderFocus)
    } else {
        e = shadows(k, e, k.elevation.buttonNeutral)
        if state == .rest {
            e = e.hover(c.hover)
        }
    }
    return e
}

/// Edit bindings collected for the inner text field.
private struct EditActs {
    var handlers: [(El) -> El] = []
    var visual: [(El) -> El] = []

    mutating func edit<S>(_ access: EditAccess<S>) {
        handlers.append { e in e.onEdit(access) }
    }

    mutating func submit<S>(_ f: @escaping (inout S, inout Tx) -> Void) {
        handlers.append { e in e.onSubmit(f) }
    }

    mutating func key<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) {
        handlers.append { e in e.onInputKey(f) }
    }

    mutating func change<S>(_ f: @escaping (inout S, inout Tx) -> Void) {
        handlers.append { e in e.onInputChange(f) }
    }

    mutating func addVisual(_ f: @escaping (El) -> El) {
        visual.append(f)
    }

    func apply(_ elIn: El, _ disabled: Bool) -> El {
        var e = elIn
        for f in visual {
            e = f(e)
        }
        if !disabled {
            for f in handlers {
                e = f(e)
            }
        }
        return e
    }
}

/// A single-line field: `TextInput.new(s.name).placeholder("Name").onEdit(\S.name)`.
public struct TextInput {
    private var editVal: TextEdit
    private var placeholderVal: String
    private var largeVal: Bool
    private var styleVal: TextStyle?
    private var heightVal: Float?
    private var widthVal: Float?
    private var leadingVal: Icon?
    private var leadingSizeVal: Float
    private var plainVal: Bool
    private var trailingVal: El?
    private var copyVal: Bool
    private var clearVal: Bool
    private var invalidVal: Bool
    private var stateVal: State
    private var editsVal: EditActs
    private var copyActsVal: Acts

    public init(_ edit: TextEdit) {
        self.editVal = edit
        self.placeholderVal = ""
        self.largeVal = false
        self.styleVal = nil
        self.heightVal = nil
        self.widthVal = 280.0
        self.leadingVal = nil
        self.leadingSizeVal = 16.0
        self.plainVal = false
        self.trailingVal = nil
        self.copyVal = false
        self.clearVal = false
        self.invalidVal = false
        self.stateVal = .rest
        self.editsVal = EditActs()
        self.copyActsVal = Acts()
    }

    public static func new(_ edit: TextEdit) -> TextInput {
        TextInput(edit)
    }

    public func secure() -> TextInput {
        var copy = self
        copy.editVal.setSecure(true)
        return copy
    }

    public func revealed(_ revealed: Bool) -> TextInput {
        var copy = self
        copy.editVal.setRevealed(revealed)
        copy.editsVal.addVisual { e in e.revealed(revealed) }
        return copy
    }

    public func animateEditLayout() -> TextInput {
        var copy = self
        copy.editsVal.handlers.append { e in e.animateEditLayout() }
        return copy
    }

    public func onChange<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextInput {
        var copy = self
        copy.editsVal.change(f)
        return copy
    }

    public func onKey<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> TextInput {
        var copy = self
        copy.editsVal.key(f)
        return copy
    }

    public func placeholder(_ p: String) -> TextInput {
        var copy = self
        copy.placeholderVal = p
        return copy
    }

    /// `appearance="large"`: 32 points tall.
    public func large() -> TextInput {
        var copy = self
        copy.largeVal = true
        return copy
    }

    /// The text's type, in place of `uiCompact` (13 / 16): typed text, placeholder, caret and
    /// selection all follow it. Unless ``height(_:)`` sets one, the box grows to fit, to the
    /// style's line height plus 12 points if that's taller than 28 (32 with ``large()``),
    /// e.g. `.textStyle(TextStyle.new(17.0, 400.0).lh(24.0)).height(56.0)` for a launcher field.
    public func textStyle(_ style: TextStyle) -> TextInput {
        var copy = self
        copy.styleVal = style
        return copy
    }

    /// The box's height in points, in place of 28 (32 with ``large()``) or the fit to
    /// ``textStyle(_:)``. Clamped to at least the text style's line height.
    public func height(_ points: Float) -> TextInput {
        var copy = self
        copy.heightVal = max(points, 1.0)
        return copy
    }

    /// Width in points (default 280); `nil` fills the parent.
    public func width(_ w: Float?) -> TextInput {
        var copy = self
        copy.widthVal = w
        return copy
    }

    public func leadingIcon(_ i: Icon) -> TextInput {
        var copy = self
        copy.leadingVal = i
        return copy
    }

    /// The leading icon's side in points (default 16). The icon stays vertically centred in the
    /// box and the text's start moves with it.
    public func leadingIconSize(_ points: Float) -> TextInput {
        var copy = self
        copy.leadingSizeVal = max(points, 1.0)
        return copy
    }

    /// A borderless field for sitting inside something else, such as a header: no fill, sheen,
    /// shadow, border, hover tint or focus outline, so the surrounding view is the context.
    public func plain() -> TextInput {
        var copy = self
        copy.plainVal = true
        return copy
    }

    /// Trailing accessory element (e.g. a badge, hint, or reveal/copy buttons).
    public func trailing(_ e: El) -> TextInput {
        var copy = self
        copy.trailingVal = e
        return copy
    }

    public func copyButton() -> TextInput {
        var copy = self
        copy.copyVal = true
        return copy
    }

    public func clearButton() -> TextInput {
        var copy = self
        copy.clearVal = true
        return copy
    }

    public func invalid(_ i: Bool) -> TextInput {
        var copy = self
        copy.invalidVal = i
        return copy
    }

    public func state(_ s: State) -> TextInput {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> TextInput {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    // PORT NOTE: Supports `WritableKeyPath<S, TextEdit>`, `EditAccess<S>`, and scoped mutation
    // closures matching `Rune.El.onEdit`.
    public func onEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> TextInput {
        onEdit(EditAccess(keyPath))
    }

    public func onEdit<S>(_ access: EditAccess<S>) -> TextInput {
        var copy = self
        copy.editsVal.edit(access)
        return copy
    }

    public func onEdit<S>(_ f: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> TextInput {
        onEdit(EditAccess(f))
    }

    public func onSubmit<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextInput {
        var copy = self
        copy.editsVal.submit(f)
        return copy
    }

    /// The trailing copy or clear button's press.
    public func onAction<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextInput {
        var copy = self
        copy.copyActsVal.pressTx(f)
        return copy
    }

    public func spans(_ spans: [Span]) -> TextInput {
        var copy = self
        copy.editsVal.addVisual { e in e.spans(spans) }
        return copy
    }

    public func decorations(_ spans: [Span]) -> TextInput {
        self.spans(spans)
    }

    public func richStyle(_ style: RichStyle) -> TextInput {
        var copy = self
        copy.editsVal.addVisual { e in e.richStyle(style) }
        return copy
    }

    public func pillIcon(_ icon: @escaping (String) -> Icon?) -> TextInput {
        var copy = self
        copy.editsVal.addVisual { e in e.pillIcon(icon) }
        return copy
    }

    public func pillStyle(_ style: @escaping (String) -> PillStyle) -> TextInput {
        var copy = self
        copy.editsVal.addVisual { e in e.pillStyle(style) }
        return copy
    }

    public func pillColors(_ bg: Color, _ fg: Color?) -> TextInput {
        var copy = self
        copy.editsVal.addVisual { e in e.pillColors(bg, fg) }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let red = invalidVal && !disabled && (k.invalidText || plainVal)
        let ink = red ? c.danger.fg : c.textBase
        let hint = red ? c.danger.fg : c.textFaint
        let style = styleVal ?? k.ty.uiCompact
        let base: Float = largeVal ? 32.0 : 28.0
        let resolvedHeight: Float
        if let h = heightVal {
            resolvedHeight = max(h, style.linePx())
        } else {
            resolvedHeight = max(base, style.linePx() + 12.0)
        }
        let field = editsVal.apply(
            textInput(editVal, style)
                .singleLine()
                .key("input")
                .grow(1.0)
                .shrink()
                .color(ink)
                .richStyle(kitRichStyle(k))
                .placeholder(placeholderVal, hint)
                .caret(ink, k.selection()),
            disabled
        )
        var value = row().key("value").grow(1.0).shrink().gap(6.0).centerY()
        if let i = leadingVal {
            value = value.child(
                el().key("leading").pl(8.0).center().child(icon(i, leadingSizeVal).color(c.iconMuted))
            )
        } else {
            value = value.child(el().w(2.0))
        }
        value = value.child(field)
        var e = row()
            .role("textbox")
            .label(placeholderVal)
            .h(resolvedHeight)
            .pr(8.0)
            .gap(8.0)
            .child(value)
        if let w = widthVal {
            e = e.w(w)
        } else {
            e = e.wFull()
        }
        if let t = trailingVal {
            e = e.child(row().key("trailing").selfCenter().centerY().child(t))
        }
        if (copyVal && !editVal.isSecure()) || clearVal {
            let glyph: Icon
            let side: Float
            let radius: Float
            if clearVal {
                (glyph, side, radius) = (k.glyph.clear, 28.0, k.radius.md)
            } else {
                (glyph, side, radius) = (k.glyph.copy, 20.0, k.radius.sm)
            }
            var b = row()
                .key("action")
                .role("button")
                .label(clearVal ? "Clear" : "Copy")
                .size(side, side)
                .selfCenter()
                .center()
                .radius(radius)
                .child(icon(glyph, 16.0).color(c.iconMuted))
            if clearVal {
                b = b.mr(-8.0)
            }
            if !disabled {
                b = copyActsVal.apply(
                    b.hit().hover(c.hover).press(pressOver(c.hover, c.pressed)),
                    true
                )
            }
            e = e.child(b)
        }
        if plainVal {
            return disabled ? e.dim(0.5) : e
        }
        return inputShell(
            k,
            e,
            (0.06, 0.02),
            stateVal,
            invalidVal && !disabled,
            editVal.focused && !disabled
        )
    }
}

/// A multi-line field (`Textarea`): 80 points tall at least, 13/1.35 type, 8 points of padding.
public struct TextArea {
    private var editVal: TextEdit
    private var placeholderVal: String
    private var widthVal: Float?
    private var rowsVal: Int
    private var growVal: (Int, Int)?
    private var maxHeightVal: Float?
    private var invalidVal: Bool
    private var stateVal: State
    private var editsVal: EditActs

    public init(_ edit: TextEdit) {
        self.editVal = edit
        self.placeholderVal = ""
        self.widthVal = 280.0
        self.rowsVal = 3
        self.growVal = nil
        self.maxHeightVal = nil
        self.invalidVal = false
        self.stateVal = .rest
        self.editsVal = EditActs()
    }

    public static func new(_ edit: TextEdit) -> TextArea {
        TextArea(edit)
    }

    /// Protect the model like a password field. Hidden non-empty values use a fixed one-line
    /// mask. Clicks and unshifted navigation move to the end; shifted navigation selects all.
    /// Typing/paste append, or replace the whole value if selected; Backspace deletes at the
    /// end. Reveal to edit an interior position. Enter inserts a newline; Cmd/Ctrl+Enter submits.
    public func secure() -> TextArea {
        var copy = self
        copy.editVal.setSecure(true)
        return copy
    }

    /// Show the text without enabling undo, copy, cut, IME or accessibility text.
    /// Toggling preserves the model selection until a hidden edit or navigation occurs.
    public func revealed(_ revealed: Bool) -> TextArea {
        var copy = self
        copy.editVal.setRevealed(revealed)
        copy.editsVal.addVisual { e in e.revealed(revealed) }
        return copy
    }

    public func placeholder(_ p: String) -> TextArea {
        var copy = self
        copy.placeholderVal = p
        return copy
    }

    public func width(_ w: Float?) -> TextArea {
        var copy = self
        copy.widthVal = w
        return copy
    }

    public func rows(_ r: Int) -> TextArea {
        var copy = self
        copy.rowsVal = max(r, 1)
        return copy
    }

    /// Fit the text: at least `minRows` lines tall, growing with each wrapped line up to
    /// `maxRows`, then scrolling inside with the caret kept in view. The height springs on
    /// the kit's control motion.
    public func autoGrow(_ minRows: Int, _ maxRows: Int) -> TextArea {
        var copy = self
        let lo = max(minRows, 1)
        copy.growVal = (lo, max(maxRows, lo))
        return copy
    }

    /// Cap the field's height and scroll overflowing text. With ``autoGrow(_:_:)``,
    /// also stop growing at this many points of text.
    public func maxHeight(_ h: Float) -> TextArea {
        var copy = self
        copy.maxHeightVal = h
        return copy
    }

    public func animateEditLayout() -> TextArea {
        var copy = self
        copy.editsVal.handlers.append { e in e.animateEditLayout() }
        return copy
    }

    public func wrapAnywhere() -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.wrapAnywhere() }
        return copy
    }

    public func invalid(_ i: Bool) -> TextArea {
        var copy = self
        copy.invalidVal = i
        return copy
    }

    public func state(_ s: State) -> TextArea {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> TextArea {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> TextArea {
        onEdit(EditAccess(keyPath))
    }

    public func onEdit<S>(_ access: EditAccess<S>) -> TextArea {
        var copy = self
        copy.editsVal.edit(access)
        return copy
    }

    public func onEdit<S>(_ f: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> TextArea {
        onEdit(EditAccess(f))
    }

    public func onSubmit<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextArea {
        var copy = self
        copy.editsVal.submit(f)
        return copy
    }

    public func onKey<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> TextArea {
        var copy = self
        copy.editsVal.key(f)
        return copy
    }

    public func onChange<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextArea {
        var copy = self
        copy.editsVal.change(f)
        return copy
    }

    public func spans(_ spans: [Span]) -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.spans(spans) }
        return copy
    }

    public func decorations(_ spans: [Span]) -> TextArea {
        self.spans(spans)
    }

    public func richStyle(_ style: RichStyle) -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.richStyle(style) }
        return copy
    }

    public func pillIcon(_ icon: @escaping (String) -> Icon?) -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.pillIcon(icon) }
        return copy
    }

    public func pillStyle(_ style: @escaping (String) -> PillStyle) -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.pillStyle(style) }
        return copy
    }

    public func pillColors(_ bg: Color, _ fg: Color?) -> TextArea {
        var copy = self
        copy.editsVal.addVisual { e in e.pillColors(bg, fg) }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let lh = (Float(13.0 * 1.35 * 2.0)).rounded(.toNearestOrAwayFromZero) / 2.0
        let style = k.ty.ui.lh(lh)
        let red = invalidVal && !disabled && k.invalidText
        let ink = red ? c.danger.fg : c.textBase
        let hint = red ? c.danger.fg : c.textFaint
        let field = editsVal.apply(
            textInput(editVal, style)
                .key("input")
                .wFull()
                .color(ink)
                .richStyle(kitRichStyle(k))
                .placeholder(placeholderVal, hint)
                .caret(ink, k.selection()),
            disabled
        )
        let line = style.linePx()
        var e = col().role("textbox").label(placeholderVal).padding(8.0)
        if let (minRows, maxRows) = growVal {
            var viewport = Rune.autoGrow(field, minRows, maxRows)
            if let h = maxHeightVal {
                viewport = viewport.maxH(max(min(h, Float(maxRows) * line), line))
            }
            e = e.child(viewport)
        } else if let h = maxHeightVal {
            let maxInner = max(h - 16.0, line)
            let minInner = min(max(Float(rowsVal) * line, 80.0 - 16.0), maxInner)
            let viewport = col()
                .key("scroll")
                .wFull()
                .shrink()
                .minH(minInner)
                .maxH(maxInner)
                .scroll(ScrollSpec(stickBottom: false))
                .child(field.animateEditLayout())
            e = e.minH(minInner + 16.0).child(viewport)
        } else {
            // A <textarea rows=3>: rows of its line height plus padding, at least 80.
            e = e.minH(max(Float(rowsVal) * line + 16.0, 80.0)).child(field)
        }
        if let w = widthVal {
            e = e.w(w)
        } else {
            e = e.wFull()
        }
        return inputShell(
            k,
            e,
            (0.02, 0.0),
            stateVal,
            invalidVal && !disabled,
            editVal.focused && !disabled
        )
    }
}

/// The older labelled field (`components/text-field`): label over a bordered 32 point input.
public struct TextField {
    private var labelVal: String
    private var editVal: TextEdit
    private var placeholderVal: String
    private var hideLabelVal: Bool
    private var ghostVal: Bool
    private var multilineVal: Bool
    private var copyableVal: Bool
    private var trailingVal: El?
    private var errorVal: String?
    private var stateVal: State
    private var editsVal: EditActs
    private var copyActsVal: Acts

    public init(_ label: String, _ edit: TextEdit) {
        self.labelVal = label
        self.editVal = edit
        self.placeholderVal = ""
        self.hideLabelVal = false
        self.ghostVal = false
        self.multilineVal = false
        self.copyableVal = false
        self.trailingVal = nil
        self.errorVal = nil
        self.stateVal = .rest
        self.editsVal = EditActs()
        self.copyActsVal = Acts()
    }

    public static func new(_ label: String, _ edit: TextEdit) -> TextField {
        TextField(label, edit)
    }

    public func placeholder(_ p: String) -> TextField {
        var copy = self
        copy.placeholderVal = p
        return copy
    }

    public func hideLabel() -> TextField {
        var copy = self
        copy.hideLabelVal = true
        return copy
    }

    public func ghost() -> TextField {
        var copy = self
        copy.ghostVal = true
        return copy
    }

    public func multiline() -> TextField {
        var copy = self
        copy.multilineVal = true
        return copy
    }

    public func copyable() -> TextField {
        var copy = self
        copy.copyableVal = true
        return copy
    }

    /// Trailing accessory element inside the field's box.
    public func trailing(_ e: El) -> TextField {
        var copy = self
        copy.trailingVal = e
        return copy
    }

    /// The trailing copy button's press.
    public func onAction<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> TextField {
        var copy = self
        copy.copyActsVal.pressTx(f)
        return copy
    }

    public func error(_ e: String) -> TextField {
        var copy = self
        copy.errorVal = e
        return copy
    }

    public func disabled(_ d: Bool) -> TextField {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> TextField {
        onEdit(EditAccess(keyPath))
    }

    public func onEdit<S>(_ access: EditAccess<S>) -> TextField {
        var copy = self
        copy.editsVal.edit(access)
        return copy
    }

    public func onEdit<S>(_ f: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> TextField {
        onEdit(EditAccess(f))
    }

    public func spans(_ spans: [Span]) -> TextField {
        var copy = self
        copy.editsVal.addVisual { e in e.spans(spans) }
        return copy
    }

    public func decorations(_ spans: [Span]) -> TextField {
        self.spans(spans)
    }

    public func richStyle(_ style: RichStyle) -> TextField {
        var copy = self
        copy.editsVal.addVisual { e in e.richStyle(style) }
        return copy
    }

    public func pillIcon(_ icon: @escaping (String) -> Icon?) -> TextField {
        var copy = self
        copy.editsVal.addVisual { e in e.pillIcon(icon) }
        return copy
    }

    public func pillStyle(_ style: @escaping (String) -> PillStyle) -> TextField {
        var copy = self
        copy.editsVal.addVisual { e in e.pillStyle(style) }
        return copy
    }

    public func pillColors(_ bg: Color, _ fg: Color?) -> TextField {
        var copy = self
        copy.editsVal.addVisual { e in e.pillColors(bg, fg) }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let body = TextStyle.new(14.0, 400.0).lh(21.0)
        var field = textInput(editVal, body)
            .key("input")
            .grow(1.0)
            .shrink()
            .color(c.textStrong)
            .richStyle(kitRichStyle(k))
            .placeholder(placeholderVal, c.textWeak)
            .caret(c.textStrong, k.selection())
        if !multilineVal {
            field = field.singleLine()
        }
        field = editsVal.apply(field, stateVal == .disabled)
        var wrapper = row()
            .key("wrapper")
            .wFull()
            .minH(32.0)
            .px(12.0)
            .py(multilineVal ? 6.0 : 0.0)
            .centerY()
            .child(field)
        if !ghostVal {
            let fill: Color
            let border: Color
            if errorVal != nil {
                (fill, border) = (c.danger.bg, c.danger.border)
            } else {
                (fill, border) = (Color.TRANSPARENT, c.borderWeak)
            }
            wrapper = wrapper.radius(k.radius.md).fill(fill).border(1.0, border)
        }
        if let t = trailingVal {
            wrapper = wrapper.child(row().key("trailing").selfCenter().centerY().child(t))
        }
        if copyableVal {
            var b = row()
                .key("copy")
                .role("button")
                .label("Copy")
                .size(24.0, 24.0)
                .center()
                .radius(k.radius.md)
                .hover(c.hover)
                .child(icon(k.glyph.copy, 16.0).color(c.stdIcon))
            if stateVal != .disabled {
                b = copyActsVal.apply(
                    b.hit().hover(c.hover).press(pressOver(c.hover, c.pressed)),
                    true
                )
            }
            wrapper = wrapper.pr(4.0).child(b)
        }
        var root = col().role("textbox").label(labelVal).gap(8.0).wFull()
        if !hideLabelVal {
            root = root.child(
                text(labelVal).key("label").font(k.ty.textXsmallMedium).color(c.textWeak)
            )
        }
        root = root.child(wrapper)
        if let e = errorVal {
            root = root.child(text(e).key("error").font(k.ty.textXsmallMedium).color(c.danger.fg))
        }
        return stateVal == .disabled ? root.dim(0.5) : root
    }
}

/// Namespace mirroring `rune_kit::text_input` module exports.
public enum text_input {
    public typealias TextInput = RuneKit.TextInput
    public typealias TextArea = RuneKit.TextArea
    public typealias TextField = RuneKit.TextField
}
