// Ported from: crates/rune-kit/src/diff/view.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Drawing a `DiffState`: a virtual list of file headers, hunk separators and lines, a
//! sticky header for the file being read, and the handlers that feed selection, expansion and
//! the reading position back into the state.

import Rune

private let DIFF_EXPAND_UP = Icon(
    name: "kit-diff-expand-up",
    view: 16.0,
    body: #"<path d="M4.5 9.5L8 6L11.5 9.5" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" fill="none"/>"#
)
private let DIFF_EXPAND_DOWN = Icon(
    name: "kit-diff-expand-down",
    view: 16.0,
    body: #"<path d="M4.5 6.5L8 10L11.5 6.5" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" fill="none"/>"#
)
private let DIFF_EXPAND_ALL = Icon(
    name: "kit-diff-expand-all",
    view: 16.0,
    body: #"<path d="M5 5.5L8 2.5L11 5.5M5 10.5L8 13.5L11 10.5" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round" fill="none"/>"#
)
private let DIFF_PLUS = Icon(
    name: "kit-diff-plus",
    view: 16.0,
    body: #"<path d="M8 4V12M4 8H12" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>"#
)

/// Width of the coloured bar that marks an added or removed line.
private let DIFF_BAR: Float = 3.0
/// Space between the line numbers and the code, and after the code.
private let DIFF_CODE_PAD: (Float, Float) = (12.0, 24.0)

/// Draws the ``DiffState`` an app keeps in its state: give it the state's accessors and build
/// it in the view. It fills the height it's given and scrolls; Cmd-C, `j`/`k` and `]`/`[` work
/// once the app routes keys to ``DiffState/key(_:_:)``.
public struct DiffView<S> {
    fileprivate let get: (S) -> DiffState
    fileprivate let modify: (inout S, (inout DiffState) -> Void) -> Void
    fileprivate var keyVal: String
    fileprivate var annotationFn: ((S, Annotation) -> El)?
    fileprivate var headerFn: ((S, Int) -> El)?
    fileprivate var onSelectFn: ((inout S, LineRange?, inout Tx) -> Void)?
    fileprivate var onCommentFn: ((inout S, LineRange, inout Tx) -> Void)?
    fileprivate var onVisibleFileFn: ((inout S, Int) -> Void)?

    // PORT NOTE: Supports both Swift `WritableKeyPath<S, DiffState>` and explicit reader/mutator closures
    // since Swift closures cannot return `inout DiffState` directly like Rust's `Fn(&mut S) -> &mut DiffState`.
    public init(_ keyPath: WritableKeyPath<S, DiffState>) {
        self.get = { $0[keyPath: keyPath] }
        self.modify = { s, body in body(&s[keyPath: keyPath]) }
        self.keyVal = "diff"
        self.annotationFn = nil
        self.headerFn = nil
        self.onSelectFn = nil
        self.onCommentFn = nil
        self.onVisibleFileFn = nil
    }

    public init(
        _ get: @escaping (S) -> DiffState,
        _ modify: @escaping (inout S, (inout DiffState) -> Void) -> Void
    ) {
        self.get = get
        self.modify = modify
        self.keyVal = "diff"
        self.annotationFn = nil
        self.headerFn = nil
        self.onSelectFn = nil
        self.onCommentFn = nil
        self.onVisibleFileFn = nil
    }

    public static func new(_ keyPath: WritableKeyPath<S, DiffState>) -> DiffView<S> {
        DiffView(keyPath)
    }

    public static func new(
        _ get: @escaping (S) -> DiffState,
        _ modify: @escaping (inout S, (inout DiffState) -> Void) -> Void
    ) -> DiffView<S> {
        DiffView(get, modify)
    }

    /// The view's element key (`"diff"` by default); give each diff in a window its own.
    public func key(_ key: String) -> DiffView<S> {
        var copy = self
        copy.keyVal = key
        return copy
    }

    /// Build each ``Annotation`` under its line. Rows holding annotations are built every
    /// commit, so a widget can read app state (a composer's text) freely.
    public func annotation(_ f: @escaping (S, Annotation) -> El) -> DiffView<S> {
        var copy = self
        copy.annotationFn = f
        return copy
    }

    /// Extra controls at the end of each file's header (a "viewed" toggle, a menu), by file.
    public func headerActions(_ f: @escaping (S, Int) -> El) -> DiffView<S> {
        var copy = self
        copy.headerFn = f
        return copy
    }

    /// Called when a click, shift-click or drag on the line numbers ends, with the selection.
    public func onSelect(_ f: @escaping (inout S, LineRange?, inout Tx) -> Void) -> DiffView<S> {
        var copy = self
        copy.onSelectFn = f
        return copy
    }

    /// Show a "+" by the line numbers of the hovered line, and call `f` with the lines it
    /// stands for when pressed: the selection when the line is in it, else that line.
    public func onComment(_ f: @escaping (inout S, LineRange, inout Tx) -> Void) -> DiffView<S> {
        var copy = self
        copy.onCommentFn = f
        return copy
    }

    /// Called when the file at the top of the view changes as it scrolls, to follow it in a
    /// file tree.
    public func onVisibleFile(_ f: @escaping (inout S, Int) -> Void) -> DiffView<S> {
        var copy = self
        copy.onVisibleFileFn = f
        return copy
    }

