// Ported from: crates/rune/src/pixels.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Pixel buffers an app replaces at will (a CPU-shaded HUD frame, a video frame), drawn by
//! `El.pixels`. Each runtime keeps a CPU-side RGBA atlas the renderer uploads by dirty rows.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

public let IMAGE_ATLAS_SIZE: UInt32 = 1024

struct DecodedMipLevel: Sendable {
    var width: UInt32
    var height: UInt32
    var pixels: [UInt8]
}

final class DecodedImageMips: Sendable {
    let mips: [DecodedMipLevel]
    init(_ mips: [DecodedMipLevel]) {
        self.mips = mips
    }
}

private struct PixelsFrame {
    var width: UInt32 = 0
    var height: UInt32 = 0
    var rgba: [UInt8] = []
    var generation: UInt64 = 0
    var mips: DecodedImageMips? = nil
}

private let pixelsIdLock = LiveLock()
// PORT NOTE: Guarded by `pixelsIdLock` for unique monotonic `Pixels` ids across threads.
nonisolated(unsafe) private var nextPixelsId: UInt64 = 1

/// A replaceable RGBA image, shared between the producer and the view.
// PORT NOTE: Synchronized with `LiveLock` so `Pixels.set` is safe from any producer thread.
public final class Pixels: @unchecked Sendable, CustomDebugStringConvertible {
    public let id: UInt64
    private let lock = LiveLock()
    private var frame = PixelsFrame()
    let source: LiveSource

    public init() {
        self.id = pixelsIdLock.withLock {
            let v = nextPixelsId
            nextPixelsId &+= 1
            return v
        }
        self.source = LiveSource(.zero)
    }

    public static func new() -> Pixels {
        Pixels()
    }

    public var debugDescription: String {
        lock.withLock {
            "Pixels(\(id), \(frame.width)x\(frame.height), gen \(frame.generation))"
        }
    }

    /// Replaces the image: `rgba` is `width * height * 4` straight-alpha sRGB pixels, rows top first.
    public func set(_ width: UInt32, _ height: UInt32, _ rgba: [UInt8]) {
        let expected = Int(width) * Int(height) * 4
        precondition(rgba.count == expected, "rgba must hold width * height * 4 bytes")
        lock.withLock {
            frame.width = width
            frame.height = height
            frame.rgba = rgba
            frame.generation &+= 1
            frame.mips = nil
        }
        source.notify()
    }

    func setMips(_ mips: DecodedImageMips) {
        guard let first = mips.mips.first else { return }
        lock.withLock {
            frame.width = first.width
            frame.height = first.height
            frame.rgba.removeAll(keepingCapacity: false)
            frame.mips = mips
            frame.generation &+= 1
        }
        source.notify()
    }

    public func size() -> (UInt32, UInt32) {
        lock.withLock { (frame.width, frame.height) }
    }

    public func rgba() -> [UInt8] {
        lock.withLock { frame.rgba }
    }

    fileprivate func withFrame<R>(_ body: (PixelsFrame) -> R) -> R {
        lock.withLock { body(frame) }
    }
}

public struct ImagePage: Sendable {
    public var width: UInt32
    public var height: UInt32
    public var data: [UInt8]
    /// Rows `(y0, y1)` changed since the last upload.
    public var dirty: (UInt32, UInt32)?
    var shelfX: UInt32 = 0
    var shelfY: UInt32 = 0
    var shelfH: UInt32 = 0
    var shown: Bool = false
    var touched: Bool = false

    init(_ w: UInt32, _ h: UInt32) {
        let pageW = (w > IMAGE_ATLAS_SIZE || h > IMAGE_ATLAS_SIZE) ? w : IMAGE_ATLAS_SIZE
        let pageH = (w > IMAGE_ATLAS_SIZE || h > IMAGE_ATLAS_SIZE) ? h : IMAGE_ATLAS_SIZE
        self.width = pageW
        self.height = pageH
        self.data = [UInt8](repeating: 0, count: Int(pageW) * Int(pageH) * 4)
        self.dirty = nil
    }

    mutating func allocate(_ w: UInt32, _ h: UInt32) -> (UInt32, UInt32)? {
        if w > width || h > height { return nil }
        if shelfX + w > width {
            shelfY += shelfH
            shelfX = 0
            shelfH = 0
        }
        if shelfY + h > height {
            return nil
        }
        let at = (shelfX, shelfY)
        shelfX += w
        shelfH = max(shelfH, h)
        return at
    }
}

