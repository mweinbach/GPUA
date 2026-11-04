// Ported from: crates/rune-kit/src/tree.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Tree: a virtualised outline over a ``TreeModel`` the app keeps in its state. A file tree is
//! the main use (``FileTree`` builds one from paths), but rows hold any data.
//!
//! The model owns the nodes, their open state, the selection and the keyboard cursor; the
//! ``Tree`` builder draws the rows that are on screen (`El.virtualRows`), so 50,000 nodes
//! cost what the visible forty do. The tree is one focus stop that keeps its keyboard while rows
//! scroll in and out: Up and Down move, Right opens or goes to the first child, Left closes or
//! goes to the parent, Home and End go to the ends, Page Up and Page Down move by a screen,
//! Return opens, and typing a name jumps to it. With ``TreeModel/multiSelect(_:)``, Shift extends
//! the selection and Cmd-A selects every row.

import Rune

/// What a key did to a ``TreeModel`` (``TreeModel/handleKey(_:_:_:)``).
public enum TreeKey: Sendable, Equatable {
    /// Not a tree key; it goes on to the window.
    case ignored
    /// It moved the cursor, the selection or a folder.
    case handled
    /// Return or Space on a row without children: the app opens this id.
    case open(String)
}

struct TreeNode<T> {
    var id: String
    var data: T
    var parent: Int?
    var children: [Int]
    var depth: UInt32
    var open: Bool
    var selected: Bool
}

/// What a filter left: hidden, shown to reach a match, or a match.
private enum Shown: Sendable, Equatable {
    case hidden
    case path
    case match
}

private struct TreeFilter: Sendable, Equatable {
    var shown: [Shown]
    /// Folders the user closed while filtering (the rest show open).
    var closed: [Bool]
}

private struct VisibleRows: Sendable, Equatable {
    /// Node index of each visible row, top to bottom.
    var rows: [Int] = []
    /// Row of each node, `Int.max` when hidden.
    var rowOf: [Int] = []
}

// PORT NOTE: Reference box replacing Rust's `RefCell<Option<Visible>>` so non-mutating reads
// (`visibleLen`, `visibleId`, `visibleRow`, `row`) compute visible rows once per mutation.
// `dirty()` uses `isKnownUniquelyReferenced` so copied `TreeModel` values never share mutable cache state.
private final class VisibleCache {
    var value: VisibleRows? = nil
}

/// Seconds of pause after which typing starts a new name (AppKit's type select).
private let TYPE_PAUSE: Double = 1.0

/// An outline's nodes, open folders, selection and keyboard cursor, kept in the app's state and
/// drawn by ``Tree``. Nodes are keyed by string ids unique across the tree (a file tree uses
/// paths). Mutating methods take `inout self`; the visible rows are worked out on the next read.
public struct TreeModel<T> {
    var nodes: [TreeNode<T>] = []
    private var index: [String: Int] = [:]
    private var roots: [Int] = []
    var cursorIdx: Int? = nil
    private var anchor: Int? = nil
    private var multi: Bool = false
    private var filterState: TreeFilter? = nil
    private var visible: VisibleCache = VisibleCache()
    private var typed: String = ""
    private var typedAt: RuneInstant? = nil
    var keyName: String = "tree"
    /// The viewport's height in points, for Page Up and Page Down.
    var viewport: Float = 0.0
    var rowHeight: Float = 24.0

    public init() {}

    private init(
        preservingKey keyName: String,
        multi: Bool,
        viewport: Float,
        rowHeight: Float
    ) {
        self.keyName = keyName
        self.multi = multi
        self.viewport = viewport
        self.rowHeight = rowHeight
    }

    public static func new() -> TreeModel<T> {
        TreeModel()
    }

    public static var `default`: TreeModel<T> {
        TreeModel()
    }

    /// The tree's element key (`"tree"` by default). Its rows are keyed by id inside it, and
    /// ``reveal(_:_:)`` looks for the row there, so give each tree on screen its own.
    public func key(_ key: String) -> TreeModel<T> {
        var copy = self
        copy.keyName = key
        return copy
    }

