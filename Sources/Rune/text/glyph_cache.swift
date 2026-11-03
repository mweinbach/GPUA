// Ported from: crates/rune/src/text/glyph_cache.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Each painted paragraph's glyphs, flattened out of `TextLayout` once, so a frame where the text
//! didn't change replays them instead of walking runs and looking up every glyph's atlas mask again.

/// Bytes all entries may hold before the least recently painted go (8 MiB).
let GLYPH_CACHE_MAX_BYTES: Int = 8 << 20
/// Entries kept at most.
let GLYPH_CACHE_MAX_ENTRIES: Int = 4096
/// One paragraph's share (2 MiB): past it, an entry drops its lines and starts again from what shows.
private let GLYPH_CACHE_ENTRY_BYTES: Int = 2 << 20
/// A line not flattened yet.
private let UNFLAT: UInt32 = UInt32.max

private let STATE_UNKNOWN: UInt8 = 0
private let STATE_PLACED: UInt8 = 1
private let STATE_EMPTY: UInt8 = 2
private let NO_MASK = AtlasGlyph(page: 0, x: 0, y: 0, w: 0, h: 0, left: 0, top: 0)

struct GlyphCacheKey: Sendable, Equatable, Hashable {
    var layoutId: ObjectIdentifier
    var inks: UInt64
    var apple: UInt8
}

struct CachedLineGlyph {
    var id: UInt32
    var rel: Float
    var x: Float
    var y: Float
    var byte: UInt32
    var face: UInt16
    var sub0: UInt8
    var sub1: UInt8
    var state: UInt8
    var mask: AtlasGlyph
}

final class GlyphCacheEntry {
    weak var layout: TextLayout?
    var inks: [UInt8] = []
    var kBits: UInt32 = 0
    var bytes: Bool = false
    /// The atlas clock the masks below were looked up under.
    var clock: UInt64 = 0
    var used: UInt64 = 0
    /// Per line, its glyphs' range (`(UNFLAT, UNFLAT)` until it first paints).
    var lines: [(UInt32, UInt32)] = []
    var glyphs: [CachedLineGlyph] = []
    var glyphCapacityTrack: Int = 0
    var faces: [EmitFace] = []

    func size() -> Int {
        192
            + max(inks.capacity, inks.count)
            + max(lines.capacity, lines.count) * 8
            + max(max(glyphs.capacity, glyphCapacityTrack), glyphs.count) * MemoryLayout<CachedLineGlyph>.stride
            + max(faces.capacity, faces.count) * MemoryLayout<EmitFace>.stride
    }

    func clear(_ lineCount: Int) {
        glyphCapacityTrack = max(glyphCapacityTrack, glyphs.capacity)
        lines.removeAll(keepingCapacity: true)
        if lineCount > 0 {
            lines.reserveCapacity(lineCount)
            for _ in 0..<lineCount {
                lines.append((UNFLAT, UNFLAT))
            }
        }
        glyphs.removeAll(keepingCapacity: true)
        if glyphCapacityTrack > glyphs.capacity {
            glyphs.reserveCapacity(glyphCapacityTrack)
        }
        faces.removeAll(keepingCapacity: true)
    }

    /// Records line `i`'s glyphs, in the exact order `TextSystem.glyphsInBand` walks them.
    func flatten(_ layout: TextLayout, _ i: Int, _ table: inout [(Float, UInt32)]) {
        guard let line = layout.get(i) else { return }
        let start = UInt32(glyphs.count)
        if bytes {
            table.removeAll(keepingCapacity: true)
            var x = line.metrics().inlineMinCoord + line.metrics().offset
            for run in line.runs() {
                let vClusters = run.visualClusters()
                if let first = vClusters.first {
                    x = line.metrics().inlineMinCoord + first.visualOffset
                }
                for cl in vClusters {
                    table.append((x, UInt32(clamping: cl.textRange.lowerBound)))
                    x += cl.advance
                }
            }
            if table.count > 1 {
                table.sort { $0.0 < $1.0 }
            }
        }

        for item in line.items() {
            guard case .glyphRun(let glyphRun) = item else { continue }
            let face = EmitFace.of(glyphRun)
            faces.append(face)
            let faceIdx = UInt16(faces.count - 1)
            var rel = glyphRun.offset()
            for g in glyphRun.glyphs() {
                let byte: UInt32 = bytes ? partitionClusterTable(table, rel + 0.01) : 0
                glyphs.append(CachedLineGlyph(
                    id: UInt32(g.id),
                    rel: rel,
                    x: g.x,
                    y: g.y,
                    byte: byte,
                    face: faceIdx,
                    sub0: 0,
                    sub1: 0,
                    state: STATE_UNKNOWN,
                    mask: NO_MASK
                ))
                rel += g.advance
            }
        }
        glyphCapacityTrack = max(glyphCapacityTrack, glyphs.capacity)
        lines[i] = (start, UInt32(glyphs.count))
    }
}

