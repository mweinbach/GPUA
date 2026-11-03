// Ported from: crates/rune/src/desktop/composite.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Virtual desktop compositing: window shadows, rounded corners, backdrop blur, and capture exclusion (`crates/rune/src/desktop/composite.rs`).

#if canImport(Darwin)
import Darwin
import Foundation
import ImageIO
import CoreGraphics
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

/// Key-window drop shadow `(blurSigma, yOffset, opacity)` in points (`crates/rune/src/desktop/composite.rs`).
let KEY_SHADOW: (Float, Float, Float) = (14.0, 14.0, 0.5)
/// Inactive-window drop shadow `(blurSigma, yOffset, opacity)` in points.
let SHADOW: (Float, Float, Float) = (6.0, 5.0, 0.32)
/// Downsample factor for desktop backdrop blur (`4`).
let DOWN: UInt32 = 4
/// Largest backdrop image, in pixels per side, decoded (`16384`).
let MAX_BACKDROP: UInt32 = 16384

struct DesktopUniform: Sendable, Equatable {
    var desktopSize: [Float]
    var slotRect: [Float]
    var cornerRadius: Float
    var shadowAlpha: Float
    var shadowSigma: Float
    var shadowOffsetY: Float
}

/// One window or overlay surface composited onto the virtual desktop (`crates/rune/src/desktop/composite.rs`).
struct DesktopSlot: Sendable {
    /// Physical desktop `[x, y, width, height]`.
    var rect: [Int32]
    /// Straight-alpha RGBA8 pixels (`width * height * 4`).
    var rgba: [UInt8]
    var shadow: Bool
    var cornerRadius: Float
    var backdropBlur: Float
    var keyWindow: Bool
    var scale: Float
    var excludeFromCapture: Bool

    init(
        rect: [Int32],
        rgba: [UInt8],
        shadow: Bool = true,
        cornerRadius: Float = 10.0,
        backdropBlur: Float = 0.0,
        keyWindow: Bool = false,
        scale: Float = 1.0,
        excludeFromCapture: Bool = false
    ) {
        self.rect = rect
        self.rgba = rgba
        self.shadow = shadow
        self.cornerRadius = cornerRadius
        self.backdropBlur = backdropBlur
        self.keyWindow = keyWindow
        self.scale = max(scale, 0.25)
        self.excludeFromCapture = excludeFromCapture
    }
}

/// Computes bounded downsampled backdrop dimensions (`crates/rune/src/desktop/composite.rs`).
func fitBackdrop(_ size: (UInt32, UInt32), maxSide: UInt32 = MAX_BACKDROP) -> (UInt32, UInt32) {
    let w0 = max((size.0 + DOWN - 1) / DOWN, 1)
    let h0 = max((size.1 + DOWN - 1) / DOWN, 1)
    let longest = max(w0, h0)
    guard longest > maxSide && maxSide > 0 else {
        return (w0, h0)
    }
    let ratio = Double(maxSide) / Double(longest)
    return (
        max(UInt32((Double(w0) * ratio).rounded()), 1),
        max(UInt32((Double(h0) * ratio).rounded()), 1)
    )
}

/// Upstream `pixels(size, scale, max)`: whole pixels when within `[1, max]` per side (`crates/rune/src/desktop/composite.rs`).
func compositeOutputPixels(_ size: (Float, Float), _ scale: Float, _ maxSide: UInt32) -> (UInt32, UInt32)? {
    func side(_ v: Float) -> UInt32? {
        let px = (v * scale).rounded()
        guard px >= 1.0 && px <= Float(maxSide) else { return nil }
        return UInt32(px)
    }
    guard let w = side(size.0), let h = side(size.1) else { return nil }
    return (w, h)
}

