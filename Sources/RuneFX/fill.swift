// Ported from: crates/rune-fx/src/fill.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Fills: styles that paint a node's whole shape, or a band inside its edge as a stroke. They share
//! the shape mask (`FillParams.border`), colour lists (`Stops`, blended in OKLab) and one input
//! for the styles that re-tone something (`FillInput`: a ramp, noise, the backdrop or an image).
//!
//! Every style is a pure function of (pixel, params, time, seed). Under reduced motion each one
//! holds a single settled pose. `catalog` lists the styles, their params and presets.

import RuneMotion

// MARK: - Colours

/// Most colours a `Stops` list holds.
public let maxStops: Int = 6

/// An ordered list of 1 to `maxStops` colours (linear light).
public struct Stops: Sendable, Equatable, Hashable {
    private var storage: [Rgb]

    /// Keeps the first `maxStops`; an empty list is one black stop.
    public init(_ colors: [Rgb]) {
        if colors.isEmpty {
            self.storage = [Rgb(0.0, 0.0, 0.0)]
        } else {
            self.storage = Array(colors.prefix(maxStops))
        }
    }

    public static func new(_ colors: [Rgb]) -> Stops {
        Stops(colors)
    }

    /// From sRGB hex colours (0xRRGGBB).
    public static func hex(_ hex: [UInt32]) -> Stops {
        Stops.new(hex.map { rgb($0) })
    }

    public func asSlice() -> [Rgb] {
        storage
    }

    public func len() -> Int {
        storage.count
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        false
    }
}

/// Linear sRGB to OKLab.
func oklab(_ c: Rgb) -> [Float] {
    let r = c.r
    let g = c.g
    let b = c.b
    let l = FoundationCompat.cbrt(max(0.412_221_46 * r + 0.536_332_55 * g + 0.051_445_995 * b, 0.0))
    let m = FoundationCompat.cbrt(max(0.211_903_5 * r + 0.680_699_5 * g + 0.107_396_96 * b, 0.0))
    let s = FoundationCompat.cbrt(max(0.088_302_46 * r + 0.281_718_85 * g + 0.629_978_7 * b, 0.0))
    return [
        0.210_454_26 * l + 0.793_617_8 * m - 0.004_072_047 * s,
        1.977_998_5 * l - 2.428_592_2 * m + 0.450_593_7 * s,
        0.025_904_037 * l + 0.782_771_77 * m - 0.808_675_77 * s,
    ]
}

// MARK: - Shared Choices

/// What a re-toning style (dither, halftone) reads as its tone.
public enum FillInput: Sendable, Equatable, Hashable {
    /// A ramp across the shape along `angle`.
    case linear
    /// Light at the centre, dark at the rim.
    case radial
    /// Slowly drifting noise.
    case noise
    /// Whatever is drawn behind the layer (needs a backdrop copy).
    case backdrop
    /// The layer's source texture (`FxLayer.source`).
    case image

    public static let choices: [Choice] = [
        Choice(id: "linear", name: "Linear", rust: "FillInput::Linear"),
        Choice(id: "radial", name: "Radial", rust: "FillInput::Radial"),
        Choice(id: "noise", name: "Noise", rust: "FillInput::Noise"),
        Choice(id: "backdrop", name: "Backdrop", rust: "FillInput::Backdrop"),
        Choice(id: "image", name: "Image", rust: "FillInput::Image"),
    ]

    static let all: [FillInput] = [.linear, .radial, .noise, .backdrop, .image]

    func code() -> Float {
        switch self {
        case .linear: return 0.0
        case .radial: return 1.0
        case .noise: return 2.0
        case .backdrop: return 3.0
        case .image: return 4.0
        }
    }

    func animates() -> Bool {
        self == .noise
    }
}

extension FillInput: ParamValue {
    func toValue() -> Value {
        .choice(Self.all.firstIndex(of: self) ?? 0)
    }

    static func fromValue(_ v: Value) -> FillInput? {
        guard case .choice(let i) = v, i >= 0, i < all.count else { return nil }
        return all[i]
    }

    func rust() -> String {
        Self.choices[Self.all.firstIndex(of: self) ?? 0].rust
    }
}

public enum DitherPattern: Sendable, Equatable, Hashable {
    case bayer2
    case bayer4
    case bayer8
    /// A 32×32 void-and-cluster tile: no visible grid, even grain.
    case blueNoise
    /// Independent random threshold per pixel.
    case white

    public static let choices: [Choice] = [
        Choice(id: "bayer2", name: "Bayer 2×2", rust: "DitherPattern::Bayer2"),
        Choice(id: "bayer4", name: "Bayer 4×4", rust: "DitherPattern::Bayer4"),
        Choice(id: "bayer8", name: "Bayer 8×8", rust: "DitherPattern::Bayer8"),
        Choice(id: "blue_noise", name: "Blue noise", rust: "DitherPattern::BlueNoise"),
        Choice(id: "white", name: "White noise", rust: "DitherPattern::White"),
    ]

    static let all: [DitherPattern] = [.bayer2, .bayer4, .bayer8, .blueNoise, .white]
}

extension DitherPattern: ParamValue {
    func toValue() -> Value {
        .choice(Self.all.firstIndex(of: self) ?? 0)
    }

    static func fromValue(_ v: Value) -> DitherPattern? {
        guard case .choice(let i) = v, i >= 0, i < all.count else { return nil }
        return all[i]
    }

    func rust() -> String {
        Self.choices[Self.all.firstIndex(of: self) ?? 0].rust
    }
}

public enum GradientKind: Sendable, Equatable, Hashable {
    case linear
    case radial
    /// Sweeps around `center`, starting at `angle`.
    case conic

    public static let choices: [Choice] = [
        Choice(id: "linear", name: "Linear", rust: "GradientKind::Linear"),
        Choice(id: "radial", name: "Radial", rust: "GradientKind::Radial"),
        Choice(id: "conic", name: "Conic", rust: "GradientKind::Conic"),
    ]

    static let all: [GradientKind] = [.linear, .radial, .conic]
}

extension GradientKind: ParamValue {
    func toValue() -> Value {
        .choice(Self.all.firstIndex(of: self) ?? 0)
    }

    static func fromValue(_ v: Value) -> GradientKind? {
        guard case .choice(let i) = v, i >= 0, i < all.count else { return nil }
        return all[i]
    }

    func rust() -> String {
        Self.choices[Self.all.firstIndex(of: self) ?? 0].rust
    }
}

/// Where a fill's pattern is pinned.
public enum FillAnchor: Sendable, Equatable, Hashable {
    /// To the window: neighbouring shapes show neighbouring parts of one surface.
    case world
    /// To the shape: every shape of the same size, seed and time looks the same.
    case element

    public static let choices: [Choice] = [
        Choice(id: "world", name: "World", rust: "FillAnchor::World"),
        Choice(id: "element", name: "Element", rust: "FillAnchor::Element"),
    ]

    static let all: [FillAnchor] = [.world, .element]
}

extension FillAnchor: ParamValue {
    func toValue() -> Value {
        .choice(Self.all.firstIndex(of: self) ?? 0)
    }

    static func fromValue(_ v: Value) -> FillAnchor? {
        guard case .choice(let i) = v, i >= 0, i < all.count else { return nil }
        return all[i]
    }

    func rust() -> String {
        Self.choices[Self.all.firstIndex(of: self) ?? 0].rust
    }
}

// MARK: - Styles

