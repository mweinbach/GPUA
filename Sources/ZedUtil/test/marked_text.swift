// Ported from: crates/util/src/test/marked_text.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

// PORT NOTE: In Rust, `std::ops::Range<usize>` has `start` and `end` fields and allows
// `start > end` for reversed/directed selections (e.g. `7..4`). Swift's `Range<Int>` requires
// `lowerBound <= upperBound`. `MarkedRange` faithfully represents directed/reversed text ranges.
public struct MarkedRange: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    public init(_ start: Int, _ end: Int) {
        self.start = start
        self.end = end
    }

    public init(_ range: Range<Int>) {
        self.start = range.lowerBound
        self.end = range.upperBound
    }

    public var isReversed: Bool {
        start > end
    }

    public var count: Int {
        abs(end - start)
    }

    public var standardRange: Range<Int> {
        min(start, end)..<max(start, end)
    }

    public var description: String {
        "\(start)..\(end)"
    }
}

// Infix operator `..` for convenient range syntax matching Rust `7..4`
infix operator .. : RangeFormationPrecedence

public func .. (start: Int, end: Int) -> MarkedRange {
    MarkedRange(start: start, end: end)
}

/// Marker configuration enum for constructing and grouping text ranges.
public enum TextRangeMarker: Equatable, Hashable, Sendable {
    case empty(Character)
    case range(Character, Character)
    case reverseRange(Character, Character)

    public func markers() -> [Character] {
        switch self {
        case .empty(let m):
            return [m]
        case .range(let l, let r), .reverseRange(let l, let r):
            return [l, r]
        }
    }
}

/// Construct a string and a list of offsets within that string using a single
/// string containing embedded position markers.
public func markedTextOffsetsBy(
    _ markedText: String,
    markers: [Character]
) -> (String, [Character: [Int]]) {
    var extractedMarkers: [Character: [Int]] = [:]
    var unmarkedText = ""

    for char in markedText {
        if markers.contains(char) {
            extractedMarkers[char, default: []].append(unmarkedText.utf8.count)
        } else {
            unmarkedText.append(char)
        }
    }

    return (unmarkedText, extractedMarkers)
}

/// Construct a string and a list of ranges within that string using a single
/// string containing embedded range markers, using arbitrary characters as
/// range markers. By using multiple different range markers, you can construct
/// ranges that overlap each other.
public func markedTextRangesBy(
    _ markedText: String,
    markers: [TextRangeMarker]
) -> (String, [TextRangeMarker: [MarkedRange]]) {
    let allMarkers = markers.flatMap { $0.markers() }
    let (unmarkedText, offsets) = markedTextOffsetsBy(markedText, markers: allMarkers)
    var markerOffsets = offsets

    var rangeLookup: [TextRangeMarker: [MarkedRange]] = [:]
    for marker in markers {
        switch marker {
        case .empty(let emptyChar):
            let offsets = markerOffsets.removeValue(forKey: emptyChar) ?? []
            rangeLookup[marker] = offsets.map { MarkedRange(start: $0, end: $0) }
        case .range(let startMarker, let endMarker):
            let starts = markerOffsets.removeValue(forKey: startMarker) ?? []
            let ends = markerOffsets.removeValue(forKey: endMarker) ?? []
            precondition(starts.count == ends.count, "marked ranges are unbalanced")
            rangeLookup[marker] = zip(starts, ends).map { start, end in
                precondition(end >= start, "marked ranges must be disjoint")
                return MarkedRange(start: start, end: end)
            }
        case .reverseRange(let startMarker, let endMarker):
            let starts = markerOffsets.removeValue(forKey: startMarker) ?? []
            let ends = markerOffsets.removeValue(forKey: endMarker) ?? []
            precondition(starts.count == ends.count, "marked ranges are unbalanced")
            rangeLookup[marker] = zip(starts, ends).map { start, end in
                precondition(end >= start, "marked ranges must be disjoint")
                return MarkedRange(start: end, end: start)
            }
        }
    }

    return (unmarkedText, rangeLookup)
}

