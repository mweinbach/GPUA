// Ported from: crates/rune/src/runtime/virtual/selection.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Retained text selection survival across virtualized row scroll/cull cycles.

struct VirtualTextEntry: Sendable, Equatable {
    var scrollKey: String
    var itemIndex: Int
    var itemKey: String
    var path: String
    var text: String
}

struct VirtualSelectionAnchor: Sendable, Equatable {
    var scrollKey: String
    var itemIndex: Int
    var itemKey: String
    var byteOffset: Int
}

struct VirtualSelectionStore: Sendable {
    /// Cached text of virtualized items by `(scrollKey, itemIndex)` so offscreen selected rows still copy cleanly.
    var entriesByScroll: [String: [Int: VirtualTextEntry]] = [:]
    var anchor: VirtualSelectionAnchor? = nil
    var focus: VirtualSelectionAnchor? = nil

    mutating func record(_ entry: VirtualTextEntry) {
        entriesByScroll[entry.scrollKey, default: [:]][entry.itemIndex] = entry
    }

    func selectedItems(for scrollKey: String) -> [SelectedText] {
        guard let a = anchor, let f = focus,
              a.scrollKey == scrollKey, f.scrollKey == scrollKey,
              let bucket = entriesByScroll[scrollKey]
        else { return [] }

        let forward = (a.itemIndex < f.itemIndex) || (a.itemIndex == f.itemIndex && a.byteOffset <= f.byteOffset)
        let startAnchor = forward ? a : f
        let endAnchor = forward ? f : a

        var out: [SelectedText] = []
        for idx in startAnchor.itemIndex...endAnchor.itemIndex {
            guard let entry = bucket[idx] else { continue }
            let utf8Count = entry.text.utf8.count
            let lo = (idx == startAnchor.itemIndex) ? min(max(startAnchor.byteOffset, 0), utf8Count) : 0
            let hi = (idx == endAnchor.itemIndex) ? min(max(endAnchor.byteOffset, 0), utf8Count) : utf8Count
            guard lo < hi else { continue }
            let sub = sliceUtf8Safely(entry.text, lo..<hi)
            out.append(
                SelectedText(
                    path: entry.path,
                    key: entry.itemKey,
                    range: lo..<hi,
                    text: sub,
                    len: utf8Count,
                    whole: lo == 0 && hi == utf8Count
                )
            )
        }
        return out
    }

    mutating func clear() {
        anchor = nil
        focus = nil
    }
}

func sliceUtf8Safely(_ s: String, _ byteRange: Range<Int>) -> String {
    let utf8 = s.utf8
    let total = utf8.count
    let lo = min(max(byteRange.lowerBound, 0), total)
    let hi = min(max(byteRange.upperBound, lo), total)
    guard lo < hi else { return "" }
    let startIdx = utf8.index(utf8.startIndex, offsetBy: lo)
    let endIdx = utf8.index(utf8.startIndex, offsetBy: hi)
    return String(decoding: utf8[startIdx..<endIdx], as: UTF8.self)
}
