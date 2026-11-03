// Ported from: crates/rune-fx/src/catalog.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The fill catalog: each fill style's id, display name, params (with ranges and units) and named
//! presets, plus generic get/set by param id and Rust emission. A tool can build its style list,
//! inspector and code output from this instead of keeping its own schema.
//!
//! Param ids are the Rust field names, so `FillParams.toRust()` can write struct literals.

import RuneMotion

/// How a number reads in an inspector.
public enum Unit: Sendable, Equatable, Hashable {
    case none
    /// Points.
    case pt
    /// Radians (show as degrees).
    case radians
    /// 0..1 of something (show as a percentage).
    case fraction
    /// Per second (speeds, rates).
    case perSecond
}

/// One option of a choice param.
public struct Choice: Sendable, Equatable, Hashable {
    public var id: String
    public var name: String
    /// The Rust path of the variant, for emitted code.
    public var rust: String

    public init(id: String, name: String, rust: String) {
        self.id = id
        self.name = name
        self.rust = rust
    }
}

public enum ParamKind: Sendable, Equatable {
    /// A float; `step` is a sensible slider step.
    case number(min: Float, max: Float, step: Float, unit: Unit)
    /// A whole number.
    case count(min: UInt32, max: UInt32)
    case toggle
    case choice([Choice])
    case color
    /// An ordered colour list (`Stops`).
    case colors(min: Int, max: Int)
    /// A point in the shape's rect, 0..1 on each axis.
    case point
    /// Up to `max` points in the shape's rect (one per colour of a `Colors` param).
    case points(max: Int)
}

/// A tunable param. Its default is whatever the style's `default()` (or a preset) holds: read it
/// with `FillParams.get`.
public struct Param: Sendable, Equatable {
    /// The Rust field name.
    public var id: String
    public var name: String
    public var kind: ParamKind

