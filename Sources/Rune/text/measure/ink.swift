// Ported from: crates/rune/src/text/measure/ink.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Where text's ink sits inside its box: 8x oversampled glyph coverage bounds and centre of mass
//! so views (e.g. keycaps centering `↵`, `⇥`, `⌘`) can optically centre what is actually drawn.

#if !os(WASI)
import Foundation
#endif

/// Rasterizing at 8x puts every measurement within 1/8 pt.
private let OVERSAMPLE: Float = 8.0
/// Inks kept per thread, and bytes of their entries and text, before the oldest go.
let INK_MAX_ENTRIES: Int = 1024
let INK_MAX_BYTES: Int = 256 << 10

/// Where a text's ink sits, in points from the top-left of its box (the size `measure` gives).
public struct TextInk: Sendable, Equatable {
    /// The ink's bounds as `[x, y, w, h]`.
    public var bounds: [Float]
    /// The ink's centre of mass, weighting each pixel by its coverage.
    public var mass: [Float]

    public init(bounds: [Float], mass: [Float]) {
        self.bounds = bounds
        self.mass = mass
    }

    // PORT NOTE: Preserves Spine's rectangle-corner initializer and computed properties alongside
    // upstream's canonical `bounds: [x, y, w, h]` and `mass: [cx, cy]`.
    public init(x0: Float = 0, y0: Float = 0, x1: Float = 0, y1: Float = 0) {
        let w = max(0, x1 - x0)
        let h = max(0, y1 - y0)
        self.bounds = [x0, y0, w, h]
        self.mass = [x0 + w * 0.5, y0 + h * 0.5]
    }

    public var x0: Float { bounds.count > 0 ? bounds[0] : 0 }
    public var y0: Float { bounds.count > 1 ? bounds[1] : 0 }
    public var x1: Float { (bounds.count > 2) ? (bounds[0] + bounds[2]) : 0 }
    public var y1: Float { (bounds.count > 3) ? (bounds[1] + bounds[3]) : 0 }

    /// The middle of the ink's bounds.
    public func centre() -> [Float] {
        let x = bounds.count > 0 ? bounds[0] : 0
        let y = bounds.count > 1 ? bounds[1] : 0
        let w = bounds.count > 2 ? bounds[2] : 0
        let h = bounds.count > 3 ? bounds[3] : 0
        return [x + w * 0.5, y + h * 0.5]
    }

    /// `pull` of the way from the bounds' centre to the centre of mass (~0.3 suits keyboard symbols).
    public func optical(_ pull: Float) -> [Float] {
        let c = centre()
        let mx = mass.count > 0 ? mass[0] : c[0]
        let my = mass.count > 1 ? mass[1] : c[1]
        return [c[0] + (mx - c[0]) * pull, c[1] + (my - c[1]) * pull]
    }
}

struct InkCacheEntry {
    var text: String
    var style: TextStyle
    var ink: TextInk?

    func byteCost() -> Int {
        96 + text.utf8.count
    }
}

final class ThreadInkCache {
    var entries: [UInt64: InkCacheEntry] = [:]
    var order: [UInt64] = []
    var orderHead: Int = 0
    var bytes: Int = 0
    var epoch: UInt64 = 0

    var activeOrderCount: Int {
        max(0, order.count - orderHead)
    }

    static func key(_ text: String, _ style: TextStyle) -> UInt64 {
        var h = KeyHasher()
        h.str(text)
        h.style(style)
        return h.hash
    }

    func reset(epoch: UInt64) {
        entries.removeAll()
        order.removeAll()
        orderHead = 0
        bytes = 0
        self.epoch = epoch
    }

    func get(_ k: UInt64, _ text: String, _ style: TextStyle) -> TextInk?? {
        guard let e = entries[k], e.text == text && e.style == style else { return nil }
        return .some(e.ink)
    }

