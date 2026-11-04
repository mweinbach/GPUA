// Ported from: crates/rune-kit/src/diff/model.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! What a diff is: files of hunks of lines, parsed from a patch or computed from two texts.

extension UInt32 {
    @inline(__always)
    func saturatingAdd(_ other: UInt32) -> UInt32 {
        let (res, overflow) = addingReportingOverflow(other)
        return overflow ? .max : res
    }

    @inline(__always)
    func saturatingSub(_ other: UInt32) -> UInt32 {
        self > other ? (self - other) : 0
    }
}

/// The two sides of a diff: the text before the change and after it.
///
/// PORT NOTE: Named `DiffSide` at `RuneKit` top level so `Rune.Side` (`.top`/`.bottom`/`.left`/`.right`)
/// is not shadowed; exposed as `diff.Side` matching upstream `rune_kit::diff::Side`.
public enum DiffSide: Int, Sendable, Equatable, Hashable, Comparable {
    case old = 0
    case new = 1

    public static func < (lhs: DiffSide, rhs: DiffSide) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What a line of a hunk is.
public enum LineKind: Sendable, Equatable, Hashable {
    /// Unchanged, on both sides.
    case context
    /// Only on the new side.
    case added
    /// Only on the old side.
    case removed
}

/// One line of a hunk.
public struct Line: Sendable, Equatable {
    public var kind: LineKind
    /// Its 1-based number on the old side, unless it was added.
    public var old: UInt32?
    /// Its 1-based number on the new side, unless it was removed.
    public var new: UInt32?
    /// The line without its line break.
    public var text: String
    /// Byte ranges of `text` that differ from the line it replaced or was replaced by (word
    /// changes), when it pairs with one and they share enough to say.
    public var changes: [Range<Int>]
    /// The file ends here without a line break (`\ No newline at end of file`).
    public var noNewline: Bool

    public init(
        kind: LineKind,
        old: UInt32?,
        new: UInt32?,
        text: String,
        changes: [Range<Int>] = [],
        noNewline: Bool = false
    ) {
        self.kind = kind
        self.old = old
        self.new = new
        self.text = text
        self.changes = changes
        self.noNewline = noNewline
    }

    static func new(_ kind: LineKind, _ old: UInt32?, _ new: UInt32?, _ text: String) -> Line {
        Line(kind: kind, old: old, new: new, text: text, changes: [], noNewline: false)
    }

    /// Its number on `side`.
    public func number(_ side: DiffSide) -> UInt32? {
        switch side {
        case .old: return old
        case .new: return new
        }
    }
}

public typealias DiffLine = Line

/// A run of changed lines with the unchanged lines around them.
public struct Hunk: Sendable, Equatable {
    /// Where the hunk starts on the old side, as its `@@` header says: the line after which
    /// lines are inserted when `oldCount` is 0.
    public var oldStart: UInt32
    public var oldCount: UInt32
    public var newStart: UInt32
    public var newCount: UInt32
    /// The text after the header's closing `@@`, often the enclosing function.
    public var section: String
    public var lines: [Line]

    public init(
        oldStart: UInt32,
        oldCount: UInt32,
        newStart: UInt32,
        newCount: UInt32,
        section: String,
        lines: [Line]
    ) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }

    /// The first line number the hunk covers on `side` (its start, or the line after it when
    /// it covers none there).
    func first(_ side: DiffSide) -> UInt32 {
        let (start, count) = side == .old ? (oldStart, oldCount) : (newStart, newCount)
        return count == 0 ? start.saturatingAdd(1) : max(start, 1)
    }

    /// One past the last line number the hunk covers on `side`.
    func end(_ side: DiffSide) -> UInt32 {
        first(side).saturatingAdd(side == .old ? oldCount : newCount)
    }

    /// The header line as a patch writes it, `@@ -1,4 +1,5 @@ section`.
    public func header() -> String {
        func range(_ start: UInt32, _ count: UInt32) -> String {
            count == 1 ? "\(start)" : "\(start),\(count)"
        }
        var h = "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@"
        if !section.isEmpty {
            h.append(" ")
            h.append(section)
        }
        return h
    }
}

