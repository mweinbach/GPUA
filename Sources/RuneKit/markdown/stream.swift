// Ported from: crates/rune-kit/src/markdown/stream.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A source still arriving (``Markdown/streaming(_:)``): its tail is parsed as what it is about to
//! become, so no markup flashes as text and no block changes kind under the reader.

import Rune

/// ``parseDoc(_:_:)`` of `src` as a stream's current text.
func parseStreaming(_ src: String, _ autolink: Bool) -> ParsedDoc {
    let (raw, tail) = parseDocTail(src, autolink)
    let srcBytes = Array(src.utf8)
    let end = heldTable(srcBytes, tail, raw.blocks.last) ?? srcBytes.count
    let patch: StreamPatch?
    switch tail {
    case .inline(let start, let scope) where start < end:
        let slice = String(decoding: srcBytes[start..<end], as: UTF8.self)
        patch = closeTail(slice, start, scope)
    default:
        patch = nil
    }
    guard let p = patch else {
        if end == srcBytes.count {
            return raw
        } else {
            return parseDoc(String(decoding: srcBytes[0..<end], as: UTF8.self), autolink)
        }
    }
    if !p.closers.isEmpty {
        let keptStr = trimEndUnicodeWhitespace(String(decoding: srcBytes[0..<p.cut], as: UTF8.self))
        let keptLen = keptStr.utf8.count
        let view = keptStr + p.closers
        var doc = parseDoc(view, autolink)
        let added = keptLen..<view.utf8.count
        let markerShown = p.markers.contains(where: { r in doc.maps.contains(where: { m in shows(m, r) }) })
            || doc.maps.contains(where: { m in shows(m, added) })
        if !markerShown {
            if p.code {
                dropClosingPad(&doc)
            }
            return doc
        }
    }
    let cutPrefix = String(decoding: srcBytes[0..<p.cut], as: UTF8.self)
    let doc = parseDoc(cutPrefix, autolink)
    if streamTableColumns(doc) >= streamTableColumns(raw) {
        return doc
    }
    // Leaving markers out of a header's last cell (`| a | *`) left that cell out too: keep it,
    // empty, so the table keeps its columns.
    let pipedDoc = parseDoc(cutPrefix + "|", autolink)
    return streamTableColumns(pipedDoc) >= streamTableColumns(raw) ? pipedDoc : raw
}

/// How many columns the last block has, if it's a table.
private func streamTableColumns(_ doc: ParsedDoc) -> Int {
    guard case .table(let t)? = doc.blocks.last else { return 0 }
    return max(t.align.count, t.head.count)
}

/// Where the trailing `|` lines start, when they may still become a table's header or row and
/// don't draw as a table yet.
private func heldTable(_ srcBytes: [UInt8], _ tail: Tail, _ last: MarkdownBlock?) -> Int? {
    if tail == .code {
        return nil
    }
    if case .table? = last {
        return nil
    }
    let bodyEnd = (!srcBytes.isEmpty && srcBytes[srcBytes.count - 1] == 0x0A) ? (srcBytes.count - 1) : srcBytes.count
    let open = (bodyEnd == srcBytes.count)

    func lineStart(_ end: Int) -> Int {
        var k = end
        while k > 0 {
            k -= 1
            if srcBytes[k] == 0x0A {
                return k + 1
            }
        }
        return 0
    }

    func piped(_ range: Range<Int>) -> Bool {
        let s = trimStartUnicodeWhitespace(String(decoding: srcBytes[range], as: UTF8.self))
        return s.hasPrefix("|")
    }

    func delim(_ range: Range<Int>) -> Bool {
        let s = trimUnicodeWhitespace(String(decoding: srcBytes[range], as: UTF8.self))
        for scalar in s.unicodeScalars {
            switch scalar {
            case "|", ":", "-", " ":
                continue
            default:
                return false
            }
        }
        return true
    }

    func header(_ at: Int) -> Int? {
        guard at >= 1 else { return nil }
        let s = lineStart(at - 1)
        let above: Int? = (s >= 1) ? lineStart(s - 1) : nil
        let isHeader = piped(s..<(at - 1))
            && !delim(s..<(at - 1))
            && (above == nil || !piped(above! ..< (s - 1)))
        return isHeader ? s : nil
    }

    let line = lineStart(bodyEnd)
    if !piped(line..<bodyEnd) {
        return nil
    }
    if open {
        if let h = header(line), delim(line..<bodyEnd) {
            return h
        }
        return line
    }
    // A finished line under another isn't a header unless that one is, and it isn't.
    if line == 0 || !piped(lineStart(line - 1)..<(line - 1)) {
        return line
    }
    return nil
}

