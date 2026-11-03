// Ported from: crates/rune/src/text/layout_cache.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The shaped-layout caches' eviction: what stale text stays shaped between commits.

/// Heap bytes a layout holds per byte of its text, and on top of that.
private let LAYOUT_PER_BYTE: Int = 64
private let LAYOUT_BASE: Int = 2048

/// Heap bytes of layouts kept after the commits that used them (3 MiB): about 1,100 short
/// labels or 48 KB of paragraphs.
let STALE_BYTES: Int = 3 << 20

struct LayoutCacheEntry<T> {
    var value: T
    /// The commit generation it was last used in.
    var used: UInt32
    /// About how many heap bytes it holds.
    var cost: UInt32
    /// The `shapeKey` it lays out, or 0 for a run.
    var shape: UInt64

    init(value: T, used: UInt32, textLen: Int, shape: UInt64) {
        let bytes = min(max(textLen, 0) * LAYOUT_PER_BYTE + LAYOUT_BASE, Int(UInt32.max))
        self.value = value
        self.used = used
        self.cost = UInt32(bytes)
        self.shape = shape
    }
}

/// Drops what `cache` hasn't used in the last two commits once it outgrows `STALE_BYTES`,
/// least recently used first. A view's layouts all share the commit it was last shown in, so
/// that commit's are kept while the budget lasts rather than all dropped together.
func evictLayoutCache<T>(_ cache: inout [UInt64: LayoutCacheEntry<T>], _ g: UInt32) {
    @inline(__always)
    func isStale(_ used: UInt32) -> Bool {
        g &- used >= 2
    }

    var total = 0
    for e in cache.values where isStale(e.used) {
        total += Int(e.cost)
    }
    if total <= STALE_BYTES {
        return
    }

    var ages: [(age: UInt32, cost: Int, key: UInt64)] = []
    ages.reserveCapacity(cache.count)
    for (k, e) in cache where isStale(e.used) {
        ages.append((g &- e.used, Int(e.cost), k))
    }
    ages.sort { a, b in
        if a.age != b.age { return a.age < b.age }
        return a.key < b.key
    }

    var younger = 0
    var kept = 0
    var cutoff = UInt32.max
    for i in ages.indices {
        let (age, cost, _) = ages[i]
        if i > 0 && ages[i - 1].age != age {
            younger = kept
        }
        kept += cost
        if kept > STALE_BYTES {
            cutoff = age
            break
        }
    }

    var room = max(0, STALE_BYTES - younger)
    for (age, cost, key) in ages {
        if age < cutoff {
            continue
        }
        if age == cutoff && cost <= room {
            room -= cost
            continue
        }
        cache.removeValue(forKey: key)
    }
}

extension TextSystem {
    /// Marks the layouts of `shape` as replaced by an edit of its text, as typing or streaming
    /// makes. Unless this commit used them, they go when it ends, rather than each edit's copy
    /// taking the stale budget from views that may be shown again.
    func supersede(_ shape: UInt64) {
        superseded.insert(shape)
    }

    /// Drops replaced layouts this commit didn't use, then keeps layouts used in the last two
    /// commits, and older ones, most recently used first, while they fit in `STALE_BYTES`.
    public func endCommit() {
        let g = generation
        if !superseded.isEmpty {
            let gone = superseded
            layouts = layouts.filter { _, e in
                e.used == g || !gone.contains(e.shape)
            }
            superseded.removeAll(keepingCapacity: true)
        }
        evictLayoutCache(&layouts, g)
        shapes = shapes.filter { _, key in layouts[key] != nil }
        // Rebind any surviving layout whose shape slot lost its pointed-to width
        for (k, e) in layouts where shapes[e.shape] == nil {
            shapes[e.shape] = k
        }
        evictLayoutCache(&runs, g)
        generation = g &+ 1
    }

