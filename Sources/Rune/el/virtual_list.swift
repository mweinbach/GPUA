// Ported from: crates/rune/src/el/virtual_list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Virtual row bookkeeping. Only geometry outside the mounted window is estimated.

import Taffy

/// What a row keeps while its key stays.
private struct VirtualRow: Sendable, Equatable {
    var index: Int
    /// Its measured height, once it has been laid out.
    var height: Float?
}

// PORT NOTE: Private interior-mutable cache matching Rust's `RefCell<Vec<f32>> + Cell<bool>`
// so `prefix`, `rowEnd`, `firstVisible`, `maxOffset`, and `visibleRange` remain non-mutating.
private final class PrefixSumsCache {
    var sums: [Float] = []
    var stale: Bool = false

    func invalidate() {
        stale = true
    }

    func resolve(rowHeights: [Float], gap: Float) -> [Float] {
        if stale || sums.count != rowHeights.count + 1 {
            stale = false
            sums.removeAll(keepingCapacity: true)
            sums.reserveCapacity(rowHeights.count + 1)
            sums.append(0.0)
            var y: Float = 0.0
            for h in rowHeights {
                y += h + gap
                sums.append(y)
            }
        }
        return sums
    }
}

/// How far ahead an index-built list keeps rows mounted, in viewports either side.
private let OVERSCAN: Float = 2.0
/// An index-built list moves its window once the viewport comes this close to its edge.
private let INDEXED_EDGE: Float = 1.75
/// How much of an index-built list's overscan, in viewports per side, may be new in one commit.
private let INDEXED_BUDGET: Float = 0.5

struct VirtualList {
    /// Row keys in order; replace them with ``setKeys(_:_:_:)``.
    var keys: [String] = []
    private var rows: [String: VirtualRow] = [:]
    /// The commit each row in `keys` first appeared in.
    private var born: [UInt64] = []
    /// `keys` changed since the frame began (``frameBegins()``).
    private var keysFresh: Bool = false
    /// The last change to `keys` kept a row the reader could see.
    private var held: Bool = false
    /// Rows mounted with their insertion transition and not yet drawn.
    var entering: Set<String> = []
    /// Each row's height, measured or estimated, in `keys` order.
    private var rowHeights: [Float] = []
    private var sumsCache = PrefixSumsCache()
    var range: Range<Int> = 0..<0
    var before: Float = 0.0
    var after: Float = 0.0
    private var estimate: Float = 0.0
    /// Rows are built by index (`El.virtualRows`), so a commit costs only the rows it mounts.
    var indexed: Bool = false
    /// The rows the last applied commit mounted.
    var shown: Set<String> = []
    /// The rows drawn inside the viewport on the last frame.
    var drawn: [String] = []
    /// The row holding the focused element, kept while that row is scrolled out.
    var focusedRow: String? = nil
    /// The rows holding the text selection's anchor and focus, kept built while scrolled out.
    var pinnedRows: [String] = []
    /// The selected row on the last commit of an `El.revealSelected(true)` stack.
    var selectedRow: String? = nil
    var revealSelected: String? = nil
    var scrollPath: String = ""
    var viewport: Float = 0.0
    var top: Float = 0.0
    var padTop: Float = 0.0
    var padBottom: Float = 0.0
    private var gap: Float = 0.0
    var anchor: (String, Float)? = nil
    /// The `El.virtualRowsVersion` that `keys` came with.
    var keysVersion: UInt64? = nil
    /// The visible row range last sent to `El.onVisibleRows`.
    var reportedVisible: Range<Int>? = nil

    init() {}

    func height(_ key: String) -> Float {
        rows[key]?.height ?? estimate
    }

    func has(_ key: String) -> Bool {
        rows[key] != nil
    }

    func indexOf(_ key: String) -> Int? {
        rows[key]?.index
    }

    /// Whether row `i`, mounting in `commit`, skips its insertion transition.
    mutating func mountsQuietly(_ i: Int, _ commit: UInt64) -> Bool {
        let quiet = born[i] < commit && !(keysFresh && !shown.contains(keys[i]))
        if !quiet {
            entering.insert(keys[i])
        }
        return quiet
    }

    /// The rows changed this frame and none the reader could see stayed (a filter).
    func replacedView() -> Bool {
        keysFresh && !held
    }

    /// A new frame: what changed the keys before it has been drawn.
    mutating func frameBegins() {
        keysFresh = false
    }