final class GlyphCache {
    var entries: [GlyphCacheKey: GlyphCacheEntry] = [:]
    var bytesCount: Int = 0
    var frame: UInt64 = 0
    /// Buffers of an entry whose layout went this frame, reused by the next new entry.
    var spare: GlyphCacheEntry? = nil
    /// Lines flattened out of `TextLayout`, a running count.
    var flattened: UInt64 = 0

    private func retire(_ e: GlyphCacheEntry) {
        let room = max(e.glyphs.capacity, e.glyphCapacityTrack)
        if room * MemoryLayout<CachedLineGlyph>.stride <= GLYPH_CACHE_ENTRY_BYTES {
            let curSpareRoom = spare.map { max($0.glyphs.capacity, $0.glyphCapacityTrack) } ?? -1
            if curSpareRoom < room {
                e.layout = nil
                spare = e
            }
        }
    }

    /// Drops `layout`'s entries before `layout` is re-broken in place.
    func forget(_ layout: TextLayout) {
        let id = ObjectIdentifier(layout)
        var toRemove: [GlyphCacheKey] = []
        for k in entries.keys where k.layoutId == id {
            toRemove.append(k)
        }
        guard !toRemove.isEmpty else { return }
        for k in toRemove {
            if let e = entries.removeValue(forKey: k) {
                retire(e)
            }
        }
        bytesCount = entries.values.reduce(0) { $0 + $1.size() }
    }

    /// Drops every entry, for layouts shaped in fonts that no longer apply.
    func clear() {
        entries.removeAll()
        spare = nil
        bytesCount = 0
    }

    /// Drops entries whose layout was deallocated, then evicts least recently painted while over budget.
    func beginFrame() {
        frame &+= 1
        spare = nil
        var deadKeys: [GlyphCacheKey] = []
        for (k, e) in entries where e.layout == nil {
            deadKeys.append(k)
        }
        if !deadKeys.isEmpty {
            for k in deadKeys {
                if let e = entries.removeValue(forKey: k) {
                    retire(e)
                }
            }
            bytesCount = entries.values.reduce(0) { $0 + $1.size() }
        }
        if bytesCount <= GLYPH_CACHE_MAX_BYTES && entries.count <= GLYPH_CACHE_MAX_ENTRIES {
            return
        }
        var order: [(UInt64, GlyphCacheKey)] = entries.map { ($0.value.used, $0.key) }
        order.sort { $0.0 < $1.0 }
        let targetBytes = GLYPH_CACHE_MAX_BYTES * 3 / 4
        let targetEntries = GLYPH_CACHE_MAX_ENTRIES * 3 / 4
        for (_, k) in order {
            if bytesCount <= targetBytes && entries.count <= targetEntries {
                break
            }
            if let e = entries.removeValue(forKey: k) {
                bytesCount = max(0, bytesCount - e.size())
            }
        }
        bytesCount = entries.values.reduce(0) { $0 + $1.size() }
    }

    func len() -> Int { entries.count }
    func bytes() -> Int { bytesCount }
}

