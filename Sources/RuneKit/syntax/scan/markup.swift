// Ported from: crates/rune-kit/src/syntax/scan/markup.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Markup (HTML and XML) and CSS.

extension syntaxScan {
    private static let htmlCommentStart: [UInt8] = Array("<!--".utf8)
    private static let htmlCommentEnd: [UInt8] = Array("-->".utf8)
    private static let cdataStart: [UInt8] = Array("<![CDATA[".utf8)
    private static let cdataEnd: [UInt8] = Array("]]>".utf8)
    private static let scriptWord: [UInt8] = Array("script".utf8)
    private static let scriptClose: [UInt8] = Array("</script".utf8)
    private static let styleWord: [UInt8] = Array("style".utf8)
    private static let styleClose: [UInt8] = Array("</style".utf8)
    private static let markupIdentExtra: [UInt8] = [0x2D, 0x3A, 0x2E] // "-:."
    private static let cssIdentExtra: [UInt8] = [0x2D] // "-"

    static func markup(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) {
        var i = startIdx
        while i < end && !out.full {
            let b = s[i]
            if starts(s, i, end, htmlCommentStart) {
                let e = find(s, i + 4, end, htmlCommentEnd).map { $0 + 3 } ?? end
                out.push(i, e, .comment)
                i = e
            } else if starts(s, i, end, cdataStart) {
                let e = find(s, i + 9, end, cdataEnd).map { $0 + 3 } ?? end
                out.push(i, e, .string)
                i = e
            } else if b == 0x3C && (isIdentStart(at(s, i + 1, end)) || at(s, i + 1, end) == 0x2F || at(s, i + 1, end) == 0x21 || at(s, i + 1, end) == 0x3F) {
                let (e, name, closing, selfClosing) = tag(s, i, end, &out)
                i = e
                let embedded: (Lang, [UInt8])?
                if eqIgnoreAsciiCase(s, name.0, name.1, scriptWord) {
                    embedded = (.js, scriptClose)
                } else if eqIgnoreAsciiCase(s, name.0, name.1, styleWord) {
                    embedded = (.css, styleClose)
                } else {
                    embedded = nil
                }
                if let (lang, close) = embedded, !closing, !selfClosing {
                    let stop = find(s, i, end, close) ?? end
                    if depth < MAX_DEPTH {
                        scan(lang, s, i, stop, &out, depth + 1)
                    }
                    i = stop
                }
            } else if b == 0x26 { // '&'
                let limit = min(end, i + 32)
                var found: Int? = nil
                var k = i + 1
                while k < limit {
                    if !(isAsciiAlnum(s[k]) || s[k] == 0x23) {
                        found = k
                        break
                    }
                    k += 1
                }
                if let e = found, e > i + 1, s[e] == 0x3B { // ';'
                    out.push(i, e + 1, .number)
                    i = e + 1
                } else {
                    i += 1
                }
            } else {
                i += 1
            }
        }
    }

    /// A tag from the `<` at `i`: (its end, its name's range, whether it closes, whether it is
    /// self-closing or a declaration).
    private static func tag(_ s: [UInt8], _ i: Int, _ end: Int, _ out: inout Out) -> (Int, (Int, Int), Bool, Bool) {
        var j = i + 1
        let nxt = at(s, j, end)
        let closing = nxt == 0x2F // '/'
        let decl = (nxt == 0x21 || nxt == 0x3F) // '!' or '?'
        if closing || decl {
            j += 1
        }
        out.push(i, j, .punctuation)
        let name = (j, identEnd(s, j, end, markupIdentExtra))
        out.push(name.0, name.1, .keyword)
        j = name.1
        while j < end && !out.full {
            let c = s[j]
            if c == 0x3E { // '>'
                out.push(j, j + 1, .punctuation)
                return (j + 1, name, closing, decl)
            } else if (c == 0x2F || c == 0x3F) && at(s, j + 1, end) == 0x3E { // "/>" or "?>"
                out.push(j, j + 2, .punctuation)
                return (j + 2, name, closing, true)
            } else if c == 0x3C { // '<'
                return (j, name, closing, true)
            } else if c == 0x22 || c == 0x27 {
                let e = stringEnd(s, j, end, c, true)
                out.push(j, e, .string)
                j = e
            } else if c == 0x3D { // '='
                out.push(j, j + 1, .punctuation)
                j += 1
                let v = j
                while j < end && !isUnquotedAttrStop(s[j]) {
                    j += 1
                }
                out.push(v, j, .string)
            } else if isIdentStart(c) {
                let e = identEnd(s, j, end, markupIdentExtra)
                out.push(j, e, .property)
                j = e
            } else {
                j += 1
            }
        }
        return (end, name, closing, true)
    }

