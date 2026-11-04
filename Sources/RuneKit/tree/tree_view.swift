// Ported from: crates/rune-kit/src/tree/view.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Rune

/// What a standard tree row shows after its indent and chevron: an icon, a label and trailing
/// content (change counts, a status dot, a badge, or any element).
public struct TreeItem {
    private var labelText: String
    private var iconGlyph: Icon? = nil
    private var iconColorValue: Color? = nil
    private var labelColorValue: Color? = nil
    private var highlightQuery: String? = nil
    private var changesValue: (UInt32, UInt32)? = nil
    private var dotColor: Color? = nil
    private var badgeText: String? = nil
    private var trailingEls: [El] = []

    public init(_ label: String) {
        self.labelText = label
    }

    public static func new(_ label: String) -> TreeItem {
        TreeItem(label)
    }

    /// A file tree's row: the node's name and its folder or file icon (``fileIcon(_:)``).
    public static func file<D>(_ node: FileNode<D>, _ row: TreeRow) -> TreeItem {
        TreeItem(node.name).icon(node.icon(row.expanded == true))
    }

    public func icon(_ i: Icon) -> TreeItem {
        var copy = self
        copy.iconGlyph = i
        return copy
    }

    public func iconColor(_ c: Color) -> TreeItem {
        var copy = self
        copy.iconColorValue = c
        return copy
    }

    /// The label's colour (the theme's text colour by default): dimmed for an ignored file, say.
    public func labelColor(_ c: Color) -> TreeItem {
        var copy = self
        copy.labelColorValue = c
        return copy
    }

    /// Marks the first case-insensitive occurrence of `query` in the label, as a search does.
    public func highlight(_ query: String) -> TreeItem {
        var copy = self
        copy.highlightQuery = query.isEmpty ? nil : query
        return copy
    }

    /// Lines added and removed, as `+12 −3` (a zero side is left out; both zero shows nothing).
    public func changes(_ added: UInt32, _ removed: UInt32) -> TreeItem {
        var copy = self
        copy.changesValue = (added > 0 || removed > 0) ? (added, removed) : nil
        return copy
    }

    /// A small status dot at the end of the row.
    public func dot(_ c: Color) -> TreeItem {
        var copy = self
        copy.dotColor = c
        return copy
    }

    /// A short status letter or count at the end of the row (`M`, `3`).
    public func badge(_ b: String) -> TreeItem {
        var copy = self
        copy.badgeText = b
        return copy
    }

    /// Any element at the end of the row.
    public func trailing(_ e: El) -> TreeItem {
        var copy = self
        copy.trailingEls.append(e)
        return copy
    }

    /// The row as ``Tree`` draws it, without handlers: indent guides, chevron, icon, label and
    /// trailing content, `style.rowHeight` tall. A sidebar can draw its rows with this.
    public func build(_ k: Kit, _ r: TreeRow, _ style: TreeStyle) -> El {
        let c = k.c
        let pad = style.padding
        let chevronW: Float = 16.0
        var e = Rune.row()
            .role("treeitem")
            .label(labelText)
            .level(r.depth + 1)
            .focusSelected(r.selected)
            .wFull()
            .h(style.rowHeight)
            .pl(pad + Float(r.depth) * style.indent)
            .pr(pad)
            .gap(4.0)
            .centerY()
            .radius(k.radius.sm)
            .motion(k.motion.control)
        if let open = r.expanded {
            e = e.expanded(open)
        }
        e = r.selected ? e.fill(style.selected) : e.hover(c.hover)
        if r.cursor && r.multi {
            e = e.outline(1.0, -1.0, c.borderFocus)
        }
        if style.guides {
            for level in 0..<r.depth {
                let x = pad + Float(level) * style.indent + chevronW * 0.5 - 0.5
                e = e.child(
                    Rune.el()
                        .key("guide\(level)")
                        .pin(x, 0.0, nil, 0.0)
                        .w(1.0)
                        .fill(style.guide)
                )
            }
        }
        let chevron = Rune.el().key("chevron").size(chevronW, chevronW).center()
        if let open = r.expanded {
            e = e.child(
                chevron.child(
                    Rune.icon(k.glyph.chevronDown, 16.0)
                        .key("glyph")
                        .color(c.iconMuted)
                        .iconRotation(open ? 0.0 : -Float.pi * 0.5)
                        .motion(k.motion.control)
                )
            )
        } else {
            e = e.child(chevron)
        }
        if let i = iconGlyph {
            e = e.child(
                Rune.icon(i, 16.0)
                    .key("icon")
                    .color(iconColorValue ?? c.iconMuted)
            )
        }
        let color = labelColorValue ?? c.textBase
        let font = k.ty.ui
        let spans: [Span]
        if let q = highlightQuery, let (a, b) = findCi(labelText, q) {
            spans = [
                Span(
                    start: a,
                    end: b,
                    weight: 650.0,
                    color: c.textBase,
                    bg: k.alpha(c.textAccent, 0.22),
                    bgPad: 1.0
                )
            ]
        } else {
            spans = []
        }
        let full = labelText
        let labelEl = spans.isEmpty ? Rune.text(labelText) : Rune.rich(labelText, spans)
        e = e.child(
            labelEl
                .key("label")
                .font(font)
                .color(color)
                .grow(1.0)
                .shrink()
                .minW(0.0)
                .truncate()
                .helpWhenTruncated(full)
        )
        if let (add, del) = changesValue {
            var counts = Rune.row().key("changes").gap(4.0).centerY()
            let f = k.ty.textXsmall.features("'tnum' 1")
            if add > 0 {
                counts = counts.child(Rune.text("+\(add)").key("added").font(f).color(c.success.icon))
            }
            if del > 0 {
                counts = counts.child(Rune.text("\u{2212}\(del)").key("removed").font(f).color(c.danger.icon))
            }
            e = e.child(counts)
        }
        if let b = badgeText {
            e = e.child(Rune.text(b).key("badge").font(k.ty.textXsmallMedium).color(c.textMuted))
        }
        if let d = dotColor {
            e = e.child(Rune.el().key("dot").size(6.0, 6.0).radius(3.0).fill(d).ml(5.0).mr(5.0))
        }
        return e.children(trailingEls)
    }
}