/// What happened to a file.
public enum FileStatus: Sendable, Equatable, Hashable {
    case modified
    case added
    case deleted
    case renamed
    case copied
}

/// A whole text, split into lines.
// PORT NOTE: Immutable reference-counted UTF-8 buffer (`Sendable` without locks) mirroring `Rc<Source>` in `crates/rune-kit/src/diff/model.rs`, giving O(1) random line access on 50k-line files.
final class DiffSource: Sendable {
    struct ByteSpan: Sendable, Equatable {
        let start: Int
        let end: Int
    }

    let utf8: [UInt8]
    let lines: [ByteSpan]
    private let missingTrailingNewline: Bool

    init(_ text: String) {
        let bytes = Array(text.utf8)
        var spans: [ByteSpan] = []
        var start = 0
        let count = bytes.count
        var i = 0
        while i < count {
            if bytes[i] == 0x0A {
                let end = (i > start && bytes[i - 1] == 0x0D) ? (i - 1) : i
                spans.append(ByteSpan(start: start, end: end))
                start = i + 1
            }
            i += 1
        }
        if start < count {
            let end = (bytes[count - 1] == 0x0D) ? (count - 1) : count
            spans.append(ByteSpan(start: start, end: end))
        }
        self.utf8 = bytes
        self.lines = spans
        self.missingTrailingNewline = !bytes.isEmpty && bytes[count - 1] != 0x0A
    }

    /// Line `n` (1-based).
    func line(_ n: UInt32) -> String? {
        guard n >= 1 else { return nil }
        let idx = Int(n - 1)
        guard idx < lines.count else { return nil }
        let span = lines[idx]
        return String(decoding: utf8[span.start..<span.end], as: UTF8.self)
    }

    func lineBytes(_ n: UInt32) -> ArraySlice<UInt8>? {
        guard n >= 1 else { return nil }
        let idx = Int(n - 1)
        guard idx < lines.count else { return nil }
        let span = lines[idx]
        return utf8[span.start..<span.end]
    }

    func len() -> UInt32 {
        UInt32(lines.count)
    }

    func endsWithoutNewline() -> Bool {
        missingTrailingNewline
    }
}

/// Lines of context around each change in a diff computed from texts, as `git diff` keeps.
private let CONTEXT: UInt32 = 3

/// One file's changes.
public struct FileDiff: Sendable {
    /// The path before the change; `nil` for an added file.
    public var oldPath: String?
    /// The path after the change; `nil` for a deleted file.
    public var newPath: String?
    public var status: FileStatus
    /// A rename's or copy's similarity, in percent.
    public var similarity: UInt8?
    /// File modes, as `100644`, when the patch gives them.
    public var oldMode: String?
    public var newMode: String?
    /// The patch says the file is binary, so it has no lines.
    public var binary: Bool
    public var hunks: [Hunk]
    var oldText: DiffSource?
    var newText: DiffSource?

    static func empty(_ oldPath: String?, _ newPath: String?) -> FileDiff {
        FileDiff(
            oldPath: oldPath,
            newPath: newPath,
            status: .modified,
            similarity: nil,
            oldMode: nil,
            newMode: nil,
            binary: false,
            hunks: [],
            oldText: nil,
            newText: nil
        )
    }

    /// The diff of `old` to `new`, a file at `path`, with three lines of context around each
    /// change and word changes on paired lines. Both texts stay with it, so every unchanged
    /// range between hunks can be expanded.
    public static func fromTexts(_ path: String, _ old: String, _ new: String) -> FileDiff {
        FileDiff.between(path, path, old, new)
    }

    /// ``fromTexts(_:_:_:)`` for a file whose path changed (a rename), was added (`oldPath`
    /// `nil`, `old` empty) or deleted (`newPath` `nil`, `new` empty).
    public static func between(_ oldPath: String?, _ newPath: String?, _ old: String, _ new: String) -> FileDiff {
        var f = FileDiff.empty(oldPath, newPath)
        switch (f.oldPath, f.newPath) {
        case (nil, _):
            f.status = .added
        case (_, nil):
            f.status = .deleted
        case (let a?, let b?) where a != b:
            f.status = .renamed
        default:
            f.status = .modified
        }
        if old.utf8.contains(0) || new.utf8.contains(0) {
            f.binary = true
            return f
        }
        let a = DiffSource(old)
        let b = DiffSource(new)
        f.hunks = buildHunks(a, b)
        f.oldText = a
        f.newText = b
        f.pairWords()
        return f
    }

