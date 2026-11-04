// Ported from: crates/rune-kit/src/table.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Table: a virtualised data table over rows the app keeps, with a sticky header, sortable and
//! resizable columns, row selection and keyboard navigation.
//!
//! The app owns the rows and their order; ``TableState`` in its state keeps what the table adds
//! (the sort shown in the header, columns the user resized, the selection and the keyboard
//! cursor). Only the rows on screen are built (`El.virtualRows`), so 100,000 rows cost what
//! the visible thirty do. A header click sets the sort and calls ``Table/onSort(_:)``, where the
//! app reorders its rows. Dragging a header's right edge resizes its column within its
//! ``TableColumn/min(_:)`` and ``TableColumn/max(_:)``; a double click on the edge puts it
//! back. The table is one focus stop: Up and Down move the selection, Home and End and Page Up
//! and Page Down jump, Return opens, and with ``TableState/multiSelect(_:)`` Shift extends,
//! Cmd-click toggles and Cmd-A selects every row.

import Rune

/// Three-way comparison result mirroring Rust's `std::cmp::Ordering`.
// PORT NOTE: Defined without Foundation (`ComparisonResult`) so `RuneKit` compiles cleanly on WASI.
public enum Ordering: Int, Sendable, Equatable, Hashable, Comparable {
    case less = -1
    case equal = 0
    case greater = 1

    public static func < (lhs: Ordering, rhs: Ordering) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func compare<T: Comparable>(_ a: T, _ b: T) -> Ordering {
        if a < b { return .less }
        if a > b { return .greater }
        return .equal
    }

    public func reverse() -> Ordering {
        switch self {
        case .less: return .greater
        case .equal: return .equal
        case .greater: return .less
        }
    }

    public func thenWith(_ next: () -> Ordering) -> Ordering {
        self == .equal ? next() : self
    }
}

/// Which way a column sorts.
public enum SortDir: Sendable, Equatable, Hashable {
    case ascending
    case descending

    public func flip() -> SortDir {
        switch self {
        case .ascending: return .descending
        case .descending: return .ascending
        }
    }

    /// Applies the direction to an ascending comparison.
    public func apply(_ o: Ordering) -> Ordering {
        switch self {
        case .ascending: return o
        case .descending: return o.reverse()
        }
    }

    /// Strict-weak-ordering predicate suitable for Swift's `Array.sort(by:)`.
    public func ordered<T: Comparable>(_ a: T, _ b: T) -> Bool {
        apply(Ordering.compare(a, b)) == .less
    }
}

private enum ColumnWidth: Sendable, Equatable {
    case fixed(Float)
    case flex(Float)
}

/// A column: its id (what ``Table/cell(_:)`` and ``Table/onSort(_:)`` receive), header title, width,
/// alignment and whether it sorts and resizes.
public struct TableColumn: Sendable, Equatable {
    fileprivate var idValue: String
    fileprivate var title: String
    fileprivate var widthPolicy: ColumnWidth
    fileprivate var minWidth: Float
    fileprivate var maxWidth: Float
    fileprivate var alignValue: Align
    fileprivate var sortableFlag: Bool
    fileprivate var resizableFlag: Bool

    /// A column sharing the free width with the other flex columns (weight 1), at least 48
    /// points wide, resizable and not sortable.
    public init(_ id: String, _ title: String) {
        self.idValue = id
        self.title = title
        self.widthPolicy = .flex(1.0)
        self.minWidth = 48.0
        self.maxWidth = .infinity
        self.alignValue = .start
        self.sortableFlag = false
        self.resizableFlag = true
    }

    /// A column sharing the free width with the other flex columns (weight 1), at least 48
    /// points wide, resizable and not sortable.
    public static func new(_ id: String, _ title: String) -> TableColumn {
        TableColumn(id, title)
    }

    /// A fixed width in points.
    public func width(_ w: Float) -> TableColumn {
        var copy = self
        copy.widthPolicy = .fixed(Swift.max(w, 0.0))
        return copy
    }

