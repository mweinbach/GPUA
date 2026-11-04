// Ported from: crates/rune-kit/src/syntax/scan/sql.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! SQL.

extension syntaxScan {
    private static let sqlKeywords: [String] = [
        "add", "all", "alter", "analyze", "and", "any", "as", "asc", "begin", "between", "by", "cascade", "case", "check",
        "column", "commit", "conflict", "constraint", "create", "cross", "database", "declare", "default", "delete", "desc",
        "distinct", "do", "drop", "else", "end", "except", "exists", "explain", "fetch", "filter", "first", "for", "foreign",
        "from", "full", "function", "grant", "group", "having", "if", "ilike", "in", "index", "inner", "insert", "intersect",
        "into", "is", "join", "key", "language", "lateral", "left", "like", "limit", "materialized", "next", "not", "nothing",
        "offset", "on", "only", "or", "order", "outer", "over", "partition", "primary", "procedure", "recursive",
        "references", "rename", "replace", "return", "returning", "returns", "revoke", "right", "rollback", "rows", "schema",
        "select", "set", "some", "table", "temp", "temporary", "then", "to", "transaction", "trigger", "truncate", "union",
        "unique", "update", "using", "vacuum", "values", "view", "when", "where", "window", "with",
    ]
    private static let sqlTypes: [String] = [
        "bigint", "bigserial", "blob", "bool", "boolean", "bytea", "char", "character", "date", "decimal", "double", "float",
        "int", "integer", "interval", "json", "jsonb", "money", "numeric", "precision", "real", "serial", "smallint", "text",
        "time", "timestamp", "timestamptz", "tinyint", "uuid", "varchar",
    ]
    private static let sqlConstants: [String] = ["true", "false", "null"]

    static func sql(_ s: [UInt8], _ startIdx: Int, _ end: Int, _ out: inout Out) {
        var i = startIdx
        while i < end && !out.full {
            let b = s[i]
            let start = i
            if isAsciiWhitespace(b) {
                i += 1
            } else if b == 0x2D && at(s, i + 1, end) == 0x2D { // "--"
                i = lineEnd(s, i, end)
                out.push(start, i, .comment)
            } else if b == 0x2F && at(s, i + 1, end) == 0x2A { // "/*"
                i = blockCommentEnd(s, i + 2, end, false)
                out.push(start, i, .comment)
            } else if b == 0x27 { // '\''
                // '' inside a string is a quote.
                i += 1
                while i < end {
                    if s[i] == 0x27 {
                        if at(s, i + 1, end) == 0x27 {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                out.push(start, min(i, end), .string)
            } else if b == 0x22 || b == 0x60 { // '"' or '`'
                i = stringEnd(s, i, end, b, true)
                out.push(start, i, .property)
            } else if isAsciiDigit(b) {
                i = numberEnd(s, i, end)
                out.push(start, i, .number)
            } else if (b == 0x24 || b == 0x3A || b == 0x40) && isIdent(at(s, i + 1, end)) {
                i = identEnd(s, i + 1, end, [])
                out.push(start, i, .property)
            } else if b == 0x3F { // '?'
                i += 1
                out.push(start, i, .property)
            } else if isIdentStart(b) {
                i = identEnd(s, i, end, [])
                var k = i
                while k < end && (s[k] == 0x20 || s[k] == 0x09) {
                    k += 1
                }
                if isWordCI(s, start, i, sqlConstants) {
                    out.push(start, i, .number)
                } else if isWordCI(s, start, i, sqlKeywords) {
                    out.push(start, i, .keyword)
                } else if isWordCI(s, start, i, sqlTypes) {
                    out.push(start, i, .type)
                } else if at(s, k, end) == 0x28 { // '('
                    out.push(start, i, .function)
                }
            } else {
                i += 1
                out.push(start, i, .punctuation)
            }
        }
    }
}
