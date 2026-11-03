// Ported from: crates/rune/src/el/text.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Text builders: font, spans and decorations, input pills, wrapping and truncation, reveal,
//! links, placeholder and caret, selection, and edit callbacks.

import Taffy

extension El {
    public func font(_ s: TextStyle) -> El {
        var copy = self
        copy.textSpec?.value.style = s
        if copy.input != nil {
            copy.syncInputRich()
        }
        return copy
    }

    /// Per-frame styled or coloured byte ranges (syntax highlights, mentions, inline styles)
    /// painted over a `text`, `rich` or `textInput` element without mutating `TextEdit`.
    public func spans(_ spans: [Span]) -> El {
        var copy = self
        if copy.input != nil {
            copy.input?.decorations = spans
            copy.syncInputRich()
        } else if copy.textSpec != nil {
            copy.textSpec?.modify { t in
                t.spans = withPillColors(spans, t.pills)
            }
        }
        return copy
    }

    /// Alias for ``spans(_:)``: per-frame syntax or highlight `Span`s painted over text.
    public func decorations(_ spans: [Span]) -> El {
        self.spans(spans)
    }

    /// An inset `color` border ring `width` points wide inside the rounded `Span.bg` of bytes `start..end`.
    public func spanRing(_ start: Int, _ end: Int, _ color: Color, _ width: Float) -> El {
        var copy = self
        if start >= 0 && start < end && width > 0.0 && width.isFinite {
            copy.textSpec?.value.rings.append((UInt32(start), UInt32(end), color, width))
        }
        return copy
    }

    /// Inset border rings `(start, end, color, width)` for multiple byte ranges (see ``spanRing(_:_:_:_:)``).
    public func spanRings<S: Swift.Sequence>(_ rings: S) -> El where S.Element == (Int, Int, Color, Float) {
        var copy = self
        for (start, end, color, width) in rings {
            copy = copy.spanRing(start, end, color, width)
        }
        return copy
    }

    /// A strikethrough line across bytes `start..end` in `color` (`nil`: the span's or text's colour).
    public func strike(_ start: Int, _ end: Int, _ color: Color?) -> El {
        var copy = self
        if start >= 0 && start < end {
            copy.textSpec?.value.strikes.append((UInt32(start), UInt32(end), color))
        }
        return copy
    }

    /// Strikethrough lines `(start, end, color)` for multiple byte ranges (see ``strike(_:_:_:)``).
    public func strikes<S: Swift.Sequence>(_ strikes: S) -> El where S.Element == (Int, Int, Color?) {
        var copy = self
        for (start, end, color) in strikes {
            copy = copy.strike(start, end, color)
        }
        return copy
    }

    /// A paint-only `TextHighlight` over bytes of the text.
    public func textHighlight(_ highlight: TextHighlight) -> El {
        var copy = self
        if highlight.start < highlight.end {
            copy.textSpec?.value.highlights.append(highlight)
        }
        return copy
    }

    /// Paint-only `TextHighlight`s over bytes of the text (see ``textHighlight(_:)``).
    public func textHighlights<S: Swift.Sequence>(_ highlights: S) -> El where S.Element == TextHighlight {
        var copy = self
        for h in highlights {
            copy = copy.textHighlight(h)
        }
        return copy
    }

    /// Set the visual palette for rich inline marks (`code`, `link`) and paragraph blocks
    /// (`quote`, `code block`, list markers) on a `textInput`.
    public func richStyle(_ style: RichStyle) -> El {
        var copy = self
        if copy.input != nil {
            copy.input?.richStyle = style
            copy.syncInputRich()
        } else {
            copy.textSpec?.value.richStyle = style
        }
        return copy
    }

    /// The chip colour of each `Mark.pill` in a `textInput`, and its label and icon colour (`nil`: the text's).
    public func pillColors(_ bg: Color, _ fg: Color?) -> El {
        var copy = self
        copy.textSpec?.value.pillColors = (bg, fg)
        if copy.input != nil {
            copy.syncInputRich()
        }
        return copy
    }

    /// The leading icon for each `Mark.pill` chip in a `textInput`, by the pill's id (`nil`: no icon).
    public func pillIcon(_ icon: @escaping (String) -> Icon?) -> El {
        var copy = self
        if copy.input != nil {
            copy.input?.pillIcon = icon
            copy.syncInputPills()
            copy.syncInputRich()
        }
        return copy
    }

    /// The look of each `Mark.pill` chip in a `textInput` by the pill's id: chip colour, label colour and icon.
    public func pillStyle(_ style: @escaping (String) -> PillStyle) -> El {
        var copy = self
        if copy.input != nil {
            copy.input?.pillStyle = style
            copy.syncInputPills()
            copy.syncInputRich()
        }
        return copy
    }

    mutating func syncInputPills() {
        guard let inp = input, textSpec != nil else { return }
        if inp.edit.isPlain() {
            textSpec?.value.pills.removeAll()
            return
        }
        let chips: [PillChip] = inp.edit.displayPills().map { (start, end, id) in
            let st = inp.pillStyle?(id) ?? PillStyle()
            let ic = st.leadingIcon ?? inp.pillIcon?(id)
            return PillChip(start: start, end: end, icon: ic, bg: st.bgColor, fg: st.fgColor)
        }
        textSpec?.value.pills = chips
    }

