// Ported from: crates/rune-motion/src/value.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation

/// Most lanes a single animated value may have.
public let maxLanes: Int = 16

/// Inline fixed-capacity buffer of `maxLanes` scalar lanes used inside the animation engine so
/// sampling, retargeting and ticking never allocate on the heap.
// PORT NOTE: Swift structs with 16 stored `Float` fields replace `[f32; MAX_LANES]` without
// requiring macOS 26 `InlineArray` or heap-allocating `[Float]`.
struct LaneStorage: Sendable, Equatable {
    var l0: Float = 0.0
    var l1: Float = 0.0
    var l2: Float = 0.0
    var l3: Float = 0.0
    var l4: Float = 0.0
    var l5: Float = 0.0
    var l6: Float = 0.0
    var l7: Float = 0.0
    var l8: Float = 0.0
    var l9: Float = 0.0
    var l10: Float = 0.0
    var l11: Float = 0.0
    var l12: Float = 0.0
    var l13: Float = 0.0
    var l14: Float = 0.0
    var l15: Float = 0.0

    @inline(__always)
    subscript(_ index: Int) -> Float {
        get {
            switch index {
            case 0: return l0
            case 1: return l1
            case 2: return l2
            case 3: return l3
            case 4: return l4
            case 5: return l5
            case 6: return l6
            case 7: return l7
            case 8: return l8
            case 9: return l9
            case 10: return l10
            case 11: return l11
            case 12: return l12
            case 13: return l13
            case 14: return l14
            case 15: return l15
            default: preconditionFailure("Lane index \(index) out of range 0..<\(maxLanes)")
            }
        }
        set {
            switch index {
            case 0: l0 = newValue
            case 1: l1 = newValue
            case 2: l2 = newValue
            case 3: l3 = newValue
            case 4: l4 = newValue
            case 5: l5 = newValue
            case 6: l6 = newValue
            case 7: l7 = newValue
            case 8: l8 = newValue
            case 9: l9 = newValue
            case 10: l10 = newValue
            case 11: l11 = newValue
            case 12: l12 = newValue
            case 13: l13 = newValue
            case 14: l14 = newValue
            case 15: l15 = newValue
            default: preconditionFailure("Lane index \(index) out of range 0..<\(maxLanes)")
            }
        }
    }

    @inline(__always)
    mutating func withMutableBuffer<R>(
        count: Int,
        _ body: (UnsafeMutableBufferPointer<Float>) -> R
    ) -> R {
        withUnsafeMutableBytes(of: &self) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: Float.self)
            return body(UnsafeMutableBufferPointer(start: ptr, count: count))
        }
    }

    @inline(__always)
    func withBuffer<R>(
        count: Int,
        _ body: (UnsafeBufferPointer<Float>) -> R
    ) -> R {
        withUnsafeBytes(of: self) { raw in
            let ptr = raw.baseAddress!.assumingMemoryBound(to: Float.self)
            return body(UnsafeBufferPointer(start: ptr, count: count))
        }
    }
}

/// A value made of `lanes` independent scalar lanes (a vector space).
public protocol Animatable: Sendable {
    static var lanes: Int { get }
    func writeLanes(_ out: UnsafeMutableBufferPointer<Float>)
    static func readLanes(_ lanes: UnsafeBufferPointer<Float>) -> Self

    func add(_ other: Self) -> Self
    func sub(_ other: Self) -> Self
    func scale(_ k: Float) -> Self
    /// Euclidean distance in lane space.
    func distance(_ other: Self) -> Float
    /// `self + (other − self) · t` in lane space.
    func lerp(_ other: Self, _ t: Float) -> Self
}

extension Animatable {
    public func add(_ other: Self) -> Self {
        zipLanes(self, other) { a, b in a + b }
    }

    public func sub(_ other: Self) -> Self {
        zipLanes(self, other) { a, b in a - b }
    }

    public func scale(_ k: Float) -> Self {
        zipLanes(self, self) { a, _ in a * k }
    }