    public init(id: String, name: String, kind: ParamKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// A param's value.
public enum Value: Sendable, Equatable {
    case number(Float)
    case count(UInt32)
    case toggle(Bool)
    /// Index into the param's `Choice` list.
    case choice(Int)
    case color(Rgb)
    case colors(Stops)
    case point([Float])
    case points([[Float]])
}

/// A named starting point for a style.
public struct Preset: Sendable, CustomStringConvertible {
    public var id: String
    public var name: String
    /// The Rust expression that builds it, for emitted code.
    public var rust: String
    let make: @Sendable () -> FillStyle

    init(id: String, name: String, rust: String, make: @escaping @Sendable () -> FillStyle) {
        self.id = id
        self.name = name
        self.rust = rust
        self.make = make
    }

    public func style() -> FillStyle {
        make()
    }

    public func fill() -> FillParams {
        FillParams.new(style())
    }

    public var description: String {
        "Preset(id: \"\(id)\")"
    }
}

/// A fill style as a catalog entry.
public struct StyleInfo: Sendable {
    /// Stable id, snake_case (`"liquid_metal"`).
    public var id: String
    public var name: String
    public var summary: String
    /// The params type, for emitted code.
    public var rust: String
    /// The style's own params, in inspector order. `FillParams.common` applies to every style.
    public var params: [Param]
    /// Named presets; the first is the style's `default()`.
    public var presets: [Preset]
    /// Whether the style may read the backdrop (always for glass; for some inputs otherwise).
    /// `Fx.needsBackdrop()` gives the answer for a given set of params.
    public var readsBackdrop: Bool

    public func preset(_ id: String) -> Preset? {
        presets.first { $0.id == id }
    }

    /// The style with its default params.
    public func defaultFill() -> FillParams {
        presets[0].fill()
    }
}

/// Every fill style, in catalog order.
public func fillStyles() -> [StyleInfo] {
    fillStylesTable
}

public func fillStyle(_ id: String) -> StyleInfo? {
    fillStylesTable.first { $0.id == id }
}

// MARK: - ParamValue

protocol ParamValue {
    func toValue() -> Value
    static func fromValue(_ v: Value) -> Self?
    func rust() -> String
}

func formatRustFloat(_ v: Float) -> String {
    let clean: Float = v.isFinite ? (v == 0.0 ? 0.0 : v) : 0.0
    let s = String(clean)
    if s.contains(".") || s.contains("e") || s.contains("E") {
        return s
    }
    return s + ".0"
}

extension Float: ParamValue {
    func toValue() -> Value {
        .number(self)
    }

    static func fromValue(_ v: Value) -> Float? {
        switch v {
        case .number(let x) where x.isFinite:
            return x
        case .count(let n):
            return Float(n)
        default:
            return nil
        }
    }

    func rust() -> String {
        formatRustFloat(self)
    }
}

extension UInt32: ParamValue {
    func toValue() -> Value {
        .count(self)
    }

    static func fromValue(_ v: Value) -> UInt32? {
        switch v {
        case .count(let n):
            return n
        case .number(let x) where x.isFinite:
            let r = Swift.max(x.rounded(), 0.0)
            return r >= 4_294_967_296.0 ? UInt32.max : UInt32(r)
        default:
            return nil
        }
    }

    func rust() -> String {
        String(self)
    }
}

extension Bool: ParamValue {
    func toValue() -> Value {
        .toggle(self)
    }

    static func fromValue(_ v: Value) -> Bool? {
        guard case .toggle(let b) = v else { return nil }
        return b
    }

    func rust() -> String {
        self ? "true" : "false"
    }
}

extension Rgb {
    /// To sRGB hex (0xRRGGBB), rounding.
    public func hex() -> UInt32 {
        @inline(__always)
        func encode(_ c: Float) -> UInt32 {
            let clamped = min(max(c, 0.0), 1.0)
            return UInt32((RuneMotion.srgbEncode(clamped) * 255.0).rounded())
        }
        return (encode(r) << 16) | (encode(g) << 8) | encode(b)
    }
}

extension Rgb: ParamValue {
    func toValue() -> Value {
        .color(self)
    }

    static func fromValue(_ v: Value) -> Rgb? {
        guard case .color(let c) = v else { return nil }
        return c
    }

    func rust() -> String {
        "rgb(0x\(hex6(hex())))"
    }
}

extension Stops: ParamValue {
    func toValue() -> Value {
        .colors(self)
    }

    static func fromValue(_ v: Value) -> Stops? {
        guard case .colors(let s) = v else { return nil }
        return s
    }

    func rust() -> String {
        let items = asSlice().map { "0x\(hex6($0.hex()))" }
        return "Stops::hex(&[\(items.joined(separator: ", "))])"
    }
}

func hex6(_ v: UInt32) -> String {
    let raw = String(v & 0xFF_FFFF, radix: 16, uppercase: false)
    if raw.count >= 6 {
        return raw
    }
    return String(repeating: "0", count: 6 - raw.count) + raw
}

func pointToValue(_ p: [Float]) -> Value {
    .point([p.count > 0 ? p[0] : 0.0, p.count > 1 ? p[1] : 0.0])
}

func pointFromValue(_ v: Value) -> [Float]? {
    guard case .point(let p) = v, p.count == 2, p[0].isFinite, p[1].isFinite else {
        return nil
    }
    return [p[0], p[1]]
}

func pointRust(_ p: [Float]) -> String {
    "[\(formatRustFloat(p[0])), \(formatRustFloat(p[1]))]"
}

func pointsToValue(_ pts: [[Float]]) -> Value {
    .points(pts)
}

func pointsFromValue(_ v: Value) -> [[Float]]? {
    guard case .points(let pts) = v, pts.count == maxStops else { return nil }
    var out: [[Float]] = []
    out.reserveCapacity(maxStops)
    for p in pts {
        guard p.count == 2, p[0].isFinite, p[1].isFinite else { return nil }
        out.append([p[0], p[1]])
    }
    return out
}

func pointsRust(_ pts: [[Float]]) -> String {
    let formatted = pts.map { pointRust($0) }
    return "[\(formatted.joined(separator: ", "))]"
}

func num(_ min: Float, _ max: Float, _ step: Float, _ unit: Unit) -> ParamKind {
    .number(min: min, max: max, step: step, unit: unit)
}

// MARK: - FillParams by id

extension FillParams {
    /// Params every fill style has.
    public static let common: [Param] = [
        Param(id: "border", name: "Border", kind: num(0.0, 32.0, 0.5, .pt)),
        Param(id: "intensity", name: "Intensity", kind: num(0.0, 1.0, 0.01, .fraction)),
    ]

    /// This style's catalog entry.
    public func info() -> StyleInfo {
        fillStylesTable[style.index()]
    }

    /// A param's value, common or the style's own, by id.
    public func get(_ id: String) -> Value? {
        switch id {
        case "border": return .number(border)
        case "intensity": return .number(intensity)
        default: return style.getParam(id)
        }
    }

    /// Set a param by id. False when the id is unknown or the value has the wrong kind.
    public mutating func set(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "border":
            guard let x = Float.fromValue(v) else { return false }
            border = x
            return true
        case "intensity":
            guard let x = Float.fromValue(v) else { return false }
            intensity = x
            return true
        default:
            return style.setParam(id, v)
        }
    }

    /// Rust that rebuilds these params: `Fx::fill(...)`, written against the closest preset.
    public func toRust() -> String {
        let info = self.info()
        var best: (count: Int, preset: Preset, diff: [String])?
        for p in info.presets {
            let base = p.style()
            var diff: [String] = []
            for q in info.params where base.getParam(q.id) != style.getParam(q.id) {
                if let val = style.rustField(q.id) {
                    diff.append("\(q.id): \(val)")
                }
            }
            if best == nil || diff.count < best!.count {
                best = (diff.count, p, diff)
            }
        }
        let chosen = best!
        var s: String
        if chosen.diff.isEmpty {
            s = chosen.preset.rust
        } else {
            s = "\(info.rust) { \(chosen.diff.joined(separator: ", ")), ..\(chosen.preset.rust) }"
        }
        if border != 0.0 {
            s += ".border(\(formatRustFloat(border)))"
        }
        if intensity != 1.0 {
            s += ".intensity(\(formatRustFloat(intensity)))"
        }
        return "Fx::fill(\(s))"
    }
}

// MARK: - Catalog Table

private let fillStylesTable: [StyleInfo] = [
    StyleInfo(
        id: "liquid_metal",
        name: "Liquid metal",
        summary: "Polished metal reflecting a studio, flowing like liquid. Works as a fill or a tube-like border.",
        rust: "LiquidMetalParams",
        params: LiquidMetalParams.params,
        presets: [
            Preset(id: "chrome", name: "Chrome", rust: "LiquidMetalParams::chrome()") { .liquidMetal(.chrome()) },
            Preset(id: "gold", name: "Gold", rust: "LiquidMetalParams::gold()") { .liquidMetal(.gold()) },
            Preset(id: "rose", name: "Rose gold", rust: "LiquidMetalParams::rose()") { .liquidMetal(.rose()) },
            Preset(id: "gunmetal", name: "Gunmetal", rust: "LiquidMetalParams::gunmetal()") { .liquidMetal(.gunmetal()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "mesh_gradient",
        name: "Mesh gradient",
        summary: "Up to six colours pinned to slowly drifting points, blended in OKLab.",
        rust: "MeshGradientParams",
        params: MeshGradientParams.params,
        presets: [
            Preset(id: "dusk", name: "Dusk", rust: "MeshGradientParams::dusk()") { .meshGradient(.dusk()) },
            Preset(id: "lagoon", name: "Lagoon", rust: "MeshGradientParams::lagoon()") { .meshGradient(.lagoon()) },
            Preset(id: "orchid", name: "Orchid", rust: "MeshGradientParams::orchid()") { .meshGradient(.orchid()) },
            Preset(id: "graphite", name: "Graphite", rust: "MeshGradientParams::graphite()") { .meshGradient(.graphite()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "dither",
        name: "Dither",
        summary: "Bayer or blue-noise dithering of a ramp, noise, the backdrop or an image into a palette.",
        rust: "DitherParams",
        params: DitherParams.params,
        presets: [
            Preset(id: "bayer", name: "Bayer", rust: "DitherParams::bayer()") { .dither(.bayer()) },
            Preset(id: "handheld", name: "Handheld", rust: "DitherParams::handheld()") { .dither(.handheld()) },
            Preset(id: "grain", name: "Blue noise", rust: "DitherParams::grain()") { .dither(.grain()) },
            Preset(id: "backdrop", name: "Backdrop", rust: "DitherParams::backdrop()") { .dither(.backdrop()) },
        ],
        readsBackdrop: true
    ),
    StyleInfo(
        id: "grain_gradient",
        name: "Grain gradient",
        summary: "A linear, radial or conic gradient scattered into film grain.",
        rust: "GrainGradientParams",
        params: GrainGradientParams.params,
        presets: [
            Preset(id: "ember", name: "Ember", rust: "GrainGradientParams::ember()") { .grainGradient(.ember()) },
            Preset(id: "halo", name: "Halo", rust: "GrainGradientParams::halo()") { .grainGradient(.halo()) },
            Preset(id: "sweep", name: "Sweep", rust: "GrainGradientParams::sweep()") { .grainGradient(.sweep()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "fluted_glass",
        name: "Fluted glass",
        summary: "Reeded glass over the backdrop: each rib shows a squeezed, flipped strip of what is behind.",
        rust: "FlutedGlassParams",
        params: FlutedGlassParams.params,
        presets: [
            Preset(id: "reeded", name: "Reeded", rust: "FlutedGlassParams::reeded()") { .flutedGlass(.reeded()) },
            Preset(id: "fine", name: "Fine", rust: "FlutedGlassParams::fine()") { .flutedGlass(.fine()) },
            Preset(id: "frosted", name: "Frosted", rust: "FlutedGlassParams::frosted()") { .flutedGlass(.frosted()) },
            Preset(id: "wide", name: "Wide", rust: "FlutedGlassParams::wide()") { .flutedGlass(.wide()) },
        ],
        readsBackdrop: true
    ),
    StyleInfo(
        id: "metaballs",
        name: "Metaballs",
        summary: "Glossy blobs that drift and merge.",
        rust: "MetaballParams",
        params: MetaballParams.params,
        presets: [
            Preset(id: "lava", name: "Lava", rust: "MetaballParams::lava()") { .metaballs(.lava()) },
            Preset(id: "mint", name: "Mint", rust: "MetaballParams::mint()") { .metaballs(.mint()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "swirl",
        name: "Swirl",
        summary: "Colours stirred into a slow swirl.",
        rust: "SwirlParams",
        params: SwirlParams.params,
        presets: [
            Preset(id: "ink", name: "Ink", rust: "SwirlParams::ink()") { .swirl(.ink()) },
            Preset(id: "marble", name: "Marble", rust: "SwirlParams::marble()") { .swirl(.marble()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "voronoi",
        name: "Voronoi",
        summary: "Cells around drifting seed points, with seams.",
        rust: "VoronoiParams",
        params: VoronoiParams.params,
        presets: [
            Preset(id: "cells", name: "Cells", rust: "VoronoiParams::cells()") { .voronoi(.cells()) },
            Preset(id: "stained", name: "Stained glass", rust: "VoronoiParams::stained()") { .voronoi(.stained()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "waves",
        name: "Waves",
        summary: "Layered bands of colour with rolling edges.",
        rust: "WaveParams",
        params: WaveParams.params,
        presets: [
            Preset(id: "sea", name: "Sea", rust: "WaveParams::sea()") { .waves(.sea()) },
            Preset(id: "dunes", name: "Dunes", rust: "WaveParams::dunes()") { .waves(.dunes()) },
        ],
        readsBackdrop: false
    ),
    StyleInfo(
        id: "halftone",
        name: "Halftone",
        summary: "Print dots on a rotated screen, sized by a ramp, noise, the backdrop or an image.",
        rust: "HalftoneParams",
        params: HalftoneParams.params,
        presets: [
            Preset(id: "print", name: "Print", rust: "HalftoneParams::print()") { .halftone(.print()) },
            Preset(id: "backdrop", name: "Backdrop", rust: "HalftoneParams::backdrop()") { .halftone(.backdrop()) },
        ],
        readsBackdrop: true
    ),
    StyleInfo(
        id: "plastic",
        name: "Plastic",
        summary: "Moulded plastic under a soft light: glossy to matte, domed or dished, with a rolled rim.",
        rust: "PlasticParams",
        params: PlasticParams.params,
        presets: [
            Preset(id: "glossy", name: "Glossy", rust: "PlasticParams::glossy()") { .plastic(.glossy()) },
            Preset(id: "matte", name: "Matte", rust: "PlasticParams::matte()") { .plastic(.matte()) },
            Preset(id: "dished", name: "Dished", rust: "PlasticParams::dished()") { .plastic(.dished()) },
        ],
        readsBackdrop: false
    ),
]
