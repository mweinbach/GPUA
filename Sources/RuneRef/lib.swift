// Ported from: crates/rune-ref/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Scalar oracle for Rune's device-pixel instance stream, not a vector rasterizer.
//! Basic operations use strict f32 semantics; canonical output is sRGB RGBA8, quantized
//! after each source-over operation, including clear.

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

public let NO_CLIP: [Float] = [-1e6, -1e6, 1e6, 1e6]

/// Validation error returned by `Scene.validate()`.
public struct SceneError: Error, Sendable, Equatable, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// Same payload as `Rune.Instance`; independent so the CPU lane has no
/// window, GPU, system-font or platform dependency. Source metadata is a sidecar.
public struct Primitive: Sendable, Equatable, Codable {
    public var node: UInt32
    public var source: String
    public var rect: [Float]
    public var radii: [Float]
    public var fill: [Float]
    /// Border paint; for a layer (kind 8), signed per-corner clip radii `[tl, tr, br, bl]`.
    public var border: [Float]
    public var params: [Float]
    public var uv: [Float]
    public var clip: [Float]
    public var fade: [Float]
    public var fadeOrigin: [Float]?
    /// For a layer (kind 8), `[turn, pivot_x, pivot_y]`: the composite turns `turn` radians
    /// clockwise about the pivot (device pixels).
    public var turn: [Float]?

    enum CodingKeys: String, CodingKey {
        case node
        case source
        case rect
        case radii
        case fill
        case border
        case params
        case uv
        case clip
        case fade
        case fadeOrigin = "fade_origin"
        case turn
    }

    public init(
        node: UInt32,
        source: String,
        rect: [Float],
        radii: [Float],
        fill: [Float],
        border: [Float],
        params: [Float],
        uv: [Float],
        clip: [Float],
        fade: [Float],
        fadeOrigin: [Float]? = nil,
        turn: [Float]? = nil
    ) {
        self.node = node
        self.source = source
        self.rect = rect
        self.radii = radii
        self.fill = fill
        self.border = border
        self.params = params
        self.uv = uv
        self.clip = clip
        self.fade = fade
        self.fadeOrigin = fadeOrigin
        self.turn = turn
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(node, forKey: .node)
        try c.encode(source, forKey: .source)
        try c.encode(rect, forKey: .rect)
        try c.encode(radii, forKey: .radii)
        try c.encode(fill, forKey: .fill)
        try c.encode(border, forKey: .border)
        try c.encode(params, forKey: .params)
        try c.encode(uv, forKey: .uv)
        try c.encode(clip, forKey: .clip)
        try c.encode(fade, forKey: .fade)
        try c.encodeIfPresent(fadeOrigin, forKey: .fadeOrigin)
        try c.encodeIfPresent(turn, forKey: .turn)
    }
}

public struct Atlas: Sendable, Equatable, Codable {
    public var width: UInt32
    public var height: UInt32
    public var data: [UInt8]

    public init(width: UInt32, height: UInt32, data: [UInt8]) {
        self.width = width
        self.height = height
        self.data = data
    }

    @usableFromInline
    func load(_ x: Int32, _ y: Int32) -> Float {
        if x < 0 || y < 0 || x >= Int32(width) || y >= Int32(height) {
            return 0.0
        }
        return Float(data[Int(UInt32(y) * width + UInt32(x))]) / 255.0
    }
}

/// The deepest nesting of layer scopes `validate` accepts.
private let MAX_LAYER_DEPTH: Int = 16

public struct Scene: Sendable, Equatable, Codable {
    public var width: UInt32
    public var height: UInt32
    public var clear: [Float]
    public var primitives: [Primitive]
    public var atlas: Atlas

    public init(
        width: UInt32,
        height: UInt32,
        clear: [Float],
        primitives: [Primitive],
        atlas: Atlas
    ) {
        self.width = width
        self.height = height
        self.clear = clear
        self.primitives = primitives
        self.atlas = atlas
    }

