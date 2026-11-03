// Tests ported from: crates/rune/src/render/continuous_corner_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Foundation
import Testing
@testable import Rune

private let APPLE_CURVE: [[Float]] = [
    [0.0, 1.528_664_8], [0.0, 1.088_493_2], [0.0, 0.868_407], [0.074_911_41, 0.631_494],
    [0.169_06, 0.372_824], [0.372_824, 0.169_06], [0.631_494, 0.074_911_41],
    [0.868_407, 0.0], [1.088_493_2, 0.0], [1.528_664_8, 0.0],
]

private func polyline(_ r: Float) -> [[Float]] {
    var points: [[Float]] = []
    for segStart in stride(from: 0, through: 6, by: 3) {
        let c0 = APPLE_CURVE[segStart]
        let c1 = APPLE_CURVE[segStart + 1]
        let c2 = APPLE_CURVE[segStart + 2]
        let c3 = APPLE_CURVE[segStart + 3]
        for k in 0..<64 {
            let t = Float(k) / 64.0
            let omt = 1.0 - t
            let b0 = omt * omt * omt
            let b1 = 3.0 * t * omt * omt
            let b2 = 3.0 * t * t * omt
            let b3 = t * t * t
            let px = (b0 * c0[0] + b1 * c1[0] + b2 * c2[0] + b3 * c3[0]) * r
            let py = (b0 * c0[1] + b1 * c1[1] + b2 * c2[1] + b3 * c3[1]) * r
            points.append([px, py])
        }
    }
    points.append([APPLE_CURVE[9][0] * r, APPLE_CURVE[9][1] * r])
    return points
}

private func oracle(_ p: [Float], _ line: [[Float]]) -> Float {
    let e = line[line.count - 1][0]
    if p[0] >= e || p[1] >= e {
        return max(-p[0], -p[1])
    }
    var bestD = Float.greatestFiniteMagnitude
    var bestSign: Float = 0.0
    for idx in 0..<(line.count - 1) {
        let a = line[idx]
        let b = line[idx + 1]
        let ab0 = b[0] - a[0]
        let ab1 = b[1] - a[1]
        let ap0 = p[0] - a[0]
        let ap1 = p[1] - a[1]
        let t = min(max((ap0 * ab0 + ap1 * ab1) / (ab0 * ab0 + ab1 * ab1), 0.0), 1.0)
        let d = hypotf(ap0 - ab0 * t, ap1 - ab1 * t)
        if d < bestD {
            bestD = d
            bestSign = ab0 * ap1 - ab1 * ap0
        }
    }
    return bestSign > 0.0 ? -bestD : bestD
}

private func ccRect(_ bounds: [Float], _ color: [Float]) -> Instance {
    Instance(
        rect: bounds,
        fill: color,
        params: [0.0, KIND_RECT, 0.0, 1.0],
        clip: NO_CLIP
    )
}

private func ccPixels(_ gpu: Gpu, _ renderer: Renderer, _ target: Offscreen) -> [UInt8] {
    let enc = gpu.metalDevice.createCommandEncoder(label: "continuous-corners")
    renderer.draw(enc, target.view, [0.0, 0.0, 0.0, 0.0])
    target.copy(enc)
    renderer.submit(gpu.metalQueue, enc)
    return target.read(gpu.metalDevice)
}

@Suite("Rune Continuous Corner Tests", .serialized)
struct RuneContinuousCornerTests {
    @Test("continuous corners follow Apple's curve in fills and clips")
    func continuousCornersFollowApplesCurveInFillsAndClips() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 96, 80)
        var atlas = TextSystem().atlas
        let bounds: [Float] = [8.0, 8.0, 72.0, 56.0]
        let r: Float = 14.0
        let line = polyline(r)

        var fill = ccRect(bounds, [1.0, 1.0, 1.0, 1.0])
        fill.radii = [-r, -r, -r, -r]

        var clipped = ccRect([0.0, 0.0, 96.0, 80.0], [1.0, 1.0, 1.0, 1.0])
        clipped.clip = [8.0, 8.0, 80.0, 64.0]
        clipped.roundClip(-r)

        for instance in [fill, clipped] {
            renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [instance], (96, 80))
            let out = ccPixels(gpu, renderer, target)
            var worst: Float = 0.0
            for y in 0..<80 {
                for x in 0..<96 {
                    let cx = Float(x) + 0.5
                    let cy = Float(y) + 0.5
                    let p = [min(cx - 8.0, 80.0 - cx), min(cy - 8.0, 64.0 - cy)]
                    let want = min(max(0.5 - oracle(p, line), 0.0), 1.0)
                    let got = Float(out[(y * 96 + x) * 4 + 3]) / 255.0
                    worst = max(worst, abs(got - want))
                }
            }
            #expect(worst < 0.04, "coverage off the curve by \(worst)")
        }
    }

    @Test("continuous corners at half the shorter side stay closed")
    func continuousCornersAtHalfTheShorterSideStayClosed() {
        let gpu = Gpu.headless()
        let renderer = Renderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let target = Offscreen(gpu.metalDevice, 64, 32)
        var atlas = TextSystem().atlas
        var capsule = ccRect([0.0, 0.0, 64.0, 32.0], [1.0, 1.0, 1.0, 1.0])
        capsule.radii = [-100.0, -100.0, -100.0, -100.0]
        renderer.prepare(gpu.metalDevice, gpu.metalQueue, &atlas, [capsule], (64, 32))
        let out = ccPixels(gpu, renderer, target)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { out[(y * 64 + x) * 4 + 3] }
        #expect(alpha(32, 16) == 255)
        #expect(alpha(32, 0) == 255)
        #expect(alpha(0, 0) == 0)
        #expect(alpha(0, 16) > 64 && alpha(0, 16) < 255)
    }
}
#endif