    /// Every file in a unified diff (`git diff`, `git show`, `git format-patch`, `diff -u`).
    public static func parse(_ patch: String) -> [FileDiff] {
        parseDiffPatch(patch)
    }

    /// Attach the whole old and new texts to a parsed diff, so the unchanged ranges between its
    /// hunks can be expanded. One side is enough (unchanged lines read the same on both);
    /// the trailing range after the last hunk needs the side it counts lines on.
    public func withTexts(_ old: String?, _ new: String?) -> FileDiff {
        var copy = self
        copy.oldText = old.map(DiffSource.init)
        copy.newText = new.map(DiffSource.init)
        return copy
    }

    /// The path to show: the new one, or the old one for a deleted file.
    public func path() -> String {
        newPath ?? oldPath ?? ""
    }

    /// Lines added.
    public func additions() -> Int {
        var total = 0
        for h in hunks {
            for l in h.lines where l.kind == .added {
                total += 1
            }
        }
        return total
    }

    /// Lines removed.
    public func deletions() -> Int {
        var total = 0
        for h in hunks {
            for l in h.lines where l.kind == .removed {
                total += 1
            }
        }
        return total
    }

    /// The highlighter language for the path's extension (or name, for a `Makefile`), as
    /// written: `"rs"`, `"tsx"`.
    public func language() -> String? {
        let p = path()
        let name: Substring
        if let slash = p.lastIndex(of: "/") {
            name = p[p.index(after: slash)...]
        } else {
            name = p[...]
        }
        if let dot = name.lastIndex(of: ".") {
            let stem = name[..<dot]
            if !stem.isEmpty {
                return String(name[name.index(after: dot)...])
            }
        }
        if name == "Makefile" || name == "Dockerfile" {
            return String(name)
        }
        return nil
    }

    /// Whether the unchanged lines between hunks can be shown.
    public func expandable() -> Bool {
        oldText != nil || newText != nil
    }

    /// Unchanged line `old` of the old side (with `new` its number on the new side), from
    /// whichever whole text the diff has.
    func contextLine(_ old: UInt32, _ new: UInt32) -> String? {
        oldText?.line(old) ?? newText?.line(new)
    }

    /// How many lines the old side has, when the diff knows: from the old text, or the new
    /// text and the hunks' line counts.
    func oldLen() -> UInt32? {
        if let t = oldText {
            return t.len()
        }
        guard let t = newText else { return nil }
        let added = Int64(additions())
        let removed = Int64(deletions())
        return UInt32(max(Int64(t.len()) - added + removed, 0))
    }

    /// The widest line it can show, in columns with tabs stopping every four.
    func columns() -> UInt32 {
        var widest: UInt32 = 0
        for h in hunks {
            for l in h.lines {
                widest = max(widest, diffColumns(l.text))
            }
        }
        for src in [oldText, newText] {
            guard let t = src else { continue }
            let n = t.len()
            if n >= 1 {
                for lineNo in 1...n {
                    if let s = t.line(lineNo) {
                        widest = max(widest, diffColumns(s))
                    }
                }
            }
        }
        return widest
    }

    /// The largest line number either side shows.
    func lastLine() -> UInt32 {
        let fromHunks: UInt32 = hunks.last.map { h in
            max(h.end(.old), h.end(.new)).saturatingSub(1)
        } ?? 0
        let fromTexts = max(oldText?.len() ?? 0, newText?.len() ?? 0)
        return max(fromHunks, fromTexts)
    }