    /// Several rows can be selected: Shift with the arrows extends the selection, Cmd-A selects
    /// every row, and ``setSelected(_:_:)`` and ``selectRange(_:)`` add to it.
    public func multiSelect(_ on: Bool) -> TreeModel<T> {
        var copy = self
        copy.multi = on
        return copy
    }

    private mutating func dirty() {
        if isKnownUniquelyReferenced(&visible) {
            visible.value = nil
        } else {
            visible = VisibleCache()
        }
    }

    /// Adds `id` under `parent` (`nil` for the top level), after its siblings. Returns `false`
    /// and adds nothing when `id` is already in the tree or `parent` isn't.
    @discardableResult
    public mutating func insert(_ parent: String?, _ id: String, _ data: T) -> Bool {
        if index[id] != nil {
            return false
        }
        let parentIdx: Int?
        if let p = parent {
            guard let found = index[p] else {
                return false
            }
            parentIdx = found
        } else {
            parentIdx = nil
        }
        let i = nodes.count
        let depth: UInt32 = parentIdx.map { nodes[$0].depth + 1 } ?? 0
        if let p = parentIdx {
            nodes[p].children.append(i)
        } else {
            roots.append(i)
        }
        index[id] = i
        nodes.append(
            TreeNode(
                id: id,
                data: data,
                parent: parentIdx,
                children: [],
                depth: depth,
                open: false,
                selected: false
            )
        )
        if filterState != nil {
            filterState!.shown.append(.hidden)
            filterState!.closed.append(false)
        }
        dirty()
        return true
    }

    /// Removes every node, the selection and the filter.
    public mutating func clear() {
        self = TreeModel(
            preservingKey: keyName,
            multi: multi,
            viewport: viewport,
            rowHeight: rowHeight
        )
    }

    public func len() -> Int {
        nodes.count
    }

    public func isEmpty() -> Bool {
        nodes.isEmpty
    }

    public func contains(_ id: String) -> Bool {
        index[id] != nil
    }

    public func get(_ id: String) -> T? {
        index[id].map { nodes[$0].data }
    }

    // PORT NOTE: Swift cannot return `Option<&mut T>` directly; `withMut` and `getMut` expose
    // scoped `inout T` mutation on a node's payload when `id` exists.
    public mutating func withMut<R>(_ id: String, _ body: (inout T) -> R) -> R? {
        guard let i = index[id] else { return nil }
        return body(&nodes[i].data)
    }

    @discardableResult
    public mutating func getMut(_ id: String, _ body: (inout T) -> Void) -> Bool {
        guard let i = index[id] else { return false }
        body(&nodes[i].data)
        return true
    }

    public func parent(_ id: String) -> String? {
        guard let i = index[id], let p = nodes[i].parent else { return nil }
        return nodes[p].id
    }

    /// `id`'s children in order, or the top-level nodes for `nil`.
    public func children(_ id: String?) -> [String] {
        let list: [Int]
        if let id {
            guard let i = index[id] else { return [] }
            list = nodes[i].children
        } else {
            list = roots
        }
        return list.map { nodes[$0].id }
    }

    public func hasChildren(_ id: String) -> Bool {
        guard let i = index[id] else { return false }
        return !nodes[i].children.isEmpty
    }

    /// 0 at the top level.
    public func depth(_ id: String) -> UInt32? {
        index[id].map { nodes[$0].depth }
    }

    /// The data of `id` and everything under it, depth first.
    public func subtree(_ id: String) -> [T] {
        guard let start = index[id] else { return [] }
        var out: [T] = []
        var stack: [Int] = [start]
        while let i = stack.popLast() {
            out.append(nodes[i].data)
            stack.append(contentsOf: nodes[i].children.reversed())
        }
        return out
    }

    /// Sorts every node's children (and the top level) by `cmp`.
    public mutating func sortBy(_ cmp: (T, T) -> Ordering) {
        let snap = nodes
        func order(_ list: inout [Int]) {
            list.sort { a, b in
                cmp(snap[a].data, snap[b].data) == .less
            }
        }
        for i in nodes.indices {
            order(&nodes[i].children)
        }
        order(&roots)
        dirty()
    }