    public func build(_ s: S, _ k: Kit) -> El {
        let st = get(s)
        let look = DiffLook(k)
        let wrap = st.wraps()
        let rootKey = keyVal
        if !wrap, let r = Rune.memoNamespace.layout("\(rootKey)/scroll") {
            st.setViewport(r)
        }
        let v = DiffViewImpl(d: self, look: look)
        let count = st.rows.count
        var list = col()
            .key("rows")
            .wFull()
            .growth(GrowthSpec())
            .selectionGroup(true)
            .role("list")
            .label("Diff")
        if !wrap {
            list = list.minW(max(v.contentWidth(st), st.viewWidth()))
        }
        let getFn = v.d.get
        let modFn = v.d.modify
        let onFile = v.d.onVisibleFileFn
        list = list
            .virtualRows(
                count,
                DIFF_LINE_H,
                { state, idx in getFn(state).keys[idx] },
                { state, idx in v.row(state, idx) }
            )
            .virtualRowsVersion(st.keysRev)
            .onVisibleRows { state, rows in
                var reported: Int? = nil
                var stickyChanged = false
                modFn(&state) { diffState in
                    let res = diffState.setVisibleRows(rows)
                    reported = res.0
                    stickyChanged = res.1
                }
                if let f = reported, let cb = onFile {
                    cb(&state, f)
                    return true
                }
                return stickyChanged
            }
        // PORT NOTE: Until `Sources/Rune/runtime/commit/commit_flatten.swift` expands `El.virtualRowsSource`
        // directly during layout, materialize memoized keyed rows into `children` for bounded diffs (`<= 1_024`
        // rows) so `DiffView` renders and interactive hit/selection/annotation behavior works in `Runtime`.
        if count <= 1_024 {
            var builtChildren: [El] = []
            builtChildren.reserveCapacity(count)
            for i in 0..<count {
                builtChildren.append(v.row(s, i).key(st.keys[i]))
            }
            list = list.children(builtChildren)
        }
        var scroll = col()
            .key("scroll")
            .wFull()
            .grow(1.0)
            .minH(0.0)
            .scroll(ScrollSpec(stickBottom: false))
        if !wrap {
            scroll = scroll.scrollXy()
        }
        scroll = scroll.child(list)
        var root = col()
            .key(rootKey)
            .wFull()
            .grow(1.0)
            .minH(0.0)
            .fill(v.look.bg)
            .child(scroll)
        if let f = st.sticky() {
            root = root.child(v.fileHeader(s, st, f, sticky: true).key("sticky").absolute(0.0, 0.0).wFull())
        }
        return root
    }
}

private struct DiffSpanRowVersion: Hashable {
    let lookVersion: UInt64
    let rev: UInt64
    let viewWidthBits: UInt32
}

private struct DiffLineRowVersion: Hashable {
    let lookVersion: UInt64
    let rev: UInt64
    let selected: Bool
    let copySide: DiffSide
    let selectionStartSide: DiffSide?
}

private struct DiffTints {
    var line: Color
    var gutter: Color
    var word: Color
    var number: Color
    var bar: Color
    var count: Color
}

/// Colours and type, from the kit's palette so themes restyle them.
private struct DiffLook {
    var font: TextStyle
    var label: TextStyle
    var small: TextStyle
    /// The advance of a mono column.
    var adv: Float
    var bg: Color
    var text: Color
    var muted: Color
    var faint: Color
    var border: Color
    var headerBg: Color
    var hover: Color
    var add: DiffTints
    var del: DiffTints
    var gapBg: Color
    var emptyBg: Color
    var selected: Color
    var selectedGutter: Color
    var selection: Color
    var accent: Color
    var onAccent: Color
    var triangleDown: Icon
    var triangleRight: Icon
    var syntax: SyntaxTheme
    /// Changes when anything above does, for memoised rows.
    var version: UInt64

    init(_ k: Kit) {
        let c = k.c
        let bg = c.bgBase
        let dark = k.dark
        func makeTints(_ hue: Color, _ fg: Color) -> DiffTints {
            DiffTints(
                line: tint(bg, hue, dark ? 0.13 : 0.1),
                gutter: tint(bg, hue, dark ? 0.2 : 0.17),
                word: tint(bg, hue, dark ? 0.32 : 0.27),
                number: tint(c.textMuted, hue, 0.7),
                bar: hue,
                count: fg
            )
        }
        var font = k.ty.mono
        font.size = 13.0
        font.lineHeight = DIFF_LINE_H

        var label = k.ty.uiMedium
        label.size = 13.0
        label.lineHeight = 20.0

        var small = k.ty.mono
        small.size = 12.0
        small.lineHeight = 16.0

        let info = c.info.icon
        let add = makeTints(c.success.icon, c.success.fg)
        let del = makeTints(c.danger.icon, c.danger.fg)
        let headerBg = c.layer01
        let textCol = c.textBase

        var hasher = Hasher()
        for col in [bg, textCol, add.bar, del.bar, info, headerBg] {
            hasher.combine(col.r.bitPattern)
            hasher.combine(col.g.bitPattern)
            hasher.combine(col.b.bitPattern)
            hasher.combine(col.a.bitPattern)
        }
        hasher.combine(font.size.bitPattern)
        let ver = UInt64(bitPattern: Int64(hasher.finalize()))

        self.font = font
        self.label = label
        self.small = small
        self.adv = 0.6 * font.size
        self.bg = bg
        self.text = textCol
        self.muted = c.textMuted
        self.faint = c.textFaint
        self.border = c.borderWeak
        self.headerBg = headerBg
        self.hover = k.alpha(c.textBase, dark ? 0.06 : 0.035)
        self.add = add
        self.del = del
        self.gapBg = tint(bg, info, dark ? 0.1 : 0.06)
        self.emptyBg = tint(bg, c.textBase, dark ? 0.03 : 0.025)
        self.selected = tint(bg, info, dark ? 0.2 : 0.14)
        self.selectedGutter = tint(bg, info, dark ? 0.32 : 0.26)
        self.selection = k.selection()
        self.accent = info
        self.onAccent = c.white
        self.triangleDown = k.glyph.triangleDown
        self.triangleRight = k.glyph.triangleRight
        self.syntax = SyntaxTheme.fromKit(k)
        self.version = ver
    }

