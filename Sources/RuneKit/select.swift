// Ported from: crates/rune-kit/src/select.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Select (`@opencode/ui` forms/select): an inline trigger and a listbox of menu items with a
//! check on the selected option, optionally grouped.

import Rune

/// The listbox's tallest: its 4-point padding, six 30-point rows (28 tall, 2 apart), and most
/// of the seventh, whose label shows fading under the edge.
private let LISTBOX_MAX_HEIGHT: Float = 4.0 + 6.0 * 30.0 + 22.0

public enum SelectAppearance: Sendable, Equatable, Hashable {
    /// The trigger the kit renders today: borderless, 24 points tall.
    case inline
    /// The 280 point field look (`data-appearance` unset).
    case field

    public init() {
        self = .inline
    }

    public static let `default`: SelectAppearance = .inline
}

/// `Select.new("fruit", fruits).current(s.fruit).open(..).onChoose { s, v, tx in .. }`.
public struct Select {
    var key: String
    var options: [(String?, String)]
    var detailsList: [String?]
    var widthVal: Float
    var currentVal: String?
    var placeholderText: String
    var openFlag: Bool
    var invalidFlag: Bool
    var stateVal: State
    var appearanceVal: SelectAppearance
    var highlightedVal: String?
    var placementVal: Placement
    var chooseFn: ((String, El) -> El)?
    var toggleFn: ((El) -> El)?
    var dismissSpec: (El, MenuModal)?

    public init(_ key: String, _ options: [String] = []) {
        self.key = key
        self.options = options.map { (nil, $0) }
        self.detailsList = []
        self.widthVal = 280.0
        self.currentVal = nil
        self.placeholderText = ""
        self.openFlag = false
        self.invalidFlag = false
        self.stateVal = .rest
        self.appearanceVal = .inline
        self.highlightedVal = nil
        self.placementVal = .bottomEnd
        self.chooseFn = nil
        self.toggleFn = nil
        self.dismissSpec = nil
    }

    public init<Options: Swift.Sequence>(_ key: String, _ options: Options) where Options.Element == String {
        self.init(key, Array(options))
    }

    public static func new(_ key: String, _ options: [String] = []) -> Select {
        Select(key, options)
    }

    public static func new<Options: Swift.Sequence>(_ key: String, _ options: Options) -> Select where Options.Element == String {
        Select(key, options)
    }

    /// Options under section headers: `(group, option)` pairs, in order.
    public static func grouped(_ key: String, _ options: [(String, String)]) -> Select {
        var s = Select(key, [])
        s.options = options.map { (g, o) in (g, o) }
        return s
    }

    /// Secondary text after each option (in option order; `nil` for none).
    public func details(_ d: [String?]) -> Select {
        var copy = self
        copy.detailsList = d
        return copy
    }

    /// The field trigger's width in points (default 280).
    public func width(_ w: Float) -> Select {
        var copy = self
        copy.widthVal = w
        return copy
    }

    public func current(_ c: String?) -> Select {
        var copy = self
        copy.currentVal = c
        return copy
    }

    public func placeholder(_ p: String) -> Select {
        var copy = self
        copy.placeholderText = p
        return copy
    }

    public func open(_ o: Bool) -> Select {
        var copy = self
        copy.openFlag = o
        return copy
    }

    public func invalid(_ i: Bool) -> Select {
        var copy = self
        copy.invalidFlag = i
        return copy
    }

    public func appearance(_ a: SelectAppearance) -> Select {
        var copy = self
        copy.appearanceVal = a
        return copy
    }

    /// The keyboard-highlighted option while open.
    public func highlighted(_ o: String?) -> Select {
        var copy = self
        copy.highlightedVal = o
        return copy
    }

    public func placement(_ p: Placement) -> Select {
        var copy = self
        copy.placementVal = p
        return copy
    }