/// Center-crops `sourceRgba` (`iw x ih`) to `targetSize` aspect ratio and scales to `targetSize` as opaque RGBA (`crates/rune/src/desktop/composite.rs`).
func fitBackdropBuffer(
    label: String = "<buffer>",
    sourceSize: (UInt32, UInt32),
    sourceRgba: [UInt8],
    targetSize: (UInt32, UInt32)
) -> Result<[UInt8], DesktopStringError> {
    let (iw, ih) = sourceSize
    if max(iw, ih) > MAX_BACKDROP {
        return .failure(DesktopStringError("\(label): \(iw)x\(ih) pixels; a backdrop is at most \(MAX_BACKDROP) pixels a side"))
    }
    let (w, h) = targetSize
    guard iw > 0 && ih > 0 && w > 0 && h > 0 else {
        return .failure(DesktopStringError("\(label): invalid dimensions"))
    }
    let cw: UInt32
    let ch: UInt32
    if UInt64(iw) * UInt64(h) > UInt64(ih) * UInt64(w) {
        let raw = UInt32((Double(ih) * Double(w) / Double(h)).rounded())
        cw = min(max(raw, 1), iw)
        ch = ih
    } else {
        cw = iw
        let raw = UInt32((Double(iw) * Double(h) / Double(w)).rounded())
        ch = min(max(raw, 1), ih)
    }
    let cropX = (iw - cw) / 2
    let cropY = (ih - ch) / 2

    var out = [UInt8](repeating: 0, count: Int(w) * Int(h) * 4)
    for ty in 0..<h {
        let syFloat = (cw == w && ch == h)
            ? Double(cropY + ty)
            : (Double(cropY) + (Double(ty) + 0.5) * Double(ch) / Double(h) - 0.5)
        let sy0 = min(max(Int(syFloat.rounded(.down)), Int(cropY)), Int(cropY + ch - 1))
        let sy1 = min(max(sy0 + 1, Int(cropY)), Int(cropY + ch - 1))
        let fy = Float(max(min(syFloat - Double(sy0), 1.0), 0.0))

        for tx in 0..<w {
            let sxFloat = (cw == w && ch == h)
                ? Double(cropX + tx)
                : (Double(cropX) + (Double(tx) + 0.5) * Double(cw) / Double(w) - 0.5)
            let sx0 = min(max(Int(sxFloat.rounded(.down)), Int(cropX)), Int(cropX + cw - 1))
            let sx1 = min(max(sx0 + 1, Int(cropX)), Int(cropX + cw - 1))
            let fx = Float(max(min(sxFloat - Double(sx0), 1.0), 0.0))

            func samplePremul(_ px: Int, _ py: Int) -> (Float, Float, Float) {
                let idx = (py * Int(iw) + px) * 4
                let a = Float(sourceRgba[idx + 3]) / 255.0
                return (
                    Float(sourceRgba[idx]) * a,
                    Float(sourceRgba[idx + 1]) * a,
                    Float(sourceRgba[idx + 2]) * a
                )
            }
            let p00 = samplePremul(sx0, sy0)
            let p10 = samplePremul(sx1, sy0)
            let p01 = samplePremul(sx0, sy1)
            let p11 = samplePremul(sx1, sy1)
            let topR = p00.0 + (p10.0 - p00.0) * fx
            let topG = p00.1 + (p10.1 - p00.1) * fx
            let topB = p00.2 + (p10.2 - p00.2) * fx
            let botR = p01.0 + (p11.0 - p01.0) * fx
            let botG = p01.1 + (p11.1 - p01.1) * fx
            let botB = p01.2 + (p11.2 - p01.2) * fx
            let dst = (Int(ty) * Int(w) + Int(tx)) * 4
            out[dst] = UInt8(clamping: Int((topR + (botR - topR) * fy).rounded()))
            out[dst + 1] = UInt8(clamping: Int((topG + (botG - topG) * fy).rounded()))
            out[dst + 2] = UInt8(clamping: Int((topB + (botB - topB) * fy).rounded()))
            out[dst + 3] = 255
        }
    }
    return .success(out)
}

