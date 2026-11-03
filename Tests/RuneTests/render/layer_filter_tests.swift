// Tests ported from: crates/rune/src/render/layer_filter_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import Testing
import CWebGPU
@testable import Rune

private func lfRect(_ bounds: [Float], _ color: [Float]) -> Instance {
    Instance(
        rect: bounds,
        fill: color,
        params: [0.0, KIND_RECT, 0.0, 1.0],
        clip: NO_CLIP
    )
}

private func lfFiltered(_ bounds: [Float], _ sigma: Float) -> [Instance] {
    [
        Instance.beginLayer(bounds, NO_CLIP, LayerSpec(blur: sigma)),
        lfRect(bounds, [1.0, 1.0, 1.0, 1.0]),
        Instance.endLayer(),
    ]
}

private func lfCoverage(_ x: Int, _ start: Int, _ end: Int, _ sigma: Float) -> Float {
    let radius = Int((3.0 * sigma).rounded(.up))
    func weight(_ d: Int) -> Float {
        let r = Float(d) / sigma
        return expf(-0.5 * r * r)
    }
    var total: Float = 0.0
    var covered: Float = 0.0
    for d in -radius...radius {
        let w = weight(d)
        total += w
        if (start..<end).contains(x + d) {
            covered += w
        }
    }
    return covered / total
}

private func lfPixels(_ gpu: Gpu, _ renderer: Renderer, _ target: Offscreen) -> [UInt8] {
    let enc = gpu.metalDevice.createCommandEncoder(label: "layer-filter-test")
    renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
    target.copy(enc)
    renderer.submit(gpu.metalQueue, enc)
    return target.read(gpu.metalDevice)
}

private func lfRgba(_ linear: [Float]) -> [UInt8] {
    (0..<4).map { i in
        let v = linear[i]
        let srgb: Float
        if i == 3 {
            srgb = v
        } else if v <= 0.0031308 {
            srgb = v * 12.92
        } else {
            srgb = 1.055 * powf(v, 1.0 / 2.4) - 0.055
        }
        return UInt8(min(max((srgb * 255.0).rounded(), 0.0), 255.0))
    }
}

private func lfNear(_ got: ArraySlice<UInt8>, _ want: [UInt8], tolerance: UInt8 = 2) {
    for (g, w) in zip(got, want) {
        let d = g >= w ? (g - w) : (w - g)
        #expect(d <= tolerance, "got \(Array(got)), want \(want)")
    }
}

