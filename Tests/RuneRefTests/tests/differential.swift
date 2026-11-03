// Tests ported from: crates/rune-ref/tests/differential.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import Testing
@testable import Rune
@testable import RuneRef

private struct DiffFailure: Error, CustomStringConvertible {
    let description: String
}

private let BUDGET: [UInt8] = [2, 2, 2, 2, 2]

private func check(_ gpu: GpuRenderer, _ scene: Scene, _ tolerance: UInt8) -> Result<UInt8, DiffFailure> {
    var cpu = Frame.new(scene.width, scene.height, true)
    cpu.render(scene)
    let actual = gpu.render(scene)
    let diff = compare(scene, cpu, actual, tolerance)
    if diff.outlierPixels > 0 {
        if let data = try? JSONEncoder().encode(diff), let str = String(data: data, encoding: .utf8) {
            return .failure(DiffFailure(description: str))
        }
        return .failure(DiffFailure(description: "\(diff)"))
    }
    return .success(diff.maxChannel)
}

@Suite("RuneRef Differential CPU vs GPU Tests", .serialized)
struct RuneRefDifferentialTests {
    @Test("CPU vs GPU corpus across 128 seeded scenes and 16 text runs")
    func cpuGpuCorpus() {
        let gpu = GpuRenderer.default()
        var maxima: [UInt8] = [0, 0, 0, 0, 0, 0]
        for seed: UInt64 in 0..<128 {
            let scene = generate.seeded(seed, 8)
            for primitive in scene.primitives {
                var single = scene
                single.primitives = [primitive]
                let kind = Int(primitive.params[1])
                switch check(gpu, single, BUDGET[kind]) {
                case .success(let m):
                    maxima[kind] = max(maxima[kind], m)
                case .failure(let err):
                    Issue.record("seed-\(seed)-kind-\(kind): \(err)")
                    return
                }
            }
            switch check(gpu, scene, 2) {
            case .success(let m):
                maxima[5] = max(maxima[5], m)
            case .failure(let err):
                Issue.record("seed-\(seed)-composite: \(err)")
                return
            }
        }
        for seed: UInt64 in 0..<16 {
            var scene = generate.seeded(seed, 4)
            textRun(&scene, seed)
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("text-\(seed): \(err)")
                return
            }
        }
    }

    @Test("CPU vs GPU property cases across 128 arbitrary byte-record scenes")
    func cpuGpuProptest() {
        let gpu = GpuRenderer.default()
        var rngState: UInt64 = 0xfeed_face_cafe_babe
        func nextByte() -> UInt8 {
            rngState = rngState &+ 0x9e3779b97f4a7c15
            var z = rngState
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return UInt8(truncatingIfNeeded: z ^ (z >> 31))
        }
        for idx in 0..<128 {
            let count = 1 + (idx % 8)
            let records: [[UInt8]] = (0..<count).map { _ in
                (0..<32).map { _ in nextByte() }
            }
            let scene = generate.scene(records)
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("proptest-\(idx): \(err)")
                return
            }
        }
    }

    @Test("saved regression scenes match CPU oracle within 2 LSB")
    func savedRegressions() throws {
        let gpu = GpuRenderer.default()
        let baseAtlas = generate.scene([]).atlas
        let atlasJson = try String(data: JSONEncoder().encode(baseAtlas), encoding: .utf8)!
        // Exact `crates/rune-ref/regressions/glyph-texel-boundary.json` payload decoded via Codable.
        let regressionJson = """
        {
          "width": 64,
          "height": 64,
          "clear": [0.025, 0.04, 0.06, 1.0],
          "primitives": [
            {
              "node": 4,
              "source": "generated/3",
              "rect": [10.5, 34.25, 14.0, 21.0],
              "radii": [25.25, 24.625, 14.625, 8.125],
              "fill": [0.29413307, 0.018131489, 0.2034756, 0.5137255],
              "border": [0.3062207, 0.45933107, 0.2034756, 0.5137255],
              "params": [0.0, 2.0, 7.8125, 1.6686275],
              "uv": [1.0, 1.0, 0.0, 0.0],
              "clip": [12.625, 8.375, 39.125, 57.375],
              "fade": [5.5, 4.0, 4.5, 2.5]
            }
          ],
          "atlas": \(atlasJson)
        }
        """
        let scene = try JSONDecoder().decode(Scene.self, from: Data(regressionJson.utf8))
        switch scene.validate() {
        case .success:
            break
        case .failure(let err):
            Issue.record("Regression validation failed: \(err)")
            return
        }
        if case .failure(let err) = check(gpu, scene, 2) {
            Issue.record("glyph-texel-boundary.json: \(err)")
        }
    }

    @Test("quarter-turn rotated glyphs match CPU oracle")
    func rotatedGlyphs() {
        let gpu = GpuRenderer.default()
        let fracPi2: Float = Float.pi * 0.5
        let clips: [([Float], [Float])] = [
            (RuneRef.NO_CLIP, [0.0, 0.0, 0.0, 0.0]),
            ([24.5, 15.25, 40.0, 26.75], [3.0, 0.0, 0.0, 2.5]),
        ]
        let angles: [Float] = [fracPi2, Float.pi, Float.pi + fracPi2, -fracPi2]
        let uvs: [[Float]] = [[1.0, 1.0, 0.0, 0.0], [1.0, 1.0, 8.0, 5.0]]
        for (n, angle) in angles.enumerated() {
            for uv in uvs {
                for (c, (clip, fade)) in clips.enumerated() {
                    var scene = generate.scene([])
                    scene.primitives.append(
                        Primitive(
                            node: 1,
                            source: "rotated/\(n)",
                            rect: [20.0, 17.0, 16.0, 10.0],
                            radii: [0.0, 0.0, 0.0, 0.0],
                            fill: [0.7, 0.6, 0.5, 0.8],
                            border: [0.0, 0.0, 0.0, 0.0],
                            params: [angle, 2.0, 0.0, 1.0],
                            uv: uv,
                            clip: clip,
                            fade: fade,
                            fadeOrigin: nil,
                            turn: nil
                        )
                    )
                    if case .failure(let err) = check(gpu, scene, 2) {
                        Issue.record("rotated-\(n)-\(uv[2])-clip-\(c): \(err)")
                        return
                    }
                }
            }
        }
    }

    @Test("GPU metamorphic invariants across 32 seeded scenes")
    func gpuMetamorphic() {
        let gpu = GpuRenderer.default()
        func close(_ a: ArraySlice<UInt8>, _ b: ArraySlice<UInt8>) -> Bool {
            guard a.count == b.count else { return false }
            for (x, y) in zip(a, b) {
                let d = x >= y ? (x - y) : (y - x)
                if d > 2 { return false }
            }
            return true
        }
        for seed: UInt64 in 0..<32 {
            let scene = generate.seeded(seed, 8)
            let original = gpu.render(scene)
            var shifted = scene
            shifted.width += 4
            shifted.height += 6
            generate.translate(&shifted, 4.0, 6.0)
            let actual = gpu.render(shifted)
            for y in 0..<64 {
                let lhs = original[(y * 256)..<((y + 1) * 256)]
                let rhs = actual[(((y + 6) * 68 + 4) * 4)..<(((y + 6) * 68 + 68) * 4)]
                #expect(close(lhs, rhs), "seed \(seed) row \(y) translate mismatch")
            }

            var transparent = scene
            for var p in scene.primitives {
                p.fill = [0.0, 0.0, 0.0, 0.0]
                p.border = [0.0, 0.0, 0.0, 0.0]
                if p.params[1] == 4.0 {
                    p.uv = [0.0, 0.0, 0.0, 0.0]
                }
                transparent.primitives.append(p)
            }
            #expect(original == gpu.render(transparent))

            var full = scene
            for idx in full.primitives.indices {
                full.primitives[idx].clip = RuneRef.NO_CLIP
                full.primitives[idx].fade = [0.0, 0.0, 0.0, 0.0]
            }
            let unclipped = gpu.render(full)
            for idx in full.primitives.indices {
                full.primitives[idx].clip = [0.0, 0.0, 64.0, 64.0]
            }
            let fullRendered = gpu.render(full)
            #expect(close(unclipped[...], fullRendered[...]))

            var disjoint = scene
            for idx in disjoint.primitives.indices {
                disjoint.primitives[idx].clip = [0.0, 0.0, 31.0, 64.0]
                disjoint.primitives[idx].fade = [0.0, 0.0, 0.0, 0.0]
            }
            let n = disjoint.primitives.count
            for var p in scene.primitives {
                p.rect[0] += 32.0
                p.clip = [32.0, 0.0, 64.0, 64.0]
                p.fade = [0.0, 0.0, 0.0, 0.0]
                disjoint.primitives.append(p)
            }
            let first = gpu.render(disjoint)
            if n > 0 && n < disjoint.primitives.count {
                disjoint.primitives = Array(disjoint.primitives[n...]) + Array(disjoint.primitives[..<n])
            }
            #expect(first == gpu.render(disjoint))
        }
    }

    @Test("CPU vs GPU dashed rings across 64 seeded scenes")
    func cpuGpuDashed() {
        let gpu = GpuRenderer.default()
        for seed: UInt64 in 0..<64 {
            let scene = generate.dashed(seed, 8)
            for (n, primitive) in scene.primitives.enumerated() {
                var single = scene
                single.primitives = [primitive]
                if case .failure(let err) = check(gpu, single, 2) {
                    Issue.record("dashed-\(seed)-\(n): \(err)")
                    return
                }
            }
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("dashed-\(seed)-composite: \(err)")
                return
            }
        }
    }

    @Test("CPU vs GPU effect slots across 16 seeded scenes")
    func cpuGpuEffectSlots() {
        let gpu = GpuRenderer.default()
        for seed: UInt64 in 0..<16 {
            var scene = generate.seeded(seed, 8)
            var slots = scene.primitives
            for idx in slots.indices {
                slots[idx].fill = [0.0, 0.0, 0.0, 1.0]
                slots[idx].border = [0.0, 0.0, 0.0, 0.0]
                slots[idx].params = [0.0, 12.0, 6.0, 1.0]
                slots[idx].uv = [0.0, 0.0, 0.0, 0.0]
            }
            scene.primitives.append(contentsOf: slots)
            if scene.primitives.count > 4 {
                let split = scene.primitives.count - 4
                scene.primitives = Array(scene.primitives[split...]) + Array(scene.primitives[..<split])
            }
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("effect-\(seed): \(err)")
                return
            }
        }
    }

    @Test("CPU vs GPU radial gradients across 64 seeded scenes and multi-stop segments")
    func cpuGpuRadial() {
        let gpu = GpuRenderer.default()
        for seed: UInt64 in 0..<64 {
            let scene = generate.radial(seed, 8)
            for (n, primitive) in scene.primitives.enumerated() {
                var single = scene
                single.primitives = [primitive]
                if case .failure(let err) = check(gpu, single, 2) {
                    Issue.record("radial-\(seed)-\(n): \(err)")
                    return
                }
            }
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("radial-\(seed)-composite: \(err)")
                return
            }
        }
        var multi = generate.scene([])
        let base = Primitive(
            node: 1,
            source: "radial/multi-0",
            rect: [8.0, 8.0, 48.0, 48.0],
            radii: [12.0, 12.0, 12.0, 12.0],
            fill: [0.8, 0.2, 0.1, 0.9],
            border: [0.2, 0.7, 0.4, 0.9],
            params: [0.0, 11.0, 0.0, 2.5],
            uv: [24.0, 24.0, 24.0, 20.0],
            clip: RuneRef.NO_CLIP,
            fade: [0.0, 0.0, 0.0, 0.0],
            fadeOrigin: nil,
            turn: nil
        )
        var outer = base
        outer.node = 2
        outer.source = "radial/multi-1"
        outer.fill = base.border
        outer.border = [0.05, 0.1, 0.3, 0.4]
        outer.params = [2.5, 11.0, 0.0, 1.0]
        multi.primitives = [base, outer]
        if case .failure(let err) = check(gpu, multi, 2) {
            Issue.record("radial-multi: \(err)")
        }
    }

    @Test("CPU vs GPU cached subtrees match uncached rendering within 2 LSB")
    func cpuGpuCachedSubtrees() {
        let gpu = GpuRenderer.default()
        // PORT NOTE: Constructs the exact cached vs uncached card + glyph + pill instance stream directly
        // so this differential test runs independently of `Runtime` layout porting (Worker B2/B3).
        func buildScene(_ cached: Bool) -> Scene {
            var base = generate.scene([])
            base.width = 64
            base.height = 64
            base.clear = [0.025, 0.04, 0.06, 1.0]
            var instances: [Rune.Instance] = []
            // Root background
            instances.append(
                Rune.Instance(
                    rect: [0.0, 0.0, 64.0, 64.0],
                    radii: [0.0, 0.0, 0.0, 0.0],
                    fill: [0.06, 0.08, 0.12, 1.0],
                    border: [0.0, 0.0, 0.0, 0.0],
                    params: [0.0, 0.0, 0.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            if cached {
                instances.append(
                    Rune.Instance.beginCachedLayer(
                        [8.0, 8.0, 48.0, 44.0],
                        Rune.NO_CLIP,
                        0x1234_5678,
                        1
                    )
                )
            }
            // Card fill + 1px border (`params[0]` is border width)
            instances.append(
                Rune.Instance(
                    rect: [8.0, 8.0, 48.0, 44.0],
                    radii: [8.0, 8.0, 8.0, 8.0],
                    fill: [0.18, 0.24, 0.36, 1.0],
                    border: [0.45, 0.62, 0.88, 1.0],
                    params: [1.0, 0.0, 0.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            // Inner translucent pill
            instances.append(
                Rune.Instance(
                    rect: [12.0, 32.0, 36.0, 12.0],
                    radii: [4.0, 4.0, 4.0, 4.0],
                    fill: [0.85 * 0.85, 0.32 * 0.85, 0.28 * 0.85, 0.85],
                    border: [0.0, 0.0, 0.0, 0.0],
                    params: [0.0, 0.0, 0.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            if cached {
                instances.append(Rune.Instance.endLayer())
            }
            base.primitives = instances.enumerated().map { idx, inst in
                Primitive.fromInstance(inst, UInt32(idx + 1), "cache/\(idx)")
            }
            textRun(&base, 3)
            return base
        }

        let uncached = buildScene(false)
        let cached = buildScene(true)
        #expect(cached.primitives.contains(where: { $0.params[1] == 8.0 && $0.params[3] == 1.0 }))
        if case .failure(let err) = check(gpu, uncached, 2) {
            Issue.record("uncached CPU vs GPU: \(err)")
            return
        }
        if case .failure(let err) = check(gpu, cached, 2) {
            Issue.record("cached CPU vs GPU: \(err)")
            return
        }
        let gpuUncached = gpu.render(uncached)
        let gpuCached = gpu.render(cached)
        var cpuUncached = Frame.new(64, 64, true)
        cpuUncached.render(uncached)
        let diff = compare(cached, cpuUncached, gpuCached, 2)
        #expect(diff.outlierPixels == 0, "cached GPU vs uncached CPU: \(diff)")
        for (a, b) in zip(gpuUncached, gpuCached) {
            let d = a >= b ? (a - b) : (b - a)
            #expect(d <= 1, "cached vs uncached GPU mismatch: \(a) vs \(b)")
        }
    }

    @Test("CPU vs GPU cached rounded and mixed continuous-corner clips")
    func cpuGpuCachedRoundedClip() {
        var scene = generate.scene([])
        scene.width = 32
        scene.height = 32
        let begin = Rune.Instance.beginLayer(
            [0.0, 0.0, 24.0, 24.0],
            [0.0, 0.0, 24.0, 24.0],
            Rune.LayerSpec(clipRadius: 8.0)
        )
        var paint = generate.scene([[UInt8](repeating: 255, count: 32)]).primitives[0]
        paint.rect = [0.0, 0.0, 24.0, 24.0]
        paint.radii = [0.0, 0.0, 0.0, 0.0]
        paint.fill = [1.0, 1.0, 1.0, 1.0]
        paint.border = [0.0, 0.0, 0.0, 0.0]
        paint.params = [0.0, 0.0, 0.0, 0.0]
        paint.clip = RuneRef.NO_CLIP
        paint.fade = [0.0, 0.0, 0.0, 0.0]
        paint.fadeOrigin = nil
        scene.primitives = [
            Primitive.fromInstance(begin, 1, "rounded"),
            paint,
            Primitive.fromInstance(Rune.Instance.endLayer(), 3, "end"),
        ]
        #expect(Float(bitPattern: Rune.Instance(scene.primitives[0]).fade[3]) == 8.0)
        let gpu = GpuRenderer.default()
        if case .failure(let err) = check(gpu, scene, 2) {
            Issue.record("rounded layer survives replay capture: \(err)")
            return
        }

        var mixed = Rune.Instance.beginLayer(
            [0.0, 0.0, 24.0, 24.0],
            [0.0, 0.0, 24.0, 24.0],
            Rune.LayerSpec()
        )
        mixed.fade[3] = Rune.packClipRadii(mixed.clip, [-10.0, -10.0, 0.0, -4.0])
        scene.primitives = [
            Primitive.fromInstance(mixed, 1, "mixed-continuous"),
            paint,
            Primitive.fromInstance(Rune.Instance.endLayer(), 3, "end"),
        ]
        #expect(scene.primitives[0].border == [-10.0, -10.0, 0.0, -4.0])
        if case .failure(let err) = check(gpu, scene, 2) {
            Issue.record("mixed continuous-corner layer matches CPU oracle: \(err)")
        }
    }

    @Test("CPU vs GPU turned layers including nested turns and post-turn rounded clips")
    func cpuGpuTurnedLayers() {
        let gpu = GpuRenderer.default()
        let angles: [Float] = [0.3, -1.1, Float.pi * 0.5, 2.6]
        for (n, angle) in angles.enumerated() {
            var scene = generate.scene([])
            scene.width = 64
            scene.height = 64
            scene.clear = [0.025, 0.04, 0.06, 1.0]

            // PORT NOTE: Emits the exact turned layer + nested turned child + rounded-clipped turned layer
            // directly via `Rune.Instance` so differential layer rotation is verified without `Runtime`.
            var instances: [Rune.Instance] = []
            // Top turned card with pivot at bottom-center `(19.0, 26.0)`
            instances.append(
                Rune.Instance.beginLayer(
                    [4.0, 4.0, 30.0, 22.0],
                    Rune.NO_CLIP,
                    Rune.LayerSpec()
                ).turned(angle, [19.0, 26.0])
            )
            instances.append(
                Rune.Instance(
                    rect: [4.0, 4.0, 30.0, 22.0],
                    radii: [5.0, 5.0, 5.0, 5.0],
                    fill: [0.18, 0.24, 0.36, 1.0],
                    border: [0.45, 0.62, 0.88, 1.0],
                    params: [0.0, 0.0, 1.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            instances.append(Rune.Instance.endLayer())

            // Clipped turned card with nested turned child
            instances.append(
                Rune.Instance.beginLayer(
                    [4.0, 30.0, 30.0, 22.0],
                    [4.0, 30.0, 60.0, 60.0],
                    Rune.LayerSpec(clipRadius: 4.0)
                ).turned(-angle, [19.0, 41.0])
            )
            instances.append(
                Rune.Instance(
                    rect: [4.0, 30.0, 30.0, 22.0],
                    radii: [5.0, 5.0, 5.0, 5.0],
                    fill: [0.18, 0.24, 0.36, 1.0],
                    border: [0.45, 0.62, 0.88, 1.0],
                    params: [0.0, 0.0, 1.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            instances.append(
                Rune.Instance.beginLayer(
                    [10.0, 36.0, 8.0, 8.0],
                    Rune.NO_CLIP,
                    Rune.LayerSpec()
                ).turned(angle * 2.0, [14.0, 40.0])
            )
            instances.append(
                Rune.Instance(
                    rect: [10.0, 36.0, 8.0, 8.0],
                    radii: [0.0, 0.0, 0.0, 0.0],
                    fill: [0.85 * 0.85, 0.32 * 0.85, 0.28 * 0.85, 0.85],
                    border: [0.0, 0.0, 0.0, 0.0],
                    params: [0.0, 0.0, 0.0, 0.0],
                    uv: [0.0, 0.0, 0.0, 0.0],
                    clip: Rune.NO_CLIP,
                    fade: [0, 0, 0, 0]
                )
            )
            instances.append(Rune.Instance.endLayer())
            instances.append(Rune.Instance.endLayer())

            let primitives = instances.enumerated().map { idx, inst in
                Primitive.fromInstance(inst, UInt32(idx + 1), "turned/\(idx)")
            }
            #expect(primitives.contains(where: { $0.params[1] == 8.0 && $0.turn?[0] == angle }))
            scene.primitives = primitives
            if case .failure(let err) = check(gpu, scene, 2) {
                Issue.record("turned-\(n): \(err)")
                return
            }
        }
    }
}
#endif
