// Ported from: crates/rune-kit/src/combobox.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Searchable select: Popover + TextInput + virtual rows. Keyboard contract follows
//! `@opencode/ui`'s `use-filtered-list`: looping arrows, Ctrl-N/P, composition-safe Enter,
//! and editor modifiers left to the text field. Fuzzy scores are Rune's own ordering.

import Rune

public struct ComboboxOption: Sendable, Equatable, Hashable {
    public var id: String
    public var label: String
    public var detail: String
    public var disabled: Bool

    public init(_ id: String, _ label: String, detail: String = "", disabled: Bool = false) {
        self.id = id
        self.label = label
        self.detail = detail
        self.disabled = disabled
    }

    public init(id: String, label: String, detail: String = "", disabled: Bool = false) {
        self.init(id, label, detail: detail, disabled: disabled)
    }

    public static func new(_ id: String, _ label: String) -> ComboboxOption {
        ComboboxOption(id, label)
    }
}

public struct ComboboxState: Equatable, Hashable {
    public var open: Bool
    public var search: TextEdit
    public var active: String?
    var query: String

    public init(open: Bool = false, search: TextEdit = TextEdit(), active: String? = nil) {
        self.open = open
        self.search = search
        self.active = active
        self.query = ""
    }

    public static var `default`: ComboboxState {
        ComboboxState()
    }

    public mutating func close() {
        open = false
        search.focused = false
        search.preedit = nil
        search.breakHistoryGroup()
    }

    func activeIndex(_ options: [ComboboxOption], _ filtered: [Int]) -> Int? {
        if query == search.text,
           let index = filtered.first(where: { !options[$0].disabled && options[$0].id == active })
        {
            return index
        }
        return filtered.first(where: { !options[$0].disabled })
    }
}

private func isScalarAlphanumeric(_ c: Unicode.Scalar) -> Bool {
    if c.value < 0x80 {
        return (c.value >= 0x30 && c.value <= 0x39)
            || (c.value >= 0x41 && c.value <= 0x5A)
            || (c.value >= 0x61 && c.value <= 0x7A)
    }
    if c.properties.isAlphabetic {
        return true
    }
    switch c.properties.generalCategory {
    case .decimalNumber, .letterNumber, .otherNumber:
        return true
    default:
        return false
    }
}

private func comboboxTrimWhitespace(_ s: String) -> String {
    let scalars = s.unicodeScalars
    var lo = scalars.startIndex
    while lo < scalars.endIndex && scalars[lo].properties.isWhitespace {
        lo = scalars.index(after: lo)
    }
    var hi = scalars.endIndex
    while hi > lo {
        let prev = scalars.index(before: hi)
        if scalars[prev].properties.isWhitespace {
            hi = prev
        } else {
            break
        }
    }
    return String(scalars[lo..<hi])
}

// Case-insensitive subsequence matching; contiguous matches and word starts rank first.
private func comboboxScore(_ query: String, _ value: String) -> Int32? {
    let needle = Array(query.unicodeScalars)
    var n = 0
    var score: Int32 = 0
    var previous = false
    var boundary = true
    for c in value.lowercased().unicodeScalars {
        if n < needle.count && c == needle[n] {
            score += 10 + (previous ? 12 : 0) + (boundary ? 8 : 0)
            previous = true
            n += 1
        } else {
            previous = false
            score -= 1
        }
        boundary = !isScalarAlphanumeric(c)
    }
    return n == needle.count ? score : nil
}

private func comboboxFiltered(_ options: [ComboboxOption], _ query: String) -> [Int] {
    let trimmed = comboboxTrimWhitespace(query).lowercased()
    if trimmed.isEmpty {
        return Array(0..<options.count)
    }
    var matches: [(Int, Int32)] = []
    for (i, o) in options.enumerated() {
        let s1 = comboboxScore(trimmed, o.label)
        let s2 = comboboxScore(trimmed, o.detail)
        let best: Int32? = switch (s1, s2) {
        case (.some(let a), .some(let b)): max(a, b)
        case (.some(let a), .none): a
        case (.none, .some(let b)): b
        case (.none, .none): nil
        }
        if let s = best {
            matches.append((i, s))
        }
    }
    matches.sort { a, b in
        if a.1 != b.1 {
            return a.1 > b.1
        }
        return a.0 < b.0
    }
    return matches.map(\.0)
}

/// `Combobox.new("models", s.combo, options, \App.combo)`.
/// Selection is app-controlled through `current` and `onChoose`; search/open/highlight
/// state belongs to the supplied `ComboboxState`. Only mounted rows are laid out/shaped.
public struct Combobox<S> {
    var key: String
    var stateVal: ComboboxState
    var options: [ComboboxOption]
    // PORT NOTE: Swift cannot return `&mut ComboboxState` from a closure; supports both
    // `WritableKeyPath<S, ComboboxState>` and a scoped mutation closure `(inout S, (inout ComboboxState) -> Void) -> Void`.
    var withState: (inout S, (inout ComboboxState) -> Void) -> Void
    var chooseFn: ((inout S, String, inout Tx) -> Void)?
    var currentVal: String?
    var placeholderText: String
    var searchPlaceholderText: String
    var emptyText: String
    var widthVal: Float
    var maxHeightVal: Float
    var placementVal: Placement
    var triggerEl: El?
    var disabledFlag: Bool
    var animateFilteringFlag: Bool