    /// A live run owns its latest layout; don't retain every timer tick in the commit cache.
    public func layoutLive(_ text: String, _ style: TextStyle, _ scale: Float) -> TextLayout {
        let key = shapeKey(text, [], style, scale, false, [])
        let wasCached = layouts[key] != nil
        let prevShape = shapes[key]
        let layout = layoutRich(text, [], style, scale, nil)
        if !wasCached {
            layouts.removeValue(forKey: key)
            if let prev = prevShape {
                shapes[key] = prev
            } else {
                shapes.removeValue(forKey: key)
            }
        }
        return layout
    }

    /// Number of layouts currently resident in the layout cache.
    public func cachedLayoutCount() -> Int {
        layouts.count
    }

    func layoutBlocksInner(
        text: String,
        spans: [Span],
        blocks: [Block],
        pills: [PillChip],
        style: TextStyle,
        scale: Float,
        maxWidth: Float?,
        align: TextAlignment,
        wrapAnywhere: Bool,
        retain: Bool
    ) -> TextLayout {
        layoutKeyed(
            shape: nil,
            text: text,
            spans: spans,
            blocks: blocks,
            pills: pills,
            style: style,
            scale: scale,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: wrapAnywhere,
            cache: retain
        )
    }

    func layoutKeyed(
        shape: UInt64?,
        text: String,
        spans: [Span],
        blocks: [Block],
        pills: [PillChip],
        style: TextStyle,
        scale: Float,
        maxWidth: Float?,
        align: TextAlignment,
        wrapAnywhere: Bool,
        cache: Bool
    ) -> TextLayout {
        let hasIndentedBlocks = blocks.contains { $0 != .paragraph }
        let sKey = shape ?? shapeKey(text, spans, style, scale, wrapAnywhere, pills)
        let key = breakKey(sKey, maxWidth, align, hasIndentedBlocks ? blocks : nil)
        let g = generation

        if cache {
            if var hit = layouts[key] {
                hit.used = g
                layouts[key] = hit
                if shapes[sKey] == nil {
                    shapes[sKey] = key
                }
                return hit.value
            }
            if let prev = shapes[sKey], var prevEntry = layouts.removeValue(forKey: prev) {
                rebroken &+= 1
                if prevEntry.used != g && isKnownUniquelyReferenced(&prevEntry.value) {
                    // Unreferenced layout from an earlier commit: drop any cached glyph lines at its address,
                    // re-break in place, and move to the new width!
                    glyphCache.forget(prevEntry.value)
                    breakLinesWithBlocks(
                        layout: prevEntry.value,
                        blocks: blocks,
                        maxWidth: maxWidth,
                        align: align,
                        wrapAnywhere: wrapAnywhere
                    )
                    prevEntry.used = g
                    let result = prevEntry.value
                    layouts[key] = prevEntry
                    shapes[sKey] = key
                    return result
                } else {
                    // Handed out this commit or still held externally: restore `prev` and re-break a COW clone.
                    let cloned = prevEntry.value.cloneShaped()
                    layouts[prev] = prevEntry
                    breakLinesWithBlocks(
                        layout: cloned,
                        blocks: blocks,
                        maxWidth: maxWidth,
                        align: align,
                        wrapAnywhere: wrapAnywhere
                    )
                    layouts[key] = LayoutCacheEntry(value: cloned, used: g, textLen: text.utf8.count, shape: sKey)
                    shapes[sKey] = key
                    return cloned
                }
            }
        }

        shaped &+= 1
        let shapedLayout = shapeParagraph(
            text: text,
            spans: spans,
            pills: pills,
            style: style,
            scale: scale
        )
        breakLinesWithBlocks(
            layout: shapedLayout,
            blocks: blocks,
            maxWidth: maxWidth,
            align: align,
            wrapAnywhere: wrapAnywhere
        )
        if cache {
            layouts[key] = LayoutCacheEntry(value: shapedLayout, used: g, textLen: text.utf8.count, shape: sKey)
            shapes[sKey] = key
        }
        return shapedLayout
    }
}
