// Ported from: crates/rune-kit/src/notes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Structured Markdown communication primitives (`facts`, `compare`, `steps`,
//! `size`, titled/marked code fences, and `> [!note]` callouts) layered over
//! ``Markdown``. Plain Markdown, GFM tables, and `mermaid` blocks pass straight
//! through to ``Markdown``.

import Rune

private let CAPS = TextStyle(
    size: 11.0,
    weight: 560.0,
    lineHeight: 18.0,
    tracking: 0.5,
    features: "'tnum' 1"
)

private let CELL = TextStyle(
    size: 13.5,
    weight: 430.0,
    lineHeight: 20.0,
    tracking: -0.1,
    features: "'tnum' 1"
)

private let CODE = TextStyle(
    size: 12.2,
    weight: 430.0,
    family: .mono,
    lineHeight: 19.0,
    features: "'tnum' 1"
)

/// A parsed piece of a ``Note``: either plain Markdown or a structured block.
enum Piece: Sendable, Equatable {
    case markdown(String)
    case facts([(String, String)])
    case compare([(String, String)])
    case steps([StepRow])
    case size(SizeBar)
    case codeFence(title: String?, marks: [ClosedRange<Int>], lines: [String])
    case callout(label: String?, body: String)

    static func == (lhs: Piece, rhs: Piece) -> Bool {
        switch (lhs, rhs) {
        case let (.markdown(a), .markdown(b)):
            return a == b
        case let (.facts(a), .facts(b)), let (.compare(a), .compare(b)):
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) where x.0 != y.0 || x.1 != y.1 {
                return false
            }
            return true
        case let (.steps(a), .steps(b)):
            return a == b
        case let (.size(a), .size(b)):
            return a == b
        case let (.codeFence(ta, ma, la), .codeFence(tb, mb, lb)):
            return ta == tb && ma == mb && la == lb
        case let (.callout(la, ba), .callout(lb, bb)):
            return la == lb && ba == bb
        default:
            return false
        }
    }
}

/// One `{status} Title · note` row inside a ```` ```steps ```` fence.
struct StepRow: Sendable, Equatable {
    var status: String
    var title: String
    var note: String?
}

/// Parsed diffstat breakdown inside a ```` ```size ```` fence.
struct SizeBar: Sendable, Equatable {
    var parts: [(String, Int64, Int64)]
    var files: String?

    static func == (lhs: SizeBar, rhs: SizeBar) -> Bool {
        guard lhs.files == rhs.files, lhs.parts.count == rhs.parts.count else {
            return false
        }
        for (a, b) in zip(lhs.parts, rhs.parts) where a.0 != b.0 || a.1 != b.1 || a.2 != b.2 {
            return false
        }
        return true
    }
}

/// Builder for rendering a Markdown note containing structured communication
/// blocks (`facts`, `compare`, `steps`, `size`, `title="…" {1,3-4}` code
/// fences, and `> [!note]` callouts).
public struct Note: Sendable {
    var keyValue: String
    var source: String
    var gapValue: Float

    public init(_ source: String) {
        self.keyValue = "note"
        self.source = source
        self.gapValue = 12.0
    }

    public static func new(_ source: String) -> Note {
        Note(source)
    }

    public func key(_ key: String) -> Note {
        var copy = self
        copy.keyValue = key
        return copy
    }

    public func gap(_ gap: Float) -> Note {
        var copy = self
        copy.gapValue = gap
        return copy
    }

    public func build(_ k: Kit) -> El {
        renderWithGap(keyValue, source, gapValue, k)
    }
}

/// Render `src` into a vertical stack keyed by `keyPrefix`.
public func renderNote(_ keyPrefix: String, _ src: String, _ k: Kit) -> El {
    renderWithGap(keyPrefix, src, 12.0, k)
}

/// Namespace matching Rust's `rune_kit::notes` module.
public enum notes {
    public typealias Note = RuneKit.Note

    public static func renderNote(_ keyPrefix: String, _ src: String, _ k: Kit) -> El {
        RuneKit.renderNote(keyPrefix, src, k)
    }
}