    func insert(_ k: UInt64, _ text: String, _ style: TextStyle, _ ink: TextInk?) {
        let entry = InkCacheEntry(text: text, style: style, ink: ink)
        let cost = entry.byteCost()
        if cost > INK_MAX_BYTES {
            return
        }
        bytes += cost
        if let old = entries.updateValue(entry, forKey: k) {
            bytes = max(0, bytes - old.byteCost())
        } else {
            order.append(k)
        }
        while entries.count > INK_MAX_ENTRIES || bytes > INK_MAX_BYTES {
            guard orderHead < order.count else { break }
            let oldest = order[orderHead]
            orderHead += 1
            if let old = entries.removeValue(forKey: oldest) {
                bytes = max(0, bytes - old.byteCost())
            }
        }
        if orderHead > 512 && orderHead * 2 >= order.count {
            order.removeFirst(orderHead)
            orderHead = 0
        }
    }
}

#if !os(WASI)
private let inkCacheThreadKey = "dev.gpua.rune.text.ink_cache"

private func currentInkCache() -> ThreadInkCache {
    let dict = Thread.current.threadDictionary
    if let existing = dict[inkCacheThreadKey] as? ThreadInkCache {
        return existing
    }
    let created = ThreadInkCache()
    dict[inkCacheThreadKey] = created
    return created
}
#else
// PORT NOTE: WASI is single-threaded; thread-local ink cache lives in a process-local box.
nonisolated(unsafe) private let wasiInkCache = ThreadInkCache()

private func currentInkCache() -> ThreadInkCache {
    wasiInkCache
}
#endif

private struct InkAcc {
    var minX: Float = 0
    var minY: Float = 0
    var maxX: Float = 0
    var maxY: Float = 0
    var sumX: Float = 0
    var sumY: Float = 0
    var weight: Float = 0

    mutating func add(_ x: Float, _ y: Float, _ a: Float) {
        if weight == 0.0 {
            minX = x
            minY = y
            maxX = x + 1.0
            maxY = y + 1.0
        } else {
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x + 1.0)
            maxY = max(maxY, y + 1.0)
        }
        sumX += (x + 0.5) * a
        sumY += (y + 0.5) * a
        weight += a
    }

    func done() -> TextInk? {
        guard weight > 0.0 else { return nil }
        let k = OVERSAMPLE
        return TextInk(
            bounds: [minX / k, minY / k, (maxX - minX) / k, (maxY - minY) / k],
            mass: [sumX / weight / k, sumY / weight / k]
        )
    }
}

/// Where `text` set in `style` puts its ink, or `nil` when it draws nothing (spaces, empty).
/// Cached per text and style for the thread; the first call costs one shaping pass and an 8x raster.
public func ink(_ text: String, _ style: TextStyle) -> TextInk? {
    let k = ThreadInkCache.key(text, style)
    let ep = fontEpoch()
    let cache = currentInkCache()
    if cache.epoch != ep {
        cache.reset(epoch: ep)
    }
    if let hit = cache.get(k, text, style) {
        return hit
    }

    let found: TextInk? = withMeasureText { t in
        let layout = t.layoutRich(text, [], style, OVERSAMPLE, nil)
        var acc = InkAcc()
        for line in layout.lines() {
            for item in line.items() {
                guard case .glyphRun(let run) = item else { continue }
                let face = run.font
                let fontSize = run.fontSize
                let baseline = run.baseline()
                var x = run.offset()
                for g in run.glyphs() {
                    let penX = x + g.x
                    let penY = baseline + g.y
                    let fracX = penX - penX.rounded(.down)
                    if let (buf, stride, pl) = t.rasterizeRawInkMask(
                        font: face,
                        glyph: g.id,
                        ppem: fontSize,
                        subpixelX: fracX
                    ) {
                        let left = penX.rounded(.down) + Float(pl.left)
                        let top = penY.rounded(.toNearestOrAwayFromZero) - Float(pl.top)
                        let w = Int(pl.w)
                        let h = Int(pl.h)
                        for row in 0..<h {
                            for col in 0..<w {
                                let idx = (row * w + col) * stride + (stride - 1)
                                if idx < buf.count {
                                    let a = Float(buf[idx]) / 255.0
                                    if a > 0.0 {
                                        acc.add(left + Float(col), top + Float(row), a)
                                    }
                                }
                            }
                        }
                    }
                    x += g.advance
                }
            }
        }
        return acc.done()
    }

    cache.insert(k, text, style, found)
    return found
}
