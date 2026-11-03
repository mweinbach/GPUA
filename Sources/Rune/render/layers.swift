// Ported from: crates/rune/src/render/layers.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Bounded painter scopes. The ordinary path retains its instance buffer, batches and pass;
//! only scopes requiring isolation acquire a target. Scope records are also compositor fences.

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
import CWebGPU

let LAYER_FORMAT: WGPUTextureFormat = WGPUTextureFormat_RGBA16Float
/// Default offscreen texture budget for `El.cache` subtrees (64 MiB).
public let DEFAULT_CACHE_BUDGET: UInt64 = 64 * 1024 * 1024
private let MAX_CACHE_DIM: UInt32 = 4096

/// Resource/pass counters for diagnostics. The ordinary path creates no layer resources.
public struct LayerStats: Sendable, Equatable {
    public var targets: Int
    public var bytes: UInt64
    public var extraPasses: Int
    public var allocations: UInt64

    public init(
        targets: Int = 0,
        bytes: UInt64 = 0,
        extraPasses: Int = 0,
        allocations: UInt64 = 0
    ) {
        self.targets = targets
        self.bytes = bytes
        self.extraPasses = extraPasses
        self.allocations = allocations
    }
}

struct PlannedLayer {
    var begin: UInt32
    var end: UInt32
    var parent: Int?
    var bounds: [Float]
    var vis: [Float]
    var clip: [Float]
    var limit: [Float]
    var fade: [UInt32]
    var opacity: Float
    var blend: Blend
    var blur: Float
    var support: Float
    var cache: (UInt64, UInt64)?
    var needsRender: Bool
    var turn: (Float, [Float])?
    var free: Bool
    var frame: [Float]
}

final class LayerTarget {
    var identity: UInt64
    var compositeParent: UInt64?
    var texture: MetalTexture
    var view: MetalView
    var projection: MetalBuffer
    var quad: MetalBuffer
    var composite: MetalBindGroup
    var base: MetalBindGroup
    var images: [MetalBindGroup?]
    var glyphs: [MetalBindGroup]
    var imageGeneration: UInt64
    var blur: LayerBlurScratch?
    var cacheNode: UInt64?
    var cacheSig: UInt64
    var lastUsed: UInt64
    var contentSize: [Float]

    init(
        identity: UInt64,
        compositeParent: UInt64?,
        texture: MetalTexture,
        view: MetalView,
        projection: MetalBuffer,
        quad: MetalBuffer,
        composite: MetalBindGroup,
        base: MetalBindGroup,
        images: [MetalBindGroup?],
        glyphs: [MetalBindGroup],
        imageGeneration: UInt64,
        blur: LayerBlurScratch?,
        cacheNode: UInt64?,
        cacheSig: UInt64,
        lastUsed: UInt64,
        contentSize: [Float]
    ) {
        self.identity = identity
        self.compositeParent = compositeParent
        self.texture = texture
        self.view = view
        self.projection = projection
        self.quad = quad
        self.composite = composite
        self.base = base
        self.images = images
        self.glyphs = glyphs
        self.imageGeneration = imageGeneration
        self.blur = blur
        self.cacheNode = cacheNode
        self.cacheSig = cacheSig
        self.lastUsed = lastUsed
        self.contentSize = contentSize
    }
}

final class Layers {
    var plan: [PlannedLayer] = []
    var targets: [LayerTarget?] = []
    var retained: [LayerTarget] = []
    var stack: [Int] = []
    var pipelines: [(WGPUTextureFormat, MetalRenderPipeline)] = []
    var additive: (MetalRenderPipeline, MetalRenderPipeline)? = nil
    var blur: LayerBlurPipeline? = nil
    var viewport: (UInt32, UInt32) = (0, 0)
    var imageGeneration: UInt64 = 0
    var allocations: UInt64 = 0
    var cacheBudget: UInt64 = DEFAULT_CACHE_BUDGET
    var frameStamp: UInt64 = 0

    func forgetBlurUniforms() {
        for t in targets.compactMap({ $0 }) {
            t.blur?.forgetUniforms()
        }
        for t in retained {
            t.blur?.forgetUniforms()
        }
    }
}