    /// Reject malformed replay files before CPU allocation or GPU upload.
    public func validate() -> Result<Void, SceneError> {
        if width == 0 || height == 0 || width > 4096 || height > 4096 {
            return .failure(SceneError("viewport must be 1..=4096"))
        }
        if primitives.count > 65536
            || atlas.width == 0
            || atlas.height == 0
            || atlas.width > 2048
            || atlas.height > 2048
            || atlas.data.count != Int(atlas.width) * Int(atlas.height)
        {
            return .failure(SceneError("invalid atlas or primitive count"))
        }
        func validColor(_ c: [Float]) -> Bool {
            guard c.count == 4 else { return false }
            for v in c {
                if !v.isFinite || v < 0.0 || v > 1.0 {
                    return false
                }
            }
            return c[0] <= c[3] && c[1] <= c[3] && c[2] <= c[3]
        }
        if !validColor(clear) {
            return .failure(SceneError("clear must be premultiplied linear RGBA"))
        }
        let validKinds: [Float] = [0.0, 1.0, 2.0, 3.0, 4.0, 8.0, 9.0, 10.0, 11.0, 12.0]
        var layerDepth = 0
        for p in primitives {
            guard p.rect.count == 4,
                  p.radii.count == 4,
                  p.fill.count == 4,
                  p.border.count == 4,
                  p.params.count == 4,
                  p.uv.count == 4,
                  p.clip.count == 4,
                  p.fade.count == 4,
                  (p.fadeOrigin == nil || p.fadeOrigin?.count == 4)
            else {
                return .failure(SceneError("invalid primitive \(p.node) (\(p.source))"))
            }
            if p.params[1] == 8.0 {
                if layerDepth == MAX_LAYER_DEPTH || p.params[2] != 0.0 {
                    return .failure(SceneError("unsupported layer \(p.node) (\(p.source))"))
                }
                let validBlend = p.params[0] == 0.0 || p.params[0] == 1.0
                let validCache = p.params[3] == 0.0 || p.params[3] == 1.0
                var badCacheKey = false
                if p.params[3] == 1.0 {
                    for v in p.radii + p.uv {
                        if !v.isFinite || v < 0.0 || v > 65535.0 || v.truncatingRemainder(dividingBy: 1.0) != 0.0 {
                            badCacheKey = true
                            break
                        }
                    }
                }
                if !validBlend || !validCache || badCacheKey {
                    return .failure(SceneError("invalid layer \(p.node) (\(p.source))"))
                }
                layerDepth += 1
            } else if p.params[1] == 9.0 {
                if layerDepth == 0 {
                    return .failure(SceneError("unbalanced layer end \(p.node) (\(p.source))"))
                }
                layerDepth -= 1
            }

            let origin = p.fadeOrigin ?? p.clip
            let allGroups = [p.rect, p.radii, p.fill, p.border, p.params, p.uv, p.clip, p.fade, origin]
            var nonFiniteOrHuge = false
            for g in allGroups {
                for v in g {
                    if !v.isFinite || abs(v) > 1e6 {
                        nonFiniteOrHuge = true
                        break
                    }
                }
                if nonFiniteOrHuge { break }
            }

            let isKnownKind = validKinds.contains(p.params[1])
            let isEmptyAllowed = p.params[1] == 9.0 || p.params[1] == 12.0
            let badBorder: Bool
            if p.params[1] == 8.0 {
                badBorder = p.border.contains(where: { $0 < 0.0 }) && p.border.contains(where: { $0 > 0.0 })
            } else {
                badBorder = !validColor(p.border)
            }
            let badTurn: Bool
            if let t = p.turn {
                badTurn = t.count != 3
                    || p.params[1] != 8.0
                    || p.params[3] == 1.0
                    || t[0] == 0.0
                    || t.contains(where: { !$0.isFinite || abs($0) > 1e6 })
            } else {
                badTurn = false
            }

            if nonFiniteOrHuge
                || !isKnownKind
                || (!isEmptyAllowed && (p.rect[2] <= 0.0 || p.rect[3] <= 0.0))
                || p.rect[2] < 0.0
                || p.rect[3] < 0.0
                || p.radii.contains(where: { $0 < 0.0 })
                || p.fade.contains(where: { $0 < 0.0 })
                || (p.params[0] < 0.0 && p.params[1] != 2.0)
                || p.params[2] < 0.0
                || !validColor(p.fill)
                || badBorder
                || badTurn
                || (p.params[1] == 4.0 && !validColor(p.uv))
                || (p.params[1] == 10.0 && (p.uv[0] <= 0.0 || p.uv[1] <= 0.0))
                || (p.params[1] == 11.0 && (p.uv[2] < 0.0 || p.uv[3] < 0.0 || ((p.uv[2] > 0.0) != (p.uv[3] > 0.0))))
                || (p.params[1] == 2.0 && (p.params[3] <= 0.0 || p.uv.contains(where: { $0 < 0.0 })))
            {
                return .failure(SceneError("invalid primitive \(p.node) (\(p.source))"))
            }
        }
        if layerDepth != 0 {
            return .failure(SceneError("unclosed layer scope"))
        }
        return .success(())
    }
}