    mutating func syncInputRich() {
        guard let inp = input, textSpec != nil else { return }
        textSpec?.modify { t in
            t.richStyle = inp.richStyle
            if inp.edit.isPlain() && inp.decorations.isEmpty {
                t.spans.removeAll()
                t.strikes.removeAll()
                t.blocks.removeAll()
                t.softBreaks.removeAll()
                t.pills.removeAll()
                return
            }
            var (baseSpans, strikes, richLinks, blocks) = inp.edit.richDisplaySpecs(t.style, inp.richStyle)
            for d in inp.decorations {
                for (ds, de) in inp.edit.mapRangeToDisplay(Int(d.start), Int(d.end)) {
                    var sp = d
                    sp.start = ds
                    sp.end = de
                    baseSpans.append(sp)
                }
            }
            let pillFg = t.pillColors?.1
            for p in t.pills {
                if let fg = p.fg ?? pillFg {
                    var sp = Span(start: Int(p.start), end: Int(p.end))
                    sp.color = fg
                    baseSpans.append(sp)
                }
            }
            var flat = flattenSpans(baseSpans)
            for i in flat.indices {
                if flat[i].underline == .TRANSPARENT {
                    flat[i].underline = flat[i].color ?? t.color
                }
            }
            t.spans = flat
            t.strikes = strikes
            t.blocks = blocks
            t.softBreaks = inp.edit.softBreaks()
            t.links = richLinks
        }
    }

    /// Wrap text at the element's width.
    public func wrap(_ enabled: Bool = true) -> El {
        var copy = self
        copy.textSpec?.value.wrap = enabled
        return copy
    }

    /// Wrap text at the element's width, breaking inside a word only when the word alone would
    /// overflow the line (`overflow-wrap: anywhere`).
    public func wrapAnywhere() -> El {
        if let inp = input, inp.singleLine {
            return self
        }
        var copy = self
        copy.textSpec?.modify { t in
            t.wrap = true
            t.wrapAnywhere = true
        }
        return copy
    }

    /// Whether this is text that wraps (`.wrap()`), for containers that let such text shrink to their width.
    public func wraps() -> Bool {
        textSpec?.value.wrap ?? false
    }

    /// One line, cut with "…" when wider than the element; the element may shrink below its text's width.
    public func truncate(_ enabled: Bool = true) -> El {
        guard enabled else {
            var copy = self
            copy.textSpec?.value.truncate = false
            return copy
        }
        return elide(.end)
    }

    /// ``truncate(_:)`` keeping both ends: "…" replaces the middle, as AppKit's `NSLineBreakByTruncatingMiddle`.
    public func truncateMiddle() -> El {
        elide(.middle)
    }

    /// ``truncate(_:)`` keeping the end: "…" replaces the start.
    public func truncateHead() -> El {
        elide(.head)
    }

    private func elide(_ elide: Elide) -> El {
        if input != nil {
            return self
        }
        return oneLine { t in
            t.truncate = true
            t.elide = elide
            t.truncateFade = false
        }
    }

    private func oneLine(_ cut: (inout TextSpec) -> Void) -> El {
        var copy = self
        copy.textSpec?.modify { t in
            t.wrap = false
            t.wrapAnywhere = false
            t.maxLines = 0
            cut(&t)
        }
        copy.style.flexShrink = 1.0
        copy.style.minSize.width = .length(0.0)
        return copy
    }

    /// Wrapped text that stops after `lines` lines, "…" ending the last when more would follow (`line-clamp`).
    public func maxLines(_ lines: Int) -> El {
        if input != nil {
            return self
        }
        var copy = self
        copy.textSpec?.modify { t in
            t.wrap = true
            t.maxLines = max(lines, 0)
            t.truncate = false
            t.truncateFade = false
        }
        return copy
    }

    /// One line, clipped with a 1.5 em trailing fade only when it overflows. No ellipsis.
    public func truncateFade() -> El {
        truncateFadeWidth(TRUNCATE_FADE_EM)
    }

    /// ``truncateFade()`` with a fade `em` ems wide.
    public func truncateFadeWidth(_ em: Float) -> El {
        oneLine { t in
            t.truncate = false
            t.truncateFade = true
            t.fadeEm = max(em, 0.0)
        }
    }

    /// Streaming word reveal (see ``TextSpec/reveal``).
    public func reveal(_ wordFade: Float) -> El {
        var copy = self
        copy.textSpec?.value.reveal = max(wordFade, 0.0)
        return copy
    }

    /// Keep a text field to one line: long text scrolls sideways under the caret instead of wrapping.
    public func singleLine(_ enabled: Bool = true) -> El {
        var copy = self
        guard var inp = copy.input else { return copy }
        inp.singleLine = enabled
        inp.edit.setSingleLine(enabled)
        copy.input = inp
        copy.textSpec?.modify { t in
            t.wrap = !enabled
            if enabled {
                t.wrapAnywhere = false
            } else if inp.edit.isSecure() {
                t.wrapAnywhere = true
            }
            if inp.edit.isSecure() && !inp.edit.isRevealed() {
                t.replaceContent(inp.edit.display().0)
            }
        }
        return copy
    }