    public func distance(_ other: Self) -> Float {
        let a = RuneMotion.lanes(self)
        let b = RuneMotion.lanes(other)
        var sum: Float = 0.0
        for i in 0..<Self.lanes {
            let d = a[i] - b[i]
            sum += d * d
        }
        return sum.squareRoot()
    }

    public func lerp(_ other: Self, _ t: Float) -> Self {
        zipLanes(self, other) { a, b in a + (b - a) * t }
    }

    /// Convenience array overload matching Rust `write_lanes(&mut [f32])`.
    public func writeLanes(_ out: inout [Float]) {
        out.withUnsafeMutableBufferPointer { buf in
            writeLanes(UnsafeMutableBufferPointer(rebasing: buf.prefix(Self.lanes)))
        }
    }

    /// Convenience array overload matching Rust `read_lanes(&[f32])`.
    public static func readLanes(_ lanes: [Float]) -> Self {
        lanes.withUnsafeBufferPointer { buf in
            readLanes(UnsafeBufferPointer(rebasing: buf.prefix(Self.lanes)))
        }
    }

    /// Convenience slice overload.
    public static func readLanes(_ lanes: ArraySlice<Float>) -> Self {
        lanes.withUnsafeBufferPointer { buf in
            readLanes(UnsafeBufferPointer(rebasing: buf.prefix(Self.lanes)))
        }
    }
}

@inline(__always)
func lanes<T: Animatable>(_ v: T) -> LaneStorage {
    precondition(T.lanes <= maxLanes, "at most \(maxLanes) lanes")
    var out = LaneStorage()
    out.withMutableBuffer(count: T.lanes) { buf in
        v.writeLanes(buf)
    }
    return out
}

@inline(__always)
private func zipLanes<T: Animatable>(_ a: T, _ b: T, _ f: (Float, Float) -> Float) -> T {
    let x = lanes(a)
    let y = lanes(b)
    var out = LaneStorage()
    for i in 0..<T.lanes {
        out[i] = f(x[i], y[i])
    }
    return out.withBuffer(count: T.lanes) { T.readLanes($0) }
}

extension Float: Animatable {
    public static let lanes: Int = 1

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = self
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Float {
        l[0]
    }
}

/// A 2D point, size or offset in points.
public struct Vec2: Sendable, Equatable, Hashable, Codable {
    public var x: Float
    public var y: Float

    public static let zero = Vec2(0.0, 0.0)

    public init() {
        self.x = 0.0
        self.y = 0.0
    }

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    public static func new(_ x: Float, _ y: Float) -> Vec2 {
        Vec2(x, y)
    }
}

extension Vec2: Animatable {
    public static let lanes: Int = 2

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = x
        out[1] = y
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Vec2 {
        Vec2(l[0], l[1])
    }
}

/// An axis-aligned rectangle. It animates as its four **edges** (left, top, right, bottom), so an
/// edge that doesn't move has no motion at all and can't jiggle (research 06 §2.7).
public struct Rect: Sendable, Equatable, Hashable, Codable {
    public var x: Float
    public var y: Float
    public var w: Float
    public var h: Float

    public static let zero = Rect(0.0, 0.0, 0.0, 0.0)

    public init() {
        self.x = 0.0
        self.y = 0.0
        self.w = 0.0
        self.h = 0.0
    }

