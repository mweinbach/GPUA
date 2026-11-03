// Ported from: crates/rune/src/tooling/interaction/names.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Normalized, interned control and route names from element paths (`#0/sidebar/row-x1208` -> `sidebar/row-x*`).

private let interactionControlSegments = 4
private let interactionPageSegments = 3
private let interactionSegmentChars = 32

/// Reference-counted interned string box so pointer identity can verify zero-reallocation interning.
final class InternedText: Sendable, Equatable, CustomStringConvertible {
    let value: String
    init(_ value: String) { self.value = value }
    var description: String { value }
    static func == (lhs: InternedText, rhs: InternedText) -> Bool {
        lhs.value == rhs.value
    }
}

struct InteractionName: Sendable, Equatable {
    var hash: UInt64
    var textBox: InternedText
    var text: String { textBox.value }
}

func interactionFxHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 0x0000_0100_0000_01b3
    }
    return h
}

/// Interned names by 64-bit hash.
struct InteractionNames {
    private var names: [UInt64: InternedText] = [:]
    private var scratch: String = ""

    init() {}

    mutating func control(_ path: String) -> InteractionName {
        intern { out in
            interactionNormalize(path, keep: interactionControlSegments, out: &out)
        }
    }

    mutating func route(_ page: String?, _ modal: String?) -> InteractionName {
        intern { out in
            if let page {
                interactionNormalize(page, keep: interactionPageSegments, out: &out)
            } else {
                out.append("root")
            }
            if out.isEmpty {
                out.append("root")
            }
            if let modal {
                out.append("+modal:")
                let beforeCount = out.utf8.count
                interactionNormalize(modal, keep: 1, out: &out)
                if out.utf8.count == beforeCount {
                    out.append("*")
                }
            }
        }
    }

    mutating func fixed(_ name: String) -> InteractionName {
        intern { out in
            out.append(name)
        }
    }

    private mutating func intern(_ write: (inout String) -> Void) -> InteractionName {
        scratch.removeAll(keepingCapacity: true)
        write(&scratch)
        let hash = interactionFxHash(scratch)
        if let existing = names[hash] {
            return InteractionName(hash: hash, textBox: existing)
        }
        let created = InternedText(scratch)
        names[hash] = created
        return InteractionName(hash: hash, textBox: created)
    }
}

/// Writes `path`'s last `keep` keyed segments, normalized, joined by `/`.
func interactionNormalize(_ path: String, keep: Int, out: inout String) {
    let keyed = path.split(separator: "/", omittingEmptySubsequences: true).filter { !$0.hasPrefix("#") }
    let skip = max(0, keyed.count - keep)
    for (i, seg) in keyed.dropFirst(skip).enumerated() {
        if i > 0 {
            out.append("/")
        }
        interactionNormalizeSegment(String(seg), out: &out)
    }
}

private func interactionNormalizeSegment(_ seg: String, out: inout String) {
    if seg.contains(where: \.isWhitespace) {
        out.append("~")
        return
    }
    var segOut = ""
    let scalars = Array(seg.unicodeScalars)
    var i = 0
    while i < scalars.count {
        let sc = scalars[i]
        if isAsciiAlnum(sc) {
            var end = i + 1
            while end < scalars.count && isAsciiAlnum(scalars[end]) {
                end += 1
            }
            let wordScalars = scalars[i..<end]
            interactionNormalizeWord(wordScalars, out: &segOut)
            i = end
        } else {
            if sc == "-" || sc == "_" || sc == "." || sc == ":" {
                segOut.unicodeScalars.append(sc)
            } else {
                segOut.append("_")
            }
            i += 1
        }
        if segOut.utf8.count >= interactionSegmentChars {
            segOut = truncateUtf8(segOut, maxBytes: interactionSegmentChars)
            out.append(segOut)
            return
        }
    }
    out.append(segOut)
}

private func isAsciiAlnum(_ s: UnicodeScalar) -> Bool {
    (s.value >= 0x30 && s.value <= 0x39)
        || (s.value >= 0x41 && s.value <= 0x5A)
        || (s.value >= 0x61 && s.value <= 0x7A)
}

private func isAsciiDigit(_ s: UnicodeScalar) -> Bool {
    s.value >= 0x30 && s.value <= 0x39
}

private func interactionNormalizeWord(_ word: ArraySlice<UnicodeScalar>, out: inout String) {
    let hasDigits = word.contains(where: isAsciiDigit)
    if hasDigits && word.count >= 8 {
        interactionAppendStar(&out)
        return
    }
    for sc in word {
        if isAsciiDigit(sc) {
            interactionAppendStar(&out)
        } else {
            out.unicodeScalars.append(sc)
        }
    }
}

private func interactionAppendStar(_ out: inout String) {
    if !out.hasSuffix("*") {
        out.append("*")
    }
}

private func truncateUtf8(_ s: String, maxBytes: Int) -> String {
    guard s.utf8.count > maxBytes else { return s }
    var out = ""
    var bytes = 0
    for sc in s.unicodeScalars {
        let len = sc.utf8.count
        if bytes + len > maxBytes { break }
        out.unicodeScalars.append(sc)
        bytes += len
    }
    return out
}
