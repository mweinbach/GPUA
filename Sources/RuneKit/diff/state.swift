// Ported from: crates/rune-kit/src/diff/state.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a diff view shows and where: the rows files, hunks and expanded ranges make, the
//! selection, annotations, the side text selection copies, and the reading position.

#if !os(WASI)
import Foundation
#endif
import Rune

/// How a diff lays out its two sides.
public enum DiffMode: Sendable, Equatable, Hashable {
    /// One column, removed lines above the added lines that replace them.
    case unified
    /// Old on the left, new on the right, changed lines side by side.
    case split

    public static let `default`: DiffMode = .unified
}

/// A line of one side of a file: what annotations and selections point at.
public struct LineRef: Sendable, Equatable, Hashable {
    public var side: DiffSide
    /// 1-based.
    public var line: UInt32

    public init(side: DiffSide, line: UInt32) {
        self.side = side
        self.line = line
    }

    public static func new(_ side: DiffSide, _ line: UInt32) -> LineRef {
        LineRef(side: side, line: line)
    }
}

/// Selected lines of one file, from where the selection started to where it ends (either
/// way round), as a click, shift-click or drag down the line numbers makes them.
public struct LineRange: Sendable, Equatable, Hashable {
    public var file: Int
    public var start: LineRef
    public var end: LineRef

    public init(file: Int, start: LineRef, end: LineRef) {
        self.file = file
        self.start = start
        self.end = end
    }

    /// One line.
    public static func line(_ file: Int, _ at: LineRef) -> LineRange {
        LineRange(file: file, start: at, end: at)
    }
}

/// A widget the app shows under a line, such as a review comment or a composer. The app
/// builds it from `id` (see ``DiffView/annotation(_:)``).
public struct Annotation: Sendable, Equatable, Hashable {
    public var file: Int
    public var at: LineRef
    public var id: String

    public init(file: Int, at: LineRef, id: String) {
        self.file = file
        self.at = at
        self.id = id
    }

    public static func new(_ file: Int, _ at: LineRef, _ id: String) -> Annotation {
        Annotation(file: file, at: at, id: id)
    }
}

/// Which way an unchanged range between hunks opens.
public enum Expand: Sendable, Equatable, Hashable {
    /// Twenty lines up from the hunk below it.
    case up
    /// Twenty lines down from the hunk above it.
    case down
    /// All of it.
    case all
}

/// Lines one expand step reveals.
public let EXPAND_STEP: UInt32 = 20

/// Row heights in points. Lines are fixed unless they wrap or carry annotations.
let DIFF_LINE_H: Float = 20.0
let DIFF_HEADER_H: Float = 44.0
let DIFF_GAP_H: Float = 32.0
let DIFF_NOTE_H: Float = 40.0

/// One row of the virtual list.
enum DiffRow: Sendable, Equatable {
    /// A file's header.
    case file(UInt32)
    /// A file with no lines to show: binary, or only renamed or re-moded.
    case note(UInt32)
    /// The unchanged range before hunk `gap` (the last one: after the last hunk), with its
    /// expand buttons and the hunk's header.
    case gap(f: UInt32, gap: UInt32)
    /// An unchanged line revealed from a range, by its old and new numbers.
    case ctx(f: UInt32, old: UInt32, new: UInt32)
    /// Line `i` of hunk `h`. In split mode, one without a partner on the other side.
    case line(f: UInt32, h: UInt32, i: UInt32)
    /// Split mode: removed line `del` beside added line `add`, both of hunk `h`.
    case pair(f: UInt32, h: UInt32, del: UInt32, add: UInt32)

    func file() -> Int {
        switch self {
        case .file(let f), .note(let f), .gap(let f, _), .ctx(let f, _, _), .line(let f, _, _), .pair(let f, _, _, _):
            return Int(f)
        }
    }
}

private struct DiffFileUi {
    var collapsed: Bool = false
    /// Lines revealed at the top and bottom of each unchanged range (`hunks.count + 1` of them).
    var revealed: [(UInt32, UInt32)] = []
}

/// An unchanged range before a hunk: its first old and new line numbers and its length
/// (`nil` when unknown: after the last hunk without the whole text).
struct DiffGap: Sendable, Equatable {
    var old: UInt32
    var new: UInt32
    var len: UInt32?
}

private struct DiffLineMapKey: Hashable, Sendable {
    let file: UInt32
    let side: DiffSide
    let line: UInt32
}

