// Tests ported from: crates/rune-motion/src/layer.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import RuneMotion

@inline(never)
private func blackBox<T>(_ value: T) -> T {
    value
}

@Test(.disabled("Upstream #[ignore] benchmark"))
func bench_layer_kinds() {
    let n = 100_000
    for (name, s) in [("under", Spring.new(3.0, 0.3)), ("critical", Spring.new(3.0, 0.0))] {
        let layers: [Layer] = (0..<n).map { i in
            Layer.spring(s, 0.0, -100.0 - Float(i % 13), 0.0, Eps(pos: 1e-3, vel: 1e-2))
        }
        var out = Array(repeating: Float(0.0), count: n)
        let t0 = Date()
        for f in 0..<120 {
            let now = Double(f) / 120.0
            for i in 0..<n {
                let (a, b) = layers[i].sample(now)
                out[i] = a + b
            }
            _ = blackBox(out)
        }
        let elapsedNs = Date().timeIntervalSince(t0) * 1e9
        print("\(name): \(elapsedNs / Double(120 * n)) ns/lane")
    }
    let xs: [Float] = (0..<n).map { i in -Float(i) * 1e-4 }
    var t0 = Date()
    var acc: Float = 0.0
    for _ in 0..<120 {
        for x in xs {
            acc += math.exp(blackBox(x))
        }
    }
    _ = blackBox(acc)
    print("exp: \(Date().timeIntervalSince(t0) * 1e9 / Double(120 * n)) ns")
    t0 = Date()
    for _ in 0..<120 {
        for x in xs {
            let (s, c) = math.sinCos(blackBox(x * 100.0))
            acc += s + c
        }
    }
    _ = blackBox(acc)
    print("sin_cos: \(Date().timeIntervalSince(t0) * 1e9 / Double(120 * n)) ns")
}
