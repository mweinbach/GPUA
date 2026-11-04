// Ported from: crates/rune-kit/src/syntax/scan/yaml.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! YAML.

extension syntaxScan {
    private static let yamlDocStart: [UInt8] = [0x2D, 0x2D, 0x2D] // "---"
    private static let yamlDocEnd: [UInt8] = [0x2E, 0x2E, 0x2E] // "..."
    private static let yamlConstants: [String] = [
        "true", "false", "null", "~", "yes", "no", "on", "off", ".inf", "-.inf", ".nan",
    ]

    static func yaml(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out) {
        var i = startIdx
        // A block scalar (`|` or `>`) runs over the lines indented past this column.
        var block: Int? = nil
        while i < end && !out.full {
            let le = lineEnd(s, i, end)
            var indent = 0
            while i + indent < le && s[i + indent] == 0x20 {
                indent += 1
            }
            let content = i + indent
            var blank = true
            for k in content..<le where !isAsciiWhitespace(s[k]) {
                blank = false
                break
            }
            if let col = block {
                if blank || indent > col {
                    out.push(content, le, .string)
                    i = le + 1
                    continue
                }
                block = nil
            }
            if !blank {
                yamlLine(s, i, content, le, &out, &block)
            }
            i = le + 1
        }
    }

    private static func yamlLine(
        _ s: [UInt8],
        _ line: Int,
        _ startContent: Int,
        _ le: Int,
        _ out: inout Out,
        _ block: inout Int?
    ) {
        var j = startContent
        let content = j

        @inline(__always)
        func sep(_ k: Int) -> Bool {
            k >= le || s[k] == 0x20 || s[k] == 0x09 || s[k] == 0x0D
        }

        if j == line && (starts(s, j, le, yamlDocStart) || starts(s, j, le, yamlDocEnd)) && sep(j + 3) {
            out.push(j, j + 3, .punctuation)
            j += 3
        }
        var parent = j - line
        while j < le && s[j] == 0x2D && sep(j + 1) { // '-'
            out.push(j, j + 1, .punctuation)
            parent = j - line
            j += 1
            while j < le && s[j] == 0x20 {
                j += 1
            }
        }
        if j < le && s[j] != 0x23, let (keyEnd, colon) = yamlKey(s, j, le) {
            out.push(j, keyEnd, .property)
            out.push(colon, colon + 1, .punctuation)
            parent = j - line
            j = colon + 1
        }
        var flow = 0
        while j < le && !out.full {
            let b = s[j]
            let start = j
            switch b {
            case 0x20, 0x09, 0x0D:
                j += 1
            case 0x23 where j == content || s[j - 1] == 0x20 || s[j - 1] == 0x09:
                out.push(j, le, .comment)
                return
            case 0x26, 0x2A, 0x21: // '&' '*' '!'
                while j < le && !(s[j] == 0x20 || s[j] == 0x09 || s[j] == 0x0D || s[j] == 0x2C || s[j] == 0x5D || s[j] == 0x7D) {
                    j += 1
                }
                out.push(start, j, .type)
            case 0x22, 0x27:
                j = stringEnd(s, j, le, b, false)
                out.push(start, j, .string)
            case 0x7C where flow == 0, 0x3E where flow == 0: // '|' or '>'
                j += 1
                while j < le && (s[j] == 0x2B || s[j] == 0x2D || isAsciiDigit(s[j])) {
                    j += 1
                }
                out.push(start, j, .punctuation)
                var k = j
                while k < le && (s[k] == 0x20 || s[k] == 0x09 || s[k] == 0x0D) {
                    k += 1
                }
                if k >= le || s[k] == 0x23 {
                    block = parent
                }
            case 0x5B, 0x7B: // '[' '{'
                flow += 1
                j += 1
                out.push(start, j, .punctuation)
            case 0x5D where flow > 0, 0x7D where flow > 0, 0x2C where flow > 0, 0x3A:
                if b == 0x5D || b == 0x7D {
                    flow = max(flow - 1, 0)
                }
                j += 1
                out.push(start, j, .punctuation)
            default:
                // A plain scalar: to a ` #` comment or the line end, or a flow separator.
                var e = j
                while e < le
                    && !((s[e] == 0x20 || s[e] == 0x09) && at(s, e + 1, le) == 0x23)
                    && !(flow > 0 && (s[e] == 0x2C || s[e] == 0x5D || s[e] == 0x7D || s[e] == 0x3A))
                {
                    e += 1
                }
                var t = e
                while t > j && (s[t - 1] == 0x20 || s[t - 1] == 0x09 || s[t - 1] == 0x0D) {
                    t -= 1
                }
                let kind: Syntax = (flow > 0 && at(s, e, le) == 0x3A) ? .property : scalarKind(s, j, t)
                out.push(j, t, kind)
                j = max(e, j + 1)
            }
        }
    }

    /// A mapping key at `j`: (its end, its colon), when a `:` followed by a space or the line end
    /// comes before any comment.
    private static func yamlKey(_ s: [UInt8], _ j: Int, _ le: Int) -> (Int, Int)? {
        @inline(__always)
        func colon(_ k: Int) -> Bool {
            at(s, k, le) == 0x3A && (k + 1 >= le || s[k + 1] == 0x20 || s[k + 1] == 0x09 || s[k + 1] == 0x0D)
        }

        if s[j] == 0x22 || s[j] == 0x27 {
            let e = stringEnd(s, j, le, s[j], false)
            var k = e
            while k < le && s[k] == 0x20 {
                k += 1
            }
            return colon(k) ? (e, k) : nil
        }
        switch s[j] {
        case 0x5B, 0x7B, 0x26, 0x2A, 0x21, 0x7C, 0x3E, 0x25, 0x40, 0x60, 0x3F:
            // '[' '{' '&' '*' '!' '|' '>' '%' '@' '`' '?'
            return nil
        default:
            break
        }
        var k = j
        while k < le {
            if colon(k) {
                var e = k
                while e > j && s[e - 1] == 0x20 {
                    e -= 1
                }
                return (e, k)
            }
            if s[k] == 0x23 && k > j && (s[k - 1] == 0x20 || s[k - 1] == 0x09) {
                return nil
            }
            k += 1
        }
        return nil
    }

    private static func scalarKind(_ s: [UInt8], _ a: Int, _ b: Int) -> Syntax {
        if isWordCI(s, a, b, yamlConstants) {
            return .number
        }
        var ds = a
        if ds < b && (s[ds] == 0x2D || s[ds] == 0x2B) {
            ds += 1
        }
        guard ds < b, isAsciiDigit(s[ds]) else {
            return .string
        }
        let isHexOrOct = (b - ds >= 2 && s[ds] == 0x30 && (s[ds + 1] == 0x78 || s[ds + 1] == 0x6F))
        if isHexOrOct {
            return .number
        }
        for k in ds..<b {
            let c = s[k]
            if !(isAsciiDigit(c) || c == 0x2E || c == 0x5F || c == 0x65 || c == 0x45 || c == 0x2B || c == 0x2D) {
                return .string
            }
        }
        return .number
    }
}
