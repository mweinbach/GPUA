// Ported from: crates/rune-kit/src/syntax/scan/python.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Python.

extension syntaxScan {
    private static let pyKeywords: [String] = [
        "and", "as", "assert", "async", "await", "break", "class", "cls", "continue", "def", "del", "elif", "else", "except",
        "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise",
        "return", "self", "try", "while", "with", "yield",
    ]
    /// Keywords only at the start of a statement that ends in `:` (`match x:`, `case [a, b]:`).
    private static let pySoftKeywords: [String] = ["match", "case"]
    private static let pyConstants: [String] = ["True", "False", "None", "Ellipsis", "NotImplemented"]
    private static let pyTypes: [String] = [
        "bool", "bytearray", "bytes", "complex", "dict", "float", "frozenset", "int", "list", "object", "set", "str", "tuple",
        "type",
    ]
    private static let dotExtra: [UInt8] = [0x2E] // "."
    private static let defBytes: [UInt8] = Array("def".utf8)
    private static let classBytes: [UInt8] = Array("class".utf8)

    static func python(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) {
        var i = startIdx
        var next: Next = .any
        var afterDot = false
        // Before the line's first token (decorators and soft keywords only count there).
        var lineStart = (depth == 0)

        while i < end && !out.full {
            let b = s[i]
            let start = i
            if b == 0x0A {
                i += 1
                lineStart = true
                continue
            }
            if b == 0x20 || b == 0x09 || b == 0x0D {
                i += 1
                continue
            }
            if b == 0x23 { // '#'
                i = lineEnd(s, i, end)
                out.push(start, i, .comment)
                continue
            }
            let first = lineStart
            lineStart = false
            let wasDot = afterDot
            afterDot = false
            let wasNext = next
            next = .any

            if let (quote, f) = pyStringStart(s, i, end) {
                i = pyString(s, i, quote, f, end, &out, depth)
            } else if isAsciiDigit(b) || (b == 0x2E && isAsciiDigit(at(s, i + 1, end))) {
                i = numberEnd(s, i, end)
                out.push(start, i, .number)
            } else if b == 0x40 && first && isIdentStart(at(s, i + 1, end)) { // '@'
                i = identEnd(s, i + 1, end, dotExtra)
                out.push(start, i, .keyword)
            } else if isIdentStart(b) {
                i = identEnd(s, i, end, [])
                var k = i
                while k < end && (s[k] == 0x20 || s[k] == 0x09) {
                    k += 1
                }
                let call = at(s, k, end) == 0x28 // '('
                let tok: Syntax?
                if wasDot {
                    tok = call ? .function : nil
                } else if isWord(s, start, i, pyConstants) {
                    tok = .number
                } else if isWord(s, start, i, pyKeywords) {
                    if i - start == 3 && starts(s, start, i, defBytes) {
                        next = .function
                    } else if i - start == 5 && starts(s, start, i, classBytes) {
                        next = .type
                    } else {
                        next = .any
                    }
                    tok = .keyword
                } else if first && isWord(s, start, i, pySoftKeywords) && softKeyword(s, i, end) {
                    tok = .keyword
                } else if wasNext == .type {
                    tok = .type
                } else if wasNext == .function {
                    tok = .function
                } else if isWord(s, start, i, pyTypes) {
                    tok = .type
                } else if isAllCaps(s, start, i) {
                    tok = .number
                } else if isAsciiUpper(s[start]) {
                    tok = .type
                } else {
                    tok = call ? .function : nil
                }
                if let t = tok {
                    out.push(start, i, t)
                }
            } else {
                i += 1
                afterDot = (b == 0x2E)
                out.push(start, i, .punctuation)
            }
        }
    }

    /// Whether a string literal starts at `i`: its quote's index, and whether it is an f-string.
    /// Up to two prefix letters (`r`, `b`, `u`, `f`, `rb`, `fr`, in either case) come before the
    /// quote.
    private static func pyStringStart(_ s: [UInt8], _ i: Int, _ end: Int) -> (Int, Bool)? {
        var f = false
        let limit = min(i + 3, end)
        var k = i
        while k < limit {
            switch s[k] {
            case 0x22, 0x27: // '"' or '\''
                return (k, f)
            case 0x66, 0x46: // 'f' or 'F'
                f = true
            case 0x72, 0x52, 0x62, 0x42, 0x75, 0x55: // r R b B u U
                break
            default:
                return nil
            }
            k += 1
        }
        return nil
    }

    /// A string from `start` (its prefix) whose quote is at `q`: single or triple quoted, an
    /// f-string's `{}` fields coloured as code.
    private static func pyString(_ s: [UInt8], _ start: Int, _ q: Int, _ f: Bool, _ end: Int, _ out: inout Out, _ depth: UInt8) -> Int {
        let qc = s[q]
        let triple = at(s, q + 1, end) == qc && at(s, q + 2, end) == qc
        let rawEnd: Int
        if triple {
            var j = q + 3
            while true {
                if j >= end {
                    rawEnd = end
                    break
                }
                if s[j] == 0x5C {
                    j += 2
                } else if s[j] == qc && at(s, j + 1, end) == qc && at(s, j + 2, end) == qc {
                    rawEnd = j + 3
                    break
                } else {
                    j += 1
                }
            }
        } else {
            rawEnd = stringEnd(s, q, end, qc, false)
        }
        let e = min(rawEnd, end)
        if !f || depth >= MAX_DEPTH {
            out.push(start, e, .string)
            return e
        }
        var seg = start
        var j = q + (triple ? 3 : 1)
        while j < e && !out.full {
            let c = s[j]
            if c == 0x5C {
                j += 2
            } else if c == 0x7B && at(s, j + 1, e) == 0x7B { // "{{"
                j += 2
            } else if c == 0x7B { // '{'
                // The field runs to its matching `}`, stepping over strings in other quotes.
                var k = j + 1
                var braces: UInt32 = 1
                while k < e {
                    let kc = s[k]
                    if kc == 0x7B {
                        braces += 1
                    } else if kc == 0x7D {
                        braces -= 1
                        if braces == 0 {
                            break
                        }
                    } else if (kc == 0x22 || kc == 0x27) && kc != qc {
                        k = stringEnd(s, k, e, kc, false)
                        continue
                    }
                    k += 1
                }
                if k >= e {
                    break
                }
                out.push(seg, j, .string)
                out.push(j, j + 1, .punctuation)
                python(s, j + 1, k, &out, depth + 1)
                out.push(k, k + 1, .punctuation)
                j = k + 1
                seg = j
            } else {
                j += 1
            }
        }
        out.push(seg, e, .string)
        return e
    }

    /// Whether the soft keyword ending at `i` starts a statement: a space follows it and the line
    /// ends with `:` (before any comment).
    private static func softKeyword(_ s: [UInt8], _ i: Int, _ end: Int) -> Bool {
        if at(s, i, end) != 0x20 {
            return false
        }
        let le = lineEnd(s, i, end)
        var codeEnd = le
        var k = i
        while k < le {
            if s[k] == 0x23 { // '#'
                codeEnd = k
                break
            }
            k += 1
        }
        while codeEnd > i && isAsciiWhitespace(s[codeEnd - 1]) {
            codeEnd -= 1
        }
        return codeEnd > i && s[codeEnd - 1] == 0x3A // ':'
    }
}