    public init(_ x: Float, _ y: Float, _ w: Float, _ h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(x: Float, y: Float, w: Float, h: Float) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public static func new(_ x: Float, _ y: Float, _ w: Float, _ h: Float) -> Rect {
        Rect(x, y, w, h)
    }

    public static func fromEdges(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Rect {
        Rect(left, top, right - left, bottom - top)
    }

    public func right() -> Float {
        x + w
    }

    public func bottom() -> Float {
        y + h
    }

    public func edges() -> [Float] {
        [x, y, right(), bottom()]
    }

    @inline(__always)
    func edgesTuple() -> (Float, Float, Float, Float) {
        (x, y, x + w, y + h)
    }

    public func origin() -> Vec2 {
        Vec2(x, y)
    }

    public func size() -> Vec2 {
        Vec2(w, h)
    }

    public func center() -> Vec2 {
        Vec2(x + w * 0.5, y + h * 0.5)
    }

    public func translated(_ d: Vec2) -> Rect {
        Rect(x + d.x, y + d.y, w, h)
    }

    public func inflate(_ m: Float) -> Rect {
        Rect(x - m, y - m, w + 2.0 * m, h + 2.0 * m)
    }

    public func union(_ o: Rect) -> Rect {
        let x0 = min(x, o.x)
        let y0 = min(y, o.y)
        let x1 = max(x + w, o.x + o.w)
        let y1 = max(y + h, o.y + o.h)
        return Rect(x0, y0, x1 - x0, y1 - y0)
    }

    public static func fromPoints(_ a: [Float], _ b: [Float]) -> Rect {
        let x0 = min(a[0], b[0])
        let y0 = min(a[1], b[1])
        return Rect(x0, y0, abs(a[0] - b[0]), abs(a[1] - b[1]))
    }

    public static func fromPoints(_ a: (Float, Float), _ b: (Float, Float)) -> Rect {
        let x0 = min(a.0, b.0)
        let y0 = min(a.1, b.1)
        return Rect(x0, y0, abs(a.0 - b.0), abs(a.1 - b.1))
    }

    public func xywh() -> [Float] {
        [x, y, w, h]
    }
}

extension Rect: Animatable {
    public static let lanes: Int = 4

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = x
        out[1] = y
        out[2] = x + w
        out[3] = y + h
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Rect {
        Rect.fromEdges(l[0], l[1], l[2], l[3])
    }
}

/// Per-corner radii: top-left, top-right, bottom-right, bottom-left.
// PORT NOTE: Stored as 4 inline `Float`s instead of `[Float]` so `Corners` is stack-allocated.
public struct Corners: Sendable, Equatable, Hashable {
    public var c0: Float
    public var c1: Float
    public var c2: Float
    public var c3: Float

    public static let zero = Corners(0.0, 0.0, 0.0, 0.0)

    public init() {
        self.c0 = 0.0
        self.c1 = 0.0
        self.c2 = 0.0
        self.c3 = 0.0
    }

    public init(_ c0: Float, _ c1: Float, _ c2: Float, _ c3: Float) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
        self.c3 = c3
    }

    public init(_ values: [Float]) {
        precondition(values.count >= 4, "Corners requires 4 values")
        self.c0 = values[0]
        self.c1 = values[1]
        self.c2 = values[2]
        self.c3 = values[3]
    }

    public init(_ values: (Float, Float, Float, Float)) {
        self.c0 = values.0
        self.c1 = values.1
        self.c2 = values.2
        self.c3 = values.3
    }

    /// `From<f32> for Corners` (`Corners::all(r)`).
    public init(_ r: Float) {
        self.c0 = r
        self.c1 = r
        self.c2 = r
        self.c3 = r
    }

    public static func all(_ r: Float) -> Corners {
        Corners(r, r, r, r)
    }

    public var values: [Float] {
        get { [c0, c1, c2, c3] }
        set {
            precondition(newValue.count >= 4, "Corners requires 4 values")
            c0 = newValue[0]
            c1 = newValue[1]
            c2 = newValue[2]
            c3 = newValue[3]
        }
    }

    @inline(__always)
    public subscript(_ index: Int) -> Float {
        get {
            switch index {
            case 0: return c0
            case 1: return c1
            case 2: return c2
            case 3: return c3
            default: preconditionFailure("Corners index \(index) out of range 0..<4")
            }
        }
        set {
            switch index {
            case 0: c0 = newValue
            case 1: c1 = newValue
            case 2: c2 = newValue
            case 3: c3 = newValue
            default: preconditionFailure("Corners index \(index) out of range 0..<4")
            }
        }
    }
}

extension Corners: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let v0 = try container.decode(Float.self)
        let v1 = try container.decode(Float.self)
        let v2 = try container.decode(Float.self)
        let v3 = try container.decode(Float.self)
        self.init(v0, v1, v2, v3)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(c0)
        try container.encode(c1)
        try container.encode(c2)
        try container.encode(c3)
    }
}