private struct DiffChunkKey: Hashable, Sendable {
    let file: UInt32
    let side: DiffSide
    let chunk: UInt32
}

/// Highlights of 128 lines of one side, by line number.
private final class DiffChunk: Sendable {
    /// Byte offset of each line in the chunk's text, and one past the last.
    let starts: [UInt32]
    let hl: [syntax.Highlight]

    init(starts: [UInt32], hl: [syntax.Highlight]) {
        self.starts = starts
        self.hl = hl
    }
}

private let DIFF_CHUNK: UInt32 = 128

/// Shared interior cache mirroring `RefCell<HashMap<..., Rc<Chunk>>>` and `Cell<f32>` in `DiffState`
/// so read-only view builds (`DiffView.build`) retain chunk highlights and viewport width across commits.
private final class DiffInteriorCache {
    fileprivate var chunks: [DiffChunkKey: DiffChunk] = [:]
    var viewW: Float

    init(viewW: Float = 0.0) {
        self.viewW = viewW
    }
}

#if !os(WASI)
private let diffKeysRevLock = NSLock()
#endif
// PORT NOTE: Guarded by `diffKeysRevLock` (and single-threaded on WASI) to match `AtomicU64` in `crates/rune-kit/src/diff/state.rs`.
nonisolated(unsafe) private var nextDiffKeysRevValue: UInt64 = 1

private func nextDiffKeysRev() -> UInt64 {
    #if !os(WASI)
    diffKeysRevLock.lock()
    defer { diffKeysRevLock.unlock() }
    #endif
    let v = nextDiffKeysRevValue
    nextDiffKeysRevValue &+= 1
    return v
}

private func decimalDigits(_ value: UInt32) -> UInt32 {
    var v = max(value, 1)
    var d: UInt32 = 1
    while v >= 10 {
        v /= 10
        d += 1
    }
    return d
}