public struct Frame: Sendable {
    public var width: UInt32
    public var height: UInt32
    public var rgba: [UInt8]
    /// Last contributing primitive index, not nearest geometry. `nil` = clear.
    public var owners: [Int?]?

    public init(width: UInt32, height: UInt32, provenance: Bool) {
        precondition(width > 0 && height > 0 && width <= 4096 && height <= 4096)
        let n = Int(width) * Int(height)
        self.width = width
        self.height = height
        self.rgba = [UInt8](repeating: 0, count: n * 4)
        self.owners = provenance ? [Int?](repeating: nil, count: n) : nil
    }

    public static func new(_ width: UInt32, _ height: UInt32, _ provenance: Bool) -> Frame {
        Frame(width: width, height: height, provenance: provenance)
    }

    /// No allocations after `Frame` construction unless isolated/cached layers are present. `Scene` must pass `validate()`.
    public mutating func render(_ scene: Scene) {
        precondition(width == scene.width && height == scene.height)
        let clearBytes = encodeRgba8(F4(scene.clear))
        let pixelCount = Int(width) * Int(height)
        rgba.withUnsafeMutableBufferPointer { rgbaBuf in
            guard let base = rgbaBuf.baseAddress else { return }
            for i in 0..<pixelCount {
                let p = i * 4
                base[p] = clearBytes.0
                base[p + 1] = clearBytes.1
                base[p + 2] = clearBytes.2
                base[p + 3] = clearBytes.3
            }
            if owners != nil {
                var localOwners = owners!
                owners = nil
                localOwners.withUnsafeMutableBufferPointer { ownersBuf in
                    if let oBase = ownersBuf.baseAddress {
                        for i in 0..<pixelCount {
                            oBase[i] = nil
                        }
                    }
                    Self.renderRange(
                        width: width,
                        height: height,
                        rgba: rgbaBuf,
                        owners: ownersBuf,
                        hasOwners: true,
                        scene: scene,
                        start: 0,
                        end: scene.primitives.count
                    )
                }
                owners = localOwners
            } else {
                let emptyOwners = UnsafeMutableBufferPointer<Int?>(start: nil, count: 0)
                Self.renderRange(
                    width: width,
                    height: height,
                    rgba: rgbaBuf,
                    owners: emptyOwners,
                    hasOwners: false,
                    scene: scene,
                    start: 0,
                    end: scene.primitives.count
                )
                _ = emptyOwners
            }
        }
    }

