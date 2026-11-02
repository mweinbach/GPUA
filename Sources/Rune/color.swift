// Ported from: crates/rune/src/color.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Colour in linear sRGB with straight alpha. Authored in OKLCH, animated in Oklab.

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
import RuneMotion

public func srgbDecode(_ c: Float) -> Float {
    RuneMotion.srgbDecode(c)
}

public func srgbEncode(_ c: Float) -> Float {
    RuneMotion.srgbEncode(c)
}

/// Colour in linear sRGB with straight alpha. Authored in OKLCH, animated in Oklab.
public struct Color: Sendable, Equatable, Codable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public static let transparent = Color(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    public static let white = Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
    public static let black = Color(r: 0.0, g: 0.0, b: 0.0, a: 1.0)

    // Rust UPPER_CASE aliases for seamless porting
    public static let TRANSPARENT = transparent
    public static let WHITE = white
    public static let BLACK = black

    public init() {
        self.r = 0.0
        self.g = 0.0
        self.b = 0.0
        self.a = 0.0
    }

    public init(r: Float, g: Float, b: Float, a: Float) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public func alpha(_ a: Float) -> Color {
        Color(r: r, g: g, b: b, a: a)
    }

    /// `t` of the way from `self` to `other`, straight in linear light.
    public func mix(_ other: Color, _ t: Float) -> Color {
        @inline(__always)
        func m(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        return Color(r: m(r, other.r), g: m(g, other.g), b: m(b, other.b), a: m(a, other.a))
    }

    public func toOklab() -> [Float] {
        let lab = RuneMotion.linearToOklab(r, g, b)
        return [lab[0], lab[1], lab[2], a]
    }

    public static func fromOklab(_ labAlpha: [Float]) -> Color {
        precondition(labAlpha.count >= 4, "fromOklab expects [L, a, b, alpha]")
        let rgb = RuneMotion.oklabToLinear([labAlpha[0], labAlpha[1], labAlpha[2]])
        return Color(
            r: min(max(rgb[0], 0.0), 1.0),
            g: min(max(rgb[1], 0.0), 1.0),
            b: min(max(rgb[2], 0.0), 1.0),
            a: min(max(labAlpha[3], 0.0), 1.0)
        )
    }

    /// Premultiplied linear RGBA.
    public func premul(_ opacity: Float) -> [Float] {
        let al = a * opacity
        return [r * al, g * al, b * al, al]
    }

    /// Premultiplied sRGB-encoded RGBA, for gamma-space (`srgbBlend`) targets.
    public func premulSrgb(_ opacity: Float) -> [Float] {
        let al = a * opacity
        return [srgbEncode(r) * al, srgbEncode(g) * al, srgbEncode(b) * al, al]
    }

    public func luminance() -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// `#rrggbbaa` in sRGB, for trees and traces.
    public func hex() -> String {
        @inline(__always)
        func enc(_ c: Float) -> UInt8 {
            let v = (srgbEncode(c) * 255.0).rounded()
            return UInt8(clamping: Int(v))
        }
        let aa = UInt8(clamping: Int((a * 255.0).rounded()))
        return byteHexString(enc(r), enc(g), enc(b), aa)
    }
}

@inline(__always)
private func byteHexString(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> String {
    let digits: [Character] = Array("0123456789abcdef")
    var out = "#"
    out.reserveCapacity(9)
    for byte in [r, g, b, a] {
        out.append(digits[Int(byte >> 4)])
        out.append(digits[Int(byte & 0x0f)])
    }
    return out
}

/// An `Float`'s bits for hashing a type that compares its floats with `==`: `-0.0` hashes as
/// `0.0`, which it equals, and every NaN alike.
@inline(__always)
func hashBits(_ x: Float) -> UInt32 {
    if x == 0.0 {
        return 0
    } else if x.isNaN {
        return Float.nan.bitPattern
    } else {
        return x.bitPattern
    }
}

extension Color: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hashBits(r))
        hasher.combine(hashBits(g))
        hasher.combine(hashBits(b))
        hasher.combine(hashBits(a))
    }
}

