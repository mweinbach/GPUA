// Ported from: crates/rune-fx/src/sim.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import CWebGPU
import RuneStaging

let simDt: Float = 1.0 / 60.0
let simJacobi: Int = 14
/// Steps per frame while playing; beyond it the sim skips time instead of stalling the frame.
let simMaxSteps: Int = 4
/// A grid that starts (or goes back in time) warms up this long, so its first frame is already burning.
let simWarmup: Float = 1.2
let simSlots: Int = 80
let simSlot: Int = 256

struct SimUniform: Sendable, Equatable {
    var dims: SIMD4<Float>
    var origin: SIMD4<Float>
    var shape: SIMD4<Float>
    var shape2: SIMD4<Float>
    var fire: SIMD4<Float>
    var fire2: SIMD4<Float>

    static let byteSize = 96

    func writeBytes(into out: inout [UInt8], at base: Int) {
        let vecs = [dims, origin, shape, shape2, fire, fire2]
        var cursor = base
        for v in vecs {
            for lane in 0..<4 {
                let bits = v[lane].bitPattern.littleEndian
                out[cursor] = UInt8(truncatingIfNeeded: bits)
                out[cursor + 1] = UInt8(truncatingIfNeeded: bits >> 8)
                out[cursor + 2] = UInt8(truncatingIfNeeded: bits >> 16)
                out[cursor + 3] = UInt8(truncatingIfNeeded: bits >> 24)
                cursor += 4
            }
        }
    }
}

struct SimKey: Sendable, Equatable, Hashable {
    var seed: UInt32
    var style: UInt32
    var nx: UInt32
    var ny: UInt32

    init(_ seed: UInt32, _ style: UInt32, _ nx: UInt32, _ ny: UInt32) {
        self.seed = seed
        self.style = style
        self.nx = nx
        self.ny = ny
    }
}

/// Which fire a grid serves: grids are matched by `(seed, style, size)` and serve one fire per frame.
struct Claim: Sendable, Equatable {
    var key: SimKey
    /// Where the fire's domain was when it last claimed the grid (pt).
    var origin: [Float]
    /// The frame it last claimed the grid.
    var used: UInt64

    /// A grid whose fire wasn't drawn last frame is gone; its fire would start over anyway.
    func alive(_ frame: UInt64) -> Bool {
        used &+ 1 >= frame
    }
}

/// The grid a fire with `key` at `origin` takes this frame: an unclaimed one with the same key,
/// the nearest to where it was, so identical fires each keep their own state. `nil`: make one.
func pick(_ claims: [Claim], _ key: SimKey, _ origin: [Float], _ frame: UInt64) -> Int? {
    var bestIdx: Int?
    var bestDist: Float = .infinity
    for (i, c) in claims.enumerated() where c.key == key && c.used != frame {
        let dx = c.origin[0] - origin[0]
        let dy = c.origin[1] - origin[1]
        let d = dx * dx + dy * dy
        if bestIdx == nil || d < bestDist {
            bestDist = d
            bestIdx = i
        }
    }
    return bestIdx
}

/// Steps to run for a grid last stepped to `prev` (`nil`: never), to reach `target`:
/// `(steps, sim time before the first, start over)`. A hitch runs at most `simMaxSteps` and skips
/// the rest; only a new grid or a jump back in time warms up.
func schedule(_ prev: Float?, _ target: Float, _ frozen: Bool) -> (Int, Float, Bool) {
    if let t = prev {
        if frozen {
            return (0, t, false)
        }
        if target >= t - 1e-4 {
            let due = max(Int(((target - t) / simDt + 1e-3).rounded(.down)), 0)
            let steps = min(due, simMaxSteps)
            return (steps, target - Float(steps) * simDt, false)
        }
    }
    let steps = min(Int((simWarmup / simDt).rounded()), simSlots)
    return (steps, target - Float(steps) * simDt, true)
}

private struct Plan {
    var steps: Int
    var t0: Float
    var reset: Bool
    var u: SimUniform
}