    private static func renderRange(
        width: UInt32,
        height: UInt32,
        rgba: UnsafeMutableBufferPointer<UInt8>,
        owners: UnsafeMutableBufferPointer<Int?>,
        hasOwners: Bool,
        scene: Scene,
        start: Int,
        end: Int
    ) {
        var cursor = start
        while cursor < end {
            let p = scene.primitives[cursor]
            if p.params[1] == 8.0 {
                var depth = 1
                var close = cursor + 1
                while close < end && depth > 0 {
                    if scene.primitives[close].params[1] == 8.0 {
                        depth += 1
                    } else if scene.primitives[close].params[1] == 9.0 {
                        depth -= 1
                    }
                    if depth > 0 {
                        close += 1
                    }
                }
                let isZeroBorder = p.border[0] == 0.0 && p.border[1] == 0.0 && p.border[2] == 0.0 && p.border[3] == 0.0
                if p.params[3] == 0.0
                    && p.fill[3] == 1.0
                    && p.params[0] == 0.0
                    && p.params[2] == 0.0
                    && p.clip == NO_CLIP
                    && isZeroBorder
                    && p.turn == nil
                {
                    Self.renderRange(
                        width: width,
                        height: height,
                        rgba: rgba,
                        owners: owners,
                        hasOwners: hasOwners,
                        scene: scene,
                        start: cursor + 1,
                        end: close
                    )
                } else if p.fill[3] > 0.0 {
                    let pixelCount = Int(width) * Int(height)
                    var layerRgba = [UInt8](repeating: 0, count: pixelCount * 4)
                    var layerOwners: [Int?] = hasOwners ? [Int?](repeating: nil, count: pixelCount) : []
                    layerRgba.withUnsafeMutableBufferPointer { lRgbaBuf in
                        layerOwners.withUnsafeMutableBufferPointer { lOwnersBuf in
                            Self.renderRange(
                                width: width,
                                height: height,
                                rgba: lRgbaBuf,
                                owners: lOwnersBuf,
                                hasOwners: hasOwners,
                                scene: scene,
                                start: cursor + 1,
                                end: close
                            )
                        }
                    }
                    let turnInfo: (Float, Float, Float, Float)?
                    if let t = p.turn, t[0] != 0.0 {
                        turnInfo = (sinf(t[0]), cosf(t[0]), t[1], t[2])
                    } else {
                        turnInfo = nil
                    }
                    let x0: UInt32
                    let y0: UInt32
                    let x1: UInt32
                    let y1: UInt32
                    if turnInfo != nil {
                        x0 = 0
                        y0 = 0
                        x1 = width
                        y1 = height
                    } else {
                        x0 = UInt32(max(p.rect[0].rounded(.down), 0.0))
                        y0 = UInt32(max(p.rect[1].rounded(.down), 0.0))
                        x1 = min(UInt32(max((p.rect[0] + p.rect[2]).rounded(.up), 0.0)), width)
                        y1 = min(UInt32(max((p.rect[1] + p.rect[3]).rounded(.up), 0.0)), height)
                    }
                    let alpha = clamp01(p.fill[3])
                    if y0 < y1 && x0 < x1 {
                        for y in y0..<y1 {
                            for x in x0..<x1 {
                                let cov = alpha * layerClipCoverage(p, F2(Float(x) + 0.5, Float(y) + 0.5))
                                if cov <= 0.0 { continue }
                                let at = Int(y * width + x)
                                let src: F4
                                if let (sn, cs, px, py) = turnInfo {
                                    let qx = Float(x) + 0.5 - px
                                    let qy = Float(y) + 0.5 - py
                                    let ux = px + cs * qx + sn * qy - 0.5
                                    let uy = py + cs * qy - sn * qx - 0.5
                                    let bx = ux.rounded(.down)
                                    let by = uy.rounded(.down)
                                    let fx = ux - bx
                                    let fy = uy - by
                                    func texel(_ tx: Float, _ ty: Float) -> F4 {
                                        if tx < 0.0 || ty < 0.0 || tx >= Float(width) || ty >= Float(height) {
                                            return .zero
                                        }
                                        let idx = Int(UInt32(ty) * width + UInt32(tx)) * 4
                                        return decodeRgba8(
                                            layerRgba[idx],
                                            layerRgba[idx + 1],
                                            layerRgba[idx + 2],
                                            layerRgba[idx + 3]
                                        )
                                    }
                                    let a = texel(bx, by)
                                    let b = texel(bx + 1.0, by)
                                    let c = texel(bx, by + 1.0)
                                    let d = texel(bx + 1.0, by + 1.0)
                                    var s = F4.zero
                                    for k in 0..<4 {
                                        let top = a[k] * (1.0 - fx) + b[k] * fx
                                        let bottom = c[k] * (1.0 - fx) + d[k] * fx
                                        s[k] = top * (1.0 - fy) + bottom * fy
                                    }
                                    src = s
                                } else {
                                    let p4 = at * 4
                                    src = decodeRgba8(
                                        layerRgba[p4],
                                        layerRgba[p4 + 1],
                                        layerRgba[p4 + 2],
                                        layerRgba[p4 + 3]
                                    )
                                }
                                let col = src.scaled(cov)
                                if col.w <= 0.0 { continue }
                                let p4 = at * 4
                                let dst = decodeRgba8(rgba[p4], rgba[p4 + 1], rgba[p4 + 2], rgba[p4 + 3])
                                let out: F4
                                if p.params[0] == 1.0 {
                                    out = F4(col.x + dst.x, col.y + dst.y, col.z + dst.z, col.w + dst.w)
                                } else {
                                    let inv = 1.0 - col.w
                                    out = F4(
                                        col.x + dst.x * inv,
                                        col.y + dst.y * inv,
                                        col.z + dst.z * inv,
                                        col.w + dst.w * inv
                                    )
                                }
                                let enc = encodeRgba8(out)
                                rgba[p4] = enc.0
                                rgba[p4 + 1] = enc.1
                                rgba[p4 + 2] = enc.2
                                rgba[p4 + 3] = enc.3
                                if hasOwners {
                                    owners[at] = layerOwners[at] ?? cursor
                                }
                            }
                        }
                    }
                }
                cursor = close + 1
                continue
            }
            if p.params[1] == 9.0 {
                cursor += 1
                continue
            }
            for y in 0..<height {
                for x in 0..<width {
                    let col = fragment(p, scene.atlas, F2(Float(x) + 0.5, Float(y) + 0.5))
                    if col.w <= 0.0 { continue }
                    let at = Int(y * width + x)
                    let p4 = at * 4
                    let dst = decodeRgba8(rgba[p4], rgba[p4 + 1], rgba[p4 + 2], rgba[p4 + 3])
                    let inv = 1.0 - col.w
                    let out = F4(
                        col.x + dst.x * inv,
                        col.y + dst.y * inv,
                        col.z + dst.z * inv,
                        col.w + dst.w * inv
                    )
                    let enc = encodeRgba8(out)
                    rgba[p4] = enc.0
                    rgba[p4 + 1] = enc.1
                    rgba[p4 + 2] = enc.2
                    rgba[p4 + 3] = enc.3
                    if hasOwners {
                        owners[at] = cursor
                    }
                }
            }
            cursor += 1
        }
    }