    func tints(_ kind: LineKind) -> DiffTints? {
        switch kind {
        case .added:
            return add
        case .removed:
            return del
        case .context:
            return nil
        }
    }

    func gutterFill(_ kind: LineKind, _ isSelected: Bool) -> Color {
        if isSelected {
            return selectedGutter
        }
        if let t = tints(kind) {
            return t.gutter
        }
        return bg
    }

    /// One line-number column for numbers of `digits` digits.
    func numberW(_ digits: UInt32) -> Float {
        (Float(digits) * adv + 16.0).rounded(.up)
    }
}

/// One side's line in a row: what a cell draws.
private struct DiffCell {
    var kind: LineKind
    var old: UInt32?
    var new: UInt32?
    var text: String
    var changes: [Range<Int>]
    var noNewline: Bool

    /// The side its text is read from, and its number there.
    func source() -> (DiffSide, UInt32) {
        switch (kind, old, new) {
        case (.removed, let n?, _):
            return (.old, n)
        case (_, _, let n?):
            return (.new, n)
        case (_, let n?, nil):
            return (.old, n)
        default:
            return (.new, 1)
        }
    }

    func label() -> String {
        let (_, n) = source()
        let kindWord: String
        switch kind {
        case .added:
            kindWord = "added"
        case .removed:
            kindWord = "removed"
        case .context:
            kindWord = "unchanged"
        }
        return "\(kindWord) line \(n): \(text)"
    }
}

private final class DiffViewImpl<S> {
    let d: DiffView<S>
    let look: DiffLook

    init(d: DiffView<S>, look: DiffLook) {
        self.d = d
        self.look = look
    }

    /// How wide unwrapped (unified) content is, so the list doesn't change width as rows are built.
    func contentWidth(_ st: DiffState) -> Float {
        let l = look
        let fileCount = st.files().count
        var digits: UInt32 = 3
        for f in 0..<fileCount {
            digits = max(digits, st.digits(f))
        }
        return DIFF_BAR + 2.0 * l.numberW(digits) + Float(st.columns()) * l.adv + DIFF_CODE_PAD.0 + DIFF_CODE_PAD.1
    }

    /// The most a full-width part of a row (a header, an annotation) spans: the viewport, not
    /// the unwrapped content.
    func viewW(_ st: DiffState, _ splitHalf: Bool) -> Float? {
        let w = st.viewWidth()
        guard w > 0.0 && !st.wraps() else { return nil }
        return splitHalf ? (w / 2.0).rounded(.down) : w
    }

    func row(_ s: S, _ i: Int) -> El {
        let st = d.get(s)
        let r = st.rows[i]
        let rowKey = st.keys[i]
        switch r {
        case .file(let f):
            return fileHeader(s, st, Int(f), sticky: false)
        case .note(let f):
            let ver = DiffSpanRowVersion(
                lookVersion: look.version,
                rev: st.rev,
                viewWidthBits: st.viewWidth().bitPattern
            )
            return memo(rowKey, ver) { self.note(st, Int(f)) }
        case .gap(let f, let gapIdx):
            let ver = DiffSpanRowVersion(
                lookVersion: look.version,
                rev: st.rev,
                viewWidthBits: st.viewWidth().bitPattern
            )
            return memo(rowKey, ver) { self.gap(st, Int(f), Int(gapIdx)) }
        default:
            if !st.annotations().isEmpty && d.annotationFn != nil && annotated(st, r) {
                return line(s, st, i)
            }
            let ver = DiffLineRowVersion(
                lookVersion: look.version,
                rev: st.rev,
                selected: st.rowSelected(i, nil),
                copySide: st.copySide(),
                selectionStartSide: st.selection()?.start.side
            )
            return memo(rowKey, ver) { self.line(s, st, i) }
        }
    }

    func annotated(_ st: DiffState, _ r: DiffRow) -> Bool {
        let f = r.file()
        for side in [DiffSide.old, DiffSide.new] {
            if let n = st.rowLine(r, side), !st.annotationsAt(f, LineRef.new(side, n)).isEmpty {
                return true
            }
        }
        return false
    }

