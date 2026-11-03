// Ported from: crates/rune/src/gpu/springs.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Opt-in retained translation/opacity tracks. Layout, glyph placement, presence and app events
//! remain CPU-owned. Callers sample on demand for hit testing and stop ticks at `settleAt()`.

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
import RuneMotion

public enum springs {
    /// Embedded WGSL source matching `gpu/springs.wgsl`.
    public static let SHADER: String = """
    // Coefficients are prepared once at retarget using rune-motion's damping branches.
    struct SpringTrack {
        abcd: vec4<f32>,
        rates: vec2<f32>,
        goal: f32,
        kind: u32,
        start: vec2<f32>,
        duration: f32,
        pad: f32,
    };

    fn spring_exp(x: f32) -> f32 {
        if (x < -87.0) { return 0.0; }
        let xc = clamp(x, -87.0, 88.0);
        let k = round(xc * 1.4426950408889634);
        let r = fma(-k, 0.0000014286068, fma(-k, 0.69314575, xc));
        let r2 = r * r;
        let a = 1.0 + r;
        let b = fma(r, 1.0 / 6.0, 0.5);
        let c = fma(r, 1.0 / 120.0, 1.0 / 24.0);
        let p = fma(r2, fma(r2, fma(r2, 1.0 / 720.0, c), b), a);
        return p * bitcast<f32>(u32(i32(k) + 127) << 23u);
    }

    fn spring_sample(s: SpringTrack, time: vec2<f32>) -> vec2<f32> {
        let whole = f32(i32(time.x) - i32(s.start.x));
        let t = max(whole + (time.y - s.start.y), 0.0);
        if (s.kind == 0u || t >= s.duration) { return vec2<f32>(s.goal, 0.0); }
        let c = s.abcd;
        if (s.kind == 1u) {
            let e = exp(-s.rates.x * t);
            let co = cos(s.rates.y * t);
            let si = sin(s.rates.y * t);
            return vec2<f32>(s.goal + e * (c.x * co + c.y * si), e * (c.z * co + c.w * si));
        }
        if (s.kind == 2u) {
            let e = exp(-s.rates.x * t);
            return vec2<f32>(s.goal + (c.x + c.y * t) * e, (c.z + c.w * t) * e);
        }
        let e1 = spring_exp(c.z * t);
        let e2 = spring_exp(c.w * t);
        return vec2<f32>(s.goal + (c.x * e1 + c.y * e2), c.x * c.z * e1 + c.y * c.w * e2);
    }

    struct SpringNode { x: SpringTrack, y: SpringTrack, opacity: SpringTrack };
    @group(1) @binding(0) var<storage, read> spring_nodes: array<SpringNode>;
    @group(1) @binding(1) var<storage, read> spring_ids: array<u32>;

    @vertex
    fn vs_springs(input: In, @builtin(instance_index) instance: u32) -> Out {
        let node = spring_nodes[spring_ids[instance]];
        let time = g.pad;
        let offset = vec2<f32>(spring_sample(node.x, time).x, spring_sample(node.y, time).x);
        let alpha = clamp(spring_sample(node.opacity, time).x, 0.0, 1.0);
        var i = input;
        i.rect = vec4<f32>(i.rect.xy + offset, i.rect.zw);
        i.fill *= alpha;
        i.border *= alpha;
        if (i.params.y > 3.5 && i.params.y < 4.5) { i.uv *= alpha; }
        if (i.params.y > 4.5 && i.params.y < 6.5) {
            i.radii += vec4<f32>(offset, offset);
            if (i.params.y > 5.5) { i.uv = vec4<f32>(i.uv.xy + offset, i.uv.zw); }
        }
        return base_vs(i);
    }
    """

    /// Splits a double-precision timestamp into `[wholeSeconds, fractionalSeconds]` in `[0, 16_777_216)`.
    public static func splitTime(_ time: Double) -> [Float] {
        precondition(time.isFinite && time >= 0.0 && time < 16_777_216.0, "spring time out of split range")
        let hi = Float(time.rounded(.down))
        return [hi, Float(time - Double(hi))]
    }