private func renderWithGap(_ keyPrefix: String, _ src: String, _ gap: Float, _ k: Kit) -> El {
    let pieces = cut(src)
    var root = col().key(keyPrefix).wFull().gap(gap).motion(Spring.new(0.34, 0.0))
    for (idx, piece) in pieces.enumerated() {
        let key = "\(keyPrefix)/p\(idx)"
        let base: El
        switch piece {
        case let .markdown(md):
            base = Markdown.new(md).build(k).key(key)
        case let .facts(rows):
            base = drawFacts(key, rows, k)
        case let .compare(sides):
            base = drawCompare(key, sides, k)
        case let .steps(steps):
            base = drawSteps(key, steps, k)
        case let .size(size):
            base = drawSize(key, size, k)
        case let .codeFence(title, marks, lines):
            base = drawCode(key, title, marks, lines, k)
        case let .callout(label, body):
            base = drawCallout(key, label, body, k)
        }
        let child = base
            .motion(Spring.new(0.32, 0.0))
            .transition(Transition.opacity())
        root = root.child(child)
    }
    return root
}

private func splitLines(_ src: String) -> [Substring] {
    guard !src.isEmpty else { return [] }
    var parts = src.split(separator: "\n", omittingEmptySubsequences: false)
    if src.hasSuffix("\n") {
        parts.removeLast()
    }
    for idx in parts.indices where parts[idx].hasSuffix("\r") {
        parts[idx] = parts[idx].dropLast()
    }
    return parts
}

private func trimStartWs(_ s: Substring) -> Substring {
    var cur = s.startIndex
    while cur < s.endIndex, s[cur].isWhitespace {
        cur = s.index(after: cur)
    }
    return s[cur...]
}

private func trimEndWs(_ s: Substring) -> Substring {
    var cur = s.endIndex
    while cur > s.startIndex {
        let prev = s.index(before: cur)
        if s[prev].isWhitespace {
            cur = prev
        } else {
            break
        }
    }
    return s[..<cur]
}

private func trimWs(_ s: Substring) -> Substring {
    trimEndWs(trimStartWs(s))
}

private func trimWs(_ s: String) -> Substring {
    trimWs(s[...])
}

private func trimNewlines(_ s: String) -> String {
    var sub = s[...]
    while sub.first == "\n" {
        sub = sub.dropFirst()
    }
    while sub.last == "\n" {
        sub = sub.dropLast()
    }
    return String(sub)
}