    public init(
        _ key: String,
        _ state: ComboboxState,
        _ options: [ComboboxOption],
        _ keyPath: WritableKeyPath<S, ComboboxState>
    ) {
        self.init(key, state, options) { s, body in
            body(&s[keyPath: keyPath])
        }
    }

    public init(
        _ key: String,
        _ state: ComboboxState,
        _ options: [ComboboxOption],
        _ access: @escaping (inout S, (inout ComboboxState) -> Void) -> Void
    ) {
        self.key = key
        self.stateVal = state
        self.options = options
        self.withState = access
        self.chooseFn = nil
        self.currentVal = nil
        self.placeholderText = ""
        self.searchPlaceholderText = "Search"
        self.emptyText = "No results"
        self.widthVal = 280.0
        self.maxHeightVal = 192.0
        self.placementVal = .bottomStart
        self.triggerEl = nil
        self.disabledFlag = false
        self.animateFilteringFlag = false
    }

    public static func new(
        _ key: String,
        _ state: ComboboxState,
        _ options: [ComboboxOption],
        _ keyPath: WritableKeyPath<S, ComboboxState>
    ) -> Combobox<S> {
        Combobox(key, state, options, keyPath)
    }

    public static func new(
        _ key: String,
        _ state: ComboboxState,
        _ options: [ComboboxOption],
        _ access: @escaping (inout S, (inout ComboboxState) -> Void) -> Void
    ) -> Combobox<S> {
        Combobox(key, state, options, access)
    }

    public func current(_ id: String?) -> Combobox<S> {
        var copy = self
        copy.currentVal = id
        return copy
    }

    public func placeholder(_ text: String) -> Combobox<S> {
        var copy = self
        copy.placeholderText = text
        return copy
    }

    public func searchPlaceholder(_ text: String) -> Combobox<S> {
        var copy = self
        copy.searchPlaceholderText = text
        return copy
    }

    public func emptyMessage(_ text: String) -> Combobox<S> {
        var copy = self
        copy.emptyText = text
        return copy
    }

    /// The popover's width, 280 by default; the trigger keeps its own.
    public func width(_ width: Float) -> Combobox<S> {
        var copy = self
        copy.widthVal = width
        return copy
    }

    /// The tallest the result list grows, 192 by default. A window with less room below (or
    /// above) the trigger shortens it further, and it scrolls.
    public func maxHeight(_ height: Float) -> Combobox<S> {
        var copy = self
        copy.maxHeightVal = height
        return copy
    }

    public func placement(_ placement: Placement) -> Combobox<S> {
        var copy = self
        copy.placementVal = placement
        return copy
    }

    /// Replaces the default field trigger (the chosen label and a chevron) with any element;
    /// pressing it opens and closes the popover.
    public func trigger(_ trigger: El) -> Combobox<S> {
        var copy = self
        copy.triggerEl = trigger
        return copy
    }

    public func disabled(_ disabled: Bool) -> Combobox<S> {
        var copy = self
        copy.disabledFlag = disabled
        return copy
    }

    /// Animate each keystroke's filtering: the popover springs to its new height and the
    /// rows crossfade, as ``PopupList/animateFiltering(_:)``. Off by default, so the rows and
    /// the height a keystroke changes land in the same frame.
    public func animateFiltering(_ animate: Bool) -> Combobox<S> {
        var copy = self
        copy.animateFilteringFlag = animate
        return copy
    }

    public func onChoose(_ choose: @escaping (inout S, String, inout Tx) -> Void) -> Combobox<S> {
        var copy = self
        copy.chooseFn = choose
        return copy
    }

    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let selected = options.first(where: { $0.id == currentVal })
        let access = withState
        let current = currentVal
        let openKey = key
        var trigger: El = if let custom = triggerEl {
            custom
        } else {
            Select.new("\(key)-value", [])
                .current(selected?.label)
                .placeholder(placeholderText)
                .appearance(.field)
                .width(widthVal)
                .disabled(disabledFlag)
                .trigger(k)
        }
        if !disabledFlag {
            trigger = trigger.onPressTx { (s: inout S, tx: inout Tx) in
                access(&s) { state in
                    state.open = !state.open
                    state.search.clear()
                    state.search.focused = state.open
                    state.query = ""
                    state.active = current
                    if state.open, let id = current {
                        tx.scrollIntoView("\(openKey)-option-\(id)")
                    }
                }
            }
        }
        var pop = Popover.new(key)
            .trigger(trigger)
            .placement(placementVal)
            .padding(0.0)
            .open(stateVal.open && !disabledFlag)
        pop = pop.onClose { (s: inout S) in
            access(&s) { $0.close() }
        }
        if !stateVal.open || disabledFlag {
            return pop.build(k, &layer)
        }

        let choices = comboboxFiltered(options, stateVal.search.text)
        let active = stateVal.activeIndex(options, choices)
        let optionsCopy = options
        let chooseCopy = chooseFn
        let comboKey = key