    /// Exact CPU counterpart of `spring_exp` in `springs.wgsl`.
    @inline(__always)
    static func springExp(_ x: Float) -> Float {
        if x < -87.0 { return 0.0 }
        let xc = min(max(x, -87.0), 88.0)
        let k = (xc * 1.4426950408889634).rounded(.toNearestOrEven)
        let r1 = xc.addingProduct(-k, 0.69314575)
        let r = r1.addingProduct(-k, 0.0000014286068)
        let r2 = r * r
        let a: Float = 1.0 + r
        let b: Float = (0.5 as Float).addingProduct(r, 1.0 / 6.0)
        let c: Float = (1.0 / 24.0 as Float).addingProduct(r, 1.0 / 120.0)
        let inner1 = c.addingProduct(r2, 1.0 / 720.0)
        let inner2 = b.addingProduct(r2, inner1)
        let p = a.addingProduct(r2, inner2)
        let scaleBits = UInt32(bitPattern: Int32(k) + 127) << 23
        return p * Float(bitPattern: scaleBits)
    }

    /// GPU ABI, 48 bytes (12 × 32-bit lanes). Construction validates finite inputs.
    public struct Track: Sendable, Equatable {
        public static let byteSize: Int = 48

        private var abcd0: Float
        private var abcd1: Float
        private var abcd2: Float
        private var abcd3: Float
        private var rate0: Float
        private var rate1: Float
        private var target: Float
        private var kind: UInt32
        private var start0: Float
        private var start1: Float
        private var duration: Float
        private var pad: Float

        public init(
            _ spring: Spring,
            _ time: Double,
            _ from: Float,
            _ target: Float,
            _ velocity: Float,
            _ epsilon: Float
        ) {
            precondition(from.isFinite && target.isFinite && velocity.isFinite, "Track inputs must be finite")
            let dur = spring.settlingDurationFrom(from, velocity, target, epsilon)
            let a = from - target
            let w = spring.omega()
            let z = spring.zeta()

            let k: UInt32
            let c: (Float, Float, Float, Float)
            let r: (Float, Float)
            if a == 0.0 && velocity == 0.0 {
                k = 0
                c = (0.0, 0.0, 0.0, 0.0)
                r = (0.0, 0.0)
            } else if abs(z - 1.0) < 1e-4 {
                let b = velocity + w * a
                k = 2
                c = (a, b, b - w * a, -w * b)
                r = (w, 0.0)
            } else if z < 1.0 {
                let sigma = z * w
                let wd = w * (1.0 - z * z).squareRoot()
                let b = (velocity + sigma * a) / wd
                k = 1
                c = (a, b, b * wd - sigma * a, -a * wd - sigma * b)
                r = (sigma, wd)
            } else {
                let root = (z * z - 1.0).squareRoot()
                let r1 = -w * (z - root)
                let r2 = -w * (z + root)
                let c1 = (velocity - r2 * a) / (r1 - r2)
                k = 3
                c = (c1, a - c1, r1, r2)
                r = (0.0, 0.0)
            }
            precondition(
                c.0.isFinite && c.1.isFinite && c.2.isFinite && c.3.isFinite && r.0.isFinite && r.1.isFinite,
                "Track coefficients must be finite"
            )
            let st = splitTime(time)
            self.abcd0 = c.0
            self.abcd1 = c.1
            self.abcd2 = c.2
            self.abcd3 = c.3
            self.rate0 = r.0
            self.rate1 = r.1
            self.target = target
            self.kind = k
            self.start0 = st[0]
            self.start1 = st[1]
            self.duration = dur
            self.pad = 0.0
        }

        public static func new(
            _ spring: Spring,
            _ time: Double,
            _ from: Float,
            _ target: Float,
            _ velocity: Float,
            _ epsilon: Float
        ) -> Track {
            Track(spring, time, from, target, velocity, epsilon)
        }

        public static func constant(_ value: Float) -> Track {
            Track(.default, 0.0, value, value, 0.0, 0.001)
        }

