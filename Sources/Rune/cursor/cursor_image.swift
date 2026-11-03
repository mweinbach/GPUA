// Ported from: crates/rune/src/cursor/image.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif

/// Pixels per point in a ``CursorImage`` PNG.
internal let CURSOR_SOURCE_SCALE: Float = 2.0

/// The largest side a cursor PNG may have, in pixels.
internal let CURSOR_MAX_SIDE: UInt32 = 256
internal let CURSOR_MAX_ENTRIES: Int = 32
internal let CURSOR_MAX_BYTES: Int = 8 << 20

/// A cursor image at `scale` pixels per point: straight-alpha RGBA, hot spot in pixels.
internal struct DecodedCursorImage: Sendable, Equatable {
    internal var rgba: [UInt8]
    internal var width: UInt32
    internal var height: UInt32
    internal var hot: [UInt32]
    internal var scale: Float

    internal init(rgba: [UInt8], width: UInt32, height: UInt32, hot: [UInt32], scale: Float) {
        self.rgba = rgba
        self.width = width
        self.height = height
        self.hot = hot
        self.scale = scale
    }
}

/// Decodes `image` and resamples it to `scale` pixels per point (the OS cursor's own scale),
/// clamping its hot spot into the result.
internal func decodeCursorImage(_ image: CursorImage, _ scale: Float) -> Result<DecodedCursorImage, ImageError> {
    let srcW: UInt32
    let srcH: UInt32
    let srcRgba: [UInt8]

    if let pngBytes = image.pngBytes {
        switch RunePngCodec.decodeRgba8(pngBytes) {
        case .success(let (w, h, rgba)):
            srcW = w
            srcH = h
            srcRgba = rgba
        case .failure(let err):
            return .failure(err)
        }
    } else {
        guard image.width > 0, image.height > 0,
              image.rgba.count == Int(image.width) * Int(image.height) * 4 else {
            return .failure(ImageError("invalid raw RGBA cursor dimensions"))
        }
        srcW = image.width
        srcH = image.height
        srcRgba = image.rgba
    }

    if srcW > CURSOR_MAX_SIDE || srcH > CURSOR_MAX_SIDE {
        return .failure(ImageError("\(srcW)×\(srcH) px is over the \(CURSOR_MAX_SIDE) px limit"))
    }

    let resolvedScale = (scale.isFinite && scale > 0.0) ? scale : CURSOR_SOURCE_SCALE
    let k = resolvedScale / CURSOR_SOURCE_SCALE
    let outW = max(1, UInt32((Float(srcW) * k).rounded()))
    let outH = max(1, UInt32((Float(srcH) * k).rounded()))
    let rgba: [UInt8]
    if outW == srcW && outH == srcH {
        rgba = srcRgba
    } else {
        rgba = resamplePremultipliedTriangle(srcRgba, srcW: srcW, srcH: srcH, dstW: outW, dstH: outH)
    }

    let hotSrc = image.hot()
    let hx = clampCursorHot(hotSrc[0], resolvedScale, outW)
    let hy = clampCursorHot(hotSrc[1], resolvedScale, outH)
    return .success(DecodedCursorImage(rgba: rgba, width: outW, height: outH, hot: [hx, hy], scale: resolvedScale))
}

private func clampCursorHot(_ point: Float, _ scale: Float, _ side: UInt32) -> UInt32 {
    let scaled = (point * scale).rounded(.down)
    if scaled.isNaN || scaled <= 0.0 {
        return 0
    }
    if !scaled.isFinite || scaled >= Float(side - 1) {
        return side - 1
    }
    return min(UInt32(scaled), side - 1)
}

