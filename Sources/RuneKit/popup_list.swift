// Ported from: crates/rune-kit/src/popup_list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Anchored popup listbox (`PopupList` / `PopupItem`) for popovers filtered by an outside
//! field, such as a chat composer's `@`-mention and `/`-command popovers, and the shared list
//! inside ``Combobox``.

import Rune

/// Protocol matching Rust `Into<PopupItem>` so `PopupList.items` and `PopupList.item` accept
/// either `PopupItem` or `ComboboxOption`.
public protocol PopupItemConvertible {
    func intoPopupItem() -> PopupItem
}

/// One row in a ``PopupList``: `PopupItem.new("review", "/review").description("Review changes")`.
public struct PopupItem: PopupItemConvertible {
    var idVal: String
    var labelVal: String
    var descriptionVal: String?
    var leadingEl: El?
    var trailingEl: El?
    var disabledFlag: Bool

    public init(_ id: String, _ label: String) {
        self.idVal = id
        self.labelVal = label
        self.descriptionVal = nil
        self.leadingEl = nil
        self.trailingEl = nil
        self.disabledFlag = false
    }

    public init(_ option: ComboboxOption) {
        self = PopupItem(option.id, option.label)
            .description(option.detail)
            .disabled(option.disabled)
    }

    public static func new(_ id: String, _ label: String) -> PopupItem {
        PopupItem(id, label)
    }

    public func intoPopupItem() -> PopupItem {
        self
    }

    /// Secondary muted text shown after the label on the same row.
    public func description(_ text: String) -> PopupItem {
        var copy = self
        copy.descriptionVal = text.isEmpty ? nil : text
        return copy
    }

    /// Leading element before the label (an icon, avatar, or swatch).
    public func leading(_ el: El) -> PopupItem {
        var copy = self
        copy.leadingEl = el
        return copy
    }

    /// Trailing element at the right edge of the row (a keybind hint, badge, or check icon).
    public func trailing(_ el: El) -> PopupItem {
        var copy = self
        copy.trailingEl = el
        return copy
    }

    public func disabled(_ disabled: Bool) -> PopupItem {
        var copy = self
        copy.disabledFlag = disabled
        return copy
    }

    public func id() -> String {
        idVal
    }

    public func label() -> String {
        labelVal
    }

    public func isDisabled() -> Bool {
        disabledFlag
    }
}

/// An anchored popup listbox driven by an outside field:
/// `PopupList.new("mentions", "composer").open(s.open).items(items).active(s.active).build(k, &layer)`.
///
/// The popup takes no keyboard focus, so focus and typing stay in the app's field while it is
/// open. Moving `active` in app state scrolls the active option into view.
public struct PopupList<S> {
    var key: String
    var anchorKey: String
    var openFlag: Bool
    var sideVal: Side
    var alignVal: Align
    var gutterVal: Float
    var widthVal: Float
    var maxHeightVal: Float
    var paddingVal: Float
    var rowRadiusVal: Float
    var itemsList: [PopupItem]
    var animateFilteringFlag: Bool
    var activeVal: Int?
    var emptyText: String
    var labelText: String?
    var onActiveFn: ((inout S, Int) -> Void)?
    var onChooseFn: ((inout S, String, inout Tx) -> Void)?
    var onCloseFn: ((inout S) -> Void)?

    public init(_ key: String, _ anchor: String) {
        self.key = key
        self.anchorKey = anchor
        self.openFlag = true
        self.sideVal = .top
        self.alignVal = .start
        self.gutterVal = 4.0
        self.widthVal = 260.0
        self.maxHeightVal = 240.0
        self.paddingVal = 4.0
        self.rowRadiusVal = 4.0
        self.itemsList = []
        self.animateFilteringFlag = false
        self.activeVal = nil
        self.emptyText = "No results"
        self.labelText = nil
        self.onActiveFn = nil
        self.onChooseFn = nil
        self.onCloseFn = nil
    }

    public static func new(_ key: String, _ anchor: String) -> PopupList<S> {
        PopupList(key, anchor)
    }

    public func anchor(_ anchor: String) -> PopupList<S> {
        var copy = self
        copy.anchorKey = anchor
        return copy
    }

