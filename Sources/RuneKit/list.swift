// Ported from: crates/rune-kit/src/list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! List (`@opencode/ui` components/list): an optional search field over grouped rows with an
//! active (highlighted) row, selected check and optional dividers.

import Rune

public struct ListItem {
    var labelVal: String
    var groupVal: String?
    var selectedFlag: Bool
    var actions: [(El) -> El]

    public init(_ label: String) {
        self.labelVal = label
        self.groupVal = nil
        self.selectedFlag = false
        self.actions = []
    }

    public static func new(_ label: String) -> ListItem {
        ListItem(label)
    }

    public func group(_ g: String) -> ListItem {
        var copy = self
        copy.groupVal = g
        return copy
    }

    public func selected(_ s: Bool) -> ListItem {
        var copy = self
        copy.selectedFlag = s
        return copy
    }

    public func onSelect<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> ListItem {
        var copy = self
        copy.actions.append { e in e.onPressTx(f) }
        return copy
    }
}

struct ListSearchSpec {
    var edit: TextEdit
    var placeholder: String
}

private struct ListGroupAccum {
    var name: String?
    var el: El
}

public struct List {
    var items: [ListItem]
    var searchSpec: ListSearchSpec?
    var activeIdx: Int?
    var dividerFlag: Bool
    var activeIconVal: Icon?
    var emptyText: String
    var addEl: El?
    var editHook: ((El) -> El)?

    public init() {
        self.items = []
        self.searchSpec = nil
        self.activeIdx = 0
        self.dividerFlag = false
        self.activeIconVal = nil
        self.emptyText = "No results"
        self.addEl = nil
        self.editHook = nil
    }

    public static func new() -> List {
        List()
    }

    public static var `default`: List {
        List()
    }

    public func item(_ i: ListItem) -> List {
        var copy = self
        copy.items.append(i)
        return copy
    }

    /// A search field bound to `edit` (filtering is the app's job).
    public func search(_ edit: TextEdit, _ placeholder: String) -> List {
        var copy = self
        copy.searchSpec = ListSearchSpec(edit: edit, placeholder: placeholder)
        return copy
    }

    // PORT NOTE: Supports `WritableKeyPath<S, TextEdit>`, `EditAccess<S>`, and scoped mutation
    // closures matching `Rune.El.onEdit`.
    public func onSearchEdit<S>(_ keyPath: WritableKeyPath<S, TextEdit>) -> List {
        onSearchEdit(EditAccess(keyPath))
    }

    public func onSearchEdit<S>(_ access: EditAccess<S>) -> List {
        var copy = self
        copy.editHook = { e in e.onEdit(access) }
        return copy
    }

    public func onSearchEdit<S>(_ f: @escaping (inout S, (inout TextEdit) -> Void) -> Void) -> List {
        onSearchEdit(EditAccess(f))
    }

    /// The highlighted row (keyboard focus); `nil` for none.
    public func active(_ i: Int?) -> List {
        var copy = self
        copy.activeIdx = i
        return copy
    }

    public func divider() -> List {
        var copy = self
        copy.dividerFlag = true
        return copy
    }

    /// An icon shown at the end of the active row.
    public func activeIcon(_ i: Icon) -> List {
        var copy = self
        copy.activeIconVal = i
        return copy
    }

    public func emptyMessage(_ m: String) -> List {
        var copy = self
        copy.emptyText = m
        return copy
    }

