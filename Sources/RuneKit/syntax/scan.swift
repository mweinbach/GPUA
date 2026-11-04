// Ported from: crates/rune-kit/src/syntax/scan.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The built-in scanners: one small scanner per language family (C-like, Python, shell,
//! markup, CSS, SQL, YAML, diff) walks the bytes once and returns coloured byte ranges. Anything
//! it doesn't recognise stays uncoloured.
//!
//! Input is untrusted. Every scanner only moves forward, lookaheads are either bounded or
//! skip bytes the scanner would visit anyway, and embedded code (template `${}`, JSX `{}`,
//! f-string `{}`, `<script>`, `$()`) nests at most `MAX_DEPTH` deep, so time is linear in the
//! source. Colouring stops after `MAX_SOURCE` bytes or `MAX_TOKENS` ranges; the rest stays
//! plain. Ranges start and end only on ASCII bytes or the ends of the source, so they fall on
//! character boundaries.

enum syntaxScan {
    /// A language family member the scanners know.
    enum Lang: Sendable, Equatable, Hashable {
        /// JavaScript, with JSX.
        case js
        case ts
        case tsx
        case json
        case rust
        case swift
        case go
        case python
        case css
        case shell
        /// HTML and XML.
        case html
        case sql
        case yaml
        /// Unified diffs.
        case diff

        /// The language a fence's info word names (case-insensitive), if it is one we colour.
        static func fromName(_ name: String) -> Lang? {
            switch asciiLowerString(name) {
            case "js", "javascript", "jsx", "mjs", "cjs":
                return .js
            case "ts", "typescript", "mts", "cts":
                return .ts
            case "tsx":
                return .tsx
            case "json", "jsonc", "json5":
                return .json
            case "rust", "rs":
                return .rust
            case "swift":
                return .swift
            case "go", "golang":
                return .go
            case "python", "py", "python3", "py3", "pyi":
                return .python
            case "css":
                return .css
            case "bash", "sh", "shell", "zsh", "shellscript":
                return .shell
            case "html", "htm", "xhtml", "xml", "svg":
                return .html
            case "sql", "postgres", "postgresql", "mysql", "sqlite":
                return .sql
            case "yaml", "yml":
                return .yaml
            case "diff", "patch":
                return .diff
            default:
                return nil
            }
        }
    }

    /// Bytes coloured per block; past this (cut at a line end) the code draws plain.
    static let MAX_SOURCE: Int = 32 * 1024
    /// Coloured ranges per block; past this the code draws plain.
    static let MAX_TOKENS: Int = 8192
    /// How deep embedded code nests (a template's `${}`, JSX's `{}`, HTML's `<script>`).
    static let MAX_DEPTH: UInt8 = 3
    /// The longest a JavaScript regex literal can be, which bounds the lookahead after a `/`.
    static let MAX_REGEX: Int = 512
    /// How deep `matching` follows elements and the code inside them before treating `<` as an
    /// operator.
    static let MAX_FRAMES: Int = 32

    /// A coloured byte range of the source.
    typealias Token = (UInt32, UInt32, Syntax)

