// Ported from: crates/rune/src/clipboard/html.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Strips active content from HTML that came from another app, and packs/unpacks Windows
//! `CF_HTML` (`HTML Format`).
//!
//! A small tokenizer, not a parser: it keeps text and ordinary tags and drops anything that
//! can run code or load something. Where it can't tell, it drops more, never less. What it
//! returns is still untrusted input to parse, not markup to hand to a web view as is.

/// Cap rich clipboard payloads so a multi-megabyte pasteboard never stalls the worker.
let MAX_RICH_BYTES: Int = 4 * 1024 * 1024

/// Elements dropped with everything inside them.
private let DROP_WITH_CONTENT: Set<String> = [
    "script", "iframe", "object", "applet", "noscript", "noembed", "noframes", "template", "frameset",
    "svg", "math", "xml", "portal", "fencedframe",
]

/// Elements dropped on their own; their content (if any) is sanitised as ordinary markup.
private let DROP_TAG: Set<String> = [
    "base", "link", "meta", "embed", "frame", "param", "form",
    "title", "textarea", "xmp", "plaintext", "listing",
]

/// Attributes that hold a URL (or, for `srcset`, a list of them).
private let URL_ATTRIBUTES: Set<String> = [
    "href", "src", "xlink:href", "background", "poster", "cite", "longdesc", "lowsrc",
    "dynsrc", "data", "codebase", "ping", "srcset", "manifest", "icon", "profile", "classid", "archive",
]

private let DROP_ATTRIBUTES: Set<String> = ["srcdoc", "http-equiv", "action", "formaction"]

/// HTML from outside the app with scripts, event handlers, frames, embeds, forms, raw-text
/// elements, `javascript:` and other non-web URLs, and CSS that imports or loads anything
/// removed. Comments, doctypes and processing instructions go too. Text and ordinary
/// formatting (tags, `class`, inline `style` and `<style>` that only style) stay.
public func sanitizeHtml(_ raw: String) -> String {
    // PORT NOTE: Operates on UTF-8 `[UInt8]` slices for O(1) indexing and exact byte-level parity with Rust `&str`.
    var bytes = clampUtf8Bytes(Array(raw.utf8), MAX_RICH_BYTES)
    if bytes.contains(0) {
        bytes.removeAll { $0 == 0 }
    }
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var i = 0
    let count = bytes.count

    while let lt = findByte(bytes, 0x3C /* '<' */, from: i) {
        out.append(contentsOf: bytes[i..<lt])
        let at = { (n: Int) -> UInt8 in
            let idx = lt + n
            return idx < count ? bytes[idx] : 0
        }
        if startsWithAscii(bytes, from: lt, "<!--") {
            guard let end = commentEnd(bytes, from: lt) else {
                return String(decoding: out, as: UTF8.self)
            }
            i = lt + end
        } else if startsWithAsciiIgnoreCase(bytes, from: lt, "<![cdata[") {
            guard let end = findSubslice(bytes, [0x5D, 0x5D, 0x3E] /* "]]>" */, from: lt + 9) else {
                return String(decoding: out, as: UTF8.self)
            }
            i = end + 3
        } else if startsWithAscii(bytes, from: lt, "<!")
            || startsWithAscii(bytes, from: lt, "<?")
            || (at(1) == 0x2F /* '/' */ && !isAsciiAlpha(at(2)))
        {
            guard let end = findByte(bytes, 0x3E /* '>' */, from: lt) else {
                return String(decoding: out, as: UTF8.self)
            }
            i = end + 1
        } else if at(1) == 0x2F /* '/' */ {
            guard let tag = HtmlTag.parse(bytes, from: lt + 2) else {
                return String(decoding: out, as: UTF8.self)
            }
            i = lt + 2 + tag.len
            if !isDroppedTag(tag.name) && tag.name != "style" {
                out.append(contentsOf: [0x3C, 0x2F]) // "</"
                out.append(contentsOf: tag.name.utf8)
                out.append(0x3E) // ">"
            }
        } else if isAsciiAlpha(at(1)) {
            guard let tag = HtmlTag.parse(bytes, from: lt + 1) else {
                return String(decoding: out, as: UTF8.self)
            }
            i = lt + 1 + tag.len
            if DROP_WITH_CONTENT.contains(tag.name) || tag.name == "style" {
                guard let (innerEnd, afterClose) = untilClose(bytes, from: i, name: tag.name) else {
                    return String(decoding: out, as: UTF8.self)
                }
                if tag.name == "style" && !tag.closed {
                    let innerStr = String(decoding: bytes[i..<innerEnd], as: UTF8.self)
                    if cssIsInert(innerStr) && cssIsInert(decodeHtmlEntities(innerStr)) {
                        tag.write(into: &out)
                        out.append(contentsOf: bytes[i..<innerEnd])
                        out.append(contentsOf: "</style>".utf8)
                    }
                }
                i = afterClose
            } else if !DROP_TAG.contains(tag.name) {
                tag.write(into: &out)
            }
        } else {
            out.append(contentsOf: "&lt;".utf8)
            i = lt + 1
        }
    }
    out.append(contentsOf: bytes[i..<count])
    return String(decoding: out, as: UTF8.self)
}