    func cells(_ st: DiffState, _ r: DiffRow) -> (DiffCell?, DiffCell?) {
        let files = st.files()
        func of(_ f: UInt32, _ h: UInt32, _ i: UInt32) -> DiffCell {
            let l = files[Int(f)].hunks[Int(h)].lines[Int(i)]
            return DiffCell(
                kind: l.kind,
                old: l.old,
                new: l.new,
                text: l.text,
                changes: l.changes,
                noNewline: l.noNewline
            )
        }
        switch r {
        case .ctx(let f, let old, let new):
            let txt = st.sideLine(Int(f), .new, new) ?? st.sideLine(Int(f), .old, old) ?? ""
            let c = DiffCell(
                kind: .context,
                old: old,
                new: new,
                text: txt,
                changes: [],
                noNewline: false
            )
            return (c, nil)
        case .line(let f, let h, let i):
            return (of(f, h, i), nil)
        case .pair(let f, let h, let del, let add):
            return (of(f, h, del), of(f, h, add))
        case .file, .note, .gap:
            return (nil, nil)
        }
    }

    func line(_ s: S, _ st: DiffState, _ i: Int) -> El {
        let r = st.rows[i]
        let f = r.file()
        let (aOpt, bOpt) = cells(st, r)
        guard let a = aOpt else { return col() }
        let lineEl: El
        switch st.mode() {
        case .unified:
            lineEl = unified(st, i, f, a)
        case .split:
            let oldCell: DiffCell?
            let newCell: DiffCell?
            switch (bOpt, a.kind) {
            case (let b?, _):
                oldCell = a
                newCell = b
            case (nil, .removed):
                oldCell = a
                newCell = nil
            case (nil, .added):
                oldCell = nil
                newCell = a
            case (nil, .context):
                oldCell = a
                newCell = a
            }
            lineEl = split(st, i, f, oldCell, newCell)
        }
        guard let buildAnnotation = d.annotationFn else {
            return lineEl
        }
        func notes(_ side: DiffSide) -> [El] {
            guard let n = st.rowLine(r, side) else { return [] }
            return st.annotationsAt(f, LineRef.new(side, n)).map { a in
                diffAnnotationNote(buildAnnotation(s, a), a)
            }
        }
        let oldNotes = notes(.old)
        let newNotes = notes(.new)
        if oldNotes.isEmpty && newNotes.isEmpty {
            return lineEl
        }
        var out = col().wFull().child(lineEl.key("line"))
        switch st.mode() {
        case .unified:
            var c = col().key("notes").wFull()
            if let w = viewW(st, false) {
                c = c.w(w).stickyLeft(0.0)
            }
            // An unchanged line's annotations from either side, once.
            var seen: Set<String> = []
            var combined: [El] = []
            for side in [DiffSide.old, DiffSide.new] {
                if let n = st.rowLine(r, side) {
                    for a in st.annotationsAt(f, LineRef.new(side, n)) where seen.insert(a.id).inserted {
                        combined.append(diffAnnotationNote(buildAnnotation(s, a), a))
                    }
                }
            }
            out = out.child(c.children(combined))
        case .split:
            func half(_ key: String, _ els: [El]) -> El {
                var c = col().key(key).wFrac(0.5).minW(0.0)
                if let w = viewW(st, true) {
                    c = c.maxW(w)
                }
                return c.children(els)
            }
            out = out.child(
                Rune.row()
                    .key("notes")
                    .wFull()
                    .itemsStart()
                    .child(half("old", oldNotes))
                    .child(half("new", newNotes))
            )
        }
        return out
    }

    func unified(_ st: DiffState, _ i: Int, _ f: Int, _ c: DiffCell) -> El {
        let l = look
        let selected = st.rowSelected(i, nil)
        let tints = l.tints(c.kind)
        let fill = selected ? l.selected : (tints?.line ?? l.bg)
        let digits = st.digits(f)
        let copy: Bool
        switch c.kind {
        case .context:
            copy = true
        case .added:
            copy = st.copySide() == .new
        case .removed:
            copy = st.copySide() == .old
        }
        let hoverSide: DiffSide = c.kind == .removed ? .old : .new
        // The marker, numbers and "+" hold to the viewport's left edge while the code scrolls
        // sideways under them, on the gutter's own opaque fill.
        var gutter = Rune.row()
            .key("gutter")
            .selfStretch()
            .itemsStretch()
            .fill(l.gutterFill(c.kind, selected))
            .child(bar(c.kind))
            .child(number(st, i, f, c.old, .old, c.kind, selected, digits).key("no"))
            .child(number(st, i, f, c.new, .new, c.kind, selected, digits).key("nn"))
        if d.onCommentFn != nil {
            let at = c.new.map { LineRef.new(.new, $0) } ?? c.old.map { LineRef.new(.old, $0) }
            if let at {
                gutter = gutter.child(plus(f, at).absolute(DIFF_BAR + 2.0 * l.numberW(digits) - 10.0, 2.0))
            }
        }
        if !st.wraps() {
            gutter = gutter.stickyLeft(0.0)
        }
        return Rune.row()
            .wFull()
            .minH(DIFF_LINE_H)
            .itemsStart()
            .fill(fill)
            .hover(l.hover)
            .hoverGroup()
            .role("listitem")
            .label(c.label())
            .child(gutter)
            .child(code(st, f, c, copy, hoverSide, st.keys[i]).key("code"))
    }