extension Corners: Animatable {
    public static let lanes: Int = 4

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = c0
        out[1] = c1
        out[2] = c2
        out[3] = c3
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Corners {
        Corners(l[0], l[1], l[2], l[3])
    }
}

/// Insets per side (left, top, right, bottom): mask insets and feathers.
// PORT NOTE: Stored as 4 inline `Float`s instead of `[Float]` so `Sides` is stack-allocated.
public struct Sides: Sendable, Equatable, Hashable {
    public var s0: Float
    public var s1: Float
    public var s2: Float
    public var s3: Float

    public static let zero = Sides(0.0, 0.0, 0.0, 0.0)

    public init() {
        self.s0 = 0.0
        self.s1 = 0.0
        self.s2 = 0.0
        self.s3 = 0.0
    }

    public init(_ s0: Float, _ s1: Float, _ s2: Float, _ s3: Float) {
        self.s0 = s0
        self.s1 = s1
        self.s2 = s2
        self.s3 = s3
    }

    public init(_ values: [Float]) {
        precondition(values.count >= 4, "Sides requires 4 values")
        self.s0 = values[0]
        self.s1 = values[1]
        self.s2 = values[2]
        self.s3 = values[3]
    }

    public init(_ values: (Float, Float, Float, Float)) {
        self.s0 = values.0
        self.s1 = values.1
        self.s2 = values.2
        self.s3 = values.3
    }

    public static func all(_ v: Float) -> Sides {
        Sides(v, v, v, v)
    }

    public var values: [Float] {
        get { [s0, s1, s2, s3] }
        set {
            precondition(newValue.count >= 4, "Sides requires 4 values")
            s0 = newValue[0]
            s1 = newValue[1]
            s2 = newValue[2]
            s3 = newValue[3]
        }
    }

    @inline(__always)
    public subscript(_ index: Int) -> Float {
        get {
            switch index {
            case 0: return s0
            case 1: return s1
            case 2: return s2
            case 3: return s3
            default: preconditionFailure("Sides index \(index) out of range 0..<4")
            }
        }
        set {
            switch index {
            case 0: s0 = newValue
            case 1: s1 = newValue
            case 2: s2 = newValue
            case 3: s3 = newValue
            default: preconditionFailure("Sides index \(index) out of range 0..<4")
            }
        }
    }
}

extension Sides: Codable {
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let v0 = try container.decode(Float.self)
        let v1 = try container.decode(Float.self)
        let v2 = try container.decode(Float.self)
        let v3 = try container.decode(Float.self)
        self.init(v0, v1, v2, v3)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(s0)
        try container.encode(s1)
        try container.encode(s2)
        try container.encode(s3)
    }
}

extension Sides: Animatable {
    public static let lanes: Int = 4

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = s0
        out[1] = s1
        out[2] = s2
        out[3] = s3
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Sides {
        Sides(l[0], l[1], l[2], l[3])
    }
}

/// A Gaussian blur sigma (standard deviation) in points.
public struct Blur: Sendable, Equatable, Hashable, Codable, RawRepresentable {
    public var rawValue: Float

    public var value: Float {
        get { rawValue }
        set { rawValue = newValue }
    }

    public init() {
        self.rawValue = 0.0
    }

    public init(_ rawValue: Float) {
        self.rawValue = rawValue
    }

    public init(rawValue: Float) {
        self.rawValue = rawValue
    }
}

extension Blur: Animatable {
    public static let lanes: Int = 1

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = rawValue
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Blur {
        Blur(l[0])
    }
}

/// A decomposed 2D transform: translate, then scale and rotate about the node's anchor.
/// Decomposed parts animate independently, so a spinning, growing card never shears.
public struct Transform: Sendable, Equatable, Hashable, Codable {
    public var translate: Vec2
    public var scale: Vec2
    /// Radians, unwrapped: animating 0 → 4π spins twice, always the same way.
    public var rotate: Float