/// Split `src` into plain Markdown chunks and structured ``Piece`` blocks.
func cut(_ src: String) -> [Piece] {
    let lines = splitLines(src)
    var out: [Piece] = []
    var md: [Substring] = []

    func flushMd() {
        let joined = md.joined(separator: "\n")
        if !trimWs(joined).isEmpty {
            out.append(.markdown(trimNewlines(joined)))
        }
        md.removeAll()
    }

    var i = 0
    while i < lines.count {
        let line = lines[i]
        let trimmed = trimStartWs(line)
        let indent = line.utf8.count - trimmed.utf8.count

        if indent < 4 && trimmed.hasPrefix(">") {
            let afterGt = trimStartWs(trimmed.dropFirst())
            if afterGt.hasPrefix("[!") {
                let rest = afterGt.dropFirst(2)
                if let close = rest.firstIndex(of: "]") {
                    let rawLabel = trimWs(rest[..<close])
                    let label: String? = (rawLabel.lowercased() != "note" && !rawLabel.isEmpty)
                        ? String(rawLabel)
                        : nil
                    var bodyLines: [String] = []
                    let inlineTail = trimWs(rest[rest.index(after: close)...])
                    if !inlineTail.isEmpty {
                        bodyLines.append(String(inlineTail))
                    }
                    i += 1
                    while i < lines.count {
                        let next = trimStartWs(lines[i])
                        if next.hasPrefix(">") {
                            let stripped = next.dropFirst()
                            let content = stripped.hasPrefix(" ") ? stripped.dropFirst() : stripped
                            bodyLines.append(String(content))
                            i += 1
                        } else {
                            break
                        }
                    }
                    flushMd()
                    out.append(.callout(label: label, body: bodyLines.joined(separator: "\n")))
                    continue
                }
            }
        }

        if indent < 4 && (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")) {
            let ch = trimmed.first!
            var afterFence = trimmed
            var ticks = 0
            while afterFence.first == ch {
                afterFence = afterFence.dropFirst()
                ticks += 1
            }
            let infoRaw = String(trimWs(afterFence))
            let tag = infoRaw.split(whereSeparator: { $0.isWhitespace }).first?.lowercased() ?? ""
            let fencePrefix = String(repeating: String(ch), count: ticks)
            var endIdx: Int? = nil
            if i + 1 < lines.count {
                for j in (i + 1)..<lines.count {
                    let u = trimStartWs(lines[j])
                    if u.hasPrefix(fencePrefix) {
                        var rem = u
                        while rem.first == ch {
                            rem = rem.dropFirst()
                        }
                        if trimWs(rem).isEmpty {
                            endIdx = j
                            break
                        }
                    }
                }
            }
            if let end = endIdx {
                let body = Array(lines[(i + 1)..<end])
                let special: Piece?
                switch tag {
                case "facts", "kv", "stats", "stat":
                    special = .facts(parsePairs(body))
                case "compare", "before-after":
                    special = .compare(parsePairs(body))
                case "steps", "status":
                    special = .steps(parseSteps(body))
                case "size":
                    special = .size(parseSize(body))
                default:
                    if infoRaw.contains("title=") || infoRaw.contains("{") {
                        let (title, marks) = parseCodeMeta(infoRaw)
                        special = .codeFence(
                            title: title,
                            marks: marks,
                            lines: body.map { String($0) }
                        )
                    } else {
                        special = nil
                    }
                }
                if let piece = special {
                    flushMd()
                    out.append(piece)
                    i = end + 1
                    continue
                }
            }
        }

        md.append(line)
        i += 1
    }
    flushMd()
    return out
}

private func stripLeadingDashSpace(_ s: Substring) -> Substring {
    var cur = s
    while cur.hasPrefix("- ") {
        cur = cur.dropFirst(2)
    }
    return cur
}

private func splitOnce(_ s: Substring, _ delimiter: String) -> (Substring, Substring)? {
    guard !delimiter.isEmpty else {
        return (s[..<s.startIndex], s)
    }
    var idx = s.startIndex
    while idx < s.endIndex {
        if s[idx...].hasPrefix(delimiter) {
            let after = s.index(idx, offsetBy: delimiter.count)
            return (s[..<idx], s[after...])
        }
        idx = s.index(after: idx)
    }
    return nil
}

private func parsePairs(_ lines: [Substring]) -> [(String, String)] {
    var out: [(String, String)] = []
    for raw in lines {
        let line = trimWs(stripLeadingDashSpace(trimWs(raw)))
        if line.isEmpty {
            continue
        }
        if let colon = line.firstIndex(of: ":") {
            let k = String(trimWs(line[..<colon]))
            let v = String(trimWs(line[line.index(after: colon)...]))
            out.append((k, v))
        } else if !out.isEmpty {
            out[out.count - 1].1 += " " + String(line)
        }
    }
    return out
}

private func parseSteps(_ lines: [Substring]) -> [StepRow] {
    var out: [StepRow] = []
    for raw in lines {
        var s = trimWs(stripLeadingDashSpace(trimWs(raw)))
        if s.isEmpty {
            continue
        }
        let status: String
        if s.hasPrefix("{"), let end = s.dropFirst().firstIndex(of: "}") {
            let inner = s.dropFirst()[..<end]
            s = trimWs(s[s.index(after: end)...])
            status = String(trimWs(inner))
        } else {
            status = "proposed"
        }
        let title: String
        let note: String?
        if let (t, n) = splitOnce(s, " · ") {
            title = String(trimWs(t))
            note = String(trimWs(n))
        } else {
            title = String(s)
            note = nil
        }
        out.append(StepRow(status: status, title: title, note: note))
    }
    return out
}

private func splitByDelimiter(_ s: String, _ delimiter: String) -> [Substring] {
    var out: [Substring] = []
    var rest = s[...]
    while let (head, tail) = splitOnce(rest, delimiter) {
        out.append(head)
        rest = tail
    }
    out.append(rest)
    return out
}

