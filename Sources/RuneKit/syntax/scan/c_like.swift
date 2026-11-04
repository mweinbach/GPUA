// Ported from: crates/rune-kit/src/syntax/scan/c_like.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! C-like languages: JavaScript, TypeScript, JSX, JSON, Rust, Swift and Go.

extension syntaxScan {
    private static let jsKeywords: [String] = [
        "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do",
        "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new",
        "of", "return", "static", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
    ]
    private static let tsKeywords: [String] = [
        "abstract", "asserts", "declare", "enum", "implements", "infer", "interface", "is", "keyof", "module", "namespace",
        "override", "private", "protected", "public", "readonly", "satisfies", "type", "unique",
    ]
    private static let tsTypes: [String] = [
        "any", "bigint", "boolean", "never", "number", "object", "string", "symbol", "unknown",
    ]
    private static let jsConstants: [String] = ["true", "false", "null", "undefined", "NaN", "Infinity"]
    private static let rustKeywords: [String] = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "fn", "for", "if",
        "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
        "struct", "super", "trait", "type", "union", "unsafe", "use", "where", "while", "yield",
    ]
    private static let rustTypes: [String] = [
        "bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128",
        "usize",
    ]
    private static let swiftKeywords: [String] = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "convenience", "default", "defer", "deinit", "didSet", "do", "else", "enum", "extension", "fallthrough", "final",
        "fileprivate", "for", "func", "get", "guard", "if", "import", "in", "indirect", "init", "inout", "internal", "is",
        "lazy", "let", "mutating", "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat",
        "required", "rethrows", "return", "self", "Self", "set", "some", "static", "struct", "subscript", "super", "switch",
        "throw", "throws", "try", "typealias", "unowned", "var", "weak", "where", "while", "willSet",
    ]
    private static let goKeywords: [String] = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto",
        "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var",
    ]
    private static let goTypes: [String] = [
        "any", "bool", "byte", "comparable", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16",
        "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
    ]
    private static let goConstants: [String] = ["true", "false", "nil", "iota"]
    private static let bools: [String] = ["true", "false"]
    private static let jsonConstants: [String] = ["true", "false", "null"]
    private static let swiftConstants: [String] = ["true", "false", "nil"]
    /// Keywords after which a name is a function or a type being defined.
    private static let definesFunction: [String] = ["fn", "function", "func"]
    private static let definesType: [String] = [
        "class", "struct", "enum", "trait", "interface", "type", "protocol", "extension", "typealias", "actor", "union",
    ]
    /// Keywords that end an expression, so a `/` after them divides and a `<` compares.
    private static let valueKeywords: [String] = ["this", "super", "self", "Self"]
    /// Words that start a statement, not JSX text.
    private static let statementStarts: [String] = [
        "export", "import", "const", "let", "var", "function", "class", "interface", "enum", "return",
    ]

    enum Next: Equatable {
        case any
        case function
        case type
    }

    static func cLike(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ lang: Lang, _ out: inout Out, _ depth: UInt8) {
        var i = startIdx
        let js = (lang == .js || lang == .ts || lang == .tsx)
        let jsx = (lang == .js || lang == .tsx)
        let (keywords, extraKeywords, types, constants): ([String], [String], [String], [String]) = switch lang {
        case .js:
            (jsKeywords, [], [], jsConstants)
        case .ts, .tsx:
            (jsKeywords, tsKeywords, tsTypes, jsConstants)
        case .rust:
            (rustKeywords, [], rustTypes, bools)
        case .swift:
            (swiftKeywords, [], [], swiftConstants)
        case .go:
            (goKeywords, [], goTypes, goConstants)
        default:
            ([], [], [], jsonConstants)
        }

        // Whether the last token ends an expression (a name, literal or closing bracket).
        var value = false
        var next: Next = .any
        var afterDot = false
        let dollarExtra: [UInt8] = [0x24] // "$"
        let tripleQuote: [UInt8] = [0x22, 0x22, 0x22]

        while i < end && !out.full {
            let b = s[i]
            let start = i
            if b == 0x20 || b == 0x09 || b == 0x0D || b == 0x0A {
                i += 1
                continue
            }
            if b == 0x2F && at(s, i + 1, end) == 0x2F { // "//"
                i = lineEnd(s, i, end)
                out.push(start, i, .comment)
                continue
            }
            if b == 0x2F && at(s, i + 1, end) == 0x2A { // "/*"
                i = blockCommentEnd(s, i + 2, end, lang == .rust || lang == .swift)
                out.push(start, i, .comment)
                continue
            }
            let wasDot = afterDot
            afterDot = false
            let wasNext = next
            next = .any

            if lang == .rust && (b == 0x72 || b == 0x62), let e = rustPrefixedLiteral(s, i, end) {
                out.push(start, e, .string)
                i = e
                value = true
            } else if lang == .rust && b == 0x27 { // '\''
                // 'x' and '\n' are characters; 'a with no quote after one character is a lifetime.
                let c = at(s, i + 1, end)
                let after = i + 1 + utf8Len(c)
                if c == 0x5C {
                    i = stringEnd(s, i, end, 0x27, false)
                    out.push(start, i, .string)
                } else if c != 0 && at(s, after, end) == 0x27 {
                    i = after + 1
                    out.push(start, i, .string)
                } else if isIdentStart(c) {
                    i = identEnd(s, i + 1, end, [])
                    out.push(start, i, .keyword)
                } else {
                    i += 1
                    out.push(start, i, .punctuation)
                }
                value = true
            } else if lang == .swift && starts(s, i, end, tripleQuote) {
                if let k = find(s, i + 3, end, tripleQuote) {
                    i = k + 3
                } else {
                    i = end
                }
                out.push(start, i, .string)
                value = true
            } else if b == 0x22 || (b == 0x27 && lang != .swift) {
                i = stringEnd(s, i, end, b, lang == .rust)
                var k = i
                while k < end && isAsciiWhitespace(s[k]) {
                    k += 1
                }
                let key = lang == .json && at(s, k, end) == 0x3A // ':'
                out.push(start, i, key ? .property : .string)
                value = true
            } else if b == 0x60 && js { // '`'
                i = template(s, i, end, lang, &out, depth)
                value = true
            } else if b == 0x60 && lang == .go { // '`'
                // A raw string: no escapes, any lines, to the next backtick.
                var p = i + 1
                var found: Int? = nil
                while p < end {
                    if s[p] == 0x60 {
                        found = p + 1
                        break
                    }
                    p += 1
                }
                i = found ?? end
                out.push(start, i, .string)
                value = true
            } else if b == 0x2F && js && !value, let e = regexEnd(s, i, end) {
                i = e
                out.push(start, i, .string)
                value = true
            } else if b == 0x3C
                && jsx
                && !value
                && (isIdentStart(at(s, i + 1, end)) || at(s, i + 1, end) == 0x3E)
                && !typeParameters(s, i, end)
            {
                i = jsxElement(s, i, end, lang, &out, depth)
                value = true
            } else if isAsciiDigit(b) || (b == 0x2E && !value && isAsciiDigit(at(s, i + 1, end))) {
                i = numberEnd(s, i, end)
                out.push(start, i, .number)
                value = true
            } else if (b == 0x40 && (lang == .ts || lang == .tsx || lang == .js || lang == .swift))
                || (b == 0x23 && lang == .swift)
            {
                i = identEnd(s, i + 1, end, [])
                out.push(start, i, .keyword)
                value = false
            } else if isIdentStart(b) || (b == 0x24 && js) {
                i = identEnd(s, i, end, js ? dollarExtra : [])
                var k = i
                while k < end && (s[k] == 0x20 || s[k] == 0x09) {
                    k += 1
                }
                let call = at(s, k, end) == 0x28 // '('
                // Go capitalises exported names: `Addr string` and `Addr: x` name a field.
                let goField = lang == .go
                    && (isIdentStart(at(s, k, end)) || (at(s, k, end) == 0x3A && at(s, k + 1, end) != 0x3D))
                value = true
                let tok: Syntax?
                if lang == .rust && at(s, i, end) == 0x21 && at(s, i + 1, end) != 0x3D {
                    i += 1
                    tok = .function
                } else if wasDot {
                    tok = call ? .function : nil
                } else if isWord(s, start, i, constants) {
                    tok = .number
                } else if isWord(s, start, i, keywords) || isWord(s, start, i, extraKeywords) {
                    value = isWord(s, start, i, valueKeywords)
                    if isWord(s, start, i, definesFunction) {
                        next = .function
                    } else if isWord(s, start, i, definesType) {
                        next = .type
                    }
                    tok = .keyword
                } else if isWord(s, start, i, types) || wasNext == .type {
                    tok = .type
                } else if wasNext == .function || (lang == .go && call) {
                    // Go capitalises exported functions, so a call is a call before it is a type.
                    tok = .function
                } else if isAllCaps(s, start, i) {
                    tok = .number
                } else if isAsciiUpper(s[start]) && !goField {
                    tok = .type
                } else {
                    tok = call ? .function : nil
                }
                if let t = tok {
                    out.push(start, i, t)
                }
            } else {
                i += 1
                afterDot = (b == 0x2E && at(s, i, end) != 0x2E)
                value = (b == 0x29 || b == 0x5D) // ')' or ']'
                out.push(start, i, .punctuation)
            }
        }
    }

    @inline(__always)
    static func utf8Len(_ lead: UInt8) -> Int {
        if lead >= 0xF0 {
            return 4
        } else if lead >= 0xE0 {
            return 3
        } else if lead >= 0xC0 {
            return 2
        } else {
            return 1
        }
    }

    /// Past a Rust `r"…"`, `r#"…"#`, `b"…"`, `br"…"` or `b'…'` literal starting at `i`.
    private static func rustPrefixedLiteral(_ s: [UInt8], _ i: Int, _ end: Int) -> Int? {
        var j = i
        if s[j] == 0x62 { // 'b'
            j += 1
            switch at(s, j, end) {
            case 0x22:
                return stringEnd(s, j, end, 0x22, true)
            case 0x27:
                return stringEnd(s, j, end, 0x27, false)
            case 0x72: // 'r'
                break
            default:
                return nil
            }
        }
        // A raw string: r, up to 255 #, a quote, and the same quote and #s to close.
        j += 1
        var hashes = 0
        while at(s, j, end) == 0x23 && hashes < 255 {
            hashes += 1
            j += 1
        }
        if at(s, j, end) != 0x22 {
            return nil
        }
        j += 1
        while j < end {
            if s[j] == 0x22 {
                var k = j + 1
                var n = 0
                while n < hashes && at(s, k, end) == 0x23 {
                    n += 1
                    k += 1
                }
                if n == hashes {
                    return k
                }
                j = k
            } else {
                j += 1
            }
        }
        return end
    }

    /// Past a JavaScript regex literal starting at the `/` at `i`, if one closes on this line
    /// within `MAX_REGEX` bytes.
    private static func regexEnd(_ s: [UInt8], _ i: Int, _ end: Int) -> Int? {
        let limit = min(end, i + MAX_REGEX)
        var j = i + 1
        var inClass = false
        while j < limit {
            let c = s[j]
            if c == 0x5C { // '\\'
                j += 1
            } else if c == 0x5B { // '['
                inClass = true
            } else if c == 0x5D { // ']'
                inClass = false
            } else if c == 0x0A { // '\n'
                return nil
            } else if c == 0x2F && !inClass { // '/'
                j += 1
                while j < end && isAsciiAlpha(s[j]) {
                    j += 1
                }
                return j > i + 2 ? j : nil
            }
            j += 1
        }
        return nil
    }

    /// A template literal from the backtick at `i`, its `${}` expressions coloured as code.
    private static func template(_ s: [UInt8], _ i: Int, _ end: Int, _ lang: Lang, _ out: inout Out, _ depth: UInt8) -> Int {
        var seg = i
        var j = i + 1
        let comments: Comments = (lang == .js || lang == .tsx) ? .jsx : .js
        while j < end && !out.full {
            let c = s[j]
            if c == 0x5C { // '\\'
                j += 2
            } else if c == 0x60 { // '`'
                out.push(seg, j + 1, .string)
                return j + 1
            } else if c == 0x24 && at(s, j + 1, end) == 0x7B { // "${"
                out.push(seg, j, .string)
                let close = matching(s, j + 1, end, 0x7B, 0x7D, comments)
                out.push(j, j + 2, .punctuation)
                if depth < MAX_DEPTH {
                    cLike(s, j + 2, close, lang, &out, depth + 1)
                }
                if close >= end {
                    return end
                }
                out.push(close, close + 1, .punctuation)
                j = close + 1
                seg = j
            } else {
                j += 1
            }
        }
        let clamped = min(j, end)
        out.push(seg, clamped, .string)
        return clamped
    }

    /// Whether the `<` at `i` opens TypeScript type parameters rather than a JSX tag: `<T,>(…)`,
    /// `<T extends U>(…)`, or `<T>(…)` followed by `=>` or `:`. Looks at most `MAX_REGEX` bytes
    /// ahead, on this line.
    static func typeParameters(_ s: [UInt8], _ i: Int, _ end: Int) -> Bool {
        let limit = min(end, i + MAX_REGEX)
        var angles: UInt32 = 0
        var j = i + 1
        let arrow: [UInt8] = [0x3D, 0x3E] // "=>"
        let extendsBytes: [UInt8] = Array("extends".utf8)
        while j < limit {
            let c = s[j]
            if c == 0x3C { // '<'
                angles += 1
            } else if c == 0x3E && angles > 0 { // '>'
                angles -= 1
            } else if c == 0x3E { // '>'
                if at(s, j + 1, limit) != 0x28 { // '('
                    return false
                }
                // `<T>(x: T) => T` is a signature; `<b>(note)</b>` is an element.
                var parens: UInt32 = 0
                var k = j + 1
                while k < limit && s[k] != 0x0A {
                    if s[k] == 0x28 {
                        parens += 1
                    } else if s[k] == 0x29 {
                        parens -= 1
                        if parens == 0 {
                            break
                        }
                    }
                    k += 1
                }
                if at(s, k, limit) != 0x29 {
                    return true
                }
                k += 1
                while at(s, k, limit) == 0x20 || at(s, k, limit) == 0x09 {
                    k += 1
                }
                return starts(s, k, limit, arrow) || at(s, k, limit) == 0x3A
            } else if c == 0x2C && angles == 0 { // ','
                return true
            } else if c == 0x3D || c == 0x7B || c == 0x22 || c == 0x27 || c == 0x2F || c == 0x0A {
                // '=' '{' '"' '\'' '/' '\n'
                return false
            } else if isIdentStart(c) {
                let e = identEnd(s, j, limit, [])
                if e - j == extendsBytes.count && starts(s, j, e, extendsBytes) {
                    return true
                }
                j = e
                continue
            }
            j += 1
        }
        return false
    }

    /// Whether the line from `i` starts like code rather than JSX text: with a statement keyword
    /// or a closing `}`, `)` or `;`. An element still open there never closed, so scanning goes
    /// back to code instead of taking the rest of the block as children.
    static func codeLine(_ s: [UInt8], _ start: Int, _ end: Int) -> Bool {
        var i = start
        while at(s, i, end) == 0x20 || at(s, i, end) == 0x09 || at(s, i, end) == 0x0D {
            i += 1
        }
        let c = at(s, i, end)
        if c == 0x7D || c == 0x29 || c == 0x3B { // '}' ')' ';'
            return true
        }
        if isIdentStart(c) {
            let e = identEnd(s, i, end, [])
            return isWord(s, i, e, statementStarts)
        }
        return false
    }

    /// A JSX element (with its children and nested elements) from the `<` at `i`. One that never
    /// closes ends at a stray `<` in a tag or at the first line that reads as code.
    private static func jsxElement(_ s: [UInt8], _ start: Int, _ end: Int, _ lang: Lang, _ out: inout Out, _ depth: UInt8) -> Int {
        var i = start
        var open = 0
        let tagNameExtra: [UInt8] = [0x2E, 0x3A, 0x2D, 0x24] // ".:-$"
        let attrExtra: [UInt8] = [0x2D, 0x3A] // "-:"
        while true {
            let closing = at(s, i + 1, end) == 0x2F // '/'
            var j = i + 1 + (closing ? 1 : 0)
            out.push(i, j, .punctuation)
            let name = j
            j = identEnd(s, j, end, tagNameExtra)
            if j > name {
                out.push(name, j, isAsciiUpper(s[name]) ? .type : .keyword)
            }
            var selfClosing = false
            var closed = false
            while j < end && !out.full {
                let c = s[j]
                if c == 0x3E { // '>'
                    out.push(j, j + 1, .punctuation)
                    j += 1
                    closed = true
                    break
                } else if c == 0x2F && at(s, j + 1, end) == 0x3E { // "/>"
                    out.push(j, j + 2, .punctuation)
                    j += 2
                    selfClosing = true
                    closed = true
                    break
                } else if c == 0x22 || c == 0x27 {
                    let e = stringEnd(s, j, end, c, true)
                    out.push(j, e, .string)
                    j = e
                } else if c == 0x7B { // '{'
                    j = jsxExpression(s, j, end, lang, &out, depth)
                } else if c == 0x3D { // '='
                    out.push(j, j + 1, .punctuation)
                    j += 1
                } else if c == 0x3C { // '<'
                    break
                } else if c == 0x0A && codeLine(s, j + 1, end) {
                    break
                } else if isIdentStart(c) {
                    let e = identEnd(s, j, end, attrExtra)
                    out.push(j, e, .property)
                    j = e
                } else {
                    j += 1
                }
            }
            if !closed {
                return min(j, end)
            }
            if closing {
                open = max(open - 1, 0)
            } else if !selfClosing {
                open += 1
            }
            if open == 0 {
                return j
            }
            // Children: text stays plain, `{…}` is code, `<` before a name, `/` or `>` starts the
            // next tag (`a < b` is text).
            while true {
                if j >= end || out.full {
                    return end
                }
                let c = s[j]
                if c == 0x3C {
                    let nxt = at(s, j + 1, end)
                    if nxt == 0x2F || nxt == 0x3E || isIdentStart(nxt) {
                        break
                    }
                    j += 1
                } else if c == 0x7B {
                    j = jsxExpression(s, j, end, lang, &out, depth)
                } else if c == 0x0A && codeLine(s, j + 1, end) {
                    return j
                } else {
                    j += 1
                }
            }
            i = j
        }
    }

    private static func jsxExpression(_ s: [UInt8], _ j: Int, _ end: Int, _ lang: Lang, _ out: inout Out, _ depth: UInt8) -> Int {
        let close = matching(s, j, end, 0x7B, 0x7D, .jsx)
        out.push(j, j + 1, .punctuation)
        if depth < MAX_DEPTH {
            cLike(s, j + 1, close, lang, &out, depth + 1)
        }
        if close >= end {
            return end
        }
        out.push(close, close + 1, .punctuation)
        return close + 1
    }
}