/// Polished metal reflecting a studio: a soft overhead key light, a strip light, a bright sky
/// that falls to a hard horizon over a dark floor. The face is gently domed so the horizon
/// crosses it, the rim rolls off over `bevel`, and the surface flows like liquid.
/// As a border (`.border(w)`) it is a round tube.
public struct LiquidMetalParams: Sendable, Equatable, FillStyleConvertible {
    /// Reflectance at normal incidence: near white for chrome, warm for gold.
    public var tint: Rgb
    /// The studio lights' colour.
    public var light: Rgb
    /// How far the surface ripples (0 = a still, polished slab).
    public var flow: Float
    /// Ripple size, pt.
    public var scale: Float
    public var speed: Float
    /// Width of the rolled rim, pt.
    public var bevel: Float
    /// How domed the face is: 0 flat (one reflection everywhere), 1 strongly curved.
    public var dome: Float
    /// Tilt of the studio around the view axis, radians.
    public var angle: Float
    /// Thin-film colour where the surface bends hardest.
    public var iridescence: Float
    /// 1 = studio as lit; higher deepens the floor and sharpens the lights.
    public var contrast: Float
    /// Where the ripples are pinned: `world` (default) flows one surface across neighbouring
    /// shapes; `element` gives every shape of the same size its own identical copy, so a row of
    /// keys matches.
    public var anchor: FillAnchor

    public init(
        tint: Rgb = rgb(0xe9ecf0),
        light: Rgb = rgb(0xffffff),
        flow: Float = 0.6,
        scale: Float = 100.0,
        speed: Float = 0.35,
        bevel: Float = 14.0,
        dome: Float = 0.55,
        angle: Float = -0.12,
        iridescence: Float = 0.08,
        contrast: Float = 1.0,
        anchor: FillAnchor = .world
    ) {
        self.tint = tint
        self.light = light
        self.flow = flow
        self.scale = scale
        self.speed = speed
        self.bevel = bevel
        self.dome = dome
        self.angle = angle
        self.iridescence = iridescence
        self.contrast = contrast
        self.anchor = anchor
    }

    public static func `default`() -> LiquidMetalParams {
        .chrome()
    }

    public static func chrome() -> LiquidMetalParams {
        LiquidMetalParams()
    }

    /// `LiquidMetalParams.chrome().anchor(.element)`.
    public func anchor(_ anchor: FillAnchor) -> LiquidMetalParams {
        var copy = self
        copy.anchor = anchor
        return copy
    }

    public static func gold() -> LiquidMetalParams {
        var p = chrome()
        p.tint = rgb(0xf3c56b)
        p.light = rgb(0xfff4dc)
        p.iridescence = 0.0
        return p
    }

    public static func rose() -> LiquidMetalParams {
        var p = chrome()
        p.tint = rgb(0xf2b7a2)
        p.light = rgb(0xfff0ea)
        p.iridescence = 0.05
        return p
    }

    public static func gunmetal() -> LiquidMetalParams {
        var p = chrome()
        p.tint = rgb(0x8d949e)
        p.light = rgb(0xe8f0ff)
        p.contrast = 1.35
        p.iridescence = 0.12
        return p
    }

    public func intoFillStyle() -> FillStyle { .liquidMetal(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "tint", name: "Tint", kind: .color),
        Param(id: "light", name: "Light", kind: .color),
        Param(id: "flow", name: "Flow", kind: num(0.0, 1.5, 0.01, .none)),
        Param(id: "scale", name: "Scale", kind: num(16.0, 480.0, 1.0, .pt)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "bevel", name: "Bevel", kind: num(0.0, 48.0, 0.5, .pt)),
        Param(id: "dome", name: "Dome", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "angle", name: "Angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "iridescence", name: "Iridescence", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "contrast", name: "Contrast", kind: num(0.5, 2.0, 0.01, .none)),
        Param(id: "anchor", name: "Anchor", kind: .choice(FillAnchor.choices)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "tint": return tint.toValue()
        case "light": return light.toValue()
        case "flow": return flow.toValue()
        case "scale": return scale.toValue()
        case "speed": return speed.toValue()
        case "bevel": return bevel.toValue()
        case "dome": return dome.toValue()
        case "angle": return angle.toValue()
        case "iridescence": return iridescence.toValue()
        case "contrast": return contrast.toValue()
        case "anchor": return anchor.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "tint": guard let x = Rgb.fromValue(v) else { return false }; tint = x
        case "light": guard let x = Rgb.fromValue(v) else { return false }; light = x
        case "flow": guard let x = Float.fromValue(v) else { return false }; flow = x
        case "scale": guard let x = Float.fromValue(v) else { return false }; scale = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "bevel": guard let x = Float.fromValue(v) else { return false }; bevel = x
        case "dome": guard let x = Float.fromValue(v) else { return false }; dome = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "iridescence": guard let x = Float.fromValue(v) else { return false }; iridescence = x
        case "contrast": guard let x = Float.fromValue(v) else { return false }; contrast = x
        case "anchor": guard let x = FillAnchor.fromValue(v) else { return false }; anchor = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "tint": return tint.rust()
        case "light": return light.rust()
        case "flow": return flow.rust()
        case "scale": return scale.rust()
        case "speed": return speed.rust()
        case "bevel": return bevel.rust()
        case "dome": return dome.rust()
        case "angle": return angle.rust()
        case "iridescence": return iridescence.rust()
        case "contrast": return contrast.rust()
        case "anchor": return anchor.rust()
        default: return nil
        }
    }
}

/// Moulded plastic under one soft light: a diffuse base in `color`, a specular highlight that is
/// small and bright when glossy and broad and faint when matte, the dome's curvature shading, a
/// rim rolled over `bevel` that catches the light, and a faint reflection at grazing angles. The
/// face's flat centre shows `color`. Uses liquid metal's dome and bevel; it never animates.
public struct PlasticParams: Sendable, Equatable, FillStyleConvertible {
    public var color: Rgb
    /// 0 polished, 1 matte: the highlight's size and softness.
    public var roughness: Float
    /// How curved the face is: positive bulges, negative is dished like a keycap's top.
    public var dome: Float
    /// Width of the rolled rim, pt.
    public var bevel: Float
    /// Where the light comes from, radians around the view axis: 0 from above, negative from the left.
    public var angle: Float

    public init(
        color: Rgb = rgb(0xece8de),
        roughness: Float = 0.15,
        dome: Float = 0.35,
        bevel: Float = 6.0,
        angle: Float = -0.5
    ) {
        self.color = color
        self.roughness = roughness
        self.dome = dome
        self.bevel = bevel
        self.angle = angle
    }

    public static func `default`() -> PlasticParams {
        .glossy()
    }

    public static func glossy() -> PlasticParams {
        PlasticParams()
    }

    public static func matte() -> PlasticParams {
        var p = glossy()
        p.color = rgb(0x2e3036)
        p.roughness = 0.8
        return p
    }

    /// A matte face dished like a keycap's top.
    public static func dished() -> PlasticParams {
        var p = glossy()
        p.color = rgb(0xd8d2c4)
        p.roughness = 0.7
        p.dome = -0.45
        return p
    }

