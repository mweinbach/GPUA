// Tests ported from: crates/rune/src/native_surface/place_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let TOP_LEFT = SurfacePlace(anchor: [.start, .start], unscaled: false)
private let TOP_LEFT_1X = SurfacePlace(anchor: [.start, .start], unscaled: true)
private let STALE: [UInt32] = [100, 50]

private func near4(_ got: [Float], _ want: [Float], _ what: String = "") {
    #expect(got.count == 4 && want.count == 4)
    for (a, b) in zip(got, want) {
        #expect(abs(a - b) < 1e-3, "\(what): \(got) vs \(want)")
    }
}

@Suite("NativeSurface Placement Tests")
struct NativeSurfacePlaceTests {
    @Test("centred default is the old placement")
    func centredDefaultIsTheOldPlacement() {
        let c = SurfacePlace.default()
        #expect(c == SurfacePlace.CENTRED)
        #expect(surfaceImageRect([0.0, 0.0, 120.0, 50.0], STALE, .fit, c) == [10.0, 0.0, 100.0, 50.0])
        near4(surfaceImageRect([0.0, 0.0, 120.0, 50.0], STALE, .fill, c), [0.0, -5.0, 120.0, 60.0], "fill wide")
        #expect(surfaceImageRect([0.0, 0.0, 80.0, 60.0], STALE, .fit, c) == [0.0, 10.0, 80.0, 40.0])
        near4(surfaceImageRect([0.0, 0.0, 80.0, 60.0], STALE, .fill, c), [-20.0, 0.0, 120.0, 60.0], "fill tall")
    }

    @Test("top-left anchor pins the corner under fit and fill")
    func topLeftAnchorPinsTheCornerUnderFitAndFill() {
        func at(_ node: [Float], _ f: SurfaceFit) -> [Float] {
            surfaceImageRect(node, STALE, f, TOP_LEFT)
        }
        #expect(at([0.0, 0.0, 120.0, 50.0], .fit) == [0.0, 0.0, 100.0, 50.0])
        near4(at([0.0, 0.0, 120.0, 50.0], .fill), [0.0, 0.0, 120.0, 60.0], "crops the bottom only")
        #expect(at([0.0, 0.0, 80.0, 60.0], .fit) == [0.0, 0.0, 80.0, 40.0])
        near4(at([0.0, 0.0, 80.0, 60.0], .fill), [0.0, 0.0, 120.0, 60.0], "crops the right only")
    }

    @Test("unscaled keeps texels and loses only the far edges")
    func unscaledKeepsTexelsAndLosesOnlyTheFarEdges() {
        func at(_ node: [Float]) -> [Float] {
            surfaceImageRect(node, STALE, .fill, TOP_LEFT_1X)
        }
        #expect(at([0.0, 0.0, 120.0, 50.0]) == [0.0, 0.0, 100.0, 50.0])
        #expect(at([0.0, 0.0, 80.0, 60.0]) == [0.0, 0.0, 100.0, 50.0])
        #expect(surfaceImageRect([7.0, 9.0, 120.0, 50.0], STALE, .fit, TOP_LEFT_1X) == [7.0, 9.0, 100.0, 50.0])
        let end = SurfacePlace(anchor: [.end, .end], unscaled: true)
        #expect(surfaceImageRect([0.0, 0.0, 80.0, 60.0], STALE, .fit, end) == [-20.0, 10.0, 100.0, 50.0])
    }

    @Test("pixels follow the same anchor")
    func pixelsFollowTheSameAnchor() {
        let size: (UInt32, UInt32) = (100, 50)
        let wide: [Float] = [0.0, 0.0, 120.0, 50.0]
        let tall: [Float] = [0.0, 0.0, 80.0, 60.0]
        let (r1, uv1) = fitImageRect(.fit, TOP_LEFT, wide, size)
        #expect(r1 == [0.0, 0.0, 100.0, 50.0] && uv1 == [0.0, 0.0, 1.0, 1.0])
        let (r2, uv2) = fitImageRect(.fit, TOP_LEFT, tall, size)
        #expect(r2 == [0.0, 0.0, 80.0, 40.0] && uv2 == [0.0, 0.0, 1.0, 1.0])

        let (rectT, cropT) = fitImageRect(.fill, TOP_LEFT, tall, size)
        #expect(rectT == tall && cropT[0] == 0.0 && cropT[1] == 0.0)
        #expect(abs(cropT[3] - 1.0) < 1e-6)
        #expect(abs(cropT[2] - 80.0 / 120.0) < 1e-6)

        let (rectW, cropW) = fitImageRect(.fill, TOP_LEFT, wide, size)
        #expect(rectW == wide && cropW[0] == 0.0 && cropW[1] == 0.0)
        #expect(abs(cropW[2] - 1.0) < 1e-6)
        #expect(abs(cropW[3] - 50.0 / 60.0) < 1e-6)

        let (r3, uv3) = fitImageRect(.fill, TOP_LEFT_1X, wide, size)
        #expect(r3 == [0.0, 0.0, 100.0, 50.0] && uv3 == [0.0, 0.0, 1.0, 1.0])
        let (r4, uv4) = fitImageRect(.fit, TOP_LEFT_1X, tall, size)
        #expect(r4 == [0.0, 0.0, 80.0, 50.0])
        near4(uv4, [0.0, 0.0, 0.8, 1.0], "crop right")
        let (r5, uv5) = fitImageRect(nil, TOP_LEFT_1X, tall, size)
        #expect(r5 == tall && uv5 == [0.0, 0.0, 1.0, 1.0])
    }

