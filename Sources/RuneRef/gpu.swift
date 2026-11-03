// Ported from: crates/rune-ref/src/gpu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Adapter to the production renderer. No copied WGSL or substitute GPU pipeline.

import Rune

extension Primitive {
    /// Capture an application's emitted primitive with its inspector metadata.
    public static func fromInstance(_ p: Rune.Instance, _ node: UInt32, _ source: String) -> Primitive {
        let (fade, offset) = Rune.unpackFade(p.fade)
        let border: [Float] = p.params[1] == 8.0 ? Rune.unpackClipRadii(p.fade[3]) : p.border
        let fadeOrigin: [Float] = (0..<4).map { e in
            let sign: Float = e < 2 ? -1.0 : 1.0
            return p.clip[e] + offset[e] * fade[e] * sign
        }
        let turn: [Float]? = (p.params[1] == 8.0 && p.border[1] != 0.0)
            ? [p.border[1], p.border[2], p.border[3]]
            : nil
        return Primitive(
            node: node,
            source: source,
            rect: p.rect,
            radii: p.radii,
            fill: p.fill,
            border: border,
            params: p.params,
            uv: p.uv,
            clip: p.clip,
            fade: fade,
            fadeOrigin: fadeOrigin,
            turn: turn
        )
    }

    public func toInstance() -> Rune.Instance {
        let borderVal: [Float]
        if params[1] == 8.0 {
            let t = turn ?? [0.0, 0.0, 0.0]
            borderVal = [0.0, t[0], t[1], t[2]]
        } else {
            borderVal = border
        }
        var instance = Rune.Instance(
            rect: rect,
            radii: radii,
            fill: fill,
            border: borderVal,
            params: params,
            uv: uv,
            clip: clip,
            fade: Rune.packFade(fade, fadeOrigin ?? clip, clip)
        )
        if params[1] == 8.0 {
            instance.fade[3] = Rune.packClipRadii(clip, border)
        }
        return instance
    }
}

extension Rune.Instance {
    public init(_ p: Primitive) {
        self = p.toInstance()
    }
}

public final class GpuRenderer {
    public var gpu: Rune.Gpu
    public var renderer: Rune.Renderer
    public var text: Rune.TextSystem
    // PORT NOTE: Tracks the high-water row count from the previous render (`ATLAS_SIZE` on first call)
    // so `render(_:)` only zeros and re-uploads rows that could actually differ from zero, avoiding
    // 4 MB Debug-mode element loops on 32x32 synthetic scenes while preserving identical atlas contents.
    private var prevDirtyRows: UInt32 = Rune.ATLAS_SIZE

    public init() {
        let g = Rune.Gpu()
        self.gpu = g
        self.renderer = Rune.Renderer(g.metalDevice, Rune.OFFSCREEN_FORMAT)
        self.text = Rune.TextSystem()
    }

    public static func `default`() -> GpuRenderer {
        GpuRenderer()
    }

    public func render(_ scene: Scene) -> [UInt8] {
        switch scene.validate() {
        case .success:
            break
        case .failure(let err):
            preconditionFailure("valid differential scene: \(err)")
        }
        let stride = Int(Rune.ATLAS_SIZE)
        let copyW = min(Int(scene.atlas.width), stride)
        let copyH = min(Int(scene.atlas.height), stride)
        let span = min(max(prevDirtyRows, UInt32(copyH)), Rune.ATLAS_SIZE)
        let zeroCount = min(Int(span) * stride, text.atlas.data.count)
        text.atlas.data.withUnsafeMutableBufferPointer { dst in
            guard let dstBase = dst.baseAddress else { return }
            if zeroCount > 0 {
                dstBase.update(repeating: 0, count: zeroCount)
            }
            scene.atlas.data.withUnsafeBufferPointer { src in
                guard let srcBase = src.baseAddress, copyW > 0 else { return }
                let srcStride = Int(scene.atlas.width)
                for y in 0..<copyH {
                    let srcOff = y * srcStride
                    let dstOff = y * stride
                    if srcOff + copyW <= src.count && dstOff + copyW <= dst.count {
                        (dstBase + dstOff).update(from: srcBase + srcOff, count: copyW)
                    }
                }
            }
        }
        text.atlas.dirty = (0, span)
        prevDirtyRows = UInt32(copyH)
        let instances = scene.primitives.map { Rune.Instance($0) }
        return Rune.Offscreen.renderScene(
            gpu: gpu,
            renderer: renderer,
            atlas: &text.atlas,
            instances: instances,
            width: scene.width,
            height: scene.height,
            clear: scene.clear
        )
    }
}