extension TextSystem {
    /// `glyphsInBand` for a layout painted frame after frame: the first frame flattens the visible
    /// lines, later frames replay them bit-for-bit identically.
    func glyphsInBandCached(
        _ layout: TextLayout,
        _ origin: [Float],
        _ k: Float,
        _ bytes: Bool,
        _ band: Range<Float>,
        _ out: inout [GlyphQuad]
    ) {
        let inks = smoothingState.inks
        var inksHash: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in inks {
            inksHash = (inksHash ^ UInt64(b)) &* 0x100_0000_01b3
        }
        let key = GlyphCacheKey(
            layoutId: ObjectIdentifier(layout),
            inks: inksHash,
            apple: smoothingState.key()
        )
        let curFrame = glyphCache.frame
        let entry: GlyphCacheEntry
        let beforeSize: Int
        if let existing = glyphCache.entries[key] {
            beforeSize = existing.size()
            entry = existing
        } else {
            let e = glyphCache.spare ?? GlyphCacheEntry()
            glyphCache.spare = nil
            e.layout = layout
            e.inks = inks
            e.kBits = k.bitPattern
            e.bytes = bytes
            e.clock = atlas.clock
            e.used = curFrame
            e.clear(layout.len())
            glyphCache.entries[key] = e
            beforeSize = 0
            entry = e
        }

        let fits = entry.kBits == k.bitPattern && entry.bytes == bytes && entry.inks == inks && entry.lines.count == layout.len()
        // A raster factor in motion changes every frame: draw directly until it rests.
        if !fits && entry.used &+ 1 >= curFrame {
            glyphsInBand(layout, origin, k, bytes, band, &out)
            return
        }
        if !fits || entry.glyphs.count * MemoryLayout<CachedLineGlyph>.stride > GLYPH_CACHE_ENTRY_BYTES {
            entry.kBits = k.bitPattern
            entry.bytes = bytes
            entry.inks = inks
            entry.clear(layout.len())
        }
        entry.used = curFrame

        var lo = 0
        if band.lowerBound > 0.0 {
            var hi = layout.len()
            while lo < hi {
                let mid = (lo + hi) / 2
                if let l = layout.get(mid), l.metrics().blockMaxCoord < band.lowerBound {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
        }

        var table = clusterScratch
        clusterScratch = []
        var i = lo
        while i < layout.len(), let line = layout.get(i), line.metrics().blockMinCoord <= band.upperBound {
            if entry.lines[i].0 == UNFLAT {
                entry.flatten(layout, i, &table)
                glyphCache.flattened &+= 1
            }
            replayCachedLine(entry, i, origin, k, &out)
            i += 1
        }
        clusterScratch = table
        glyphCache.bytesCount = max(0, glyphCache.bytesCount + entry.size() - beforeSize)
    }

    private func replayCachedLine(
        _ entry: GlyphCacheEntry,
        _ i: Int,
        _ origin: [Float],
        _ k: Float,
        _ out: inout [GlyphQuad]
    ) {
        let ox = origin.count > 0 ? origin[0] : 0.0
        let oy = origin.count > 1 ? origin[1] : 0.0
        let (start, end) = entry.lines[i]
        var curFace: UInt16 = UInt16.max
        var baseline: Float = 0.0
        var size: Float = 0.0

        for gi in Int(start)..<Int(end) {
            if entry.clock != atlas.clock {
                // An atlas page was evicted: invalidate cached masks so they are looked up again.
                entry.clock = atlas.clock
                for idx in entry.glyphs.indices {
                    entry.glyphs[idx].state = STATE_UNKNOWN
                }
            }
            let g = entry.glyphs[gi]
            let f = entry.faces[Int(g.face)]
            if g.face != curFace {
                curFace = g.face
                baseline = (oy + f.baseline * k).rounded(.toNearestOrAwayFromZero)
                size = f.size * k
            }
            let at: [Float] = (k == 1.0)
                ? [ox + g.rel + g.x, baseline + g.y]
                : [ox + (g.rel + g.x) * k, baseline + g.y * k]
            let (fPos, sub) = place(at, size, glide)
            if g.sub0 == sub[0] && g.sub1 == sub[1] && g.state == STATE_PLACED {
                atlas.touch(g.mask.page, g.mask.w * g.mask.h)
                out.append(atlasQuad(g.mask, fPos[0], fPos[1], f.ink, g.byte))
                continue
            }
            if g.sub0 == sub[0] && g.sub1 == sub[1] && g.state == STATE_EMPTY {
                continue
            }
            let placed = pushGlyph(f, g.id, at, k, g.byte, &out)
            switch placed {
            case .atlas(let mask, let pSub):
                entry.glyphs[gi].state = STATE_PLACED
                entry.glyphs[gi].sub0 = pSub[0]
                entry.glyphs[gi].sub1 = pSub[1]
                entry.glyphs[gi].mask = mask
            case .empty(let pSub):
                entry.glyphs[gi].state = STATE_EMPTY
                entry.glyphs[gi].sub0 = pSub[0]
                entry.glyphs[gi].sub1 = pSub[1]
                entry.glyphs[gi].mask = NO_MASK
            case .other:
                entry.glyphs[gi].state = STATE_UNKNOWN
                entry.glyphs[gi].sub0 = 0
                entry.glyphs[gi].sub1 = 0
                entry.glyphs[gi].mask = NO_MASK
            }
        }
    }
}