    public static let identity = Transform(
        translate: .zero,
        scale: Vec2(1.0, 1.0),
        rotate: 0.0
    )

    public init() {
        self = .identity
    }

    public init(translate: Vec2 = .zero, scale: Vec2 = Vec2(1.0, 1.0), rotate: Float = 0.0) {
        self.translate = translate
        self.scale = scale
        self.rotate = rotate
    }

    /// The 2×3 affine matrix `[a, b, c, d, tx, ty]` (column-major like CGAffineTransform) that
    /// applies this transform about `anchor` (in the same space as the translate).
    public func toAffine(_ anchor: Vec2) -> [Float] {
        let (s, c) = math.sinCos(rotate)
        let a = c * scale.x
        let b = s * scale.x
        let cc = -s * scale.y
        let d = c * scale.y
        // p' = M (p − anchor) + anchor + translate
        let tx = anchor.x + translate.x - (a * anchor.x + cc * anchor.y)
        let ty = anchor.y + translate.y - (b * anchor.x + d * anchor.y)
        return [a, b, cc, d, tx, ty]
    }
}

extension Transform: Animatable {
    public static let lanes: Int = 5

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        out[0] = translate.x
        out[1] = translate.y
        out[2] = scale.x
        out[3] = scale.y
        out[4] = rotate
    }

    @inline(__always)
    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> Transform {
        Transform(translate: Vec2(l[0], l[1]), scale: Vec2(l[2], l[3]), rotate: l[4])
    }
}

/// An sRGB colour with straight (unpremultiplied) alpha, components in 0…1.
///
/// It animates in **premultiplied OKLab** (`[L·α, a·α, b·α, α]`): hue changes don't pass through
/// grey, and fading to transparent doesn't drag the colour toward black.
public struct Color: Sendable, Equatable, Hashable, Codable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public static let transparent = Color(r: 0.0, g: 0.0, b: 0.0, a: 0.0)
    public static let black = Color(r: 0.0, g: 0.0, b: 0.0, a: 1.0)
    public static let white = Color(r: 1.0, g: 1.0, b: 1.0, a: 1.0)

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

    public static func rgba(_ r: Float, _ g: Float, _ b: Float, _ a: Float) -> Color {
        Color(r: r, g: g, b: b, a: a)
    }

    /// `0xRRGGBB` with alpha 1.
    public static func hex(_ rgb: UInt32) -> Color {
        Color(
            r: Float((rgb >> 16) & 0xff) / 255.0,
            g: Float((rgb >> 8) & 0xff) / 255.0,
            b: Float(rgb & 0xff) / 255.0,
            a: 1.0
        )
    }

    public func withAlpha(_ a: Float) -> Color {
        Color(r: r, g: g, b: b, a: a)
    }

    /// `[L, a, b]` in OKLab (Björn Ottosson's matrices).
    public func toOklab() -> [Float] {
        let (l, aLab, bLab) = linearToOklabTuple(srgbDecode(r), srgbDecode(g), srgbDecode(b))
        return [l, aLab, bLab]
    }

    public static func fromOklab(_ lab: [Float], _ alpha: Float) -> Color {
        let (lr, lg, lb) = oklabToLinearTuple(lab[0], lab[1], lab[2])
        return Color(
            r: srgbEncode(min(max(lr, 0.0), 1.0)),
            g: srgbEncode(min(max(lg, 0.0), 1.0)),
            b: srgbEncode(min(max(lb, 0.0), 1.0)),
            a: alpha
        )
    }
}

@inline(__always)
private func linearToOklabTuple(_ r: Float, _ g: Float, _ b: Float) -> (Float, Float, Float) {
    let l = cbrtf(0.412_221_47 * r + 0.536_332_55 * g + 0.051_445_995 * b)
    let m = cbrtf(0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b)
    let s = cbrtf(0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b)
    return (
        0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s,
        1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s
    )
}