    /// Whether the rows are exactly `otherKeys`, in order.
    func sameKeys<C: Collection>(_ otherKeys: C) -> Bool where C.Element == String? {
        guard otherKeys.count == keys.count else { return false }
        for (a, b) in zip(otherKeys, keys) where a != b {
            return false
        }
        return true
    }

    /// Replaces the rows. Keys that stay keep their measured height and birth; new ones are born
    /// at `commit`. Returns the first row visible at `offset` (when given) that stays, with its
    /// top before the change, to anchor the reader to.
    @discardableResult
    mutating func setKeys(_ newKeys: [String], _ commit: UInt64, _ offset: Float?) -> (String, Float)? {
        var newRows: [String: VirtualRow] = [:]
        newRows.reserveCapacity(newKeys.count)
        var newBorn: [UInt64] = []
        newBorn.reserveCapacity(newKeys.count)
        var newHeights: [Float] = []
        newHeights.reserveCapacity(newKeys.count)

        for (index, key) in newKeys.enumerated() {
            let old = rows[key]
            let h = old?.height
            newBorn.append(old.map { born[$0.index] } ?? commit)
            newHeights.append(h ?? estimate)
            let prev = newRows.updateValue(VirtualRow(index: index, height: h), forKey: key)
            precondition(prev == nil, "virtual row keys must be unique")
        }

        let newAnchor: (String, Float)?
        if let off = offset,
           let candidate = firstVisible(off, { newRows[$0] != nil }),
           candidate.1 < off + viewport {
            newAnchor = candidate
        } else {
            newAnchor = nil
        }

        if newKeys != keys {
            keysFresh = true
            if offset != nil {
                held = (newAnchor != nil)
            } else {
                held = keys.contains(where: { newRows[$0] != nil })
            }
        }

        rows = newRows
        born = newBorn
        keys = newKeys
        rowHeights = newHeights
        if !isKnownUniquelyReferenced(&sumsCache) {
            sumsCache = PrefixSumsCache()
        }
        sumsCache.invalidate()
        reportedVisible = nil
        return newAnchor
    }

    mutating func setEstimate(_ newEstimate: Float) {
        if newEstimate != estimate {
            estimate = newEstimate
            rowHeights = keys.map { height($0) }
            if !isKnownUniquelyReferenced(&sumsCache) {
                sumsCache = PrefixSumsCache()
            }
            sumsCache.invalidate()
        }
    }

    mutating func setGap(_ newGap: Float) {
        if newGap != gap {
            gap = newGap
            if !isKnownUniquelyReferenced(&sumsCache) {
                sumsCache = PrefixSumsCache()
            }
            sumsCache.invalidate()
        }
    }

    mutating func setHeight(_ key: String, _ height: Float) {
        guard var row = rows[key] else { return }
        row.height = height
        rows[key] = row
        let i = row.index
        if rowHeights[i] != height {
            rowHeights[i] = height
            if !isKnownUniquelyReferenced(&sumsCache) {
                sumsCache = PrefixSumsCache()
            }
            sumsCache.invalidate()
        }
    }

    private func sums() -> [Float] {
        sumsCache.resolve(rowHeights: rowHeights, gap: gap)
    }

    func prefix(_ end: Int) -> Float {
        let s = sums()
        return (end == 0 || end < keys.count) ? s[end] : (s[end] - gap)
    }

    /// The bottom of the first `end` rows (without the gap after row `end - 1`).
    func rowEnd(_ end: Int) -> Float {
        end == 0 ? 0.0 : (sums()[end] - gap)
    }

    /// The first row still visible at `offset`, among those `keep` accepts, and its top.
    func firstVisible(_ offset: Float, _ keep: (String) -> Bool) -> (String, Float)? {
        let s = sums()
        let first = partitionPoint(s[1...]) { padTop + $0 - gap <= offset }
        for i in first..<keys.count where keep(keys[i]) {
            return (keys[i], padTop + s[i])
        }
        return nil
    }

    /// The furthest the rows can scroll: their extent less the viewport.
    func maxOffset() -> Float {
        max(padTop + prefix(keys.count) + padBottom - viewport, 0.0)
    }

