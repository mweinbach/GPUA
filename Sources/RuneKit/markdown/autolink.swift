// Ported from: crates/rune-kit/src/markdown/autolink.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Bare GFM autolinks (`https://…`, `http://…`, `www.…`) found in inline text.

import Rune

/// Scans `inl.text` outside inline code and existing links for bare GFM autolinks (`https://…`,
/// `http://…`, `www.…`) and wires them into `inl.links` and `inl.spans`.
func autolinkInline(_ inl: inout MarkdownInline, _ imageRanges: [(Int, Int)]) {
    if !inl.text.contains("://") && !inl.text.contains("www.") {
        return
    }
    var excluded: [(Int, Int)] = []
    excluded.reserveCapacity(inl.spans.count + imageRanges.count)
    for (a, b, st) in inl.spans {
        switch st {
        case .code, .codePad, .link:
            excluded.append((a, b))
        default:
            break
        }
    }
    excluded.append(contentsOf: imageRanges)
    excluded.sort { $0.0 < $1.0 }

    let bytes = Array(inl.text.utf8)
    var found: [(Int, Int, String)] = []
    var cursor = 0
    for (exA, exB) in excluded {
        if cursor < exA {
            scanBareUrls(bytes, cursor, exA, &found)
        }
        if exB > cursor {
            cursor = exB
        }
    }
    if cursor < bytes.count {
        scanBareUrls(bytes, cursor, bytes.count, &found)
    }
    if found.isEmpty {
        return
    }
    let hadLinks = !inl.links.isEmpty
    for (start, end, dest) in found {
        inl.links.append((start, end, dest))
        inl.spans.append((start, end, .link))
    }
    if hadLinks {
        inl.links.sort { $0.0 < $1.0 }
        // Keep `.link` spans in `inl.spans` ordered by start byte to match `inl.links`.
        let linkRanges = inl.links.map { ($0.0, $0.1) }
        var k = 0
        for idx in inl.spans.indices where inl.spans[idx].2 == .link {
            inl.spans[idx].0 = linkRanges[k].0
            inl.spans[idx].1 = linkRanges[k].1
            k += 1
        }
    }
}

@inline(__always)
private func utf8ScalarByteLen(_ b: UInt8) -> Int {
    if b < 0x80 { return 1 }
    if (b & 0xE0) == 0xC0 { return 2 }
    if (b & 0xF0) == 0xE0 { return 3 }
    if (b & 0xF8) == 0xF0 { return 4 }
    return 1
}

@inline(__always)
private func asciiLower(_ b: UInt8) -> UInt8 {
    (b >= 0x41 && b <= 0x5A) ? (b + 32) : b
}

private func matchesPrefixIgnoreAsciiCase(_ bytes: [UInt8], _ pos: Int, _ end: Int, _ ascii: StaticString) -> Bool {
    let n = ascii.utf8CodeUnitCount
    guard pos + n <= end else { return false }
    return ascii.withUTF8Buffer { pat in
        for k in 0..<n where asciiLower(bytes[pos + k]) != pat[k] {
            return false
        }
        return true
    }
}

private func scanBareUrls(_ bytes: [UInt8], _ segStart: Int, _ segEnd: Int, _ out: inout [(Int, Int, String)]) {
    var i = segStart
    while i < segEnd {
        let prefixLen: Int
        let isWww: Bool
        if matchesPrefixIgnoreAsciiCase(bytes, i, segEnd, "https://") {
            prefixLen = 8
            isWww = false
        } else if matchesPrefixIgnoreAsciiCase(bytes, i, segEnd, "http://") {
            prefixLen = 7
            isWww = false
        } else if i + 4 <= segEnd
            && bytes[i] == 0x77 && bytes[i + 1] == 0x77 && bytes[i + 2] == 0x77 && bytes[i + 3] == 0x2E
        {
            prefixLen = 4
            isWww = true
        } else {
            i += min(utf8ScalarByteLen(bytes[i]), segEnd - i)
            continue
        }

        let validPrev: Bool
        if i == 0 {
            validPrev = true
        } else {
            let prev = bytes[i - 1]
            switch prev {
            case 0x20, 0x09, 0x0A, 0x2A, 0x5F, 0x7E, 0x5B: // ' ', '\t', '\n', '*', '_', '~', '['
                validPrev = true
            case 0x28: // '('
                validPrev = (i < 2 || bytes[i - 2] != 0x5D) // not "]("
            default:
                validPrev = false
            }
        }
        if !validPrev {
            i += prefixLen
            continue
        }

        // Advance until Unicode whitespace, Unicode control, '<' or '>'.
        let restStr = String(decoding: bytes[i..<segEnd], as: UTF8.self)
        var rawLen = 0
        for scalar in restStr.unicodeScalars {
            let v = scalar.value
            let isStop = scalar.properties.isWhitespace
                || v <= 0x1F
                || (v >= 0x7F && v <= 0x9F)
                || v == 0x3C // '<'
                || v == 0x3E // '>'
            if isStop {
                break
            }
            rawLen += scalar.utf8.count
        }
        var end = i + rawLen
        trimGfmAutolink(bytes, i, prefixLen, &end)
        let matched = String(decoding: bytes[i..<end], as: UTF8.self)
        let afterPrefix = String(decoding: bytes[(i + prefixLen)..<end], as: UTF8.self)
        if validAutolinkDomain(afterPrefix, isWww) {
            let dest = isWww ? "http://\(matched)" : matched
            out.append((i, end, dest))
            i = end
        } else {
            i += prefixLen
        }
    }
}

