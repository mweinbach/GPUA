// Ported from: crates/rune-kit/src/syntax/scan/shell.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Shell.

extension syntaxScan {
    private static let shellKeywords: [String] = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function", "select",
        "time", "return", "exit", "export", "local", "readonly", "declare", "unset", "shift", "break", "continue",
    ]
    /// Words after which the next word is a command too.
    private static let shellLeads: [String] = [
        "if", "then", "else", "elif", "do", "while", "until", "time", "function", "!",
    ]
    private static let shellWrappers: [String] = [
        "sudo", "exec", "nohup", "xargs", "env", "command", "builtin",
    ]
    private static let shellDashExtra: [UInt8] = [0x2D] // "-"
    private static let shellSpecialParams: [UInt8] = Array("?@#*$!-0123456789".utf8)

    static func shell(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) {
        var i = startIdx
        var command = true
        // A heredoc's delimiter (its byte range) and whether `<<-` strips leading tabs.
        var heredoc: (Int, Int, Bool)? = nil

        while i < end && !out.full {
            let b = s[i]
            let start = i
            switch b {
            case 0x0A: // '\n'
                i += 1
                command = true
                if let (a, z, dash) = heredoc {
                    heredoc = nil
                    i = heredocBody(s, i, end, a, z, dash, &out)
                }
            case 0x20, 0x09, 0x0D:
                i += 1
            case 0x23: // '#'
                i = lineEnd(s, i, end)
                out.push(start, i, .comment)
            case 0x27: // '\''
                var p = i + 1
                var found: Int? = nil
                while p < end {
                    if s[p] == 0x27 {
                        found = p + 1
                        break
                    }
                    p += 1
                }
                i = found ?? end
                out.push(start, i, .string)
                command = false
            case 0x22: // '"'
                i = shellString(s, i, end, &out, depth)
                command = false
            case 0x24: // '$'
                i = dollar(s, i, end, &out, depth)
                command = false
            case 0x60: // '`'
                var p = i + 1
                var close = end
                while p < end {
                    if s[p] == 0x60 {
                        close = p
                        break
                    }
                    p += 1
                }
                out.push(i, i + 1, .punctuation)
                if depth < MAX_DEPTH {
                    shell(s, i + 1, close, &out, depth + 1)
                }
                let nextIdx = min(close + 1, end)
                out.push(close, nextIdx, .punctuation)
                i = nextIdx
                command = false
            case 0x5C: // '\\'
                // A line continuation keeps whether the next word is a command (after `&&`).
                let crlf = at(s, i + 1, end) == 0x0D && at(s, i + 2, end) == 0x0A
                let continues = crlf || at(s, i + 1, end) == 0x0A
                let step = crlf ? 3 : (1 + utf8Len(at(s, i + 1, end)))
                i = min(i + step, end)
                command = command && continues
            case 0x3C where at(s, i + 1, end) == 0x3C && at(s, i + 2, end) != 0x3C: // "<<"
                i += 2
                let dash = at(s, i, end) == 0x2D
                if dash {
                    i += 1
                }
                out.push(start, i, .punctuation)
                while at(s, i, end) == 0x20 || at(s, i, end) == 0x09 {
                    i += 1
                }
                let q = at(s, i, end)
                let quoted = (q == 0x27 || q == 0x22)
                let name = i + (quoted ? 1 : 0)
                let nameEnd = identEnd(s, name, end, shellDashExtra)
                if nameEnd > name {
                    let closingQuote = (quoted && at(s, nameEnd, end) == q) ? 1 : 0
                    i = nameEnd + closingQuote
                    out.push(start + 2 + (dash ? 1 : 0), i, .string)
                    heredoc = (name, nameEnd, dash)
                }
                command = false
            case 0x7C, 0x26, 0x3B, 0x28, 0x29, 0x7B, 0x7D, 0x3C, 0x3E:
                // '|' '&' ';' '(' ')' '{' '}' '<' '>'
                i += 1
                out.push(start, i, .punctuation)
                command = !(b == 0x29 || b == 0x3C || b == 0x3E)
            default:
                while i < end && !isShellWordStop(s[i]) {
                    i += 1
                }
                let len = i - start
                var eq: Int? = nil
                for k in start..<i {
                    if s[k] == 0x3D { // '='
                        eq = k - start
                        break
                    }
                }
                if (len == 1 && s[start] == 0x5B) || (len == 2 && s[start] == 0x5B && s[start + 1] == 0x5B) {
                    out.push(start, i, .punctuation)
                    command = false
                } else if (len == 1 && s[start] == 0x5D) || (len == 2 && s[start] == 0x5D && s[start + 1] == 0x5D) {
                    out.push(start, i, .punctuation)
                } else if command, let eqOffset = eq, eqOffset > 0, isValidEnvName(s, start, start + eqOffset) {
                    // FOO=bar before a command.
                    out.push(start, start + eqOffset, .property)
                    out.push(start + eqOffset, start + eqOffset + 1, .punctuation)
                } else if command {
                    if isWord(s, start, i, shellKeywords) {
                        out.push(start, i, .keyword)
                        command = isWord(s, start, i, shellLeads)
                    } else {
                        out.push(start, i, .function)
                        command = isWord(s, start, i, shellWrappers)
                    }
                } else if len == 2 && s[start] == 0x69 && s[start + 1] == 0x6E { // "in"
                    out.push(start, i, .keyword)
                } else if len > 0 && isAllDigits(s, start, i) {
                    out.push(start, i, .number)
                }
                if len == 0 {
                    i += 1
                }
            }
        }
    }

    @inline(__always)
    private static func isShellWordStop(_ b: UInt8) -> Bool {
        // ' ' '\t' '\r' '\n' '|' '&' ';' '(' ')' '<' '>' '\'' '"' '$' '`' '\\'
        switch b {
        case 0x20, 0x09, 0x0D, 0x0A, 0x7C, 0x26, 0x3B, 0x28, 0x29, 0x3C, 0x3E, 0x27, 0x22, 0x24, 0x60, 0x5C:
            return true
        default:
            return false
        }
    }

    private static func isValidEnvName(_ s: [UInt8], _ a: Int, _ b: Int) -> Bool {
        for k in a..<b {
            if !(isAsciiAlnum(s[k]) || s[k] == 0x5F) {
                return false
            }
        }
        return true
    }

    private static func isAllDigits(_ s: [UInt8], _ a: Int, _ b: Int) -> Bool {
        for k in a..<b where !isAsciiDigit(s[k]) {
            return false
        }
        return true
    }

    /// A double-quoted shell string from `i`, its `$` expansions coloured as variables.
    private static func shellString(_ s: [UInt8], _ i: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) -> Int {
        var seg = i
        var j = i + 1
        while j < end && !out.full {
            let c = s[j]
            if c == 0x5C {
                j += 2
            } else if c == 0x22 {
                out.push(seg, j + 1, .string)
                return j + 1
            } else if c == 0x24 && (at(s, j + 1, end) == 0x7B || at(s, j + 1, end) == 0x28 || isIdentStart(at(s, j + 1, end))) {
                out.push(seg, j, .string)
                j = dollar(s, j, end, &out, depth)
                seg = j
            } else {
                j += 1
            }
        }
        let clamped = min(j, end)
        out.push(seg, clamped, .string)
        return clamped
    }

    /// A `$` expansion from `i`: `$name`, `${…}`, `$1`, `$?`, or a `$(…)` command substitution.
    private static func dollar(_ s: [UInt8], _ i: Int, _ end: Int, _ out: inout Out, _ depth: UInt8) -> Int {
        let c = at(s, i + 1, end)
        if c == 0x7B { // '{'
            var p = i
            var e = end
            while p < end {
                if s[p] == 0x7D || s[p] == 0x0A {
                    e = p + (s[p] == 0x7D ? 1 : 0)
                    break
                }
                p += 1
            }
            out.push(i, e, .property)
            return e
        } else if c == 0x28 { // '('
            let close = matching(s, i + 1, end, 0x28, 0x29, .shell)
            out.push(i, i + 2, .punctuation)
            if depth < MAX_DEPTH {
                shell(s, i + 2, close, &out, depth + 1)
            }
            if close >= end {
                return end
            }
            out.push(close, close + 1, .punctuation)
            return close + 1
        } else if isAsciiAlpha(c) || c == 0x5F {
            var e = i + 1
            while e < end && (isAsciiAlnum(s[e]) || s[e] == 0x5F) {
                e += 1
            }
            out.push(i, e, .property)
            return e
        } else if c != 0 && shellSpecialParams.contains(c) {
            out.push(i, i + 2, .property)
            return i + 2
        } else {
            return i + 1
        }
    }

    /// A heredoc's lines from `i` up to and including the line that is just `delim`.
    private static func heredocBody(
        _ s: [UInt8],
        _ i: Int,
        _ end: Int,
        _ delimStart: Int,
        _ delimEnd: Int,
        _ dash: Bool,
        _ out: inout Out
    ) -> Int {
        let delimLen = delimEnd - delimStart
        var j = i
        while j < end {
            let le = lineEnd(s, j, end)
            var ls = j
            if dash {
                while ls < le && s[ls] == 0x09 {
                    ls += 1
                }
            }
            let trimEnd = (le > ls && s[le - 1] == 0x0D) ? (le - 1) : le
            if trimEnd - ls == delimLen {
                var same = true
                for k in 0..<delimLen where s[ls + k] != s[delimStart + k] {
                    same = false
                    break
                }
                if same {
                    out.push(i, le, .string)
                    return le
                }
            }
            j = le + 1
        }
        out.push(i, end, .string)
        return end
    }
}
