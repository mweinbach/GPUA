// Ported from: crates/gpui/src/color.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

// MARK: - Hex Constructors & Color Utilities

/// Convert an RGB hex color code number (0xRRGGBB) to `Rgba` with alpha 1.0.
public func rgb(_ hex: UInt32) -> Rgba {
    let r = Float((hex >> 16) & 0xFF) / 255.0
    let g = Float((hex >> 8) & 0xFF) / 255.0
    let b = Float(hex & 0xFF) / 255.0
    return Rgba(r: r, g: g, b: b, a: 1.0)
}

/// Convert an RGBA hex color code number (0xRRGGBBAA) to `Rgba`.
public func rgba(_ hex: UInt32) -> Rgba {
    let r = Float((hex >> 24) & 0xFF) / 255.0
    let g = Float((hex >> 16) & 0xFF) / 255.0
    let b = Float((hex >> 8) & 0xFF) / 255.0
    let a = Float(hex & 0xFF) / 255.0
    return Rgba(r: r, g: g, b: b, a: a)
}

/// Swap from RGBA with premultiplied alpha to BGRA.
public func swapRgbaPaToBgra(_ color: inout [UInt8]) {
    guard color.count >= 4 else { return }
    color.swapAt(0, 2)
    if color[3] > 0 {
        let a = Float(color[3]) / 255.0
        color[0] = UInt8(Swift.min(Swift.max((Float(color[0]) / a).rounded(), 0.0), 255.0))
        color[1] = UInt8(Swift.min(Swift.max((Float(color[1]) / a).rounded(), 0.0), 255.0))
        color[2] = UInt8(Swift.min(Swift.max((Float(color[2]) / a).rounded(), 0.0), 255.0))
    }
}

// MARK: - Rgba

