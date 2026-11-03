// Ported from: crates/rune/src/text/hash.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Deterministic 64-bit hashes for text layout and run caches.
//!
//! `KeyHasher` folds each 64-bit word with a 128-bit multiply-xor (`rustc-hash` / wyhash mixer):
//! ~6-8 bytes/cycle on text, one instruction per numeric field, and no cross-lane mixing gap
//! between adjacent `f32` bits.

/// Alignment of broken text lines inside a layout's wrap width.
// PORT NOTE: Mirrors `parley::Alignment` (`Start = 0`, `Center = 1`, `End = 2`, `Justify = 3`).
public enum TextAlignment: UInt8, Sendable, Equatable, Hashable {
    case start = 0
    case center = 1
    case end = 2
    case justify = 3

    public init(_ align: Align, justify: Bool = false) {
        if justify {
            self = .justify
        } else {
            switch align {
            case .start: self = .start
            case .center: self = .center
            case .end: self = .end
            }
        }
    }
}

struct KeyHasher {
    var hash: UInt64 = 0

    static let SEED: UInt64 = 0x243f_6a88_85a3_08d3
    static let MUL: UInt64 = 0x9e37_79b9_7f4a_7c15

    @inline(__always)
    mutating func mix(_ word: UInt64) {
        let (hi, lo) = (hash ^ word ^ Self.SEED).multipliedFullWidth(by: Self.MUL)
        hash = lo ^ hi
    }

    @inline(__always)
    mutating func u8(_ v: UInt8) {
        mix(UInt64(v))
    }

    @inline(__always)
    mutating func bool(_ v: Bool) {
        u8(v ? 1 : 0)
    }

    @inline(__always)
    mutating func u32(_ v: UInt32) {
        mix(UInt64(v))
    }

    @inline(__always)
    mutating func u64(_ v: UInt64) {
        mix(v)
    }

    @inline(__always)
    mutating func usize(_ v: Int) {
        mix(UInt64(bitPattern: Int64(v)))
    }

    @inline(__always)
    mutating func f32(_ v: Float) {
        u32(hashBits(v))
    }

    @inline(__always)
    mutating func f32Pair(_ a: Float, _ b: Float) {
        mix(UInt64(hashBits(a)) | (UInt64(hashBits(b)) << 32))
    }

    mutating func bytes(_ bytes: UnsafeBufferPointer<UInt8>) {
        var fx: UInt64 = 0
        let fxK: UInt64 = 0xf135_7aea_2e62_a9c5
        var i = 0
        let count = bytes.count
        while i + 8 <= count {
            var word: UInt64 = 0
            for k in 0..<8 {
                word |= UInt64(bytes[i + k]) << (k * 8)
            }
            let (hi, lo) = (fx ^ word).multipliedFullWidth(by: fxK)
            fx = lo ^ hi
            i += 8
        }
        let rem = count - i
        if rem >= 4 {
            var a: UInt32 = 0
            var b: UInt32 = 0
            for k in 0..<4 {
                a |= UInt32(bytes[i + k]) << (k * 8)
                b |= UInt32(bytes[count - 4 + k]) << (k * 8)
            }
            let word = UInt64(a) | (UInt64(b) << 32)
            let (hi, lo) = (fx ^ word).multipliedFullWidth(by: fxK)
            fx = lo ^ hi
        } else if rem > 0 {
            let b0 = UInt64(bytes[i])
            let bMid = UInt64(bytes[i + rem / 2])
            let bLast = UInt64(bytes[count - 1])
            let word = (b0 << 16) | (bMid << 8) | bLast
            let (hi, lo) = (fx ^ word).multipliedFullWidth(by: fxK)
            fx = lo ^ hi
        }
        mix(fx ^ UInt64(bitPattern: Int64(count)))
    }

    mutating func str(_ s: String) {
        var copy = s
        copy.withUTF8 { buf in
            bytes(buf)
        }
    }

    mutating func optStr(_ s: String?) {
        if let s {
            u8(1)
            str(s)
        } else {
            u8(0)
        }
    }