    /// Anchor to `anchor` with explicit side, alignment and offset, as `El.anchored`.
    public func anchored(_ anchor: String, _ side: Side, _ align: Align, _ gap: Float) -> PopupList<S> {
        var copy = self
        copy.anchorKey = anchor
        copy.sideVal = side
        copy.alignVal = align
        copy.gutterVal = gap
        return copy
    }

    public func placement(_ placement: Placement) -> PopupList<S> {
        var copy = self
        let (side, align) = placement.split()
        copy.sideVal = side
        copy.alignVal = align
        return copy
    }

    public func side(_ side: Side) -> PopupList<S> {
        var copy = self
        copy.sideVal = side
        return copy
    }

    public func align(_ align: Align) -> PopupList<S> {
        var copy = self
        copy.alignVal = align
        return copy
    }

    public func offset(_ gap: Float) -> PopupList<S> {
        var copy = self
        copy.gutterVal = gap
        return copy
    }

    public func gutter(_ gap: Float) -> PopupList<S> {
        var copy = self
        copy.gutterVal = gap
        return copy
    }

    public func open(_ open: Bool) -> PopupList<S> {
        var copy = self
        copy.openFlag = open
        return copy
    }

    public func width(_ width: Float) -> PopupList<S> {
        var copy = self
        copy.widthVal = width
        return copy
    }

    public func maxHeight(_ maxHeight: Float) -> PopupList<S> {
        var copy = self
        copy.maxHeightVal = maxHeight
        return copy
    }

    /// Space between the popover's edge and its rows, in points (default 4).
    public func padding(_ padding: Float) -> PopupList<S> {
        var copy = self
        copy.paddingVal = padding
        return copy
    }

    /// Corner radius of each row's highlight, in points (default 4).
    public func rowRadius(_ radius: Float) -> PopupList<S> {
        var copy = self
        copy.rowRadiusVal = radius
        return copy
    }

    /// The rows. A change lands at once: the popover takes its new height and rows appear and
    /// go in the same frame, even in a commit that animates the field the list follows (one
    /// with `animateEditLayout`). ``animateFiltering(_:)`` animates it instead.
    public func items<Items: Swift.Sequence>(_ items: Items) -> PopupList<S> where Items.Element: PopupItemConvertible {
        var copy = self
        copy.itemsList = items.map { $0.intoPopupItem() }
        return copy
    }

    /// Animate a change to the rows: the popover springs to its new height, and the rows it
    /// drops fade out where they stood (a 0.24 s spring) as the new ones fade in (0.3 s).
    /// Off by default, so a list that follows each keystroke swaps at once. Opening, closing
    /// and the hover highlight animate either way.
    public func animateFiltering(_ animate: Bool) -> PopupList<S> {
        var copy = self
        copy.animateFilteringFlag = animate
        return copy
    }

    public func item(_ item: some PopupItemConvertible) -> PopupList<S> {
        var copy = self
        copy.itemsList.append(item.intoPopupItem())
        return copy
    }

    public func active(_ active: Int?) -> PopupList<S> {
        var copy = self
        copy.activeVal = active
        return copy
    }

    public func emptyMessage(_ text: String) -> PopupList<S> {
        var copy = self
        copy.emptyText = text
        return copy
    }

    public func label(_ label: String) -> PopupList<S> {
        var copy = self
        copy.labelText = label
        return copy
    }

    public func onActive(_ f: @escaping (inout S, Int) -> Void) -> PopupList<S> {
        var copy = self
        copy.onActiveFn = f
        return copy
    }

    public func onChoose(_ f: @escaping (inout S, String, inout Tx) -> Void) -> PopupList<S> {
        var copy = self
        copy.onChooseFn = f
        return copy
    }

    public func onClose(_ f: @escaping (inout S) -> Void) -> PopupList<S> {
        var copy = self
        copy.onCloseFn = f
        return copy
    }