    /// A share of the width the fixed columns leave, by weight (1 by default).
    public func flex(_ weight: Float) -> TableColumn {
        var copy = self
        copy.widthPolicy = .flex(Swift.max(weight, 0.0))
        return copy
    }

    /// The narrowest the column gets, by layout or by dragging.
    public func min(_ w: Float) -> TableColumn {
        var copy = self
        copy.minWidth = Swift.max(w, 0.0)
        return copy
    }

    /// The widest the column gets.
    public func max(_ w: Float) -> TableColumn {
        var copy = self
        copy.maxWidth = Swift.max(w, 0.0)
        return copy
    }

    /// Where cells and the title sit: numbers read best at the end.
    public func align(_ a: Align) -> TableColumn {
        var copy = self
        copy.alignValue = a
        return copy
    }

    /// A header click sorts by this column.
    public func sortable() -> TableColumn {
        var copy = self
        copy.sortableFlag = true
        return copy
    }

    /// Whether dragging the header's edge resizes the column (on by default).
    public func resizable(_ on: Bool) -> TableColumn {
        var copy = self
        copy.resizableFlag = on
        return copy
    }

    public func id() -> String {
        idValue
    }

    /// `w` within the column's min and max.
    public func clamp(_ w: Float) -> Float {
        Swift.min(Swift.max(w, minWidth), Swift.max(maxWidth, minWidth))
    }
}

/// A cell's content: text that truncates (its whole text shows as a tooltip when cut short), or
/// any element.
public struct Cell: ExpressibleByStringLiteral {
    fileprivate enum Content {
        case text(String)
        case el(El)
    }

    fileprivate var content: Content
    fileprivate var colorValue: Color?
    fileprivate var monoFlag: Bool
    fileprivate var mutedFlag: Bool

    public init(_ t: String) {
        self.content = .text(t)
        self.colorValue = nil
        self.monoFlag = false
        self.mutedFlag = false
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    private init(content: Content) {
        self.content = content
        self.colorValue = nil
        self.monoFlag = false
        self.mutedFlag = false
    }

    public static func text(_ t: String) -> Cell {
        Cell(t)
    }

    public static func el(_ e: El) -> Cell {
        Cell(content: .el(e))
    }

    /// The monospaced face with tabular digits, for ids, hashes and sizes.
    public func mono() -> Cell {
        var copy = self
        copy.monoFlag = true
        return copy
    }

    /// The theme's secondary text colour.
    public func muted() -> Cell {
        var copy = self
        copy.mutedFlag = true
        return copy
    }

    public func color(_ c: Color) -> Cell {
        var copy = self
        copy.colorValue = c
        return copy
    }
}

// PORT NOTE: Reference box for `cursor_hint` / `anchor_hint` (`std::cell::Cell<usize>` in upstream)
// so O(1) index hints update across non-mutating reads without requiring `inout` state borrows.
private final class IndexHint {
    var value: Int = 0
}

private enum ResizeStart: Equatable {
    case idle
    case active(Float?)
}

/// What the table adds to the app's rows, kept in the app's state: the sort, resized columns,
/// the selection and the keyboard cursor. Rows are named by the ids ``Table``'s `rowId`
/// gives, so the selection follows a row through a re-sort.
public struct TableState {
    fileprivate var keyValue: String
    fileprivate var multi: Bool
    fileprivate var sortValue: (String, SortDir)?
    fileprivate var widths: [String: Float]
    /// Each column's laid-out width, for starting a drag.
    fileprivate var laidOut: [String: Float]
    fileprivate var resizeStart: ResizeStart
    fileprivate var selectedSet: Set<String>
    fileprivate var cursorValue: String?
    /// Where the cursor's row was last seen, to find it again without a scan.
    private var cursorHint: IndexHint
    fileprivate var anchorValue: String?
    /// Where the anchor's row was last seen, to extend selections without a scan.
    private var anchorHint: IndexHint
    fileprivate var viewport: Float
    fileprivate var rowHeight: Float

