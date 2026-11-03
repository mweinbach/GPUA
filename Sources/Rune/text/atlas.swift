// Ported from: crates/rune/src/text/atlas.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The glyph atlas: shelf-packed greyscale pages of glyph and icon masks, aged and evicted by
//! use, and the quads that sample them.

public let ATLAS_SIZE: UInt32 = 2048

/// Steady-state shelf pages (page 0 + one secondary page for ping-pong eviction).
let MAX_STEADY_PAGES: Int = 2

/// Hard ceiling on total glyph atlas pages if a single frame or unframed loop overflows.
let MAX_OVERFLOW_PAGES: Int = 8

/// CPU byte budget for cached RGBA colour glyphs (`colorPixels`) before frame-boundary eviction.
let COLOR_GLYPH_BUDGET: Int = 16 * 1024 * 1024

struct GlyphKey: Sendable, Equatable, Hashable {
    var font: UInt64
    var index: UInt32
    var glyph: UInt32
    var size: UInt32
    var coords: UInt64
    /// The x phase in sixtieths of a pixel (`PHASES`).
    var subpx: UInt8
    /// How far down the mask is drawn, in quarters of a pixel (`GLIDE_PHASES`).
    var subpy: UInt8
    /// The dilation radius in device px, as `Float` bits.
    var dilation: UInt32
    /// The CoreGraphics pipeline's stages (`Smoothing.key`).
    var apple: UInt8
    /// Synthetic oblique, in degrees (`0` for none).
    var skew: UInt8
}

struct IconCacheKey: Sendable, Equatable, Hashable {
    var iconHash: UInt64
    var px: UInt32

    init(_ icon: Icon, _ px: UInt32) {
        var h = KeyHasher()
        h.str(icon.name)
        h.f32(icon.view)
        h.str(icon.body)
        self.iconHash = h.hash
        self.px = px
    }

    init(rawId: UInt64, px: UInt32) {
        self.iconHash = rawId
        self.px = px
    }
}

struct AtlasGlyph: Sendable, Equatable {
    var page: UInt16
    var x: UInt32
    var y: UInt32
    var w: UInt32
    var h: UInt32
    var left: Int32
    var top: Int32
}

enum PlacedMask: Sendable, Equatable {
    case empty
    case placed(AtlasGlyph)
    case unplaced
}

struct Rasterized: Sendable, Equatable {
    var left: Int32
    var top: Int32
    var w: UInt32
    var h: UInt32
}

/// A colour glyph's RGBA image (`GlyphQuad.color`) and its placement around the pen (device px).
struct ColorGlyph: Sendable, Equatable {
    var index: UInt32
    var used: Bool
    var left: Int32
    var top: Int32
    var w: UInt32
    var h: UInt32

    /// The quad for a resting pen at `[x, y]`, rounded at rest, then moved by `glide`
    /// (the image draws filtered).
    func quad(_ x: Float, _ y: Float, _ glide: [Float], _ ink: UInt16, _ byte: UInt32) -> GlyphQuad {
        let gx = glide.count > 0 ? glide[0] : 0.0
        let gy = glide.count > 1 ? glide[1] : 0.0
        let rect: [Float] = [
            x.rounded(.toNearestOrAwayFromZero) + Float(left) + gx,
            y.rounded(.toNearestOrAwayFromZero) - Float(top) + gy,
            Float(w),
            Float(h)
        ]
        return GlyphQuad(rect: rect, uv: [0.0, 0.0], ink: ink, byte: byte, color: index)
    }
}

struct Shelf: Sendable, Equatable {
    var x: UInt32
    var y: UInt32
    var h: UInt32
    var shown: Bool
    var touched: Bool
    var full: Bool
    var age: UInt64
    var liveTexels: UInt32

    static func new(_ age: UInt64) -> Shelf {
        Shelf(x: 1, y: 1, h: 0, shown: false, touched: false, full: false, age: age, liveTexels: 0)
    }

    mutating func reset(_ age: UInt64) {
        self = Self.new(age)
    }

    func nonEmpty() -> Bool {
        x > 1 || y > 1 || h > 0
    }