    func split(_ st: DiffState, _ i: Int, _ f: Int, _ old: DiffCell?, _ new: DiffCell?) -> El {
        let digits = st.digits(f)
        func half(_ side: DiffSide, _ cellOpt: DiffCell?) -> El {
            let l = look
            let sideKey = side == .old ? "old" : "new"
            var h = Rune.row().key(sideKey).wFrac(0.5).minW(0.0).minH(DIFF_LINE_H).itemsStart().selfStretch()
            guard var cell = cellOpt else {
                return h.fill(l.emptyBg)
            }
            // An unchanged line shows on both sides as context.
            let kind = cell.kind
            let selected = st.rowSelected(i, side)
            let fill = selected ? l.selected : (l.tints(kind)?.line ?? l.bg)
            let n = side == .old ? cell.old : cell.new
            if kind == .context {
                cell.text = st.sideLine(f, side, n ?? 1) ?? cell.text
            }
            let copy = st.copySide() == side
            h = h
                .fill(fill)
                .hover(l.hover)
                .hoverGroup()
                .role("listitem")
                .label(cell.label())
                .child(bar(kind))
                .child(number(st, i, f, n, side, kind, selected, digits).key("n"))
                .child(code(st, f, cell, copy, side, st.keys[i]).key("code"))
            if let n, d.onCommentFn != nil {
                h = h.child(plus(f, LineRef.new(side, n)).absolute(DIFF_BAR + l.numberW(digits) - 10.0, 2.0))
            }
            return h
        }
        let divider = col().key("divider").w(1.0).selfStretch().fill(look.border)
        return Rune.row()
            .wFull()
            .minH(DIFF_LINE_H)
            .itemsStretch()
            .child(half(.old, old))
            .child(divider)
            .child(half(.new, new))
    }

    func bar(_ kind: LineKind) -> El {
        let b = col().key("bar").w(DIFF_BAR).selfStretch()
        if let t = look.tints(kind) {
            return b.fill(t.bar)
        }
        return b
    }

    /// A line-number cell: pressing it selects the line, shift-pressing extends the selection
    /// to it, and dragging down the numbers selects the lines passed.
    func number(
        _ st: DiffState,
        _ i: Int,
        _ f: Int,
        _ n: UInt32?,
        _ side: DiffSide,
        _ kind: LineKind,
        _ selected: Bool,
        _ digits: UInt32
    ) -> El {
        let l = look
        let isUnified = st.mode() == .unified
        var c = Rune.row()
            .w(l.numberW(digits))
            .minH(DIFF_LINE_H)
            .selfStretch()
            .px(8.0)
            .justifyEnd()
            .itemsStart()
        if !isUnified {
            c = c.fill(l.gutterFill(kind, selected))
        }
        if let n {
            let color = selected ? l.text : (l.tints(kind)?.number ?? l.faint)
            c = c.child(text("\(n)").font(l.font).color(color))
        }
        let atOpt: LineRef?
        if let n {
            atOpt = LineRef.new(side, n)
        } else if isUnified {
            let other: DiffSide = side == .old ? .new : .old
            atOpt = st.rowLine(st.rows[i], other).map { LineRef.new(other, $0) }
        } else {
            atOpt = nil
        }
        guard let at = atOpt else {
            return c
        }
        let modFn = d.modify
        let onSelect = d.onSelectFn
        let rowAt = UInt32(i)
        return c.cursor(.pointer).onDrag { s, drag, tx in
            switch drag.phase {
            case .down:
                modFn(&s) { diffState in
                    diffState.pressLine(f, at)
                }
            case .move:
                let y = drag.y
                modFn(&s) { diffState in
                    guard let rIdx = diffState.rowFrom(rowAt, y) else { return }
                    let rowVal = diffState.rows[Int(rIdx)]
                    guard rowVal.file() == f else { return }
                    // Unified rows hold one side or both: keep to the pressed side where it can.
                    let toOpt: LineRef?
                    if let lineNo = diffState.rowLine(rowVal, side) {
                        toOpt = LineRef.new(side, lineNo)
                    } else if isUnified {
                        let other: DiffSide = side == .old ? .new : .old
                        toOpt = diffState.rowLine(rowVal, other).map { LineRef.new(other, $0) }
                    } else {
                        toOpt = nil
                    }
                    if let to = toOpt {
                        diffState.dragTo(f, to)
                    }
                }
            case .up:
                if drag.cancelled() {
                    modFn(&s) { diffState in
                        diffState.cancelLine()
                    }
                    return
                }
                var released: LineRange? = nil
                modFn(&s) { diffState in
                    released = diffState.releaseLine()
                }
                if let cb = onSelect {
                    cb(&s, released, &tx)
                }
            }
        }
    }

    /// The "+" that appears by the numbers of the hovered line.
    func plus(_ f: Int, _ at: LineRef) -> El {
        let l = look
        let getFn = d.get
        let cb = d.onCommentFn
        return Rune.row()
            .key("plus")
            .size(16.0, 16.0)
            .center()
            .radius(4.0)
            .fill(l.accent)
            .groupOpacity(0.0, 1.0)
            .cursor(.pointer)
            .role("button")
            .label("Comment on this line")
            .child(icon(DIFF_PLUS, 12.0).color(l.onAccent))
            .onPressTx { s, tx in
                let st = getFn(s)
                let lines: LineRange
                if let sel = st.selection(), sel.file == f && st.contains(sel, at) {
                    lines = sel
                } else {
                    lines = LineRange.line(f, at)
                }
                if let cb {
                    cb(&s, lines, &tx)
                }
            }
    }