/// Resizes in premultiplied alpha using separable triangle (tent) filtering so transparent
/// pixels' colour doesn't bleed into edges.
internal func resamplePremultipliedTriangle(
    _ src: [UInt8],
    srcW: UInt32,
    srcH: UInt32,
    dstW: UInt32,
    dstH: UInt32
) -> [UInt8] {
    let sw = Int(srcW)
    let sh = Int(srcH)
    let dw = Int(dstW)
    let dh = Int(dstH)

    // Premultiply straight RGBA8 in [0, 255] matching `(c * a + 127) / 255`.
    var premul = [UInt8](repeating: 0, count: sw * sh * 4)
    for i in stride(from: 0, to: premul.count, by: 4) {
        let a = UInt32(src[i + 3])
        premul[i] = UInt8((UInt32(src[i]) * a + 127) / 255)
        premul[i + 1] = UInt8((UInt32(src[i + 1]) * a + 127) / 255)
        premul[i + 2] = UInt8((UInt32(src[i + 2]) * a + 127) / 255)
        premul[i + 3] = UInt8(a)
    }

    // Horizontal pass: sw x sh -> dw x sh (Float accumulators)
    var horiz = [Float](repeating: 0, count: dw * sh * 4)
    let xRatio = Float(sw) / Float(dw)
    let xSupport = max(1.0, xRatio)
    for dx in 0..<dw {
        let center = (Float(dx) + 0.5) * xRatio - 0.5
        let left = max(0, Int((center - xSupport).rounded(.down)))
        let right = min(sw - 1, Int((center + xSupport).rounded(.up)))
        var weights = [(Int, Float)]()
        var wSum: Float = 0
        if left <= right {
            for sx in left...right {
                let dist = abs((Float(sx) - center) / xSupport)
                if dist < 1.0 {
                    let w = 1.0 - dist
                    weights.append((sx, w))
                    wSum += w
                }
            }
        }
        if wSum == 0 {
            let nearest = min(max(0, Int(center.rounded())), sw - 1)
            weights = [(nearest, 1.0)]
            wSum = 1.0
        }
        for sy in 0..<sh {
            var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
            for (sx, w) in weights {
                let idx = (sy * sw + sx) * 4
                r += Float(premul[idx]) * w
                g += Float(premul[idx + 1]) * w
                b += Float(premul[idx + 2]) * w
                a += Float(premul[idx + 3]) * w
            }
            let inv = 1.0 / wSum
            let outIdx = (sy * dw + dx) * 4
            horiz[outIdx] = r * inv
            horiz[outIdx + 1] = g * inv
            horiz[outIdx + 2] = b * inv
            horiz[outIdx + 3] = a * inv
        }
    }

    // Vertical pass: dw x sh -> dw x dh, then unpremultiply
    var out = [UInt8](repeating: 0, count: dw * dh * 4)
    let yRatio = Float(sh) / Float(dh)
    let ySupport = max(1.0, yRatio)
    for dy in 0..<dh {
        let center = (Float(dy) + 0.5) * yRatio - 0.5
        let top = max(0, Int((center - ySupport).rounded(.down)))
        let bottom = min(sh - 1, Int((center + ySupport).rounded(.up)))
        var weights = [(Int, Float)]()
        var wSum: Float = 0
        if top <= bottom {
            for sy in top...bottom {
                let dist = abs((Float(sy) - center) / ySupport)
                if dist < 1.0 {
                    let w = 1.0 - dist
                    weights.append((sy, w))
                    wSum += w
                }
            }
        }
        if wSum == 0 {
            let nearest = min(max(0, Int(center.rounded())), sh - 1)
            weights = [(nearest, 1.0)]
            wSum = 1.0
        }
        let inv = 1.0 / wSum
        for dx in 0..<dw {
            var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
            for (sy, w) in weights {
                let idx = (sy * dw + dx) * 4
                r += horiz[idx] * w
                g += horiz[idx + 1] * w
                b += horiz[idx + 2] * w
                a += horiz[idx + 3] * w
            }
            let pr = UInt32(min(255.0, max(0.0, (r * inv).rounded())))
            let pg = UInt32(min(255.0, max(0.0, (g * inv).rounded())))
            let pb = UInt32(min(255.0, max(0.0, (b * inv).rounded())))
            let pa = UInt32(min(255.0, max(0.0, (a * inv).rounded())))
            let outIdx = (dy * dw + dx) * 4
            if pa == 0 {
                out[outIdx] = 0
                out[outIdx + 1] = 0
                out[outIdx + 2] = 0
                out[outIdx + 3] = 0
            } else {
                out[outIdx] = UInt8(min(255, (pr * 255 + pa / 2) / pa))
                out[outIdx + 1] = UInt8(min(255, (pg * 255 + pa / 2) / pa))
                out[outIdx + 2] = UInt8(min(255, (pb * 255 + pa / 2) / pa))
                out[outIdx + 3] = UInt8(pa)
            }
        }
    }
    return out
}

internal struct CursorCacheEntry<T> {
    internal var keyImage: CursorImage
    internal var keyScaleBits: UInt32
    /// `nil` when the image didn't decode or the OS refused it: the arrow shows.
    internal var cursor: T?
    internal var bytes: Int
}

/// OS cursors made from cursor images, oldest first, bounded in entries and decoded bytes.
/// A failure is kept too, so it's decoded and logged once.
internal struct ImageCursors<T> {
    internal var entries: [CursorCacheEntry<T>] = []
    internal var bytes: Int = 0
    internal var decodes: Int = 0

    internal init() {}

    /// Non-nil once `image` at `scale` has been made: `.some(cursor)` or `.some(nil)` if it failed.
    internal mutating func cached(_ image: CursorImage, _ scale: Float) -> T?? {
        let scaleBits = scale.bitPattern
        guard let idx = entries.firstIndex(where: { $0.keyScaleBits == scaleBits && $0.keyImage == image }) else {
            return nil
        }
        let entry = entries.remove(at: idx)
        let cursor = entry.cursor
        entries.append(entry)
        return .some(cursor)
    }

    /// The OS cursor for `image` at `scale`, decoded and handed to `make` the first time.
    internal mutating func get(
        _ image: CursorImage,
        _ scale: Float,
        _ make: (DecodedCursorImage) -> Result<T, ImageError>
    ) -> T? {
        if let hit = cached(image, scale) {
            return hit
        }
        decodes += 1
        let cursor: T?
        let entryBytes: Int
        switch decodeCursorImage(image, scale) {
        case .success(let decoded):
            switch make(decoded) {
            case .success(let built):
                cursor = built
                entryBytes = decoded.rgba.count
            case .failure(let problem):
                logCursorProblem(image, problem.message)
                cursor = nil
                entryBytes = 0
            }
        case .failure(let problem):
            logCursorProblem(image, problem.message)
            cursor = nil
            entryBytes = 0
        }
        bytes += entryBytes
        entries.append(CursorCacheEntry(
            keyImage: image,
            keyScaleBits: scale.bitPattern,
            cursor: cursor,
            bytes: entryBytes
        ))
        while entries.count > 1 && (entries.count > CURSOR_MAX_ENTRIES || bytes > CURSOR_MAX_BYTES) {
            let evicted = entries.removeFirst()
            bytes -= evicted.bytes
        }
        return cursor
    }
}

private func logCursorProblem(_ image: CursorImage, _ problem: String) {
    #if !os(WASI)
    let msg = "rune: cursor image (\(image.bytes().count) bytes) shows the arrow instead: \(problem)\n"
    FileHandle.standardError.write(Data(msg.utf8))
    #endif
}