/// Add a glyph run, then freeze its atlas into the replay scene.
/// Shaping is deliberately outside the oracle: this lane tests glyph sampling.
public func textRun(_ scene: inout Scene, _ seed: UInt64) {
    let text = Rune.TextSystem()
    let strings = ["Rune ffi", "Ág jW", "012345", "a\u{301} test"]
    let chosen = strings[Int(seed % UInt64(strings.count))]
    let fontSize: Float = 9.0 + Float(seed % 15)
    let gw = max(UInt32((fontSize * 0.55).rounded(.toNearestOrAwayFromZero)), 4)
    let gh = max(UInt32((fontSize * 0.85).rounded(.toNearestOrAwayFromZero)), 6)
    let lineH = (fontSize * 1.25).rounded(.up)
    let stride = Int(Rune.ATLAS_SIZE)

    struct EmittedGlyph {
        var byte: Int
        var rect: [Float]
        var uv: [Float]
    }
    var quads: [EmittedGlyph] = []
    var penX: Float = 2.0
    var penY: Float = 2.0
    var shelfX: UInt32 = 0
    var shelfY: UInt32 = 0
    var shelfH: UInt32 = 0
    var byteOffset = 0
    for scalar in chosen.unicodeScalars {
        let scalarLen = scalar.utf8.count
        defer { byteOffset += scalarLen }
        if scalar.properties.generalCategory == .nonspacingMark {
            continue
        }
        let adv = Float(gw) + 1.0
        if penX + Float(gw) > 62.0 && penX > 2.0 {
            penX = 2.0
            penY += lineH
        }
        if scalar == " " {
            penX += max(Float(gw) * 0.5, 3.0)
            continue
        }
        let allocW = gw + 2
        let allocH = gh + 2
        if shelfX + allocW > 900 {
            shelfX = 0
            shelfY += shelfH
            shelfH = 0
        }
        if shelfY + allocH <= 900 {
            let ax = shelfX
            let ay = shelfY
            shelfX += allocW
            shelfH = max(shelfH, allocH)
            let ux = Int(ax + 1)
            let uy = Int(ay + 1)
            let code = UInt32(scalar.value)
            for gy in 0..<Int(gh) {
                for gx in 0..<Int(gw) {
                    let cx = Float(gx) + 0.5 - Float(gw) * 0.5
                    let cy = Float(gy) + 0.5 - Float(gh) * 0.5
                    let rx = max(Float(gw) * 0.42, 1.5)
                    let ry = max(Float(gh) * 0.42, 2.0)
                    let norm = ((cx / rx) * (cx / rx) + (cy / ry) * (cy / ry)).squareRoot()
                    let ring = max(0.0, 1.0 - abs(norm - 0.65) * 2.4)
                    let bar: Float = ((gx + Int(code % 3)) % max(Int(gw) / 2, 2) == 0) ? 0.55 : 0.0
                    let val = min(max(ring + bar, 0.0), 1.0)
                    let byteVal = UInt8((val * 255.0).rounded(.toNearestOrAwayFromZero))
                    text.atlas.data[(uy + gy) * stride + (ux + gx)] = byteVal
                }
            }
            quads.append(
                EmittedGlyph(
                    byte: byteOffset,
                    rect: [penX.rounded(.down), penY.rounded(.down), Float(gw), Float(gh)],
                    uv: [Float(ux), Float(uy)]
                )
            )
        }
        penX += adv
    }

    // Keep synthetic atlas texels used by earlier generated glyphs in a separate region.
    for idx in scene.primitives.indices {
        if scene.primitives[idx].params[1] == 2.0 {
            scene.primitives[idx].uv[0] += 960.0
            scene.primitives[idx].uv[1] += 960.0
        }
    }
    let copyH = min(Int(scene.atlas.height), 32)
    let copyW = min(Int(scene.atlas.width), 32)
    let srcStride = Int(scene.atlas.width)
    for y in 0..<copyH {
        let dstStart = (y + 960) * stride + 960
        let srcStart = y * srcStride
        for x in 0..<copyW {
            text.atlas.data[dstStart + x] = scene.atlas.data[srcStart + x]
        }
    }
    let first = UInt32(scene.primitives.count + 1)
    for (n, q) in quads.enumerated() {
        scene.primitives.append(
            Primitive(
                node: first + UInt32(n),
                source: "text/\(seed)/byte-\(q.byte)",
                rect: q.rect,
                radii: [0.0, 0.0, 0.0, 0.0],
                fill: [0.7, 0.6, 0.5, 0.8],
                border: [0.0, 0.0, 0.0, 0.0],
                params: [0.0, 2.0, 0.0, 0.85],
                uv: [q.uv[0], q.uv[1], 0.0, 0.0],
                clip: NO_CLIP,
                fade: [0.0, 0.0, 0.0, 0.0],
                fadeOrigin: nil,
                turn: nil
            )
        )
    }
    scene.atlas = Atlas(
        width: Rune.ATLAS_SIZE,
        height: Rune.ATLAS_SIZE,
        data: text.atlas.data
    )
}

/// Namespace mirroring `rune_ref::gpu::*`.
public enum gpu {
    public typealias GpuRenderer = RuneRef.GpuRenderer

    public static func textRun(_ scene: inout Scene, _ seed: UInt64) {
        RuneRef.textRun(&scene, seed)
    }
}
