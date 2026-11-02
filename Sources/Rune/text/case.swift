// Ported from: crates/rune/src/text/case.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.textCase`: draw a cased copy of a string while byte ranges (spans, links) and tools keep the authored one.

/// How `El.textCase` draws a text's letters.
public enum TextCase: Sendable, Equatable, Hashable {
    /// Capitals, by `String.uppercased()`: `"Straße"` draws `"STRASSE"`.
    case uppercase
    /// Lower case, by `String.lowercased()` (a word-final `"Σ"` draws `"ς"`).
    case lowercase
}

/// The authored string behind a cased one, and where each of its characters landed.
struct TextCaseSource: Sendable, Equatable {
    var text: String
    /// `(sourceByte, shownByte)` at each source character's start, then both lengths.
    var bounds: [(UInt32, UInt32)]

    static func == (lhs: TextCaseSource, rhs: TextCaseSource) -> Bool {
        guard lhs.text == rhs.text, lhs.bounds.count == rhs.bounds.count else { return false }
        for (a, b) in zip(lhs.bounds, rhs.bounds) where a.0 != b.0 || a.1 != b.1 {
            return false
        }
        return true
    }

    static func new(_ textCase: TextCase, _ text: String) -> (String, TextCaseSource) {
        let shownStr: String
        switch textCase {
        case .uppercase: shownStr = text.uppercased()
        case .lowercase: shownStr = text.lowercased()
        }
        var bounds: [(UInt32, UInt32)] = []
        bounds.reserveCapacity(text.unicodeScalars.count + 1)
        var srcByte: UInt32 = 0
        var dstByte: UInt32 = 0
        for scalar in text.unicodeScalars {
            bounds.append((srcByte, dstByte))
            let s = String(scalar)
            let mapped: String
            switch textCase {
            case .uppercase: mapped = s.uppercased()
            case .lowercase: mapped = s.lowercased()
            }
            srcByte += UInt32(s.utf8.count)
            dstByte += UInt32(mapped.utf8.count)
        }
        bounds.append((UInt32(text.utf8.count), UInt32(shownStr.utf8.count)))
        return (shownStr, TextCaseSource(text: text, bounds: bounds))
    }

    func shown(_ b: UInt32, _ up: Bool) -> UInt32 {
        let i: Int
        if up {
            i = bounds.firstIndex(where: { $0.0 >= b }) ?? bounds.count
        } else {
            let pp = bounds.firstIndex(where: { $0.0 > b }) ?? bounds.count
            i = max(pp - 1, 0)
        }
        if i < bounds.count { return bounds[i].1 }
        return bounds.last?.1 ?? 0
    }

    func source(_ b: UInt32, _ up: Bool) -> UInt32 {
        let i: Int
        if up {
            i = bounds.firstIndex(where: { $0.1 >= b }) ?? bounds.count
        } else {
            let pp = bounds.firstIndex(where: { $0.1 > b }) ?? bounds.count
            i = max(pp - 1, 0)
        }
        if i < bounds.count { return bounds[i].0 }
        return UInt32(text.utf8.count)
    }
}