    public func hash() -> String {
        blake3Hex(rgba)
    }

    public func blame(_ scene: Scene, _ x: UInt32, _ y: UInt32) -> Primitive? {
        if x >= width || y >= height {
            return nil
        }
        guard let ids = owners, let index = ids[Int(y * width + x)] else {
            return nil
        }
        guard index >= 0 && index < scene.primitives.count else {
            return nil
        }
        return scene.primitives[index]
    }
}

@inline(__always)
private func encodeChannel(_ raw: Float, isAlpha: Bool) -> UInt8 {
    let v0 = min(max(raw, 0.0), 1.0)
    let v: Float
    if isAlpha {
        v = v0
    } else if v0 <= 0.0031308 {
        v = v0 * 12.92
    } else {
        let invGamma: Float = Float(1.0) / Float(2.4)
        v = 1.055 * powf(v0, invGamma) - 0.055
    }
    return UInt8((v * 255.0).rounded(.toNearestOrAwayFromZero))
}

@inline(__always)
private func encodeRgba8(_ c: F4) -> (UInt8, UInt8, UInt8, UInt8) {
    (
        encodeChannel(c.x, isAlpha: false),
        encodeChannel(c.y, isAlpha: false),
        encodeChannel(c.z, isAlpha: false),
        encodeChannel(c.w, isAlpha: true)
    )
}