private struct Grid {
    var claim: Claim
    var n: [UInt32]
    var views: [WGPUTextureView]
    var binds: [[WGPUBindGroup]]
    var uniforms: WGPUBuffer
    /// Which state texture holds the latest step.
    var cur: Int
    /// Sim time of `views[cur]`; `nil` until the first step.
    var t: Float?
    var plan: Plan?
    /// Software state for headless tests (mirrors `views[0]`, `views[1]`, and `p0`).
    var cpuState: [[SIMD4<Float>]]
    var cpuPressure: [Float]
}

private let simCurl = 0
private let simForces = 1
private let simDiv = 2
private let simJac = 3
private let simProject = 4
private let simAdvect = 5

// PORT NOTE: Sims owns WebGPU compute pipelines and per-fire grid textures mutated sequentially
// during `prepare` and `simulate`, matching upstream `Sims`.
final class Sims: @unchecked Sendable {
    let device: WGPUDevice
    let pipes: [WGPUComputePipeline]
    let bgl: WGPUBindGroupLayout
    private var grids: [Grid]
    private var frame: UInt64
    private var bytes: [UInt8]

    init(_ device: WGPUDevice) {
        self.device = device
        let cs = WGPUShaderStage_Compute

        var e0 = WGPUBindGroupLayoutEntry()
        e0.binding = 0
        e0.visibility = cs
        e0.buffer.type = WGPUBufferBindingType_Uniform
        e0.buffer.hasDynamicOffset = 1
        e0.buffer.minBindingSize = 0

        func texEntry(_ binding: UInt32) -> WGPUBindGroupLayoutEntry {
            var e = WGPUBindGroupLayoutEntry()
            e.binding = binding
            e.visibility = cs
            e.texture.sampleType = WGPUTextureSampleType_UnfilterableFloat
            e.texture.viewDimension = WGPUTextureViewDimension_2D
            e.texture.multisampled = 0
            return e
        }

        func storeEntry(_ binding: UInt32, _ format: WGPUTextureFormat) -> WGPUBindGroupLayoutEntry {
            var e = WGPUBindGroupLayoutEntry()
            e.binding = binding
            e.visibility = cs
            e.storageTexture.access = WGPUStorageTextureAccess_WriteOnly
            e.storageTexture.format = format
            e.storageTexture.viewDimension = WGPUTextureViewDimension_2D
            return e
        }

        let bgl = createFXBindGroupLayout(device, "fx firesim", [
            e0,
            texEntry(1),
            storeEntry(3, WGPUTextureFormat_RGBA16Float),
            texEntry(4),
            texEntry(5),
            storeEntry(6, WGPUTextureFormat_R32Float),
        ])
        let layout = createFXPipelineLayout(device, "fx firesim", [bgl])
        let module = createFXShaderModule(device, "fx firesim", loadFXShader("firesim"))
        let pipeNames = ["curl", "forces", "divergence", "jacobi", "project", "advect"]
        self.pipes = pipeNames.map { entry in
            createFXComputePipeline(device, entry, layout, module, entry)
        }
        self.bgl = bgl
        self.grids = []
        self.frame = 0
        self.bytes = []
    }

    static func new(_ device: WGPUDevice) -> Sims {
        Sims(device)
    }

    func beginFrame() {
        frame &+= 1
        let f = frame
        grids.removeAll { !$0.claim.alive(f) }
        for idx in grids.indices {
            grids[idx].plan = nil
        }
    }

