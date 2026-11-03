// Tests ported from: crates/rune-ref/src/shader.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

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
import Testing
@testable import RuneRef

@Suite("RuneRef Shader Tests")
struct RuneRefShaderTests {
    @Test("ring_arc walks the centre line")
    func ringArcWalksTheCentreLine() {
        let cases: [([Float], [Float], Float)] = [
            ([40.0, 20.0], [10.0, 10.0, 10.0, 10.0], 2.0),
            ([30.0, 30.0], [0.0, 6.0, 15.0, 3.0], 1.0),
            ([50.0, 12.0], [6.0, 6.0, 6.0, 6.0], 0.5),
            ([24.0, 18.0], [0.0, 0.0, 0.0, 0.0], 1.5),
        ]
        let fracPi2: Float = Float.pi * 0.5
        let tau: Float = Float.pi * 2.0

        func remEuclid(_ a: Float, _ b: Float) -> Float {
            let r = a.truncatingRemainder(dividingBy: b)
            return r < 0.0 ? r + b : r
        }

        for (size, radii, bw) in cases {
            let h = bw * 0.5
            let minHalf = min(size[0], size[1]) * 0.5
            let rc = radii.map { max(min($0, minHalf) - h, 0.0) }
            let (_, total) = ringArc([size[0] * 0.5, h], size, radii, bw)
            let rcSum = rc.reduce(Float(0.0), +)
            let expected = 2.0 * (size[0] + size[1] - 2.0 * bw) - (2.0 - fracPi2) * rcSum
            #expect(abs(total - expected) < 1e-3, "\(total) vs \(expected)")

            var points: [[Float]] = []
            let steps = 400
            for n in 0..<steps {
                let angle = Float(n) / Float(steps) * tau
                let dir: [Float] = [sinf(angle), -cosf(angle)]
                var lo: Float = 0.0
                var hi: Float = size[0] + size[1]
                for _ in 0..<60 {
                    let mid = (lo + hi) * 0.5
                    let q: [Float] = [dir[0] * mid, dir[1] * mid]
                    if sd(q, [size[0] * 0.5, size[1] * 0.5], radii) + h < 0.0 {
                        lo = mid
                    } else {
                        hi = mid
                    }
                }
                points.append([size[0] * 0.5 + dir[0] * lo, size[1] * 0.5 + dir[1] * lo])
            }

            var trip: Float = 0.0
            for n in 1...steps {
                let a = points[n - 1]
                let b = points[n % steps]
                let dx = b[0] - a[0]
                let dy = b[1] - a[1]
                let chord = (dx * dx + dy * dy).squareRoot()
                let ds = remEuclid(ringArc(b, size, radii, bw).0 - ringArc(a, size, radii, bw).0, total)
                #expect(ds > chord - 1e-3 && ds < chord * 1.5 + 1e-3, "\(size) \(radii) step \(n): \(ds) vs \(chord)")
                trip += ds
            }
            #expect(abs(trip - total) < 1e-2, "\(trip) vs \(total)")
        }
    }

    @Test("dash pattern closes at the seam")
    func dashPatternClosesAtTheSeam() {
        for total: Float in [37.3, 100.0, 251.9, 3.0] {
            for d: [Float] in [[4.0, 3.0, 0.0], [6.0, 2.5, 1.7], [10.0, 10.0, -4.0]] {
                for n in 0..<50 {
                    let s = Float(n) * 0.37
                    #expect(abs(dashCov(s, total, d) - dashCov(s + total, total, d)) < 1e-3)
                    #expect(abs(dashCov(s, total, d) - dashCov(s - total, total, d)) < 1e-3)
                }
            }
        }
        #expect(abs(dashCov(0.0, 100.0, [4.0, 3.0, 0.0]) - 0.5) < 1e-4)
        #expect(dashCov(1.0, 100.0, [4.0, 3.0, 0.0]) == 1.0)
        for n in 0..<50 {
            let s = Float(n) * 1.3
            #expect(abs(dashCov(s, 100.0, [4.0, 3.0, 7.0]) - dashCov(s, 100.0, [4.0, 3.0, 0.0])) < 1e-3)
        }
    }
}
