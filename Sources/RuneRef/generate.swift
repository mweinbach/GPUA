// Ported from: crates/rune-ref/src/generate.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! One bounded decoder shared by proptest, corpus generation and CLI replay.
//! Each 32-byte record shrinks independently; deleting records deletes primitives.

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

/// Namespace mirroring `rune_ref::generate::*`.
public enum generate {
    public static func scene(_ records: [[UInt8]]) -> Scene {
        var atlasData = [UInt8]()
        atlasData.reserveCapacity(1024)
        for n in 0..<1024 {
            atlasData.append(UInt8((n * 73 + (n / 32) * 19) % 256))
        }
        var out = Scene(
            width: 64,
            height: 64,
            clear: [0.025, 0.04, 0.06, 1.0],
            primitives: [],
            atlas: Atlas(width: 32, height: 32, data: atlasData)
        )
        for (index, b) in records.prefix(32).enumerated() {
            precondition(b.count == 32, "generate.scene expects 32-byte records")
            let a = Float(b[9]) / 255.0
            func color(_ start: Int) -> [Float] {
                [
                    Float(b[start]) / 255.0 * a,
                    Float(b[start + 1]) / 255.0 * a,
                    Float(b[start + 2]) / 255.0 * a,
                    a,
                ]
            }
            let kindInt = UInt32(b[0] % 5)
            let kind = Float(kindInt)
            var p = Primitive(
                node: UInt32(index + 1),
                source: "generated/\(index)",
                rect: [
                    Float(b[1]) / 4.0 - 8.0,
                    Float(b[2]) / 4.0 - 8.0,
                    1.0 + Float(b[3] % 128) / 4.0,
                    1.0 + Float(b[4] % 128) / 4.0,
                ],
                radii: (0..<4).map { Float(b[20 + $0]) / 8.0 },
                fill: color(6),
                border: color(10),
                params: [
                    Float(b[13]) / 32.0,
                    kind,
                    Float(b[14]) / 32.0,
                    0.7 + Float(b[15]) / 255.0,
                ],
                uv: [0.0, 0.0, 0.0, 0.0],
                clip: NO_CLIP,
                fade: [0.0, 0.0, 0.0, 0.0],
                fadeOrigin: nil,
                turn: nil
            )
            if (b[16] & 1) != 0 {
                p.clip = [
                    Float(b[17]) / 8.0,
                    Float(b[18]) / 8.0,
                    32.0 + Float(b[19]) / 8.0,
                    32.0 + Float(b[24]) / 8.0,
                ]
                p.fade = (0..<4).map { Float(b[25 + $0] % 32) / 4.0 }
            }
            switch kindInt {
            case 1:
                let r0 = p.radii[0]
                p.radii = [r0, r0, r0, r0]
            case 2:
                p.params[0] = 0.0
                p.uv = [1.0, 1.0, 0.0, 0.0]
                p.rect[2] = 1.0 + Float(b[3] % 24)
                p.rect[3] = 1.0 + Float(b[4] % 24)
                if (b[16] & 2) != 0 {
                    p.uv[2] = p.rect[2]
                    p.uv[3] = p.rect[3]
                    let scale: Float = 0.5 + Float(b[29] % 8) / 4.0
                    p.rect[2] *= scale
                    p.rect[3] *= scale
                }
            case 3:
                p.uv = [
                    Float(b[30]) / 32.0 - 4.0,
                    Float(b[31]) / 32.0 - 4.0,
                    0.0,
                    0.0,
                ]
            case 4:
                p.uv = color(29)
            default:
                break
            }
            out.primitives.append(p)
        }
        return out
    }

    /// Stable SplitMix64 corpus, independent of proptest's evolving RNG algorithm.
    public static func seeded(_ seed: UInt64, _ count: Int) -> Scene {
        var state = seed
        let n = min(max(count, 0), 32)
        var records: [[UInt8]] = []
        records.reserveCapacity(n)
        for _ in 0..<n {
            var rec = [UInt8]()
            rec.reserveCapacity(32)
            for _ in 0..<32 {
                state = state &+ 0x9e3779b97f4a7c15
                var z = state
                z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
                z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
                rec.append(UInt8(truncatingIfNeeded: z ^ (z >> 31)))
            }
            records.append(rec)
        }
        return scene(records)
    }