/// Upright bounds of edges `r` (`[x0, y0, x1, y1]`) turned `angle` radians clockwise about `p`.
func turnedBounds(_ r: [Float], _ angle: Float, _ p: [Float]) -> [Float] {
    let sn = sinf(angle)
    let c = cosf(angle)
    var out: [Float] = [.infinity, .infinity, -.infinity, -.infinity]
    for (x, y) in [(r[0], r[1]), (r[2], r[1]), (r[0], r[3]), (r[2], r[3])] {
        let dx = x - p[0]
        let dy = y - p[1]
        let qx = p[0] + c * dx - sn * dy
        let qy = p[1] + sn * dx + c * dy
        out[0] = min(out[0], qx)
        out[1] = min(out[1], qy)
        out[2] = max(out[2], qx)
        out[3] = max(out[3], qy)
    }
    return out
}

@inline(__always)
private func unionBounds(_ a: inout [Float], _ b: [Float]) {
    if b[2] <= b[0] || b[3] <= b[1] { return }
    a[0] = min(a[0], b[0])
    a[1] = min(a[1], b[1])
    a[2] = max(a[2], b[2])
    a[3] = max(a[3], b[3])
}

extension Renderer {
    static func targetBytes(_ t: LayerTarget) -> UInt64 {
        let bpp = UInt64(metalFormatBytesPerPixel(LAYER_FORMAT))
        var bytes = UInt64(t.texture.width) * UInt64(t.texture.height) * bpp
        if let blur = t.blur {
            bytes += blur.bytes()
        }
        return bytes
    }

    /// Maximum bytes of offscreen textures retained for `El.cache` subtrees before LRU eviction.
    public func setCacheBudget(_ bytes: UInt64) {
        layers.cacheBudget = bytes
        var retainedBytes = layers.retained.reduce(UInt64(0)) { $0 + Self.targetBytes($1) }
        while !layers.retained.isEmpty && retainedBytes > bytes {
            var oldestIdx = 0
            for idx in 1..<layers.retained.count {
                if layers.retained[idx].lastUsed < layers.retained[oldestIdx].lastUsed {
                    oldestIdx = idx
                }
            }
            retainedBytes -= Self.targetBytes(layers.retained[oldestIdx])
            let last = layers.retained.removeLast()
            if oldestIdx < layers.retained.count {
                layers.retained[oldestIdx] = last
            }
        }
    }

    public func cacheBudget() -> UInt64 {
        layers.cacheBudget
    }

    func syncResidentCaches(_ out: inout [UInt64: UInt64]) {
        if !out.isEmpty {
            out.removeAll(keepingCapacity: true)
        }
        for t in layers.targets.compactMap({ $0 }) {
            if let node = t.cacheNode {
                out[node] = t.cacheSig
            }
        }
        for t in layers.retained {
            if let node = t.cacheNode {
                out[node] = t.cacheSig
            }
        }
    }

    public func layerStats() -> LayerStats {
        var stats = LayerStats(allocations: layers.allocations)
        for (index, slot) in layers.targets.enumerated() {
            guard let t = slot else { continue }
            stats.targets += 1
            stats.bytes += Self.targetBytes(t)
            if let blur = t.blur {
                stats.extraPasses += blur.passes()
            }
            if index >= layers.plan.count || layers.plan[index].needsRender {
                stats.extraPasses += 1
            }
        }
        for t in layers.retained {
            stats.targets += 1
            stats.bytes += Self.targetBytes(t)
        }
        return stats
    }