    /// Make a byte range of this text pressable (see `Link`).
    public func link(_ link: Link) -> El {
        var copy = self
        guard copy.textSpec != nil else { return copy }
        copy.textSpec?.value.links.append(link)
        copy.focusSpec.value.enabled = true
        if copy.handlers.getIfSome?.cursor == nil {
            copy.handlers.value.cursor = .pointer
        }
        return copy
    }

    /// Called with a `Link`'s id when it is clicked, or pressed with Enter or Space while focused.
    public func onLink<S>(_ f: @escaping (inout S, String, inout Tx) -> Void) -> El {
        var copy = self
        copy.textSpec?.value.onLink = { states, id, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, id, &tx)
            }
        }
        return copy
    }

    /// Called with a `Link`'s id and the point (window points) when a secondary press lands on its glyphs.
    public func onLinkSecondary<S>(_ f: @escaping (inout S, String, PointerPress, inout Tx) -> Void) -> El {
        var copy = self
        copy.textSpec?.value.onLinkSecondary = { states, id, p, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, id, p, &tx)
            }
        }
        return copy
    }

    public func placeholder(_ s: String, _ c: Color? = nil) -> El {
        var copy = self
        copy.input?.placeholder = s
        if let c {
            copy.input?.placeholderColor = c
        }
        return copy
    }

    public func caret(_ caret: Color, _ selection: Color) -> El {
        var copy = self
        copy.input?.caret = caret
        copy.input?.selection = selection
        return copy
    }

    /// Lets people select this read-only text and copy it, as SwiftUI's `.textSelection(.enabled)`.
    public func selectable(_ on: Bool) -> El {
        var copy = self
        guard let spec = copy.textSpec?.value else { return copy }
        if copy.input != nil || spec.redacted {
            return copy
        }
        copy.textSpec?.value.selectable = on
        let cur = copy.handlers.getIfSome?.cursor
        if on && (cur == nil || (!spec.links.isEmpty && cur == .pointer)) {
            copy.handlers.value.cursor = .text
        }
        return copy
    }

    /// Makes the ``selectable(_:)`` texts inside this element one selection, in tree order.
    public func selectionGroup(_ on: Bool) -> El {
        var copy = self
        copy.selectionGroupFlag = on
        return copy
    }

    /// What copying a text selection inside this element puts on the clipboard instead of the drawn text.
    public func selectionCopy(_ f: @escaping (TextSelection) -> String?) -> El {
        var copy = self
        copy.handlers.value.selectionCopy = f
        return copy
    }

    /// Hears the ``selectable(_:)`` text selection change inside this element.
    public func onSelectionChange<S>(_ f: @escaping (inout S, SelectionChange, inout Tx) -> Void) -> El {
        var copy = self
        copy.handlers.value.onSelectionChange = { states, change, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, change, &tx)
            }
        }
        return copy
    }

    /// Draws and lays out, but the pointer and keyboard pass through this element and everything inside it (`inert`).
    public func inert() -> El {
        var copy = self
        copy.inertFlag = true
        return copy
    }

    /// Bytes of ``selectable(_:)`` text that draw but aren't copied.
    public func uncopied(_ range: Range<Int>) -> El {
        var copy = self
        guard range.lowerBound >= 0 && range.lowerBound < range.upperBound else { return copy }
        copy.textSpec?.modify { t in
            let at = t.uncopied.firstIndex(where: { Int($0.0) >= range.lowerBound }) ?? t.uncopied.count
            t.uncopied.insert((UInt32(range.lowerBound), UInt32(range.upperBound)), at: at)
        }
        return copy
    }

    /// The selection highlight of ``selectable(_:)`` text or a text field, drawn alike for both.
    public func selectionColor(_ color: Color) -> El {
        var copy = self
        copy.input?.selection = color
        copy.textSpec?.value.selection = color
        return copy
    }

    /// Binds the field to a `TextEdit` in app state via a `WritableKeyPath`.
    public func onEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> El {
        onEdit(EditAccess(keyPath))
    }

    /// Binds the field to a `TextEdit` in app state via an `EditAccess<S>` descriptor.
    public func onEdit<S>(_ access: EditAccess<S>) -> El {
        var copy = self
        copy.input?.access = editFn(access)
        return copy
    }

    /// Binds the field to a `TextEdit` in app state via a scoped mutation closure.
    public func onEdit<S>(_ f: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> El {
        onEdit(EditAccess(f))
    }

    /// Called when Return submits this text field.
    public func onSubmit<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> El {
        var copy = self
        copy.input?.submit = { states, tx in
            _ = states.withMutable { (state: inout S) in
                f(&state, &tx)
            }
        }
        return copy
    }

    /// Let dependent layout reflow when this input changes; the typed text remains immediate.
    public func animateEditLayout() -> El {
        var copy = self
        copy.input?.animateLayout = true
        return copy
    }
}