func diffPartitionPoint<T>(_ items: [T], _ pred: (T) -> Bool) -> Int {
    var lo = 0
    var hi = items.count
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        if pred(items[mid]) {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    return lo
}

/// A diff and everything about how it is shown: the app keeps one in its state and
/// ``DiffView`` draws it.
public struct DiffState: CustomDebugStringConvertible {
    private var fileList: [FileDiff] = []
    private var ui: [DiffFileUi] = []
    private var modeValue: DiffMode = .unified
    private var wrapValue: Bool = false
    private var annotationList: [Annotation] = []
    private var byLine: [DiffLineMapKey: [UInt32]] = [:]
    private var selectionValue: LineRange? = nil
    var selecting: Bool = false
    private var selectionAtPress: LineRange? = nil
    /// The press was on the one selected line: it clears the selection unless it drags.
    var unselect: Bool = false
    var shift: Bool = false
    /// The side text selection copies, which follows the pointer.
    private var copySideValue: DiffSide = .new
    private var hovered: [(DiffSide, String)] = []
    private var highlighter: Highlighter = .builtin()
    private var interior: DiffInteriorCache = DiffInteriorCache()
    /// Per file, per hunk, per side: the index in the hunk of each of its lines on that side.
    private var sideLines: [[([UInt32], [UInt32])]] = []
    private var fileGaps: [[DiffGap]] = []
    /// Per file, the digits its line numbers take (at least three).
    private var digitsPerFile: [UInt32] = []
    /// The widest line of any file, in columns.
    private var maxColumns: UInt32 = 0
    var rows: [DiffRow] = []
    var keys: [String] = []
    private var rowOf: [DiffLineMapKey: UInt32] = [:]
    private var fileRows: [UInt32] = []
    private var hunkRows: [UInt32] = []
    /// Bumped whenever the rows change, so built rows rebuild.
    var rev: UInt64 = 0
    /// Changes with `keys`, unique across states so a swapped-in state never matches.
    var keysRev: UInt64 = 0
    private var visibleRows: Range<Int> = 0..<0
    private var visible: Int = 0
    /// The visible file last reported to the app.
    private var reported: Int? = nil
    private var nav: UInt32? = nil

    public init(_ files: [FileDiff] = []) {
        setFiles(files)
    }

    public static func new(_ files: [FileDiff]) -> DiffState {
        DiffState(files)
    }

    public static var `default`: DiffState {
        DiffState()
    }

    public var debugDescription: String {
        "DiffState { files: \(fileList.count), rows: \(rows.count), mode: \(modeValue) }"
    }

    /// Show `files` instead, every range collapsed again and the selection cleared.
    /// Annotations stay; drop or remap them with ``setAnnotations(_:)``.
    public mutating func setFiles(_ files: [FileDiff]) {
        self.ui = files.map { f in
            DiffFileUi(collapsed: false, revealed: Array(repeating: (0, 0), count: f.hunks.count + 1))
        }
        self.sideLines = files.map { f in
            f.hunks.map { h in
                func on(_ side: DiffSide) -> [UInt32] {
                    var out: [UInt32] = []
                    for idx in h.lines.indices where h.lines[idx].number(side) != nil {
                        out.append(UInt32(idx))
                    }
                    return out
                }
                return (on(.old), on(.new))
            }
        }
        self.fileGaps = files.map(computeDiffGaps)
        self.digitsPerFile = files.map { f in
            max(decimalDigits(max(f.lastLine(), 1)), 3)
        }
        self.maxColumns = files.map { $0.columns() }.max() ?? 0
        self.fileList = files
        self.selectionValue = nil
        self.interior = DiffInteriorCache(viewW: self.interior.viewW)
        self.visible = 0
        self.reported = nil
        self.visibleRows = 0..<0
        indexAnnotations()
        rebuild()
    }

    public func files() -> [FileDiff] {
        fileList
    }

    /// The index of the file at `path` (its new path, or old for a deleted file).
    public func fileIndex(_ path: String) -> Int? {
        fileList.firstIndex { f in
            f.path() == path || f.oldPath == path
        }
    }

    public func mode() -> DiffMode {
        modeValue
    }

    /// Switch between unified and split. Rows keep their keys where they can (unchanged and
    /// removed lines), so a switch made in a handler that calls `Tx.motion` springs them to
    /// their new places.
    public mutating func setMode(_ mode: DiffMode) {
        if modeValue != mode {
            modeValue = mode
            rebuild()
        }
    }

    public func wrap() -> Bool {
        wrapValue
    }

    /// Whether long lines wrap as drawn: split always wraps, each side half the width.
    func wraps() -> Bool {
        wrapValue || modeValue == .split
    }

    /// Wrap long lines (rows grow), or keep them on one line and scroll sideways (the default).
    /// Split wraps either way, as side-by-side review does, so both sides stay in view.
    public mutating func setWrap(_ wrap: Bool) {
        if wrapValue != wrap {
            wrapValue = wrap
            rev &+= 1
        }
    }

    /// Highlight code with `h` instead of the built-in scanners.
    public mutating func setHighlighter(_ h: Highlighter) {
        highlighter = h
        interior = DiffInteriorCache(viewW: interior.viewW)
        rev &+= 1
    }

    public func collapsed(_ file: Int) -> Bool {
        guard file >= 0, file < ui.count else { return false }
        return ui[file].collapsed
    }

    /// Show only `file`'s header, or its lines again.
    public mutating func setCollapsed(_ file: Int, _ collapsed: Bool) {
        guard file >= 0, file < ui.count, ui[file].collapsed != collapsed else { return }
        ui[file].collapsed = collapsed
        rebuild()
    }

    /// Lines of `file`'s unchanged range before hunk `gap` still hidden, when known.
    public func hidden(_ file: Int, _ gap: Int) -> UInt32? {
        guard file >= 0, file < fileGaps.count,
              gap >= 0, gap < fileGaps[file].count
        else {
            return nil
        }
        let g = fileGaps[file][gap]
        let (top, bottom) = ui[file].revealed[gap]
        return g.len.map { n in n.saturatingSub(top.saturatingAdd(bottom)) }
    }

    /// Reveal more of `file`'s unchanged range before hunk `gap` (`hunks.count`: after the
    /// last). Does nothing without the file's whole text.
    public mutating func expand(_ file: Int, _ gap: Int, _ how: Expand) {
        guard let hiddenCount = hidden(file, gap),
              hiddenCount > 0,
              fileList[file].expandable()
        else {
            return
        }
        let last = gap == fileList[file].hunks.count
        switch how {
        case .all:
            // Nothing below the first range and nothing above the last to grow from.
            ui[file].revealed[gap].0 += hiddenCount
        case .up:
            if last {
                ui[file].revealed[gap].0 += min(hiddenCount, EXPAND_STEP)
            } else {
                ui[file].revealed[gap].1 += min(hiddenCount, EXPAND_STEP)
            }
        case .down:
            ui[file].revealed[gap].0 += min(hiddenCount, EXPAND_STEP)
        }
        rebuild()
    }

    public func annotations() -> [Annotation] {
        annotationList
    }

    /// Show these annotations under their lines, in order where several share a line.
    public mutating func setAnnotations(_ annotations: [Annotation]) {
        annotationList = annotations
        indexAnnotations()
        rev &+= 1
    }

    /// The annotations under `file`'s line `at`.
    func annotationsAt(_ file: Int, _ at: LineRef) -> [Annotation] {
        guard file >= 0 else { return [] }
        let key = DiffLineMapKey(file: UInt32(file), side: at.side, line: at.line)
        guard let indices = byLine[key] else { return [] }
        return indices.map { annotationList[Int($0)] }
    }

    private mutating func indexAnnotations() {
        byLine.removeAll()
        for (i, a) in annotationList.enumerated() where a.file >= 0 {
            let key = DiffLineMapKey(file: UInt32(a.file), side: a.at.side, line: a.at.line)
            byLine[key, default: []].append(UInt32(i))
        }
    }

    public func selection() -> LineRange? {
        selectionValue
    }

    public mutating func setSelection(_ sel: LineRange?) {
        selectionValue = sel
    }

    /// The selected lines' text on the side the selection started on, one per line, without
    /// numbers or markers: what copying the selection gives.
    public func selectedText() -> String? {
        guard let sel = selectionValue else { return nil }
        let side = sel.start.side
        guard let (a, b) = selectedRows(sel) else { return nil }
        var out: [String] = []
        for r in a...b {
            if let n = rowLine(rows[Int(r)], side) {
                out.append(sideLine(sel.file, side, n) ?? "")
            }
        }
        return out.joined(separator: "\n")
    }

    /// The selection's first and last rows.
    private func selectedRows(_ sel: LineRange) -> (UInt32, UInt32)? {
        guard sel.file >= 0 else { return nil }
        let f = UInt32(sel.file)
        guard let a = rowOf[DiffLineMapKey(file: f, side: sel.start.side, line: sel.start.line)],
              let b = rowOf[DiffLineMapKey(file: f, side: sel.end.side, line: sel.end.line)]
        else {
            return nil
        }
        return (min(a, b), max(a, b))
    }

    /// Whether line `at` is in `sel`.
    func contains(_ sel: LineRange, _ at: LineRef) -> Bool {
        guard sel.file >= 0, let (a, b) = selectedRows(sel) else { return false }
        guard let r = rowOf[DiffLineMapKey(file: UInt32(sel.file), side: at.side, line: at.line)] else {
            return false
        }
        return r >= a && r <= b
    }

    /// Whether row `r`'s line on `side` is selected.
    func rowSelected(_ r: Int, _ side: DiffSide?) -> Bool {
        guard r >= 0, r < rows.count,
              let sel = selectionValue,
              let (a, b) = selectedRows(sel)
        else {
            return false
        }
        if rows[r].file() != sel.file || r < Int(a) || r > Int(b) {
            return false
        }
        guard let s = side else { return true }
        return s == sel.start.side || s == sel.end.side
    }

    /// A press on line `at`'s number: a new selection, or with Shift held one extended to it.
    /// Pressing the one selected line clears it on release, unless the press drags.
    mutating func pressLine(_ file: Int, _ at: LineRef) {
        selectionAtPress = selectionValue
        let sel: LineRange
        if let s = selectionValue, shift && s.file == file {
            sel = LineRange(file: s.file, start: s.start, end: at)
        } else {
            sel = LineRange.line(file, at)
        }
        unselect = !shift && selectionValue == sel
        selecting = true
        setSelection(sel)
    }

    /// The pointer, dragging from a line number, reached line `at`.
    mutating func dragTo(_ file: Int, _ at: LineRef) {
        if let s = selectionValue, selecting && s.file == file && s.end != at {
            unselect = false
            setSelection(LineRange(file: s.file, start: s.start, end: at))
        }
    }

    /// The press on the line numbers ended: the selection it leaves.
    @discardableResult
    mutating func releaseLine() -> LineRange? {
        selectionAtPress = nil
        if unselect {
            unselect = false
            selectionValue = nil
        }
        selecting = false
        return selectionValue
    }

    mutating func cancelLine() {
        if selecting {
            selectionValue = selectionAtPress
            selectionAtPress = nil
        }
        selecting = false
        unselect = false
    }

    func copySide() -> DiffSide {
        copySideValue
    }

    /// Notes the pointer entering or leaving a line's code; returns whether that changed the
    /// side a selection copies, the only part the view reads.
    @discardableResult
    mutating func hoverText(_ side: DiffSide, _ cell: String, _ inside: Bool) -> Bool {
        let was = copySideValue
        if inside {
            if !hovered.contains(where: { $0.1 == cell }) {
                hovered.append((side, cell))
            }
            if hovered.allSatisfy({ $0.0 == side }) {
                copySideValue = side
            }
        } else {
            hovered.removeAll { $0.1 == cell }
        }
        return copySideValue != was
    }

    public func visibleFile() -> Int {
        visible
    }

    /// Scroll `file`'s header to the top.
    public mutating func scrollToFile(_ file: Int, _ tx: inout Tx) {
        guard file >= 0, file < fileRows.count else { return }
        let r = fileRows[file]
        revealAtTop(r, &tx)
        visible = file
        nav = r
    }

    /// Scroll to `file`'s line `at`, opening the range it's in if it's hidden, and put it
    /// below the header.
    public mutating func scrollToLine(_ file: Int, _ at: LineRef, _ tx: inout Tx) {
        guard file >= 0, file < fileList.count else { return }
        if collapsed(file) {
            setCollapsed(file, false)
        }
        let targetKey = DiffLineMapKey(file: UInt32(file), side: at.side, line: at.line)
        if rowOf[targetKey] == nil {
            if let gapIdx = fileGaps[file].firstIndex(where: { g in
                let first = at.side == .old ? g.old : g.new
                guard at.line >= first else { return false }
                if let n = g.len {
                    return at.line < first.saturatingAdd(n)
                }
                return true
            }) {
                expand(file, gapIdx, .all)
            }
        }
        guard let r = rowOf[targetKey] else { return }
        revealBelowHeader(r, &tx)
        visible = file
        nav = r
    }

    /// Bring the next (or previous) hunk to just below the sticky header.
    @discardableResult
    public mutating func nextHunk(_ forward: Bool, _ tx: inout Tx) -> Bool {
        let from = position()
        let target: UInt32?
        if forward {
            target = hunkRows.first { $0 > from }
        } else {
            target = hunkRows.last { $0 < from }
        }
        guard let r = target else { return false }
        revealBelowHeader(r, &tx)
        visible = rows[Int(r)].file()
        nav = r
        return true
    }

    /// Scroll to the next (or previous) file's header.
    @discardableResult
    public mutating func nextFile(_ forward: Bool, _ tx: inout Tx) -> Bool {
        let pos = Int(position())
        guard pos >= 0, pos < rows.count else { return false }
        let at = rows[pos].file()
        let target = forward ? (at + 1) : (at - 1)
        guard target >= 0, target < fileList.count else { return false }
        scrollToFile(target, &tx)
        return true
    }

    /// The row under the sticky header: where navigation last put it, unless the list has
    /// scrolled away since.
    private func position() -> UInt32 {
        let top = rowBelowHeader()
        switch (nav, top) {
        case (let n?, let t?) where (t >= n ? (t - n) : (n - t)) <= 3:
            return n
        case (_, let t?):
            return t
        case (let n?, nil):
            return n
        case (nil, nil):
            return 0
        }
    }

    private func rowBelowHeader() -> UInt32? {
        if visibleRows.isEmpty {
            return nil
        }
        var r = visibleRows.lowerBound
        if sticky() != nil {
            var room: Float = 0.0
            while r + 1 < rows.count && room < DIFF_HEADER_H {
                room += estimate(r)
                r += 1
            }
        }
        return UInt32(r)
    }

    /// Handle a key for the diff: `j`/`k` next and previous hunk, `]`/`[` next and previous
    /// file, Escape clears the line selection, Cmd-C copies it, and Shift (with
    /// `App.modifierKeys`) makes a click on a line number extend the selection. Call it
    /// from the app's `onKey`; it returns whether it took the key.
    public mutating func key(_ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        switch ev.key {
        case .modifier(let modifier, _) where modifier == .shiftLeft || modifier == .shiftRight:
            shift = ev.mods.shift
            return false
        default:
            break
        }
        if tx.focused() != nil && !ev.isCommand("c") {
            return false
        }
        switch ev.key {
        case .text(let t) where !ev.mods.cmd && !ev.mods.ctrl && !ev.mods.alt:
            switch t {
            case "j":
                return nextHunk(true, &tx)
            case "k":
                return nextHunk(false, &tx)
            case "]":
                return nextFile(true, &tx)
            case "[":
                return nextFile(false, &tx)
            default:
                return false
            }
        // PORT NOTE: In `Sources/Rune/runtime/input/input_keys.swift`, `onKey` runs before active-drag
        // `Escape` cancellation (`pointerCancel()`), whereas upstream Rust cancels active drags first;
        // guarding `!selecting` preserves both `Escape` clearing idle selection and `Escape` cancelling gutter drags.
        case .escape where selectionValue != nil && !selecting:
            setSelection(nil)
            return true
        default:
            if ev.isCommand("c") {
                if let text = selectedText() {
                    tx.copy(text)
                    return true
                }
                return false
            }
            return false
        }
    }

    /// The scroll viewport's rect.
    func setViewport(_ r: [Float]) {
        if r.count >= 3 {
            interior.viewW = r[2]
        }
    }

    func viewWidth() -> Float {
        interior.viewW
    }

    /// The virtual list's visible row range changed to `rows`: returns `(reportedFile, stickyChanged)`.
    mutating func setVisibleRows(_ rowsRange: Range<Int>) -> (Int?, Bool) {
        let beforeSticky = sticky()
        visibleRows = rowsRange
        if rowsRange.lowerBound >= 0 && rowsRange.lowerBound < rows.count {
            visible = rows[rowsRange.lowerBound].file()
        }
        let reportedFile: Int?
        if !fileList.isEmpty && reported != visible {
            reported = visible
            reportedFile = visible
        } else {
            reportedFile = nil
        }
        return (reportedFile, sticky() != beforeSticky)
    }

    /// The row reached by moving `y` points vertically from the top of row `from`.
    func rowFrom(_ from: UInt32, _ y: Float) -> UInt32? {
        guard !rows.isEmpty else { return nil }
        var r = min(Int(from), rows.count - 1)
        var rem = y
        while rem < 0.0 && r > 0 {
            r -= 1
            rem += estimate(r)
        }
        while r + 1 < rows.count {
            let h = estimate(r)
            if rem < h {
                break
            }
            rem -= h
            r += 1
        }
        return UInt32(r)
    }

    /// The visible file's header has scrolled above the viewport's top, so a copy of it sticks
    /// there.
    func sticky() -> Int? {
        if fileList.isEmpty || visibleRows.isEmpty {
            return nil
        }
        let f = visible
        guard f >= 0, f < fileRows.count else { return nil }
        let header = Int(fileRows[f])
        return visibleRows.lowerBound > header ? f : nil
    }

    /// Scroll so row `r` is at the top: to the end first, so the reveal comes from below.
    private func revealAtTop(_ r: UInt32, _ tx: inout Tx) {
        if let last = keys.last {
            tx.scrollIntoView(last)
        }
        let idx = Int(r)
        if idx >= 0 && idx < keys.count {
            tx.scrollIntoView(keys[idx])
        }
    }

    /// Scroll so row `r` sits just below the sticky header: the row a header's height above
    /// it goes to the top.
    private func revealBelowHeader(_ r: UInt32, _ tx: inout Tx) {
        var top = Int(r)
        var room: Float = 0.0
        while top > 0 && room < DIFF_HEADER_H {
            if case .file = rows[top] {
                break
            }
            top -= 1
            room += estimate(top)
        }
        revealAtTop(UInt32(top), &tx)
    }

    private func estimate(_ r: Int) -> Float {
        switch rows[r] {
        case .file:
            return DIFF_HEADER_H
        case .note:
            return DIFF_NOTE_H
        case .gap:
            return DIFF_GAP_H
        case .ctx, .line, .pair:
            return DIFF_LINE_H
        }
    }

    /// Line `n` of `side` of file `f`, from its whole text, its hunks or an unchanged range.
    func sideLine(_ f: Int, _ side: DiffSide, _ n: UInt32) -> String? {
        guard f >= 0, f < fileList.count else { return nil }
        let file = fileList[f]
        let hunks = file.hunks
        let h = diffPartitionPoint(hunks) { $0.end(side) <= n }
        if h < hunks.count && hunks[h].first(side) <= n {
            let hunk = hunks[h]
            let sideArr = side == .old ? sideLines[f][h].0 : sideLines[f][h].1
            let offset = Int(n - hunk.first(side))
            guard offset >= 0, offset < sideArr.count else { return nil }
            let lineIdx = Int(sideArr[offset])
            return hunk.lines[lineIdx].text
        }
        let g = fileGaps[f][h]
        let start = side == .old ? g.old : g.new
        guard n >= start else { return nil }
        let off = n - start
        return file.contextLine(g.old.saturatingAdd(off), g.new.saturatingAdd(off))
    }

    /// Colour-only highlights of line `n` of `side` of file `f`, relative to the line.
    func highlights(_ f: Int, _ side: DiffSide, _ n: UInt32) -> [syntax.Highlight] {
        guard f >= 0, f < fileList.count else { return [] }
        let lang = fileList[f].language()
        if highlighter.isBuiltin() && !(lang.map(syntax.known) ?? false) {
            return []
        }
        let c = n.saturatingSub(1) / DIFF_CHUNK
        let key = DiffChunkKey(file: UInt32(f), side: side, chunk: c)
        let chunk: DiffChunk
        if let cached = interior.chunks[key] {
            chunk = cached
        } else {
            var text = ""
            var starts: [UInt32] = []
            starts.reserveCapacity(Int(DIFF_CHUNK) + 1)
            var byteLen: UInt32 = 0
            for m in (c * DIFF_CHUNK + 1)...((c + 1) * DIFF_CHUNK) {
                starts.append(byteLen)
                let line = sideLine(f, side, m) ?? ""
                text.append(line)
                text.append("\n")
                byteLen += UInt32(line.utf8.count) + 1
            }
            starts.append(byteLen)
            let hl = highlighter.highlight(lang, text)
            let built = DiffChunk(starts: starts, hl: hl)
            if interior.chunks.count > 512 {
                interior.chunks.removeAll()
            }
            interior.chunks[key] = built
            chunk = built
        }
        let k = Int(n.saturatingSub(1) % DIFF_CHUNK)
        let a = Int(chunk.starts[k])
        let b = Int(chunk.starts[k + 1]) - 1
        let first = diffPartitionPoint(chunk.hl) { $0.0.upperBound <= a }
        var out: [syntax.Highlight] = []
        var idx = first
        while idx < chunk.hl.count {
            let (r, p) = chunk.hl[idx]
            if r.lowerBound >= b {
                break
            }
            let lo = max(r.lowerBound, a) - a
            let hi = min(r.upperBound, b) - a
            if lo < hi {
                out.append((lo..<hi, p))
            }
            idx += 1
        }
        return out
    }

    /// Row `r`'s line number on `side`.
    func rowLine(_ r: DiffRow, _ side: DiffSide) -> UInt32? {
        switch r {
        case .ctx(_, let old, let new):
            return side == .old ? old : new
        case .line(let f, let h, let i):
            return fileList[Int(f)].hunks[Int(h)].lines[Int(i)].number(side)
        case .pair(let f, let h, let del, let add):
            let i = side == .old ? del : add
            return fileList[Int(f)].hunks[Int(h)].lines[Int(i)].number(side)
        case .file, .note, .gap:
            return nil
        }
    }

    /// Lay the rows out again from the files, modes and expanded ranges.
    private mutating func rebuild() {
        rev &+= 1
        nav = nil
        var newRows: [DiffRow] = []
        fileRows.removeAll(keepingCapacity: true)
        hunkRows.removeAll(keepingCapacity: true)

        for (f, file) in fileList.enumerated() {
            let fu = UInt32(f)
            fileRows.append(UInt32(newRows.count))
            newRows.append(.file(fu))
            if ui[f].collapsed {
                continue
            }
            if file.hunks.isEmpty {
                newRows.append(.note(fu))
                continue
            }
            for gap in 0...file.hunks.count {
                let g = fileGaps[f][gap]
                let (top, bottom) = ui[f].revealed[gap]
                if top > 0 {
                    for k in 0..<top {
                        newRows.append(.ctx(f: fu, old: g.old + k, new: g.new + k))
                    }
                }
                let hiddenCount = g.len.map { n in n.saturatingSub(top.saturatingAdd(bottom)) }
                let firstRow = UInt32(newRows.count)
                if let hCount = hiddenCount, hCount > 0 {
                    newRows.append(.gap(f: fu, gap: UInt32(gap)))
                }
                if let n = g.len {
                    let startK = n - min(bottom, n)
                    if startK < n {
                        for k in startK..<n {
                            newRows.append(.ctx(f: fu, old: g.old + k, new: g.new + k))
                        }
                    }
                }
                guard gap < file.hunks.count else { break }
                let h = file.hunks[gap]
                hunkRows.append(firstRow)
                let hu = UInt32(gap)
                let lines = h.lines
                var i = 0
                while i < lines.count {
                    if modeValue == .split && lines[i].kind == .removed {
                        let del = i
                        while i < lines.count && lines[i].kind == .removed {
                            i += 1
                        }
                        let add = i
                        while i < lines.count && lines[i].kind == .added {
                            i += 1
                        }
                        let nd = add - del
                        let na = i - add
                        let pairMax = max(nd, na)
                        for k in 0..<pairMax {
                            if k < nd && k < na {
                                newRows.append(.pair(f: fu, h: hu, del: UInt32(del + k), add: UInt32(add + k)))
                            } else if k < nd {
                                newRows.append(.line(f: fu, h: hu, i: UInt32(del + k)))
                            } else {
                                newRows.append(.line(f: fu, h: hu, i: UInt32(add + k)))
                            }
                        }
                        continue
                    }
                    newRows.append(.line(f: fu, h: hu, i: UInt32(i)))
                    i += 1
                }
            }
        }

        rowOf.removeAll(keepingCapacity: true)
        let newKeys = newRows.map { keyOf($0) }
        if !visibleRows.isEmpty {
            if visibleRows.lowerBound >= 0,
               visibleRows.lowerBound < keys.count,
               let start = newKeys.firstIndex(of: keys[visibleRows.lowerBound])
            {
                let len = visibleRows.count
                visibleRows = start..<min(start + len, newRows.count)
            } else {
                visibleRows = 0..<0
            }
        }
        keys = newKeys
        keysRev = nextDiffKeysRev()
        for (i, r) in newRows.enumerated() {
            let f = UInt32(r.file())
            for side in [DiffSide.old, DiffSide.new] {
                if let n = rowLine(r, side) {
                    rowOf[DiffLineMapKey(file: f, side: side, line: n)] = UInt32(i)
                }
            }
        }
        rows = newRows
    }

    /// A row's key: the same for an unchanged or removed line in both modes, so switching
    /// moves it rather than replacing it.
    private func keyOf(_ r: DiffRow) -> String {
        switch r {
        case .file(let f):
            return "df\(f)"
        case .note(let f):
            return "df\(f).note"
        case .gap(let f, let gap):
            return "df\(f).g\(gap)"
        case .ctx(let f, let old, _):
            return "df\(f).c\(old)"
        case .line(let f, let h, let i):
            let l = fileList[Int(f)].hunks[Int(h)].lines[Int(i)]
            switch l.kind {
            case .context:
                return "df\(f).c\(l.old ?? 0)"
            case .removed:
                return "df\(f).o\(l.old ?? 0)"
            case .added:
                return "df\(f).n\(l.new ?? 0)"
            }
        case .pair(let f, let h, let del, _):
            let oldNo = fileList[Int(f)].hunks[Int(h)].lines[Int(del)].old ?? 0
            return "df\(f).o\(oldNo)"
        }
    }

    /// The digits `file`'s line numbers take.
    func digits(_ file: Int) -> UInt32 {
        guard file >= 0, file < digitsPerFile.count else { return 3 }
        return digitsPerFile[file]
    }

    /// The widest line of any file, in columns.
    func columns() -> UInt32 {
        maxColumns
    }

    /// The key of `file`'s header row, for `Tx.scrollIntoView`.
    public func fileKey(_ file: Int) -> String? {
        guard file >= 0, file < fileRows.count else { return nil }
        let r = Int(fileRows[file])
        guard r >= 0, r < keys.count else { return nil }
        return keys[r]
    }
}

/// The unchanged ranges before each hunk of `f` and after its last.
private func computeDiffGaps(_ f: FileDiff) -> [DiffGap] {
    var out: [DiffGap] = []
    out.reserveCapacity(f.hunks.count + 1)
    var old: UInt32 = 1
    var new: UInt32 = 1
    for h in f.hunks {
        let first = h.first(.old)
        out.append(DiffGap(old: old, new: new, len: first.saturatingSub(old)))
        old = h.end(.old)
        new = h.end(.new)
    }
    let len = f.oldLen().map { n in n.saturatingAdd(1).saturatingSub(old) }
    out.append(DiffGap(old: old, new: new, len: f.hunks.isEmpty ? 0 : len))
    return out
}