/// An RGBA color in 0.0 ... 1.0 range.
public struct Rgba: Sendable, Equatable, Hashable, Codable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(r: Float, g: Float, b: Float, a: Float = 1.0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Blend this color with another color using source-over equation.
    /// Note: upstream GPUI preserves background alpha (`self.a`) on semi-transparent blend.
    public func blend(with other: Rgba) -> Rgba {
        if other.a >= 1.0 {
            return other
        } else if other.a <= 0.0 {
            return self
        } else {
            return Rgba(
                r: (self.r * (1.0 - other.a)) + (other.r * other.a),
                g: (self.g * (1.0 - other.a)) + (other.g * other.a),
                b: (self.b * (1.0 - other.a)) + (other.b * other.a),
                a: self.a
            )
        }
    }

    /// Packed big-endian 32-bit unsigned integer (0xRRGGBBAA).
    public var packedU32: UInt32 {
        let rU32 = UInt32((r * 255.0).rounded())
        let gU32 = UInt32((g * 255.0).rounded())
        let bU32 = UInt32((b * 255.0).rounded())
        let aU32 = UInt32((a * 255.0).rounded())
        return (rU32 << 24) | (gU32 << 16) | (bU32 << 8) | aU32
    }

    /// Parses a CSS hex color string (#RGB, #RGBA, #RRGGBB, #RRGGBBAA).
    public init?(hex: String) {
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard str.hasPrefix("#") else { return nil }
        str.removeFirst()

        func parseHexDigit(_ c: Character) -> UInt8? {
            guard let val = c.hexDigitValue else { return nil }
            return UInt8(val)
        }

        func duplicate(_ val: UInt8) -> UInt8 {
            (val << 4) | val
        }

        let chars = Array(str)
        switch chars.count {
        case 3: // #RGB -> duplicate
            guard let r = parseHexDigit(chars[0]),
                  let g = parseHexDigit(chars[1]),
                  let b = parseHexDigit(chars[2]) else { return nil }
            self.init(
                r: Float(duplicate(r)) / 255.0,
                g: Float(duplicate(g)) / 255.0,
                b: Float(duplicate(b)) / 255.0,
                a: 1.0
            )
        case 4: // #RGBA -> duplicate
            guard let r = parseHexDigit(chars[0]),
                  let g = parseHexDigit(chars[1]),
                  let b = parseHexDigit(chars[2]),
                  let a = parseHexDigit(chars[3]) else { return nil }
            self.init(
                r: Float(duplicate(r)) / 255.0,
                g: Float(duplicate(g)) / 255.0,
                b: Float(duplicate(b)) / 255.0,
                a: Float(duplicate(a)) / 255.0
            )
        case 6: // #RRGGBB
            guard let r1 = parseHexDigit(chars[0]), let r2 = parseHexDigit(chars[1]),
                  let g1 = parseHexDigit(chars[2]), let g2 = parseHexDigit(chars[3]),
                  let b1 = parseHexDigit(chars[4]), let b2 = parseHexDigit(chars[5]) else { return nil }
            let r = (r1 << 4) | r2
            let g = (g1 << 4) | g2
            let b = (b1 << 4) | b2
            self.init(r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0, a: 1.0)
        case 8: // #RRGGBBAA
            guard let r1 = parseHexDigit(chars[0]), let r2 = parseHexDigit(chars[1]),
                  let g1 = parseHexDigit(chars[2]), let g2 = parseHexDigit(chars[3]),
                  let b1 = parseHexDigit(chars[4]), let b2 = parseHexDigit(chars[5]),
                  let a1 = parseHexDigit(chars[6]), let a2 = parseHexDigit(chars[7]) else { return nil }
            let r = (r1 << 4) | r2
            let g = (g1 << 4) | g2
            let b = (b1 << 4) | b2
            let a = (a1 << 4) | a2
            self.init(r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0, a: Float(a) / 255.0)
        default:
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let str = try container.decode(String.self)
        guard let color = Rgba(hex: str) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid RGBA hex string: \(str)")
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        let hexStr = String(format: "#%08x", packedU32)
        try container.encode(hexStr)
    }
}

extension Rgba: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        String(format: "rgba(#%08x)", packedU32)
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - Hsla

/// An HSLA color with hue, saturation, lightness, and alpha in [0.0, 1.0].
public struct Hsla: Sendable, Equatable, Hashable, Comparable, Codable {
    public var h: Float
    public var s: Float
    public var l: Float
    public var a: Float

    public init(h: Float, s: Float, l: Float, a: Float = 1.0) {
        self.h = Swift.min(Swift.max(h, 0.0), 1.0)
        self.s = Swift.min(Swift.max(s, 0.0), 1.0)
        self.l = Swift.min(Swift.max(l, 0.0), 1.0)
        self.a = Swift.min(Swift.max(a, 0.0), 1.0)
    }

    public static func < (lhs: Hsla, rhs: Hsla) -> Bool {
        if lhs.h != rhs.h { return lhs.h < rhs.h }
        if lhs.s != rhs.s { return lhs.s < rhs.s }
        if lhs.l != rhs.l { return lhs.l < rhs.l }
        return lhs.a < rhs.a
    }

    public func toRgb() -> Rgba {
        let c = (1.0 - Swift.abs(2.0 * l - 1.0)) * s
        let mod = (h * 6.0).truncatingRemainder(dividingBy: 2.0)
        let x = c * (1.0 - Swift.abs(mod - 1.0))
        let m = l - c / 2.0
        let cm = c + m
        let xm = x + m

        let sector = Int((h * 6.0).rounded(.down))
        let (r, g, b): (Float, Float, Float) = {
            switch sector {
            case 0, 6: return (cm, xm, m)
            case 1: return (xm, cm, m)
            case 2: return (m, cm, xm)
            case 3: return (m, xm, cm)
            case 4: return (xm, m, cm)
            default: return (cm, m, xm)
            }
        }()

        return Rgba(
            r: Swift.min(Swift.max(r, 0.0), 1.0),
            g: Swift.min(Swift.max(g, 0.0), 1.0),
            b: Swift.min(Swift.max(b, 0.0), 1.0),
            a: a
        )
    }

    public init(rgba: Rgba) {
        let r = rgba.r
        let g = rgba.g
        let b = rgba.b

        let maxVal = Swift.max(r, Swift.max(g, b))
        let minVal = Swift.min(r, Swift.min(g, b))
        let delta = maxVal - minVal

        let l = (maxVal + minVal) / 2.0
        let s: Float
        if l == 0.0 || l == 1.0 {
            s = 0.0
        } else if l < 0.5 {
            s = delta / (2.0 * l)
        } else {
            s = delta / (2.0 - 2.0 * l)
        }

        let h: Float
        if delta == 0.0 {
            h = 0.0
        } else if maxVal == r {
            let rem = ((g - b) / delta).truncatingRemainder(dividingBy: 6.0)
            let positiveRem = rem < 0 ? rem + 6.0 : rem
            h = positiveRem / 6.0
        } else if maxVal == g {
            h = (((b - r) / delta) + 2.0) / 6.0
        } else {
            h = (((r - g) / delta) + 4.0) / 6.0
        }

        self.h = Swift.min(Swift.max(h, 0.0), 1.0)
        self.s = Swift.min(Swift.max(s, 0.0), 1.0)
        self.l = Swift.min(Swift.max(l, 0.0), 1.0)
        self.a = Swift.min(Swift.max(rgba.a, 0.0), 1.0)
    }

    public func blend(with other: Hsla) -> Hsla {
        if other.a >= 1.0 {
            return other
        } else if other.a <= 0.0 {
            return self
        } else {
            let selfRgb = self.toRgb()
            let otherRgb = other.toRgb()
            let blended = selfRgb.blend(with: otherRgb)
            return Hsla(rgba: blended)
        }
    }

    public func grayscale() -> Hsla {
        Hsla(h: h, s: 0.0, l: l, a: a)
    }

    public mutating func fadeOut(by factor: Float) {
        a *= (1.0 - Swift.min(Swift.max(factor, 0.0), 1.0))
    }

    public func opacity(_ factor: Float) -> Hsla {
        Hsla(h: h, s: s, l: l, a: a * Swift.min(Swift.max(factor, 0.0), 1.0))
    }

    public func alpha(_ newAlpha: Float) -> Hsla {
        Hsla(h: h, s: s, l: l, a: Swift.min(Swift.max(newAlpha, 0.0), 1.0))
    }

    public var isTransparent: Bool { a == 0.0 }
    public var isOpaque: Bool { a == 1.0 }

    public init(from decoder: any Decoder) throws {
        let rgba = try Rgba(from: decoder)
        self.init(rgba: rgba)
    }

    public func encode(to encoder: any Encoder) throws {
        try toRgb().encode(to: encoder)
    }
}

public func hsla(_ h: Float, _ s: Float, _ l: Float, _ a: Float = 1.0) -> Hsla {
    Hsla(h: h, s: s, l: l, a: a)
}

// Predefined colors
public func black() -> Hsla { Hsla(h: 0, s: 0, l: 0, a: 1) }
public func transparentBlack() -> Hsla { Hsla(h: 0, s: 0, l: 0, a: 0) }
public func transparentWhite() -> Hsla { Hsla(h: 0, s: 0, l: 1, a: 0) }
public func opaqueGrey(lightness: Float, opacity: Float) -> Hsla {
    Hsla(h: 0, s: 0, l: lightness, a: opacity)
}
public func white() -> Hsla { Hsla(h: 0, s: 0, l: 1, a: 1) }
public func red() -> Hsla { Hsla(h: 0, s: 1, l: 0.5, a: 1) }
public func blue() -> Hsla { Hsla(h: 0.6666666667, s: 1, l: 0.5, a: 1) }
public func green() -> Hsla { Hsla(h: 0.3333333333, s: 1, l: 0.25, a: 1) }
public func yellow() -> Hsla { Hsla(h: 0.1666666667, s: 1, l: 0.5, a: 1) }

extension Hsla {
    public static func red() -> Hsla { GPUI.red() }
    public static func green() -> Hsla { GPUI.green() }
    public static func blue() -> Hsla { GPUI.blue() }
    public static func black() -> Hsla { GPUI.black() }
    public static func white() -> Hsla { GPUI.white() }
    public static func transparentBlack() -> Hsla { GPUI.transparentBlack() }
}

extension Hsla: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        String(format: "hsla(%.2f, %.2f%%, %.2f%%, %.2f)", h * 360.0, s * 100.0, l * 100.0, a)
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - BackgroundTag & ColorSpace

@frozen
public struct BackgroundTag: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let solid = BackgroundTag(rawValue: 0)
    public static let linearGradient = BackgroundTag(rawValue: 1)
    public static let patternSlash = BackgroundTag(rawValue: 2)
    public static let checkerboard = BackgroundTag(rawValue: 3)
}