    /// Find or make the grid for a fire layer covering `domain` (pt) and plan this frame's steps.
    /// Call once per fire per frame, after `beginFrame`.
    func plan(
        _ device: WGPUDevice,
        _ layer: FxLayer,
        _ p: FireParams,
        _ domain: Rect,
        _ frozen: Bool
    ) -> (Int, [Float]) {
        let area = max(domain.w * domain.h, 1.0)
        let cell = min(max((area / 16_000.0).squareRoot(), 1.0), 3.0)
        let nx = max(UInt32((domain.w / cell).rounded(.up)), 8)
        let ny = max(UInt32((domain.h / cell).rounded(.up)), 8)
        let n = [nx, ny]
        let style = p.style.rawValue
        let key = SimKey(layer.seed, style, nx, ny)
        let origin = [domain.x, domain.y]
        let claim = Claim(key: key, origin: origin, used: frame)

        let idx: Int
        if let found = pick(grids.map(\.claim), key, origin, frame) {
            idx = found
        } else {
            grids.append(makeGrid(device, n, claim))
            idx = grids.count - 1
        }

        grids[idx].claim = claim
        let (steps, t0, reset) = schedule(grids[idx].t, layer.time, frozen)
        let s = layer.shape
        let r = s.rect
        let speed = max(p.speed / 1.5, 0.05)
        let rise = min(max(p.height * 2.2, 20.0), 140.0) * speed.squareRoot()
        let cooling = 1.15 * rise / max(p.height, 4.0)
        let u = SimUniform(
            dims: SIMD4<Float>(Float(nx), Float(ny), cell, simDt),
            origin: SIMD4<Float>(domain.x, domain.y, 0.0, 0.0),
            shape: SIMD4<Float>(r.x + r.w * 0.5, r.y + r.h * 0.5, r.w * 0.5, r.h * 0.5),
            shape2: SIMD4<Float>(s.radius, Float(layer.seed % 65_536), rise, max(p.scale, 2.0)),
            fire: SIMD4<Float>(rise * 3.0, cooling, max(p.smoke, 0.0) * 0.6, 0.25 + 0.6 * p.warp),
            fire2: SIMD4<Float>(rise * (0.3 + 1.5 * p.swirl), speed, 1.4, 2.0)
        )
        grids[idx].plan = Plan(steps: steps, t0: t0, reset: reset, u: u)
        return (idx, [Float(nx) * cell, Float(ny) * cell])
    }

    /// The state view a grid's layer should sample this frame (after its planned steps).
    func finalView(_ i: Int) -> WGPUTextureView {
        let g = grids[i]
        let steps = g.plan?.steps ?? 0
        return g.views[g.cur ^ (steps & 1)]
    }

    func pending() -> Bool {
        grids.contains { ($0.plan?.steps ?? 0) > 0 }
    }