/// The byte range of `q` in `s`, ignoring ASCII case.
private func findCi(_ s: String, _ q: String) -> (Int, Int)? {
    let sl = s.lowercased()
    let ql = q.lowercased()
    // Lowercasing can change byte lengths outside ASCII; only trust a same-length mapping.
    if sl.utf8.count != s.utf8.count {
        return findUtf8Bytes(Array(s.utf8), Array(q.utf8))
    }
    return findUtf8Bytes(Array(sl.utf8), Array(ql.utf8))
}

private func findUtf8Bytes(_ haystack: [UInt8], _ needle: [UInt8]) -> (Int, Int)? {
    if needle.isEmpty {
        return (0, 0)
    }
    guard needle.count <= haystack.count else {
        return nil
    }
    let limit = haystack.count - needle.count
    for i in 0...limit {
        if haystack[i..<(i + needle.count)].elementsEqual(needle) {
            return (i, i + needle.count)
        }
    }
    return nil
}

/// A tree's metrics and colours. ``TreeStyle/fromKit(_:)`` takes them from the theme.
public struct TreeStyle: Sendable, Equatable {
    public var rowHeight: Float
    /// Points each level steps in.
    public var indent: Float
    /// Space at the row's ends.
    public var padding: Float
    /// Hairlines down each level's indent.
    public var guides: Bool
    public var guide: Color
    public var selected: Color

    public init(
        rowHeight: Float,
        indent: Float,
        padding: Float,
        guides: Bool,
        guide: Color,
        selected: Color
    ) {
        self.rowHeight = rowHeight
        self.indent = indent
        self.padding = padding
        self.guides = guides
        self.guide = guide
        self.selected = selected
    }

    public static func fromKit(_ k: Kit) -> TreeStyle {
        TreeStyle(
            rowHeight: 24.0,
            indent: 14.0,
            padding: 6.0,
            guides: true,
            guide: k.c.borderMuted,
            selected: k.alpha(k.c.textAccent, k.dark ? 0.24 : 0.2)
        )
    }
}

/// A virtualised tree over a ``TreeModel`` in the app's state `S`.
public struct Tree<S, T> {
    private let getModel: (S) -> TreeModel<T>
    private let mutateModel: (inout S, (inout TreeModel<T>) -> Void) -> Void
    private let labelFn: (T) -> String
    private var rowFn: ((T, TreeRow) -> TreeItem)? = nil
    private var onSelectFn: ((inout S, String, inout Tx) -> Void)? = nil
    private var onOpenFn: ((inout S, String, inout Tx) -> Void)? = nil
    private var styleOverride: TreeStyle? = nil
    private var nameValue: String? = nil

    // PORT NOTE: `WritableKeyPath` (in-place mutation) and `(get, set)` overloads replace Rust's
    // `(fn(&S) -> &TreeModel<T>, fn(&mut S) -> &mut TreeModel<T>)`.
    public init(
        _ model: WritableKeyPath<S, TreeModel<T>>,
        _ label: @escaping (T) -> String
    ) {
        self.getModel = { $0[keyPath: model] }
        self.mutateModel = { s, body in body(&s[keyPath: model]) }
        self.labelFn = label
    }

    public init(
        _ get: @escaping (S) -> TreeModel<T>,
        _ set: @escaping (inout S, TreeModel<T>) -> Void,
        _ label: @escaping (T) -> String
    ) {
        self.getModel = get
        self.mutateModel = { s, body in
            var m = get(s)
            body(&m)
            set(&s, m)
        }
        self.labelFn = label
    }

    public static func new(
        _ model: WritableKeyPath<S, TreeModel<T>>,
        _ label: @escaping (T) -> String
    ) -> Tree<S, T> {
        Tree(model, label)
    }