public struct PlacedImage: Sendable, Equatable {
    public var rect: [UInt32]
    public var page: Int
    public var premultiplied: Bool

    public init(rect: [UInt32], page: Int, premultiplied: Bool) {
        self.rect = rect
        self.page = page
        self.premultiplied = premultiplied
    }
}

private struct AtlasSlotKey: Hashable {
    let id: UInt64
    let level: Int
}

private struct AtlasSlot {
    var page: Int
    var x: UInt32
    var y: UInt32
    var w: UInt32
    var h: UInt32
    var generation: UInt64
}

/// CPU-side RGBA shelf atlas for ``Pixels`` images.
public struct ImageAtlas: Sendable {
    public var pages: [ImagePage] = []
    private var slots: [AtlasSlotKey: AtlasSlot] = [:]
    var copies: UInt64 = 0

    public init() {}

    public mutating func place(_ pixels: Pixels, _ drawn: [Float]) -> PlacedImage? {
        pixels.withFrame { frame in
            var w = frame.width
            var h = frame.height
            if w == 0 || h == 0 || w > 8192 || h > 8192 {
                return nil
            }
            var level = 0
            let bytes: [UInt8]
            let isPremul: Bool
            if let decoded = frame.mips {
                let targetW = min(max(drawn[0], 1.0), Float(frame.width))
                let targetH = min(max(drawn[1], 1.0), Float(frame.height))
                while level + 1 < decoded.mips.count {
                    let next = decoded.mips[level + 1]
                    if Float(next.width) < targetW || Float(next.height) < targetH {
                        break
                    }
                    level += 1
                }
                let mip = decoded.mips[level]
                w = mip.width
                h = mip.height
                bytes = mip.pixels
                isPremul = true
            } else {
                bytes = frame.rgba
                isPremul = false
            }

            let key = AtlasSlotKey(id: pixels.id, level: level)
            if let existing = slots[key], existing.w != w || existing.h != h {
                slots.removeValue(forKey: key)
            }
            if slots[key] == nil {
                let (pageIdx, ax, ay) = allocateSlot(w, h)
                slots[key] = AtlasSlot(page: pageIdx, x: ax, y: ay, w: w, h: h, generation: 0)
            }
            guard var slot = slots[key] else { return nil }
            pages[slot.page].touched = true
            if slot.generation != frame.generation {
                slot.generation = frame.generation
                slots[key] = slot
                copies &+= 1
                let rowStride = Int(pages[slot.page].width) * 4
                let copyBytes = Int(w) * 4
                for line in 0..<Int(h) {
                    let dst = (Int(slot.y) + line) * rowStride + Int(slot.x) * 4
                    let src = line * copyBytes
                    pages[slot.page].data.replaceSubrange(dst..<(dst + copyBytes), with: bytes[src..<(src + copyBytes)])
                }
                let y0 = slot.y
                let y1 = slot.y + h
                if let old = pages[slot.page].dirty {
                    pages[slot.page].dirty = (min(old.0, y0), max(old.1, y1))
                } else {
                    pages[slot.page].dirty = (y0, y1)
                }
            }
            return PlacedImage(rect: [slot.x, slot.y, w, h], page: slot.page, premultiplied: isPremul)
        }
    }

    public mutating func endFrame() {
        let firstKept = pages.first.map { $0.width <= IMAGE_ATLAS_SIZE && $0.height <= IMAGE_ATLAS_SIZE } ?? false
        let currentPages = pages
        slots = slots.filter { _, s in
            currentPages[s.page].touched || (s.page == 0 && firstKept)
        }
        for i in pages.indices {
            pages[i].shown = pages[i].touched
            pages[i].touched = false
            if !slots.values.contains(where: { $0.page == i }) {
                pages[i].shelfX = 0
                pages[i].shelfY = 0
                pages[i].shelfH = 0
                pages[i].dirty = nil
                if pages[i].width > IMAGE_ATLAS_SIZE || pages[i].height > IMAGE_ATLAS_SIZE {
                    pages[i].data = []
                }
            }
        }
        let keep = (slots.values.map { $0.page + 1 }.max()) ?? 0
        if pages.count > keep {
            pages.removeSubrange(keep..<pages.count)
        }
    }