    @discardableResult
    func record(
        _ staging: Staging?,
        _ queue: WGPUQueue,
        _ encoder: WGPUCommandEncoder,
        _ timestamps: UnsafePointer<WGPUComputePassTimestampWrites>?
    ) -> Bool {
        if !pending() {
            return false
        }
        let isLive = SyntheticFXGPU.shared.isLiveDevice(device)
        for idx in grids.indices {
            guard let plan = grids[idx].plan, plan.steps > 0 else { continue }
            bytes = [UInt8](repeating: 0, count: plan.steps * simSlot)
            for k in 0..<plan.steps {
                var u = plan.u
                u.origin[2] = plan.t0 + Float(k + 1) * simDt
                u.origin[3] = (plan.reset && k == 0) ? 1.0 : 0.0
                u.writeBytes(into: &bytes, at: k * simSlot)
            }
            if let staging {
                staging.writeBuffer(grids[idx].uniforms, 0, bytes)
            } else if isLive {
                #if os(Linux) || os(Android) || os(WASI)
                bytes.withUnsafeBytes { raw in
                    wgpuQueueWriteBuffer(queue, grids[idx].uniforms, 0, raw.baseAddress, raw.count)
                }
                #endif
            }
        }
        if let staging {
            staging.flush(encoder)
        }

        #if os(Linux) || os(Android) || os(WASI)
        if isLive {
            withFXStringView("fx firesim") { labelView in
                var desc = WGPUComputePassDescriptor()
                desc.label = labelView
                desc.timestampWrites = timestamps
                let pass = wgpuCommandEncoderBeginComputePass(encoder, &desc)!
                for idx in grids.indices {
                    guard let plan = grids[idx].plan, plan.steps > 0 else { continue }
                    let wg0 = (grids[idx].n[0] + 7) / 8
                    let wg1 = (grids[idx].n[1] + 7) / 8
                    for k in 0..<plan.steps {
                        var off = UInt32(k * simSlot)
                        let cur = grids[idx].cur
                        let b = grids[idx].binds[cur]
                        let run: (Int, WGPUBindGroup) -> Void = { pipeIdx, bg in
                            wgpuComputePassEncoderSetPipeline(pass, self.pipes[pipeIdx])
                            withUnsafePointer(to: &off) { offPtr in
                                wgpuComputePassEncoderSetBindGroup(pass, 0, bg, 1, offPtr)
                            }
                            wgpuComputePassEncoderDispatchWorkgroups(pass, wg0, wg1, 1)
                        }
                        run(simCurl, b[0])
                        run(simForces, b[1])
                        run(simDiv, b[2])
                        for j in 0..<simJacobi {
                            run(simJac, b[3 + (j & 1)])
                        }
                        run(simProject, b[5])
                        run(simAdvect, b[6])
                        grids[idx].cur ^= 1
                    }
                    grids[idx].t = plan.t0 + Float(plan.steps) * simDt
                    grids[idx].plan = Plan(steps: 0, t0: plan.t0, reset: plan.reset, u: plan.u)
                }
                wgpuComputePassEncoderEnd(pass)
                wgpuComputePassEncoderRelease(pass)
            }
            return true
        }
        #endif

        _ = timestamps
        for idx in grids.indices {
            guard let plan = grids[idx].plan, plan.steps > 0 else { continue }
            let nx = Int(grids[idx].n[0])
            let ny = Int(grids[idx].n[1])
            var s0 = grids[idx].cpuState[0]
            var s1 = grids[idx].cpuState[1]
            var p0 = grids[idx].cpuPressure
            grids[idx].cpuState = [[], []]
            grids[idx].cpuPressure = []
            var cur = grids[idx].cur
            for k in 0..<plan.steps {
                var u = plan.u
                u.origin[2] = plan.t0 + Float(k + 1) * simDt
                u.origin[3] = (plan.reset && k == 0) ? 1.0 : 0.0
                if cur == 0 {
                    stepHeadlessSimGrid(u: u, nx: nx, ny: ny, sIn: s0, sOut: &s1, p0: &p0)
                    cur = 1
                } else {
                    stepHeadlessSimGrid(u: u, nx: nx, ny: ny, sIn: s1, sOut: &s0, p0: &p0)
                    cur = 0
                }
            }
            grids[idx].cur = cur
            grids[idx].cpuState = [s0, s1]
            grids[idx].cpuPressure = p0
            SyntheticFXGPU.shared.replaceViewMip0(
                grids[idx].views[cur],
                width: nx,
                height: ny,
                pixels: cur == 0 ? s0 : s1
            )
            grids[idx].t = plan.t0 + Float(plan.steps) * simDt
            grids[idx].plan = Plan(steps: 0, t0: plan.t0, reset: plan.reset, u: plan.u)
        }
        return true
    }