    private static func asciiLowerString(_ s: String) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.utf8.count)
        for b in s.utf8 {
            bytes.append(asciiLower(b))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    @inline(__always)
    static func isCharBoundary(_ bytes: [UInt8], _ idx: Int) -> Bool {
        idx >= 0 && idx <= bytes.count && (idx == bytes.count || (bytes[idx] & 0xC0) != 0x80)
    }

    /// How much of `src` gets colour: all of it, or up to the last line end within `MAX_SOURCE`.
    static func colouredLen(_ src: String) -> Int {
        let count = src.utf8.count
        if count <= MAX_SOURCE {
            return count
        }
        var idx = 0
        var lastNewline = 0
        for b in src.utf8 {
            if idx >= MAX_SOURCE {
                break
            }
            if b == 0x0A {
                lastNewline = idx
            }
            idx += 1
        }
        return lastNewline
    }

    static func colouredLenBytes(_ bytes: [UInt8]) -> Int {
        if bytes.count <= MAX_SOURCE {
            return bytes.count
        }
        var k = MAX_SOURCE - 1
        while k >= 0 {
            if bytes[k] == 0x0A {
                return k
            }
            k -= 1
        }
        return 0
    }

    /// The coloured ranges of `src`, in order and not overlapping.
    static func highlight(_ lang: Lang, _ src: String) -> [Token] {
        let bytes = Array(src.utf8)
        let end = colouredLenBytes(bytes)
        var out = Out()
        scan(lang, bytes, 0, end, &out, 0)
        // The scanners only cut at ASCII bytes; this keeps a slip from ever splitting a character.
        out.tokens.removeAll { tok in
            !(isCharBoundary(bytes, Int(tok.0)) && isCharBoundary(bytes, Int(tok.1)))
        }
        return out.tokens
    }

    struct Out {
        var tokens: [Token] = []
        var full: Bool = false

        mutating func push(_ a: Int, _ b: Int, _ s: Syntax) {
            if a >= b || full {
                return
            }
            if let last = tokens.last,
               Int(last.1) == a,
               last.2 == s
            {
                tokens[tokens.count - 1].1 = UInt32(b)
                return
            }
            if tokens.count >= MAX_TOKENS {
                full = true
                return
            }
            tokens.append((UInt32(a), UInt32(b), s))
        }
    }

    static func scan(_ lang: Lang, _ s: [UInt8], _ i: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) {
        switch lang {
        case .js, .ts, .tsx, .json, .rust, .swift, .go:
            cLike(s, i, end, lang, &out, depth)
        case .python:
            python(s, i, end, &out, depth)
        case .diff:
            diff(s, i, end, &out)
        case .css:
            css(s, i, end, &out)
        case .shell:
            shell(s, i, end, &out, depth)
        case .html:
            markup(s, i, end, &out, depth)
        case .sql:
            sql(s, i, end, &out)
        case .yaml:
            yaml(s, i, end, &out)
        }
    }

    // -----------------------------------------------------------------------------------------
    // Shared helpers

    @inline(__always)
    static func at(_ s: [UInt8], _ i: Int, _ end: Int) -> UInt8 {
        (i >= 0 && i < end) ? s[i] : 0
    }

    @inline(__always)
    static func isAsciiAlpha(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }

    @inline(__always)
    static func isAsciiDigit(_ b: UInt8) -> Bool {
        b >= 0x30 && b <= 0x39
    }

    @inline(__always)
    static func isAsciiAlnum(_ b: UInt8) -> Bool {
        isAsciiAlpha(b) || isAsciiDigit(b)
    }

    @inline(__always)
    static func isAsciiUpper(_ b: UInt8) -> Bool {
        b >= 0x41 && b <= 0x5A
    }

    @inline(__always)
    static func isAsciiWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D
    }

    @inline(__always)
    static func asciiLower(_ b: UInt8) -> UInt8 {
        (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
    }

    @inline(__always)
    static func isIdentStart(_ b: UInt8) -> Bool {
        isAsciiAlpha(b) || b == 0x5F || b >= 0x80
    }

    @inline(__always)
    static func isIdent(_ b: UInt8) -> Bool {
        isAsciiAlnum(b) || b == 0x5F || b >= 0x80
    }

    static func identEnd(_ s: [UInt8], _ start: Int, _ end: Int, _ extra: [UInt8]) -> Int {
        var i = start
        while i < end && (isIdent(s[i]) || extra.contains(s[i])) {
            i += 1
        }
        return i
    }

    static func lineEnd(_ s: [UInt8], _ i: Int, _ end: Int) -> Int {
        var k = i
        while k < end {
            if s[k] == 0x0A {
                return k
            }
            k += 1
        }
        return end
    }

    static func starts(_ s: [UInt8], _ i: Int, _ end: Int, _ pat: [UInt8]) -> Bool {
        let clamped = min(max(i, 0), end)
        guard end - clamped >= pat.count else { return false }
        for k in 0..<pat.count where s[i + k] != pat[k] {
            return false
        }
        return true
    }

    static func eqIgnoreAsciiCase(_ s: [UInt8], _ a: Int, _ b: Int, _ pat: [UInt8]) -> Bool {
        guard b - a == pat.count else { return false }
        for k in 0..<pat.count where asciiLower(s[a + k]) != asciiLower(pat[k]) {
            return false
        }
        return true
    }

    /// Where `pat` (a few bytes long) next starts at or after `i`, ignoring ASCII case.
    static func find(_ s: [UInt8], _ i: Int, _ end: Int, _ pat: [UInt8]) -> Int? {
        if end < pat.count || i > end - pat.count {
            return nil
        }
        let last = end - pat.count
        var k = max(i, 0)
        while k <= last {
            if eqIgnoreAsciiCase(s, k, k + pat.count, pat) {
                return k
            }
            k += 1
        }
        return nil
    }

    /// Past the string whose quote `q` is at `i`: after the closing quote, at the line end for a
    /// single-line string, or at `end`.
    static func stringEnd(_ s: [UInt8], _ i: Int, _ end: Int, _ q: UInt8, _ multiline: Bool) -> Int {
        var j = i + 1
        while j < end {
            let c = s[j]
            if c == 0x5C { // '\\'
                j += 2
            } else if c == 0x0A && !multiline {
                return j
            } else if c == q {
                return j + 1
            } else {
                j += 1
            }
        }
        return end
    }

    /// The comments `matching` skips: JavaScript's `//` and `/* */`, or the shell's `#`. `jsx` is
    /// `js` that also steps over JSX elements, whose text is not code (`<p>don't</p>`).
    enum Comments: Equatable {
        case js
        case jsx
        case shell
    }

    /// Where `matching` is inside JSX: code between brackets (with its bracket depth), or an
    /// element (with how many of its tags are open, and whether it is in a tag rather than text).
    enum Frame {
        case code(Int)
        case element(open: Int, inTag: Bool, closing: Bool)
    }

    /// Whether the `<` at `j` (code from `i`) starts a JSX element: it follows an operator, an
    /// opening bracket or `return`, and opens a tag rather than type parameters.
    static func jsxStarts(_ s: [UInt8], _ i: Int, _ j: Int, _ end: Int) -> Bool {
        if !(isIdentStart(at(s, j + 1, end)) || at(s, j + 1, end) == 0x3E) || typeParameters(s, j, end) {
            return false
        }
        var k = j
        while k > i && j - k < 64 && isAsciiWhitespace(s[k - 1]) {
            k -= 1
        }
        let prev: UInt8 = k > i ? s[k - 1] : 0x7B // '{'
        switch prev {
        case 0x28, 0x2C, 0x3D, 0x3A, 0x3F, 0x26, 0x7C, 0x7B, 0x5B, 0x21, 0x3B, 0x3E:
            // '(' ',' '=' ':' '?' '&' '|' '{' '[' '!' ';' '>'
            return true
        default:
            return k >= i + 6
                && starts(s, k - 6, k, Array("return".utf8))
                && (k == i + 6 || !isIdent(s[k - 7]))
        }
    }

    /// The index of the bracket closing the one at `i`, skipping quoted strings and comments, or
    /// `end`.
    static func matching(_ s: [UInt8], _ i: Int, _ end: Int, _ open: UInt8, _ close: UInt8, _ comments: Comments) -> Int {
        var stack: [Frame] = [.code(0)]
        var j = i
        while j < end {
            let top = stack.count - 1
            if case .element(var tags, var inTag, var closing) = stack[top] {
                let c = s[j]
                if inTag {
                    if c == 0x22 || c == 0x27 { // '"' or '\''
                        j = stringEnd(s, j, end, c, true)
                        continue
                    } else if c == 0x7B { // '{'
                        stack.append(.code(0))
                        continue
                    } else if (c == 0x3E) || (c == 0x2F && at(s, j + 1, end) == 0x3E) {
                        j += (c == 0x3E) ? 1 : 2
                        if closing {
                            tags = max(tags - 1, 0)
                        } else if c == 0x3E {
                            tags += 1
                        }
                        inTag = false
                        if tags == 0 {
                            stack.removeLast()
                        } else {
                            stack[top] = .element(open: tags, inTag: inTag, closing: closing)
                        }
                        continue
                    } else if c == 0x3C { // '<'
                        // A tag cut short; read on as code.
                        stack.removeLast()
                        continue
                    }
                } else {
                    if c == 0x7B { // '{'
                        stack.append(.code(0))
                        continue
                    } else if c == 0x3C && at(s, j + 1, end) == 0x2F { // "</"
                        inTag = true
                        closing = true
                        stack[top] = .element(open: tags, inTag: inTag, closing: closing)
                        j += 2
                        continue
                    } else if c == 0x3C && (isIdentStart(at(s, j + 1, end)) || at(s, j + 1, end) == 0x3E) {
                        inTag = true
                        closing = false
                        stack[top] = .element(open: tags, inTag: inTag, closing: closing)
                    } else if c == 0x0A && codeLine(s, j + 1, end) {
                        stack.removeLast()
                    }
                }
                j += 1
                continue
            }

            guard case .code(var depth) = stack[top] else {
                j += 1
                continue
            }
            let c = s[j]
            if c == 0x3C && comments == .jsx && top + 3 <= MAX_FRAMES && jsxStarts(s, i, j, end) {
                stack.append(.element(open: 0, inTag: true, closing: false))
            } else if c == 0x5C { // '\\'
                j += 1
            } else if c == 0x22 || c == 0x27 || c == 0x60 { // '"' '\'' '`'
                j = stringEnd(s, j, end, c, c == 0x60)
                continue
            } else if c == 0x2F && comments != .shell && at(s, j + 1, end) == 0x2F { // "//"
                j = lineEnd(s, j, end)
                continue
            } else if c == 0x2F && comments != .shell && at(s, j + 1, end) == 0x2A { // "/*"
                j = blockCommentEnd(s, j + 2, end, false)
                continue
            } else if c == 0x23 && comments == .shell && j > i && isShellCommentPrefix(s[j - 1]) {
                // A `#` starting a word; `$#` and `a#b` are not comments.
                j = lineEnd(s, j, end)
                continue
            } else if c == open {
                depth += 1
                stack[top] = .code(depth)
            } else if c == close {
                depth -= 1
                stack[top] = .code(depth)
                if depth == 0 {
                    if top == 0 {
                        return j
                    }
                    stack.removeLast()
                }
            }
            j += 1
        }
        return end
    }

    @inline(__always)
    private static func isShellCommentPrefix(_ b: UInt8) -> Bool {
        // ' ' '\t' '\n' '(' ';' '|' '&'
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x28 || b == 0x3B || b == 0x7C || b == 0x26
    }

    static func numberEnd(_ s: [UInt8], _ start: Int, _ end: Int) -> Int {
        var i = start
        let hex = s[i] == 0x30 && (at(s, i + 1, end) == 0x78 || at(s, i + 1, end) == 0x58)
        i += 1
        while i < end {
            let c = s[i]
            if isAsciiAlnum(c) || c == 0x5F {
                let nextByte = at(s, i + 1, end)
                if !hex && (c == 0x65 || c == 0x45) && (nextByte == 0x2B || nextByte == 0x2D) {
                    i += 2
                } else {
                    i += 1
                }
            } else if c == 0x2E && isAsciiDigit(at(s, i + 1, end)) {
                i += 1
            } else {
                break
            }
        }
        return min(i, end)
    }

    static func blockCommentEnd(_ s: [UInt8], _ start: Int, _ end: Int, _ nested: Bool) -> Int {
        var i = start
        var depth: UInt32 = 1
        while i < end {
            if s[i] == 0x2A && at(s, i + 1, end) == 0x2F { // "*/"
                depth -= 1
                i += 2
                if depth == 0 {
                    return i
                }
            } else if nested && s[i] == 0x2F && at(s, i + 1, end) == 0x2A { // "/*"
                depth += 1
                i += 2
            } else {
                i += 1
            }
        }
        return end
    }

    static func isWord(_ s: [UInt8], _ a: Int, _ b: Int, _ list: [String]) -> Bool {
        let len = b - a
        guard len > 0 else { return false }
        for item in list where item.utf8.count == len {
            var match = true
            var idx = a
            for byte in item.utf8 {
                if s[idx] != byte {
                    match = false
                    break
                }
                idx += 1
            }
            if match { return true }
        }
        return false
    }

    static func isWordCI(_ s: [UInt8], _ a: Int, _ b: Int, _ list: [String]) -> Bool {
        let len = b - a
        guard len > 0 else { return false }
        for item in list where item.utf8.count == len {
            var match = true
            var idx = a
            for byte in item.utf8 {
                if asciiLower(s[idx]) != asciiLower(byte) {
                    match = false
                    break
                }
                idx += 1
            }
            if match { return true }
        }
        return false
    }

    static func isAllCaps(_ s: [UInt8], _ a: Int, _ b: Int) -> Bool {
        guard b - a > 1, isAsciiUpper(s[a]) else { return false }
        for idx in a..<b {
            let c = s[idx]
            if !(isAsciiUpper(c) || isAsciiDigit(c) || c == 0x5F) {
                return false
            }
        }
        return true
    }

    // -----------------------------------------------------------------------------------------
    // Diff

    private static let diffHeaders: [[UInt8]] = [
        Array("@@".utf8),
        Array("diff ".utf8),
        Array("index ".utf8),
        Array("--- ".utf8),
        Array("+++ ".utf8),
        Array("\\".utf8),
    ]

    /// Whole lines: added, removed, or a header (`@@`, `diff`, `index`, `---`, `+++`, `\`).
    static func diff(_ s: [UInt8], _ start: Int, _ end: Int, _ out: inout Out) {
        var i = start
        while i < end && !out.full {
            let le = lineEnd(s, i, end)
            let kind: Syntax?
            if le > i && diffHeaders.contains(where: { starts(s, i, le, $0) }) {
                kind = .comment
            } else if le > i {
                switch s[i] {
                case 0x2B: // '+'
                    kind = .inserted
                case 0x2D: // '-'
                    kind = .deleted
                default:
                    kind = nil
                }
            } else {
                kind = nil
            }
            if let k = kind {
                let textEnd = (le > i && s[le - 1] == 0x0D) ? (le - 1) : le
                out.push(i, textEnd, k)
            }
            i = le + 1
        }
    }
}