    func buildList(_ k: Kit) -> El {
        let active: Int? = {
            guard let i = activeVal, i >= 0, i < itemsList.count, !itemsList[i].disabledFlag else {
                return nil
            }
            return i
        }()
        var rows = Rune.col()
            .key("rows")
            .wFull()
            .growth(GrowthSpec())
            .virtualize(28.0)
            .revealSelected(true)
        for (i, option) in itemsList.enumerated() {
            let id = option.idVal
            let isActive = active == i
            var item = Rune.row()
                .key("\(key)-option-\(id)")
                .role("option")
                .label(option.labelVal)
                .focusSelected(isActive)
                .wFull()
                .h(28.0)
                .px(8.0)
                .gap(8.0)
                .centerY()
                .radius(rowRadiusVal)
                .transition(.opacity())
                .fill(isActive ? k.c.hover : Color.TRANSPARENT)
            if let leading = option.leadingEl {
                item = item.child(leading)
            }
            if let desc = option.descriptionVal, !desc.isEmpty {
                item = item
                    .child(Rune.text(option.labelVal).font(k.ty.uiCompact).color(k.c.textBase).shrink().truncate())
                    .child(Rune.text(desc).key("description").font(k.ty.uiCompact).color(k.c.textWeak).grow(1.0).shrink().truncate())
            } else {
                item = item.child(
                    Rune.text(option.labelVal).font(k.ty.uiCompact).color(k.c.textBase).grow(1.0).shrink().truncate()
                )
            }
            if let trailing = option.trailingEl {
                item = item.child(trailing)
            }
            if option.disabledFlag {
                item = item.dim(0.5).onPress { (_: inout S) in }
            } else {
                if let onActive = onActiveFn {
                    item = item.onHover { (s: inout S) in
                        onActive(&s, i)
                    }
                }
                if let onChoose = onChooseFn {
                    item = item.onPressTx { (s: inout S, tx: inout Tx) in
                        onChoose(&s, id, &tx)
                    }
                } else {
                    item = item.onPress { (_: inout S) in }
                }
            }
            rows = rows.child(item)
        }
        // The viewport and the empty state both stay mounted, so the popover's height springs
        // between them as the search edits it instead of swapping one box for the other.
        let empty = itemsList.isEmpty
        var viewport = Rune.col()
            .key("viewport")
            .role("listbox")
            .wFull()
            .h(min(Float(itemsList.count) * 28.0, maxHeightVal))
            .shrink()
            // A window too short for the list still shows one row to scroll.
            .minH(empty ? 0.0 : 28.0)
            .scroll(ScrollSpec(stickBottom: false))
            .scrollEdgeFade(OVERLAY_LIST_SCROLL_FADE)
            .scrollMargin(OVERLAY_LIST_SCROLL_FADE)
            .clipSoft(0.0)
            .child(rows)
        if let label = labelText {
            viewport = viewport.label(label)
        }
        return Rune.col()
            .key("list")
            .preserveFocusOnPress(true)
            .wFull()
            .shrink()
            .minH(0.0)
            .child(viewport)
            .child(
                Rune.el()
                    .key("empty")
                    .h(empty ? 28.0 : 0.0)
                    .px(8.0)
                    .centerY()
                    .clipSoft(0.0)
                    .opacity(empty ? 1.0 : 0.0)
                    .child(Rune.text(emptyText).font(k.ty.uiCompact).color(k.c.textWeak))
            )
    }

    public func build(_ k: Kit, _ layer: inout [El]) {
        if !openFlag {
            return
        }
        if let close = onCloseFn {
            layer.append(scrim("\(key)-scrim") { (s: inout S) in
                close(&s)
            })
        }
        let contentKey = "\(key)-content"
        let instant = !animateFilteringFlag
        let list = buildList(k)
        var content = Rune.col()
            .key(contentKey)
            .preserveFocusOnPress(true)
            .w(widthVal)
            .padding(paddingVal)
            .onPress { (_: inout S) in }
            .child(list)
        if instant {
            content = content.instantChanges()
        }
        layer.append(overlayAnchorAt(k, overlayRaised(k, content, k.radius.md), anchorKey, sideVal, alignVal, gutterVal))
    }
}

/// Namespace mirroring `rune_kit::popup_list` module exports.
public enum popupList {
    public typealias PopupItem = RuneKit.PopupItem
    public typealias PopupList = RuneKit.PopupList
}