    public mutating func invalidate() {
        for i in pages.indices {
            pages[i].dirty = (0, pages[i].height)
        }
    }

    private mutating func allocateSlot(_ w: UInt32, _ h: UInt32) -> (Int, UInt32, UInt32) {
        for i in pages.indices {
            if pages[i].data.isEmpty {
                pages[i] = ImagePage(w, h)
            }
            if let (x, y) = pages[i].allocate(w, h) {
                return (i, x, y)
            }
        }
        if w <= IMAGE_ATLAS_SIZE && h <= IMAGE_ATLAS_SIZE {
            if let idleIdx = pages.firstIndex(where: {
                !$0.shown && !$0.touched && $0.width <= IMAGE_ATLAS_SIZE && $0.height <= IMAGE_ATLAS_SIZE && ($0.shelfY + $0.shelfH > 0)
            }) {
                slots = slots.filter { $0.value.page != idleIdx }
                pages[idleIdx].shelfX = 0
                pages[idleIdx].shelfY = 0
                pages[idleIdx].shelfH = 0
                let (x, y) = pages[idleIdx].allocate(w, h)!
                return (idleIdx, x, y)
            }
        }
        var page = ImagePage(w, h)
        let (x, y) = page.allocate(w, h)!
        pages.append(page)
        return (pages.count - 1, x, y)
    }
}

func fitImageRect(
    _ fit: SurfaceFit?,
    _ place: SurfacePlace,
    _ rect: [Float],
    _ size: (UInt32, UInt32),
    _ snapWeight: Float = 1.0
) -> ([Float], [Float]) {
    let whole: [Float] = [0.0, 0.0, 1.0, 1.0]
    let x = rect[0], y = rect[1], w = rect[2], h = rect[3]
    let iw = Float(size.0), ih = Float(size.1)
    guard let fit, iw > 0.0, ih > 0.0, w > 0.0, h > 0.0 else {
        return (rect, whole)
    }
    let share = place.share()
    let kx = share[0], ky = share[1]
    let u: Float
    if abs(w - w.rounded()) < 1.0 / 512.0 && abs(h - h.rounded()) < 1.0 / 512.0 {
        u = min(max(snapWeight, 0.0), 1.0)
    } else {
        u = 0.0
    }
    func blend(_ exact: [Float], _ snapped: [Float]) -> [Float] {
        if u <= 0.0 { return exact }
        if u >= 1.0 { return snapped }
        return (0..<4).map { exact[$0] + (snapped[$0] - exact[$0]) * u }
    }
    func windowSpan(_ span: Float, _ s: Float) -> (Float, Float) {
        if s == 0.5 { return ((1.0 - span) * 0.5, (1.0 + span) * 0.5) }
        let a = (1.0 - span) * s
        return (a, a + span)
    }
    if place.unscaled {
        let dw = min(iw, w), dh = min(ih, h)
        let (x0, x1) = windowSpan(dw / iw, kx)
        let (y0, y1) = windowSpan(dh / ih, ky)
        let exact: [Float] = [x + (w - dw) * kx, y + (h - dh) * ky, dw, dh]
        let snapped: [Float] = [x + ((w - dw) * kx).rounded(), y + ((h - dh) * ky).rounded(), dw, dh]
        return (blend(exact, snapped), [x0, y0, x1, y1])
    }
    if fit == .fit {
        let k = min(w / iw, h / ih)
        let dw = min(max(iw * k, 1.0), w)
        let dh = min(max(ih * k, 1.0), h)
        let exact: [Float] = [x + (w - dw) * kx, y + (h - dh) * ky, dw, dh]
        if u <= 0.0 { return (exact, whole) }
        let sw = min(max((iw * k).rounded(), 1.0), w)
        let sh = min(max((ih * k).rounded(), 1.0), h)
        let snapped: [Float] = [x + ((w - sw) * kx).rounded(), y + ((h - sh) * ky).rounded(), sw, sh]
        return (blend(exact, snapped), whole)
    }
    let k = max(w / iw, h / ih)
    let (x0, x1) = windowSpan(w / (iw * k), kx)
    let (y0, y1) = windowSpan(h / (ih * k), ky)
    return (rect, [x0, y0, x1, y1])
}