        public func settleAt() -> Double {
            Double(start0) + Double(start1) + Double(duration)
        }

        /// Evaluates `(position, velocity)` at split timestamp `[timeHi, timeLo]`, matching `spring_sample` in `springs.wgsl`.
        public func sample(_ time: [Float]) -> (Float, Float) {
            let whole = Float(Int32(time[0]) &- Int32(start0))
            let t = max(whole + (time[1] - start1), 0.0)
            if kind == 0 || t >= duration {
                return (target, 0.0)
            }
            if kind == 1 {
                let e = expf(-rate0 * t)
                let co = cosf(rate1 * t)
                let si = sinf(rate1 * t)
                return (target + e * (abcd0 * co + abcd1 * si), e * (abcd2 * co + abcd3 * si))
            }
            if kind == 2 {
                let e = expf(-rate0 * t)
                return (target + (abcd0 + abcd1 * t) * e, (abcd2 + abcd3 * t) * e)
            }
            let e1 = springExp(abcd2 * t)
            let e2 = springExp(abcd3 * t)
            return (target + (abcd0 * e1 + abcd1 * e2), abcd0 * abcd2 * e1 + abcd1 * abcd3 * e2)
        }

        public func writeBytes(into out: inout [UInt8]) {
            func appendF32(_ v: Float) {
                var le = v.bitPattern.littleEndian
                withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
            }
            func appendU32(_ v: UInt32) {
                var le = v.littleEndian
                withUnsafeBytes(of: &le) { out.append(contentsOf: $0) }
            }
            appendF32(abcd0)
            appendF32(abcd1)
            appendF32(abcd2)
            appendF32(abcd3)
            appendF32(rate0)
            appendF32(rate1)
            appendF32(target)
            appendU32(kind)
            appendF32(start0)
            appendF32(start1)
            appendF32(duration)
            appendF32(pad)
        }
    }

    /// GPU ABI, 144 bytes (3 × `Track`).
    public struct Node: Sendable, Equatable {
        public static let byteSize: Int = 144

        public var x: Track
        public var y: Track
        public var opacity: Track

        public init(x: Track, y: Track, opacity: Track) {
            self.x = x
            self.y = y
            self.opacity = opacity
        }

        public func settleAt() -> Double {
            max(x.settleAt(), max(y.settleAt(), opacity.settleAt()))
        }

        public func sample(_ time: [Float]) -> (offset: (Float, Float), alpha: Float) {
            let dx = x.sample(time).0
            let dy = y.sample(time).0
            let a = min(max(opacity.sample(time).0, 0.0), 1.0)
            return ((dx, dy), a)
        }

        public func toBytes() -> [UInt8] {
            var out: [UInt8] = []
            out.reserveCapacity(Self.byteSize)
            x.writeBytes(into: &out)
            y.writeBytes(into: &out)
            opacity.writeBytes(into: &out)
            return out
        }
    }

    /// Retained spring node storage and instance-to-node index mapping.
    struct Bindings: Sendable {
        var nodes: [Node]
        var ids: [UInt32]
        var deadlines: [Double]
        var settleAt: Double
        var nodesBuffer: MetalBuffer?
        var idsBuffer: MetalBuffer?
        var group: MetalBindGroup?

        static func layout(_ device: MetalDevice) -> MetalBindGroupLayout {
            device.createBindGroupLayout(
                label: "springs",
                entries: [
                    MetalBindGroupLayoutEntry(
                        binding: 0,
                        visibility: .vertex,
                        ty: .storageBuffer(readOnly: true, hasDynamicOffset: false)
                    ),
                    MetalBindGroupLayoutEntry(
                        binding: 1,
                        visibility: .vertex,
                        ty: .storageBuffer(readOnly: true, hasDynamicOffset: false)
                    ),
                ]
            )
        }

        init(nodes: [Node], ids: [UInt32]) {
            precondition(!nodes.isEmpty && !ids.isEmpty, "Spring Bindings require non-empty nodes and ids")
            precondition(ids.allSatisfy { Int($0) < nodes.count }, "Spring node id out of bounds")
            self.nodes = nodes
            self.ids = ids
            self.deadlines = nodes.map { $0.settleAt() }
            self.settleAt = self.deadlines.reduce(0.0, max)
            self.nodesBuffer = nil
            self.idsBuffer = nil
            self.group = nil
        }