    // Open folders ----------------------------------------------------------------------------

    /// Whether `id` shows its children. Under a filter, folders leading to a match show open
    /// unless closed since.
    public func isExpanded(_ id: String) -> Bool {
        guard let i = index[id] else { return false }
        return open(i)
    }

    private func open(_ i: Int) -> Bool {
        if let f = filterState {
            return !f.closed[i]
        }
        return nodes[i].open
    }

    private mutating func setOpen(_ i: Int, _ isOpen: Bool) {
        if filterState != nil {
            filterState!.closed[i] = !isOpen
        } else {
            nodes[i].open = isOpen
        }
        // A cursor or anchor inside a closing folder moves up to it.
        if !isOpen {
            if let c = cursorIdx, isUnder(c, i) {
                if !multi && nodes[c].selected {
                    selectOnly(i)
                } else {
                    cursorIdx = i
                }
            }
            if let a = anchor, isUnder(a, i) {
                anchor = i
            }
        }
        dirty()
    }

    private func isUnder(_ node: Int, _ ancestor: Int) -> Bool {
        var cur = node
        while let p = nodes[cur].parent {
            if p == ancestor {
                return true
            }
            cur = p
        }
        return false
    }

    public mutating func setExpanded(_ id: String, _ open: Bool) {
        if let i = index[id] {
            setOpen(i, open)
        }
    }

    public mutating func toggle(_ id: String) {
        if let i = index[id] {
            setOpen(i, !open(i))
        }
    }

    public mutating func expandAll() {
        for i in 0..<nodes.count where !nodes[i].children.isEmpty {
            setOpen(i, true)
        }
    }

    public mutating func collapseAll() {
        for i in 0..<nodes.count {
            setOpen(i, false)
        }
    }

    /// Opens every folder above `id`, so its row shows.
    public mutating func expandTo(_ id: String) {
        guard let i = index[id] else { return }
        if filterState != nil {
            if filterState!.shown[i] == .hidden {
                filterState!.shown[i] = .match
            }
            var p = nodes[i].parent
            while let j = p {
                if filterState!.shown[j] == .hidden {
                    filterState!.shown[j] = .path
                }
                p = nodes[j].parent
            }
            dirty()
        }
        var p = nodes[i].parent
        while let j = p {
            nodes[j].open = true
            setOpen(j, true)
            p = nodes[j].parent
        }
    }

    // Selection ------------------------------------------------------------------------------

    /// Selected ids in tree order.
    public func selected() -> [String] {
        var out: [String] = []
        var stack: [Int] = Array(roots.reversed())
        while let i = stack.popLast() {
            if nodes[i].selected {
                out.append(nodes[i].id)
            }
            stack.append(contentsOf: nodes[i].children.reversed())
        }
        return out
    }

    public func isSelected(_ id: String) -> Bool {
        guard let i = index[id] else { return false }
        return nodes[i].selected
    }

    /// The keyboard cursor's row: where the arrows move from (the selected row unless Shift or
    /// Cmd made more).
    public func cursor() -> String? {
        cursorIdx.map { nodes[$0].id }
    }

    public mutating func clearSelection() {
        for i in nodes.indices {
            nodes[i].selected = false
        }
    }

    /// Selects `id` alone and puts the cursor on it.
    public mutating func select(_ id: String) {
        if let i = index[id] {
            selectOnly(i)
        }
    }

    private mutating func selectOnly(_ i: Int) {
        clearSelection()
        nodes[i].selected = true
        cursorIdx = i
        anchor = i
    }

    /// Adds `id` to the selection or takes it out (a multi-select tree; otherwise it selects
    /// `id` alone or clears it).
    public mutating func setSelected(_ id: String, _ on: Bool) {
        guard let i = index[id] else { return }
        if !multi {
            clearSelection()
        }
        nodes[i].selected = on
        cursorIdx = i
        anchor = i
    }