private func clampUtf8Bytes(_ bytes: [UInt8], _ maxLen: Int) -> [UInt8] {
    if bytes.count <= maxLen { return bytes }
    var end = maxLen
    while end > 0 && !isUtf8CharBoundary(bytes, end) {
        end -= 1
    }
    return Array(bytes[0..<end])
}

private func isUtf8CharBoundary(_ bytes: [UInt8], _ index: Int) -> Bool {
    if index < 0 || index > bytes.count { return false }
    if index == 0 || index == bytes.count { return true }
    return (bytes[index] & 0xC0) != 0x80
}

private func isAsciiAlpha(_ b: UInt8) -> Bool {
    (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
}

private func isAsciiAlphanumeric(_ b: UInt8) -> Bool {
    isAsciiAlpha(b) || (b >= 0x30 && b <= 0x39)
}

private func isAsciiWhitespace(_ b: UInt8) -> Bool {
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D
}

private func asciiLower(_ b: UInt8) -> UInt8 {
    (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
}

private func findByte(_ bytes: [UInt8], _ needle: UInt8, from start: Int) -> Int? {
    var idx = start
    let count = bytes.count
    while idx < count {
        if bytes[idx] == needle { return idx }
        idx += 1
    }
    return nil
}

private func findSubslice(_ bytes: [UInt8], _ needle: [UInt8], from start: Int) -> Int? {
    let n = needle.count
    if n == 0 { return start }
    let limit = bytes.count - n
    if start > limit { return nil }
    var idx = start
    let first = needle[0]
    while idx <= limit {
        if bytes[idx] == first {
            var match = true
            for k in 1..<n where bytes[idx + k] != needle[k] {
                match = false
                break
            }
            if match { return idx }
        }
        idx += 1
    }
    return nil
}

private func startsWithAscii(_ bytes: [UInt8], from start: Int, _ prefix: StaticString) -> Bool {
    let n = prefix.utf8CodeUnitCount
    if start + n > bytes.count { return false }
    return prefix.withUTF8Buffer { buf in
        for k in 0..<n where bytes[start + k] != buf[k] {
            return false
        }
        return true
    }
}

private func startsWithAsciiIgnoreCase(_ bytes: [UInt8], from start: Int, _ lowerPrefix: StaticString) -> Bool {
    let n = lowerPrefix.utf8CodeUnitCount
    if start + n > bytes.count { return false }
    return lowerPrefix.withUTF8Buffer { buf in
        for k in 0..<n where asciiLower(bytes[start + k]) != buf[k] {
            return false
        }
        return true
    }
}

private func commentEnd(_ bytes: [UInt8], from lt: Int) -> Int? {
    if startsWithAscii(bytes, from: lt, "<!-->") { return 5 }
    if startsWithAscii(bytes, from: lt, "<!--->") { return 6 }
    let bodyStart = lt + 4
    if bodyStart > bytes.count { return nil }
    var j = bodyStart
    while j + 2 < bytes.count {
        if bytes[j] == 0x2D /* '-' */ && bytes[j + 1] == 0x2D /* '-' */ {
            if bytes[j + 2] == 0x3E /* '>' */ {
                return (j - lt) + 3
            }
            if bytes[j + 2] == 0x21 /* '!' */ && j + 3 < bytes.count && bytes[j + 3] == 0x3E /* '>' */ {
                return (j - lt) + 4
            }
        }
        j += 1
    }
    return nil
}

private func isDroppedTag(_ name: String) -> Bool {
    DROP_WITH_CONTENT.contains(name) || DROP_TAG.contains(name)
}

/// Returns `(innerEndIndex, indexAfterCloseTag)` in `bytes`.
private func untilClose(_ bytes: [UInt8], from start: Int, name: String) -> (Int, Int)? {
    let needle = Array(name.utf8)
    let count = bytes.count
    var i = start
    while let at = findByte(bytes, 0x3C /* '<' */, from: i) {
        let afterName = at + 2 + needle.count
        if at + 1 < count && bytes[at + 1] == 0x2F /* '/' */ && afterName <= count {
            var matches = true
            for k in 0..<needle.count where asciiLower(bytes[at + 2 + k]) != needle[k] {
                matches = false
                break
            }
            if matches {
                let boundary: UInt8 = afterName < count ? bytes[afterName] : 0x3E /* '>' */
                if !isAsciiAlphanumeric(boundary) && boundary != 0x2D && boundary != 0x3A && boundary != 0x5F {
                    guard let end = findByte(bytes, 0x3E /* '>' */, from: afterName) else {
                        return nil
                    }
                    return (at, end + 1)
                }
            }
        }
        i = at + 1
    }
    return nil
}

private struct HtmlTag {
    var name: String
    var attributes: [(String, String?)]
    var closed: Bool
    var len: Int

    static func parse(_ bytes: [UInt8], from base: Int) -> HtmlTag? {
        let count = bytes.count
        var p = base
        while p < count {
            let c = bytes[p]
            if isAsciiAlphanumeric(c) || c == 0x2D || c == 0x3A || c == 0x5F {
                p += 1
            } else {
                break
            }
        }
        let name = String(decoding: bytes[base..<p].map(asciiLower), as: UTF8.self)
        var i = p
        var attributes: [(String, String?)] = []
        var closed = false

        while true {
            while i < count && (isAsciiWhitespace(bytes[i]) || bytes[i] == 0x2F /* '/' */) {
                closed = bytes[i] == 0x2F
                i += 1
            }
            guard i < count else { return nil }
            if bytes[i] == 0x3E /* '>' */ {
                return HtmlTag(name: name, attributes: attributes, closed: closed, len: (i + 1) - base)
            }
            closed = false

            let attrStart = i
            while i < count && !isAsciiWhitespace(bytes[i])
                && bytes[i] != 0x2F && bytes[i] != 0x3E && bytes[i] != 0x3D /* '=' */
            {
                i += 1
            }
            if i == attrStart { i += 1 } // A stray `=`.
            let attr = String(decoding: bytes[attrStart..<i].map(asciiLower), as: UTF8.self)
            while i < count && isAsciiWhitespace(bytes[i]) { i += 1 }
            var value: String? = nil
            if i < count && bytes[i] == 0x3D /* '=' */ {
                i += 1
                while i < count && isAsciiWhitespace(bytes[i]) { i += 1 }
                if i < count && (bytes[i] == 0x22 /* '"' */ || bytes[i] == 0x27 /* '\'' */) {
                    let q = bytes[i]
                    guard let end = findByte(bytes, q, from: i + 1) else { return nil }
                    value = String(decoding: bytes[(i + 1)..<end], as: UTF8.self)
                    i = end + 1
                } else {
                    let valStart = i
                    while i < count && !isAsciiWhitespace(bytes[i]) && bytes[i] != 0x3E /* '>' */ {
                        i += 1
                    }
                    value = String(decoding: bytes[valStart..<i], as: UTF8.self)
                }
            }
            if keepAttribute(attr, value) {
                attributes.append((attr, value))
            }
        }
    }

    func write(into out: inout [UInt8]) {
        out.append(0x3C) // '<'
        out.append(contentsOf: name.utf8)
        for (attrName, attrVal) in attributes {
            out.append(0x20) // ' '
            out.append(contentsOf: attrName.utf8)
            if let attrVal {
                out.append(contentsOf: [0x3D, 0x22]) // '="'
                for b in attrVal.utf8 {
                    switch b {
                    case 0x22: out.append(contentsOf: "&quot;".utf8)
                    case 0x3C: out.append(contentsOf: "&lt;".utf8)
                    case 0x3E: out.append(contentsOf: "&gt;".utf8)
                    default: out.append(b)
                    }
                }
                out.append(0x22) // '"'
            }
        }
        if closed {
            out.append(contentsOf: [0x20, 0x2F]) // " /"
        }
        out.append(0x3E) // '>'
    }
}

private func keepAttribute(_ name: String, _ value: String?) -> Bool {
    if name.isEmpty { return false }
    for c in name.utf8 {
        if !(isAsciiAlphanumeric(c) || c == 0x2D || c == 0x3A || c == 0x5F || c == 0x2E) {
            return false
        }
    }
    if name.hasPrefix("on") || DROP_ATTRIBUTES.contains(name) { return false }
    let val = value ?? ""
    if name == "style" { return cssIsInert(val) && cssIsInert(decodeHtmlEntities(val)) }
    if name == "srcset" { return srcsetIsSafe(val) }
    if URL_ATTRIBUTES.contains(name) { return urlIsSafe(val, image: name == "src") }
    return true
}

private func isUnicodeWhitespace(_ s: UnicodeScalar) -> Bool {
    s.properties.isWhitespace
}

private func isUnicodeControl(_ s: UnicodeScalar) -> Bool {
    s.value <= 0x1F || (s.value >= 0x7F && s.value <= 0x9F)
}

private func srcsetIsSafe(_ raw: String) -> Bool {
    let decodedBytes = Array(decodeHtmlEntities(raw).utf8)
    var start = 0
    var end = decodedBytes.count
    while start < end && isAsciiWhitespace(decodedBytes[start]) { start += 1 }
    while end > start && isAsciiWhitespace(decodedBytes[end - 1]) { end -= 1 }
    if start >= end { return false }

    var i = start
    while i < end {
        while i < end && (isAsciiWhitespace(decodedBytes[i]) || decodedBytes[i] == 0x2C /* ',' */) {
            i += 1
        }
        if i >= end { break }
        let urlEnd: Int
        if i + 5 <= end && startsWithAsciiIgnoreCase(decodedBytes, from: i, "data:") {
            var commaPos: Int? = nil
            var k = i
            while k < end {
                if decodedBytes[k] == 0x2C { commaPos = k; break }
                k += 1
            }
            let afterComma = commaPos.map { $0 + 1 } ?? i
            var p = afterComma
            while p < end && !isAsciiWhitespace(decodedBytes[p]) && decodedBytes[p] != 0x2C {
                p += 1
            }
            urlEnd = p
        } else {
            var p = i
            while p < end && !isAsciiWhitespace(decodedBytes[p]) && decodedBytes[p] != 0x2C {
                p += 1
            }
            urlEnd = p
        }
        let candidate = String(decoding: decodedBytes[i..<urlEnd], as: UTF8.self)
        if !urlIsSafe(candidate, image: true) { return false }
        i = urlEnd
        if let comma = findByte(decodedBytes, 0x2C, from: i), comma < end {
            i = comma + 1
        } else {
            break
        }
    }
    return true
}

private func cssIsInert(_ css: String) -> Bool {
    let bytes = Array(css.utf8)
    var stripped: [UInt8] = []
    stripped.reserveCapacity(bytes.count)
    var i = 0
    while let start = findSubslice(bytes, [0x2F, 0x2A], from: i) {
        stripped.append(contentsOf: bytes[i..<start])
        guard let end = findSubslice(bytes, [0x2A, 0x2F], from: start + 2) else {
            return false
        }
        i = end + 2
    }
    stripped.append(contentsOf: bytes[i..<bytes.count])
    let strippedStr = String(decoding: stripped, as: UTF8.self)
    return cssTokensClean(css) && cssTokensClean(strippedStr)
}

private func cssTokensClean(_ css: String) -> Bool {
    var plain = ""
    plain.reserveCapacity(css.utf8.count)
    for scalar in css.unicodeScalars {
        if !isUnicodeWhitespace(scalar) && !isUnicodeControl(scalar) {
            if scalar.value >= 0x41 && scalar.value <= 0x5A {
                plain.unicodeScalars.append(UnicodeScalar(scalar.value + 32)!)
            } else {
                plain.unicodeScalars.append(scalar)
            }
        }
    }
    let badTokens = [
        "expression(", "javascript:", "vbscript:", "data:", "@import", "url(",
        "image-set(", "behavior:", "-moz-binding", "</", "\\", "<",
    ]
    for bad in badTokens where plain.contains(bad) {
        return false
    }
    return true
}

private func urlIsSafe(_ raw: String, image: Bool) -> Bool {
    let decoded = decodeHtmlEntities(raw)
    var urlBytes: [UInt8] = []
    urlBytes.reserveCapacity(decoded.utf8.count)
    for scalar in decoded.unicodeScalars {
        if !isUnicodeControl(scalar) && !isUnicodeWhitespace(scalar) {
            for b in String(scalar).utf8 {
                urlBytes.append(asciiLower(b))
            }
        }
    }
    let url = String(decoding: urlBytes, as: UTF8.self)
    guard let colonIdx = findByte(urlBytes, 0x3A /* ':' */, from: 0) else {
        return !url.hasPrefix("//") && !url.hasPrefix("\\\\") && !urlBytes.contains(0x26 /* '&' */)
    }
    let beforeColon = urlBytes[0..<colonIdx]
    if beforeColon.contains(0x2F) || beforeColon.contains(0x3F) || beforeColon.contains(0x23) || beforeColon.contains(0x26) {
        return !url.hasPrefix("//") && !url.hasPrefix("\\\\") && !beforeColon.contains(0x26)
    }
    let scheme = String(decoding: beforeColon, as: UTF8.self)
    switch scheme {
    case "http", "https", "mailto", "tel", "cid":
        return true
    case "data":
        guard image else { return false }
        for kind in ["png", "jpeg", "jpg", "gif", "webp"] {
            let prefix = "data:image/\(kind)"
            if url.hasPrefix(prefix), urlBytes.count > prefix.utf8.count {
                let next = urlBytes[prefix.utf8.count]
                if next == 0x3B /* ';' */ || next == 0x2C /* ',' */ {
                    return true
                }
            }
        }
        return false
    default:
        return false
    }
}

private func isHexDigit(_ b: UInt8) -> Bool {
    (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
}

private func decodeHtmlEntities(_ s: String) -> String {
    let bytes = Array(s.utf8)
    guard bytes.contains(0x26 /* '&' */) else { return s }
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    var i = 0
    let count = bytes.count

    while let amp = findByte(bytes, 0x26 /* '&' */, from: i) {
        out.append(contentsOf: bytes[i..<amp])
        var bodyLen = 0
        while amp + 1 + bodyLen < count {
            let c = bytes[amp + 1 + bodyLen]
            if isAsciiAlphanumeric(c) || c == 0x23 /* '#' */ {
                bodyLen += 1
            } else {
                break
            }
        }
        let bodyStart = amp + 1
        let bodyEnd = bodyStart + bodyLen
        var decoded: (UnicodeScalar, Int)? = nil

        if bodyLen > 0 && bytes[bodyStart] == 0x23 /* '#' */ {
            let numStart = bodyStart + 1
            let isHex = numStart < bodyEnd && (bytes[numStart] == 0x78 /* 'x' */ || bytes[numStart] == 0x58 /* 'X' */)
            let rawStart = isHex ? (numStart + 1) : numStart
            let radix = isHex ? 16 : 10
            let prefixLen = isHex ? 2 : 1
            var digitLen = 0
            while rawStart + digitLen < bodyEnd {
                let c = bytes[rawStart + digitLen]
                let ok = isHex ? isHexDigit(c) : (c >= 0x30 && c <= 0x39)
                if ok { digitLen += 1 } else { break }
            }
            if digitLen > 0 {
                var nzStart = rawStart
                let digitsEnd = rawStart + digitLen
                while nzStart < digitsEnd && bytes[nzStart] == 0x30 /* '0' */ {
                    nzStart += 1
                }
                let n: UInt32?
                if nzStart == digitsEnd {
                    n = 0
                } else {
                    let trimmed = String(decoding: bytes[nzStart..<digitsEnd], as: UTF8.self)
                    n = UInt32(trimmed, radix: radix)
                }
                let scalar: UnicodeScalar
                if let val = n, val != 0, let s = UnicodeScalar(val) {
                    scalar = s
                } else {
                    scalar = UnicodeScalar(0xFFFD)!
                }
                decoded = (scalar, prefixLen + digitLen)
            }
        } else if bodyLen > 0 {
            let lower = String(decoding: bytes[bodyStart..<bodyEnd].map(asciiLower), as: UTF8.self)
            let named: UnicodeScalar? = switch lower {
            case "colon": ":"
            case "tab": "\t"
            case "newline": "\n"
            case "lpar": "("
            case "rpar": ")"
            case "sol": "/"
            case "bsol": "\\"
            case "amp": "&"
            case "lt", "nvlt": "<"
            case "gt", "nvgt": ">"
            case "quot": "\""
            case "apos": "'"
            case "nbsp": " "
            case "num": "#"
            case "period": "."
            case "commat": "@"
            case "semi": ";"
            case "equals": "="
            case "grave": "`"
            case "plus": "+"
            case "comma": ","
            case "dollar": "$"
            default: nil
            }
            if let ch = named {
                decoded = (ch, bodyLen)
            }
        }

        if let (scalar, used) = decoded {
            for b in String(scalar).utf8 {
                out.append(b)
            }
            i = amp + 1 + used
            if i < count && bytes[i] == 0x3B /* ';' */ {
                i += 1
            }
        } else {
            out.append(0x26)
            i = amp + 1
        }
    }
    out.append(contentsOf: bytes[i..<count])
    return String(decoding: out, as: UTF8.self)
}

/// Packs an HTML fragment into a Windows `CF_HTML` (`HTML Format`) payload whose header
/// offsets (`StartHTML`, `EndHTML`, `StartFragment`, `EndFragment`) are UTF-8 byte offsets
/// from the start of the payload, including the header.
func packCfHtml(_ fragment: String) -> String {
    let prefix = "<html>\r\n<body>\r\n<!--StartFragment-->"
    let suffix = "<!--EndFragment-->\r\n</body>\r\n</html>"
    let startHtml = 105
    let startFrag = startHtml + prefix.utf8.count
    let endFrag = startFrag + fragment.utf8.count
    let endHtml = endFrag + suffix.utf8.count
    func pad10(_ n: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, 10 - s.count)) + s
    }
    return "Version:0.9\r\nStartHTML:\(pad10(startHtml))\r\nEndHTML:\(pad10(endHtml))\r\nStartFragment:\(pad10(startFrag))\r\nEndFragment:\(pad10(endFrag))\r\n\(prefix)\(fragment)\(suffix)"
}

/// Extracts the HTML fragment (or document) from a Windows `CF_HTML` (`HTML Format`) buffer.
func unpackCfHtml(_ raw: [UInt8]) -> String? {
    let nulPos = raw.firstIndex(of: 0) ?? raw.count
    let len = min(nulPos, MAX_RICH_BYTES)
    if len == 0 { return nil }
    let sliceBytes = Array(raw[0..<len])
    guard let text = String(bytes: sliceBytes, encoding: .utf8) else { return nil }
    let textBytes = Array(text.utf8)

    var startHtml: Int? = nil
    var endHtml: Int? = nil
    var startFrag: Int? = nil
    var endFrag: Int? = nil
    var headerEnd = 0
    var sawHeader = false

    var pos = 0
    while pos < textBytes.count {
        let lineEnd: Int
        if let nl = findByte(textBytes, 0x0A /* '\n' */, from: pos) {
            lineEnd = nl + 1
        } else {
            lineEnd = textBytes.count
        }
        var trimEnd = lineEnd
        while trimEnd > pos && (textBytes[trimEnd - 1] == 0x0A || textBytes[trimEnd - 1] == 0x0D) {
            trimEnd -= 1
        }
        if trimEnd > pos && textBytes[pos] == 0x3C /* '<' */ {
            break
        }
        guard let colon = findByte(textBytes, 0x3A /* ':' */, from: pos), colon < trimEnd else {
            break
        }
        sawHeader = true
        headerEnd = lineEnd
        let key = String(decoding: textBytes[pos..<colon], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let valStr = String(decoding: textBytes[(colon + 1)..<trimEnd], as: UTF8.self).trimmingCharacters(in: .whitespaces)
        let offset: Int?
        if let parsed = Int64(valStr), parsed >= 0, let idx = Int(exactly: parsed) {
            offset = idx
        } else {
            offset = nil
        }
        switch key {
        case "StartHTML": startHtml = offset
        case "EndHTML": endHtml = offset
        case "StartFragment": startFrag = offset
        case "EndFragment": endFrag = offset
        default: break
        }
        pos = lineEnd
    }

    let validSlice = { (s: Int, e: Int) -> String? in
        guard s >= headerEnd, s <= e, e <= textBytes.count,
              isUtf8CharBoundary(textBytes, s), isUtf8CharBoundary(textBytes, e) else {
            return nil
        }
        return String(decoding: textBytes[s..<e], as: UTF8.self)
    }

    if let s = startFrag, let e = endFrag, let frag = validSlice(s, e), !frag.isEmpty {
        return frag
    }
    let startMark = Array("<!--StartFragment-->".utf8)
    let endMark = Array("<!--EndFragment-->".utf8)
    if let sIdx = findSubslice(textBytes, startMark, from: 0) {
        let fragStart = sIdx + startMark.count
        if let eIdx = findSubslice(textBytes, endMark, from: fragStart) {
            return String(decoding: textBytes[fragStart..<eIdx], as: UTF8.self)
        }
    }
    if let s = startHtml, let e = endHtml, let doc = validSlice(s, e), !doc.isEmpty {
        return doc
    }
    let bodyStart = sawHeader ? headerEnd : 0
    let body = String(decoding: textBytes[bodyStart..<textBytes.count], as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return body.isEmpty ? nil : body
}