    func prepareLayers(
        _ device: MetalDevice,
        _ queue: MetalQueue,
        _ instances: [Instance],
        _ viewport: (UInt32, UInt32)
    ) {
        let st = uploads.staging(device, queue)
        layers.viewport = viewport
        let hadLayers = !layers.plan.isEmpty
        for idx in layers.targets.indices {
            if let t = layers.targets[idx], t.cacheNode != nil {
                layers.targets[idx] = nil
                layers.retained.append(t)
            }
        }
        layers.plan.removeAll(keepingCapacity: true)
        layers.stack.removeAll(keepingCapacity: true)

        for (index, i) in instances.enumerated() {
            if i.params[1] == KIND_LAYER {
                let parent = layers.stack.last
                let parentCachedHit: Bool = parent.map { p in
                    guard let (n, s) = layers.plan[p].cache else { return false }
                    return layers.retained.contains(where: { $0.cacheNode == n && $0.cacheSig == s })
                } ?? false
                let hidden = (parent.map { layers.plan[$0].opacity == 0.0 } ?? false) || parentCachedHit
                let rawLimit: [Float]
                if let p = parent {
                    let pl = layers.plan[p]
                    let grow = (3.0 * pl.blur).rounded(.up)
                    rawLimit = [
                        max(pl.clip[0], pl.limit[0]) - grow,
                        max(pl.clip[1], pl.limit[1]) - grow,
                        min(pl.clip[2], pl.limit[2]) + grow,
                        min(pl.clip[3], pl.limit[3]) + grow,
                    ]
                } else {
                    rawLimit = NO_CLIP
                }
                let blur = layerBlurSigma(i.params[2])
                let cache: (UInt64, UInt64)? = (i.params[3] == 1.0)
                    ? (unpackU64F32(i.radii), unpackU64F32(i.uv))
                    : nil
                let turn: (Float, [Float])? = (i.border[1] != 0.0)
                    ? (i.border[1], [i.border[2], i.border[3]])
                    : nil
                let parentFree = parent.map { layers.plan[$0].free } ?? false
                let free = turn != nil || parentFree
                let frame: [Float]
                if free {
                    let outer: [Float]
                    if let p = parent, parentFree {
                        outer = layers.plan[p].frame
                    } else {
                        let sup = parent.map { layers.plan[$0].support } ?? 0.0
                        outer = [-sup, -sup, Float(viewport.0) + sup, Float(viewport.1) + sup]
                    }
                    let shown = [
                        max(outer[0], i.clip[0]),
                        max(outer[1], i.clip[1]),
                        min(outer[2], i.clip[2]),
                        min(outer[3], i.clip[3]),
                    ]
                    if let (angle, pivot) = turn, shown[2] > shown[0] && shown[3] > shown[1] {
                        frame = turnedBounds(shown, -angle, pivot)
                    } else {
                        frame = shown
                    }
                } else {
                    frame = [0, 0, 0, 0]
                }
                let limit = parentFree ? NO_CLIP : rawLimit
                let parentSupport = parent.map { layers.plan[$0].support } ?? 0.0
                layers.stack.append(layers.plan.count)
                layers.plan.append(
                    PlannedLayer(
                        begin: UInt32(index),
                        end: 0,
                        parent: parent,
                        bounds: [i.rect[0], i.rect[1], i.rect[0] + i.rect[2], i.rect[1] + i.rect[3]],
                        vis: [0, 0, 0, 0],
                        clip: i.clip,
                        limit: limit,
                        fade: i.fade,
                        opacity: hidden ? 0.0 : min(max(i.fill[3], 0.0), 1.0),
                        blend: (i.params[0] == 1.0) ? .plusLighter : .sourceOver,
                        blur: blur,
                        support: parentSupport + (3.0 * blur).rounded(.up),
                        cache: cache,
                        needsRender: true,
                        turn: turn,
                        free: free,
                        frame: frame
                    )
                )
            } else if i.params[1] == KIND_LAYER_END {
                guard let at = layers.stack.popLast() else {
                    fatalError("unbalanced layer end")
                }
                layers.plan[at].end = UInt32(index)
                let grow = (3.0 * layers.plan[at].blur).rounded(.up)
                let b = layers.plan[at].bounds
                let vis: [Float]
                if layers.plan[at].free {
                    let f = layers.plan[at].frame
                    vis = [
                        max(b[0] - grow, f[0] - grow).rounded(.down),
                        max(b[1] - grow, f[1] - grow).rounded(.down),
                        min(b[2] + grow, f[2] + grow).rounded(.up),
                        min(b[3] + grow, f[3] + grow).rounded(.up),
                    ]
                } else {
                    let c = layers.plan[at].clip
                    let lim = layers.plan[at].limit
                    let sup = layers.plan[at].support
                    vis = [
                        max(max(b[0] - grow, max(c[0], lim[0]) - grow), -sup).rounded(.down),
                        max(max(b[1] - grow, max(c[1], lim[1]) - grow), -sup).rounded(.down),
                        min(min(b[2] + grow, min(c[2], lim[2]) + grow), Float(viewport.0) + sup).rounded(.up),
                        min(min(b[3] + grow, min(c[3], lim[3]) + grow), Float(viewport.1) + sup).rounded(.up),
                    ]
                }
                layers.plan[at].vis = vis
                if layers.plan[at].cache != nil {
                    if vis[2] <= vis[0] || vis[3] <= vis[1] {
                        layers.plan[at].opacity = 0.0
                    }
                    layers.plan[at].bounds = [b[0].rounded(.down), b[1].rounded(.down), b[2].rounded(.up), b[3].rounded(.up)]
                } else {
                    layers.plan[at].bounds = vis
                }
                let finalB = layers.plan[at].bounds
                let parentContribution: [Float]
                if let (angle, pivot) = layers.plan[at].turn, finalB[2] > finalB[0] && finalB[3] > finalB[1] {
                    parentContribution = turnedBounds(finalB, angle, pivot)
                } else {
                    parentContribution = finalB
                }
                if let parentIdx = layers.plan[at].parent, layers.plan[parentIdx].cache == nil {
                    unionBounds(&layers.plan[parentIdx].bounds, parentContribution)
                }
            } else if let at = layers.stack.last {
                if layers.plan[at].cache != nil { continue }
                var rect = i.rect
                if i.params[1] == KIND_GLYPH && i.params[0] != 0.0 {
                    let s = sinf(i.params[0])
                    let c = cosf(i.params[0])
                    let w = abs(c) * rect[2] + abs(s) * rect[3]
                    let h = abs(s) * rect[2] + abs(c) * rect[3]
                    rect = [rect[0] + (rect[2] - w) * 0.5, rect[1] + (rect[3] - h) * 0.5, w, h]
                }
                let grow: Float
                switch i.params[1] {
                case KIND_GLYPH:
                    grow = 0.0
                case KIND_SHADOW:
                    grow = i.params[2] * 3.0 + 1.0
                case KIND_EFFECT:
                    grow = i.params[2] + 1.0
                case KIND_RECT, KIND_GRADIENT, KIND_DASHED, KIND_RADIAL:
                    grow = 1.0 + i.params[2] * 2.0
                default:
                    grow = 1.0
                }
                unionBounds(
                    &layers.plan[at].bounds,
                    [
                        max(rect[0] - grow, i.clip[0]),
                        max(rect[1] - grow, i.clip[1]),
                        min(rect[0] + rect[2] + grow, i.clip[2]),
                        min(rect[1] + rect[3] + grow, i.clip[3]),
                    ]
                )
            }
        }
        precondition(layers.stack.isEmpty, "unclosed layer scope")

        if layers.targets.count < layers.plan.count {
            layers.targets.append(contentsOf: repeatElement(nil, count: layers.plan.count - layers.targets.count))
        } else if layers.targets.count > layers.plan.count {
            layers.targets.removeSubrange(layers.plan.count..<layers.targets.count)
        }

        if !layers.plan.isEmpty || !layers.retained.isEmpty {
            layers.frameStamp &+= 1
        }
        let stamp = layers.frameStamp
        let maxDim = MAX_CACHE_DIM
        let bpp = UInt64(metalFormatBytesPerPixel(LAYER_FORMAT))
        var activeCacheBytes: UInt64 = 0

        for index in layers.plan.indices {
            layers.plan[index].bounds[2] = max(layers.plan[index].bounds[2] - layers.plan[index].bounds[0], 0.0)
            layers.plan[index].bounds[3] = max(layers.plan[index].bounds[3] - layers.plan[index].bounds[1], 0.0)
            if layers.plan[index].bounds[2] == 0.0 || layers.plan[index].bounds[3] == 0.0 {
                layers.plan[index].opacity = 0.0
            }
            guard layers.plan[index].opacity > 0.0,
                  let (nodeId, sig) = layers.plan[index].cache
            else { continue }
            guard let pos = layers.retained.firstIndex(where: { $0.cacheNode == nodeId && $0.cacheSig == sig }) else {
                continue
            }
            let tBytes = Self.targetBytes(layers.retained[pos])
            let overBudget = activeCacheBytes + tBytes > layers.cacheBudget
            if overBudget && layers.plan[index].begin + 1 < layers.plan[index].end {
                continue
            }
            let t = layers.retained.remove(at: pos)
            if overBudget {
                t.cacheNode = nil
            } else {
                t.lastUsed = stamp
                activeCacheBytes += tBytes
            }
            layers.plan[index].needsRender = false
            let b = layers.plan[index].bounds
            var quad = Instance.beginLayer(
                b,
                layers.plan[index].clip,
                LayerSpec(opacity: layers.plan[index].opacity, blend: layers.plan[index].blend)
            )
            quad.fade = layers.plan[index].fade
            if abs(t.contentSize[0] - b[2]) > 0.5 || abs(t.contentSize[1] - b[3]) > 0.5 {
                quad.uv = [0.0, 0.0, t.contentSize[0], t.contentSize[1]]
            }
            st.writeBuffer(t.quad, 0, instanceBytes(quad))
            layers.targets[index] = t
        }

        for index in layers.plan.indices {
            if !layers.plan[index].needsRender { continue }
            let additiveParent = layers.plan[index].parent.map { layers.plan[$0].blend == .plusLighter } ?? false
            if layers.plan[index].opacity == 0.0 {
                layers.targets[index] = nil
                continue
            }
            var bounds = layers.plan[index].bounds
            var width = UInt32(bounds[2])
            var height = UInt32(bounds[3])
            var bucket = (((width + 63) / 64) * 64, ((height + 63) / 64) * 64)
            var cacheTarget: (UInt64, UInt64)? = nil

            if let (nodeId, sig) = layers.plan[index].cache {
                let neededBytes = UInt64(bucket.0) * UInt64(bucket.1) * bpp
                if bucket.0 <= maxDim && bucket.1 <= maxDim && activeCacheBytes + neededBytes <= layers.cacheBudget {
                    activeCacheBytes += neededBytes
                    cacheTarget = (nodeId, sig)
                    if let pos = layers.retained.firstIndex(where: { $0.cacheNode == nodeId }) {
                        layers.targets[index] = layers.retained.remove(at: pos)
                    } else {
                        var retainedBytes = layers.retained.reduce(UInt64(0)) { $0 + Self.targetBytes($1) }
                        while !layers.retained.isEmpty && activeCacheBytes + retainedBytes > layers.cacheBudget {
                            var oldest = 0
                            for k in 1..<layers.retained.count {
                                if layers.retained[k].lastUsed < layers.retained[oldest].lastUsed {
                                    oldest = k
                                }
                            }
                            retainedBytes -= Self.targetBytes(layers.retained[oldest])
                            layers.retained.remove(at: oldest)
                        }
                    }
                } else {
                    if let pos = layers.retained.firstIndex(where: { $0.cacheNode == nodeId }) {
                        layers.retained.remove(at: pos)
                    }
                    layers.plan[index].cache = nil
                    let v = layers.plan[index].vis
                    bounds = [v[0], v[1], max(v[2] - v[0], 0.0), max(v[3] - v[1], 0.0)]
                    layers.plan[index].bounds = bounds
                    width = UInt32(bounds[2])
                    height = UInt32(bounds[3])
                    bucket = (((width + 63) / 64) * 64, ((height + 63) / 64) * 64)
                }
            }

            let l = layers.plan[index]
            if cacheTarget == nil
                && l.opacity == 1.0
                && l.blend == .sourceOver
                && !additiveParent
                && l.blur == 0.0
                && l.fade[3] == 0
                && l.clip == NO_CLIP
                && l.turn == nil {
                layers.targets[index] = nil
                continue
            }

            let needsTargetAlloc: Bool
            if let existing = layers.targets[index] {
                let sz = (existing.texture.width, existing.texture.height)
                needsTargetAlloc = sz.0 < width
                    || sz.1 < height
                    || (sz != bucket && UInt64(sz.0) * UInt64(sz.1) > 2 * UInt64(width) * UInt64(height))
            } else {
                needsTargetAlloc = true
            }

            if needsTargetAlloc {
                let (bw, bh) = (max(bucket.0, 1), max(bucket.1, 1))
                let tex = device.createTexture(
                    label: "isolated group",
                    format: LAYER_FORMAT,
                    width: bw,
                    height: bh,
                    usage: UInt32(WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopySrc)
                )
                let v = tex.createView()
                let proj = device.createBuffer(label: "layer projection", size: 16)
                let base = Self.makeBindGroup(device, bindLayout, globals, atlas, atlas, proj)
                let comp = Self.makeBindGroup(device, bindLayout, globals, atlas, tex, nil)
                layers.targets[index] = LayerTarget(
                    identity: layers.allocations + 1,
                    compositeParent: nil,
                    texture: tex,
                    view: v,
                    projection: proj,
                    quad: Self.makeInstanceBuffer(device, 1),
                    composite: comp,
                    base: base,
                    images: [],
                    glyphs: [],
                    imageGeneration: .max,
                    blur: nil,
                    cacheNode: nil,
                    cacheSig: 0,
                    lastUsed: 0,
                    contentSize: [0, 0]
                )
                layers.allocations &+= 1
            }

            let sigma = layers.plan[index].blur
            if sigma > 0.0 && layers.blur == nil {
                layers.blur = LayerBlurPipeline(device)
            }
            let t = layers.targets[index]!
            t.cacheNode = cacheTarget?.0
            t.cacheSig = cacheTarget?.1 ?? 0
            t.lastUsed = stamp
            t.contentSize = [bounds[2], bounds[3]]
            if sigma > 0.0 {
                let blurPipe = layers.blur!
                if t.blur == nil {
                    t.blur = blurPipe.scratch(device, t.texture)
                    layers.allocations &+= 1
                }
                if t.blur!.prepare(device, blurPipe, st, [bounds[2], bounds[3]], sigma, layers.plan[index].blend == .plusLighter) {
                    layers.allocations &+= 1
                }
            } else {
                t.blur = nil
            }
            st.writeBuffer(t.projection, 0, floatsBytes(bounds))
            var quad = Instance.beginLayer(
                bounds,
                layers.plan[index].clip,
                LayerSpec(opacity: layers.plan[index].opacity, blend: layers.plan[index].blend)
            )
            if let (angle, pivot) = layers.plan[index].turn {
                quad = quad.turned(angle, pivot)
            }
            quad.fade = layers.plan[index].fade
            st.writeBuffer(t.quad, 0, instanceBytes(quad))
        }

        if !layers.retained.isEmpty {
            var retainedBytes = layers.retained.reduce(UInt64(0)) { $0 + Self.targetBytes($1) }
            while !layers.retained.isEmpty && activeCacheBytes + retainedBytes > layers.cacheBudget {
                var oldest = 0
                for k in 1..<layers.retained.count {
                    if layers.retained[k].lastUsed < layers.retained[oldest].lastUsed {
                        oldest = k
                    }
                }
                retainedBytes -= Self.targetBytes(layers.retained[oldest])
                layers.retained.remove(at: oldest)
            }
        }

        for index in layers.plan.indices {
            guard let t = layers.targets[index] else { continue }
            let parent = findLayerTarget(layers.plan[index].parent)
            let parentIdentity = parent.flatMap { layers.targets[$0]?.identity }
            if t.compositeParent == parentIdentity { continue }
            let parentProj = parent.flatMap { layers.targets[$0]?.projection }
            t.composite = Self.makeBindGroup(device, bindLayout, globals, atlas, t.texture, parentProj)
            t.compositeParent = parentIdentity
        }

        if layers.targets.contains(where: { $0 != nil }) {
            addFormat(device, LAYER_FORMAT)
            addLayerFormat(device, format)
            for (extraFmt, _) in extra {
                addLayerFormat(device, extraFmt)
            }
        }
        if layers.plan.contains(where: { $0.blend == .plusLighter }) {
            if layers.additive == nil {
                layers.additive = (
                    Self.makePipeline(device, pipelineLayout, shader, LAYER_FORMAT, vertexEntry, .plusLighter),
                    Self.makePipeline(device, pipelineLayout, shader, LAYER_FORMAT, "vs", .plusLighter)
                )
            }
            #if !os(WASI)
            surfaces?.addPlusLighter(device, LAYER_FORMAT)
            #endif
        }
        refreshLayerBindings(device)
        if hadLayers || !layers.plan.isEmpty {
            positionLayerSurfaces(queue)
        }
    }