    /// Word changes for each removed line followed by an added one, pairing them in order.
    mutating func pairWords() {
        for hIdx in hunks.indices {
            var i = 0
            let total = hunks[hIdx].lines.count
            while i < total {
                let del = i
                while i < total && hunks[hIdx].lines[i].kind == .removed {
                    i += 1
                }
                let add = i
                while i < total && hunks[hIdx].lines[i].kind == .added {
                    i += 1
                }
                if add == del || i == add {
                    i = max(i, del + 1)
                    continue
                }
                let pairs = min(add - del, i - add)
                if pairs <= 128 {
                    for k in 0..<pairs {
                        let (a, b) = myers.words(
                            hunks[hIdx].lines[del + k].text,
                            hunks[hIdx].lines[add + k].text
                        )
                        hunks[hIdx].lines[del + k].changes = a
                        hunks[hIdx].lines[add + k].changes = b
                    }
                }
            }
        }
    }
}

/// Columns `line` takes with tabs stopping every four.
func diffColumns(_ line: String) -> UInt32 {
    var col: UInt32 = 0
    for scalar in line.unicodeScalars {
        if scalar == "\t" {
            col += 4 - (col % 4)
        } else {
            col += 1
        }
    }
    return col
}

private struct InternKey: Hashable {
    let bytes: ArraySlice<UInt8>
    let missingNewline: Bool
}

private func intern(_ s: DiffSource, _ ids: inout [InternKey: UInt32]) -> [UInt32] {
    let last = s.len()
    guard last >= 1 else { return [] }
    var out: [UInt32] = []
    out.reserveCapacity(Int(last))
    for n in 1...last {
        let slice = s.lineBytes(n) ?? ArraySlice<UInt8>()
        let key = InternKey(bytes: slice, missingNewline: n == last && s.endsWithoutNewline())
        if let existing = ids[key] {
            out.append(existing)
        } else {
            let next = UInt32(ids.count)
            ids[key] = next
            out.append(next)
        }
    }
    return out
}

/// The nearest line above 0-based line `before` that starts with a letter, `_` or `$` (a
/// function or type at the left margin), as `git diff` names a hunk by default.
private func hunkSection(_ s: DiffSource, _ before: UInt32) -> String {
    let limit = min(before, s.len())
    guard limit >= 1 else { return "" }
    var checked = 0
    var n = limit
    while n >= 1 && checked < 2000 {
        checked += 1
        if let line = s.line(n), let first = line.unicodeScalars.first {
            if first.properties.isAlphabetic || first == "_" || first == "$" {
                var scalars = Array(line.unicodeScalars)
                while let last = scalars.last, last.properties.isWhitespace {
                    scalars.removeLast()
                }
                let capped = scalars.prefix(80)
                var result = String.UnicodeScalarView()
                result.append(contentsOf: capped)
                return String(result)
            }
        }
        if n == 1 { break }
        n -= 1
    }
    return ""
}