        // The search field sits borderless over a divider: the open popover is its frame, and the
        // caret shows its focus.
        var fieldBuilder = TextInput.new(stateVal.search)
            .plain()
            .leadingIcon(k.glyph.search)
            .height(36.0)
            .width(nil)
            .placeholder(searchPlaceholderText)
        // Without it, an edit's commit is instant: the filtered rows and the height land with the text.
        if animateFilteringFlag {
            fieldBuilder = fieldBuilder.animateEditLayout()
        }
        let field = fieldBuilder
            .onEdit { (s: inout S, editBody: (inout TextEdit) -> Void) in
                access(&s) { state in
                    editBody(&state.search)
                }
            }
            .onChange { (s: inout S, tx: inout Tx) in
                access(&s) { state in
                    state.active = nil
                    state.query = state.search.text
                    if let i = comboboxFiltered(optionsCopy, state.search.text).first(where: { !optionsCopy[$0].disabled }) {
                        tx.scrollIntoView("\(comboKey)-option-\(optionsCopy[i].id)")
                    }
                }
            }
            .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) -> Bool in
                var consumed = false
                var chosenId: String? = nil
                access(&s) { state in
                    if state.search.preedit != nil {
                        consumed = false
                        return
                    }
                    if ev.key == .escape {
                        if !tx.keyRepeat() {
                            state.close()
                        }
                        consumed = true
                        return
                    }
                    if ev.mods.alt || ev.mods.logo {
                        consumed = false
                        return
                    }
                    let currentChoices = comboboxFiltered(optionsCopy, state.search.text)
                    let enabled = currentChoices.filter { !optionsCopy[$0].disabled }
                    let currentActive = state.activeIndex(optionsCopy, enabled)
                    if ev.key == .enter {
                        consumed = true
                        if tx.keyRepeat() {
                            return
                        }
                        chosenId = currentActive.map { optionsCopy[$0].id }
                        state.close()
                        return
                    }
                    let control = ev.mods.ctrl && !ev.mods.shift
                    let delta: Int
                    switch ev.key {
                    case .down where !ev.mods.cmd && !ev.mods.ctrl:
                        delta = 1
                    case .up where !ev.mods.cmd && !ev.mods.ctrl:
                        delta = -1
                    case .text(let c) where control && c == "n":
                        delta = 1
                    case .text(let c) where control && c == "p":
                        delta = -1
                    case .command("n") where control:
                        delta = 1
                    case .command("p") where control:
                        delta = -1
                    default:
                        consumed = false
                        return
                    }
                    if !enabled.isEmpty {
                        let index = currentActive.flatMap { orig in enabled.firstIndex(of: orig) } ?? 0
                        let len = enabled.count
                        let next = ((index + delta) % len + len) % len
                        let id = optionsCopy[enabled[next]].id
                        tx.scrollIntoView("\(comboKey)-option-\(id)")
                        state.active = id
                        state.query = state.search.text
                    }
                    consumed = true
                }
                if let selectedId = chosenId, let choose = chooseCopy {
                    choose(&s, selectedId, &tx)
                }
                return consumed
            }
            .build(k)
            .key("search")

        let activePos = active.flatMap { orig in choices.firstIndex(of: orig) }
        let popupItems: [PopupItem] = choices.map { i in
            let option = optionsCopy[i]
            return PopupItem.new(option.id, option.label)
                .description(option.detail)
                .disabled(option.disabled)
                .trailing(
                    Rune.icon(k.glyph.checkSmall, 14.0)
                        .color(k.c.iconBase)
                        .opacity(current == option.id ? 1.0 : 0.0)
                )
        }
        let hoverChoices = choices
        let list = PopupList<S>.new(key, "")
            .maxHeight(maxHeightVal)
            .items(popupItems)
            .active(activePos)
            .emptyMessage(emptyText)
            .onActive { (s: inout S, i: Int) in
                guard i >= 0 && i < hoverChoices.count else { return }
                let orig = hoverChoices[i]
                access(&s) { state in
                    state.active = optionsCopy[orig].id
                    state.query = state.search.text
                }
            }
            .onChoose { (s: inout S, id: String, tx: inout Tx) in
                access(&s) { $0.close() }
                if let choose = chooseCopy {
                    choose(&s, id, &tx)
                }
            }
            .buildList(k)

        let results = Rune.col().key("results").wFull().padding(4.0).shrink().minH(0.0).child(list)
        let body = Rune.col()
            .w(widthVal)
            .shrink()
            .minH(0.0)
            .child(Rune.row().key("header").wFull().px(4.0).child(field))
            .child(Rune.el().key("divider").wFull().h(1.0).fill(k.c.borderWeak))
            .child(results)
        return pop.child(body).build(k, &layer)
    }
}

/// Namespace mirroring `rune_kit::combobox` module exports.
public enum combobox {
    public typealias ComboboxOption = RuneKit.ComboboxOption
    public typealias ComboboxState = RuneKit.ComboboxState
    public typealias Combobox = RuneKit.Combobox
}