    /// The row index range intersecting the scroll viewport (`offset .. offset + viewport`).
    func visibleRange(_ offset: Float, _ pinned: Bool) -> Range<Int> {
        if keys.isEmpty {
            return 0..<0
        }
        let maxOff = maxOffset()
        let clampedOffset = pinned ? maxOff : min(max(offset, 0.0), maxOff)
        let s = sums()
        let start = partitionPoint(s[1...]) { padTop + $0 - gap <= clampedOffset }
        let end = max(partitionPoint(s[..<keys.count]) { padTop + $0 < clampedOffset + viewport }, start)
        return start..<end
    }

    /// Picks the rows to mount for `offset`, clamped to the rows' extent.
    mutating func select(_ offset: Float, _ pinned: Bool, _ budget: Set<String>?) {
        let clampedOffset = pinned ? maxOffset() : min(offset, maxOffset())
        let (ovStart, ovEnd) = overscan(clampedOffset)
        var start: Int
        var end: Int

        let s = sums()
        if let shownSet = budget, !pinned {
            let first = max(partitionPoint(s[1...]) { padTop + $0 - gap <= clampedOffset }, ovStart)
            let last = max(partitionPoint(s[..<keys.count]) { padTop + $0 < clampedOffset + viewport }, first)
            let maxBudget = viewport * INDEXED_BUDGET
            var spent: Float = 0.0
            var from = first
            while from > ovStart {
                let i = from - 1
                if !shownSet.contains(keys[i]) {
                    if spent >= maxBudget { break }
                    spent += rowHeights[i] + gap
                }
                from = i
            }
            spent = 0.0
            var to = min(last, ovEnd)
            while to < ovEnd {
                if !shownSet.contains(keys[to]) {
                    if spent >= maxBudget { break }
                    spent += rowHeights[to] + gap
                }
                to += 1
            }
            start = from
            end = max(to, from)
        } else {
            start = ovStart
            end = ovEnd
        }

        var lo = start
        var hi = end
        for k in drawn {
            guard let i = indexOf(k) else { continue }
            if i < start && prefix(start) - prefix(i) <= viewport * OVERSCAN {
                lo = min(lo, i)
            }
            if i >= end && rowEnd(i + 1) - rowEnd(end) <= viewport * OVERSCAN {
                hi = max(hi, i + 1)
            }
        }
        start = lo
        end = hi

        anchor = pinned ? nil : anchorAt(clampedOffset)
        if pinned {
            start = min(start, max(end - 32, 0))
        }
        end = max(end, start)
        place(start..<end)
    }

    /// Keeps the rows mounted now (clamped to the rows), sets the anchor for `offset`,
    /// and re-derives the space above and below them.
    mutating func hold(_ offset: Float, _ pinned: Bool) {
        let clampedOffset = pinned ? maxOffset() : min(offset, maxOffset())
        anchor = pinned ? nil : anchorAt(clampedOffset)
        let len = keys.count
        place(min(range.lowerBound, len)..<min(range.upperBound, len))
    }

    private mutating func place(_ newRange: Range<Int>) {
        let total = prefix(keys.count)
        let start = newRange.lowerBound
        let end = max(newRange.upperBound, start)
        range = start..<end
        before = prefix(start)
        after = (start < end) ? (total - rowEnd(end)) : (total - before)
    }

    private func anchorAt(_ offset: Float) -> (String, Float)? {
        let vis = visibleRange(offset, false)
        let s = sums()
        for i in vis {
            if rows[keys[i]]?.height != nil {
                return (keys[i], padTop + s[i])
            }
        }
        return firstVisible(offset, { _ in true })
    }

    private func overscan(_ offset: Float) -> (Int, Int) {
        let lo = offset - viewport * OVERSCAN
        let hi = offset + viewport * (1.0 + OVERSCAN)
        let s = sums()
        let start = partitionPoint(s[1...]) { padTop + $0 - gap <= lo }
        let end = partitionPoint(s[..<keys.count]) { padTop + $0 < hi }
        return (start, end)
    }

    /// How tall the mounted rows outside the overscan around `offset` are.
    func spare(_ offset: Float, _ pinned: Bool) -> Float {
        if pinned || keys.isEmpty { return 0.0 }
        let (start, end) = overscan(min(offset, maxOffset()))
        let above = prefix(min(start, range.upperBound)) - prefix(min(range.lowerBound, start))
        let below = rowEnd(range.upperBound) - rowEnd(min(max(end, range.lowerBound), range.upperBound))
        return max(above, 0.0) + max(below, 0.0)
    }