    /// The code of a line: syntax colours under word changes, tabs padded to four columns.
    func code(
        _ st: DiffState,
        _ f: Int,
        _ c: DiffCell,
        _ copy: Bool,
        _ side: DiffSide,
        _ rowKey: String
    ) -> El {
        let l = look
        let (src, n) = c.source()
        let syntaxColors: [(Range<Int>, Color)] = st.highlights(f, src, n).map { r, p in
            (r, l.syntax.paint(p))
        }
        let wordColor = l.tints(c.kind)?.word
        let spans = diffLayer(
            c.text.utf8.count,
            syntaxColors,
            wordColor != nil ? c.changes : [],
            wordColor
        )
        let (shown, shiftedSpans, pads) = diffTabbed(c.text, spans, st.wraps())
        var t = rich(shown, shiftedSpans).font(l.font).color(l.text).key("text")
        // PORT NOTE: `Rune.rich` sets `wrap = true` and `El.singleLine()` in `Sources/Rune` only clears `wrap`
        // on `InputSpec` elements, so explicitly clear `.wrap(false)` for unwrapped static rich code lines.
        t = st.wraps() ? t.wFull() : t.wrap(false).singleLine()
        if copy {
            t = t.selectable(true).selectionColor(l.selection)
            for padRange in pads {
                t = t.uncopied(padRange)
            }
        }
        let modFn = d.modify
        let cellId = "\(rowKey).\(side.rawValue)"
        var codeEl = col()
            .grow(1.0)
            .minW(0.0)
            .pl(DIFF_CODE_PAD.0)
            .pr(DIFF_CODE_PAD.1)
            .child(t)
            .onHoverChange { s, inside, tx in
                var changed = false
                modFn(&s) { diffState in
                    changed = diffState.hoverText(side, cellId, inside)
                }
                if !changed {
                    tx.liveOnly()
                }
            }
        if c.noNewline {
            codeEl = codeEl.child(
                text("No newline at end of file")
                    .font(l.small)
                    .color(l.muted)
                    .opacity(0.6)
                    .key("eof")
                    .pb(2.0)
            )
        }
        return codeEl
    }

    func gutterW(_ st: DiffState, _ f: Int) -> Float {
        let n = look.numberW(st.digits(f))
        return DIFF_BAR + (st.mode() == .unified ? 2.0 * n : n)
    }

    /// The unchanged lines between two hunks, folded: buttons to show more, and the next
    /// hunk's header.
    func gap(_ st: DiffState, _ f: Int, _ gapIdx: Int) -> El {
        let l = look
        let file = st.files()[f]
        let hidden = st.hidden(f, gapIdx) ?? 0
        let last = gapIdx == file.hunks.count
        let expandable = file.expandable()
        var buttons: [El] = []
        if expandable {
            func addButton(_ how: Expand, _ glyph: Icon, _ btnLabel: String) {
                let modFn = d.modify
                let howKey: String
                switch how {
                case .up: howKey = "Up"
                case .down: howKey = "Down"
                case .all: howKey = "All"
                }
                buttons.append(
                    Rune.row()
                        .key(howKey)
                        .size(24.0, 24.0)
                        .center()
                        .radius(6.0)
                        .hover(l.hover)
                        .cursor(.pointer)
                        .role("button")
                        .label(btnLabel)
                        .child(icon(glyph, 16.0).color(l.muted))
                        .onPressTx { s, _ in
                            modFn(&s) { diffState in
                                diffState.expand(f, gapIdx, how)
                            }
                        }
                )
            }
            let step = min(hidden, EXPAND_STEP)
            if hidden <= EXPAND_STEP {
                addButton(.all, DIFF_EXPAND_ALL, "Show \(hidden) hidden lines")
            } else {
                if gapIdx > 0 {
                    addButton(.down, DIFF_EXPAND_DOWN, "Show \(step) more lines below")
                }
                if !last {
                    addButton(.up, DIFF_EXPAND_UP, "Show \(step) more lines above")
                }
            }
        }
        let buttonsRow = Rune.row()
            .key("expand")
            .w(gutterW(st, f))
            .h(DIFF_GAP_H)
            .center()
            .gap(2.0)
            .children(buttons)
        var inner = Rune.row().key("inner").h(DIFF_GAP_H).itemsCenter().gap(12.0).child(buttonsRow)
        if let w = viewW(st, false) {
            inner = inner.maxW(w).stickyLeft(0.0)
        }
        if hidden > 0 {
            let countEl = text(hidden == 1 ? "1 unchanged line" : "\(hidden) unchanged lines")
                .font(l.small)
                .color(l.muted)
                .key("count")
            let countWrap: El
            if expandable && hidden > EXPAND_STEP {
                let modFn = d.modify
                countWrap = Rune.row()
                    .key("all")
                    .px(6.0)
                    .h(24.0)
                    .itemsCenter()
                    .radius(6.0)
                    .hover(l.hover)
                    .cursor(.pointer)
                    .role("button")
                    .label("Show all \(hidden) lines")
                    .onPressTx { s, _ in
                        modFn(&s) { diffState in
                            diffState.expand(f, gapIdx, .all)
                        }
                    }
                    .child(countEl)
            } else {
                countWrap = Rune.row().key("all").px(6.0).child(countEl)
            }
            inner = inner.child(countWrap)
        }
        if gapIdx >= 0 && gapIdx < file.hunks.count {
            let h = file.hunks[gapIdx]
            inner = inner.child(text(h.header()).font(l.small).color(l.faint).wrap(false).singleLine().key("header"))
        }
        let groupLabel: String
        if gapIdx >= 0 && gapIdx < file.hunks.count {
            groupLabel = "\(hidden) unchanged lines, then \(file.hunks[gapIdx].header())"
        } else {
            groupLabel = "\(hidden) unchanged lines"
        }
        return Rune.row()
            .wFull()
            .h(DIFF_GAP_H)
            .itemsCenter()
            .fill(l.gapBg)
            .role("group")
            .label(groupLabel)
            .child(inner)
    }