@frozen
public struct ColorSpace: RawRepresentable, Sendable, Equatable, Hashable, Codable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let srgb = ColorSpace(rawValue: 0)
    public static let oklab = ColorSpace(rawValue: 1)
}

// MARK: - LinearColorStop

@frozen
public struct LinearColorStop: Sendable, Equatable, Hashable, Codable {
    public var color: Hsla
    public var percentage: Float

    public init(color: Hsla, percentage: Float) {
        self.color = color
        self.percentage = percentage
    }

    public func opacity(_ factor: Float) -> LinearColorStop {
        LinearColorStop(color: color.opacity(factor), percentage: percentage)
    }
}

public func linearColorStop(_ color: Hsla, _ percentage: Float) -> LinearColorStop {
    LinearColorStop(color: color, percentage: percentage)
}

public func linearColorStop(_ color: Rgba, _ percentage: Float) -> LinearColorStop {
    LinearColorStop(color: Hsla(rgba: color), percentage: percentage)
}

// MARK: - Background (72-byte GPU memory layout)

@frozen
public struct Background: Sendable, Equatable, Hashable, Codable {
    public var tag: BackgroundTag
    public var colorSpace: ColorSpace
    public var solid: Hsla
    public var gradientAngleOrPatternHeight: Float
    public var colors: (LinearColorStop, LinearColorStop)
    public var pad: UInt32 = 0