    public init() {
        self.keyValue = "table"
        self.multi = false
        self.sortValue = nil
        self.widths = [:]
        self.laidOut = [:]
        self.resizeStart = .idle
        self.selectedSet = []
        self.cursorValue = nil
        self.cursorHint = IndexHint()
        self.anchorValue = nil
        self.anchorHint = IndexHint()
        self.viewport = 0.0
        self.rowHeight = 28.0
    }

    public static func new() -> TableState {
        TableState()
    }

    /// The table's element key (`"table"` by default). Its rows are keyed by id inside it, and
    /// ``reveal(_:_:)`` looks for the row there, so give each table on screen its own.
    public func key(_ key: String) -> TableState {
        var copy = self
        copy.keyValue = key
        return copy
    }

    /// Several rows can be selected (Shift, Cmd-click, Cmd-A).
    public func multiSelect(_ on: Bool) -> TableState {
        var copy = self
        copy.multi = on
        return copy
    }

    /// The sort the header shows: a column id and direction.
    public func sort() -> (String, SortDir)? {
        sortValue
    }

    public mutating func setSort(_ column: String, _ dir: SortDir) {
        sortValue = (column, dir)
    }

    public mutating func clearSort() {
        sortValue = nil
    }

    /// What a click on `column`'s header sorts by: the other way if it's the sort column,
    /// otherwise ascending.
    public func nextSort(_ column: String) -> SortDir {
        if let (c, d) = sortValue, c == column {
            return d.flip()
        }
        return .ascending
    }

    /// The width the user gave `column` by dragging, if any.
    public func columnWidth(_ column: String) -> Float? {
        widths[column]
    }

    /// Sets `column`'s width as a drag does (the table clamps it to the column's bounds).
    public mutating func setColumnWidth(_ column: String, _ w: Float) {
        widths[column] = w
    }

    /// Puts `column` back to its declared width.
    public mutating func resetColumnWidth(_ column: String) {
        widths.removeValue(forKey: column)
    }

    public func selected() -> Set<String> {
        selectedSet
    }

    public func selectedLen() -> Int {
        selectedSet.count
    }

    public func isSelected(_ id: String) -> Bool {
        selectedSet.contains(id)
    }

    /// The keyboard cursor's row.
    public func cursor() -> String? {
        cursorValue
    }

    /// Selects `id` alone and puts the cursor on it.
    public mutating func select(_ id: String) {
        selectedSet.removeAll(keepingCapacity: true)
        selectedSet.insert(id)
        cursorValue = id
        anchorValue = id
    }

    public mutating func clearSelection() {
        selectedSet.removeAll()
    }

    /// Selects `id` and scrolls its row into view.
    public mutating func reveal(_ id: String, _ tx: inout Tx) {
        tx.scrollIntoViewIn(keyValue, id)
        select(id)
    }

    private static func findAt(
        _ id: String,
        _ hint: IndexHint,
        _ len: Int,
        _ idAt: (Int) -> String
    ) -> Int? {
        let h = hint.value
        if h >= 0 && h < len && idAt(h) == id {
            return h
        }
        for i in 0..<len where idAt(i) == id {
            hint.value = i
            return i
        }
        return nil
    }

    /// The cursor's row index among `len` rows.
    private func cursorRow(_ len: Int, _ idAt: (Int) -> String) -> Int? {
        guard let cur = cursorValue else { return nil }
        return Self.findAt(cur, cursorHint, len, idAt)
    }

    private func anchorRow(_ len: Int, _ idAt: (Int) -> String) -> Int? {
        guard let anc = anchorValue else { return nil }
        return Self.findAt(anc, anchorHint, len, idAt)
    }