    /// A file with no lines to show.
    func note(_ st: DiffState, _ f: Int) -> El {
        let l = look
        let file = st.files()[f]
        let msg: String
        if file.binary {
            msg = "Binary file not shown"
        } else if file.status == .renamed || file.status == .copied {
            msg = "File moved without changes"
        } else if file.oldMode != file.newMode {
            msg = "File mode changed"
        } else if file.status == .added || file.status == .deleted {
            msg = "Empty file"
        } else {
            msg = "No changes"
        }
        var inner = Rune.row()
            .key("inner")
            .h(DIFF_NOTE_H)
            .itemsCenter()
            .pl(gutterW(st, f) + DIFF_CODE_PAD.0)
            .child(text(msg).font(l.small).color(l.muted))
        if let w = viewW(st, false) {
            inner = inner.maxW(w).stickyLeft(0.0)
        }
        return Rune.row().wFull().h(DIFF_NOTE_H).fill(l.bg).role("note").label(msg).child(inner)
    }

    func fileHeader(_ s: S, _ st: DiffState, _ f: Int, sticky: Bool) -> El {
        let l = look
        let file = st.files()[f]
        let isCollapsed = st.collapsed(f)
        let modFn = d.modify
        let toggle = Rune.row()
            .key("toggle")
            .size(24.0, 24.0)
            .center()
            .radius(6.0)
            .hover(l.hover)
            .cursor(.pointer)
            .role("button")
            .label(isCollapsed ? "Expand file" : "Collapse file")
            .child(icon(isCollapsed ? l.triangleRight : l.triangleDown, 16.0).color(l.muted))
            .onPressTx { state, tx in
                modFn(&state) { diffState in
                    diffState.setCollapsed(f, !diffState.collapsed(f))
                    if sticky {
                        diffState.scrollToFile(f, &tx)
                    }
                }
            }
        func pathEl(_ p: String, _ c: Color) -> El {
            text(p).font(l.label).color(c).truncateHead().minW(0.0).shrink()
        }
        var name = Rune.row().key("path").itemsCenter().gap(6.0).minW(0.0).shrink()
        if (file.status == .renamed || file.status == .copied),
           let a = file.oldPath,
           let b = file.newPath
        {
            name = name
                .child(pathEl(a, l.muted).key("old"))
                .child(text("→").font(l.label).color(l.faint).key("arrow"))
                .child(pathEl(b, l.text).key("new"))
        } else {
            name = name.child(pathEl(file.path(), l.text).key("new"))
        }
        let statusBadge: (String, Color)?
        switch file.status {
        case .added:
            statusBadge = ("Added", l.add.count)
        case .deleted:
            statusBadge = ("Deleted", l.del.count)
        case .renamed:
            statusBadge = ("Renamed", l.muted)
        case .copied:
            statusBadge = ("Copied", l.muted)
        case .modified:
            statusBadge = nil
        }
        var inner = Rune.row()
            .key("inner")
            .wFull()
            .grow(1.0)
            .px(10.0)
            .gap(8.0)
            .itemsCenter()
            .child(toggle)
            .child(name)
        if let (word, color) = statusBadge {
            inner = inner.child(text(word).font(l.small).color(color).key("status"))
        }
        if let a = file.oldMode, let b = file.newMode, a != b {
            inner = inner.child(text("\(a) → \(b)").font(l.small).color(l.faint).key("mode"))
        }
        inner = inner.child(Rune.row().key("space").grow(1.0))
        let adds = file.additions()
        let dels = file.deletions()
        if adds > 0 {
            inner = inner.child(text("+\(adds)").font(l.small).color(l.add.count).key("adds"))
        }
        if dels > 0 {
            inner = inner.child(text("−\(dels)").font(l.small).color(l.del.count).key("dels"))
        }
        if let headerActions = d.headerFn {
            inner = inner.child(headerActions(s, f).key("actions"))
        }
        var headerLabel = file.path()
        if file.status == .renamed, let a = file.oldPath {
            headerLabel.append(", renamed from \(a)")
        }
        headerLabel.append(", \(adds) added, \(dels) removed")
        func rule(_ ruleKey: String, _ c: Color) -> El {
            col().key(ruleKey).wFull().h(1.0).fill(c)
        }
        var h = col().wFull().h(DIFF_HEADER_H).fill(l.headerBg).role("heading").label(headerLabel)
        // In the list, as wide as the view and held to its left edge while the code scrolls
        // sideways, so the counts and actions stay in sight.
        if !sticky, let w = viewW(st, false) {
            h = h.w(w).stickyLeft(0.0)
        }
        h = h.child(rule("top", (f > 0 && !sticky) ? l.border : l.headerBg))
        return h.child(inner).child(rule("bottom", l.border))
    }
}