    public init(
        tag: BackgroundTag = .solid,
        colorSpace: ColorSpace = .srgb,
        solid: Hsla = black(),
        gradientAngleOrPatternHeight: Float = 0.0,
        colors: (LinearColorStop, LinearColorStop) = (LinearColorStop(color: black(), percentage: 0), LinearColorStop(color: black(), percentage: 1)),
        pad: UInt32 = 0
    ) {
        self.tag = tag
        self.colorSpace = colorSpace
        self.solid = solid
        self.gradientAngleOrPatternHeight = gradientAngleOrPatternHeight
        self.colors = colors
        self.pad = pad
    }

    public func colorSpace(_ space: ColorSpace) -> Background {
        var copy = self
        copy.colorSpace = space
        return copy
    }

    public func opacity(_ factor: Float) -> Background {
        var copy = self
        copy.solid = copy.solid.opacity(factor)
        copy.colors = (
            colors.0.opacity(factor),
            colors.1.opacity(factor)
        )
        return copy
    }

    public var isTransparent: Bool {
        switch tag {
        case .linearGradient:
            return colors.0.color.isTransparent && colors.1.color.isTransparent
        default:
            return solid.isTransparent
        }
    }

    public static func == (lhs: Background, rhs: Background) -> Bool {
        lhs.tag == rhs.tag
            && lhs.colorSpace == rhs.colorSpace
            && lhs.solid == rhs.solid
            && lhs.gradientAngleOrPatternHeight == rhs.gradientAngleOrPatternHeight
            && lhs.colors.0 == rhs.colors.0
            && lhs.colors.1 == rhs.colors.1
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(tag)
        hasher.combine(colorSpace)
        hasher.combine(solid)
        hasher.combine(gradientAngleOrPatternHeight)
        hasher.combine(colors.0)
        hasher.combine(colors.1)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hsla = try container.decode(Hsla.self)
        self = solidBackground(hsla)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(solid)
    }
}

public func solidBackground(_ color: Hsla) -> Background {
    Background(
        tag: .solid,
        colorSpace: .srgb,
        solid: color,
        gradientAngleOrPatternHeight: 0.0,
        colors: (LinearColorStop(color: color, percentage: 0), LinearColorStop(color: color, percentage: 1)),
        pad: 0
    )
}

public func solidBackground(_ color: Rgba) -> Background {
    solidBackground(Hsla(rgba: color))
}

public func linearGradient(
    angle: Float,
    from: LinearColorStop,
    to: LinearColorStop
) -> Background {
    Background(
        tag: .linearGradient,
        colorSpace: .srgb,
        solid: from.color,
        gradientAngleOrPatternHeight: angle,
        colors: (from, to),
        pad: 0
    )
}

public func patternSlash(color: Hsla, width: Float, interval: Float) -> Background {
    let widthScaled = UInt32((width * 255.0).rounded())
    let intervalScaled = UInt32((interval * 255.0).rounded())
    let height = Float((widthScaled * 0xFFFF) + intervalScaled)
    return Background(
        tag: .patternSlash,
        colorSpace: .srgb,
        solid: color,
        gradientAngleOrPatternHeight: height,
        colors: (LinearColorStop(color: color, percentage: 0), LinearColorStop(color: color, percentage: 1)),
        pad: 0
    )
}

public func checkerboard(color: Hsla, size: Float) -> Background {
    Background(
        tag: .checkerboard,
        colorSpace: .srgb,
        solid: color,
        gradientAngleOrPatternHeight: size,
        colors: (LinearColorStop(color: color, percentage: 0), LinearColorStop(color: color, percentage: 1)),
        pad: 0
    )
}