    private func makeGrid(_ device: WGPUDevice, _ n: [UInt32], _ claim: Claim) -> Grid {
        let usage = WGPUTextureUsage_StorageBinding | WGPUTextureUsage_TextureBinding
        let texA = createFXTexture(device, "fx sim state a", width: n[0], height: n[1], mipLevels: 1, format: WGPUTextureFormat_RGBA16Float, usage: usage)
        let texB = createFXTexture(device, "fx sim state b", width: n[0], height: n[1], mipLevels: 1, format: WGPUTextureFormat_RGBA16Float, usage: usage)
        let views = [
            createFXTextureView(device, texA),
            createFXTextureView(device, texB),
        ]
        let scalarLabels = ["fx sim curl", "fx sim div", "fx sim p0", "fx sim p1"]
        let rViews: [WGPUTextureView] = scalarLabels.map { label in
            let t = createFXTexture(device, label, width: n[0], height: n[1], mipLevels: 1, format: WGPUTextureFormat_R32Float, usage: usage)
            return createFXTextureView(device, t)
        }
        let (curl, div, p0, p1) = (rViews[0], rViews[1], rViews[2], rViews[3])
        let uniforms = createFXBuffer(
            device,
            "fx sim params",
            UInt64(simSlots * simSlot),
            WGPUBufferUsage_Uniform | WGPUBufferUsage_CopyDst
        )
        let mkBind: (WGPUTextureView, WGPUTextureView, WGPUTextureView, WGPUTextureView, WGPUTextureView) -> WGPUBindGroup = { sIn, sOut, a, b, out in
            createFXBindGroup(device, "fx firesim", self.bgl, [
                (0, .buffer(uniforms, offset: 0, size: UInt64(SimUniform.byteSize))),
                (1, .view(sIn)),
                (3, .view(sOut)),
                (4, .view(a)),
                (5, .view(b)),
                (6, .view(out)),
            ])
        }
        let mkSet: (WGPUTextureView, WGPUTextureView) -> [WGPUBindGroup] = { x, y in
            [
                mkBind(x, y, p1, div, curl),
                mkBind(x, y, curl, div, p1),
                mkBind(y, x, curl, p0, div),
                mkBind(y, x, p0, div, p1),
                mkBind(y, x, p1, div, p0),
                mkBind(y, x, p0, div, curl),
                mkBind(x, y, curl, div, p1),
            ]
        }
        let binds = [mkSet(views[0], views[1]), mkSet(views[1], views[0])]
        let cellCount = Int(n[0] * n[1])
        return Grid(
            claim: claim,
            n: n,
            views: views,
            binds: binds,
            uniforms: uniforms,
            cur: 0,
            t: nil,
            plan: nil,
            cpuState: [
                [SIMD4<Float>](repeating: .zero, count: cellCount),
                [SIMD4<Float>](repeating: .zero, count: cellCount),
            ],
            cpuPressure: [Float](repeating: 0.0, count: cellCount)
        )
    }
}

// MARK: - Headless `firesim.wgsl` Stepper

@inline(__always)
private func simSmoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let denom = e1 - e0
    if abs(denom) < 1e-8 { return x >= e1 ? 1.0 : 0.0 }
    let t = min(max((x - e0) / denom, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)
}

@inline(__always)
private func simHash2(_ cx: Int, _ cy: Int, _ seed: UInt32) -> Float {
    let ux = UInt32(bitPattern: Int32(truncatingIfNeeded: cx))
    let uy = UInt32(bitPattern: Int32(truncatingIfNeeded: cy))
    return Float(cpu.pcg(ux ^ cpu.pcg(uy ^ cpu.pcg(seed))) >> 8) * (1.0 / 16_777_216.0)
}

@inline(__always)
private func simVnoise(_ px: Float, _ py: Float, _ seed: UInt32) -> Float {
    let fx = px.rounded(.down)
    let fy = py.rounded(.down)
    let ix = Int(fx)
    let iy = Int(fy)
    let tx = px - fx
    let ty = py - fy
    let wx = tx * tx * (3.0 - 2.0 * tx)
    let wy = ty * ty * (3.0 - 2.0 * ty)
    let a = simHash2(ix, iy, seed)
    let b = simHash2(ix + 1, iy, seed)
    let c = simHash2(ix, iy + 1, seed)
    let d = simHash2(ix + 1, iy + 1, seed)
    let ab = a + (b - a) * wx
    let cd = c + (d - c) * wx
    return (ab + (cd - ab) * wy) * 2.0 - 1.0
}

@inline(__always)
private func simSdRrect(_ u: SimUniform, _ px: Float, _ py: Float) -> Float {
    let r = min(u.shape2.x, min(u.shape.z, u.shape.w))
    let qx = abs(px - u.shape.x) - u.shape.z + r
    let qy = abs(py - u.shape.y) - u.shape.w + r
    let mx = max(qx, 0.0)
    let my = max(qy, 0.0)
    return (mx * mx + my * my).squareRoot() + min(max(qx, qy), 0.0) - r
}

