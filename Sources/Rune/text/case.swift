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
typealias CaseSource = TextCaseSource

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

    // PORT NOTE: Implements Unicode Standard §3.13 `Final_Sigma` context rule explicitly via
    // `UnicodeScalar.Properties` (`isCased`, `isCaseIgnorable`), matching Rust `str::to_lowercase`
    // across macOS, Linux, Windows, Android, and WASI (Swift stdlib `String.lowercased()` omits
    // `Final_Sigma` when Greek sigma precedes space + another word).
    static func new(_ textCase: TextCase, _ text: String) -> (String, TextCaseSource) {
        let scalars = Array(text.unicodeScalars)
        var shownStr = ""
        shownStr.reserveCapacity(text.utf8.count)
        var bounds: [(UInt32, UInt32)] = []
        bounds.reserveCapacity(scalars.count + 1)
        var srcByte: UInt32 = 0
        var dstByte: UInt32 = 0

        for (idx, scalar) in scalars.enumerated() {
            bounds.append((srcByte, dstByte))
            let mapped: String
            switch textCase {
            case .uppercase:
                mapped = String(scalar).uppercased()
            case .lowercase:
                if scalar.value == 0x03A3 {
                    var prev = idx - 1
                    while prev >= 0 && scalars[prev].properties.isCaseIgnorable {
                        prev -= 1
                    }
                    let precededByCased = prev >= 0 && scalars[prev].properties.isCased

                    var next = idx + 1
                    while next < scalars.count && scalars[next].properties.isCaseIgnorable {
                        next += 1
                    }
                    let followedByCased = next < scalars.count && scalars[next].properties.isCased

                    mapped = (precededByCased && !followedByCased) ? "ς" : "σ"
                } else {
                    mapped = String(scalar).lowercased()
                }
            }
            shownStr.append(mapped)
            srcByte += UInt32(scalar.utf8.count)
            dstByte += UInt32(mapped.utf8.count)
        }
        bounds.append((UInt32(text.utf8.count), dstByte))
        return (shownStr, TextCaseSource(text: text, bounds: bounds))
    }

    func shown(_ b: UInt32, _ up: Bool) -> UInt32 {
        let i: Int
        if up {
            i = partitionPoint(byFirst: true, lessOrEqual: false, target: b)
        } else {
            let pp = partitionPoint(byFirst: true, lessOrEqual: true, target: b)
            i = max(pp - 1, 0)
        }
        if i < bounds.count { return bounds[i].1 }
        return bounds.last?.1 ?? 0
    }

    func source(_ b: UInt32, _ up: Bool) -> UInt32 {
        let i: Int
        if up {
            i = partitionPoint(byFirst: false, lessOrEqual: false, target: b)
        } else {
            let pp = partitionPoint(byFirst: false, lessOrEqual: true, target: b)
            i = max(pp - 1, 0)
        }
        if i < bounds.count { return bounds[i].0 }
        return UInt32(text.utf8.count)
    }

    private func partitionPoint(byFirst: Bool, lessOrEqual: Bool, target: UInt32) -> Int {
        var lo = 0
        var hi = bounds.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            let val = byFirst ? bounds[mid].0 : bounds[mid].1
            let cond = lessOrEqual ? (val <= target) : (val < target)
            if cond {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }
}