    /// A click on row `i` with `mods`, as ``Table`` handles it.
    fileprivate mutating func click(_ i: Int, _ len: Int, _ mods: Mods, _ idAt: (Int) -> String) {
        let id = idAt(i)
        if multi && mods.shift {
            extend(i, len, idAt)
            return
        }
        cursorHint.value = i
        anchorHint.value = i
        if multi && mods.cmd {
            if selectedSet.remove(id) == nil {
                selectedSet.insert(id)
            }
            cursorValue = id
            anchorValue = id
            return
        }
        select(id)
    }

    /// Selects from the anchor to row `i`.
    private mutating func extend(_ i: Int, _ len: Int, _ idAt: (Int) -> String) {
        let anchor: Int
        if let existing = anchorRow(len, idAt) {
            anchor = existing
        } else {
            anchorValue = idAt(i)
            anchorHint.value = i
            anchor = i
        }
        let a = Swift.min(anchor, i)
        let b = Swift.max(anchor, i)
        var next: Set<String> = []
        next.reserveCapacity(b - a + 1)
        for j in a...b {
            next.insert(idAt(j))
        }
        selectedSet = next
        cursorValue = idAt(i)
        cursorHint.value = i
    }

    /// Applies a key to `len` rows named by `idAt`.
    fileprivate mutating func handleKey(
        _ ev: KeyEvent,
        _ len: Int,
        _ idAt: (Int) -> String,
        _ tx: inout Tx
    ) -> TableKeyOutcome {
        let m = ev.mods
        if len == 0 || m.alt || (m.ctrl && !m.cmd) || (m.logo && !m.cmd) {
            return .ignored
        }
        if ev.isCommand("a") && multi {
            var next: Set<String> = []
            next.reserveCapacity(len)
            for i in 0..<len {
                next.insert(idAt(i))
            }
            selectedSet = next
            return .handled
        }
        if m.cmd {
            return .ignored
        }
        let at = cursorRow(len, idAt)
        let floored = Int((viewport / Swift.max(rowHeight, 1.0)).rounded(.down))
        let page = Swift.max(Swift.max(floored - 1, 0), 1)
        let target: Int
        switch ev.key {
        case .up:
            target = at.map { Swift.max($0 - 1, 0) } ?? (len - 1)
        case .down:
            target = at.map { Swift.min($0 + 1, len - 1) } ?? 0
        case .home:
            target = 0
        case .end:
            target = len - 1
        case .pageUp:
            target = at.map { Swift.max($0 - page, 0) } ?? 0
        case .pageDown:
            target = at.map { Swift.min($0 + page, len - 1) } ?? 0
        case .enter:
            guard let r = at else { return .ignored }
            return tx.keyRepeat() ? .handled : .open(r)
        case .escape where multi && selectedSet.count > 1:
            if let r = at {
                cursorHint.value = r
                anchorHint.value = r
                select(idAt(r))
            } else {
                clearSelection()
            }
            return .handled
        default:
            return .ignored
        }

        let before = cursorValue
        if m.shift && multi {
            extend(target, len, idAt)
        } else {
            cursorHint.value = target
            anchorHint.value = target
            select(idAt(target))
        }
        tx.scrollIntoViewIn(keyValue, idAt(target))
        return cursorValue != before ? .moved : .handled
    }
}

private enum TableKeyOutcome {
    case ignored
    case handled
    case moved
    case open(Int)
}

/// A table's metrics and colours. ``TableStyle/fromKit(_:)`` takes them from the theme;
/// `MarkdownStyle.tableLike` draws Markdown tables with the same font, padding and rules.
public struct TableStyle: Sendable, Equatable {
    public var rowHeight: Float
    public var headerHeight: Float
    /// Space either side of a cell's content.
    public var cellPad: Float
    public var font: TextStyle
    public var mono: TextStyle
    public var headerFont: TextStyle
    public var text: Color
    public var muted: Color
    public var headerText: Color
    /// The rule under the header and between header cells.
    public var rule: Color
    public var selected: Color
    /// Every other row's fill, when striped (``Table/zebra(_:)``).
    public var stripe: Color