/// Hunks of `old` to `new` with `CONTEXT` lines around each change, merged when their
/// context would touch.
private func buildHunks(_ old: DiffSource, _ new: DiffSource) -> [Hunk] {
    var ids: [InternKey: UInt32] = [:]
    let a = intern(old, &ids)
    let b = intern(new, &ids)
    let ops = myers.diff(a, b)

    // Changes as (old range, new range), 0-based.
    var changes: [(Range<UInt32>, Range<UInt32>)] = []
    var i: UInt32 = 0
    var j: UInt32 = 0
    for op in ops {
        switch op {
        case .equal(_, _, let len):
            let l = UInt32(len)
            i += l
            j += l
        case .delete(_, let len):
            let l = UInt32(len)
            if let last = changes.last, last.0.upperBound == i && last.1.upperBound == j {
                changes[changes.count - 1].0 = last.0.lowerBound..<(last.0.upperBound + l)
            } else {
                changes.append((i..<(i + l), j..<j))
            }
            i += l
        case .insert(_, let len):
            let l = UInt32(len)
            if let last = changes.last, last.0.upperBound == i && last.1.upperBound == j {
                changes[changes.count - 1].1 = last.1.lowerBound..<(last.1.upperBound + l)
            } else {
                changes.append((i..<i, j..<(j + l)))
            }
            j += l
        }
    }

    var groups: [[(Range<UInt32>, Range<UInt32>)]] = []
    for c in changes {
        if let lastGroup = groups.last, let last = lastGroup.last, c.0.lowerBound - last.0.upperBound <= 2 * CONTEXT {
            groups[groups.count - 1].append(c)
        } else {
            groups.append([c])
        }
    }

    func textAt(_ src: DiffSource, _ zeroBased: UInt32) -> String {
        src.line(zeroBased + 1) ?? ""
    }

    return groups.map { g in
        let first = g[0]
        let last = g[g.count - 1]
        let start = first.0.lowerBound.saturatingSub(CONTEXT)
        let shift = first.0.lowerBound - start
        let os = start
        let ns = first.1.lowerBound - shift
        let endOld = min(last.0.upperBound + CONTEXT, old.len())
        var lines: [Line] = []
        var oi = os
        var nj = ns
        for c in g {
            while oi < c.0.lowerBound {
                lines.append(Line.new(.context, oi + 1, nj + 1, textAt(old, oi)))
                oi += 1
                nj += 1
            }
            for n in c.0 {
                lines.append(Line.new(.removed, n + 1, nil, textAt(old, n)))
            }
            for n in c.1 {
                lines.append(Line.new(.added, nil, n + 1, textAt(new, n)))
            }
            oi = c.0.upperBound
            nj = c.1.upperBound
        }
        while oi < endOld {
            lines.append(Line.new(.context, oi + 1, nj + 1, textAt(old, oi)))
            oi += 1
            nj += 1
        }
        let oldCountTotal = old.len()
        let newCountTotal = new.len()
        for idx in lines.indices {
            switch lines[idx].kind {
            case .removed, .context:
                lines[idx].noNewline = (lines[idx].old == oldCountTotal) && old.endsWithoutNewline()
            case .added:
                lines[idx].noNewline = (lines[idx].new == newCountTotal) && new.endsWithoutNewline()
            }
        }
        let oc = oi - os
        let nc = nj - ns
        return Hunk(
            oldStart: oc == 0 ? os : (os + 1),
            oldCount: oc,
            newStart: nc == 0 ? ns : (ns + 1),
            newCount: nc,
            section: hunkSection(old, os),
            lines: lines
        )
    }
}

/// Every file in a unified diff, as `git diff`, `git show`, `git format-patch` or `diff -u`
/// write them: renames, copies, mode changes, added and deleted files, binary files and
/// `\ No newline at end of file` included. Text around the diffs (a commit message, a mail
/// header) is skipped. Word changes are paired as ``FileDiff/fromTexts(_:_:_:)`` pairs them.
func parseDiffPatch(_ patch: String) -> [FileDiff] {
    var files: [FileDiff] = []
    let lines: [String] = patch.split(separator: "\n", omittingEmptySubsequences: false).map { sub in
        if sub.last == "\r" {
            return String(sub.dropLast())
        }
        return String(sub)
    }
    var i = 0
    var cur: FileDiff? = nil
    var inHeader = false

    while i < lines.count {
        let l = lines[i]
        if l.hasPrefix("diff --git ") {
            if let finished = cur.take() {
                files.append(finished)
            }
            let rest = String(l.dropFirst("diff --git ".count))
            let (a, b) = gitPaths(rest)
            cur = FileDiff.empty(a, b)
            inHeader = true
            i += 1
            continue
        }
        if l.hasPrefix("--- "),
           i + 2 < lines.count,
           lines[i + 1].hasPrefix("+++ "),
           lines[i + 2].hasPrefix("@@ ")
        {
            let a = pathOf(String(l.dropFirst(4)))
            let b = pathOf(String(lines[i + 1].dropFirst(4)))
            if cur != nil && inHeader {
                cur?.oldPath = a
                cur?.newPath = b
            } else {
                if let finished = cur.take() {
                    files.append(finished)
                }
                cur = FileDiff.empty(a, b)
            }
            inHeader = false
            i += 2
            continue
        }
        if cur != nil {
            if l.hasPrefix("@@ ") {
                inHeader = false
                if let h = hunkHeader(l) {
                    let (built, next) = hunkBody(h, lines, i + 1)
                    cur?.hunks.append(built)
                    i = next
                    continue
                }
            } else if inHeader, var f = cur {
                headerLine(&f, l)
                cur = f
            }
        }
        i += 1
    }
    if let finished = cur {
        files.append(finished)
    }
    for idx in files.indices {
        if files[idx].status == .modified {
            switch (files[idx].oldPath, files[idx].newPath) {
            case (nil, .some):
                files[idx].status = .added
            case (.some, nil):
                files[idx].status = .deleted
            case (let a?, let b?) where a != b:
                files[idx].status = .renamed
            default:
                files[idx].status = .modified
            }
        }
        files[idx].pairWords()
    }
    return files
}