    @inline(__always)
    private static func isUnquotedAttrStop(_ b: UInt8) -> Bool {
        // ' ' '\t' '\r' '\n' '>' '"' '\'' '<'
        b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A || b == 0x3E || b == 0x22 || b == 0x27 || b == 0x3C
    }

    // CSS

    static func css(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out) {
        var i = startIdx
        var blocks = 0
        // At a statement's start, before its first token; inside a declaration; after its `:`.
        var fresh = true
        var decl = false
        var value = false

        @inline(__always)
        func identStart(_ k: Int) -> Bool {
            isIdentStart(at(s, k, end)) || (at(s, k, end) == 0x2D && isIdentStart(at(s, k + 1, end)))
        }

        while i < end && !out.full {
            let b = s[i]
            let start = i
            if isAsciiWhitespace(b) {
                i += 1
                continue
            }
            if b == 0x2F && at(s, i + 1, end) == 0x2A { // "/*"
                i = blockCommentEnd(s, i + 2, end, false)
                out.push(start, i, .comment)
                continue
            }
            if b == 0x7B || b == 0x7D || b == 0x3B { // '{' '}' ';'
                if b == 0x7B {
                    blocks += 1
                } else if b == 0x7D {
                    blocks = max(blocks - 1, 0)
                }
                i += 1
                out.push(start, i, .punctuation)
                fresh = true
                decl = false
                value = false
                continue
            }
            if fresh {
                fresh = false
                // Inside braces, a statement that reaches `;` or `}` (or the end) before `{` is a
                // declaration; otherwise it is a nested rule's selector.
                if blocks > 0 {
                    var stopper: UInt8? = nil
                    var k = i
                    while k < end {
                        let c = s[k]
                        if c == 0x7B || c == 0x3B || c == 0x7D {
                            stopper = c
                            break
                        }
                        k += 1
                    }
                    decl = stopper != 0x7B
                } else {
                    decl = false
                }
            }
            if b == 0x22 || b == 0x27 {
                i = stringEnd(s, i, end, b, false)
                out.push(start, i, .string)
            } else if b == 0x3A && decl && !value { // ':'
                i += 1
                out.push(start, i, .punctuation)
                value = true
            } else if b == 0x40 { // '@'
                i = identEnd(s, i + 1, end, cssIdentExtra)
                out.push(start, i, .keyword)
            } else if b == 0x23 && value { // '#'
                i = identEnd(s, i + 1, end, [])
                out.push(start, i, .number)
            } else if (b == 0x23 || b == 0x2E) && !value && identStart(i + 1) {
                i = identEnd(s, i + 1, end, cssIdentExtra)
                out.push(start, i, .type)
            } else if b == 0x3A && !value { // ':'
                while at(s, i, end) == 0x3A {
                    i += 1
                }
                i = identEnd(s, i, end, cssIdentExtra)
                out.push(start, i, .keyword)
            } else if b == 0x21 && value { // '!'
                i = identEnd(s, i + 1, end, [])
                out.push(start, i, .keyword)
            } else if isAsciiDigit(b) || ((b == 0x2E || b == 0x2D || b == 0x2B) && value && isAsciiDigit(at(s, i + 1, end))) {
                let signAdvance = (b != 0x2E && !isAsciiDigit(b)) ? 1 : 0
                i = numberEnd(s, i + signAdvance, end)
                if at(s, i, end) == 0x25 { // '%'
                    i += 1
                }
                out.push(start, i, .number)
            } else if b == 0x2D && at(s, i + 1, end) == 0x2D { // "--"
                i = identEnd(s, i + 2, end, cssIdentExtra)
                out.push(start, i, .property)
            } else if identStart(i) {
                i = identEnd(s, i + 1, end, cssIdentExtra)
                if decl && !value {
                    out.push(start, i, .property)
                } else if at(s, i, end) == 0x28 { // '('
                    out.push(start, i, .function)
                }
            } else {
                i += 1
                out.push(start, i, .punctuation)
            }
        }
    }
}