    mutating func alloc(_ w: UInt32, _ h: UInt32) -> (UInt32, UInt32)? {
        if x + w + 1 > ATLAS_SIZE {
            y += self.h + 1
            x = 1
            self.h = 0
        }
        if y + h + 1 > ATLAS_SIZE {
            full = true
            return nil
        }
        let pos = (x, y)
        x += w + 1
        self.h = max(self.h, h)
        return pos
    }

    mutating func touch(_ texels: UInt32) {
        touched = true
        let (next, overflow) = liveTexels.addingReportingOverflow(texels)
        liveTexels = overflow ? UInt32.max : next
    }

    mutating func endFrame() {
        shown = touched
        touched = false
        liveTexels = 0
    }
}

/// One overflow 2048x2048 shelf page in `Atlas`.
public struct AtlasPage: Sendable {
    public var data: [UInt8]
    /// Rows `[y0, y1)` changed since the last upload.
    public var dirty: (UInt32, UInt32)?
    var shelf: Shelf

    public init() {
        self.data = [UInt8](repeating: 0, count: Int(ATLAS_SIZE * ATLAS_SIZE))
        self.dirty = nil
        self.shelf = Shelf.new(1)
    }

    static func new(_ age: UInt64) -> AtlasPage {
        var p = AtlasPage()
        p.shelf = Shelf.new(age)
        return p
    }
}

/// One glyph to draw: device-pixel rect, atlas origin, brush and source byte (for reveals).
public struct GlyphQuad: Sendable, Equatable {
    public var rect: [Float]
    /// Atlas origin with the page packed into y (`page * ATLAS_SIZE + y`).
    /// Use `atlasPage()` and `atlasUv()` when sampling an atlas page directly.
    public var uv: [Float]
    public var ink: UInt16
    public var byte: UInt32
    /// A colour glyph (emoji) drawn from `TextSystem.colorGlyph` instead of the alpha
    /// atlas: 0 for none, else its index plus one.
    public var color: UInt32

    public init(
        rect: [Float] = [0, 0, 0, 0],
        uv: [Float] = [0, 0],
        ink: UInt16 = 0,
        byte: UInt32 = 0,
        color: UInt32 = 0
    ) {
        self.rect = rect
        self.uv = uv
        self.ink = ink
        self.byte = byte
        self.color = color
    }

    /// Alpha atlas page. Placements remain valid until the next frame begins.
    public func atlasPage() -> Int {
        Int(UInt32(max(uv[1], 0))) / Int(ATLAS_SIZE)
    }

    /// Pixel origin within `atlasPage()`, without the packed page index.
    public func atlasUv() -> [Float] {
        let page = atlasPage()
        return [uv[0], uv[1] - Float(page * Int(ATLAS_SIZE))]
    }
}

/// Shelf-packed greyscale pages for glyph and icon coverage masks.
public struct Atlas: Sendable {
    public var data: [UInt8]
    /// Rows `[y0, y1)` changed since the last upload.
    public var dirty: (UInt32, UInt32)?
    /// `(node_id, signature)` of `El.cache` targets currently resident in the GPU renderer.
    var residentCaches: [UInt64: UInt64]
    /// Secondary and overflow shelf pages (`page >= 1` lives at `pages[page - 1]`).
    var pages: [AtlasPage]
    var resetsCount: UInt64
    var rasterizedCount: UInt64
    var shelf: Shelf
    var clock: UInt64
    var map: [GlyphKey: AtlasGlyph?]
    var icons: [IconCacheKey: AtlasGlyph?]

    public init() {
        self.data = [UInt8](repeating: 0, count: Int(ATLAS_SIZE * ATLAS_SIZE))
        self.dirty = nil
        self.residentCaches = [:]
        self.pages = []
        self.resetsCount = 0
        self.rasterizedCount = 0
        self.shelf = Shelf.new(1)
        self.clock = 1
        self.map = [:]
        self.icons = [:]
    }

    static func new() -> Atlas {
        Atlas()
    }

    /// Marks every row for upload (a new texture, e.g. after the window's format changed).
    public mutating func invalidate() {
        dirty = (0, ATLAS_SIZE)
        for i in pages.indices {
            pages[i].dirty = (0, ATLAS_SIZE)
        }
        residentCaches.removeAll()
    }