    #if canImport(Metal)
    @Test("a stale frame draws pinned top-left on the GPU")
    func aStaleFrameDrawsPinnedTopLeftOnTheGpu() {
        let gpu = Gpu.headless()
        let surface = NativeSurface().placed(TOP_LEFT_1X)

        // 8x6 white BGRA frame drawn into a 20x16 box: only 0..<8 x 0..<6 should light up.
        let whiteFrame = ByteFrame(
            width: 8,
            height: 6,
            format: .bgra,
            color: ColorInfo(matrix: .bt709, transfer: .srgb),
            planes: [[UInt8](repeating: 255, count: 8 * 6 * 4), []]
        )
        _ = surface.pushBytes(whiteFrame, 1)

        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let draw = SurfaceDraw(
            surface: surface,
            fit: .fit,
            beforeInstance: 0,
            rect: [0.0, 0.0, 20.0, 16.0]
        )
        pipe.prepare(gpu.metalDevice, gpu.metalQueue, [draw], (20, 16))
        let target = Offscreen(gpu.metalDevice, 20, 16)
        let encoder = gpu.metalDevice.createCommandEncoder()
        let pass = encoder.beginRenderPass(
            colorAttachments: [MetalColorAttachment(view: target.view, load: .clear(r: 0, g: 0, b: 0, a: 1))]
        )
        pipe.draw(pass, 0)
        pass.end()
        target.copy(encoder)
        pipe.submit(gpu.metalQueue, encoder)
        let pixels = target.read(gpu.metalDevice)

        func red(_ x: Int, _ y: Int) -> UInt8 {
            pixels[(y * 20 + x) * 4]
        }
        #expect(red(0, 0) == 255, "pinned at top-left")
        #expect(red(7, 5) == 255, "far corner of the 8x6 frame")
        #expect(red(8, 0) == 0, "right of the frame stays clear, not stretched")
        #expect(red(0, 6) == 0, "below the frame stays clear, not centred")
        #expect(red(10, 8) == 0, "centre of the 20x16 box is outside the 8x6 frame")

        // Now shrink the pane to 4x4 without a new frame: only the 4x4 top-left corner draws.
        var redTopLeft = [UInt8](repeating: 0, count: 8 * 6 * 4)
        for y in 0..<6 {
            for x in 0..<8 {
                let idx = (y * 8 + x) * 4
                if x < 4 && y < 4 {
                    redTopLeft[idx..<idx + 4] = [0, 0, 255, 255][...]
                } else {
                    redTopLeft[idx..<idx + 4] = [0, 255, 0, 255][...]
                }
            }
        }
        _ = surface.pushBytes(
            ByteFrame(
                width: 8,
                height: 6,
                format: .bgra,
                color: ColorInfo(matrix: .bt709, transfer: .srgb),
                planes: [redTopLeft, []]
            ),
            2
        )

        let shrinkDraw = SurfaceDraw(
            surface: surface,
            fit: .fit,
            beforeInstance: 0,
            rect: [0.0, 0.0, 4.0, 4.0]
        )
        pipe.prepare(gpu.metalDevice, gpu.metalQueue, [shrinkDraw], (8, 8))
        let shrunk = Offscreen(gpu.metalDevice, 8, 8)
        let enc2 = gpu.metalDevice.createCommandEncoder()
        let pass2 = enc2.beginRenderPass(
            colorAttachments: [MetalColorAttachment(view: shrunk.view, load: .clear(r: 0, g: 0, b: 0, a: 1))]
        )
        pipe.draw(pass2, 0)
        pass2.end()
        shrunk.copy(enc2)
        pipe.submit(gpu.metalQueue, enc2)
        let sp = shrunk.read(gpu.metalDevice)
        #expect(Array(sp[0..<4]) == [255, 0, 0, 255], "top-left stays red, not green from the centre")
        let corner = (3 * 8 + 3) * 4
        #expect(Array(sp[corner..<corner + 4]) == [255, 0, 0, 255], "(3, 3) is still the red top-left texel")
    }
    #endif
}