    /// Selects the visible rows from the anchor (the last row clicked or moved to without
    /// Shift) to `id`, as Shift-click does.
    public mutating func selectRange(_ id: String) {
        guard let i = index[id] else { return }
        if !multi {
            selectOnly(i)
            return
        }
        let anchorIdx = anchor ?? i
        let vis = rows()
        let a = vis.rowOf[anchorIdx]
        let b = vis.rowOf[i]
        if a == Int.max || b == Int.max {
            selectOnly(i)
            return
        }
        let lo = min(a, b)
        let hi = max(a, b)
        let range = Array(vis.rows[lo...hi])
        clearSelection()
        for j in range {
            nodes[j].selected = true
        }
        cursorIdx = i
    }

    /// A click on `id`'s row with `mods` held: it selects the row alone, or with Shift extends
    /// the selection to it and with Cmd adds or removes it (a multi-select tree). Returns
    /// whether it was a plain click.
    @discardableResult
    public mutating func click(_ id: String, _ mods: Mods) -> Bool {
        guard let i = index[id] else { return false }
        if multi && mods.shift {
            selectRange(id)
            return false
        }
        if multi && mods.cmd {
            nodes[i].selected.toggle()
            cursorIdx = i
            anchor = i
            return false
        }
        selectOnly(i)
        return true
    }

    /// Opens the folders above `id`, selects it alone and scrolls its row into view, as a tree
    /// following an editor does. Returns `false` when `id` isn't in the tree.
    @discardableResult
    public mutating func reveal(_ id: String, _ tx: inout Tx) -> Bool {
        if !contains(id) {
            return false
        }
        expandTo(id)
        select(id)
        tx.scrollIntoViewIn(keyName, id)
        return true
    }

    // Filter ---------------------------------------------------------------------------------

    /// Shows only the nodes `keep` matches, with the folders that lead to them (open), as a
    /// file tree's search does. A folder that matches shows without the children that don't.
    public mutating func filter(_ keep: (T) -> Bool) {
        let n = nodes.count
        var shown = Array(repeating: Shown.hidden, count: n)
        for i in 0..<n {
            if keep(nodes[i].data) {
                shown[i] = .match
                var p = nodes[i].parent
                while let j = p {
                    if shown[j] != .hidden {
                        break
                    }
                    shown[j] = .path
                    p = nodes[j].parent
                }
            }
        }
        filterState = TreeFilter(shown: shown, closed: Array(repeating: false, count: n))
        dirty()
        let vis = rows()
        let hideCursor = cursorIdx.map { vis.rowOf[$0] == Int.max } ?? false
        let hideAnchor = anchor.map { vis.rowOf[$0] == Int.max } ?? false
        if hideCursor {
            cursorIdx = nil
        }
        if hideAnchor {
            anchor = cursorIdx
        }
    }

    public mutating func clearFilter() {
        if filterState != nil {
            filterState = nil
            dirty()
        }
    }

    public func isFiltering() -> Bool {
        filterState != nil
    }

    /// Whether the filter matched `id` itself (not just a folder leading to a match); `true` for
    /// every node without a filter.
    public func isMatch(_ id: String) -> Bool {
        guard let i = index[id] else { return false }
        guard let f = filterState else { return true }
        return f.shown[i] == .match
    }

    // Visible rows ---------------------------------------------------------------------------

    private func rows() -> VisibleRows {
        if let cached = visible.value {
            return cached
        }
        var v = VisibleRows(rows: [], rowOf: Array(repeating: Int.max, count: nodes.count))
        var stack: [Int] = Array(roots.reversed())
        while let i = stack.popLast() {
            if !shown(i) {
                continue
            }
            v.rowOf[i] = v.rows.count
            v.rows.append(i)
            if open(i) {
                stack.append(contentsOf: nodes[i].children.reversed())
            }
        }
        visible.value = v
        return v
    }

    private func shown(_ i: Int) -> Bool {
        guard let f = filterState else { return true }
        return f.shown[i] != .hidden
    }

    /// Whether `i` has children the filter shows.
    private func openable(_ i: Int) -> Bool {
        nodes[i].children.contains { shown($0) }
    }

    /// How many rows show.
    public func visibleLen() -> Int {
        rows().rows.count
    }