    /// Number of allocated 2048x2048 shelf pages (at least 1).
    public func pageCount() -> Int {
        1 + pages.count
    }

    /// Alpha texels for a page returned by `GlyphQuad.atlasPage()`.
    public func pageData(_ page: Int) -> [UInt8]? {
        if page == 0 {
            return data
        }
        let idx = page - 1
        guard idx >= 0 && idx < pages.count else { return nil }
        return pages[idx].data
    }

    /// Number of shelf page resets since the atlas was created.
    public func resets() -> UInt64 {
        resetsCount
    }

    /// Number of glyphs and icons placed into the atlas since creation.
    public func rasterized() -> UInt64 {
        rasterizedCount
    }

    /// Rasterized glyph entries, for tests that bound the atlas.
    public func glyphEntries() -> Int {
        map.count
    }

    private func shelfRef(_ page: Int) -> Shelf {
        page == 0 ? shelf : pages[page - 1].shelf
    }

    mutating func touch(_ page: UInt16, _ texels: UInt32) {
        if page == 0 {
            shelf.touch(texels)
        } else {
            let idx = Int(page) - 1
            if idx >= 0 && idx < pages.count {
                pages[idx].shelf.touch(texels)
            }
        }
    }

    mutating func evictPage(_ page: Int) {
        let p16 = UInt16(page)
        map = map.filter { _, v in
            guard let g = v else { return true }
            return g.page != p16
        }
        icons = icons.filter { _, v in
            guard let g = v else { return true }
            return g.page != p16
        }
        residentCaches.removeAll()
        clock &+= 1
        resetsCount &+= 1
        let age = clock
        if page == 0 {
            dirty = nil
            shelf.reset(age)
        } else if page - 1 >= 0 && page - 1 < pages.count {
            pages[page - 1].dirty = nil
            pages[page - 1].shelf.reset(age)
        }
    }

    mutating func beginFrame(_ pinnedMask: UInt32 = 0) {
        let total = pageCount()
        var totalLive: UInt64 = 0
        for p in 0..<total {
            totalLive += UInt64(shelfRef(p).liveTexels)
        }
        let halfPage = UInt64(ATLAS_SIZE * ATLAS_SIZE / 2)
        let needed = min(max(Int(totalLive / halfPage) + MAX_STEADY_PAGES, MAX_STEADY_PAGES), MAX_OVERFLOW_PAGES)
        var fullCount = 0
        for p in 0..<total where shelfRef(p).full {
            fullCount += 1
        }
        if fullCount >= needed || total > needed {
            let keep = min(needed, total)
            var oldest: (Int, UInt64)? = nil
            for p in 0..<keep {
                let s = shelfRef(p)
                let bit: UInt32 = 1 << UInt32(min(p, 31))
                if s.full && (pinnedMask & bit) == 0 {
                    if oldest == nil || s.age < oldest!.1 {
                        oldest = (p, s.age)
                    }
                }
            }
            if let (victim, _) = oldest {
                evictPage(victim)
            }
            if keep < total {
                for p in keep..<total {
                    let bit: UInt32 = 1 << UInt32(min(p, 31))
                    if (pinnedMask & bit) == 0 && shelfRef(p).nonEmpty() {
                        evictPage(p)
                    }
                }
            }
            while pageCount() > needed {
                let last = pageCount() - 1
                let bit: UInt32 = 1 << UInt32(min(last, 31))
                if (pinnedMask & bit) != 0 || shelfRef(last).nonEmpty() {
                    break
                }
                pages.removeLast()
                let maxP = UInt16(pageCount() - 1)
                let hadOverflowRefs = map.values.contains(where: { $0 != nil && $0!.page > maxP })
                    || icons.values.contains(where: { $0 != nil && $0!.page > maxP })
                if hadOverflowRefs {
                    clock &+= 1
                }
            }
        }
        let afterTotal = pageCount()
        for p in 0..<afterTotal {
            if p == 0 {
                shelf.endFrame()
            } else {
                pages[p - 1].shelf.endFrame()
            }
            let bit: UInt32 = 1 << UInt32(min(p, 31))
            if (pinnedMask & bit) != 0 {
                touch(UInt16(p), 0)
            }
        }
    }