    public init(
        rowHeight: Float,
        headerHeight: Float,
        cellPad: Float,
        font: TextStyle,
        mono: TextStyle,
        headerFont: TextStyle,
        text: Color,
        muted: Color,
        headerText: Color,
        rule: Color,
        selected: Color,
        stripe: Color
    ) {
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.cellPad = cellPad
        self.font = font
        self.mono = mono
        self.headerFont = headerFont
        self.text = text
        self.muted = muted
        self.headerText = headerText
        self.rule = rule
        self.selected = selected
        self.stripe = stripe
    }

    public static func fromKit(_ k: Kit) -> TableStyle {
        let c = k.c
        return TableStyle(
            rowHeight: 28.0,
            headerHeight: 30.0,
            cellPad: 10.0,
            font: k.ty.textSmall,
            mono: k.ty.mono.features("'tnum' 1"),
            headerFont: k.ty.textSmallMedium,
            text: c.textBase,
            muted: c.textMuted,
            headerText: c.textMuted,
            rule: c.borderWeak,
            selected: k.alpha(c.textAccent, k.dark ? 0.24 : 0.2),
            stripe: k.alpha(c.textBase, k.dark ? 0.035 : 0.03)
        )
    }
}

/// A virtualised table over the app's rows in its state `S`.
public struct Table<S> {
    private let getState: (S) -> TableState
    private let setState: (inout S, TableState) -> Void
    private let lenFn: (S) -> Int
    private let rowIdFn: (S, Int) -> String
    private var columns: [TableColumn] = []
    private var cellFn: ((S, Int, String) -> Cell)? = nil
    private var onSortFn: ((inout S, String, SortDir, inout Tx) -> Void)? = nil
    private var onSelectFn: ((inout S, String, inout Tx) -> Void)? = nil
    private var onOpenFn: ((inout S, String, inout Tx) -> Void)? = nil
    private var zebraFlag: Bool = false
    private var styleOverride: TableStyle? = nil
    private var nameValue: String? = nil

    // PORT NOTE: `WritableKeyPath` and `(get, set)` overloads replace Rust's `(fn(&S) -> &TableState, fn(&mut S) -> &mut TableState)`.
    public init(
        _ state: WritableKeyPath<S, TableState>,
        _ len: @escaping (S) -> Int,
        _ rowId: @escaping (S, Int) -> String
    ) {
        self.getState = { $0[keyPath: state] }
        self.setState = { s, v in s[keyPath: state] = v }
        self.lenFn = len
        self.rowIdFn = rowId
    }

    public init(
        _ get: @escaping (S) -> TableState,
        _ set: @escaping (inout S, TableState) -> Void,
        _ len: @escaping (S) -> Int,
        _ rowId: @escaping (S, Int) -> String
    ) {
        self.getState = get
        self.setState = set
        self.lenFn = len
        self.rowIdFn = rowId
    }

    public static func new(
        _ state: WritableKeyPath<S, TableState>,
        _ len: @escaping (S) -> Int,
        _ rowId: @escaping (S, Int) -> String
    ) -> Table<S> {
        Table(state, len, rowId)
    }

    public static func new(
        _ get: @escaping (S) -> TableState,
        _ set: @escaping (inout S, TableState) -> Void,
        _ len: @escaping (S) -> Int,
        _ rowId: @escaping (S, Int) -> String
    ) -> Table<S> {
        Table(get, set, len, rowId)
    }

    public func column(_ c: TableColumn) -> Table<S> {
        var copy = self
        copy.columns.append(c)
        return copy
    }

    /// What row `i` shows in column `col` (the column's id).
    public func cell(_ f: @escaping (S, Int, String) -> Cell) -> Table<S> {
        var copy = self
        copy.cellFn = f
        return copy
    }