    /// The id of visible row `row`.
    public func visibleId(_ row: Int) -> String? {
        let vis = rows()
        guard row >= 0 && row < vis.rows.count else { return nil }
        return nodes[vis.rows[row]].id
    }

    /// The row `id` shows at, if it shows.
    public func visibleRow(_ id: String) -> Int? {
        guard let i = index[id] else { return nil }
        let r = rows().rowOf[i]
        return r != Int.max ? r : nil
    }

    /// Visible row `row`'s data and state, for drawing it.
    public func row(_ row: Int) -> (T, TreeRow)? {
        let vis = rows()
        guard row >= 0 && row < vis.rows.count else { return nil }
        let i = vis.rows[row]
        let n = nodes[i]
        let state = TreeRow(
            id: n.id,
            depth: n.depth,
            expanded: openable(i) ? open(i) : nil,
            selected: n.selected,
            cursor: cursorIdx == i,
            matched: filterState.map { $0.shown[i] == .match } ?? false,
            multi: multi
        )
        return (n.data, state)
    }

    // Keyboard -------------------------------------------------------------------------------

    private mutating func moveTo(_ i: Int, _ extend: Bool) {
        if extend && multi {
            let id = nodes[i].id
            selectRange(id)
        } else {
            selectOnly(i)
        }
    }

    /// Applies a key (see the module docs); `label` gives a node's name for typing to jump.
    /// ``Tree`` calls this from its key handler, and scrolls the cursor's row into view.
    @discardableResult
    public mutating func handleKey(_ ev: KeyEvent, _ label: (T) -> String, _ tx: inout Tx) -> TreeKey {
        let m = ev.mods
        if (m.ctrl && !m.cmd) || m.alt || (m.logo && !m.cmd) {
            return .ignored
        }
        let len = visibleLen()
        if len == 0 {
            return .ignored
        }
        if ev.isCommand("a") && multi {
            let visRows = rows().rows
            for i in visRows {
                nodes[i].selected = true
            }
            return .handled
        }
        if m.cmd {
            return .ignored
        }
        let vis = rows()
        let at: Int? = cursorIdx.flatMap { c in
            let r = vis.rowOf[c]
            return r != Int.max ? r : nil
        }
        let rawPage = Int((viewport / max(rowHeight, 1.0)).rounded(.down))
        let page = max(max(rawPage - 1, 0), 1)
        let target: Int?
        switch ev.key {
        case .up:
            target = at.map { max($0 - 1, 0) } ?? (len - 1)
        case .down:
            target = at.map { min($0 + 1, len - 1) } ?? 0
        case .home:
            target = 0
        case .end:
            target = len - 1
        case .pageUp:
            target = at.map { max($0 - page, 0) } ?? 0
        case .pageDown:
            target = at.map { min($0 + page, len - 1) } ?? (len - 1)
        case .right where m.shift, .left where m.shift:
            target = nil
        case .right:
            guard let r = at else {
                return go(0, false, &tx)
            }
            let i = vis.rows[r]
            if !openable(i) {
                return .handled
            }
            if !open(i) {
                setOpen(i, true)
                return .handled
            }
            target = min(r + 1, len - 1)
        case .left:
            guard let r = at else {
                return go(0, false, &tx)
            }
            let i = vis.rows[r]
            if openable(i) && open(i) {
                setOpen(i, false)
                return .handled
            }
            guard let p = nodes[i].parent else {
                return .handled
            }
            target = vis.rowOf[p]
        case .enter:
            return activate(at, tx)
        case .text(let t) where t == " ":
            return activate(at, tx)
        case .text(let t) where !t.unicodeScalars.allSatisfy(\.properties.isWhitespace):
            let now = RuneInstant.now()
            let pause: Bool
            if let earlier = typedAt {
                let d = now.durationSince(earlier)
                let secs = Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
                pause = secs > TYPE_PAUSE
            } else {
                pause = true
            }
            typedAt = now
            if let r = typeSelect(t, pause, label) {
                return go(r, false, &tx)
            }
            return .handled
        default:
            target = nil
        }
        guard let r = target else {
            return .ignored
        }
        return go(r, m.shift, &tx)
    }