private func parseSize(_ lines: [Substring]) -> SizeBar {
    let joined = lines.map(String.init).joined(separator: " ")
    var parts: [(String, Int64, Int64)] = []
    var files: String? = nil
    for rawChunk in splitByDelimiter(joined, " · ") {
        let chunk = trimWs(rawChunk)
        if chunk.isEmpty {
            continue
        }
        if chunk.hasSuffix("files") || chunk.hasSuffix("file") {
            files = String(chunk)
            continue
        }
        let tokens = chunk.split(whereSeparator: { $0.isWhitespace })
        guard let name = tokens.first else {
            continue
        }
        var adds: Int64 = 0
        var dels: Int64 = 0
        for tok in tokens.dropFirst() {
            if tok.hasPrefix("+") {
                let cleaned = tok.dropFirst().filter { $0 != "," }
                adds = Int64(cleaned) ?? 0
            } else if tok.hasPrefix("−") || tok.hasPrefix("-") {
                let cleaned = tok.dropFirst().filter { $0 != "," }
                dels = Int64(cleaned) ?? 0
            }
        }
        parts.append((String(name), adds, dels))
    }
    return SizeBar(parts: parts, files: files)
}

private func parseCodeMeta(_ info: String) -> (String?, [ClosedRange<Int>]) {
    var title: String? = nil
    if let (_, rest) = splitOnce(info[...], "title=\""),
       let end = rest.firstIndex(of: "\"")
    {
        title = String(rest[..<end])
    }
    var marks: [ClosedRange<Int>] = []
    if let open = info.lastIndex(of: "{"),
       let close = info[open...].firstIndex(of: "}")
    {
        let inner = info[info.index(after: open)..<close]
        for rawSpec in inner.split(separator: ",", omittingEmptySubsequences: false) {
            let spec = trimWs(rawSpec)
            if let dash = spec.firstIndex(of: "-") {
                let a = trimWs(spec[..<dash])
                let b = trimWs(spec[spec.index(after: dash)...])
                if let lo = Int(a), let hi = Int(b), lo >= 0, hi >= lo {
                    marks.append(lo...hi)
                }
            } else if let line = Int(spec), line >= 0 {
                marks.append(line...line)
            }
        }
    }
    return (title, marks)
}

private func statusColor(_ status: String, _ k: Kit) -> Color {
    let lower = status.lowercased()
    let c = k.c
    switch lower {
    case "built", "done", "shipped", "merged", "verified", "green", "good":
        return c.success.fg
    case "risk", "blocked", "failed", "red", "bad", "error":
        return c.danger.fg
    case "proposal", "proposed", "warn", "warning", "hold":
        return c.warning.fg
    case "working", "on a branch", "in flight":
        return c.info.fg
    default:
        return c.textMuted
    }
}

private func splitLeadingStatus(_ val: String) -> (String?, String) {
    let s = trimWs(val)
    if s.hasPrefix("{"), let end = s.dropFirst().firstIndex(of: "}") {
        let st = String(trimWs(s.dropFirst()[..<end]))
        let rest = String(trimWs(s[s.index(after: end)...]))
        return (st, rest)
    }
    return (nil, String(s))
}

private func fnv1a(_ s: String) -> UInt32 {
    var h: UInt32 = 0x811c_9dc5
    for b in s.utf8 {
        h ^= UInt32(b)
        h = h &* 0x0100_0193
    }
    return h
}

private func hex8(_ value: UInt32) -> String {
    let digits: [Character] = [
        "0", "1", "2", "3", "4", "5", "6", "7",
        "8", "9", "a", "b", "c", "d", "e", "f",
    ]
    var chars: [Character] = []
    chars.reserveCapacity(8)
    for shift in stride(from: 28, through: 0, by: -4) {
        let nibble = Int((value >> UInt32(shift)) & 0xF)
        chars.append(digits[nibble])
    }
    return String(chars)
}