    mutating func alloc(_ w: UInt32, _ h: UInt32) -> (Int, UInt32, UInt32)? {
        if w == 0 || h == 0 || w + 2 > ATLAS_SIZE || h + 2 > ATLAS_SIZE {
            return nil
        }
        let total = pageCount()
        for p in 0..<total {
            if !shelfRef(p).full {
                let pos = (p == 0) ? shelf.alloc(w, h) : pages[p - 1].shelf.alloc(w, h)
                if let (x, y) = pos {
                    return (p, x, y)
                }
            }
        }
        // Try shelf tails on full pages for small glyphs before opening or resetting a page.
        for p in 0..<total {
            let pos = (p == 0) ? shelf.alloc(w, h) : pages[p - 1].shelf.alloc(w, h)
            if let (x, y) = pos {
                return (p, x, y)
            }
        }
        // Recycle an idle page (untouched in both the last frame and this frame so far).
        var idleVictim: (Int, UInt64)? = nil
        for p in 0..<total {
            let s = shelfRef(p)
            if !s.touched && !s.shown && s.nonEmpty() {
                if idleVictim == nil || s.age < idleVictim!.1 {
                    idleVictim = (p, s.age)
                }
            }
        }
        if let (p, _) = idleVictim {
            evictPage(p)
            let pos = (p == 0) ? shelf.alloc(w, h) : pages[p - 1].shelf.alloc(w, h)
            if let (x, y) = pos {
                return (p, x, y)
            }
        }
        // Once we have the steady-state page pair, recycle the oldest page not touched this frame.
        if total >= MAX_STEADY_PAGES {
            var coldVictim: (Int, UInt64)? = nil
            for p in 0..<total {
                let s = shelfRef(p)
                if !s.touched && s.nonEmpty() {
                    if coldVictim == nil || s.age < coldVictim!.1 {
                        coldVictim = (p, s.age)
                    }
                }
            }
            if let (p, _) = coldVictim {
                evictPage(p)
                let pos = (p == 0) ? shelf.alloc(w, h) : pages[p - 1].shelf.alloc(w, h)
                if let (x, y) = pos {
                    return (p, x, y)
                }
            }
        }
        if total < MAX_OVERFLOW_PAGES {
            clock &+= 1
            var page = AtlasPage.new(clock)
            if let (x, y) = page.shelf.alloc(w, h) {
                pages.append(page)
                return (pages.count, x, y)
            }
        }
        return nil
    }

    mutating func put(_ w: UInt32, _ h: UInt32, _ src: [UInt8], _ left: Int32, _ top: Int32) -> AtlasGlyph? {
        guard let (page, ax, ay) = alloc(w, h) else { return nil }
        let stride = Int(ATLAS_SIZE)
        let writeInto = { (buf: inout [UInt8], dirtySlot: inout (UInt32, UInt32)?) in
            let x0 = Int(ax - 1)
            let x1 = Int(ax + w + 1)
            let topRow = Int(ay - 1) * stride
            for k in x0..<x1 { buf[topRow + k] = 0 }
            for row in 0..<Int(h) {
                let line = Int(ay + UInt32(row)) * stride
                buf[line + x0] = 0
                let srcBase = row * Int(w)
                let dstBase = line + Int(ax)
                for col in 0..<Int(w) {
                    buf[dstBase + col] = src[srcBase + col]
                }
                buf[line + Int(ax + w)] = 0
            }
            let botRow = Int(ay + h) * stride
            for k in x0..<x1 { buf[botRow + k] = 0 }
            let y0 = ay - 1
            let y1 = ay + h + 1
            if let prev = dirtySlot {
                dirtySlot = (min(prev.0, y0), max(prev.1, y1))
            } else {
                dirtySlot = (y0, y1)
            }
        }
        if page == 0 {
            writeInto(&data, &dirty)
        } else {
            var pageDirty = pages[page - 1].dirty
            writeInto(&pages[page - 1].data, &pageDirty)
            pages[page - 1].dirty = pageDirty
        }
        rasterizedCount &+= 1
        touch(UInt16(page), w * h)
        return AtlasGlyph(page: UInt16(page), x: ax, y: ay, w: w, h: h, left: left, top: top)
    }
}