    func addLayerFormat(_ device: MetalDevice, _ fmt: WGPUTextureFormat) {
        if !layers.pipelines.contains(where: { $0.0 == fmt }) {
            layers.pipelines.append((fmt, Self.makePipeline(device, pipelineLayout, shader, fmt, "vs", .sourceOver)))
        }
    }

    private func findLayerTarget(_ startLayer: Int?) -> Int? {
        var cur = startLayer
        while let idx = cur {
            if layers.targets[idx] != nil {
                return idx
            }
            cur = layers.plan[idx].parent
        }
        return nil
    }

    func layerBlend(_ target: Int?) -> Blend {
        target.map { layers.plan[$0].blend } ?? .sourceOver
    }

    func imagesChanged() {
        layers.imageGeneration &+= 1
    }

    func refreshLayerBindings(_ device: MetalDevice) {
        for slot in layers.targets {
            guard let t = slot else { continue }
            if t.imageGeneration == layers.imageGeneration { continue }
            t.images = images.map { page in
                page.map { (tex, _) in
                    Self.makeBindGroup(device, bindLayout, globals, atlas, tex, t.projection)
                }
            }
            t.glyphs = atlasPages.map { (tex, _) in
                Self.makeBindGroup(device, bindLayout, globals, tex, tex, t.projection)
            }
            t.imageGeneration = layers.imageGeneration
        }
    }