    public func intoFillStyle() -> FillStyle { .plastic(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "color", name: "Colour", kind: .color),
        Param(id: "roughness", name: "Roughness", kind: num(0.05, 1.0, 0.01, .fraction)),
        Param(id: "dome", name: "Dome", kind: num(-1.0, 1.0, 0.01, .none)),
        Param(id: "bevel", name: "Bevel", kind: num(0.0, 48.0, 0.5, .pt)),
        Param(id: "angle", name: "Light angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "color": return color.toValue()
        case "roughness": return roughness.toValue()
        case "dome": return dome.toValue()
        case "bevel": return bevel.toValue()
        case "angle": return angle.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "color": guard let x = Rgb.fromValue(v) else { return false }; color = x
        case "roughness": guard let x = Float.fromValue(v) else { return false }; roughness = x
        case "dome": guard let x = Float.fromValue(v) else { return false }; dome = x
        case "bevel": guard let x = Float.fromValue(v) else { return false }; bevel = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "color": return color.rust()
        case "roughness": return roughness.rust()
        case "dome": return dome.rust()
        case "bevel": return bevel.rust()
        case "angle": return angle.rust()
        default: return nil
        }
    }
}

public let defaultMeshPoints: [[Float]] = [
    [0.12, 0.18],
    [0.86, 0.12],
    [0.5, 0.55],
    [0.14, 0.9],
    [0.9, 0.86],
    [0.62, 0.3],
]

/// Colours pinned to points that drift slowly, blended smoothly in OKLab.
public struct MeshGradientParams: Sendable, Equatable, FillStyleConvertible {
    public var colors: Stops
    /// Each colour's rest point, 0..1 across the shape's rect.
    public var points: [[Float]]
    /// How far the points wander from rest, as a fraction of the rect.
    public var drift: Float
    public var speed: Float
    /// 1 = wide soft blends; higher keeps each colour to its own region.
    public var sharpness: Float
    /// Organic bend of the blend field.
    public var warp: Float

    public init(
        colors: Stops = Stops.hex([0x2b1b5a, 0xff6f91, 0xffc46b, 0x6a4cff, 0xff9a5a]),
        points: [[Float]] = defaultMeshPoints,
        drift: Float = 0.12,
        speed: Float = 0.25,
        sharpness: Float = 1.6,
        warp: Float = 0.35
    ) {
        self.colors = colors
        self.points = points
        self.drift = drift
        self.speed = speed
        self.sharpness = sharpness
        self.warp = warp
    }

    public static func `default`() -> MeshGradientParams {
        .dusk()
    }

    public static func dusk() -> MeshGradientParams {
        MeshGradientParams()
    }

    public static func lagoon() -> MeshGradientParams {
        var p = dusk()
        p.colors = Stops.hex([0x0b3d5c, 0x2ec4b6, 0xcbf3f0, 0x1b6ca8])
        return p
    }

    public static func orchid() -> MeshGradientParams {
        var p = dusk()
        p.colors = Stops.hex([0xf9d5e5, 0xc06c84, 0x6c5b7b, 0xf8b195, 0x355c7d, 0xeeac99])
        p.sharpness = 2.0
        return p
    }

    public static func graphite() -> MeshGradientParams {
        var p = dusk()
        p.colors = Stops.hex([0x15171c, 0x3a3f4b, 0x8a93a3, 0x22262e])
        p.drift = 0.08
        p.warp = 0.2
        return p
    }

    public func intoFillStyle() -> FillStyle { .meshGradient(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "colors", name: "Colours", kind: .colors(min: 2, max: maxStops)),
        Param(id: "points", name: "Points", kind: .points(max: maxStops)),
        Param(id: "drift", name: "Drift", kind: num(0.0, 0.4, 0.01, .fraction)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "sharpness", name: "Sharpness", kind: num(0.5, 4.0, 0.01, .none)),
        Param(id: "warp", name: "Warp", kind: num(0.0, 1.0, 0.01, .none)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "colors": return colors.toValue()
        case "points": return pointsToValue(points)
        case "drift": return drift.toValue()
        case "speed": return speed.toValue()
        case "sharpness": return sharpness.toValue()
        case "warp": return warp.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "points": guard let x = pointsFromValue(v) else { return false }; points = x
        case "drift": guard let x = Float.fromValue(v) else { return false }; drift = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "sharpness": guard let x = Float.fromValue(v) else { return false }; sharpness = x
        case "warp": guard let x = Float.fromValue(v) else { return false }; warp = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "colors": return colors.rust()
        case "points": return pointsRust(points)
        case "drift": return drift.rust()
        case "speed": return speed.rust()
        case "sharpness": return sharpness.rust()
        case "warp": return warp.rust()
        default: return nil
        }
    }
}

/// Ordered dithering of a tone into a palette, in square pixels anchored to the shape.
public struct DitherParams: Sendable, Equatable, FillStyleConvertible {
    public var pattern: DitherPattern
    public var input: FillInput
    /// Dark to light. Two colours is one-bit; more is a palette.
    public var colors: Stops
    /// Size of one dither pixel, pt.
    public var pixel: Float
    /// Linear input: ramp direction, radians.
    public var angle: Float
    /// Noise input: feature size, pt.
    public var scale: Float
    /// Noise input: drift speed.
    public var speed: Float
    /// Shifts the tone before quantising (-1..1).
    public var bias: Float
    public var contrast: Float

    public init(
        pattern: DitherPattern = .bayer4,
        input: FillInput = .linear,
        colors: Stops = Stops.hex([0x14161c, 0xe8e4d8]),
        pixel: Float = 2.0,
        angle: Float = 0.6,
        scale: Float = 90.0,
        speed: Float = 0.2,
        bias: Float = 0.0,
        contrast: Float = 1.0
    ) {
        self.pattern = pattern
        self.input = input
        self.colors = colors
        self.pixel = pixel
        self.angle = angle
        self.scale = scale
        self.speed = speed
        self.bias = bias
        self.contrast = contrast
    }

    public static func `default`() -> DitherParams {
        .bayer()
    }

    /// One-bit Bayer 4×4 over a diagonal ramp.
    public static func bayer() -> DitherParams {
        DitherParams()
    }

    /// Four greens, Bayer 8×8, over drifting noise.
    public static func handheld() -> DitherParams {
        var p = bayer()
        p.pattern = .bayer8
        p.input = .noise
        p.colors = Stops.hex([0x0f380f, 0x306230, 0x8bac0f, 0x9bbc0f])
        p.pixel = 3.0
        return p
    }

    /// Blue-noise one-bit over a radial ramp.
    public static func grain() -> DitherParams {
        var p = bayer()
        p.pattern = .blueNoise
        p.input = .radial
        p.colors = Stops.hex([0x1b1530, 0xffd7a8])
        p.pixel = 1.0
        return p
    }

    /// Re-tones whatever is behind the layer in two inks.
    public static func backdrop() -> DitherParams {
        var p = bayer()
        p.pattern = .bayer4
        p.input = .backdrop
        p.colors = Stops.hex([0x101418, 0xf2efe6])
        p.pixel = 2.0
        p.contrast = 1.35
        p.bias = -0.1
        return p
    }