@inline(__always)
private func oklabToLinearTuple(_ ll: Float, _ a: Float, _ b: Float) -> (Float, Float, Float) {
    let l0 = ll + 0.396_337_78 * a + 0.215_803_76 * b
    let m0 = ll - 0.105_561_346 * a - 0.063_854_17 * b
    let s0 = ll - 0.089_484_18 * a - 1.291_485_5 * b
    let l = l0 * l0 * l0
    let m = m0 * m0 * m0
    let s = s0 * s0 * s0
    return (
        4.076_741_7 * l - 3.307_711_6 * m + 0.230_969_94 * s,
        -1.268_438 * l + 2.609_757_4 * m - 0.341_319_38 * s,
        -0.004_196_086_3 * l - 0.703_418_6 * m + 1.707_614_7 * s
    )
}

/// Linear sRGB `[r, g, b]` to OKLab `[L, a, b]` (Björn Ottosson's matrices).
public func linearToOklab(_ r: Float, _ g: Float, _ b: Float) -> [Float] {
    let (l, a, bLab) = linearToOklabTuple(r, g, b)
    return [l, a, bLab]
}

/// OKLab `[L, a, b]` to unclamped linear sRGB `[r, g, b]`.
public func oklabToLinear(_ lab: [Float]) -> [Float] {
    let (r, g, b) = oklabToLinearTuple(lab[0], lab[1], lab[2])
    return [r, g, b]
}

public func srgbDecode(_ c: Float) -> Float {
    if c <= 0.040_45 {
        return c / 12.92
    } else {
        return powf((c + 0.055) / 1.055, 2.4)
    }
}

public func srgbEncode(_ c: Float) -> Float {
    if c <= 0.003_130_8 {
        return c * 12.92
    } else {
        return 1.055 * powf(c, 1.0 / 2.4) - 0.055
    }
}

extension Color: Animatable {
    public static let lanes: Int = 4

    @inline(__always)
    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        let (l, aLab, bLab) = linearToOklabTuple(srgbDecode(r), srgbDecode(g), srgbDecode(b))
        let al = a
        out[0] = l * al
        out[1] = aLab * al
        out[2] = bLab * al
        out[3] = al
    }

    @inline(__always)
    public static func readLanes(_ x: UnsafeBufferPointer<Float>) -> Color {
        let alpha = min(max(x[3], 0.0), 1.0)
        if x[3] <= 1e-6 {
            return .transparent
        }
        let inv = 1.0 / x[3]
        let (lr, lg, lb) = oklabToLinearTuple(x[0] * inv, x[1] * inv, x[2] * inv)
        return Color(
            r: srgbEncode(min(max(lr, 0.0), 1.0)),
            g: srgbEncode(min(max(lg, 0.0), 1.0)),
            b: srgbEncode(min(max(lb, 0.0), 1.0)),
            a: alpha
        )
    }
}

// PORT NOTE: Swift cannot conform non-nominal tuple types `(A, B)` / `(A, B, C)` or fixed-size
// `[T; N]` arrays to `Animatable`. `AnimatablePair`, `AnimatableTriple` and `AnimatableArray`
// provide nominal wrappers with identical lane layout and `maxLanes` behavior.

/// Two `Animatable` values animated together (Swift nominal counterpart to Rust `(A, B)`).
public struct AnimatablePair<A: Animatable, B: Animatable>: Animatable {
    public var first: A
    public var second: B

    public init(_ first: A, _ second: B) {
        self.first = first
        self.second = second
    }

    public static var lanes: Int { A.lanes + B.lanes }

    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        first.writeLanes(UnsafeMutableBufferPointer(rebasing: out[0..<A.lanes]))
        second.writeLanes(UnsafeMutableBufferPointer(rebasing: out[A.lanes..<(A.lanes + B.lanes)]))
    }

    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> AnimatablePair<A, B> {
        let first = A.readLanes(UnsafeBufferPointer(rebasing: l[0..<A.lanes]))
        let second = B.readLanes(UnsafeBufferPointer(rebasing: l[A.lanes..<(A.lanes + B.lanes)]))
        return AnimatablePair(first, second)
    }
}