@inline(__always)
private func decodeChannel(_ byte: UInt8, isAlpha: Bool) -> Float {
    let v = Float(byte) / 255.0
    if isAlpha {
        return v
    } else if v <= 0.04045 {
        return v / 12.92
    } else {
        return powf((v + 0.055) / 1.055, 2.4)
    }
}

@inline(__always)
private func decodeRgba8(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> F4 {
    F4(
        decodeChannel(r, isAlpha: false),
        decodeChannel(g, isAlpha: false),
        decodeChannel(b, isAlpha: false),
        decodeChannel(a, isAlpha: true)
    )
}

public struct Difference: Sendable, Equatable, Codable {
    public var maxChannel: UInt8
    public var outlierPixels: Int
    public var first: PixelBlame?

    enum CodingKeys: String, CodingKey {
        case maxChannel = "max_channel"
        case outlierPixels = "outlier_pixels"
        case first
    }

    public init(maxChannel: UInt8, outlierPixels: Int, first: PixelBlame?) {
        self.maxChannel = maxChannel
        self.outlierPixels = outlierPixels
        self.first = first
    }
}

public struct PixelBlame: Sendable, Equatable, Codable {
    public var x: UInt32
    public var y: UInt32
    public var expected: [UInt8]
    public var actual: [UInt8]
    public var node: UInt32?
    public var source: String?

    public init(
        x: UInt32,
        y: UInt32,
        expected: [UInt8],
        actual: [UInt8],
        node: UInt32?,
        source: String?
    ) {
        self.x = x
        self.y = y
        self.expected = expected
        self.actual = actual
        self.node = node
        self.source = source
    }
}

/// Strict per-channel gate; no outlier allowance, no average that hides a bad edge.
public func compare(_ scene: Scene, _ cpu: Frame, _ gpu: [UInt8], _ tolerance: UInt8) -> Difference {
    precondition(cpu.rgba.count == gpu.count)
    var diff = Difference(maxChannel: 0, outlierPixels: 0, first: nil)
    let pixelCount = cpu.rgba.count / 4
    for at in 0..<pixelCount {
        let p4 = at * 4
        var d: UInt8 = 0
        for c in 0..<4 {
            let a = cpu.rgba[p4 + c]
            let b = gpu[p4 + c]
            let delta = a >= b ? (a - b) : (b - a)
            if delta > d { d = delta }
        }
        if d > diff.maxChannel {
            diff.maxChannel = d
        }
        if d <= tolerance {
            continue
        }
        diff.outlierPixels += 1
        if diff.first == nil {
            let x = UInt32(at) % cpu.width
            let y = UInt32(at) / cpu.width
            let p = cpu.blame(scene, x, y)
            diff.first = PixelBlame(
                x: x,
                y: y,
                expected: [cpu.rgba[p4], cpu.rgba[p4 + 1], cpu.rgba[p4 + 2], cpu.rgba[p4 + 3]],
                actual: [gpu[p4], gpu[p4 + 1], gpu[p4 + 2], gpu[p4 + 3]],
                node: p?.node,
                source: p?.source
            )
        }
    }
    return diff
}

// MARK: - Pure-Swift BLAKE3-256

// PORT NOTE: Replaces Rust `blake3::hash` with a self-contained pure-Swift BLAKE3 implementation (no external dependency).
private let BLAKE3_IV: [UInt32] = [
    0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
]

private let BLAKE3_CHUNK_START: UInt32 = 1 << 0
private let BLAKE3_CHUNK_END: UInt32 = 1 << 1
private let BLAKE3_PARENT: UInt32 = 1 << 2
private let BLAKE3_ROOT: UInt32 = 1 << 3

private let BLAKE3_MSG_PERMUTATION: [Int] = [
    2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8,
]

@inline(__always)
private func rotr32(_ x: UInt32, _ n: UInt32) -> UInt32 {
    (x >> n) | (x << (32 - n))
}

@inline(__always)
private func blake3G(
    _ state: inout [UInt32],
    _ a: Int,
    _ b: Int,
    _ c: Int,
    _ d: Int,
    _ mx: UInt32,
    _ my: UInt32
) {
    state[a] = state[a] &+ state[b] &+ mx
    state[d] = rotr32(state[d] ^ state[a], 16)
    state[c] = state[c] &+ state[d]
    state[b] = rotr32(state[b] ^ state[c], 12)
    state[a] = state[a] &+ state[b] &+ my
    state[d] = rotr32(state[d] ^ state[a], 8)
    state[c] = state[c] &+ state[d]
    state[b] = rotr32(state[b] ^ state[c], 7)
}

private func blake3Round(_ state: inout [UInt32], _ m: [UInt32]) {
    blake3G(&state, 0, 4, 8, 12, m[0], m[1])
    blake3G(&state, 1, 5, 9, 13, m[2], m[3])
    blake3G(&state, 2, 6, 10, 14, m[4], m[5])
    blake3G(&state, 3, 7, 11, 15, m[6], m[7])
    blake3G(&state, 0, 5, 10, 15, m[8], m[9])
    blake3G(&state, 1, 6, 11, 12, m[10], m[11])
    blake3G(&state, 2, 7, 8, 13, m[12], m[13])
    blake3G(&state, 3, 4, 9, 14, m[14], m[15])
}

private func blake3Compress(
    _ cv: [UInt32],
    _ blockWords: [UInt32],
    _ counter: UInt64,
    _ blockLen: UInt32,
    _ flags: UInt32
) -> [UInt32] {
    var state: [UInt32] = [
        cv[0], cv[1], cv[2], cv[3],
        cv[4], cv[5], cv[6], cv[7],
        BLAKE3_IV[0], BLAKE3_IV[1], BLAKE3_IV[2], BLAKE3_IV[3],
        UInt32(truncatingIfNeeded: counter),
        UInt32(truncatingIfNeeded: counter >> 32),
        blockLen,
        flags,
    ]
    var block = blockWords
    for r in 0..<7 {
        blake3Round(&state, block)
        if r < 6 {
            var permuted = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                permuted[i] = block[BLAKE3_MSG_PERMUTATION[i]]
            }
            block = permuted
        }
    }
    for i in 0..<8 {
        state[i] ^= state[i + 8]
        state[i + 8] ^= cv[i]
    }
    return state
}