private extension Optional {
    mutating func take() -> Wrapped? {
        let out = self
        self = nil
        return out
    }
}

private func trimAsciiAndUnicodeWhitespace(_ s: Substring) -> String {
    let scalars = Array(s.unicodeScalars)
    var lo = 0
    var hi = scalars.count
    while lo < hi && scalars[lo].properties.isWhitespace {
        lo += 1
    }
    while hi > lo && scalars[hi - 1].properties.isWhitespace {
        hi -= 1
    }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars[lo..<hi])
    return String(view)
}

private func trimEndWhitespace(_ s: String) -> String {
    var scalars = Array(s.unicodeScalars)
    while let last = scalars.last, last.properties.isWhitespace {
        scalars.removeLast()
    }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars)
    return String(view)
}

private func trimStartWhitespace(_ s: String) -> String {
    let scalars = Array(s.unicodeScalars)
    var lo = 0
    while lo < scalars.count && scalars[lo].properties.isWhitespace {
        lo += 1
    }
    var view = String.UnicodeScalarView()
    view.append(contentsOf: scalars[lo...])
    return String(view)
}

private func headerLine(_ f: inout FileDiff, _ l: String) {
    func word(_ prefix: String) -> String? {
        guard l.hasPrefix(prefix) else { return nil }
        return trimAsciiAndUnicodeWhitespace(l.dropFirst(prefix.count))
    }
    if let m = word("old mode ") {
        f.oldMode = m
    } else if let m = word("new mode ") {
        f.newMode = m
    } else if let m = word("new file mode ") {
        f.newMode = m
        f.status = .added
        f.oldPath = nil
    } else if let m = word("deleted file mode ") {
        f.oldMode = m
        f.status = .deleted
        f.newPath = nil
    } else if let p = word("rename from ") {
        f.oldPath = unquote(p)
        f.status = .renamed
    } else if let p = word("rename to ") {
        f.newPath = unquote(p)
        f.status = .renamed
    } else if let p = word("copy from ") {
        f.oldPath = unquote(p)
        f.status = .copied
    } else if let p = word("copy to ") {
        f.newPath = unquote(p)
        f.status = .copied
    } else if let s = word("similarity index ") {
        var digits = s[...]
        while digits.last == "%" {
            digits = digits.dropLast()
        }
        f.similarity = parseStrictUInt8(digits)
    } else if let rest = word("index ") {
        if let space = rest.firstIndex(of: " ") {
            let mode = String(rest[rest.index(after: space)...])
            if f.oldMode == nil {
                f.oldMode = mode
            }
            if f.newMode == nil {
                f.newMode = mode
            }
        }
    } else if l.hasPrefix("Binary files ") || l == "GIT binary patch" {
        f.binary = true
    }
}

/// The two paths of a `diff --git a/x b/y` line. With unquoted paths containing spaces the
/// split is ambiguous; the `---`/`+++` or rename lines that follow correct it.
private func gitPaths(_ rest: String) -> (String?, String?) {
    if rest.first == "\"", let (a, b) = splitQuoted(rest) {
        return (stripDiffPrefix(a), stripDiffPrefix(b))
    }
    let bytes = Array(rest.utf8)
    let half = bytes.count / 2
    if bytes.count % 2 == 1,
       bytes[half] == 0x20,
       half >= 2,
       bytes[0] == 0x61, bytes[1] == 0x2F, /* "a/" */
       bytes.count - (half + 1) >= 2,
       bytes[half + 1] == 0x62, bytes[half + 2] == 0x2F, /* "b/" */
       bytes[2..<half] == bytes[(half + 3)..<bytes.count]
    {
        let left = String(decoding: bytes[0..<half], as: UTF8.self)
        let right = String(decoding: bytes[(half + 1)..<bytes.count], as: UTF8.self)
        return (stripDiffPrefix(left), stripDiffPrefix(right))
    }
    // Find first " b/"
    if bytes.count >= 3 {
        for at in 0...(bytes.count - 3) {
            if bytes[at] == 0x20 && bytes[at + 1] == 0x62 && bytes[at + 2] == 0x2F {
                let left = String(decoding: bytes[0..<at], as: UTF8.self)
                let right = String(decoding: bytes[(at + 1)..<bytes.count], as: UTF8.self)
                return (stripDiffPrefix(left), stripDiffPrefix(right))
            }
        }
    }
    return (nil, nil)
}