#if canImport(Darwin)
/// Upstream `fit_backdrop(path, size)`: checks header dimensions against `MAX_BACKDROP` before full decode (`crates/rune/src/desktop/composite.rs`).
func fitBackdropImageFile(_ path: String, _ targetSize: (UInt32, UInt32)) -> Result<[UInt8], DesktopStringError> {
    let url = URL(fileURLWithPath: path)
    // Decode PNG directly via `decodePng` when possible so untagged sRGB PNG bytes are preserved
    // without CoreGraphics GenericRGB -> sRGB profile gamma conversion (matching Rust `image::open`).
    if let data = try? Data(contentsOf: url), let png = decodePng([UInt8](data)) {
        if max(png.width, png.height) > MAX_BACKDROP {
            return .failure(DesktopStringError("\(path): \(png.width)x\(png.height) pixels; a backdrop is at most \(MAX_BACKDROP) pixels a side"))
        }
        return fitBackdropBuffer(label: path, sourceSize: (png.width, png.height), sourceRgba: png.rgba, targetSize: targetSize)
    }
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return .failure(DesktopStringError("\(path): failed to open image"))
    }
    guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
        let iw = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.uint32Value,
        let ih = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.uint32Value
    else {
        return .failure(DesktopStringError("\(path): failed to read image dimensions"))
    }
    if max(iw, ih) > MAX_BACKDROP {
        return .failure(DesktopStringError("\(path): \(iw)x\(ih) pixels; a backdrop is at most \(MAX_BACKDROP) pixels a side"))
    }
    guard let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        return .failure(DesktopStringError("\(path): failed to decode image"))
    }
    var raw = [UInt8](repeating: 0, count: Int(iw) * Int(ih) * 4)
    let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let ok = raw.withUnsafeMutableBytes { ptr -> Bool in
        guard let base = ptr.baseAddress,
            let ctx = CGContext(
                data: base,
                width: Int(iw),
                height: Int(ih),
                bitsPerComponent: 8,
                bytesPerRow: Int(iw) * 4,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: Int(iw), height: Int(ih)))
        return true
    }
    guard ok else {
        return .failure(DesktopStringError("\(path): failed to rasterize image"))
    }
    // `raw` is already premultiplied RGBA; set alpha=255 so `fitBackdropBuffer` treats RGB as premultiplied.
    for i in stride(from: 3, to: raw.count, by: 4) {
        raw[i] = 255
    }
    return fitBackdropBuffer(label: path, sourceSize: (iw, ih), sourceRgba: raw, targetSize: targetSize)
}
#endif