private func wordsFromLittleEndianBlock(_ bytes: ArraySlice<UInt8>) -> [UInt32] {
    var words = [UInt32](repeating: 0, count: 16)
    var idx = bytes.startIndex
    var pos = 0
    while idx < bytes.endIndex {
        let shift = (pos & 3) * 8
        words[pos >> 2] |= UInt32(bytes[idx]) << shift
        idx = bytes.index(after: idx)
        pos += 1
    }
    return words
}

private struct Blake3Output {
    var inputCv: [UInt32]
    var blockWords: [UInt32]
    var counter: UInt64
    var blockLen: UInt32
    var flags: UInt32

    func chainingValue() -> [UInt32] {
        Array(blake3Compress(inputCv, blockWords, counter, blockLen, flags).prefix(8))
    }

    func rootHex() -> String {
        let out = blake3Compress(inputCv, blockWords, 0, blockLen, flags | BLAKE3_ROOT)
        let hexDigits = Array("0123456789abcdef".utf8)
        var chars = [UInt8]()
        chars.reserveCapacity(64)
        for i in 0..<8 {
            let w = out[i]
            for b in 0..<4 {
                let byte = Int((w >> (b * 8)) & 0xff)
                chars.append(hexDigits[byte >> 4])
                chars.append(hexDigits[byte & 0x0f])
            }
        }
        return String(decoding: chars, as: UTF8.self)
    }
}