    /// A trailing row (e.g. "Add item").
    public func addRow(_ e: El) -> List {
        var copy = self
        copy.addEl = e
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let itemFont = TextStyle.new(14.0, 500.0).lh(21.0)
        var root = Rune.col().role("list").wFull().gap(12.0)
        if let search = searchSpec {
            var input = Rune.textInput(search.edit, TextStyle.new(14.0, 400.0).lh(20.0))
                .singleLine()
                .key("input")
                .grow(1.0)
                .shrink()
                .color(c.textStrong)
                .placeholder(search.placeholder, c.textWeak)
            if let f = editHook {
                input = f(input)
            }
            root = root.child(
                Rune.row().key("search-wrapper").wFull().mb(4.0).gap(8.0).centerY().child(
                    Rune.row()
                        .key("search")
                        .grow(1.0)
                        .padding(8.0)
                        .gap(8.0)
                        .centerY()
                        .radius(k.radius.md)
                        .fill(c.surfaceBase)
                        .child(Rune.icon(k.glyph.search, 16.0).color(c.stdIcon))
                        .child(input)
                )
            )
        }
        var scroll = Rune.col().key("scroll").wFull().gap(12.0)
        // Rows with an action are one Tab stop; arrows move between them (AppKit lists).
        if items.contains(where: { !$0.actions.isEmpty }) {
            scroll = scroll.role("listbox").focusGroup()
        }
        if items.isEmpty && addEl == nil {
            scroll = scroll.child(
                Rune.col()
                    .key("empty")
                    .wFull()
                    .px(48.0)
                    .py(32.0)
                    .center()
                    .child(Rune.text(emptyText).font(TextStyle.new(14.0, 400.0).lh(21.0)).color(c.textWeak))
            )
        }
        let n = items.count
        var groupEl: ListGroupAccum? = nil
        var groups: [El] = []
        for (i, item) in items.enumerated() {
            if groupEl == nil || groupEl?.name != item.groupVal {
                if let prev = groupEl {
                    groups.append(prev.el)
                }
                var g = Rune.col().key("group\(i)").wFull()
                if let name = item.groupVal {
                    g = g.child(
                        Rune.row().key("header").wFull().pt(8.0).pb(8.0).pl(8.0).pr(12.0).fill(c.surfaceRaised).child(
                            Rune.text(name).font(TextStyle.new(14.0, 500.0).lh(21.0)).color(c.textWeak)
                        )
                    )
                }
                groupEl = ListGroupAccum(name: item.groupVal, el: g)
            }
            let active = activeIdx == i
            let pressable = !item.actions.isEmpty
            var r = Rune.row()
                .key("item\(i)")
                .role("option")
                .label(item.labelVal)
                .wFull()
                .px(8.0)
                .py(6.0)
                .centerY()
                .radius(k.radius.md)
                .gap(4.0)
                .child(Rune.text(item.labelVal).font(itemFont).color(c.textStrong).shrink().truncate())
            if item.selectedFlag {
                r = r.child(Rune.icon(k.glyph.checkSmall, 16.0).color(c.stdIconStrong))
            }
            if active {
                r = r.fill(c.surfaceRaisedHover)
                if let ai = activeIconVal {
                    r = r.child(Rune.icon(ai, 16.0).color(c.stdIconStrong))
                }
            } else if pressable {
                r = r.focusHighlight(c.surfaceRaisedHover)
            } else {
                r = r.hover(c.surfaceRaisedHover)
            }
            if pressable {
                r = r.focusable(true).focusSelected(item.selectedFlag)
            }
            if dividerFlag && i + 1 < n {
                r = r.child(
                    Rune.el().key("divider").h(1.0).pin(16.0, nil, 16.0, 0.0).fill(c.borderWeak)
                )
            }
            for a in item.actions {
                r = a(r)
            }
            if var currentGroup = groupEl {
                currentGroup.el = currentGroup.el.child(r)
                groupEl = currentGroup
            }
        }
        if let finalGroup = groupEl {
            groups.append(finalGroup.el)
        }
        if let add = addEl {
            groups.append(Rune.col().key("add").wFull().child(add))
        }
        let count = groups.count
        for (i, g) in groups.enumerated() {
            scroll = scroll.child(i + 1 == count ? g.pb(12.0) : g)
        }
        return root.child(scroll)
    }
}

/// Namespace mirroring `rune_kit::list` module exports.
public enum list {
    public typealias ListItem = RuneKit.ListItem
    public typealias List = RuneKit.List
}