    func anchorDelta() -> Float {
        guard let (key, old) = anchor, let i = indexOf(key) else { return 0.0 }
        return padTop + prefix(i) - old
    }

    func needsWindow(_ offset: Float, _ pinned: Bool) -> Bool {
        if keys.isEmpty { return false }
        if pinned { return range.upperBound != keys.count }
        let edge = viewport * (indexed ? INDEXED_EDGE : 0.5)
        let topEdge = padTop + before
        let bottomEdge = padTop + rowEnd(range.upperBound)
        return (range.lowerBound > 0 && offset < topEdge + edge)
            || (range.upperBound < keys.count && offset + viewport > bottomEdge - edge)
    }
}

/// The most an element can be tall before layout.
func heightBound(_ style: Taffy.Style<String>, _ avail: Float) -> Float {
    var h = style.size.height.intoOption() ?? avail
    if let maxH = style.maxSize.height.intoOption() {
        h = min(h, maxH)
    }
    if let minH = style.minSize.height.intoOption() {
        h = max(h, minH)
    }
    return h
}

/// A column flex container's vertical gap in points; zero for non-column containers.
func gapY(_ style: Taffy.Style<String>) -> Float {
    let isColumn = style.display == .flex
        && style.flexWrap == .noWrap
        && (style.flexDirection == .column || style.flexDirection == .columnReverse)
    guard isColumn else { return 0.0 }
    return lpPoints(style.gap.height)
}

/// The most each child of an element whose bound is `bound` can be tall.
func childBounds(
    _ style: Taffy.Style<String>,
    _ scrolls: Bool,
    _ bound: Float,
    _ children: [El]
) -> ChildBounds {
    if scrolls {
        return ChildBounds(outer: .infinity, inner: .infinity, fixed: 0.0, column: false)
    }
    let inner = bound - lpPoints(style.padding.top) - lpPoints(style.padding.bottom)
    let isColumn = style.display == .flex
        && style.flexWrap == .noWrap
        && (style.flexDirection == .column || style.flexDirection == .columnReverse)
    if !isColumn || children.count < 2 {
        return ChildBounds(outer: bound, inner: inner, fixed: 0.0, column: false)
    }
    let inFlowCount = children.filter { isInFlow($0.style) }.count
    let gaps = lpPoints(style.gap.height) * Float(max(inFlowCount - 1, 0))
    let fixedSum = children.reduce(Float(0.0)) { $0 + fixedHeight($1.style) }
    return ChildBounds(outer: bound, inner: inner - gaps, fixed: fixedSum, column: isColumn)
}

struct ChildBounds {
    let outer: Float
    let inner: Float
    let fixed: Float
    let column: Bool

    func of(_ child: El) -> Float {
        let style = child.style
        let bound: Float
        if style.position == .absolute {
            if let top = lpaPoints(style.inset.top), let bottom = lpaPoints(style.inset.bottom) {
                bound = outer - top - bottom
            } else {
                bound = .infinity
            }
        } else if column && isInFlow(style) {
            bound = inner - (fixed - fixedHeight(style))
        } else {
            bound = inner
        }
        return max(bound, 0.0)
    }
}

private func lpPoints(_ p: LengthPercentage) -> Float {
    if case .length(let x) = p.value {
        return x
    }
    return 0.0
}

private func lpaPoints(_ d: LengthPercentageAuto) -> Float? {
    if case .length(let x) = d.value {
        return x
    }
    return nil
}

private func isInFlow(_ style: Taffy.Style<String>) -> Bool {
    style.display != .none && style.position != .absolute
}

private func fixedHeight(_ style: Taffy.Style<String>) -> Float {
    guard isInFlow(style) else { return 0.0 }
    let minVal = style.minSize.height.intoOption() ?? 0.0
    if style.flexShrink > 0.0 {
        return minVal
    }
    let h = style.size.height.intoOption() ?? 0.0
    let capped = style.maxSize.height.intoOption().map { min(h, $0) } ?? h
    return max(capped, minVal)
}

private func partitionPoint<C: RandomAccessCollection>(
    _ slice: C,
    _ pred: (C.Element) -> Bool
) -> Int {
    var lo = 0
    var hi = slice.count
    while lo < hi {
        let mid = lo + (hi - lo) / 2
        let idx = slice.index(slice.startIndex, offsetBy: mid)
        if pred(slice[idx]) {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    return lo
}