public func oklch(_ l: Float, _ c: Float, _ h: Float) -> Color {
    oklcha(l, c, h, 1.0)
}

public func oklcha(_ l: Float, _ c: Float, _ h: Float, _ a: Float) -> Color {
    let rad = h * (.pi / 180.0)
    let (s, co) = RuneMotion.math.sinCos(rad)
    return Color.fromOklab([l, c * co, c * s, a])
}

/// `#rgb`, `#rrggbb` or `#rrggbbaa` (sRGB) to linear ``Color``.
public func hex(_ s: String) -> Color? {
    guard s.hasPrefix("#") else { return nil }
    let chars = Array(s.dropFirst().utf8)
    @inline(__always)
    func nibble(_ b: UInt8) -> UInt8? {
        switch b {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return b - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return b - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): return b - UInt8(ascii: "A") + 10
        default: return nil
        }
    }
    @inline(__always)
    func pair(_ i: Int) -> Float? {
        guard i + 1 < chars.count, let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
        return Float((hi << 4) | lo) / 255.0
    }
    @inline(__always)
    func single(_ i: Int) -> Float? {
        guard i < chars.count, let v = nibble(chars[i]) else { return nil }
        return Float(v * 17) / 255.0
    }
    let r: Float
    let g: Float
    let b: Float
    let a: Float
    switch chars.count {
    case 3:
        guard let rr = single(0), let gg = single(1), let bb = single(2) else { return nil }
        (r, g, b, a) = (rr, gg, bb, 1.0)
    case 6:
        guard let rr = pair(0), let gg = pair(2), let bb = pair(4) else { return nil }
        (r, g, b, a) = (rr, gg, bb, 1.0)
    case 8:
        guard let rr = pair(0), let gg = pair(2), let bb = pair(4), let aa = pair(6) else { return nil }
        (r, g, b, a) = (rr, gg, bb, aa)
    default:
        return nil
    }
    return Color(r: srgbDecode(r), g: srgbDecode(g), b: srgbDecode(b), a: a)
}

/// Source-over of premultiplied `top` onto premultiplied `bottom`.
public func over(_ top: [Float], _ bottom: [Float]) -> [Float] {
    let k = 1.0 - top[3]
    return [
        top[0] + bottom[0] * k,
        top[1] + bottom[1] * k,
        top[2] + bottom[2] * k,
        top[3] + bottom[3] * k,
    ]
}

extension Color: RuneMotion.Animatable {
    public static let lanes: Int = 4

    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        let lab = toOklab()
        let al = lab[3]
        out[0] = lab[0] * al
        out[1] = lab[1] * al
        out[2] = lab[2] * al
        out[3] = al
    }

    public static func readLanes(_ x: UnsafeBufferPointer<Float>) -> Color {
        let al = min(max(x[3], 0.0), 1.0)
        if al <= 1e-6 {
            return .transparent
        }
        return Color.fromOklab([x[0] / al, x[1] / al, x[2] / al, al])
    }
}

/// Namespace mirroring `rune::color` module exports.
public enum color {
    public typealias Color = Rune.Color
    public static func oklch(_ l: Float, _ c: Float, _ h: Float) -> Color { Rune.oklch(l, c, h) }
    public static func oklcha(_ l: Float, _ c: Float, _ h: Float, _ a: Float) -> Color { Rune.oklcha(l, c, h, a) }
    public static func hex(_ s: String) -> Color? { Rune.hex(s) }
    public static func over(_ top: [Float], _ bottom: [Float]) -> [Float] { Rune.over(top, bottom) }
    public static func srgbDecode(_ c: Float) -> Float { Rune.srgbDecode(c) }
    public static func srgbEncode(_ c: Float) -> Float { Rune.srgbEncode(c) }
}