/// Composites `slots` in back-to-front order onto a virtual desktop RGBA8 buffer (`crates/rune/src/desktop/composite.rs`).
func desktopPixels(
    origin: (Int32, Int32) = (0, 0),
    desktopSize: (UInt32, UInt32),
    background: Color = Color(0.11, 0.12, 0.14, 1.0),
    backdropRgba: [UInt8]? = nil,
    slots: [DesktopSlot],
    includeCaptureExcluded: Bool = true
) -> [UInt8] {
    let dw = Int(max(desktopSize.0, 1))
    let dh = Int(max(desktopSize.1, 1))
    var out = [UInt8](repeating: 0, count: dw * dh * 4)

    if let bg = backdropRgba, bg.count >= dw * dh * 4 {
        out.replaceSubrange(0..<(dw * dh * 4), with: bg[0..<(dw * dh * 4)])
    } else {
        let bgR = UInt8(clamping: Int((min(max(background.r, 0.0), 1.0) * 255.0).rounded()))
        let bgG = UInt8(clamping: Int((min(max(background.g, 0.0), 1.0) * 255.0).rounded()))
        let bgB = UInt8(clamping: Int((min(max(background.b, 0.0), 1.0) * 255.0).rounded()))
        let bgA = UInt8(clamping: Int((min(max(background.a, 0.0), 1.0) * 255.0).rounded()))

        for px in 0..<(dw * dh) {
            let base = px * 4
            out[base] = bgR
            out[base + 1] = bgG
            out[base + 2] = bgB
            out[base + 3] = bgA
        }
    }

    for slot in slots {
        if !includeCaptureExcluded && slot.excludeFromCapture {
            continue
        }
        guard slot.rect.count == 4 else { continue }
        let sx = Int(slot.rect[0] - origin.0)
        let sy = Int(slot.rect[1] - origin.1)
        let sw = Int(slot.rect[2])
        let sh = Int(slot.rect[3])
        guard sw > 0 && sh > 0 else { continue }
        let radPx = max(slot.cornerRadius * slot.scale, 0.0)
        guard slot.rgba.count >= sw * sh * 4 else { continue }

        // 1. Optional blurred drop shadow behind window (`fs_mask` -> `fs_blur_x` -> `fs_blur_y` -> `fs_shadow`)
        if slot.shadow {
            let (sigmaPt, offsetPt, opacity) = slot.keyWindow ? KEY_SHADOW : SHADOW
            let offY = offsetPt * slot.scale
            let downF = Float(DOWN)
            let pad = Int(ceil((KEY_SHADOW.0 * slot.scale * 3.0) / downF)) * Int(DOWN)
            let maskW = max((sw + 2 * pad + Int(DOWN) - 1) / Int(DOWN), 1)
            let maskH = max((sh + 2 * pad + Int(DOWN) - 1) / Int(DOWN), 1)

            var mask0 = [Float](repeating: 0.0, count: maskW * maskH)
            for my in 0..<maskH {
                let baseY = my * Int(DOWN) - pad
                for mx in 0..<maskW {
                    let baseX = mx * Int(DOWN) - pad
                    var sum: Float = 0.0
                    for dy in 0..<Int(DOWN) {
                        let qy = baseY + dy
                        guard qy >= 0 && qy < sh else { continue }
                        for dx in 0..<Int(DOWN) {
                            let qx = baseX + dx
                            guard qx >= 0 && qx < sw else { continue }
                            let a = Float(slot.rgba[(qy * sw + qx) * 4 + 3]) / 255.0
                            guard a > 0.0 else { continue }
                            let cov: Float = radPx > 0.0
                                ? min(max(0.5 - roundedBoxSdf(x: Float(qx) + 0.5, y: Float(qy) + 0.5, w: Float(sw), h: Float(sh), r: radPx), 0.0), 1.0)
                                : 1.0
                            sum += a * cov
                        }
                    }
                    mask0[my * maskW + mx] = sum / 16.0
                }
            }

            let sigmaTex = max((sigmaPt * slot.scale) / downF, 0.5)
            let r = Int(ceil(sigmaTex * 3.0))
            var weights = [Float](repeating: 0.0, count: 2 * r + 1)
            var weightTotal: Float = 0.0
            let invTwoSigmaSq = 1.0 / (2.0 * sigmaTex * sigmaTex)
            for k in -r...r {
                let w = expf(-Float(k * k) * invTwoSigmaSq)
                weights[k + r] = w
                weightTotal += w
            }

            var mask1 = [Float](repeating: 0.0, count: maskW * maskH)
            for my in 0..<maskH {
                let rowOff = my * maskW
                for mx in 0..<maskW {
                    var sum: Float = 0.0
                    for k in -r...r {
                        let qx = mx + k
                        if qx >= 0 && qx < maskW {
                            sum += weights[k + r] * mask0[rowOff + qx]
                        }
                    }
                    mask1[rowOff + mx] = sum / weightTotal
                }
            }
            for my in 0..<maskH {
                let rowOff = my * maskW
                for mx in 0..<maskW {
                    var sum: Float = 0.0
                    for k in -r...r {
                        let qy = my + k
                        if qy >= 0 && qy < maskH {
                            sum += weights[k + r] * mask1[qy * maskW + mx]
                        }
                    }
                    mask0[rowOff + mx] = sum / weightTotal
                }
            }

            let yStart = max(0, Int(floor(Float(sy) + offY - Float(pad))))
            let yEnd = min(dh, Int(ceil(Float(sy + sh) + offY + Float(pad))))
            let xStart = max(0, sx - pad)
            let xEnd = min(dw, sx + sw + pad)

            for py in yStart..<yEnd {
                let my = ((Float(py) + 0.5) - Float(sy) - offY + Float(pad)) / downF - 0.5
                let y0i = min(max(Int(floor(my)), 0), maskH - 1)
                let y1i = min(max(y0i + 1, 0), maskH - 1)
                let fy = min(max(my - floor(my), 0.0), 1.0)
                for px in xStart..<xEnd {
                    let mx = ((Float(px) + 0.5) - Float(sx) + Float(pad)) / downF - 0.5
                    let x0i = min(max(Int(floor(mx)), 0), maskW - 1)
                    let x1i = min(max(x0i + 1, 0), maskW - 1)
                    let fx = min(max(mx - floor(mx), 0.0), 1.0)

                    let m00 = mask0[y0i * maskW + x0i]
                    let m10 = mask0[y0i * maskW + x1i]
                    let m01 = mask0[y1i * maskW + x0i]
                    let m11 = mask0[y1i * maskW + x1i]
                    let top = m00 + (m10 - m00) * fx
                    let bot = m01 + (m11 - m01) * fx
                    let sa = (top + (bot - top) * fy) * opacity
                    if sa > 1.0 / 512.0 {
                        blendPixelLinearSrgb(&out, idx: (py * dw + px) * 4, srgbR: 0, srgbG: 0, srgbB: 0, a: sa)
                    }
                }
            }
        }

        // 2. Blit slot RGBA8 with rounded-corner anti-aliased mask (`fs_window`)
        let y0 = max(0, sy)
        let y1 = min(dh, sy + sh)
        let x0 = max(0, sx)
        let x1 = min(dw, sx + sw)

        for py in y0..<y1 {
            let localY = py - sy
            for px in x0..<x1 {
                let localX = px - sx
                var maskAlpha: Float = 1.0
                if radPx > 0.0 {
                    let sdf = roundedBoxSdf(
                        x: Float(localX) + 0.5,
                        y: Float(localY) + 0.5,
                        w: Float(sw),
                        h: Float(sh),
                        r: radPx
                    )
                    maskAlpha = min(max(0.5 - sdf, 0.0), 1.0)
                    if maskAlpha <= 0.0 { continue }
                }
                let sIdx = (localY * sw + localX) * 4
                let sa = (Float(slot.rgba[sIdx + 3]) / 255.0) * maskAlpha
                if sa >= 0.9999 {
                    let dIdx = (py * dw + px) * 4
                    out[dIdx] = slot.rgba[sIdx]
                    out[dIdx + 1] = slot.rgba[sIdx + 1]
                    out[dIdx + 2] = slot.rgba[sIdx + 2]
                    out[dIdx + 3] = 255
                } else if sa > 0.0 {
                    blendPixelLinearSrgb(
                        &out,
                        idx: (py * dw + px) * 4,
                        srgbR: slot.rgba[sIdx],
                        srgbG: slot.rgba[sIdx + 1],
                        srgbB: slot.rgba[sIdx + 2],
                        a: sa
                    )
                }
            }
        }
    }

    return out
}