/// GFM 6.9 extended autolink path trailing-punctuation trimming.
private func trimGfmAutolink(_ bytes: [UInt8], _ start: Int, _ prefixLen: Int, _ end: inout Int) {
    while end - start > prefixLen {
        let slice = String(decoding: bytes[start..<end], as: UTF8.self)
        guard let last = slice.unicodeScalars.last else { break }
        switch last {
        case "?", "!", ".", ",", ":", "*", "_", "~", "'", "\"":
            end -= last.utf8.count
            continue
        case ")":
            let bodyStart = start + prefixLen
            var opens = 0
            var closes = 0
            for k in bodyStart..<end {
                if bytes[k] == 0x28 { opens += 1 }
                else if bytes[k] == 0x29 { closes += 1 }
            }
            if closes > opens {
                end -= 1
                continue
            }
            return
        case "]":
            let bodyStart = start + prefixLen
            var opens = 0
            var closes = 0
            for k in bodyStart..<end {
                if bytes[k] == 0x5B { opens += 1 }
                else if bytes[k] == 0x5D { closes += 1 }
            }
            if closes > opens {
                end -= 1
                continue
            }
            return
        case ";":
            let beforeSemiEnd = end - 1
            var amp: Int? = nil
            var k = beforeSemiEnd
            while k > start {
                k -= 1
                if bytes[k] == 0x26 { // '&'
                    amp = k
                    break
                }
            }
            if let ampIdx = amp, ampIdx - start >= prefixLen, ampIdx + 1 < beforeSemiEnd {
                var allAlnum = true
                for j in (ampIdx + 1)..<beforeSemiEnd {
                    let b = bytes[j]
                    let isAlnum = (b >= 0x30 && b <= 0x39)
                        || (b >= 0x41 && b <= 0x5A)
                        || (b >= 0x61 && b <= 0x7A)
                    if !isAlnum {
                        allAlnum = false
                        break
                    }
                }
                if allAlnum {
                    end = ampIdx
                    continue
                }
            }
            end -= 1
            continue
        default:
            return
        }
    }
}

/// Validates the authority/domain portion of a bare URL after `https://`, `http://`, or `www.`.
private func validAutolinkDomain(_ afterPrefix: String, _ isWww: Bool) -> Bool {
    let bytes = Array(afterPrefix.utf8)
    var hostEnd = bytes.count
    for (idx, b) in bytes.enumerated() {
        if b == 0x2F || b == 0x3F || b == 0x23 { // '/', '?', '#'
            hostEnd = idx
            break
        }
    }
    var hostSlice = bytes[0..<hostEnd]
    if let colonIdx = hostSlice.lastIndex(of: 0x3A), colonIdx + 1 < hostSlice.endIndex {
        let port = hostSlice[(colonIdx + 1)..<hostSlice.endIndex]
        if port.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) {
            hostSlice = hostSlice[0..<colonIdx]
        }
    }
    if hostSlice.isEmpty {
        return false
    }
    @inline(__always)
    func isAsciiAlnum(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }
    let first = hostSlice[hostSlice.startIndex]
    let last = hostSlice[hostSlice.index(before: hostSlice.endIndex)]
    if !isAsciiAlnum(first) || last == 0x2E || last == 0x2D {
        return false
    }
    for b in hostSlice {
        if !(isAsciiAlnum(b) || b == 0x2E || b == 0x2D || b == 0x5F) {
            return false
        }
    }
    let host = String(decoding: hostSlice, as: UTF8.self)
    if isWww && !host.contains(".") {
        return false
    }
    let segments = host.split(separator: ".", omittingEmptySubsequences: false)
    if segments.contains(where: { $0.isEmpty }) {
        return false
    }
    // GFM 6.9: the last two domain segments must not contain underscores.
    if segments.count >= 2 {
        for seg in segments[(segments.count - 2)...] where seg.contains("_") {
            return false
        }
    }
    return true
}