extension AnimatablePair: Equatable where A: Equatable, B: Equatable {}
extension AnimatablePair: Hashable where A: Hashable, B: Hashable {}

/// Three `Animatable` values animated together (Swift nominal counterpart to Rust `(A, B, C)`).
public struct AnimatableTriple<A: Animatable, B: Animatable, C: Animatable>: Animatable {
    public var first: A
    public var second: B
    public var third: C

    public init(_ first: A, _ second: B, _ third: C) {
        self.first = first
        self.second = second
        self.third = third
    }

    public static var lanes: Int { A.lanes + B.lanes + C.lanes }

    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        let a = A.lanes
        let b = A.lanes + B.lanes
        first.writeLanes(UnsafeMutableBufferPointer(rebasing: out[0..<a]))
        second.writeLanes(UnsafeMutableBufferPointer(rebasing: out[a..<b]))
        third.writeLanes(UnsafeMutableBufferPointer(rebasing: out[b..<(b + C.lanes)]))
    }

    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> AnimatableTriple<A, B, C> {
        let a = A.lanes
        let b = A.lanes + B.lanes
        return AnimatableTriple(
            A.readLanes(UnsafeBufferPointer(rebasing: l[0..<a])),
            B.readLanes(UnsafeBufferPointer(rebasing: l[a..<b])),
            C.readLanes(UnsafeBufferPointer(rebasing: l[b..<(b + C.lanes)]))
        )
    }
}

extension AnimatableTriple: Equatable where A: Equatable, B: Equatable, C: Equatable {}
extension AnimatableTriple: Hashable where A: Hashable, B: Hashable, C: Hashable {}

/// Type-level integer count witness for `AnimatableArray` so `Animatable.lanes` stays a static
/// property without integer generic parameters requiring macOS 26.
public protocol LaneCount: Sendable {
    static var count: Int { get }
}

public enum Count1: LaneCount { public static let count = 1 }
public enum Count2: LaneCount { public static let count = 2 }
public enum Count3: LaneCount { public static let count = 3 }
public enum Count4: LaneCount { public static let count = 4 }
public enum Count5: LaneCount { public static let count = 5 }
public enum Count6: LaneCount { public static let count = 6 }
public enum Count8: LaneCount { public static let count = 8 }
public enum Count16: LaneCount { public static let count = 16 }

/// Fixed-length array of `Animatable` values (Swift nominal counterpart to Rust `[T; N]`).
public struct AnimatableArray<T: Animatable, N: LaneCount>: Animatable {
    public var elements: [T]

    public init(_ elements: [T]) {
        precondition(elements.count == N.count, "Expected \(N.count) elements, got \(elements.count)")
        self.elements = elements
    }

    public init(repeating value: T) {
        self.elements = Array(repeating: value, count: N.count)
    }

    public static var lanes: Int { T.lanes * N.count }

    public subscript(_ index: Int) -> T {
        get { elements[index] }
        set { elements[index] = newValue }
    }

    public func writeLanes(_ out: UnsafeMutableBufferPointer<Float>) {
        let stride = T.lanes
        for i in 0..<N.count {
            elements[i].writeLanes(
                UnsafeMutableBufferPointer(rebasing: out[(i * stride)..<((i + 1) * stride)])
            )
        }
    }

    public static func readLanes(_ l: UnsafeBufferPointer<Float>) -> AnimatableArray<T, N> {
        let stride = T.lanes
        var out: [T] = []
        out.reserveCapacity(N.count)
        for i in 0..<N.count {
            out.append(T.readLanes(UnsafeBufferPointer(rebasing: l[(i * stride)..<((i + 1) * stride)])))
        }
        return AnimatableArray(out)
    }
}

extension AnimatableArray: Equatable where T: Equatable {}
extension AnimatableArray: Hashable where T: Hashable {}