    func positionLayerSurfaces(_ queue: MetalQueue) {
        #if !os(WASI)
        guard let sr = surfaces else { return }
        for idx in 0..<sr.len() {
            let before = sr.beforeInstance(idx)
            var foundLayer: Int? = nil
            for pIdx in layers.plan.indices.reversed() {
                if before > layers.plan[pIdx].begin && before <= layers.plan[pIdx].end {
                    foundLayer = pIdx
                    break
                }
            }
            let bounds: [Float]
            if let tIdx = findLayerTarget(foundLayer) {
                bounds = layers.plan[tIdx].bounds
            } else {
                bounds = [0.0, 0.0, Float(layers.viewport.0), Float(layers.viewport.1)]
            }
            if bounds[2] > 0.0 && bounds[3] > 0.0 {
                sr.target(queue, idx, bounds)
            }
        }
        #else
        _ = queue
        #endif
    }

    public func encodeLayers(_ encoder: MetalCommandEncoder) {
        encodeLayersTimed(encoder, nil) { _, _ in }
    }

    public func encodeLayersWith(_ encoder: MetalCommandEncoder, _ hook: @escaping EffectHook) {
        encodeLayersTimed(encoder, nil) { phase, site in
            if case .draw(let pass) = phase {
                hook(pass, site)
            }
        }
    }