    mutating func optF32(_ v: Float?) {
        if let v {
            u8(1)
            f32(v)
        } else {
            u8(0)
        }
    }

    mutating func family(_ f: Family) {
        switch f {
        case .sans:
            u8(0)
        case .mono:
            u8(1)
        case .systemMono:
            u8(2)
        case .named(let s):
            u8(3)
            str(s)
        }
    }

    mutating func optical(_ o: OpticalSize) {
        switch o {
        case .auto:
            u8(0)
        case .fontDefault:
            u8(1)
        case .fixed(let v):
            u8(2)
            f32(v)
        }
    }

    mutating func style(_ style: TextStyle) {
        f32Pair(style.size, style.weight)
        f32Pair(style.lineHeight, style.tracking)
        bool(style.italic)
        family(style.family)
        str(style.features)
        str(style.variations)
        optical(style.opticalSize)
    }
}

/// A 64-bit cache key of `text` in `style` at `scale`, with `width` when given.
public func textHash(
    _ text: String,
    _ spans: [Span],
    _ style: TextStyle,
    _ scale: Float,
    _ width: Float? = nil
) -> UInt64 {
    var h = KeyHasher()
    h.str(text)
    h.usize(spans.count)
    for sp in spans {
        h.mix(UInt64(sp.start) | (UInt64(sp.end) << 32))
        h.optF32(sp.weight)
        h.u8((sp.italic ? 1 : 0) | (sp.mono ? 2 : 0))
        h.optF32(sp.size)
    }
    h.style(style)
    h.f32(scale)
    h.optF32(width)
    return h.hash
}

/// What shaping depends on: the text, its spans, style and scale, overflow-wrap and pills.
/// Span fields read only at paint time (`color`, `underline`, `bg`) are skipped
/// so link hover recolours reuse the cached layout.
func shapeKey(
    _ text: String,
    _ spans: [Span],
    _ style: TextStyle,
    _ scale: Float,
    _ wrapAnywhere: Bool,
    _ pills: [PillChip]
) -> UInt64 {
    let key = textHash(text, spans, style, scale, nil)
    if !wrapAnywhere && pills.isEmpty {
        return key
    }
    var h = KeyHasher()
    h.u64(key)
    h.bool(wrapAnywhere)
    h.usize(pills.count)
    for p in pills {
        h.mix(UInt64(p.start) | (UInt64(p.end) << 32))
        h.bool(p.icon != nil)
    }
    return h.hash
}

/// A shaping broken at `maxWidth`, aligned and block-indented: equals `shape` itself when the
/// layout is unwrapped, start-aligned and unindented (matching `textHash(..., nil)`).
func breakKey(
    _ shape: UInt64,
    _ maxWidth: Float?,
    _ align: TextAlignment,
    _ blocks: [Block]?
) -> UInt64 {
    if maxWidth == nil && align == .start && blocks == nil {
        return shape
    }
    var h = KeyHasher()
    h.u64(shape)
    h.optF32(maxWidth)
    h.u8(align.rawValue)
    if let blocks {
        h.u8(1)
        h.usize(blocks.count)
        for b in blocks {
            switch b {
            case .paragraph:
                h.u8(0)
            case .bullet(let l):
                h.u8(1)
                h.u8(l)
            case .numbered(let l):
                h.u8(2)
                h.u8(l)
            case .quote:
                h.u8(3)
            case .code:
                h.u8(4)
            }
        }
    } else {
        h.u8(0)
    }
    return h.hash
}

/// A run's text hashed alone, so each style and scale only mixes it in.
func runHash(_ text: String) -> UInt64 {
    var h = KeyHasher()
    h.str(text)
    return h.hash
}

/// A run's key at one style and scale.
func runKey(_ runHashValue: UInt64, _ style: TextStyle, _ scale: Float) -> UInt64 {
    var h = KeyHasher()
    h.u64(runHashValue)
    h.u64(textHash("", [], style, scale, nil))
    return h.hash
}