@inline(__always)
private func simFuelBand(_ u: SimUniform, _ px: Float, _ py: Float) -> Float {
    let h = u.dims.z
    let d = simSdRrect(u, px, py)
    let e = 0.5 * h
    let gx = simSdRrect(u, px + e, py) - simSdRrect(u, px - e, py)
    let gy = simSdRrect(u, px, py + e) - simSdRrect(u, px, py - e)
    let gl = max((gx * gx + gy * gy).squareRoot(), 1e-4)
    let up = min(max(-gy / gl, 0.0), 1.0)
    let depth = u.fire2.w
    return simSmoothstep(-depth - 1.5, -depth + 0.5, d)
        * (1.0 - simSmoothstep(0.0, h + 1.5, d))
        * simSmoothstep(0.35, 0.8, up)
}

@inline(__always)
private func simEmission(_ u: SimUniform, _ x: Float, _ t: Float, _ seed: UInt32) -> Float {
    let sp = max(u.shape2.w * 0.32, 3.5)
    let fs = u.fire2.y
    let slow = simVnoise(x / sp, t * 0.55 * fs, seed) * 0.7
        + simVnoise(x / sp * 2.3 + 5.1, t * 1.1 * fs, seed &+ 1) * 0.3
    let fast = simVnoise(x / sp * 1.7 + 11.0, t * 6.0 * fs, seed &+ 2)
    let r = min(u.shape2.x, min(u.shape.z, u.shape.w))
    let ends = 1.0 - simSmoothstep(u.shape.z - r * 1.6, u.shape.z - r * 0.35, abs(x - u.shape.x))
    return simSmoothstep(-0.1, 0.4, slow + 0.25 * fast) * ends
}