    private mutating func activate(_ at: Int?, _ tx: Tx) -> TreeKey {
        guard let r = at else { return .ignored }
        if tx.keyRepeat() {
            return .handled
        }
        let i = rows().rows[r]
        if openable(i) {
            setOpen(i, !open(i))
            return .handled
        }
        return .open(nodes[i].id)
    }

    private mutating func go(_ row: Int, _ extend: Bool, _ tx: inout Tx) -> TreeKey {
        let i = rows().rows[row]
        moveTo(i, extend)
        tx.scrollIntoViewIn(keyName, nodes[i].id)
        return .handled
    }

    /// The row typing `typedText` jumps to: the next whose name starts with everything typed since
    /// the last pause, and the same letter again cycles through names starting with it.
    mutating func typeSelect(_ typedText: String, _ pause: Bool, _ label: (T) -> String) -> Int? {
        if pause {
            typed.removeAll(keepingCapacity: true)
        }
        typed.append(contentsOf: typedText.lowercased())
        guard let first = typed.unicodeScalars.first else { return nil }
        let cycle = typed.unicodeScalars.allSatisfy { $0 == first }
        let prefix = cycle ? String(first) : typed
        let v = rows()
        let len = v.rows.count
        guard len > 0 else { return nil }
        let at: Int? = cursorIdx.flatMap { c in
            let r = v.rowOf[c]
            return r != Int.max ? r : nil
        }
        // A longer name keeps matching the row it's on; a repeated letter moves on.
        let start: Int
        if let r = at {
            start = cycle ? r + 1 : r
        } else {
            start = 0
        }
        for k in 0..<len {
            let r = (start + k) % len
            if label(nodes[v.rows[r]].data).lowercased().hasPrefix(prefix) {
                return r
            }
        }
        return nil
    }
}

/// A row's state as the tree draws it.
public struct TreeRow: Sendable, Equatable {
    public var id: String
    /// 0 at the top level.
    public var depth: UInt32
    /// `Some(open)` for a row with children (shown ones, under a filter), `nil` for a leaf.
    public var expanded: Bool?
    public var selected: Bool
    /// The keyboard cursor is on it.
    public var cursor: Bool
    /// A filter matched it (`false` without a filter).
    public var matched: Bool
    var multi: Bool

    init(
        id: String,
        depth: UInt32,
        expanded: Bool?,
        selected: Bool,
        cursor: Bool,
        matched: Bool,
        multi: Bool
    ) {
        self.id = id
        self.depth = depth
        self.expanded = expanded
        self.selected = selected
        self.cursor = cursor
        self.matched = matched
        self.multi = multi
    }

    /// A row's state for drawing a ``TreeItem`` outside a ``Tree`` (a sidebar, say).
    public init(_ id: String, _ depth: UInt32) {
        self.id = id
        self.depth = depth
        self.expanded = nil
        self.selected = false
        self.cursor = false
        self.matched = false
        self.multi = false
    }

    public static func new(_ id: String, _ depth: UInt32) -> TreeRow {
        TreeRow(id, depth)
    }

    public func expanded(_ open: Bool?) -> TreeRow {
        var copy = self
        copy.expanded = open
        return copy
    }

    public func selected(_ on: Bool) -> TreeRow {
        var copy = self
        copy.selected = on
        return copy
    }
}

// PORT NOTE: Module-like namespace matching `rune_kit::tree` in upstream Rust.
public enum tree {
    public typealias TreeKey = RuneKit.TreeKey
    public typealias TreeModel<T> = RuneKit.TreeModel<T>
    public typealias TreeRow = RuneKit.TreeRow
    public typealias FileNode<D> = RuneKit.FileNode<D>
    public typealias FileTree = RuneKit.FileTree
    public typealias Tree<S, T> = RuneKit.Tree<S, T>
    public typealias TreeItem = RuneKit.TreeItem
    public typealias TreeStyle = RuneKit.TreeStyle

    public static func fileIcon(_ name: String) -> Icon {
        RuneKit.fileIcon(name)
    }

    public static func naturalCmp(_ a: String, _ b: String) -> Ordering {
        RuneKit.naturalCmp(a, b)
    }
}