    public static func new(
        _ get: @escaping (S) -> TreeModel<T>,
        _ set: @escaping (inout S, TreeModel<T>) -> Void,
        _ label: @escaping (T) -> String
    ) -> Tree<S, T> {
        Tree(get, set, label)
    }

    /// What each row shows; by default its label alone.
    public func row(_ f: @escaping (T, TreeRow) -> TreeItem) -> Tree<S, T> {
        var copy = self
        copy.rowFn = f
        return copy
    }

    /// The cursor moved to `id`, by click or key: a diff view can follow it.
    public func onSelect(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Tree<S, T> {
        var copy = self
        copy.onSelectFn = f
        return copy
    }

    /// A row without children was double-clicked, or Return or Space pressed on it.
    public func onOpen(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Tree<S, T> {
        var copy = self
        copy.onOpenFn = f
        return copy
    }

    public func style(_ s: TreeStyle) -> Tree<S, T> {
        var copy = self
        copy.styleOverride = s
        return copy
    }

    /// The tree's accessibility label ("Files").
    public func name(_ n: String) -> Tree<S, T> {
        var copy = self
        copy.nameValue = n
        return copy
    }

    /// The tree, filling the height its parent gives it (set one with `.h(..)` or `.grow(..)`).
    public func build(_ s: S, _ k: Kit) -> El {
        let get = getModel
        let mutate = mutateModel
        let label = labelFn
        let rowBuilder = rowFn
        let onSelect = onSelectFn
        let onOpen = onOpenFn
        let resolvedStyle = styleOverride ?? TreeStyle.fromKit(k)
        let model = get(s)
        let count = model.visibleLen()
        let treeKey = model.keyName
        let kit = k

        let buildRow: (S, Int) -> El = { s, i in
            let m = get(s)
            guard let (data, r) = m.row(i) else {
                return Rune.el()
            }
            let item: TreeItem
            if let f = rowBuilder {
                item = f(data, r)
            } else {
                item = TreeItem.new(label(data))
            }
            let id = r.id
            let openable = r.expanded != nil
            var e = item.build(kit, r, resolvedStyle).key(r.id)
            // A click selects the row (Shift extends and Cmd toggles, in a multi-select tree);
            // on a folder it also opens or closes it, as a file tree's does.
            let pick = id
            e = e.onPressTx { (s: inout S, tx: inout Tx) in
                mutate(&s) { m in
                    let plain = m.click(pick, tx.mods())
                    if openable && plain {
                        m.toggle(pick)
                    }
                }
                if let f = onSelect {
                    f(&s, pick, &tx)
                }
            }
            if !openable, let f = onOpen {
                e = e.onDoublePressTx { (s: inout S, tx: inout Tx) in
                    f(&s, id, &tx)
                }
            }
            return e
        }

        var rows = Rune.col()
            .key("rows")
            .wFull()
            .growth(GrowthSpec())
            .virtualRows(
                count,
                resolvedStyle.rowHeight,
                { (s: S, i: Int) in get(s).visibleId(i) ?? "" },
                buildRow
            )
        // PORT NOTE: Until `Sources/Rune/runtime/commit/commit_flatten.swift` expands `El.virtualRowsSource`
        // directly during layout, materialize keyed rows into `children` for bounded trees (`<= 1_024` rows)
        // so `Tree` renders and interactive hit/selection/disclosure behavior works in `Runtime`.
        if count <= 1_024 {
            var builtChildren: [El] = []
            builtChildren.reserveCapacity(count)
            for i in 0..<count {
                builtChildren.append(buildRow(s, i))
            }
            rows = rows.children(builtChildren)
        }

        let viewport = Rune.col()
            .key("viewport")
            .wFull()
            .grow(1.0)
            .minH(0.0)
            .scroll(ScrollSpec(stickBottom: false))
            // Inside a scrolling page this reports every frame of the scroll; only a new height
            // changes what the view reads.
            .onLayoutTx { (s: inout S, r: [Float], tx: inout Tx) in
                guard r.count >= 4 else { return }
                mutate(&s) { m in
                    if m.viewport == r[3] && m.rowHeight == resolvedStyle.rowHeight {
                        tx.liveOnly()
                    }
                    m.viewport = r[3]
                    m.rowHeight = resolvedStyle.rowHeight
                }
            }
            .child(rows)

        var root = Rune.col()
            .key(treeKey)
            .role("tree")
            .focusable(true)
            .wFull()
        if let n = nameValue {
            root = root.label(n)
        }
        return root
            .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
                var before: Int? = nil
                var after: Int? = nil
                var afterId: String? = nil
                var out: TreeKey = .ignored
                mutate(&s) { m in
                    before = m.cursorIdx
                    out = m.handleKey(ev, label, &tx)
                    after = m.cursorIdx
                    afterId = after.map { m.nodes[$0].id }
                }
                switch out {
                case .ignored:
                    return false
                case .handled:
                    if before != after, let f = onSelect, let id = afterId {
                        f(&s, id, &tx)
                    }
                    return true
                case .open(let id):
                    if let f = onOpen {
                        f(&s, id, &tx)
                    }
                    return true
                }
            }
            .child(viewport)
    }
}