/// How to end a stream's last inline run for its parse.
private struct StreamPatch: Equatable {
    var cut: Int
    var closers: String
    var markers: [Range<Int>]
    var code: Bool
}

private struct StreamOpen {
    var at: Int
    var ch: UInt8
    var n: Int
}

/// What ends `run`, the source from byte `base` of the inline text the stream ends in: `nil`
/// when it ends on nothing open.
private func closeTail(_ run: String, _ base: Int, _ scope: Scope) -> StreamPatch? {
    // A blank line ended the paragraph: what's open in it stays as written.
    if scope == .para {
        let lines = run.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count >= 2 {
            for idx in 0..<(lines.count - 1) {
                if trimUnicodeWhitespace(String(lines[idx])).isEmpty {
                    return nil
                }
            }
        }
    }
    let b = Array(run.utf8)
    var stack: [StreamOpen] = []
    var code: (Int, Int)? = nil
    var cut = b.count
    var i = 0
    while i < b.count {
        let byte = b[i]
        if byte == 0x5C { // '\\'
            if i + 1 < b.count {
                i += 1 + utf8CharByteCount(b[i + 1])
            } else {
                i += 1
            }
            continue
        }
        if byte == 0x0A && scope != .para {
            stack.removeAll(keepingCapacity: true)
            i += 1
            continue
        }
        if byte == 0x7C && scope == .cell { // '|'
            stack.removeAll(keepingCapacity: true)
            i += 1
            continue
        }
        if byte == 0x60 { // '`'
            let n = runLen(b, i)
            if let j = closingTicks(b, i + n, n) {
                i = j + n
                continue
            } else {
                code = (i, n)
                break
            }
        }
        if (byte == 0x68 || byte == 0x77) && urlAt(b, i) { // 'h' or 'w'
            let rest = String(decoding: b[i..<b.count], as: UTF8.self)
            var adv = 0
            for sc in rest.unicodeScalars {
                if sc.properties.isWhitespace {
                    break
                }
                adv += sc.utf8.count
            }
            i += max(adv, 1)
            continue
        }
        if byte == 0x2A || byte == 0x5F || byte == 0x7E { // '*', '_', '~'
            let n = runLen(b, i)
            let before = lastScalar(b, 0..<i)
            guard let after = firstScalar(b, (i + n)..<b.count) else {
                // At the very end: hidden while it may still open or close a span.
                let mayClose = !isSpace(before) && stack.contains(where: { $0.ch == byte })
                if isWordStart(before) || mayClose {
                    cut = i
                }
                break
            }
            if byte == 0x7E && n != 2 {
                i += n
                continue
            }
            let (opens, closes) = flanks(byte, before, after)
            var left = n
            if closes {
                while left > 0 {
                    guard let p = stack.lastIndex(where: { $0.ch == byte }) else { break }
                    let used = min(stack[p].n, left)
                    stack[p].n -= used
                    left -= used
                    let newCount = (stack[p].n == 0) ? p : (p + 1)
                    if newCount < stack.count {
                        stack.removeSubrange(newCount..<stack.count)
                    }
                }
            }
            if left > 0 && opens {
                stack.append(StreamOpen(at: i + n - left, ch: byte, n: left))
            }
            i += n
            continue
        }
        i += utf8CharByteCount(byte)
    }

    if let (at, n) = code {
        var contentEnd = cut
        while contentEnd > 0 && b[contentEnd - 1] == 0x60 {
            contentEnd -= 1
        }
        let trimmed = trimEndUnicodeWhitespace(String(decoding: b[0..<contentEnd], as: UTF8.self)).utf8.count
        if trimmed <= at + n {
            cut = at
            code = nil
        } else {
            cut = trimmed
        }
    }
    // An opener with nothing after it yet is left out with what follows.
    if code == nil {
        while let o = stack.last {
            let trimmedLen = trimEndUnicodeWhitespace(String(decoding: b[0..<cut], as: UTF8.self)).utf8.count
            if trimmedLen <= o.at + o.n {
                cut = o.at
                stack.removeLast()
            } else {
                break
            }
        }
    }
    var closers = ""
    var markers: [Range<Int>] = []
    if let (at, n) = code {
        if at + n < cut && b[at + n] == 0x20 {
            closers.append(" ")
        }
        closers.append(String(repeating: "`", count: n))
        markers.append((base + at)..<(base + at + n))
    }
    for o in stack.reversed() {
        let ch = Character(UnicodeScalar(o.ch))
        closers.append(String(repeating: String(ch), count: o.n))
        markers.append((base + o.at)..<(base + o.at + o.n))
    }
    if cut < b.count || !closers.isEmpty {
        return StreamPatch(cut: base + cut, closers: closers, markers: markers, code: code != nil)
    }
    return nil
}