    public func state(_ s: State) -> Select {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> Select {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    /// The trigger's press (open or close the listbox).
    public func onToggle<S>(_ f: @escaping (inout S) -> Void) -> Select {
        var copy = self
        copy.toggleFn = { e in e.onPress(f) }
        return copy
    }

    /// Presses outside and Escape close the listbox. While open it holds keyboard focus.
    public func onClose<S>(_ f: @escaping (inout S) -> Void) -> Select {
        var copy = self
        copy.dismissSpec = menuDismissal("\(key)-scrim", f)
        return copy
    }

    /// Choosing an option: `f(&state, option, &tx)`.
    public func onChoose<S>(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Select {
        var copy = self
        copy.chooseFn = { v, e in
            e.onPressTx { (s: inout S, tx: inout Tx) in
                f(&s, v, &tx)
            }
        }
        return copy
    }

    /// The field alone, for an app that opens its own menu or picker on press (`onToggle`):
    /// `open` still turns the chevron and highlights the field, but no listbox is built.
    public func trigger(_ k: Kit) -> El {
        field(k)
    }

    public func build(_ k: Kit, _ layer: inout [El]) -> El {
        let triggerEl = field(k)
        if stateVal == .disabled || !openFlag {
            return triggerEl
        }
        let c = k.c
        let anchorKey = "\(key)-trigger"
        let modal = menuMountDismiss(dismissSpec, &layer)
        // About six and three-quarter rows tall at most, so a longer list shows its next row's label
        // fading under the edge and reads as one that scrolls (hex#840); consecutive options
        // sit 2 points apart, headers flush.
        var list = Rune.col().key("rows").padding(4.0).itemsStretch()
        var group: String? = nil
        var afterItem = false
        for (i, (g, o)) in options.enumerated() {
            if g != group {
                group = g
                if let gName = group {
                    list = list.child(
                        Rune.row()
                            .key("group\(i)")
                            .h(28.0)
                            .px(12.0)
                            .centerY()
                            .child(Rune.text(gName).font(k.ty.smallMedium).color(c.textFaint))
                    )
                    afterItem = false
                }
            }
            let selected = currentVal == o
            var item = Rune.row()
                .key("option\(i)")
                .role("option")
                .focusable(true)
                .focusSelected(selected)
                .label(o)
                .h(28.0)
                .pl(12.0)
                .pr(6.0)
                .gap(8.0)
                .centerY()
                .radius(4.0)
                .mt(afterItem ? 2.0 : 0.0)
                .child(
                    Rune.text(o).key("label").font(k.ty.uiCompact).color(c.textBase).grow(1.0).shrink().truncate()
                )
                .child(
                    Rune.el().key("indicator").size(16.0, 16.0).center().child(
                        Rune.icon(k.glyph.checkSmall, 14.0).color(c.iconBase).opacity(selected ? 1.0 : 0.0)
                    )
                )
            if highlightedVal == o {
                item = item.fill(c.hover)
            } else {
                item = item.focusHighlight(c.hover)
            }
            if let choose = chooseFn {
                item = choose(o, item)
            }
            list = list.child(item)
            afterItem = true
        }
        var content = shadows(
            k,
            Rune.col()
                .key("\(key)-content")
                .focusReturn(anchorKey)
                .minW(160.0)
                .maxW(368.0)
                .radius(6.0)
                .fill(c.layer01)
                .child(
                    Rune.col()
                        .key("listbox")
                        .role("listbox")
                        .focusGroup()
                        .maxH(LISTBOX_MAX_HEIGHT)
                        .minH(0.0)
                        .shrink()
                        .child(overlayFitScroll(list))
                ),
            k.elevation.floating
        )
        if let modal = modal {
            content = modal(content)
        }
        layer.append(overlayMenuAnchor(k, content, anchorKey, placementVal, 2.0))
        return triggerEl
    }

    /// The closed or open field: label, chevron, and the press that toggles the listbox.
    private func field(_ k: Kit) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let anchorKey = "\(key)-trigger"
        let red = invalidFlag && !disabled && k.invalidText
        let (label, ink): (String, Color) = if let v = currentVal {
            (v, red ? c.danger.fg : c.textBase)
        } else {
            (placeholderText, red ? c.danger.fg : c.textFaint)
        }
        let chevron: Icon = openFlag ? k.glyph.chevronUp : k.glyph.chevronDown
        var triggerEl = Rune.row()
            .key(anchorKey)
            .role("combobox")
            .label(label)
            .centerY()
            .focusable(!disabled)
            .focusRing(1.0, 0.0, c.borderFocus)
        switch appearanceVal {
        case .inline:
            let font = k.ty.uiMedium.lh(16.0)
            let hover = stateVal == .hover || openFlag
            var t = triggerEl
                .h(24.0)
                .pl(8.0)
                .pr(4.0)
                .py(4.0)
                .gap(4.0)
                .radius(k.radius.sm)
                .child(Rune.text(label).key("value").font(font).color(ink).truncate())
                .child(Rune.icon(chevron, 16.0).key("chevron").color(c.iconMuted))
            if hover {
                t = t.fill(c.hover)
            } else if stateVal == .pressed {
                t = t.fill(c.pressed)
            } else if !disabled {
                t = t.hover(c.hover).press(pressOver(c.hover, c.pressed))
            }
            triggerEl = t
        case .field:
            var t = triggerEl
                .w(widthVal)
                .h(28.0)
                .pr(6.0)
                .gap(8.0)
                .radius(k.radius.md)
                .fill(openFlag || stateVal == .hover ? over(c.hover, c.bgBase) : c.bgBase)
                .gradient(k.light(0.02), k.light(0.0))
                .child(
                    Rune.row()
                        .key("value")
                        .grow(1.0)
                        .shrink()
                        .pl(8.0)
                        .child(Rune.text(label).font(k.ty.uiCompact).color(ink).truncate())
                )
                .child(
                    Rune.el().size(20.0, 20.0).center().child(
                        Rune.icon(chevron, 16.0).key("chevron").color(c.iconMuted)
                    )
                )
            if invalidFlag && !disabled {
                t = t.outline(1.0, 0.0, c.danger.fg)
            } else if stateVal == .focus && !openFlag {
                t = t.outline(1.0, 0.0, c.borderFocus)
            } else {
                t = shadows(k, t, k.elevation.buttonNeutral)
                if stateVal == .rest && !openFlag {
                    t = t.hover(c.hover)
                }
            }
            triggerEl = t
        }
        if disabled {
            return triggerEl.dim(0.5)
        }
        if let f = toggleFn {
            triggerEl = f(triggerEl)
        }
        return triggerEl
    }
}

/// Namespace mirroring `rune_kit::select` module exports.
public enum select {
    public typealias SelectAppearance = RuneKit.SelectAppearance
    public typealias Select = RuneKit.Select
}