        init(device: MetalDevice, layout: MetalBindGroupLayout, nodes: [Node], ids: [UInt32]) {
            precondition(!nodes.isEmpty && !ids.isEmpty, "Spring Bindings require non-empty nodes and ids")
            precondition(ids.allSatisfy { Int($0) < nodes.count }, "Spring node id out of bounds")
            self.nodes = nodes
            self.ids = ids
            self.deadlines = nodes.map { $0.settleAt() }
            self.settleAt = self.deadlines.reduce(0.0, max)

            var nodeBytes: [UInt8] = []
            nodeBytes.reserveCapacity(nodes.count * Node.byteSize)
            for n in nodes {
                n.x.writeBytes(into: &nodeBytes)
                n.y.writeBytes(into: &nodeBytes)
                n.opacity.writeBytes(into: &nodeBytes)
            }
            var idBytes = [UInt8](repeating: 0, count: ids.count * 4)
            for (idx, v) in ids.enumerated() {
                let le = v.littleEndian
                idBytes[idx * 4 + 0] = UInt8(truncatingIfNeeded: le)
                idBytes[idx * 4 + 1] = UInt8(truncatingIfNeeded: le >> 8)
                idBytes[idx * 4 + 2] = UInt8(truncatingIfNeeded: le >> 16)
                idBytes[idx * 4 + 3] = UInt8(truncatingIfNeeded: le >> 24)
            }
            let nb = device.createBuffer(label: "spring nodes", size: nodeBytes.count, contents: nodeBytes)
            let ib = device.createBuffer(label: "spring ids", size: idBytes.count, contents: idBytes)
            let bg = device.createBindGroup(
                label: "springs",
                layout: layout,
                entries: [
                    MetalBindGroupEntry(binding: 0, resource: .buffer(buffer: nb, offset: 0, size: nil)),
                    MetalBindGroupEntry(binding: 1, resource: .buffer(buffer: ib, offset: 0, size: nil)),
                ]
            )
            self.nodesBuffer = nb
            self.idsBuffer = ib
            self.group = bg
        }

        mutating func writeNode(_ index: Int, _ node: Node) {
            precondition(index >= 0 && index < nodes.count, "Spring node index out of bounds")
            nodes[index] = node
            let d = node.settleAt()
            deadlines[index] = d
            if d >= settleAt {
                settleAt = d
            } else {
                settleAt = deadlines.reduce(0.0, max)
            }
        }

        func apply(to instance: Instance, instanceIndex: Int, time: [Float]) -> Instance {
            guard instanceIndex >= 0 && instanceIndex < ids.count else { return instance }
            let nodeIdx = Int(ids[instanceIndex])
            guard nodeIdx >= 0 && nodeIdx < nodes.count else { return instance }
            let ((ox, oy), alpha) = nodes[nodeIdx].sample(time)
            var i = instance
            i.rect = [i.rect[0] + ox, i.rect[1] + oy, i.rect[2], i.rect[3]]
            i.fill = [i.fill[0] * alpha, i.fill[1] * alpha, i.fill[2] * alpha, i.fill[3] * alpha]
            i.border = [i.border[0] * alpha, i.border[1] * alpha, i.border[2] * alpha, i.border[3] * alpha]
            let kind = i.params[1]
            if kind > 3.5 && kind < 4.5 {
                i.uv = [i.uv[0] * alpha, i.uv[1] * alpha, i.uv[2] * alpha, i.uv[3] * alpha]
            }
            if kind > 4.5 && kind < 6.5 {
                i.radii = [i.radii[0] + ox, i.radii[1] + oy, i.radii[2] + ox, i.radii[3] + oy]
                if kind > 5.5 {
                    i.uv = [i.uv[0] + ox, i.uv[1] + oy, i.uv[2], i.uv[3]]
                }
            }
            return i
        }
    }
}