/// Construct a string and a list of ranges within that string using a single
/// string containing embedded range markers.
public func markedTextRanges(
    _ markedText: String,
    rangesAreDirected: Bool = false
) -> (String, [MarkedRange]) {
    var unmarkedText = ""
    var ranges: [MarkedRange] = []
    var currentRangeStart: Int?
    var currentRangeCursor: Int?

    let text = markedText.replacingOccurrences(of: "•", with: " ")
    for char in text {
        switch char {
        case "ˇ":
            let unmarkedLen = unmarkedText.utf8.count
            if currentRangeStart != nil {
                if currentRangeCursor != nil {
                    fatalError("duplicate point marker 'ˇ'")
                }
                currentRangeCursor = unmarkedLen
            } else {
                ranges.append(MarkedRange(start: unmarkedLen, end: unmarkedLen))
            }
        case "«":
            let unmarkedLen = unmarkedText.utf8.count
            if currentRangeStart != nil {
                fatalError("unexpected range start marker '«'")
            }
            currentRangeStart = unmarkedLen
        case "»":
            let unmarkedLen = unmarkedText.utf8.count
            guard let start = currentRangeStart else {
                fatalError("unexpected range end marker '»'")
            }
            currentRangeStart = nil

            var reversed = false
            if let cursor = currentRangeCursor {
                currentRangeCursor = nil
                if cursor == start {
                    reversed = true
                } else if cursor != unmarkedLen {
                    fatalError("unexpected 'ˇ' marker in the middle of a range")
                }
            } else if rangesAreDirected {
                fatalError("missing 'ˇ' marker to indicate range direction")
            }

            if reversed {
                ranges.append(MarkedRange(start: unmarkedLen, end: start))
            } else {
                ranges.append(MarkedRange(start: start, end: unmarkedLen))
            }
        default:
            unmarkedText.append(char)
        }
    }

    return (unmarkedText, ranges)
}

/// Construct a string and a list of offsets within that string using a single
/// string containing embedded position markers.
public func markedTextOffsets(_ markedText: String) -> (String, [Int]) {
    let (text, ranges) = markedTextRanges(markedText, rangesAreDirected: false)
    let offsets = ranges.map { range in
        precondition(range.start == range.end, "marked ranges must be point offsets")
        return range.start
    }
    return (text, offsets)
}

/// Generates a marked text string with «...» and ˇ markers from an unmarked string and ranges.
public func generateMarkedText(
    _ unmarkedText: String,
    ranges: [MarkedRange],
    indicateCursors: Bool = false
) -> String {
    var result = unmarkedText
    for range in ranges.reversed() {
        if indicateCursors {
            if range.start < range.end {
                let endIdx = result.utf8.index(result.startIndex, offsetBy: range.end)
                result.insert(contentsOf: "ˇ»", at: endIdx)
                let startIdx = result.utf8.index(result.startIndex, offsetBy: range.start)
                result.insert("«", at: startIdx)
            } else if range.start == range.end {
                let idx = result.utf8.index(result.startIndex, offsetBy: range.start)
                result.insert("ˇ", at: idx)
            } else {
                let startIdx = result.utf8.index(result.startIndex, offsetBy: range.start)
                result.insert("»", at: startIdx)
                let endIdx = result.utf8.index(result.startIndex, offsetBy: range.end)
                result.insert(contentsOf: "«ˇ", at: endIdx)
            }
        } else {
            if range.start == range.end {
                let idx = result.utf8.index(result.startIndex, offsetBy: range.start)
                result.insert("ˇ", at: idx)
            } else {
                let maxOffset = max(range.start, range.end)
                let minOffset = min(range.start, range.end)
                let endIdx = result.utf8.index(result.startIndex, offsetBy: maxOffset)
                result.insert("»", at: endIdx)
                let startIdx = result.utf8.index(result.startIndex, offsetBy: minOffset)
                result.insert("«", at: startIdx)
            }
        }
    }
    return result
}
