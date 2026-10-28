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
    var lines = s.components(separatedBy: "\n")
    if lines.count > maxLines {
        lines = Array(lines.prefix(maxLines))
        if !lines.isEmpty {
            lines.removeLast()
        }
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