private func drawFacts(_ key: String, _ rows: [(String, String)], _ k: Kit) -> El {
    let c = k.c
    var list = col()
        .key(key)
        .wFull()
        .radius(8.0)
        .fill(c.layer02)
        .border(1.0, c.borderWeak)
        .px(14.0)
        .py(6.0)
    for (idx, (label, val)) in rows.enumerated() {
        if idx > 0 {
            list = list.child(el().wFull().h(1.0).fill(c.borderWeak))
        }
        let valKey = "v-\(hex8(fnv1a(val)))"
        let (st, rest) = splitLeadingStatus(val)
        var right = row()
            .key(valKey)
            .gap(6.0)
            .centerY()
            .rideTrailing()
            .motion(Spring.new(0.28, 0.0))
            .transition(Transition.blurReplace())
        if let st {
            let tone = statusColor(st, k)
            right = right
                .child(el().w(7.0).h(7.0).radius(3.5).fill(tone))
                .child(text(st).font(TextStyle.new(12.5, 580.0)).color(tone))
        }
        if !rest.isEmpty {
            right = right.child(text(rest).font(CELL).color(c.textBase))
        }
        list = list.child(
            row()
                .key("fact-\(idx)")
                .wFull()
                .py(7.0)
                .centerY()
                .gap(16.0)
                .child(text(label.uppercased()).font(CAPS).color(c.textMuted))
                .child(spacer())
                .child(right)
        )
    }
    return list
}

private func drawCompare(_ key: String, _ sides: [(String, String)], _ k: Kit) -> El {
    let c = k.c
    var grid = row().key(key).wFull().gap(10.0)
    for (idx, (label, body)) in sides.enumerated() {
        let accent = idx == 0 ? c.danger.fg : c.success.fg
        let pane = col()
            .key("side-\(idx)")
            .grow(1.0)
            .shrink()
            .padding(12.0)
            .gap(6.0)
            .radius(8.0)
            .fill(c.layer02)
            .border(1.0, c.borderWeak)
            .child(
                row()
                    .gap(6.0)
                    .centerY()
                    .child(el().w(6.0).h(6.0).radius(3.0).fill(accent))
                    .child(text(label.uppercased()).font(CAPS).color(accent))
            )
            .child(text(body).wrap().font(CELL).color(c.textBase))
        grid = grid.child(pane)
    }
    return grid
}

private func drawSteps(_ key: String, _ steps: [StepRow], _ k: Kit) -> El {
    let c = k.c
    let built = steps.filter { s in
        switch s.status.lowercased() {
        case "built", "done", "shipped", "merged":
            return true
        default:
            return false
        }
    }.count
    var wrap = col()
        .key(key)
        .wFull()
        .padding(12.0)
        .gap(8.0)
        .radius(8.0)
        .fill(c.layer02)
        .border(1.0, c.borderWeak)
        .child(text("\(built) of \(steps.count) built").font(CAPS).color(c.textMuted))
    for (idx, step) in steps.enumerated() {
        let tone = statusColor(step.status, k)
        let done: Bool
        switch step.status.lowercased() {
        case "built", "done", "shipped", "merged":
            done = true
        default:
            done = false
        }
        let dot = done
            ? el().w(9.0).h(9.0).radius(4.5).fill(tone)
            : el().w(9.0).h(9.0).radius(4.5).border(1.5, tone)
        var r = row()
            .key("step-\(idx)")
            .wFull()
            .gap(9.0)
            .centerY()
            .child(dot)
            .child(text(step.title).font(TextStyle.new(13.5, 540.0)).color(c.textBase))
        if let note = step.note {
            r = r.child(spacer()).child(text(note).font(k.ty.ui).color(c.textMuted))
        }
        wrap = wrap.child(r)
    }
    return wrap
}