    public func encodeLayersWithBackdrop(_ encoder: MetalCommandEncoder, _ hook: EffectBackdropHook) {
        encodeLayersTimed(encoder, nil, hook)
    }

    func targetFrame(_ target: Int?) -> ([Float], [UInt32]) {
        if let idx = target {
            let b = layers.plan[idx].bounds
            return ([b[0], b[1]], [UInt32(b[2]), UInt32(b[3])])
        }
        return ([0.0, 0.0], [layers.viewport.0, layers.viewport.1])
    }

    func encodeLayersTimed(
        _ encoder: MetalCommandEncoder,
        _ timestamps: MetalPassTimestampWrites?,
        _ hook: EffectBackdropHook
    ) {
        flushUploads(encoder)
        var first = true
        for index in layers.plan.indices.reversed() {
            let l = layers.plan[index]
            if !l.needsRender { continue }
            guard let target = layers.targets[index] else { continue }
            let ts: MetalPassTimestampWrites?
            if first, let t = timestamps {
                ts = MetalPassTimestampWrites(querySet: t.querySet, beginningIndex: t.beginningIndex, endIndex: nil)
            } else {
                ts = nil
            }
            first = false
            let pass = encoder.beginRenderPass(
                label: "isolated group",
                colorAttachment: MetalRenderPassColorAttachment(
                    view: target.view,
                    loadOp: .clear(r: 0, g: 0, b: 0, a: 0),
                    storeOp: .store
                ),
                timestampWrites: ts
            )
            if l.bounds[2] > 0 && l.bounds[3] > 0 {
                pass.setViewport(x: 0, y: 0, width: l.bounds[2], height: l.bounds[3])
            }
            let active = ActivePass.owned(pass, encoder, target.view)
            drawLayerRange(active, LAYER_FORMAT, (l.begin + 1)..<l.end, index, hook)
            active.endIfOwned()
            if let blur = target.blur {
                layers.blur!.encode(encoder, blur, target.view)
            }
        }
    }