    public func intoFillStyle() -> FillStyle { .dither(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "pattern", name: "Pattern", kind: .choice(DitherPattern.choices)),
        Param(id: "input", name: "Input", kind: .choice(FillInput.choices)),
        Param(id: "colors", name: "Colours", kind: .colors(min: 2, max: maxStops)),
        Param(id: "pixel", name: "Pixel", kind: num(0.5, 16.0, 0.5, .pt)),
        Param(id: "angle", name: "Angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "scale", name: "Noise scale", kind: num(8.0, 400.0, 1.0, .pt)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "bias", name: "Bias", kind: num(-1.0, 1.0, 0.01, .none)),
        Param(id: "contrast", name: "Contrast", kind: num(0.2, 4.0, 0.01, .none)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "pattern": return pattern.toValue()
        case "input": return input.toValue()
        case "colors": return colors.toValue()
        case "pixel": return pixel.toValue()
        case "angle": return angle.toValue()
        case "scale": return scale.toValue()
        case "speed": return speed.toValue()
        case "bias": return bias.toValue()
        case "contrast": return contrast.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "pattern": guard let x = DitherPattern.fromValue(v) else { return false }; pattern = x
        case "input": guard let x = FillInput.fromValue(v) else { return false }; input = x
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "pixel": guard let x = Float.fromValue(v) else { return false }; pixel = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "scale": guard let x = Float.fromValue(v) else { return false }; scale = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "bias": guard let x = Float.fromValue(v) else { return false }; bias = x
        case "contrast": guard let x = Float.fromValue(v) else { return false }; contrast = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "pattern": return pattern.rust()
        case "input": return input.rust()
        case "colors": return colors.rust()
        case "pixel": return pixel.rust()
        case "angle": return angle.rust()
        case "scale": return scale.rust()
        case "speed": return speed.rust()
        case "bias": return bias.rust()
        case "contrast": return contrast.rust()
        default: return nil
        }
    }
}

/// A linear, radial or conic gradient whose colours scatter into film grain. A conic gradient
/// loops: its last colour blends back into the first.
public struct GrainGradientParams: Sendable, Equatable, FillStyleConvertible {
    public var kind: GradientKind
    public var colors: Stops
    /// Linear: direction; conic: start, radians.
    public var angle: Float
    /// Radial and conic centre, 0..1 across the rect.
    public var center: [Float]
    /// How far grain scatters the gradient and its brightness (0..1).
    public var amount: Float
    /// Grain size, pt.
    public var size: Float
    /// One grain value for all channels; off gives colour grain.
    public var mono: Bool
    /// Grain re-rolls per second (0 = static).
    public var fps: Float

    public init(
        kind: GradientKind = .linear,
        colors: Stops = Stops.hex([0x1a0b2e, 0xc2185b, 0xff8a3d, 0xffe1a8]),
        angle: Float = 1.2,
        center: [Float] = [0.5, 0.5],
        amount: Float = 0.4,
        size: Float = 0.5,
        mono: Bool = true,
        fps: Float = 12.0
    ) {
        self.kind = kind
        self.colors = colors
        self.angle = angle
        self.center = [center.count > 0 ? center[0] : 0.5, center.count > 1 ? center[1] : 0.5]
        self.amount = amount
        self.size = size
        self.mono = mono
        self.fps = fps
    }

    public static func `default`() -> GrainGradientParams {
        .ember()
    }

    public static func ember() -> GrainGradientParams {
        GrainGradientParams()
    }

    public static func halo() -> GrainGradientParams {
        var p = ember()
        p.kind = .radial
        p.colors = Stops.hex([0xe9f1ff, 0x7aa2ff, 0x2a2f7a, 0x0b0d1f])
        p.center = [0.5, 0.35]
        return p
    }

    public static func sweep() -> GrainGradientParams {
        var p = ember()
        p.kind = .conic
        p.colors = Stops.hex([0x00c2a8, 0x3a86ff, 0x8338ec, 0xff006e, 0xffbe0b])
        p.angle = -1.57
        p.mono = false
        return p
    }

    public func intoFillStyle() -> FillStyle { .grainGradient(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "kind", name: "Kind", kind: .choice(GradientKind.choices)),
        Param(id: "colors", name: "Colours", kind: .colors(min: 2, max: maxStops)),
        Param(id: "angle", name: "Angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "center", name: "Centre", kind: .point),
        Param(id: "amount", name: "Grain", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "size", name: "Grain size", kind: num(0.5, 8.0, 0.25, .pt)),
        Param(id: "mono", name: "Mono", kind: .toggle),
        Param(id: "fps", name: "Grain rate", kind: num(0.0, 30.0, 1.0, .perSecond)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "kind": return kind.toValue()
        case "colors": return colors.toValue()
        case "angle": return angle.toValue()
        case "center": return pointToValue(center)
        case "amount": return amount.toValue()
        case "size": return size.toValue()
        case "mono": return mono.toValue()
        case "fps": return fps.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "kind": guard let x = GradientKind.fromValue(v) else { return false }; kind = x
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "center": guard let x = pointFromValue(v) else { return false }; center = x
        case "amount": guard let x = Float.fromValue(v) else { return false }; amount = x
        case "size": guard let x = Float.fromValue(v) else { return false }; size = x
        case "mono": guard let x = Bool.fromValue(v) else { return false }; mono = x
        case "fps": guard let x = Float.fromValue(v) else { return false }; fps = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "kind": return kind.rust()
        case "colors": return colors.rust()
        case "angle": return angle.rust()
        case "center": return pointRust(center)
        case "amount": return amount.rust()
        case "size": return size.rust()
        case "mono": return mono.rust()
        case "fps": return fps.rust()
        default: return nil
        }
    }
}

/// Reeded glass over the backdrop: parallel convex ribs, each showing a squeezed, flipped strip of
/// what is behind.
public struct FlutedGlassParams: Sendable, Equatable, FillStyleConvertible {
    /// Rib width, pt.
    public var rib: Float
    /// Rib direction, radians (0 = vertical ribs).
    public var angle: Float
    /// How far each rib bends the image sideways, pt.
    public var refraction: Float
    /// 0..1: clear to frosted (reads the blurred backdrop like a frosted lens).
    public var frost: Float
    /// Colour split toward the rib edges.
    public var dispersion: Float
    /// Sheen along each rib's lit side.
    public var highlight: Float
    public var tint: Rgb
    public var tintAmount: Float

    public init(
        rib: Float = 14.0,
        angle: Float = 0.0,
        refraction: Float = 9.0,
        frost: Float = 0.0,
        dispersion: Float = 0.15,
        highlight: Float = 0.5,
        tint: Rgb = rgb(0xffffff),
        tintAmount: Float = 0.0
    ) {
        self.rib = rib
        self.angle = angle
        self.refraction = refraction
        self.frost = frost
        self.dispersion = dispersion
        self.highlight = highlight
        self.tint = tint
        self.tintAmount = tintAmount
    }

    public static func `default`() -> FlutedGlassParams {
        .reeded()
    }

    public static func reeded() -> FlutedGlassParams {
        FlutedGlassParams()
    }

    public static func fine() -> FlutedGlassParams {
        var p = reeded()
        p.rib = 6.0
        p.refraction = 5.0
        return p
    }

    public static func frosted() -> FlutedGlassParams {
        var p = reeded()
        p.frost = 0.6
        return p
    }

    public static func wide() -> FlutedGlassParams {
        var p = reeded()
        p.rib = 32.0
        p.refraction = 18.0
        p.dispersion = 0.25
        return p
    }

