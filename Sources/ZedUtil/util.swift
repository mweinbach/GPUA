// Ported from: crates/util/src/util.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

public func isUtf8CharBoundary(_ byte: UInt8) -> Bool {
    Int8(bitPattern: byte) >= -0x40
}

public func truncate(_ s: String, _ maxChars: Int) -> String {
    if s.count <= maxChars { return s }
    let endIdx = s.index(s.startIndex, offsetBy: maxChars)
    return String(s[..<endIdx])
}

public func truncateAndTrailoff(_ s: String, _ maxChars: Int) -> String {
    if s.count <= maxChars {
        return s
    }
    let endIdx = s.index(s.startIndex, offsetBy: maxChars)
    return String(s[..<endIdx]) + "…"
}

public func truncateAndRemoveFront(_ s: String, _ maxChars: Int) -> String {
    if s.count <= maxChars {
        return s
    }
    let suffixCount = max(0, maxChars)
    let startIdx = s.index(s.endIndex, offsetBy: -suffixCount)
    return "…" + String(s[startIdx...])
}

public func truncateLinesAndTrailoff(_ s: String, _ maxLines: Int) -> String {
    var lines = s.components(separatedBy: "\n").prefix(maxLines).map { String($0) }
    if lines.count > maxLines - 1 {
        lines.removeLast()
        return lines.joined(separator: "\n") + "\n…"
    } else {
        return lines.joined(separator: "\n")
    }
}

public func truncateToByteLimit(_ s: String, _ maxBytes: Int) -> String {
    let utf8 = s.utf8
    if utf8.count < maxBytes {
        return s
    }
    for i in (0..<maxBytes).reversed() {
        let prefixData = Data(utf8.prefix(i))
        if let str = String(data: prefixData, encoding: .utf8) {
            return str
        }
    }
    return ""
}

public func truncateLinesToByteLimit(_ s: String, _ maxBytes: Int) -> String {
    let utf8 = s.utf8
    if utf8.count < maxBytes {
        return s
    }
    let bytes = Array(utf8.prefix(maxBytes))
    for i in (0..<maxBytes).reversed() {
        if bytes[i] == UInt8(ascii: "\n") {
            let lineData = Data(bytes.prefix(i + 1))
            if let str = String(data: lineData, encoding: .utf8) {
                return str
            }
        }
    }
    return truncateToByteLimit(s, maxBytes)
}

public func extendSorted<T>(
    _ vec: inout [T],
    _ newItems: [T],
    limit: Int,
    by areInIncreasingOrder: (T, T) -> Bool
) {
    var startIndex = 0
    for newItem in newItems {
        var low = startIndex
        var high = vec.count
        var found = false
        while low < high {
            let mid = (low + high) / 2
            if areInIncreasingOrder(vec[mid], newItem) {
                low = mid + 1
            } else if areInIncreasingOrder(newItem, vec[mid]) {
                high = mid
            } else {
                found = true
                break
            }
        }
        if !found {
            let index = low
            if vec.count < limit {
                vec.insert(newItem, at: index)
            } else if index < vec.count {
                vec.removeLast()
                vec.insert(newItem, at: index)
            }
            startIndex = index
        }
    }
}

public func truncateToBottomNSortedBy<T>(
    _ vec: inout [T],
    _ n: Int,
    by areInIncreasingOrder: (T, T) -> Bool
) {
    vec.sort(by: areInIncreasingOrder)
    if vec.count > n {
        vec.removeSubrange(n..<vec.count)
    }
}

@inlinable
public func maybe<T>(_ block: () throws -> T?) -> T? {
    try? block()
}

public struct NumericPrefixWithSuffix: Equatable, Comparable, Sendable {
    public let prefix: UInt64?
    public let suffix: String

    public init(_ prefix: UInt64?, _ suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }

    public static func fromNumericPrefixedStr(_ str: String) -> NumericPrefixWithSuffix {
        var digits = ""
        var remainderStart = str.startIndex
        for idx in str.indices {
            let ch = str[idx]
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
                remainderStart = str.index(after: idx)
            } else {
                break
            }
        }
        let prefix = UInt64(digits)
        let remainder = String(str[remainderStart...])
        return NumericPrefixWithSuffix(prefix, remainder)
    }

    public static func < (lhs: NumericPrefixWithSuffix, rhs: NumericPrefixWithSuffix) -> Bool {
        switch (lhs.prefix, rhs.prefix) {
        case (nil, nil):
            let c = lhs.suffix.caseInsensitiveCompare(rhs.suffix)
            if c == .orderedSame {
                return lhs.suffix > rhs.suffix
            }
            return c == .orderedAscending
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (l?, r?):
            if l < r { return true }
            if l > r { return false }
            let c = lhs.suffix.caseInsensitiveCompare(rhs.suffix)
            if c == .orderedSame {
                return lhs.suffix > rhs.suffix
            }
            return c == .orderedAscending
        }
    }
}

public func wordConsistsOfEmojis(_ s: String) -> Bool {
    guard !s.isEmpty else { return false }
    for scalar in s.unicodeScalars {
        if scalar.properties.isEmoji && !scalar.isASCII {
            continue
        }
        if scalar.value == 0x200D || scalar.value == 0xFE0F {
            continue
        }
        return false
    }
    return true
}

public func expandedAndWrappedUsizeRange(
    _ range: Range<Int>,
    _ additionalBefore: Int,
    _ additionalAfter: Int,
    _ wrapLength: Int
) -> [Int] {
    let startWraps = range.lowerBound < additionalBefore
    let endWraps = wrapLength < range.upperBound + additionalAfter
    if startWraps && endWraps {
        return Array(0..<wrapLength)
    } else if startWraps {
        let wrappedStart = max(0, (range.lowerBound + wrapLength) - additionalBefore)
        if wrappedStart <= range.upperBound {
            return Array(0..<wrapLength)
        } else {
            return Array(0..<(range.upperBound + additionalAfter)) + Array(wrappedStart..<wrapLength)
        }
    } else if endWraps {
        let wrappedEnd = range.upperBound + additionalAfter - wrapLength
        if range.lowerBound <= wrappedEnd {
            return Array(0..<wrapLength)
        } else {
            return Array(0..<wrappedEnd) + Array((range.lowerBound - additionalBefore)..<wrapLength)
        }
    } else {
        return Array((range.lowerBound - additionalBefore)..<(range.upperBound + additionalAfter))
    }
}

public func wrappedUsizeOutwardFrom(
    _ start: Int,
    _ additionalBefore: Int,
    _ additionalAfter: Int,
    _ wrapLength: Int
) -> [Int] {
    if wrapLength == 0 { return [] }
    var count = 0
    var afterOffset = 1
    var beforeOffset = 1
    var result: [Int] = []

    while count < wrapLength {
        count += 1
        if count == 1 {
            result.append(start % wrapLength)
        } else if afterOffset <= additionalAfter && afterOffset <= beforeOffset {
            let value = (start + afterOffset) % wrapLength
            afterOffset += 1
            result.append(value)
        } else if beforeOffset <= additionalBefore {
            let value = (start + wrapLength - (beforeOffset % wrapLength)) % wrapLength
            beforeOffset += 1
            result.append(value)
        } else if afterOffset <= additionalAfter {
            let value = (start + afterOffset) % wrapLength
            afterOffset += 1
            result.append(value)
        } else {
            break
        }
    }
    return result
}

public func splitStrWithRanges(_ s: String, where pat: (Character) -> Bool) -> [(Range<Int>, String)] {
    var result: [(Range<Int>, String)] = []
    let utf8 = Array(s.utf8)
    var byteOffset = 0
    var segmentStartByte = 0
    var segmentChars = ""

    for ch in s {
        let chLen = String(ch).utf8.count
        if pat(ch) {
            if byteOffset > segmentStartByte {
                result.append((segmentStartByte..<byteOffset, segmentChars))
            }
            segmentChars = ""
            segmentStartByte = byteOffset + chLen
        } else {
            segmentChars.append(ch)
        }
        byteOffset += chLen
    }

    if utf8.count > segmentStartByte {
        result.append((segmentStartByte..<utf8.count, segmentChars))
    }

    return result
}