private func splitQuoted(_ rest: String) -> (String, String)? {
    let bytes = Array(rest.utf8)
    guard let end = quotedEnd(bytes) else { return nil }
    let a = unquote(String(decoding: bytes[0..<end], as: UTF8.self))
    let tail = trimStartWhitespace(String(decoding: bytes[end..<bytes.count], as: UTF8.self))
    return (a, unquote(tail))
}

/// The byte after the closing quote of the quoted string `bytes` starts with.
private func quotedEnd(_ bytes: [UInt8]) -> Int? {
    guard bytes.first == 0x22 /* '"' */ else { return nil }
    var escaped = false
    var i = 1
    while i < bytes.count {
        let c = bytes[i]
        if escaped {
            escaped = false
        } else if c == 0x5C /* '\\' */ {
            escaped = true
        } else if c == 0x22 /* '"' */ {
            return i + 1
        }
        i += 1
    }
    return nil
}

/// A path as git writes it: bare, or in double quotes with C escapes (octal bytes for
/// non-ASCII).
private func unquote(_ p: String) -> String {
    guard p.count >= 2 && p.first == "\"" && p.last == "\"" else {
        return p
    }
    let inner = Array(p.utf8.dropFirst().dropLast())
    var bytes: [UInt8] = []
    bytes.reserveCapacity(inner.count)
    var i = 0
    while i < inner.count {
        let c = inner[i]
        i += 1
        if c != 0x5C /* '\\' */ {
            bytes.append(c)
            continue
        }
        guard i < inner.count else {
            bytes.append(0x5C)
            break
        }
        let esc = inner[i]
        i += 1
        switch esc {
        case 0x6E /* 'n' */:
            bytes.append(0x0A)
        case 0x74 /* 't' */:
            bytes.append(0x09)
        case 0x72 /* 'r' */:
            bytes.append(0x0D)
        case 0x30...0x37 /* '0'...'7' */:
            var v = UInt32(esc - 0x30)
            for _ in 0..<2 {
                if i < inner.count, inner[i] >= 0x30 && inner[i] <= 0x37 {
                    v = v * 8 + UInt32(inner[i] - 0x30)
                    i += 1
                } else {
                    break
                }
            }
            bytes.append(UInt8(truncatingIfNeeded: v))
        default:
            bytes.append(esc)
        }
    }
    return String(decoding: bytes, as: UTF8.self)
}

private func stripDiffPrefix(_ p: String) -> String {
    let u = unquote(p)
    if u.hasPrefix("a/") || u.hasPrefix("b/") {
        return String(u.dropFirst(2))
    }
    return u
}

/// The path of a `---` or `+++` line: `nil` for `/dev/null`, without a trailing timestamp.
private func pathOf(_ s: String) -> String? {
    let head: String
    if s.first == "\"" {
        head = s
    } else if let tab = s.firstIndex(of: "\t") {
        head = String(s[..<tab])
    } else {
        head = s
    }
    let trimmed = trimEndWhitespace(head)
    if trimmed == "/dev/null" {
        return nil
    }
    return stripDiffPrefix(trimmed)
}

private func parseStrictUInt32(_ s: Substring) -> UInt32? {
    guard !s.isEmpty else { return nil }
    for b in s.utf8 where b < 0x30 || b > 0x39 {
        return nil
    }
    return UInt32(s, radix: 10)
}