@Suite("Rune Layer Filter Tests", .serialized)
struct RuneLayerFilterTests {
    @Test("gaussian pixels support offscreen saturation and pooling")
    func gaussianPixelsSupportOffscreenSaturationAndPooling() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 64, 48)
        var atlas = TextSystem().atlas
        let cases: [(Int, Int, Float, Bool)] = [
            (12, 10, 2.0, false),
            (-6, -4, 3.0, false),
            (12, 10, 2.0, true),
        ]
        for (left, top, sigma, additive) in cases {
            let bounds: [Float] = [Float(left), Float(top), 20.0, 16.0]
            var content = lfFiltered(bounds, sigma)
            if additive {
                content[0].params[0] = 1.0
                content.insert(lfRect(bounds, [1.0, 1.0, 1.0, 1.0]), at: 2)
            }
            renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (64, 48))
            #expect(renderer.layerStats().extraPasses == 3)
            let out = lfPixels(gpu, renderer, target)
            for y in 0..<48 {
                for x in 0..<64 {
                    let c = lfCoverage(x, left, left + 20, sigma) * lfCoverage(y, top, top + 16, sigma)
                    let at = (y * 64 + x) * 4
                    lfNear(out[at..<(at + 4)], lfRgba([c, c, c, c]))
                }
            }
        }
        let allocations = renderer.layerStats().allocations
        for sigma: Float in [2.1, 2.4, 2.0] {
            renderer.prepare(
                gpu.metalDevice,
                gpu.metalQueue,
                &atlas,
                lfFiltered([12.0, 10.0, 20.0, 16.0], sigma),
                (64, 48)
            )
            #expect(renderer.layerStats().allocations == allocations)
        }
        for sigma: Float in [0.0, -1.0, .nan] {
            renderer.prepare(
                gpu.metalDevice,
                gpu.metalQueue,
                &atlas,
                lfFiltered([12.0, 10.0, 20.0, 16.0], sigma),
                (64, 48)
            )
            #expect(renderer.layerStats().targets == 0)
            #expect(renderer.layerStats().extraPasses == 0)
        }
    }

    @Test("blur live springs curves and zero bypass", .disabled("Requires full Runtime layout/painter port (Worker B2/B3)"))
    func blurLiveSpringsCurvesAndZeroBypass() {}

    @Test("runtime keeps offscreen blur sources and presence transitions", .disabled("Requires full Runtime layout/painter port (Worker B2/B3)"))
    func runtimeKeepsOffscreenBlurSourcesAndPresenceTransitions() {}

    @Test("later live blur binding replaces the earlier source", .disabled("Requires full Runtime layout/painter port (Worker B2/B3)"))
    func laterLiveBlurBindingReplacesTheEarlierSource() {}

    @Test("nested blur and capsule mask apply to completed output")
    func nestedBlurAndCapsuleMaskApplyToCompletedOutput() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 64, 48)
        var atlas = TextSystem().atlas
        let clip: [Float] = [8.0, 8.0, 56.0, 40.0]
        var outer = Instance.beginLayer(
            [0.0, 0.0, 64.0, 48.0],
            clip,
            LayerSpec(opacity: 0.5, blur: 2.0, clipRadius: 16.0)
        )
        var all = [outer]
        all.append(contentsOf: lfFiltered([0.0, 0.0, 64.0, 48.0], 2.0))
        all.append(Instance.endLayer())
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, all, (64, 48))
        #expect(renderer.layerStats().extraPasses == 6)
        let out = lfPixels(gpu, renderer, target)
        let checks: [(Int, Int, Float)] = [(8, 8, 0.0), (55, 39, 0.0), (32, 24, 0.5), (32, 9, 0.5), (4, 24, 0.0)]
        for (x, y, c) in checks {
            let at = (y * 64 + x) * 4
            lfNear(out[at..<(at + 4)], lfRgba([c, c, c, c]))
        }

        outer = Instance.beginLayer(
            [0.0, 0.0, 64.0, 48.0],
            [24.0, 0.0, 64.0, 48.0],
            LayerSpec(opacity: 0.5)
        )
        all = [
            outer,
            Instance.beginLayer([0.0, 0.0, 64.0, 48.0], clip, LayerSpec(clipRadius: 16.0)),
            lfRect([0.0, 0.0, 64.0, 48.0], [1.0, 1.0, 1.0, 1.0]),
            Instance.endLayer(),
            Instance.endLayer(),
        ]
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, all, (64, 48))
        let out2 = lfPixels(gpu, renderer, target)
        lfNear(out2[((8 * 64 + 24) * 4)..<((8 * 64 + 25) * 4)], lfRgba([0.5, 0.5, 0.5, 0.5]))
        lfNear(out2[((24 * 64 + 20) * 4)..<((24 * 64 + 21) * 4)], [0, 0, 0, 0])
    }

    @Test("nested targets bound ancestor support without losing halos")
    func nestedTargetsBoundAncestorSupportWithoutLosingHalos() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 512, 512)
        var atlas = TextSystem().atlas
        let clip: [Float] = [240.0, 240.0, 272.0, 272.0]
        var content: [Instance] = [
            Instance.beginLayer([0.0, 0.0, 512.0, 512.0], NO_CLIP, LayerSpec(blur: 3.0)),
            Instance.beginLayer([0.0, 0.0, 512.0, 512.0], NO_CLIP, LayerSpec(blur: 2.0)),
        ]
        content.append(contentsOf: lfFiltered([232.0, 246.0, 6.0, 20.0], 1.0))
        content.append(contentsOf: [Instance.endLayer(), Instance.endLayer()])
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (512, 512))
        let reference = lfPixels(gpu, renderer, target)

        content[0].clip = clip
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (512, 512))
        for t in renderer.layers.targets.compactMap({ $0 }) {
            #expect(t.texture.width <= 64 && t.texture.height <= 64)
        }
        let out = lfPixels(gpu, renderer, target)
        var halo = false
        for y in 0..<512 {
            for x in 0..<512 {
                let at = (y * 512 + x) * 4 + 3
                let inside = (240..<272).contains(x) && (240..<272).contains(y)
                let want: UInt8 = inside ? reference[at] : 0
                let diff = out[at] >= want ? (out[at] - want) : (want - out[at])
                #expect(diff <= 1, "(\(x),\(y))")
                if inside && out[at] > 0 { halo = true }
            }
        }
        #expect(halo)
    }

    @Test("unchanged blur reuses uniforms and changed inputs refresh them")
    func unchangedBlurReusesUniformsAndChangedInputsRefreshThem() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        var atlas = TextSystem().atlas
        var writes: UInt64 = 0
        let seq: [(Float, Float, Bool, Bool)] = [
            (20.0, 2.0, false, true),
            (20.0, 2.0, false, false),
            (20.0, 2.5, false, true),
            (22.0, 2.5, false, true),
            (22.0, 2.5, true, true),
            (22.0, 4.0, true, true),
            (22.0, 4.0, true, false),
            (22.0, 2.0, true, true),
        ]
        for (width, sigma, additive, changed) in seq {
            var content = lfFiltered([12.0, 10.0, width, 16.0], sigma)
            content[0].params[0] = additive ? 1.0 : 0.0
            renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (64, 48))
            let blur = renderer.layers.targets[0]!.blur!
            let expected = writes + (changed ? UInt64(blur.passes()) : 0)
            #expect(blur.uniformWrites == expected)
            writes = expected
        }
    }

    @Test("filtered video and image page match primitive source")
    func filteredVideoAndImagePageMatchPrimitiveSource() throws {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 64, 48)
        var atlas = TextSystem().atlas
        let bounds: [Float] = [12.0, 10.0, 20.0, 16.0]
        var content = lfFiltered(bounds, 2.0)
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (64, 48))
        let reference = lfPixels(gpu, renderer, target)

        var images = ImageAtlas()
        let full = Pixels()
        full.set(1024, 1024, [UInt8](repeating: 255, count: 1024 * 1024 * 4))
        _ = images.place(full, [1024.0, 1024.0])
        let white = Pixels()
        white.set(1, 1, [255, 255, 255, 255])
        let image = images.place(white, [20.0, 16.0])!
        #expect(image.page == 1)
        content[1] = Instance(
            rect: bounds,
            fill: [0.0, 0.0, 0.0, 1.0],
            params: [Float(image.page), KIND_IMAGE, 0.0, 1.0],
            uv: image.rect.map { Float($0) },
            clip: NO_CLIP
        )
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (64, 48))
        renderer.uploadImages(gpu.metalDevice, gpu.metalQueue, &images)
        #expect(lfPixels(gpu, renderer, target) == reference)

        content.remove(at: 1)
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, content, (64, 48))
        let surface = NativeSurface()
        _ = try surface.pushBytes(
            ByteFrame(
                width: 1,
                height: 1,
                format: .bgra,
                color: ColorInfo(),
                planes: [[255, 255, 255, 255], []]
            ),
            1
        ).get()
        renderer.prepareSurfaces(
            gpu.metalDevice,
            gpu.metalQueue,
            [
                SurfaceDraw(
                    surface: surface,
                    fit: .fill,
                    beforeInstance: 1,
                    rect: bounds,
                    radii: [0.0, 0.0, 0.0, 0.0],
                    clip: NO_CLIP,
                    fade: [0, 0, 0, 0],
                    opacity: 1.0
                ),
            ],
            (64, 48)
        )
        #expect(lfPixels(gpu, renderer, target) == reference)

        _ = try surface.pushBytes(
            ByteFrame(
                width: 1,
                height: 1,
                format: .bgra,
                color: ColorInfo(),
                planes: [[0, 0, 0, 255], []]
            ),
            2
        ).get()
        renderer.prepareSurfaces(
            gpu.metalDevice,
            gpu.metalQueue,
            [
                SurfaceDraw(
                    surface: surface,
                    fit: .fill,
                    beforeInstance: 1,
                    rect: bounds,
                    radii: [0.0, 0.0, 0.0, 0.0],
                    clip: NO_CLIP,
                    fade: [0, 0, 0, 0],
                    opacity: 1.0
                ),
            ],
            (64, 48)
        )
        let black = lfPixels(gpu, renderer, target)
        #expect(black[(18 * 64 + 22) * 4] == 0)
        #expect(black[(18 * 64 + 22) * 4 + 3] == reference[(18 * 64 + 22) * 4 + 3])
    }

    @Test("reduced gaussian accuracy and resolution boundary continuity")
    func reducedGaussianAccuracyAndResolutionBoundaryContinuity() {
        let gpu = Gpu.headless()
        let fmt = WGPUTextureFormat_RGBA8Unorm
        let renderer = Renderer(gpu.metalDevice, fmt)
        let target = Offscreen(gpu.metalDevice, 128, 96, fmt)
        var atlas = TextSystem().atlas
        var previous: [UInt8]? = nil
        let sigmas: [Float] = [2.999, 3.001, 4.0, 8.0, 16.0, 64.0]
        for sigma in sigmas {
            renderer.prepare(
                gpu.metalDevice,
                gpu.metalQueue,
                &atlas,
                lfFiltered([24.0, 24.0, 80.0, 48.0], sigma),
                (128, 96)
            )
            let out = lfPixels(gpu, renderer, target)
            var worst: UInt8 = 0
            for y in 0..<96 {
                for x in 0..<128 {
                    let c = lfCoverage(x, 24, 104, sigma) * lfCoverage(y, 24, 72, sigma)
                    let want = UInt8((c * 255.0).rounded())
                    let got = out[(y * 128 + x) * 4 + 3]
                    let diff = got >= want ? (got - want) : (want - got)
                    worst = max(worst, diff)
                }
            }
            #expect(worst <= 3, "sigma=\(sigma) error=\(worst)")
            if sigma == 3.001, let before = previous {
                for (a, b) in zip(out, before) {
                    let d = a >= b ? (a - b) : (b - a)
                    #expect(d <= 1, "resolution boundary must be continuous")
                }
            }
            previous = out
        }
    }
}
#endif