    func drawLayerRange(
        _ activePass: ActivePass,
        _ fmt: WGPUTextureFormat,
        _ range: Range<UInt32>,
        _ target: Int?,
        _ hook: EffectBackdropHook
    ) {
        var cursor = range.lowerBound
        for (index, l) in layers.plan.enumerated() {
            if l.begin < cursor || l.begin >= range.upperBound { continue }
            precondition(l.end < range.upperBound, "draw_range must not split a layer scope")
            drawPlain(activePass, fmt, cursor..<l.begin, target, true, hook)
            if let t = layers.targets[index] {
                let pipe: MetalRenderPipeline
                if layerBlend(target) == .plusLighter {
                    pipe = layers.additive!.1
                } else {
                    guard let found = layers.pipelines.first(where: { $0.0 == fmt })?.1 else {
                        fatalError("Renderer.addFormat first")
                    }
                    pipe = found
                }
                activePass.pass.setPipeline(pipe)
                if let group = springsState?.group {
                    activePass.pass.setBindGroup(1, group)
                }
                activePass.pass.setBindGroup(0, t.composite)
                activePass.pass.setVertexBuffer(0, t.quad)
                activePass.pass.draw(vertices: 0..<4, instances: 0..<1)
            } else if l.opacity == 1.0 {
                if l.clip != NO_CLIP {
                    let (origin, size) = targetFrame(target)
                    func edge(_ v: Float, _ o: Float, _ maxVal: UInt32) -> UInt32 {
                        UInt32(min(max(v - o, 0.0), Float(maxVal)))
                    }
                    let x0 = edge(l.clip[0].rounded(.down), origin[0], size[0])
                    let y0 = edge(l.clip[1].rounded(.down), origin[1], size[1])
                    let x1 = edge(l.clip[2].rounded(.up), origin[0], size[0])
                    let y1 = edge(l.clip[3].rounded(.up), origin[1], size[1])
                    if x1 > x0 && y1 > y0 {
                        let outer = activePass.scissor
                        activePass.setScissor([x0, y0, x1 - x0, y1 - y0], size)
                        drawLayerRange(activePass, fmt, (l.begin + 1)..<l.end, target, hook)
                        activePass.setScissor(outer, size)
                    }
                } else {
                    drawLayerRange(activePass, fmt, (l.begin + 1)..<l.end, target, hook)
                }
            }
            cursor = l.end + 1
        }
        let includeEnd = range.upperBound == count || layers.plan.contains(where: { $0.end == range.upperBound })
        drawPlain(activePass, fmt, cursor..<range.upperBound, target, includeEnd, hook)
    }

    func validateLayerRange(_ range: Range<UInt32>) {
        for l in layers.plan {
            let splitStart = l.begin < range.lowerBound && range.lowerBound <= l.end
            let splitEnd = l.begin < range.upperBound && range.upperBound <= l.end
            precondition(!splitStart && !splitEnd, "draw_range must not split a layer scope")
        }
    }

    private func drawPlain(
        _ activePass: ActivePass,
        _ fmt: WGPUTextureFormat,
        _ range: Range<UInt32>,
        _ target: Int?,
        _ includeEnd: Bool,
        _ hook: EffectBackdropHook
    ) {
        var cursor = range.lowerBound
        #if !os(WASI)
        if let sr = surfaces {
            for index in 0..<sr.len() {
                let before = sr.beforeInstance(index)
                if before < range.lowerBound || before > range.upperBound || (before == range.upperBound && !includeEnd) {
                    continue
                }
                drawWithEffects(activePass, fmt, cursor..<before, target, hook)
                sr.drawBlended(activePass.pass, index, fmt, layerBlend(target))
                cursor = before
            }
        }
        #endif
        drawWithEffects(activePass, fmt, cursor..<range.upperBound, target, hook)
    }
}