@inline(__always)
private func utf8CharByteCount(_ lead: UInt8) -> Int {
    if lead < 0x80 { return 1 }
    if (lead & 0xE0) == 0xC0 { return 2 }
    if (lead & 0xF0) == 0xE0 { return 3 }
    if (lead & 0xF8) == 0xF0 { return 4 }
    return 1
}

private func runLen(_ b: [UInt8], _ i: Int) -> Int {
    let ch = b[i]
    var k = i
    while k < b.count && b[k] == ch {
        k += 1
    }
    return k - i
}

private func closingTicks(_ b: [UInt8], _ from: Int, _ n: Int) -> Int? {
    var cur = from
    while cur < b.count {
        if b[cur] != 0x60 {
            cur += 1
            continue
        }
        let len = runLen(b, cur)
        if len == n {
            return cur
        }
        cur += len
    }
    return nil
}

private func urlAt(_ b: [UInt8], _ i: Int) -> Bool {
    let rest = String(decoding: b[i..<b.count], as: UTF8.self)
    guard rest.hasPrefix("https://") || rest.hasPrefix("http://") || rest.hasPrefix("www.") else {
        return false
    }
    guard let prev = lastScalar(b, 0..<i) else { return true }
    return prev.properties.isWhitespace || prev == "(" || prev == "<" || prev == "["
}

private func firstScalar(_ b: [UInt8], _ range: Range<Int>) -> UnicodeScalar? {
    guard range.lowerBound < range.upperBound else { return nil }
    return String(decoding: b[range], as: UTF8.self).unicodeScalars.first
}

private func lastScalar(_ b: [UInt8], _ range: Range<Int>) -> UnicodeScalar? {
    guard range.lowerBound < range.upperBound else { return nil }
    return String(decoding: b[range], as: UTF8.self).unicodeScalars.last
}

private func isSpace(_ c: UnicodeScalar?) -> Bool {
    guard let c else { return true }
    return c.properties.isWhitespace
}

private func isAlphaNum(_ c: UnicodeScalar) -> Bool {
    if c.value < 0x80 {
        return (c.value >= 0x30 && c.value <= 0x39)
            || (c.value >= 0x41 && c.value <= 0x5A)
            || (c.value >= 0x61 && c.value <= 0x7A)
    }
    switch c.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
         .decimalNumber, .letterNumber, .otherNumber:
        return true
    default:
        return false
    }
}

private func isPunct(_ c: UnicodeScalar?) -> Bool {
    guard let c else { return false }
    return !isAlphaNum(c) && !c.properties.isWhitespace
}

private func isWordStart(_ before: UnicodeScalar?) -> Bool {
    isSpace(before) || isPunct(before)
}

private func flanks(_ ch: UInt8, _ before: UnicodeScalar?, _ afterScalar: UnicodeScalar) -> (Bool, Bool) {
    let after: UnicodeScalar? = afterScalar
    let left = !isSpace(after) && (!isPunct(after) || isWordStart(before))
    let right = !isSpace(before) && (!isPunct(before) || isWordStart(after))
    if ch == 0x5F { // '_'
        return (left && (!right || isPunct(before)), right && (!left || isPunct(after)))
    } else {
        return (left && isWordStart(before), right)
    }
}

func trimEndUnicodeWhitespace(_ s: String) -> String {
    var scalars = s.unicodeScalars
    while let last = scalars.last, last.properties.isWhitespace {
        scalars.removeLast()
    }
    return String(scalars)
}