    public func intoFillStyle() -> FillStyle { .flutedGlass(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "rib", name: "Rib width", kind: num(2.0, 64.0, 0.5, .pt)),
        Param(id: "angle", name: "Angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "refraction", name: "Refraction", kind: num(0.0, 40.0, 0.5, .pt)),
        Param(id: "frost", name: "Frost", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "dispersion", name: "Dispersion", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "highlight", name: "Highlight", kind: num(0.0, 1.0, 0.01, .fraction)),
        Param(id: "tint", name: "Tint", kind: .color),
        Param(id: "tint_amount", name: "Tint amount", kind: num(0.0, 1.0, 0.01, .fraction)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "rib": return rib.toValue()
        case "angle": return angle.toValue()
        case "refraction": return refraction.toValue()
        case "frost": return frost.toValue()
        case "dispersion": return dispersion.toValue()
        case "highlight": return highlight.toValue()
        case "tint": return tint.toValue()
        case "tint_amount": return tintAmount.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "rib": guard let x = Float.fromValue(v) else { return false }; rib = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "refraction": guard let x = Float.fromValue(v) else { return false }; refraction = x
        case "frost": guard let x = Float.fromValue(v) else { return false }; frost = x
        case "dispersion": guard let x = Float.fromValue(v) else { return false }; dispersion = x
        case "highlight": guard let x = Float.fromValue(v) else { return false }; highlight = x
        case "tint": guard let x = Rgb.fromValue(v) else { return false }; tint = x
        case "tint_amount": guard let x = Float.fromValue(v) else { return false }; tintAmount = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "rib": return rib.rust()
        case "angle": return angle.rust()
        case "refraction": return refraction.rust()
        case "frost": return frost.rust()
        case "dispersion": return dispersion.rust()
        case "highlight": return highlight.rust()
        case "tint": return tint.rust()
        case "tint_amount": return tintAmount.rust()
        default: return nil
        }
    }
}

/// Glossy blobs that drift and merge, over a base colour.
public struct MetaballParams: Sendable, Equatable, FillStyleConvertible {
    /// Blob colours (each blob takes one in turn).
    public var colors: Stops
    public var base: Rgb
    public var count: UInt32
    /// Blob radius as a fraction of the rect's shorter side.
    public var size: Float
    public var speed: Float
    /// Sheen on the blobs.
    public var gloss: Float

    public init(
        colors: Stops = Stops.hex([0xff5e3a, 0xff9a3c, 0xff2d6f]),
        base: Rgb = rgb(0x1a0f1f),
        count: UInt32 = 6,
        size: Float = 0.2,
        speed: Float = 0.4,
        gloss: Float = 0.5
    ) {
        self.colors = colors
        self.base = base
        self.count = count
        self.size = size
        self.speed = speed
        self.gloss = gloss
    }

    public static func `default`() -> MetaballParams {
        .lava()
    }

    public static func lava() -> MetaballParams {
        MetaballParams()
    }

    public static func mint() -> MetaballParams {
        var p = lava()
        p.colors = Stops.hex([0x7cf2c4, 0x37d0e8, 0xb8f36b])
        p.base = rgb(0x0d1b1e)
        return p
    }

    public func intoFillStyle() -> FillStyle { .metaballs(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "colors", name: "Colours", kind: .colors(min: 1, max: maxStops)),
        Param(id: "base", name: "Base", kind: .color),
        Param(id: "count", name: "Count", kind: .count(min: 1, max: 8)),
        Param(id: "size", name: "Size", kind: num(0.05, 0.5, 0.01, .fraction)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "gloss", name: "Gloss", kind: num(0.0, 1.0, 0.01, .fraction)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "colors": return colors.toValue()
        case "base": return base.toValue()
        case "count": return count.toValue()
        case "size": return size.toValue()
        case "speed": return speed.toValue()
        case "gloss": return gloss.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "base": guard let x = Rgb.fromValue(v) else { return false }; base = x
        case "count": guard let x = UInt32.fromValue(v) else { return false }; count = x
        case "size": guard let x = Float.fromValue(v) else { return false }; size = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "gloss": guard let x = Float.fromValue(v) else { return false }; gloss = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "colors": return colors.rust()
        case "base": return base.rust()
        case "count": return count.rust()
        case "size": return size.rust()
        case "speed": return speed.rust()
        case "gloss": return gloss.rust()
        default: return nil
        }
    }
}

/// Colours stirred into a slow swirl (warped noise through a ramp).
public struct SwirlParams: Sendable, Equatable, FillStyleConvertible {
    public var colors: Stops
    /// Feature size, pt.
    public var scale: Float
    public var speed: Float
    /// Twist around the centre, turns at the middle.
    public var twist: Float
    /// How much the noise folds into itself.
    public var warp: Float

    public init(
        colors: Stops = Stops.hex([0x0b1026, 0x3b2c85, 0x2fb3c9, 0xf2f6ff]),
        scale: Float = 140.0,
        speed: Float = 0.2,
        twist: Float = 0.6,
        warp: Float = 1.0
    ) {
        self.colors = colors
        self.scale = scale
        self.speed = speed
        self.twist = twist
        self.warp = warp
    }

    public static func `default`() -> SwirlParams {
        .ink()
    }

    public static func ink() -> SwirlParams {
        SwirlParams()
    }

    public static func marble() -> SwirlParams {
        var p = ink()
        p.colors = Stops.hex([0xf4f1ea, 0xc9c2b4, 0x6f6a61, 0xf4f1ea])
        p.scale = 90.0
        p.twist = 0.3
        p.warp = 1.6
        return p
    }

    public func intoFillStyle() -> FillStyle { .swirl(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "colors", name: "Colours", kind: .colors(min: 2, max: maxStops)),
        Param(id: "scale", name: "Scale", kind: num(16.0, 480.0, 1.0, .pt)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "twist", name: "Twist", kind: num(-2.0, 2.0, 0.01, .none)),
        Param(id: "warp", name: "Warp", kind: num(0.0, 2.5, 0.01, .none)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "colors": return colors.toValue()
        case "scale": return scale.toValue()
        case "speed": return speed.toValue()
        case "twist": return twist.toValue()
        case "warp": return warp.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "scale": guard let x = Float.fromValue(v) else { return false }; scale = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "twist": guard let x = Float.fromValue(v) else { return false }; twist = x
        case "warp": guard let x = Float.fromValue(v) else { return false }; warp = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "colors": return colors.rust()
        case "scale": return scale.rust()
        case "speed": return speed.rust()
        case "twist": return twist.rust()
        case "warp": return warp.rust()
        default: return nil
        }
    }
}

/// Cells around drifting seed points, with optional seams.
public struct VoronoiParams: Sendable, Equatable, FillStyleConvertible {
    public var colors: Stops
    /// Seam colour.
    public var edgeColor: Rgb
    /// Cell size, pt.
    public var scale: Float
    public var speed: Float
    /// Seam width, pt (0 = none).
    public var edge: Float
    /// Shading toward each cell's rim (0 = flat cells).
    public var depth: Float

    public init(
        colors: Stops = Stops.hex([0x1f2a44, 0x2c3e66, 0x3d5a8a, 0x5577b0]),
        edgeColor: Rgb = rgb(0x0b0f1a),
        scale: Float = 36.0,
        speed: Float = 0.25,
        edge: Float = 1.5,
        depth: Float = 0.4
    ) {
        self.colors = colors
        self.edgeColor = edgeColor
        self.scale = scale
        self.speed = speed
        self.edge = edge
        self.depth = depth
    }

    public static func `default`() -> VoronoiParams {
        .cells()
    }

    public static func cells() -> VoronoiParams {
        VoronoiParams()
    }

    public static func stained() -> VoronoiParams {
        var p = cells()
        p.colors = Stops.hex([0xd7263d, 0xf46036, 0x2e294e, 0x1b998b, 0xc5d86d])
        p.edgeColor = rgb(0x111111)
        p.scale = 20.0
        p.edge = 2.0
        p.depth = 0.25
        return p
    }