@inline(__always)
private func roundedBoxSdf(x: Float, y: Float, w: Float, h: Float, r: Float) -> Float {
    let hw = w * 0.5
    let hh = h * 0.5
    let rad = min(r, min(hw, hh))
    let qx = abs(x - hw) - (hw - rad)
    let qy = abs(y - hh) - (hh - rad)
    let outX = max(qx, 0.0)
    let outY = max(qy, 0.0)
    return hypotf(outX, outY) + min(max(qx, qy), 0.0) - rad
}

@inline(__always)
private func blendPixelLinearSrgb(_ buf: inout [UInt8], idx: Int, srgbR: UInt8, srgbG: UInt8, srgbB: UInt8, a: Float) {
    let sr = srgbDecode(Float(srgbR) / 255.0)
    let sg = srgbDecode(Float(srgbG) / 255.0)
    let sb = srgbDecode(Float(srgbB) / 255.0)
    let dr = srgbDecode(Float(buf[idx]) / 255.0)
    let dg = srgbDecode(Float(buf[idx + 1]) / 255.0)
    let db = srgbDecode(Float(buf[idx + 2]) / 255.0)
    let da = Float(buf[idx + 3]) / 255.0
    let inv = 1.0 - a
    let outA = a + da * inv
    guard outA > 1e-6 else { return }
    let outR = srgbEncode((sr * a + dr * da * inv) / outA)
    let outG = srgbEncode((sg * a + dg * da * inv) / outA)
    let outB = srgbEncode((sb * a + db * da * inv) / outA)
    buf[idx] = UInt8(clamping: Int((min(max(outR, 0.0), 1.0) * 255.0).rounded()))
    buf[idx + 1] = UInt8(clamping: Int((min(max(outG, 0.0), 1.0) * 255.0).rounded()))
    buf[idx + 2] = UInt8(clamping: Int((min(max(outB, 0.0), 1.0) * 255.0).rounded()))
    buf[idx + 3] = UInt8(clamping: Int((min(max(outA, 0.0), 1.0) * 255.0).rounded()))
}
