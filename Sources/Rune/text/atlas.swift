// Ported from: crates/rune/src/text/atlas.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

//! The glyph atlas: shelf-packed greyscale pages of glyph and icon masks, aged and evicted by
//! use, and the quads that sample them.

public let ATLAS_SIZE: UInt32 = 2048

public struct AtlasPage: Sendable {
    public var data: [UInt8]
    /// Rows `[y0, y1)` changed since the last upload.
    public var dirty: (UInt32, UInt32)?

    public init() {
        self.data = [UInt8](repeating: 0, count: Int(ATLAS_SIZE * ATLAS_SIZE))
        self.dirty = nil
    }
}

/// One glyph to draw: device-pixel rect, atlas origin, brush and source byte (for reveals).
public struct GlyphQuad: Sendable, Equatable {
    public var rect: [Float]
    /// Atlas origin with the page packed into y (`page * ATLAS_SIZE + y`).
    public var uv: [Float]
    public var ink: UInt16
    public var byte: UInt32
    /// A colour glyph (emoji) drawn from `TextSystem.colorGlyph` instead of the alpha atlas: 0 for none, else index + 1.
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

    /// Alpha atlas page.
    public func atlasPage() -> Int {
        Int(uv[1]) / Int(ATLAS_SIZE)
    }

    /// Pixel origin within `atlasPage()`, without the packed page index.
    public func atlasUv() -> [Float] {
        let page = atlasPage()
        return [uv[0], uv[1] - Float(page * Int(ATLAS_SIZE))]
    }
}

public struct Atlas: Sendable {
    public var data: [UInt8]
    public var dirty: (UInt32, UInt32)?
    var residentCaches: [UInt64: UInt64]
    var pages: [AtlasPage]
    var resetsCount: UInt64
    var rasterizedCount: UInt64
    private var shelfX: UInt32 = 1
    private var shelfY: UInt32 = 1
    private var shelfH: UInt32 = 0

    public init() {
        self.data = [UInt8](repeating: 0, count: Int(ATLAS_SIZE * ATLAS_SIZE))
        self.dirty = nil
        self.residentCaches = [:]
        self.pages = []
        self.resetsCount = 0
        self.rasterizedCount = 0
    }

    public mutating func invalidate() {
        dirty = (0, ATLAS_SIZE)
        for i in pages.indices {
            pages[i].dirty = (0, ATLAS_SIZE)
        }
        residentCaches.removeAll()
    }

    public func pageCount() -> Int {
        1 + pages.count
    }

    public func pageData(_ page: Int) -> [UInt8]? {
        if page == 0 { return data }
        let idx = page - 1
        guard idx >= 0 && idx < pages.count else { return nil }
        return pages[idx].data
    }

    public func resets() -> UInt64 {
        resetsCount
    }

    public func rasterized() -> UInt64 {
        rasterizedCount
    }

    mutating func beginFrame(_ pinnedMask: UInt32 = 0) {
        _ = pinnedMask
    }
}