    /// A sortable column's header was clicked: the table already shows the new sort; reorder
    /// the rows to match.
    public func onSort(_ f: @escaping (inout S, String, SortDir, inout Tx) -> Void) -> Table<S> {
        var copy = self
        copy.onSortFn = f
        return copy
    }

    /// The cursor moved to row `id`, by click or key.
    public func onSelect(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Table<S> {
        var copy = self
        copy.onSelectFn = f
        return copy
    }

    /// A row was double-clicked, or Return pressed on it.
    public func onOpen(_ f: @escaping (inout S, String, inout Tx) -> Void) -> Table<S> {
        var copy = self
        copy.onOpenFn = f
        return copy
    }

    /// Fill every other row.
    public func zebra(_ on: Bool) -> Table<S> {
        var copy = self
        copy.zebraFlag = on
        return copy
    }

    public func style(_ s: TableStyle) -> Table<S> {
        var copy = self
        copy.styleOverride = s
        return copy
    }

    /// The table's accessibility label.
    public func name(_ n: String) -> Table<S> {
        var copy = self
        copy.nameValue = n
        return copy
    }

    /// The table, filling the height its parent gives it.
    public func build(_ s: S, _ k: Kit) -> El {
        let get = getState
        let set = setState
        let len = lenFn
        let rowId = rowIdFn
        let cols = columns
        let cell = cellFn
        let onSort = onSortFn
        let onSelect = onSelectFn
        let onOpen = onOpenFn
        let zebra = zebraFlag
        let style = styleOverride ?? TableStyle.fromKit(k)
        let name = nameValue

        let state = get(s)
        let count = len(s)
        let sizes: [ColumnWidth] = cols.map { c in
            if let w = state.columnWidth(c.idValue) {
                return .fixed(c.clamp(w))
            }
            return c.widthPolicy
        }

        let header = tableHeaderRow(k, state, cols, sizes, style, onSort, get, set)
        let focus = k.c.borderFocus

        let buildRow: (S, Int) -> El = { s, i in
            let st = get(s)
            let id = rowId(s, i)
            let selected = st.isSelected(id)
            var r = row()
                .key(id)
                .role("row")
                .focusSelected(selected)
                .wFull()
                .h(style.rowHeight)
                .centerY()
            if selected {
                r = r.fill(style.selected)
            } else if zebra && i % 2 == 1 {
                r = r.fill(style.stripe).hover(style.stripe.mix(style.selected, 0.5))
            } else {
                r = r.hover(style.stripe.mix(style.selected, 0.5))
            }
            if st.multi && st.cursorValue == id {
                r = r.outline(1.0, -1.0, focus)
            }
            for (j, c) in cols.enumerated() {
                let content = cell.map { $0(s, i, c.idValue) } ?? Cell.text("")
                r = r.child(tableCellEl(c, sizes[j], content, style).key(c.idValue))
            }
            r = r.onPressTx { (s: inout S, tx: inout Tx) in
                let n = len(s)
                guard i < n else { return }
                let mods = tx.mods()
                var st = get(s)
                st.click(i, n, mods) { j in rowId(s, j) }
                set(&s, st)
                if let f = onSelect {
                    let id = rowId(s, i)
                    f(&s, id, &tx)
                }
            }
            if let f = onOpen {
                r = r.onDoublePressTx { (s: inout S, tx: inout Tx) in
                    if i < len(s) {
                        let id = rowId(s, i)
                        f(&s, id, &tx)
                    }
                }
            }
            return r
        }

        var rows = col()
            .key("rows")
            .wFull()
            .growth(GrowthSpec())
            .virtualRows(count, style.rowHeight, rowId, buildRow)
        // PORT NOTE: Until `Sources/Rune/runtime/commit/commit_flatten.swift` expands `El.virtualRowsSource`
        // directly during layout, materialize keyed rows into `children` for bounded tables (`<= 1_024` rows)
        // so `Table` renders and interactive hit/selection/resize behavior works in `Runtime`.
        if count <= 1_024 {
            var builtChildren: [El] = []
            builtChildren.reserveCapacity(count)
            for i in 0..<count {
                builtChildren.append(buildRow(s, i))
            }
            rows = rows.children(builtChildren)
        }

        let viewport = col()
            .key("viewport")
            .wFull()
            .grow(1.0)
            .minH(0.0)
            .scroll(ScrollSpec(stickBottom: false))
            // Inside a scrolling page this reports every frame of the scroll; only a new height
            // changes what the view reads.
            .onLayoutTx { (s: inout S, r: [Float], tx: inout Tx) in
                var st = get(s)
                if st.viewport == r[3] && st.rowHeight == style.rowHeight {
                    tx.liveOnly()
                }
                st.viewport = r[3]
                st.rowHeight = style.rowHeight
                set(&s, st)
            }
            .child(rows)

        var root = col()
            .key(state.keyValue)
            .role("grid")
            .focusable(true)
            .wFull()
            .clipSoft(0.0)
        if let n = name {
            root = root.label(n)
        }
        return root
            .onKey { (s: inout S, ev: KeyEvent, tx: inout Tx) in
                let n = len(s)
                var st = get(s)
                let out = st.handleKey(ev, n, { j in rowId(s, j) }, &tx)
                let cursor = st.cursorValue
                set(&s, st)
                switch out {
                case .ignored:
                    return false
                case .handled:
                    return true
                case .moved:
                    if let f = onSelect, let id = cursor {
                        f(&s, id, &tx)
                    }
                    return true
                case .open(let r):
                    if let f = onOpen {
                        let id = rowId(s, r)
                        f(&s, id, &tx)
                    }
                    return true
                }
            }
            .child(header)
            .child(viewport)
    }
}

/// Sizes a header or body cell to its column.
private func tableSized(_ e: El, _ c: TableColumn, _ w: ColumnWidth) -> El {
    var out: El
    switch w {
    case .fixed(let width):
        out = e.w(width)
    case .flex(let g):
        out = e.w(0.0).grow(g).shrink()
    }
    out = out.minW(c.minWidth)
    return c.maxWidth.isFinite ? out.maxW(c.maxWidth) : out
}

private func tableJustify(_ e: El, _ a: Align) -> El {
    switch a {
    case .start:
        return e
    case .center:
        return e.justifyCenter()
    case .end:
        return e.justifyEnd()
    }
}

private func tableCellEl(_ c: TableColumn, _ w: ColumnWidth, _ cell: Cell, _ style: TableStyle) -> El {
    let inner: El
    switch cell.content {
    case .text(let t):
        let color = cell.colorValue ?? (cell.mutedFlag ? style.muted : style.text)
        inner = text(t)
            .font(cell.monoFlag ? style.mono : style.font)
            .color(color)
            .align(c.alignValue)
            .truncate()
            .shrink()
            .minW(0.0)
            .helpWhenTruncated(t)
    case .el(let e):
        inner = e
    }
    return tableJustify(
        tableSized(row().role("gridcell").hFull().px(style.cellPad).centerY().clipSoft(0.0), c, w),
        c.alignValue
    ).child(inner)
}

private func tableHeaderRow<S>(
    _ k: Kit,
    _ state: TableState,
    _ columns: [TableColumn],
    _ sizes: [ColumnWidth],
    _ style: TableStyle,
    _ onSort: ((inout S, String, SortDir, inout Tx) -> Void)?,
    _ get: @escaping (S) -> TableState,
    _ set: @escaping (inout S, TableState) -> Void
) -> El {
    var h = row()
        .key("header")
        .role("row")
        .wFull()
        .h(style.headerHeight)
        .child(el().key("rule").pin(0.0, nil, 0.0, 0.0).h(1.0).fill(style.rule))
    let last = Swift.max(columns.count - 1, 0)
    for (j, c) in columns.enumerated() {
        let sorted: SortDir? = {
            guard let (id, d) = state.sort(), id == c.idValue else { return nil }
            return d
        }()
        let label: String
        switch sorted {
        case .ascending?:
            label = "\(c.title), sorted ascending"
        case .descending?:
            label = "\(c.title), sorted descending"
        case nil:
            label = c.title
        }
        let titleEl = text(c.title)
            .key("title")
            .font(style.headerFont)
            .color(sorted != nil ? style.text : style.headerText)
            .truncate()
            .shrink()
            .minW(0.0)
            .helpWhenTruncated(c.title)
        var inner = row().key("inner").gap(2.0).centerY().minW(0.0).shrink().child(titleEl)
        if let d = sorted {
            let glyph = d == .ascending ? k.glyph.chevronUp : k.glyph.chevronDown
            inner = inner.child(icon(glyph, 14.0).key("sort").color(style.text))
        }
        var cell = tableJustify(
            tableSized(
                row().role("columnheader").label(label).hFull().px(style.cellPad).centerY(),
                c,
                sizes[j]
            ),
            c.alignValue
        )
        .key(c.idValue)
        .child(inner)

        let id = c.idValue
        cell = cell.onLayoutTx { (s: inout S, r: [Float], tx: inout Tx) in
            var st = get(s)
            if st.laidOut.updateValue(r[2], forKey: id) == r[2] {
                tx.liveOnly()
            }
            set(&s, st)
        }
        if c.sortableFlag {
            cell = cell.cursor(.pointer).hover(k.c.hover).onPressTx { (s: inout S, tx: inout Tx) in
                var st = get(s)
                let dir = st.nextSort(id)
                st.setSort(id, dir)
                set(&s, st)
                if let f = onSort {
                    f(&s, id, dir, &tx)
                }
            }
        }
        if c.resizableFlag {
            cell = cell.child(tableResizeHandle(c, get, set, style.rule, j == last))
        } else if j != last {
            cell = cell.child(el().key("rule").pin(nil, 8.0, 0.0, 8.0).w(1.0).fill(style.rule))
        }
        h = h.child(cell)
    }
    return h
}

/// The drag target on a header cell's right edge: a hairline that widens the column as it's
/// dragged, clamped to its bounds. A double click puts the column back.
private func tableResizeHandle<S>(
    _ c: TableColumn,
    _ get: @escaping (S) -> TableState,
    _ set: @escaping (inout S, TableState) -> Void,
    _ rule: Color,
    _ last: Bool
) -> El {
    let id = c.idValue
    let line = el().key("line").w(1.0).hFull().fill(last ? Color.TRANSPARENT : rule)
    return row()
        .key("resize")
        .label("Resize \(c.title)")
        .pin(nil, 6.0, -4.0, 6.0)
        .w(9.0)
        .justifyCenter()
        .cursor(.resizeColumn)
        .onDrag { (s: inout S, d: inout Drag, _: inout Tx) in
            var st = get(s)
            switch d.phase {
            case .down:
                st.resizeStart = .active(st.columnWidth(id))
                d.data = st.columnWidth(id) ?? st.laidOut[id] ?? c.minWidth
            case .move, .up:
                if d.cancelled() {
                    if case .active(let prev) = st.resizeStart {
                        st.resizeStart = .idle
                        if let w = prev {
                            st.setColumnWidth(id, w)
                        } else {
                            st.resetColumnWidth(id)
                        }
                    } else {
                        st.resetColumnWidth(id)
                    }
                } else {
                    st.setColumnWidth(id, c.clamp(d.data + d.dx))
                    if d.phase == .up {
                        st.resizeStart = .idle
                    }
                }
            }
            set(&s, st)
        }
        .onDoublePress { (s: inout S) in
            var st = get(s)
            st.resetColumnWidth(id)
            set(&s, st)
        }
        .child(line)
}