    public func intoFillStyle() -> FillStyle { .voronoi(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "colors", name: "Colours", kind: .colors(min: 1, max: maxStops)),
        Param(id: "edge_color", name: "Seam colour", kind: .color),
        Param(id: "scale", name: "Cell size", kind: num(6.0, 200.0, 1.0, .pt)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "edge", name: "Seam", kind: num(0.0, 8.0, 0.25, .pt)),
        Param(id: "depth", name: "Depth", kind: num(0.0, 1.0, 0.01, .fraction)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "colors": return colors.toValue()
        case "edge_color": return edgeColor.toValue()
        case "scale": return scale.toValue()
        case "speed": return speed.toValue()
        case "edge": return edge.toValue()
        case "depth": return depth.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "edge_color": guard let x = Rgb.fromValue(v) else { return false }; edgeColor = x
        case "scale": guard let x = Float.fromValue(v) else { return false }; scale = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "edge": guard let x = Float.fromValue(v) else { return false }; edge = x
        case "depth": guard let x = Float.fromValue(v) else { return false }; depth = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "colors": return colors.rust()
        case "edge_color": return edgeColor.rust()
        case "scale": return scale.rust()
        case "speed": return speed.rust()
        case "edge": return edge.rust()
        case "depth": return depth.rust()
        default: return nil
        }
    }
}

/// Layered bands of colour with rolling, swaying edges.
public struct WaveParams: Sendable, Equatable, FillStyleConvertible {
    /// One band per colour, back to front.
    public var colors: Stops
    /// Edge height, as a fraction of the rect.
    public var amplitude: Float
    /// Crests across the rect.
    public var frequency: Float
    public var speed: Float
    /// Direction the bands stack along, radians (0 = top to bottom).
    public var angle: Float
    /// Edge softness, as a fraction of the rect.
    public var softness: Float

    public init(
        colors: Stops = Stops.hex([0xbfe7ff, 0x5fb3e8, 0x2a7bbf, 0x154a85, 0x0a2649]),
        amplitude: Float = 0.05,
        frequency: Float = 1.6,
        speed: Float = 0.4,
        angle: Float = 0.0,
        softness: Float = 0.006
    ) {
        self.colors = colors
        self.amplitude = amplitude
        self.frequency = frequency
        self.speed = speed
        self.angle = angle
        self.softness = softness
    }

    public static func `default`() -> WaveParams {
        .sea()
    }

    public static func sea() -> WaveParams {
        WaveParams()
    }

    public static func dunes() -> WaveParams {
        var p = sea()
        p.colors = Stops.hex([0xfde6c4, 0xf4b77c, 0xe08a4f, 0xb35a3a, 0x6e3226])
        p.amplitude = 0.07
        p.frequency = 1.1
        p.speed = 0.15
        return p
    }

    public func intoFillStyle() -> FillStyle { .waves(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "colors", name: "Colours", kind: .colors(min: 2, max: maxStops)),
        Param(id: "amplitude", name: "Amplitude", kind: num(0.0, 0.25, 0.005, .fraction)),
        Param(id: "frequency", name: "Frequency", kind: num(0.2, 6.0, 0.05, .none)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "angle", name: "Angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "softness", name: "Softness", kind: num(0.0, 0.1, 0.001, .fraction)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "colors": return colors.toValue()
        case "amplitude": return amplitude.toValue()
        case "frequency": return frequency.toValue()
        case "speed": return speed.toValue()
        case "angle": return angle.toValue()
        case "softness": return softness.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "colors": guard let x = Stops.fromValue(v) else { return false }; colors = x
        case "amplitude": guard let x = Float.fromValue(v) else { return false }; amplitude = x
        case "frequency": guard let x = Float.fromValue(v) else { return false }; frequency = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "softness": guard let x = Float.fromValue(v) else { return false }; softness = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "colors": return colors.rust()
        case "amplitude": return amplitude.rust()
        case "frequency": return frequency.rust()
        case "speed": return speed.rust()
        case "angle": return angle.rust()
        case "softness": return softness.rust()
        default: return nil
        }
    }
}

/// Print-style dots on a rotated grid, sized by a tone.
public struct HalftoneParams: Sendable, Equatable, FillStyleConvertible {
    public var input: FillInput
    public var ink: Rgb
    /// The colour between the dots.
    public var base: Rgb
    /// Dot pitch, pt.
    public var cell: Float
    /// Screen angle, radians.
    public var angle: Float
    /// Linear input: ramp direction, radians.
    public var rampAngle: Float
    /// Noise input: feature size, pt.
    public var scale: Float
    public var speed: Float
    public var bias: Float
    public var contrast: Float

    public init(
        input: FillInput = .radial,
        ink: Rgb = rgb(0x1b1b1f),
        base: Rgb = rgb(0xf1ece1),
        cell: Float = 6.0,
        angle: Float = 0.785,
        rampAngle: Float = 0.6,
        scale: Float = 90.0,
        speed: Float = 0.2,
        bias: Float = 0.0,
        contrast: Float = 1.0
    ) {
        self.input = input
        self.ink = ink
        self.base = base
        self.cell = cell
        self.angle = angle
        self.rampAngle = rampAngle
        self.scale = scale
        self.speed = speed
        self.bias = bias
        self.contrast = contrast
    }

    public static func `default`() -> HalftoneParams {
        .print()
    }

    public static func print() -> HalftoneParams {
        HalftoneParams()
    }

    /// Re-screens whatever is behind the layer.
    public static func backdrop() -> HalftoneParams {
        var p = print()
        p.input = .backdrop
        p.cell = 4.0
        return p
    }

    public func intoFillStyle() -> FillStyle { .halftone(self) }
    public func border(_ width: Float) -> FillParams { intoFillParams().border(width) }
    public func intensity(_ k: Float) -> FillParams { intoFillParams().intensity(k) }