    /// `seeded`, with every primitive redrawn as a dashed border ring (kind 10).
    public static func dashed(_ seed: UInt64, _ count: Int) -> Scene {
        var s = seeded(seed, count)
        for idx in s.primitives.indices {
            func b(_ n: Int) -> UInt32 {
                let v = s.primitives[idx].radii[n % 4] * 8.0 + s.primitives[idx].rect[n % 4] * 4.0
                return v <= 0.0 ? 0 : UInt32(v)
            }
            let soft: Float = (b(1) % 4 == 0) ? s.primitives[idx].params[2] : 0.0
            s.primitives[idx].params = [
                0.5 + Float(b(0) % 8) * 0.25,
                10.0,
                soft,
                1.0,
            ]
            s.primitives[idx].uv = [
                1.0 + Float(b(2) % 24) * 0.5,
                1.0 + Float(b(3) % 16) * 0.5,
                Float(b(1) % 32) * 0.75 - 6.0,
                0.0,
            ]
            if b(0) % 3 == 0 {
                s.primitives[idx].border = s.primitives[idx].fill
            }
        }
        return s
    }

    /// `seeded`, with every primitive redrawn as a radial or angled linear gradient (kind 11),
    /// including multi-stop open band edges (`+ 2.0` on `t0` / `t1`).
    public static func radial(_ seed: UInt64, _ count: Int) -> Scene {
        var s = seeded(seed, count)
        var out: [Primitive] = []
        out.reserveCapacity(s.primitives.count * 2)
        let tau: Float = 2.0 * Float.pi
        for var p in s.primitives {
            func b(_ n: Int) -> UInt32 {
                let v = p.radii[n % 4] * 8.0 + p.rect[n % 4] * 4.0
                return v <= 0.0 ? 0 : UInt32(v)
            }
            let t0 = Float(b(0) % 4) * 0.1
            let t1 = min(t0 + 0.35 + Float(b(1) % 6) * 0.1, 1.0)
            let soft: Float = (b(1) % 4 == 0) ? p.params[2] : 0.0
            if b(0) % 4 == 0 {
                let angle = Float(b(2) % 16) * (tau / 16.0)
                let dx = sinf(angle)
                let dy = -cosf(angle)
                let span = max(abs(dx) * p.rect[2] + abs(dy) * p.rect[3], 1.0)
                p.uv = [dx / span, dy / span, 0.0, 0.0]
            } else {
                let cx = (0.2 + Float(b(2) % 7) * 0.1) * p.rect[2]
                let cy = (0.2 + Float(b(3) % 7) * 0.1) * p.rect[3]
                let rx = max(4.0 + Float(b(0) % 24), 1.0)
                let ry: Float = (b(1) % 2 == 0) ? rx : max(4.0 + Float(b(1) % 24), 1.0)
                p.uv = [cx, cy, rx, ry]
            }
            if b(2) % 2 == 0 {
                let tMid: Float = 0.5 * (t0 + t1)
                let mid: [Float] = [
                    0.5 * (p.fill[0] + p.border[0]),
                    0.5 * (p.fill[1] + p.border[1]),
                    0.5 * (p.fill[2] + p.border[2]),
                    0.5 * (p.fill[3] + p.border[3]),
                ]
                var inner = p
                inner.border = mid
                inner.params = [t0, 11.0, soft, tMid + 2.0]
                out.append(inner)
                p.fill = mid
                p.params = [tMid + 2.0, 11.0, soft, t1]
                out.append(p)
            } else {
                p.params = [t0, 11.0, soft, t1]
                out.append(p)
            }
        }
        s.primitives = out
        return s
    }

    public static func translate(_ scene: inout Scene, _ x: Float, _ y: Float) {
        for idx in scene.primitives.indices {
            scene.primitives[idx].rect[0] += x
            scene.primitives[idx].rect[1] += y
            if scene.primitives[idx].clip != NO_CLIP {
                scene.primitives[idx].clip[0] += x
                scene.primitives[idx].clip[2] += x
                scene.primitives[idx].clip[1] += y
                scene.primitives[idx].clip[3] += y
            }
        }
    }
}
