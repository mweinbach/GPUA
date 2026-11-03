// Ported from: crates/rune/src/edit/html.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Safe HTML subset import and export for `TextEdit`.
//!
//! Supported elements:
//! - Inline: `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, `<ins>`, `<s>`, `<del>`, `<strike>`,
//!   `<a href="...">`, `<code>`, CSS `style` attributes (`font-weight`, `font-style`,
//!   `text-decoration`, `text-decoration-line`), and `<span data-pill="id">` for `Mark.pill`.
//! - Block: `<p>`, `<div>`, `<br>`, `<ul>`, `<ol>`, `<li>`, `<blockquote>`, `<pre>`.
//! - Stripped with content: `<script>`, `<style>`, `<head>`.
//! - Unknown tags drop their wrapper and keep their text. Dangerous link schemes
//!   (`javascript:`, `vbscript:`, `data:`, etc.) are rejected.

private enum HtmlListKind: Equatable {
    case bullet
    case numbered
}

private struct ActiveHtmlMark {
    var mark: Mark
    var start: Int
}

private struct HtmlTagFrame {
    var tag: String
    var addedMarks: [Mark]
    var suppressedMarks: [Mark]
}

private let HTML_MAX_DEPTH: Int = 512

/// Safe URL check for `<a href="...">`: allows `http:`, `https:`, `mailto:`, `tel:`, and
/// scheme-less URLs.
func isSafeHref(_ url: String) -> Bool {
    var cleaned: [UInt8] = []
    cleaned.reserveCapacity(min(url.utf8.count, 64))
    for s in url.unicodeScalars {
        if editIsScalarControl(s) || s.properties.isWhitespace {
            continue
        }
        if cleaned.count >= 64 {
            break
        }
        if s.value < 0x80 {
            let b = UInt8(s.value)
            cleaned.append((b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z")) ? (b + 32) : b)
        } else {
            for b in s.utf8 {
                cleaned.append(b)
            }
        }
    }
    if cleaned.isEmpty {
        return false
    }
    var schemeLen = cleaned.count
    for (idx, b) in cleaned.enumerated() {
        let isAlnum = (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
            || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
        let isSchemeChar = isAlnum || b == UInt8(ascii: "+") || b == UInt8(ascii: "-") || b == UInt8(ascii: ".")
        if !isSchemeChar {
            schemeLen = idx
            break
        }
    }
    if schemeLen >= cleaned.count || cleaned[schemeLen] != UInt8(ascii: ":") {
        // No scheme: relative path, `www.example.com`, or `#fragment`.
        return true
    }
    let scheme = String(decoding: cleaned[0..<schemeLen], as: UTF8.self)
    return scheme == "http" || scheme == "https" || scheme == "mailto" || scheme == "tel"
}

/// Decodes HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`, `&#123;`, `&#x1F600;`).
func decodeEntities(_ input: String) -> String {
    let bytes = Array(input.utf8)
    guard bytes.contains(UInt8(ascii: "&")) else { return input }
    var out: [UInt8] = []
    out.reserveCapacity(bytes.count)
    decodeEntitiesSlice(bytes[0..<bytes.count], into: &out)
    return String(decoding: out, as: UTF8.self)
}

private func decodeEntitiesSlice(_ slice: ArraySlice<UInt8>, into out: inout [UInt8]) {
    var i = slice.startIndex
    let end = slice.endIndex
    while i < end {
        if slice[i] != UInt8(ascii: "&") {
            out.append(slice[i])
            i += 1
            continue
        }
        let afterAmp = i + 1
        // Look for `;` in the next 33 bytes only, so a run of bare `&`s stays linear.
        let windowEnd = min(end, afterAmp + 33)
        var semiIdx: Int? = nil
        var scan = afterAmp
        while scan < windowEnd {
            if slice[scan] == UInt8(ascii: ";") {
                semiIdx = scan
                break
            }
            scan += 1
        }
        guard let semi = semiIdx, semi > afterAmp else {
            out.append(UInt8(ascii: "&"))
            i = afterAmp
            continue
        }
        let entitySlice = slice[afterAmp..<semi]
        var hasWhitespace = false
        for b in entitySlice where editIsAsciiWhitespace(b) || b >= 0x80 {
            if editIsAsciiWhitespace(b) {
                hasWhitespace = true
                break
            }
        }
        if hasWhitespace {
            out.append(UInt8(ascii: "&"))
            i = afterAmp
            continue
        }
        let entityStr = String(decoding: entitySlice, as: UTF8.self)
        if entityStr.unicodeScalars.contains(where: { $0.properties.isWhitespace }) {
            out.append(UInt8(ascii: "&"))
            i = afterAmp
            continue
        }
        let decoded: Unicode.Scalar?
        if entityStr.hasPrefix("#x") || entityStr.hasPrefix("#X") {
            let hex = entityStr.dropFirst(2)
            if let code = UInt32(hex, radix: 16) {
                decoded = Unicode.Scalar(code)
            } else {
                decoded = nil
            }
        } else if entityStr.hasPrefix("#") {
            let dec = entityStr.dropFirst(1)
            if entityStr == "#39" {
                decoded = "'"
            } else if let code = UInt32(dec, radix: 10) {
                decoded = Unicode.Scalar(code)
            } else {
                decoded = nil
            }
        } else {
            switch entityStr {
            case "amp", "AMP": decoded = "&"
            case "lt", "LT": decoded = "<"
            case "gt", "GT": decoded = ">"
            case "quot", "QUOT": decoded = "\""
            case "apos": decoded = "'"
            case "nbsp", "NBSP": decoded = "\u{00A0}"
            case "copy": decoded = "©"
            case "mdash": decoded = "—"
            case "ndash": decoded = "–"
            case "hellip": decoded = "…"
            case "lsquo": decoded = "‘"
            case "rsquo": decoded = "’"
            case "ldquo": decoded = "“"
            case "rdquo": decoded = "”"
            case "bull": decoded = "•"
            case "colon": decoded = ":"
            case "Tab": decoded = "\t"
            case "NewLine": decoded = "\n"
            default: decoded = nil
            }
        }
        if let ch = decoded {
            for b in ch.utf8 {
                out.append(b)
            }
            i = semi + 1
        } else {
            out.append(UInt8(ascii: "&"))
            i = afterAmp
        }
    }
}

private func escapeHtmlBytes(_ slice: ArraySlice<UInt8>, into out: inout [UInt8]) {
    for b in slice {
        switch b {
        case UInt8(ascii: "&"):
            out.append(contentsOf: "&amp;".utf8)
        case UInt8(ascii: "<"):
            out.append(contentsOf: "&lt;".utf8)
        case UInt8(ascii: ">"):
            out.append(contentsOf: "&gt;".utf8)
        case UInt8(ascii: "\""):
            out.append(contentsOf: "&quot;".utf8)
        default:
            out.append(b)
        }
    }
}

private func extractAttr(_ attrsBytes: ArraySlice<UInt8>, _ nameLower: String) -> String? {
    let targetBytes = Array(nameLower.utf8)
    var i = attrsBytes.startIndex
    let end = attrsBytes.endIndex
    while i < end {
        while i < end && editIsAsciiWhitespace(attrsBytes[i]) {
            i += 1
        }
        let keyStart = i
        while i < end {
            let b = attrsBytes[i]
            let isKeyChar = (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
                || (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
                || (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
                || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") || b == UInt8(ascii: ":")
            if !isKeyChar { break }
            i += 1
        }
        if i == keyStart {
            i += 1
            continue
        }
        let keySlice = attrsBytes[keyStart..<i]
        while i < end && editIsAsciiWhitespace(attrsBytes[i]) {
            i += 1
        }
        if i >= end || attrsBytes[i] != UInt8(ascii: "=") {
            continue
        }
        i += 1
        while i < end && editIsAsciiWhitespace(attrsBytes[i]) {
            i += 1
        }
        if i >= end {
            break
        }
        let valSlice: ArraySlice<UInt8>
        if attrsBytes[i] == UInt8(ascii: "\"") || attrsBytes[i] == UInt8(ascii: "'") {
            let quote = attrsBytes[i]
            i += 1
            let valStart = i
            while i < end && attrsBytes[i] != quote {
                i += 1
            }
            valSlice = attrsBytes[valStart..<i]
            if i < end {
                i += 1
            }
        } else {
            let valStart = i
            while i < end
                && !editIsAsciiWhitespace(attrsBytes[i])
                && attrsBytes[i] != UInt8(ascii: ">")
                && attrsBytes[i] != UInt8(ascii: "/")
            {
                i += 1
            }
            valSlice = attrsBytes[valStart..<i]
        }
        if asciiCaseInsensitiveEqual(keySlice, targetBytes) {
            var decoded: [UInt8] = []
            decoded.reserveCapacity(valSlice.count)
            decodeEntitiesSlice(valSlice, into: &decoded)
            return String(decoding: decoded, as: UTF8.self)
        }
    }
    return nil
}

private func asciiCaseInsensitiveEqual(_ a: ArraySlice<UInt8>, _ bLower: [UInt8]) -> Bool {
    guard a.count == bLower.count else { return false }
    var ai = a.startIndex
    for j in 0..<bLower.count {
        let ab = a[ai]
        let lower = (ab >= UInt8(ascii: "A") && ab <= UInt8(ascii: "Z")) ? (ab + 32) : ab
        if lower != bLower[j] { return false }
        ai += 1
    }
    return true
}

private func parseStyleMarks(_ style: String, _ add: inout [Mark], _ remove: inout [Mark]) {
    for decl in style.split(separator: ";") {
        guard let colonIdx = decl.firstIndex(of: ":") else { continue }
        let prop = decl[..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let val = decl[decl.index(after: colonIdx)...].trimmingCharacters(in: .whitespacesAndNewlines)
        if prop == "font-weight" {
            let v = val.split(whereSeparator: { $0.isWhitespace }).first.map { $0.lowercased() } ?? ""
            if v == "bold" || v == "bolder" || (Float(v).map { $0 >= 600.0 } ?? false) {
                add.append(.bold)
            } else if v == "normal" || v == "lighter" || (Float(v).map { $0 < 600.0 } ?? false) {
                remove.append(.bold)
            }
        } else if prop == "font-style" {
            let v = val.split(whereSeparator: { $0.isWhitespace }).first.map { $0.lowercased() } ?? ""
            if v == "italic" || v == "oblique" {
                add.append(.italic)
            } else if v == "normal" {
                remove.append(.italic)
            }
        } else if prop == "text-decoration" || prop == "text-decoration-line" {
            for tokSub in val.split(whereSeparator: { $0.isWhitespace }) {
                let tok = tokSub.lowercased()
                if tok == "underline" {
                    add.append(.underline)
                } else if tok == "line-through" {
                    add.append(.strike)
                } else if tok == "none" {
                    remove.append(.underline)
                    remove.append(.strike)
                }
            }
        }
    }
}

func parseHtml(_ html: String) -> TextEdit {
    let bytes = Array(html.utf8)
    var textBytes: [UInt8] = []
    var marks: [MarkRange] = []
    var blocks: [Block] = [.paragraph]
    var softBreaks: [UInt32] = []

    var stack: [HtmlTagFrame] = []
    var openTags: [String: Int] = [:]
    var activeMarks: [ActiveHtmlMark] = []
    var listStack: [HtmlListKind] = []
    var inPre = 0
    var inQuote = 0
    var inLi = 0
    var lineHasBlock = false
    var lineOpen = false
    var lineHasContent = false

    func currentDefaultBlock() -> Block {
        if inPre > 0 {
            return .code
        } else if inLi > 0, let kind = listStack.last {
            let level = UInt8(min(listStack.count - 1, Int(MAX_LIST_LEVEL)))
            switch kind {
            case .bullet: return .bullet(level)
            case .numbered: return .numbered(level)
            }
        } else if inQuote > 0 {
            return .quote
        } else {
            return .paragraph
        }
    }

    func flushActiveMarks(_ pos: Int) {
        if inPre == 0 {
            for idx in activeMarks.indices {
                if activeMarks[idx].start < pos {
                    marks.append(MarkRange(
                        start: activeMarks[idx].start,
                        end: pos,
                        mark: activeMarks[idx].mark
                    ))
                }
                activeMarks[idx].start = pos
            }
        } else {
            for idx in activeMarks.indices {
                activeMarks[idx].start = pos
            }
        }
    }

    func startNewParagraph(_ block: Block) {
        if (!lineHasBlock || lineOpen) && !lineHasContent {
            if !blocks.isEmpty {
                blocks[blocks.count - 1] = block
            }
            lineHasBlock = true
            lineOpen = true
            return
        }
        let pos = textBytes.count
        flushActiveMarks(pos)
        textBytes.append(UInt8(ascii: "\n"))
        blocks.append(block)
        let newPos = textBytes.count
        for idx in activeMarks.indices {
            activeMarks[idx].start = newPos
        }
        lineHasBlock = true
        lineOpen = true
        lineHasContent = false
    }

    func pushBr() {
        flushActiveMarks(textBytes.count)
        let blk = blocks.last ?? .paragraph
        textBytes.append(UInt8(ascii: "\n"))
        blocks.append(blk)
        if inPre == 0 {
            softBreaks.append(UInt32(blocks.count - 1))
        }
        let newPos = textBytes.count
        for idx in activeMarks.indices {
            activeMarks[idx].start = newPos
        }
    }

    var deferredBr: (Int, Int)? = nil
    var i = 0
    let totalBytes = bytes.count

    while i < totalBytes {
        if bytes[i] == UInt8(ascii: "<") {
            // Comment `<!-- ... -->`
            if i + 4 <= totalBytes,
               bytes[i + 1] == UInt8(ascii: "!"),
               bytes[i + 2] == UInt8(ascii: "-"),
               bytes[i + 3] == UInt8(ascii: "-")
            {
                var scan = i + 4
                var foundEnd: Int? = nil
                while scan + 3 <= totalBytes {
                    if bytes[scan] == UInt8(ascii: "-"),
                       bytes[scan + 1] == UInt8(ascii: "-"),
                       bytes[scan + 2] == UInt8(ascii: ">")
                    {
                        foundEnd = scan + 3
                        break
                    }
                    scan += 1
                }
                if let nextI = foundEnd {
                    i = nextI
                    continue
                } else {
                    break
                }
            }
            // Processing instruction or doctype `<!...>` / `<?...>`
            if i + 2 <= totalBytes && (bytes[i + 1] == UInt8(ascii: "!") || bytes[i + 1] == UInt8(ascii: "?")) {
                var scan = i + 2
                var foundGt: Int? = nil
                while scan < totalBytes {
                    if bytes[scan] == UInt8(ascii: ">") {
                        foundGt = scan + 1
                        break
                    }
                    scan += 1
                }
                if let nextI = foundGt {
                    i = nextI
                    continue
                } else {
                    break
                }
            }
            var closeAngle: Int? = nil
            var scan = i + 1
            while scan < totalBytes {
                if bytes[scan] == UInt8(ascii: ">") {
                    closeAngle = scan
                    break
                }
                scan += 1
            }
            guard let gtIdx = closeAngle else {
                decodeEntitiesSlice(bytes[i..<totalBytes], into: &textBytes)
                break
            }
            var tagLo = i + 1
            var tagHi = gtIdx
            i = gtIdx + 1

            while tagLo < tagHi && editIsAsciiWhitespace(bytes[tagLo]) { tagLo += 1 }
            while tagHi > tagLo && editIsAsciiWhitespace(bytes[tagHi - 1]) { tagHi -= 1 }
            if tagLo >= tagHi {
                continue
            }

            let isClosing = (bytes[tagLo] == UInt8(ascii: "/"))
            let rawEndsWithSlash = (bytes[tagHi - 1] == UInt8(ascii: "/"))

            var bodyLo = tagLo
            var bodyHi = tagHi
            while bodyLo < bodyHi && bytes[bodyLo] == UInt8(ascii: "/") { bodyLo += 1 }
            while bodyHi > bodyLo && bytes[bodyHi - 1] == UInt8(ascii: "/") { bodyHi -= 1 }
            while bodyLo < bodyHi && editIsAsciiWhitespace(bytes[bodyLo]) { bodyLo += 1 }
            while bodyHi > bodyLo && editIsAsciiWhitespace(bytes[bodyHi - 1]) { bodyHi -= 1 }

            var tagNameEnd = bodyLo
            while tagNameEnd < bodyHi {
                let b = bytes[tagNameEnd]
                if editIsAsciiWhitespace(b) || b == UInt8(ascii: "/") {
                    break
                }
                tagNameEnd += 1
            }
            var tagLowerBytes: [UInt8] = []
            tagLowerBytes.reserveCapacity(tagNameEnd - bodyLo)
            for k in bodyLo..<tagNameEnd {
                let b = bytes[k]
                tagLowerBytes.append((b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z")) ? (b + 32) : b)
            }
            let tag = String(decoding: tagLowerBytes, as: UTF8.self)
            let attrsSlice = bytes[tagNameEnd..<bodyHi]
            let selfClosing = rawEndsWithSlash || isVoidHtmlTag(tag)

            if !isClosing && (tag == "script" || tag == "style" || tag == "head") {
                if !selfClosing {
                    var patBytes: [UInt8] = [UInt8(ascii: "<"), UInt8(ascii: "/")]
                    patBytes.append(contentsOf: tagLowerBytes)
                    var search = i
                    var found: Int? = nil
                    while search + patBytes.count <= totalBytes {
                        if asciiCaseInsensitiveEqual(bytes[search..<(search + patBytes.count)], patBytes) {
                            var gtScan = search + patBytes.count
                            while gtScan < totalBytes {
                                if bytes[gtScan] == UInt8(ascii: ">") {
                                    found = gtScan + 1
                                    break
                                }
                                gtScan += 1
                            }
                            break
                        }
                        search += 1
                    }
                    i = found ?? totalBytes
                }
                continue
            }

            if !isClosing && tag == "br" {
                if let def = deferredBr, def.0 == textBytes.count && def.1 == blocks.count {
                    pushBr()
                    lineHasBlock = true
                    lineOpen = true
                }
                deferredBr = nil
                if inPre > 0 {
                    pushBr()
                    lineHasContent = false
                } else {
                    deferredBr = (textBytes.count, blocks.count)
                    lineHasBlock = true
                    lineOpen = true
                    lineHasContent = true
                }
                continue
            }

            if !isClosing && !selfClosing && stack.count >= HTML_MAX_DEPTH {
                continue
            }

            if !isClosing {
                switch tag {
                case "ul":
                    listStack.append(.bullet)
                    if lineHasContent { lineOpen = false }
                case "ol":
                    listStack.append(.numbered)
                    if lineHasContent { lineOpen = false }
                case "li":
                    inLi += 1
                    startNewParagraph(currentDefaultBlock())
                case "blockquote":
                    inQuote += 1
                    startNewParagraph(currentDefaultBlock())
                case "pre":
                    inPre += 1
                    startNewParagraph(.code)
                case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6":
                    startNewParagraph(currentDefaultBlock())
                default:
                    break
                }

                var toAdd: [Mark] = []
                var toSuppress: [Mark] = []
                switch tag {
                case "b", "strong", "h1", "h2", "h3", "h4", "h5", "h6":
                    toAdd.append(.bold)
                case "i", "em":
                    toAdd.append(.italic)
                case "u", "ins":
                    toAdd.append(.underline)
                case "s", "del", "strike":
                    toAdd.append(.strike)
                case "code":
                    if inPre == 0 {
                        toAdd.append(.code)
                    }
                case "a":
                    if let href = extractAttr(attrsSlice, "href"), isSafeHref(href) {
                        toAdd.append(.link(href.trimmingCharacters(in: .whitespacesAndNewlines)))
                    }
                case "span":
                    if let id = extractAttr(attrsSlice, "data-pill") {
                        toAdd.append(.pill(id))
                    }
                default:
                    break
                }
                if let style = extractAttr(attrsSlice, "style") {
                    parseStyleMarks(style, &toAdd, &toSuppress)
                    toAdd.removeAll { m in toSuppress.contains(where: { $0.sameKind(m) }) }
                }

                let pos = textBytes.count
                var frame = HtmlTagFrame(tag: tag, addedMarks: [], suppressedMarks: [])

                for rem in toSuppress {
                    if let idx = activeMarks.firstIndex(where: { $0.mark.sameKind(rem) }) {
                        let popped = activeMarks.remove(at: idx)
                        if inPre == 0 && popped.start < pos {
                            marks.append(MarkRange(start: popped.start, end: pos, mark: popped.mark))
                        }
                        frame.suppressedMarks.append(popped.mark)
                    }
                }
                for m in toAdd {
                    if let idx = activeMarks.firstIndex(where: { $0.mark.sameKind(m) }) {
                        if activeMarks[idx].mark != m {
                            let old = activeMarks.remove(at: idx)
                            if inPre == 0 && old.start < pos {
                                marks.append(MarkRange(start: old.start, end: pos, mark: old.mark))
                            }
                            frame.suppressedMarks.append(old.mark)
                            activeMarks.append(ActiveHtmlMark(mark: m, start: pos))
                            frame.addedMarks.append(m)
                        }
                    } else {
                        activeMarks.append(ActiveHtmlMark(mark: m, start: pos))
                        frame.addedMarks.append(m)
                    }
                }

                if !selfClosing {
                    openTags[tag, default: 0] += 1
                    stack.append(frame)
                }
            } else {
                // Closing tag
                let pos = textBytes.count
                if let openCount = openTags[tag], openCount > 0,
                   let frameIdx = stack.lastIndex(where: { $0.tag == tag })
                {
                    while stack.count > frameIdx {
                        let frame = stack.removeLast()
                        if let n = openTags[frame.tag], n > 0 {
                            openTags[frame.tag] = n - 1
                        }
                        for m in frame.addedMarks.reversed() {
                            if let idx = activeMarks.lastIndex(where: { $0.mark == m }) {
                                let ended = activeMarks.remove(at: idx)
                                if inPre == 0 && ended.start < pos {
                                    marks.append(MarkRange(start: ended.start, end: pos, mark: ended.mark))
                                }
                            }
                        }
                        for sup in frame.suppressedMarks {
                            if !activeMarks.contains(where: { $0.mark.sameKind(sup) }) {
                                activeMarks.append(ActiveHtmlMark(mark: sup, start: pos))
                            }
                        }
                        switch frame.tag {
                        case "ul", "ol":
                            _ = listStack.popLast()
                            lineOpen = false
                        case "li":
                            inLi = max(0, inLi - 1)
                            lineOpen = false
                        case "blockquote":
                            inQuote = max(0, inQuote - 1)
                            lineOpen = false
                        case "pre":
                            inPre = max(0, inPre - 1)
                            lineOpen = false
                        case "p", "div", "h1", "h2", "h3", "h4", "h5", "h6":
                            lineOpen = false
                        default:
                            break
                        }
                    }
                }
            }
        } else {
            // Plain text node up to next `<`
            var nextLt = i
            while nextLt < totalBytes && bytes[nextLt] != UInt8(ascii: "<") {
                nextLt += 1
            }
            let rawSlice = bytes[i..<nextLt]
            i = nextLt

            var decodedBytes: [UInt8] = []
            decodedBytes.reserveCapacity(rawSlice.count)
            decodeEntitiesSlice(rawSlice, into: &decodedBytes)
            let decoded = String(decoding: decodedBytes, as: UTF8.self)

            if inPre > 0 {
                let scalars = Array(decoded.unicodeScalars)
                var sIdx = 0
                while sIdx < scalars.count {
                    let c = scalars[sIdx]
                    if c == "\r" {
                        if sIdx + 1 < scalars.count && scalars[sIdx + 1] == "\n" {
                            sIdx += 1
                            continue
                        }
                        textBytes.append(UInt8(ascii: "\n"))
                        blocks.append(.code)
                        lineHasBlock = true
                        lineOpen = false
                        lineHasContent = false
                    } else if c == "\n" {
                        if lineOpen && !lineHasContent {
                            lineOpen = false
                            sIdx += 1
                            continue
                        }
                        textBytes.append(UInt8(ascii: "\n"))
                        blocks.append(.code)
                        lineHasBlock = true
                        lineOpen = false
                        lineHasContent = false
                    } else if c == "\t" || !editIsScalarControl(c) {
                        for b in c.utf8 { textBytes.append(b) }
                        lineHasBlock = true
                        lineOpen = false
                        lineHasContent = true
                    }
                    sIdx += 1
                }
            } else {
                let allWs = decoded.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
                if !lineOpen && allWs && (!lineHasBlock || lineHasContent) {
                    continue
                }
                if lineOpen && !lineHasContent && allWs && i < totalBytes && bytes[i] == UInt8(ascii: "<") {
                    if nextTagIsBlock(bytes, afterLt: i + 1) {
                        continue
                    }
                }
                if !lineOpen && !decoded.isEmpty && (!lineHasBlock || lineHasContent) {
                    let blk = currentDefaultBlock()
                    if !lineHasBlock {
                        if !blocks.isEmpty {
                            blocks[blocks.count - 1] = blk
                        }
                        lineHasBlock = true
                        lineOpen = true
                    } else if !allWs {
                        startNewParagraph(blk)
                    }
                }
                if allWs {
                    if let def = deferredBr, def.0 == textBytes.count && def.1 == blocks.count {
                        continue
                    }
                } else {
                    if let def = deferredBr, def.0 == textBytes.count && def.1 == blocks.count {
                        pushBr()
                    }
                    deferredBr = nil
                }
                var prevSpace = textBytes.isEmpty
                    || textBytes.last == UInt8(ascii: "\n")
                    || textBytes.last == UInt8(ascii: " ")
                for ch in decoded.unicodeScalars {
                    if ch.value == 0x00A0 {
                        for b in ch.utf8 { textBytes.append(b) }
                        prevSpace = false
                        lineHasBlock = true
                        lineOpen = true
                        lineHasContent = true
                    } else if ch.properties.isWhitespace {
                        if !prevSpace {
                            textBytes.append(UInt8(ascii: " "))
                            prevSpace = true
                            lineHasBlock = true
                            lineOpen = true
                            lineHasContent = true
                        }
                    } else if !editIsScalarControl(ch) {
                        for b in ch.utf8 { textBytes.append(b) }
                        prevSpace = false
                        lineHasBlock = true
                        lineOpen = true
                        lineHasContent = true
                    }
                }
            }
        }
    }

    flushActiveMarks(textBytes.count)

    if blocks.count > 1,
       blocks.last == .code,
       textBytes.last == UInt8(ascii: "\n"),
       !softBreaks.contains(UInt32(blocks.count - 1))
    {
        _ = textBytes.popLast()
        _ = blocks.popLast()
    }

    let finalText = String(decoding: textBytes, as: UTF8.self)
    var edit = TextEdit(finalText).rich()
    edit.marksStorage = marks
    edit.blocksStorage = blocks
    edit.softBreaksStorage = softBreaks
    edit.clampListLevels()
    edit.syncInvariants()
    return edit
}

private func isVoidHtmlTag(_ tag: String) -> Bool {
    switch tag {
    case "area", "base", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr":
        return true
    default:
        return false
    }
}

private let BLOCK_TAG_NAMES: [[UInt8]] = [
    Array("p".utf8), Array("div".utf8), Array("ul".utf8), Array("ol".utf8),
    Array("li".utf8), Array("blockquote".utf8), Array("pre".utf8),
    Array("h1".utf8), Array("h2".utf8), Array("h3".utf8),
    Array("h4".utf8), Array("h5".utf8), Array("h6".utf8),
]

private func nextTagIsBlock(_ bytes: [UInt8], afterLt: Int) -> Bool {
    var pos = afterLt
    let n = bytes.count
    while pos < n && editIsAsciiWhitespace(bytes[pos]) {
        pos += 1
    }
    for blk in BLOCK_TAG_NAMES {
        if pos + blk.count < n && asciiCaseInsensitiveEqual(bytes[pos..<(pos + blk.count)], blk) {
            let nextByte = bytes[pos + blk.count]
            if editIsAsciiWhitespace(nextByte) || nextByte == UInt8(ascii: ">") || nextByte == UInt8(ascii: "/") {
                return true
            }
        }
    }
    return false
}

/// Serializes UTF-8 byte range `range` of `edit` to HTML.
func serializeHtml(_ edit: TextEdit, _ range: Range<Int>) -> String {
    let textBytes = Array(edit.text.utf8)
    let textLen = textBytes.count
    let start = min(max(range.lowerBound, 0), textLen)
    let end = max(start, min(range.upperBound, textLen))
    if start == end && edit.blocks().allSatisfy({ $0 == .paragraph }) {
        return ""
    }

    var paras: [(Int, Range<Int>, Block, Bool)] = []
    for p in edit.paragraphs() {
        let pEndWithNl = p.range.upperBound < textLen ? p.range.upperBound + 1 : p.range.upperBound
        if p.range.lowerBound <= end && pEndWithNl >= start {
            let subStart = max(p.range.lowerBound, start)
            let subEnd = min(p.range.upperBound, end)
            if subStart <= subEnd
                && (subStart < subEnd || start == end || (p.range.lowerBound >= start && p.range.upperBound <= end))
            {
                paras.append((p.index, subStart..<subEnd, p.block, p.softBreak && p.range.lowerBound > start))
            }
        }
    }

    var out: [UInt8] = []
    var idx = 0
    while idx < paras.count {
        let block = paras[idx].2
        switch block {
        case .code:
            out.append(contentsOf: "<pre><code>".utf8)
            var first = true
            while idx < paras.count && paras[idx].2 == .code {
                if !first {
                    out.append(UInt8(ascii: "\n"))
                }
                first = false
                let r = paras[idx].1
                escapeHtmlBytes(textBytes[r], into: &out)
                idx += 1
            }
            out.append(contentsOf: "</code></pre>".utf8)

        case .bullet, .numbered:
            var openLists: [HtmlListKind] = []
            while idx < paras.count && paras[idx].2.isList() {
                let (_, r, blk, _) = paras[idx]
                let kind: HtmlListKind
                let level: Int
                switch blk {
                case .bullet(let l):
                    kind = .bullet
                    level = Int(l)
                case .numbered(let l):
                    kind = .numbered
                    level = Int(l)
                default:
                    kind = .bullet
                    level = 0
                }
                let targetDepth = level + 1
                while openLists.count > targetDepth {
                    switch openLists.removeLast() {
                    case .bullet: out.append(contentsOf: "</ul>".utf8)
                    case .numbered: out.append(contentsOf: "</ol>".utf8)
                    }
                }
                if openLists.count == targetDepth && openLists.last != kind {
                    switch openLists.removeLast() {
                    case .bullet: out.append(contentsOf: "</ul>".utf8)
                    case .numbered: out.append(contentsOf: "</ol>".utf8)
                    }
                }
                while openLists.count < targetDepth {
                    let k: HtmlListKind = (openLists.count + 1 == targetDepth) ? kind : (openLists.last ?? kind)
                    switch k {
                    case .bullet: out.append(contentsOf: "<ul>".utf8)
                    case .numbered: out.append(contentsOf: "<ol>".utf8)
                    }
                    openLists.append(k)
                }
                out.append(contentsOf: "<li>".utf8)
                serializeInline(edit, textBytes, r, &out)
                idx += 1
                while idx < paras.count && paras[idx].3 && paras[idx].2 == blk {
                    out.append(contentsOf: "<br>".utf8)
                    serializeInline(edit, textBytes, paras[idx].1, &out)
                    idx += 1
                }
                out.append(contentsOf: "</li>".utf8)
            }
            while let k = openLists.popLast() {
                switch k {
                case .bullet: out.append(contentsOf: "</ul>".utf8)
                case .numbered: out.append(contentsOf: "</ol>".utf8)
                }
            }

        case .quote:
            out.append(contentsOf: "<blockquote>".utf8)
            serializeInline(edit, textBytes, paras[idx].1, &out)
            idx += 1
            while idx < paras.count && paras[idx].3 && paras[idx].2 == .quote {
                out.append(contentsOf: "<br>".utf8)
                serializeInline(edit, textBytes, paras[idx].1, &out)
                idx += 1
            }
            out.append(contentsOf: "</blockquote>".utf8)

        case .paragraph:
            out.append(contentsOf: "<p>".utf8)
            serializeInline(edit, textBytes, paras[idx].1, &out)
            idx += 1
            while idx < paras.count && paras[idx].3 && paras[idx].2 == .paragraph {
                out.append(contentsOf: "<br>".utf8)
                serializeInline(edit, textBytes, paras[idx].1, &out)
                idx += 1
            }
            out.append(contentsOf: "</p>".utf8)
        }
    }
    return String(decoding: out, as: UTF8.self)
}

private func serializeInline(
    _ edit: TextEdit,
    _ textBytes: [UInt8],
    _ range: Range<Int>,
    _ out: inout [UInt8]
) {
    var at = range.lowerBound
    for m in edit.marks() where range.lowerBound <= m.start && m.end <= range.upperBound {
        guard let id = m.mark.pillId() else { continue }
        serializeMarks(edit, textBytes, at..<m.start, &out)
        out.append(contentsOf: "<span data-pill=\"".utf8)
        let idBytes = Array(id.utf8)
        escapeHtmlBytes(idBytes[0..<idBytes.count], into: &out)
        out.append(contentsOf: "\">".utf8)
        serializeMarks(edit, textBytes, m.range(), &out)
        out.append(contentsOf: "</span>".utf8)
        at = m.end
    }
    serializeMarks(edit, textBytes, at..<range.upperBound, &out)
}

private func serializeMarks(
    _ edit: TextEdit,
    _ textBytes: [UInt8],
    _ range: Range<Int>,
    _ out: inout [UInt8]
) {
    if range.isEmpty {
        return
    }
    let overlapping = edit.marks().filter { m in
        m.start < range.upperBound && m.end > range.lowerBound && !m.mark.isPill
    }
    if overlapping.isEmpty {
        escapeHtmlBytes(textBytes[range], into: &out)
        return
    }
    var bounds: [Int] = [range.lowerBound, range.upperBound]
    bounds.reserveCapacity(2 + overlapping.count * 2)
    for m in overlapping {
        bounds.append(min(max(m.start, range.lowerBound), range.upperBound))
        bounds.append(min(max(m.end, range.lowerBound), range.upperBound))
    }
    bounds.sort()
    var uniqueBounds: [Int] = []
    uniqueBounds.reserveCapacity(bounds.count)
    for b in bounds where uniqueBounds.last != b {
        uniqueBounds.append(b)
    }

    var covering: [MarkRange] = []
    var next = 0
    guard uniqueBounds.count >= 2 else { return }
    for bIdx in 0..<(uniqueBounds.count - 1) {
        let a = uniqueBounds[bIdx]
        let b = uniqueBounds[bIdx + 1]
        if a >= b { continue }
        covering.removeAll { $0.end <= a }
        while next < overlapping.count && overlapping[next].start <= a {
            if overlapping[next].end > a {
                covering.append(overlapping[next])
            }
            next += 1
        }
        var active = covering.map(\.mark)
        active.sort { htmlNestingOrder($0) < htmlNestingOrder($1) }
        for m in active {
            switch m {
            case .bold: out.append(contentsOf: "<strong>".utf8)
            case .italic: out.append(contentsOf: "<em>".utf8)
            case .underline: out.append(contentsOf: "<u>".utf8)
            case .strike: out.append(contentsOf: "<s>".utf8)
            case .code: out.append(contentsOf: "<code>".utf8)
            case .link(let url):
                out.append(contentsOf: "<a href=\"".utf8)
                let uBytes = Array(url.utf8)
                escapeHtmlBytes(uBytes[0..<uBytes.count], into: &out)
                out.append(contentsOf: "\">".utf8)
            case .pill:
                break
            }
        }
        escapeHtmlBytes(textBytes[a..<b], into: &out)
        for m in active.reversed() {
            switch m {
            case .bold: out.append(contentsOf: "</strong>".utf8)
            case .italic: out.append(contentsOf: "</em>".utf8)
            case .underline: out.append(contentsOf: "</u>".utf8)
            case .strike: out.append(contentsOf: "</s>".utf8)
            case .code: out.append(contentsOf: "</code>".utf8)
            case .link: out.append(contentsOf: "</a>".utf8)
            case .pill: break
            }
        }
    }
}

private func htmlNestingOrder(_ m: Mark) -> UInt8 {
    switch m {
    case .link: return 0
    case .bold: return 1
    case .italic: return 2
    case .underline: return 3
    case .strike: return 4
    case .code: return 5
    case .pill: return 6
    }
}