private struct Blake3ChunkState {
    var cv: [UInt32] = BLAKE3_IV
    var chunkCounter: UInt64
    var block: [UInt8] = []
    var blocksCompressed: UInt8 = 0

    init(chunkCounter: UInt64) {
        self.chunkCounter = chunkCounter
        self.block.reserveCapacity(64)
    }

    var len: Int {
        64 * Int(blocksCompressed) + block.count
    }

    var startFlag: UInt32 {
        blocksCompressed == 0 ? BLAKE3_CHUNK_START : 0
    }

    mutating func update(_ input: ArraySlice<UInt8>) {
        var slice = input
        while !slice.isEmpty {
            if block.count == 64 {
                let words = wordsFromLittleEndianBlock(block[...])
                cv = Array(blake3Compress(cv, words, chunkCounter, 64, startFlag).prefix(8))
                blocksCompressed += 1
                block.removeAll(keepingCapacity: true)
            }
            let want = 64 - block.count
            let take = min(want, slice.count)
            let end = slice.index(slice.startIndex, offsetBy: take)
            block.append(contentsOf: slice[slice.startIndex..<end])
            slice = slice[end...]
        }
    }

    func output() -> Blake3Output {
        Blake3Output(
            inputCv: cv,
            blockWords: wordsFromLittleEndianBlock(block[...]),
            counter: chunkCounter,
            blockLen: UInt32(block.count),
            flags: startFlag | BLAKE3_CHUNK_END
        )
    }
}

private func blake3ParentOutput(_ leftCv: [UInt32], _ rightCv: [UInt32]) -> Blake3Output {
    var blockWords = [UInt32](repeating: 0, count: 16)
    for i in 0..<8 {
        blockWords[i] = leftCv[i]
        blockWords[i + 8] = rightCv[i]
    }
    return Blake3Output(
        inputCv: BLAKE3_IV,
        blockWords: blockWords,
        counter: 0,
        blockLen: 64,
        flags: BLAKE3_PARENT
    )
}

func blake3Hex(_ input: [UInt8]) -> String {
    var chunkState = Blake3ChunkState(chunkCounter: 0)
    var cvStack: [[UInt32]] = []
    var slice = input[...]
    while !slice.isEmpty {
        if chunkState.len == 1024 {
            var newCv = chunkState.output().chainingValue()
            var totalChunks = chunkState.chunkCounter + 1
            while (totalChunks & 1) == 0 {
                let left = cvStack.removeLast()
                newCv = blake3ParentOutput(left, newCv).chainingValue()
                totalChunks >>= 1
            }
            cvStack.append(newCv)
            chunkState = Blake3ChunkState(chunkCounter: chunkState.chunkCounter + 1)
        }
        let want = 1024 - chunkState.len
        let take = min(want, slice.count)
        let end = slice.index(slice.startIndex, offsetBy: take)
        chunkState.update(slice[slice.startIndex..<end])
        slice = slice[end...]
    }
    var output = chunkState.output()
    while let left = cvStack.popLast() {
        output = blake3ParentOutput(left, output.chainingValue())
    }
    return output.rootHex()
}