private func drawSize(_ key: String, _ size: SizeBar, _ k: Kit) -> El {
    let c = k.c
    let totals: [Int64] = size.parts.map { (_, a, d) in max(a + d, 1) }
    let grand: Int64 = max(totals.reduce(0, +), 1)
    func kindColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "app", "core", "render":
            return c.info.fg
        case "tests", "test":
            return c.success.fg
        case "docs", "doc":
            return c.warning.fg
        default:
            return c.textMuted
        }
    }

    var blocks = row().key("blocks").wFull().gap(3.0)
    var allocated = 0
    for (idx, ((name, _, _), part)) in zip(size.parts, totals).enumerated() {
        let rawCount: Int
        if idx + 1 == size.parts.count {
            rawCount = max(10 - allocated, 1)
        } else {
            rawCount = Int(((Double(part) / Double(grand)) * 10.0).rounded(.toNearestOrAwayFromZero))
        }
        let count = max(rawCount, 1)
        allocated += count
        let fill = kindColor(name)
        for b in 0..<min(count, 10) {
            blocks = blocks.child(el().key("b-\(idx)-\(b)").grow(1.0).h(8.0).radius(2.5).fill(fill))
        }
    }

    var legend = row().key("legend").wFull().gap(12.0).centerY()
    for (name, adds, dels) in size.parts {
        let fill = kindColor(name)
        legend = legend.child(
            row()
                .gap(5.0)
                .centerY()
                .child(el().w(7.0).h(7.0).radius(2.0).fill(fill))
                .child(text("\(name) +\(adds) −\(dels)").font(TextStyle.new(12.0, 480.0)).color(c.textBase))
        )
    }
    if let files = size.files {
        legend = legend.child(spacer()).child(text(files).font(CAPS).color(c.textMuted))
    }

    return col()
        .key(key)
        .wFull()
        .padding(12.0)
        .gap(8.0)
        .radius(8.0)
        .fill(c.layer02)
        .border(1.0, c.borderWeak)
        .child(blocks)
        .child(legend)
}

private func drawCode(
    _ key: String,
    _ title: String?,
    _ marks: [ClosedRange<Int>],
    _ lines: [String],
    _ k: Kit
) -> El {
    let c = k.c
    var card = col().key(key).wFull().radius(8.0).fill(c.bgDeep).border(1.0, c.borderWeak)
    if let title {
        card = card
            .child(
                row()
                    .wFull()
                    .px(12.0)
                    .py(7.0)
                    .fill(c.layer02)
                    .child(text(title).font(k.ty.ui).color(c.textMuted))
            )
            .child(el().wFull().h(1.0).fill(c.borderWeak))
    }
    var body = col().wFull().py(6.0)
    for (idx, raw) in lines.enumerated() {
        let lineNo = idx + 1
        let marked = marks.contains { $0.contains(lineNo) }
        let added = raw.hasPrefix("+")
        let removed = raw.hasPrefix("-")
        let bar: Color
        let bg: Color
        let ink: Color
        if added {
            bar = c.success.fg
            bg = c.success.fg.alpha(0.12)
            ink = c.success.fg
        } else if removed {
            bar = c.danger.fg
            bg = c.danger.fg.alpha(0.12)
            ink = c.danger.fg
        } else if marked {
            bar = c.info.fg
            bg = c.info.fg.alpha(0.12)
            ink = c.textBase
        } else {
            bar = Color.TRANSPARENT
            bg = Color.TRANSPARENT
            ink = c.textBase
        }
        let numStr = lineNo < 10 ? " \(lineNo)" : "\(lineNo)"
        body = body.child(
            row()
                .key("line-\(lineNo)")
                .wFull()
                .px(10.0)
                .py(1.5)
                .gap(8.0)
                .centerY()
                .fill(bg)
                .child(el().w(2.5).h(15.0).radius(1.0).fill(bar))
                .child(text(numStr).font(CODE).color(c.textMuted))
                .child(text(raw).font(CODE).color(ink))
        )
    }
    return card.child(body)
}

private func drawCallout(_ key: String, _ label: String?, _ body: String, _ k: Kit) -> El {
    let c = k.c
    var inner = col().grow(1.0).shrink().gap(4.0)
    if let label {
        inner = inner.child(text(label.uppercased()).font(CAPS).color(c.info.fg))
    }
    inner = inner.child(Markdown.new(body).build(k))
    return row()
        .key(key)
        .wFull()
        .padding(10.0)
        .gap(10.0)
        .radius(6.0)
        .fill(c.info.fg.alpha(0.08))
        .child(el().w(3.0).hFull().radius(1.5).fill(c.info.fg))
        .child(inner)
}