private func parseStrictUInt8(_ s: Substring) -> UInt8? {
    guard !s.isEmpty else { return nil }
    for b in s.utf8 where b < 0x30 || b > 0x39 {
        return nil
    }
    return UInt8(s, radix: 10)
}

private func splitOnce(_ s: Substring, _ needle: String) -> (Substring, Substring)? {
    let sBytes = Array(s.utf8)
    let nBytes = Array(needle.utf8)
    guard !nBytes.isEmpty, sBytes.count >= nBytes.count else { return nil }
    for at in 0...(sBytes.count - nBytes.count) {
        if sBytes[at..<(at + nBytes.count)].elementsEqual(nBytes) {
            let left = String(decoding: sBytes[0..<at], as: UTF8.self)[...]
            let right = String(decoding: sBytes[(at + nBytes.count)..<sBytes.count], as: UTF8.self)[...]
            return (left, right)
        }
    }
    return nil
}

private func hunkHeader(_ l: String) -> Hunk? {
    guard l.hasPrefix("@@ -") else { return nil }
    let rest = l.dropFirst(4)
    guard let (ranges, section) = splitOnce(rest, " @@"),
          let (oldPart, newPart) = splitOnce(ranges, " +")
    else { return nil }

    func parseRange(_ r: Substring) -> (UInt32, UInt32)? {
        if let comma = r.firstIndex(of: ",") {
            guard let st = parseStrictUInt32(r[..<comma]),
                  let ct = parseStrictUInt32(r[r.index(after: comma)...])
            else { return nil }
            return (st, ct)
        }
        guard let st = parseStrictUInt32(r) else { return nil }
        return (st, 1)
    }

    guard let (os, oc) = parseRange(oldPart),
          let (ns, nc) = parseRange(newPart)
    else { return nil }

    return Hunk(
        oldStart: os,
        oldCount: oc,
        newStart: ns,
        newCount: nc,
        section: trimAsciiAndUnicodeWhitespace(section),
        lines: []
    )
}

/// The lines of hunk `h` from `lines[i...]`, read until its counts are used up: the index of
/// the line after it.
private func hunkBody(_ hIn: Hunk, _ lines: [String], _ startIdx: Int) -> (Hunk, Int) {
    var h = hIn
    var i = startIdx
    var old = h.first(.old)
    var new = h.first(.new)
    var oldLeft = h.oldCount
    var newLeft = h.newCount

    while i < lines.count {
        let l = lines[i]
        if l.first == "\\" {
            if !h.lines.isEmpty {
                h.lines[h.lines.count - 1].noNewline = true
            }
            i += 1
            continue
        }
        if oldLeft == 0 && newLeft == 0 {
            break
        }
        let kind: LineKind
        let text: String
        if l.first == " " {
            kind = .context
            text = String(l.dropFirst())
        } else if l.isEmpty && i + 1 < lines.count {
            // A context line whose space an editor trimmed.
            kind = .context
            text = ""
        } else if l.first == "-" && oldLeft > 0 {
            kind = .removed
            text = String(l.dropFirst())
        } else if l.first == "+" && newLeft > 0 {
            kind = .added
            text = String(l.dropFirst())
        } else {
            break
        }

        let builtLine: Line
        switch kind {
        case .context:
            guard oldLeft > 0 && newLeft > 0 else {
                h.oldCount -= oldLeft
                h.newCount -= newLeft
                return (h, i)
            }
            oldLeft -= 1
            newLeft -= 1
            let o = old
            let n = new
            old = old.saturatingAdd(1)
            new = new.saturatingAdd(1)
            builtLine = Line.new(kind, o, n, text)
        case .removed:
            oldLeft -= 1
            let o = old
            old = old.saturatingAdd(1)
            builtLine = Line.new(kind, o, nil, text)
        case .added:
            newLeft -= 1
            let n = new
            new = new.saturatingAdd(1)
            builtLine = Line.new(kind, nil, n, text)
        }
        h.lines.append(builtLine)
        i += 1
    }
    h.oldCount -= oldLeft
    h.newCount -= newLeft
    return (h, i)
}