private func stepHeadlessSimGrid(
    u: SimUniform,
    nx: Int,
    ny: Int,
    sIn: [SIMD4<Float>],
    sOut: inout [SIMD4<Float>],
    p0: inout [Float]
) {
    let h = u.dims.z
    let dt = u.dims.w
    let t = u.origin.z
    let reset = u.origin.w > 0.5
    let seed = UInt32(u.shape2.y)
    let count = nx * ny

    @inline(__always)
    func clIdx(_ cx: Int, _ cy: Int) -> Int {
        let x = min(max(cx, 0), nx - 1)
        let y = min(max(cy, 0), ny - 1)
        return y * nx + x
    }

    @inline(__always)
    func pos(_ cx: Int, _ cy: Int) -> (Float, Float) {
        (u.origin.x + (Float(cx) + 0.5) * h, u.origin.y + (Float(cy) + 0.5) * h)
    }

    @inline(__always)
    func solid(_ cx: Int, _ cy: Int) -> Bool {
        let (px, py) = pos(cx, cy)
        return simSdRrect(u, px, py) < -u.fire2.w - 1.0
    }

    // 1. Curl
    var curl = [Float](repeating: 0.0, count: count)
    if !reset {
        for cy in 0..<ny {
            for cx in 0..<nx {
                let w = (sIn[clIdx(cx + 1, cy)].y - sIn[clIdx(cx - 1, cy)].y
                    - sIn[clIdx(cx, cy + 1)].x + sIn[clIdx(cx, cy - 1)].x) / (2.0 * h)
                curl[cy * nx + cx] = w
            }
        }
    }

    // 2. Forces -> forced
    var forced = [SIMD4<Float>](repeating: .zero, count: count)
    for cy in 0..<ny {
        for cx in 0..<nx {
            let idx = cy * nx + cx
            let s = reset ? SIMD4<Float>.zero : sIn[idx]
            var vx = s.x
            var vy = s.y
            var temp = s.z
            var sm = s.w
            let (px, py) = pos(cx, cy)

            vy -= dt * (u.fire.x * temp - u.fire.x * 0.12 * sm)

            if !reset {
                let wl = abs(curl[clIdx(cx - 1, cy)])
                let wr = abs(curl[clIdx(cx + 1, cy)])
                let wu = abs(curl[clIdx(cx, cy - 1)])
                let wd = abs(curl[clIdx(cx, cy + 1)])
                var gx = (wr - wl) / (2.0 * h)
                var gy = (wd - wu) / (2.0 * h)
                let gl = (gx * gx + gy * gy).squareRoot()
                if gl > 1e-4 {
                    gx /= gl
                    gy /= gl
                    let w = curl[idx]
                    let lift = min(max((u.shape.y - u.shape.w - py) / max(u.shape2.z * 0.4, 8.0), 0.15), 1.0)
                    let k = dt * u.fire.w * lift * h
                    vx += k * (gy * w)
                    vy += k * (-gx * w)
                }
            }

            let above = u.shape.y - u.shape.w - py
            let sway = simVnoise(px / 90.0, t * 0.35 * u.fire2.y, seed &+ 9)
                + 0.5 * simVnoise(px / 30.0 + 3.0, py / 40.0 - t * 0.9 * u.fire2.y, seed &+ 10)
            vx += dt * u.fire2.x * sway * min(max(above / 40.0, 0.0), 1.0)

            let band = simFuelBand(u, px, py)
            if band > 0.0 {
                let e = simEmission(u, px, t, seed) * band
                let flicker = 0.95 + 0.25 * simVnoise(px / 3.0, t * 9.0, seed &+ 4)
                temp = max(temp, e * flicker)
                let targetVy = -u.shape2.z * (0.6 + 0.6 * e)
                vy += (targetVy - vy) * (e * 0.6)
            }

            let cool = 1.0 - FoundationCompat.expf(-dt * u.fire.y)
            let lost = temp * cool
            temp -= lost
            sm += lost * u.fire.z * (1.0 - simSmoothstep(0.25, 0.55, temp))
            sm *= FoundationCompat.expf(-dt * u.fire2.z)

            if solid(cx, cy) {
                vx = 0.0
                vy = 0.0
                temp *= 0.5
                sm = 0.0
            }
            vx *= FoundationCompat.expf(-dt * 7.0 * simSmoothstep(0.1, 0.6, temp))
            let edge = min(min(Float(cx), Float(nx - 1 - cx)), Float(cy))
            let fade = simSmoothstep(0.0, 4.0, edge)
            temp *= fade
            sm *= fade
            forced[idx] = quantizeForFormat(SIMD4<Float>(vx, vy, temp, sm), WGPUTextureFormat_RGBA16Float)
        }
    }

    // 3. Divergence
    var div = [Float](repeating: 0.0, count: count)
    for cy in 0..<ny {
        for cx in 0..<nx {
            let l = solid(cx - 1, cy) ? 0.0 : forced[clIdx(cx - 1, cy)].x
            let r = solid(cx + 1, cy) ? 0.0 : forced[clIdx(cx + 1, cy)].x
            let tp = solid(cx, cy - 1) ? 0.0 : forced[clIdx(cx, cy - 1)].y
            let bt = solid(cx, cy + 1) ? 0.0 : forced[clIdx(cx, cy + 1)].y
            let (px, py) = pos(cx, cy)
            let src = simFuelBand(u, px, py) * simEmission(u, px, t, seed) * u.shape2.z * 0.2 / h
            div[cy * nx + cx] = (r - l + bt - tp) / (2.0 * h) - src
        }
    }

    // 4. Jacobi pressure (14 iterations, p0 <-> p1)
    var p1 = [Float](repeating: 0.0, count: count)
    @inline(__always)
    func pn(_ pArr: [Float], _ cx: Int, _ cy: Int, _ centre: Float) -> Float {
        if cy < 0 { return 0.0 }
        if cx < 0 || cx >= nx || cy >= ny || solid(cx, cy) { return centre }
        return pArr[cy * nx + cx]
    }
    for j in 0..<simJacobi {
        if (j & 1) == 0 {
            for cy in 0..<ny {
                for cx in 0..<nx {
                    let idx = cy * nx + cx
                    let pc = p0[idx]
                    let s = pn(p0, cx - 1, cy, pc) + pn(p0, cx + 1, cy, pc)
                        + pn(p0, cx, cy - 1, pc) + pn(p0, cx, cy + 1, pc)
                    p1[idx] = (s - h * h * div[idx]) * 0.25
                }
            }
        } else {
            for cy in 0..<ny {
                for cx in 0..<nx {
                    let idx = cy * nx + cx
                    let pc = p1[idx]
                    let s = pn(p1, cx - 1, cy, pc) + pn(p1, cx + 1, cy, pc)
                        + pn(p1, cx, cy - 1, pc) + pn(p1, cx, cy + 1, pc)
                    p0[idx] = (s - h * h * div[idx]) * 0.25
                }
            }
        }
    }

    // 5. Project -> projected
    var projected = [SIMD4<Float>](repeating: .zero, count: count)
    let vmax = 2.0 * h / dt
    for cy in 0..<ny {
        for cx in 0..<nx {
            let idx = cy * nx + cx
            let s = forced[idx]
            let pc = p0[idx]
            let gx = (pn(p0, cx + 1, cy, pc) - pn(p0, cx - 1, cy, pc)) / (2.0 * h)
            let gy = (pn(p0, cx, cy + 1, pc) - pn(p0, cx, cy - 1, pc)) / (2.0 * h)
            var vx = s.x - gx
            var vy = s.y - gy
            if solid(cx, cy) {
                vx = 0.0
                vy = 0.0
            }
            let vl = (vx * vx + vy * vy).squareRoot()
            if vl > vmax {
                let k = vmax / vl
                vx *= k
                vy *= k
            }
            projected[idx] = quantizeForFormat(SIMD4<Float>(vx, vy, s.z, s.w), WGPUTextureFormat_RGBA16Float)
        }
    }

    // 6. Advect (midpoint monotone cubic) -> sOut
    @inline(__always)
    func crWeights(_ f: Float) -> SIMD4<Float> {
        let f2 = f * f
        let f3 = f2 * f
        return SIMD4<Float>(
            -0.5 * f3 + f2 - 0.5 * f,
            1.5 * f3 - 2.5 * f2 + 1.0,
            -1.5 * f3 + 2.0 * f2 + 0.5 * f,
            0.5 * f3 - 0.5 * f2
        )
    }

    func sampleCubic(_ px: Float, _ py: Float) -> SIMD4<Float> {
        let gx = (px - u.origin.x) / h - 0.5
        let gy = (py - u.origin.y) / h - 0.5
        let fx0 = gx.rounded(.down)
        let fy0 = gy.rounded(.down)
        let ix0 = Int(fx0)
        let iy0 = Int(fy0)
        let wx = crWeights(gx - fx0)
        let wy = crWeights(gy - fy0)
        var acc = SIMD4<Float>.zero
        for oy in 0..<4 {
            var row = SIMD4<Float>.zero
            for ox in 0..<4 {
                row += wx[ox] * projected[clIdx(ix0 + ox - 1, iy0 + oy - 1)]
            }
            acc += wy[oy] * row
        }
        let q0 = projected[clIdx(ix0, iy0)]
        let q1 = projected[clIdx(ix0 + 1, iy0)]
        let q2 = projected[clIdx(ix0, iy0 + 1)]
        let q3 = projected[clIdx(ix0 + 1, iy0 + 1)]
        let lo = pointwiseMin(pointwiseMin(q0, q1), pointwiseMin(q2, q3))
        let hi = pointwiseMax(pointwiseMax(q0, q1), pointwiseMax(q2, q3))
        return pointwiseMin(pointwiseMax(acc, lo), hi)
    }

    for cy in 0..<ny {
        for cx in 0..<nx {
            let idx = cy * nx + cx
            let (px, py) = pos(cx, cy)
            let v = projected[idx]
            let midX = px - 0.5 * dt * v.x
            let midY = py - 0.5 * dt * v.y
            let vm = sampleCubic(midX, midY)
            let r = sampleCubic(px - dt * vm.x, py - dt * vm.y)
            sOut[idx] = quantizeForFormat(
                SIMD4<Float>(r.x, r.y, max(r.z, 0.0), max(r.w, 0.0)),
                WGPUTextureFormat_RGBA16Float
            )
        }
    }
}