    public static let params: [Param] = [
        Param(id: "input", name: "Input", kind: .choice(FillInput.choices)),
        Param(id: "ink", name: "Ink", kind: .color),
        Param(id: "base", name: "Base", kind: .color),
        Param(id: "cell", name: "Dot pitch", kind: num(2.0, 32.0, 0.5, .pt)),
        Param(id: "angle", name: "Screen angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "ramp_angle", name: "Ramp angle", kind: num(-3.14159, 3.14159, 0.01, .radians)),
        Param(id: "scale", name: "Noise scale", kind: num(8.0, 400.0, 1.0, .pt)),
        Param(id: "speed", name: "Speed", kind: num(0.0, 2.0, 0.01, .perSecond)),
        Param(id: "bias", name: "Bias", kind: num(-1.0, 1.0, 0.01, .none)),
        Param(id: "contrast", name: "Contrast", kind: num(0.2, 4.0, 0.01, .none)),
    ]

    func getParam(_ id: String) -> Value? {
        switch id {
        case "input": return input.toValue()
        case "ink": return ink.toValue()
        case "base": return base.toValue()
        case "cell": return cell.toValue()
        case "angle": return angle.toValue()
        case "ramp_angle": return rampAngle.toValue()
        case "scale": return scale.toValue()
        case "speed": return speed.toValue()
        case "bias": return bias.toValue()
        case "contrast": return contrast.toValue()
        default: return nil
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch id {
        case "input": guard let x = FillInput.fromValue(v) else { return false }; input = x
        case "ink": guard let x = Rgb.fromValue(v) else { return false }; ink = x
        case "base": guard let x = Rgb.fromValue(v) else { return false }; base = x
        case "cell": guard let x = Float.fromValue(v) else { return false }; cell = x
        case "angle": guard let x = Float.fromValue(v) else { return false }; angle = x
        case "ramp_angle": guard let x = Float.fromValue(v) else { return false }; rampAngle = x
        case "scale": guard let x = Float.fromValue(v) else { return false }; scale = x
        case "speed": guard let x = Float.fromValue(v) else { return false }; speed = x
        case "bias": guard let x = Float.fromValue(v) else { return false }; bias = x
        case "contrast": guard let x = Float.fromValue(v) else { return false }; contrast = x
        default: return false
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch id {
        case "input": return input.rust()
        case "ink": return ink.rust()
        case "base": return base.rust()
        case "cell": return cell.rust()
        case "angle": return angle.rust()
        case "ramp_angle": return rampAngle.rust()
        case "scale": return scale.rust()
        case "speed": return speed.rust()
        case "bias": return bias.rust()
        case "contrast": return contrast.rust()
        default: return nil
        }
    }
}

// MARK: - FillStyle / FillParams

/// Which fill, with its params. The order is the catalog's (`fillStyles()`).
public enum FillStyle: Sendable, Equatable, FillParamsConvertible {
    case liquidMetal(LiquidMetalParams)
    case meshGradient(MeshGradientParams)
    case dither(DitherParams)
    case grainGradient(GrainGradientParams)
    case flutedGlass(FlutedGlassParams)
    case metaballs(MetaballParams)
    case swirl(SwirlParams)
    case voronoi(VoronoiParams)
    case waves(WaveParams)
    case halftone(HalftoneParams)
    case plastic(PlasticParams)

    public static func from(_ p: some FillStyleConvertible) -> FillStyle {
        p.intoFillStyle()
    }

    public func intoFillParams() -> FillParams {
        FillParams.new(self)
    }

    /// Position in `fillStyles()`; also the shader variant.
    func index() -> Int {
        switch self {
        case .liquidMetal: return 0
        case .meshGradient: return 1
        case .dither: return 2
        case .grainGradient: return 3
        case .flutedGlass: return 4
        case .metaballs: return 5
        case .swirl: return 6
        case .voronoi: return 7
        case .waves: return 8
        case .halftone: return 9
        case .plastic: return 10
        }
    }

    func getParam(_ id: String) -> Value? {
        switch self {
        case .liquidMetal(let p): return p.getParam(id)
        case .meshGradient(let p): return p.getParam(id)
        case .dither(let p): return p.getParam(id)
        case .grainGradient(let p): return p.getParam(id)
        case .flutedGlass(let p): return p.getParam(id)
        case .metaballs(let p): return p.getParam(id)
        case .swirl(let p): return p.getParam(id)
        case .voronoi(let p): return p.getParam(id)
        case .waves(let p): return p.getParam(id)
        case .halftone(let p): return p.getParam(id)
        case .plastic(let p): return p.getParam(id)
        }
    }

    mutating func setParam(_ id: String, _ v: Value) -> Bool {
        switch self {
        case .liquidMetal(var p):
            guard p.setParam(id, v) else { return false }
            self = .liquidMetal(p)
        case .meshGradient(var p):
            guard p.setParam(id, v) else { return false }
            self = .meshGradient(p)
        case .dither(var p):
            guard p.setParam(id, v) else { return false }
            self = .dither(p)
        case .grainGradient(var p):
            guard p.setParam(id, v) else { return false }
            self = .grainGradient(p)
        case .flutedGlass(var p):
            guard p.setParam(id, v) else { return false }
            self = .flutedGlass(p)
        case .metaballs(var p):
            guard p.setParam(id, v) else { return false }
            self = .metaballs(p)
        case .swirl(var p):
            guard p.setParam(id, v) else { return false }
            self = .swirl(p)
        case .voronoi(var p):
            guard p.setParam(id, v) else { return false }
            self = .voronoi(p)
        case .waves(var p):
            guard p.setParam(id, v) else { return false }
            self = .waves(p)
        case .halftone(var p):
            guard p.setParam(id, v) else { return false }
            self = .halftone(p)
        case .plastic(var p):
            guard p.setParam(id, v) else { return false }
            self = .plastic(p)
        }
        return true
    }

    func rustField(_ id: String) -> String? {
        switch self {
        case .liquidMetal(let p): return p.rustField(id)
        case .meshGradient(let p): return p.rustField(id)
        case .dither(let p): return p.rustField(id)
        case .grainGradient(let p): return p.rustField(id)
        case .flutedGlass(let p): return p.rustField(id)
        case .metaballs(let p): return p.rustField(id)
        case .swirl(let p): return p.rustField(id)
        case .voronoi(let p): return p.rustField(id)
        case .waves(let p): return p.rustField(id)
        case .halftone(let p): return p.rustField(id)
        case .plastic(let p): return p.rustField(id)
        }
    }
}

/// A fill: the style plus what every style shares. Build it with `FillParams.new`, `from`, or a preset.
public struct FillParams: Sendable, Equatable, FillParamsConvertible {
    public var style: FillStyle
    /// 0 fills the shape; above 0 paints only a band this wide (pt) inside the edge, as a stroke.
    public var border: Float
    /// Opacity of the fill, 0..1.
    public var intensity: Float

    public init(style: FillStyle, border: Float = 0.0, intensity: Float = 1.0) {
        self.style = style
        self.border = border
        self.intensity = intensity
    }

    public static func new(_ style: FillStyle) -> FillParams {
        FillParams(style: style, border: 0.0, intensity: 1.0)
    }

    public static func from(_ p: some FillParamsConvertible) -> FillParams {
        p.intoFillParams()
    }

    public func intoFillParams() -> FillParams {
        self
    }

    public func border(_ width: Float) -> FillParams {
        var copy = self
        copy.border = width
        return copy
    }

    public func intensity(_ k: Float) -> FillParams {
        var copy = self
        copy.intensity = k
        return copy
    }

    /// Whether this fill samples the backdrop (glass, or a dither or halftone of it).
    public func needsBackdrop() -> Bool {
        switch style {
        case .flutedGlass:
            return true
        case .dither(let p):
            return p.input == .backdrop
        case .halftone(let p):
            return p.input == .backdrop
        default:
            return false
        }
    }

    func needsSource() -> Bool {
        switch style {
        case .dither(let p):
            return p.input == .image
        case .halftone(let p):
            return p.input == .image
        default:
            return false
        }
    }

    /// Whether the fill moves on its own (so the frame loop keeps ticking).
    func animates() -> Bool {
        switch style {
        case .liquidMetal(let p):
            return p.speed > 0.0 && p.flow > 0.0
        case .meshGradient(let p):
            return p.speed > 0.0 && (p.drift > 0.0 || p.warp > 0.0)
        case .dither(let p):
            return p.input.animates() && p.speed > 0.0
        case .grainGradient(let p):
            return p.fps > 0.0 && p.amount > 0.0
        case .flutedGlass:
            return false
        case .metaballs(let p):
            return p.speed > 0.0
        case .swirl(let p):
            return p.speed > 0.0
        case .voronoi(let p):
            return p.speed > 0.0
        case .waves(let p):
            return p.speed > 0.0 && p.amplitude > 0.0
        case .halftone(let p):
            return p.input.animates() && p.speed > 0.0
        case .plastic:
            return false
        }
    }

    func cost() -> FxCost {
        let ramp: UInt32 = 2
        func inputCost(_ i: FillInput) -> (UInt32, UInt32) {
            switch i {
            case .noise: return (0, 3)
            case .backdrop, .image: return (1, 0)
            default: return (0, 0)
            }
        }
        let samples: UInt32
        let alu: UInt32
        switch style {
        case .liquidMetal(let p):
            samples = 0
            alu = p.flow > 0.0 ? 8 : 0
        case .meshGradient(let p):
            samples = UInt32(p.colors.len() * 2)
            alu = p.warp > 0.0 ? 2 : 0
        case .dither(let p):
            let (s, a) = inputCost(p.input)
            samples = s + 1 + (p.pattern == .blueNoise ? 1 : 0)
            alu = a
        case .grainGradient:
            samples = ramp
            alu = 0
        case .flutedGlass(let p):
            samples = p.frost > 0.0 ? 6 : 3
            alu = 0
        case .metaballs(let p):
            samples = min(max(p.count, 1), 8) * 2
            alu = 0
        case .swirl:
            samples = ramp
            alu = 9
        case .voronoi:
            samples = 1
            alu = 0
        case .waves(let p):
            samples = UInt32(p.colors.len())
            alu = 0
        case .halftone(let p):
            let (s, a) = inputCost(p.input)
            samples = s * 4
            alu = a * 4
        case .plastic:
            samples = 0
            alu = 0
        }
        return FxCost(passes: 1, samples: samples, alu: alu, backdrop: needsBackdrop(), source: needsSource())
    }

    /// Whether the fill draws nothing on a shape of this rect, at any time.
    func drawsNothing(_ r: Rect) -> Bool {
        !(intensity > 0.0) || !(border.isFinite && border >= 0.0) || !(r.w > 0.0) || !(r.h > 0.0)
    }

    /// Pack into `i` (kind is `kindFill`); `nil` when the fill draws nothing.
    func pack(_ i: inout InstRaw, _ rm: Bool, _ time: Float) -> Rect? {
        let r = rectOf(i)
        if drawsNothing(r) {
            return nil
        }
        @inline(__always)
        func fin(_ x: Float, _ d: Float) -> Float {
            x.isFinite ? x : d
        }
        // Looping styles settle on one pose under reduced motion, and fold large times to keep f32 precision.
        i.t.x = rm ? calmT : cpu.foldT(time)
        i.t.z = Float(style.index())
        i.aux = SIMD4<Float>(border, min(intensity, 1.0), 0.0, 0.0)
        switch style {
        case .liquidMetal(let p):
            i.c0 = p.tint.v4()
            i.c1 = p.light.v4()
            i.p0 = SIMD4<Float>(
                max(fin(p.flow, 0.0), 0.0),
                max(fin(p.scale, 100.0), 1.0),
                fin(p.speed, 0.0),
                max(fin(p.bevel, 0.0), 0.0)
            )
            i.p1 = SIMD4<Float>(
                fin(p.dome, 0.0),
                fin(p.angle, 0.0),
                max(fin(p.iridescence, 0.0), 0.0),
                max(fin(p.contrast, 1.0), 0.1)
            )
            i.p2 = SIMD4<Float>(p.anchor == .element ? 1.0 : 0.0, 0.0, 0.0, 0.0)
        case .meshGradient(let p):
            i.p0 = SIMD4<Float>(p.drift, p.speed, min(max(p.sharpness, 0.1), 8.0), p.warp)
        case .dither(let p):
            let pat: Float
            switch p.pattern {
            case .bayer2: pat = 1.0
            case .bayer4: pat = 2.0
            case .bayer8: pat = 3.0
            case .blueNoise: pat = 4.0
            case .white: pat = 5.0
            }
            i.p0 = SIMD4<Float>(pat, p.input.code(), max(p.pixel, 0.25), p.angle)
            i.p1 = SIMD4<Float>(max(p.scale, 1.0), p.speed, p.bias, p.contrast)
        case .grainGradient(let p):
            let kind: Float
            switch p.kind {
            case .linear: kind = 0.0
            case .radial: kind = 1.0
            case .conic: kind = 2.0
            }
            i.p0 = SIMD4<Float>(kind, p.angle, p.center[0], p.center[1])
            i.p1 = SIMD4<Float>(p.amount, max(p.size, 0.25), p.mono ? 1.0 : 0.0, rm ? 0.0 : p.fps)
        case .flutedGlass(let p):
            i.c0 = p.tint.v4()
            i.p0 = SIMD4<Float>(max(p.rib, 1.0), p.angle, p.refraction, p.frost)
            i.p1 = SIMD4<Float>(p.dispersion, p.highlight, p.tintAmount, 0.0)
        case .metaballs(let p):
            i.c0 = p.base.v4()
            i.p0 = SIMD4<Float>(Float(min(max(p.count, 1), 8)), p.size, p.speed, p.gloss)
        case .swirl(let p):
            i.p0 = SIMD4<Float>(max(p.scale, 1.0), p.speed, p.twist, p.warp)
        case .voronoi(let p):
            i.c0 = p.edgeColor.v4()
            i.p0 = SIMD4<Float>(max(p.scale, 2.0), p.speed, p.edge, p.depth)
        case .waves(let p):
            i.p0 = SIMD4<Float>(p.amplitude, p.frequency, p.speed, p.angle)
            i.p1 = SIMD4<Float>(p.softness, 0.0, 0.0, 0.0)
        case .halftone(let p):
            i.c0 = p.ink.v4()
            i.c1 = p.base.v4()
            i.p0 = SIMD4<Float>(0.0, p.input.code(), max(p.cell, 1.0), p.rampAngle)
            i.p1 = SIMD4<Float>(max(p.scale, 1.0), p.speed, p.bias, p.contrast)
            i.p2 = SIMD4<Float>(p.angle, 0.0, 0.0, 0.0)
        case .plastic(let p):
            i.c0 = p.color.v4()
            i.p0 = SIMD4<Float>(
                min(max(fin(p.roughness, 0.15), 0.0), 1.0),
                fin(p.dome, 0.0),
                max(fin(p.bevel, 0.0), 0.0),
                fin(p.angle, 0.0)
            )
        }
        return r.inflate(1.0)
    }

    /// Per-frame tables: colour stops (linear, then OKLab; mesh points ride in `w`), metaball
    /// paths and the blue-noise tile. `xf` = (stops offset, stop count, extra offset, extra count).
    func tables(_ i: inout InstRaw, _ rect: Rect, _ t: Float, _ seed: UInt32, _ data: inout [SIMD4<Float>]) {
        func pushStops(_ data: inout [SIMD4<Float>], _ s: Stops, _ pts: [[Float]]?) -> (Float, Float) {
            let first = Float(data.count)
            for (k, c) in s.asSlice().enumerated() {
                let p = pts.map { $0[k] } ?? [0.0, 0.0]
                let l = oklab(c)
                data.append(SIMD4<Float>(c.r, c.g, c.b, p[0]))
                data.append(SIMD4<Float>(l[0], l[1], l[2], p[1]))
            }
            return (first, Float(s.len()))
        }

        let fn: (Float, Float)
        switch style {
        case .meshGradient(let p):
            let pts = cpu.meshPoints(p, t, seed)
            fn = pushStops(&data, p.colors, pts)
        case .dither(let p):
            fn = pushStops(&data, p.colors, nil)
        case .grainGradient(let p):
            fn = pushStops(&data, p.colors, nil)
        case .metaballs(let p):
            fn = pushStops(&data, p.colors, nil)
        case .swirl(let p):
            fn = pushStops(&data, p.colors, nil)
        case .voronoi(let p):
            fn = pushStops(&data, p.colors, nil)
        case .waves(let p):
            fn = pushStops(&data, p.colors, nil)
        default:
            // Glass leaves `xf` to `blurBackdrop`, which marks the frost pyramid there.
            return
        }
        i.xf = SIMD4<Float>(fn.0, fn.1, 0.0, 0.0)
        switch style {
        case .dither(let p) where p.pattern == .blueNoise:
            i.xf.z = Float(data.count)
            i.xf.w = Float(blueN)
            data.append(contentsOf: cpu.blueNoise())
        case .metaballs(let p):
            i.xf.z = Float(data.count)
            i.xf.w = Float(min(max(p.count, 1), 8))
            cpu.metaballs(p, rect, t, seed, &data)
        default:
            break
        }
    }
}

private func rectOf(_ i: InstRaw) -> Rect {
    Rect.new(i.rect.x, i.rect.y, i.rect.z, i.rect.w)
}