/// An annotation's widget, keyed by its id so it keeps its state as rows come and go.
private func diffAnnotationNote(_ el: El, _ a: Annotation) -> El {
    col().key("a.\(a.id)").wFull().child(el)
}

/// Spans for a line from its syntax colours and the byte ranges given `bg` (word changes):
/// cut where either starts or ends, so each piece has one colour and one background.
func diffLayer(
    _ len: Int,
    _ syntax: [(Range<Int>, Color)],
    _ words: [Range<Int>],
    _ bg: Color?
) -> [Span] {
    var rawCuts: [Int] = []
    rawCuts.reserveCapacity((syntax.count + words.count) * 2)
    for (r, _) in syntax {
        if r.lowerBound >= 0 && r.lowerBound <= len {
            rawCuts.append(r.lowerBound)
        }
        if r.upperBound >= 0 && r.upperBound <= len {
            rawCuts.append(r.upperBound)
        }
    }
    for r in words {
        if r.lowerBound >= 0 && r.lowerBound <= len {
            rawCuts.append(r.lowerBound)
        }
        if r.upperBound >= 0 && r.upperBound <= len {
            rawCuts.append(r.upperBound)
        }
    }
    guard rawCuts.count >= 2 else { return [] }
    rawCuts.sort()
    var cuts: [Int] = []
    cuts.reserveCapacity(rawCuts.count)
    for c in rawCuts {
        if cuts.last != c {
            cuts.append(c)
        }
    }
    guard cuts.count >= 2 else { return [] }

    var out: [Span] = []
    for idx in 0..<(cuts.count - 1) {
        let a = cuts[idx]
        let b = cuts[idx + 1]
        let synIdx = diffPartitionPoint(syntax) { $0.0.upperBound <= a }
        let color: Color? = (synIdx < syntax.count && syntax[synIdx].0.lowerBound <= a)
            ? syntax[synIdx].1
            : nil
        let wordIdx = diffPartitionPoint(words) { $0.upperBound <= a }
        let on = wordIdx < words.count && words[wordIdx].lowerBound <= a
        let spanBg: Color? = on ? bg : nil
        if color == nil && spanBg == nil {
            continue
        }
        if !out.isEmpty,
           Int(out[out.count - 1].end) == a,
           out[out.count - 1].color == color,
           out[out.count - 1].bg == spanBg
        {
            out[out.count - 1].end = UInt32(b)
        } else {
            var sp = Span.new(a, b)
            sp.color = color
            sp.bg = spanBg
            out.append(sp)
        }
    }
    return out
}

/// `code` as drawn: text layout draws a tab as one space, so each tab is followed by spaces up
/// to the next four-column stop; and when `wrap`, a zero-width space after `.`, `(`, `[` and
/// `/` lets a long call chain or path break there. Returns the text, `spans` moved to match,
/// and the inserted ranges (drawn, never copied).
func diffTabbed(_ code: String, _ spans: [Span], _ wrap: Bool) -> (String, [Span], [Range<Int>]) {
    let hasTab = code.utf8.contains(0x09)
    let hasBreakable = wrap && code.utf8.contains(where: { $0 == 0x2E || $0 == 0x28 || $0 == 0x5B || $0 == 0x2F })
    if !hasTab && !hasBreakable {
        return (code, spans, [])
    }
    let scalars = Array(code.unicodeScalars)
    var shownScalars = String.UnicodeScalarView()
    shownScalars.reserveCapacity(scalars.count + 8)
    // (byte in `code` after the insertion, bytes added up to and including it)
    var shifts: [(Int, Int)] = []
    var pads: [Range<Int>] = []
    var col = 0
    var codeByte = 0
    var shownByte = 0
    for idx in scalars.indices {
        let ch = scalars[idx]
        let chBytes = ch.utf8.count
        shownScalars.append(ch)
        shownByte += chBytes
        col += 1
        let start = shownByte
        if ch == "\t" {
            let pad = 3 - ((col - 1) % 4)
            if pad > 0 {
                for _ in 0..<pad {
                    shownScalars.append(" ")
                }
                shownByte += pad
                col += pad
            }
        } else if wrap && (ch == "." || ch == "(" || ch == "[" || ch == "/") {
            if idx + 1 < scalars.count && !scalars[idx + 1].properties.isWhitespace {
                shownScalars.append("\u{200B}")
                shownByte += 3
            }
        }
        if shownByte > start {
            let added = shownByte - start
            pads.append(start..<shownByte)
            let prevShift = shifts.last?.1 ?? 0
            shifts.append((codeByte + chBytes, prevShift + added))
        }
        codeByte += chBytes
    }
    func shift(_ b: UInt32) -> UInt32 {
        let n = diffPartitionPoint(shifts) { $0.0 <= Int(b) }
        return n == 0 ? b : (b + UInt32(shifts[n - 1].1))
    }
    var outSpans = spans
    for idx in outSpans.indices {
        outSpans[idx].start = shift(outSpans[idx].start)
        outSpans[idx].end = shift(outSpans[idx].end)
    }
    return (String(shownScalars), outSpans, pads)
}