func trimStartUnicodeWhitespace(_ s: String) -> String {
    var scalars = s.unicodeScalars
    while let first = scalars.first, first.properties.isWhitespace {
        scalars.removeFirst()
    }
    return String(scalars)
}

func trimUnicodeWhitespace(_ s: String) -> String {
    trimEndUnicodeWhitespace(trimStartUnicodeWhitespace(s))
}

/// Drops the padding after a code span the stream is still inside, so its text only grows.
private func dropClosingPad(_ doc: inout ParsedDoc) {
    guard !doc.blocks.isEmpty, doc.blocks.count == doc.maps.count else { return }
    let idx = doc.blocks.count - 1
    dropClosingPadInBlock(&doc.blocks[idx], &doc.maps[idx])
}

private func dropClosingPadInBlock(_ block: inout MarkdownBlock, _ map: inout BlockMap) {
    switch (block, map) {
    case (.para(var inl), .inline(var m)):
        if stripPad(&inl, &m) {
            block = .para(inl)
            map = .inline(m)
        }
    case (.heading(let lvl, var inl), .inline(var m)):
        if stripPad(&inl, &m) {
            block = .heading(lvl, inl)
            map = .inline(m)
        }
    case (.list(let start, var items), .list(var maps)):
        guard !items.isEmpty, items.count == maps.count else { return }
        let li = items.count - 1
        guard !items[li].isEmpty, items[li].count == maps[li].count else { return }
        let bi = items[li].count - 1
        dropClosingPadInBlock(&items[li][bi], &maps[li][bi])
        block = .list(start: start, items: items)
        map = .list(maps)
    case (.quote(var inner), .quote(var maps)):
        guard !inner.isEmpty, inner.count == maps.count else { return }
        let bi = inner.count - 1
        dropClosingPadInBlock(&inner[bi], &maps[bi])
        block = .quote(inner)
        map = .quote(maps)
    case (.table(var t), .table(var head, var rows)):
        if !t.rows.isEmpty, t.rows.count == rows.count {
            let ri = t.rows.count - 1
            if !t.rows[ri].isEmpty, t.rows[ri].count == rows[ri].count {
                let ci = t.rows[ri].count - 1
                if stripPad(&t.rows[ri][ci], &rows[ri][ci]) {
                    block = .table(t)
                    map = .table(head: head, rows: rows)
                }
            }
        } else if !t.head.isEmpty, t.head.count == head.count {
            let ci = t.head.count - 1
            if stripPad(&t.head[ci], &head[ci]) {
                block = .table(t)
                map = .table(head: head, rows: rows)
            }
        }
    default:
        break
    }
}

private func stripPad(_ inl: inout MarkdownInline, _ map: inout SpanMap) -> Bool {
    let len = inl.text.utf8.count
    let padLen = PAD.utf8.count
    guard let k = inl.spans.firstIndex(where: { $0.2 == .codePad && $0.1 == len && $0.0 + padLen == len }) else {
        return false
    }
    inl.spans.remove(at: k)
    let cut = len - padLen
    let bytes = Array(inl.text.utf8)
    inl.text = String(decoding: bytes[0..<cut], as: UTF8.self)
    inl.spans = inl.spans.compactMap { s in
        let b = min(s.1, cut)
        return s.0 < b ? (s.0, b, s.2) : nil
    }
    inl.links = inl.links.compactMap { l in
        let b = min(l.1, cut)
        return l.0 < b ? (l.0, b, l.2) : nil
    }
    map.truncateOut(cut)
    return true
}

/// Whether any of `map`'s text comes from source bytes `r`.
private func shows(_ map: BlockMap, _ r: Range<Int>) -> Bool {
    func hit(_ m: SpanMap) -> Bool {
        m.pairs.contains { (s, _) in s.lowerBound < r.upperBound && r.lowerBound < s.upperBound }
    }
    switch map {
    case .inline(let m), .code(let m):
        return hit(m)
    case .list(let items):
        return items.contains { item in item.contains { b in shows(b, r) } }
    case .quote(let inner):
        return inner.contains { b in shows(b, r) }
    case .table(let head, let rows):
        return head.contains(where: hit) || rows.contains { row in row.contains(where: hit) }
    case .none:
        return false
    }
}
