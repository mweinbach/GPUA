// Tests ported from: crates/rune/src/native_surface/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Foundation
import Testing
@testable import Rune
#if os(macOS)
import CoreVideo
import IOSurface
#endif

private func drawOne(
    _ gpu: Gpu,
    _ pipe: SurfaceRenderer,
    _ draw: SurfaceDraw,
    _ w: UInt32,
    _ h: UInt32,
    _ clear: [Double]
) -> [UInt8] {
    let target = Offscreen(gpu.metalDevice, w, h)
    pipe.prepare(gpu.metalDevice, gpu.metalQueue, [draw], (w, h))
    let encoder = gpu.metalDevice.createCommandEncoder()
    let pass = encoder.beginRenderPass(
        colorAttachments: [
            MetalColorAttachment(
                view: target.view,
                load: .clear(r: clear[0], g: clear[1], b: clear[2], a: clear[3])
            )
        ],
        timestampWrites: pipe.timestampWrites()
    )
    if !pipe.isEmpty() {
        pipe.draw(pass, 0)
    }
    pass.end()
    target.copy(encoder)
    pipe.submit(gpu.metalQueue, encoder)
    return target.read(gpu.metalDevice)
}

private func fullDraw(_ surface: NativeSurface, _ w: Float, _ h: Float) -> SurfaceDraw {
    SurfaceDraw(
        surface: surface,
        fit: .fit,
        beforeInstance: 0,
        rect: [0.0, 0.0, w, h]
    )
}

private func srgbByte(_ linear: Float) -> UInt8 {
    let c = min(max(linear, 0.0), 1.0)
    let e: Float = if c <= 0.0031308 {
        c * 12.92
    } else {
        1.055 * Float(pow(Double(c), 1.0 / 2.4)) - 0.055
    }
    return UInt8((e * 255.0).rounded())
}

private func nv12Solid(_ w: UInt32, _ h: UInt32, _ y: UInt8, _ cb: UInt8, _ cr: UInt8, _ format: SurfaceFormat, _ color: ColorInfo) -> ByteFrame {
    let n = Int(w * h)
    var uv = [UInt8]()
    uv.reserveCapacity(n / 2)
    for _ in 0..<(n / 4) {
        uv.append(cb)
        uv.append(cr)
    }
    return ByteFrame(width: w, height: h, format: format, color: color, planes: [[UInt8](repeating: y, count: n), uv])
}

private func px(_ img: [UInt8], _ w: UInt32, _ x: UInt32, _ y: UInt32) -> [UInt8] {
    let i = Int((y * w + x) * 4)
    return [img[i], img[i + 1], img[i + 2], img[i + 3]]
}

private func assertClose(_ got: [UInt8], _ want: [UInt8], _ tol: Int, _ label: String) {
    for c in 0..<4 {
        let diff = abs(Int(got[c]) - Int(want[c]))
        #expect(diff <= tol, "\(label): got \(got), expected \(want) (±\(tol))")
    }
}

private func waitCompleted(_ gpu: Gpu, _ surface: NativeSurface, _ atLeast: UInt64) {
    let deadline = Date().addingTimeInterval(2.0)
    while surface.counts().1 < atLeast && Date() < deadline {
        _ = gpu.metalDevice.poll(.poll)
        Thread.sleep(forTimeInterval: 0.002)
    }
    #expect(surface.counts().1 >= atLeast, "GPU completion did not arrive: \(surface.counts())")
}

private func checkSurfaceSuite(
    _ gpu: Gpu,
    _ pipe: SurfaceRenderer,
    _ push: (NativeSurface, ByteFrame, UInt64) -> Void
) {
    let surface = NativeSurface()
    let seenLock = NSLock()
    nonisolated(unsafe) var seen: [FrameTiming] = []
    surface.setObserver { t in
        seenLock.lock()
        seen.append(t)
        seenLock.unlock()
    }

    // 1. Colour accuracy: SMPTE bars, BT.601 vs BT.709, video vs full range, sRGB vs BT.709 transfer.
    let cases: [(UInt8, UInt8, UInt8, SurfaceFormat, ColorInfo, String)] = [
        (16, 128, 128, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 video black"),
        (235, 128, 128, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 video white"),
        (126, 128, 128, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 mid grey"),
        (82, 90, 240, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 red bar"),
        (145, 54, 34, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 green bar"),
        (41, 240, 110, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709), "bt709 blue bar"),
        (82, 90, 240, .nv12Video, ColorInfo(matrix: .bt601, transfer: .bt709), "bt601 vs bt709 matrix"),
        (0, 128, 128, .nv12Full, ColorInfo(matrix: .bt709, transfer: .srgb), "full-range black"),
        (255, 128, 128, .nv12Full, ColorInfo(matrix: .bt709, transfer: .srgb), "full-range white"),
        (180, 100, 170, .nv12Full, ColorInfo(matrix: .bt601, transfer: .srgb), "full-range warm"),
    ]
    for (idx, (y, cb, cr, fmt, color, label)) in cases.enumerated() {
        push(surface, nv12Solid(16, 16, y, cb, cr, fmt, color), UInt64(idx + 1))
        let out = drawOne(gpu, pipe, fullDraw(surface, 16.0, 16.0), 16, 16, [0, 0, 0, 1])
        let ref = nv12Reference(y, cb, cr, fmt, color)
        let want: [UInt8] = [srgbByte(ref[0]), srgbByte(ref[1]), srgbByte(ref[2]), 255]
        assertClose(px(out, 16, 8, 8), want, 2, label)
    }

    // BGRA input: byte order is B, G, R, A in sRGB; output target is RGBA sRGB.
    var bgra = [UInt8]()
    for _ in 0..<(8 * 8) {
        bgra.append(contentsOf: [32, 128, 220, 255])
    }
    push(
        surface,
        ByteFrame(width: 8, height: 8, format: .bgra, color: ColorInfo(matrix: .bt709, transfer: .srgb), planes: [bgra, []]),
        100
    )
    let outBGRA = drawOne(gpu, pipe, fullDraw(surface, 8.0, 8.0), 8, 8, [0, 0, 0, 1])
    assertClose(px(outBGRA, 8, 4, 4), [220, 128, 32, 255], 1, "bgra channel order")

    // 2. Sharpness: 1px vertical luma stripes at 1:1 device pixels must not blur into grey.
    var luma = [UInt8](repeating: 0, count: 16 * 16)
    for i in 0..<(16 * 16) {
        luma[i] = (i % 2 == 0) ? 235 : 16
    }
    push(
        surface,
        ByteFrame(
            width: 16,
            height: 16,
            format: .nv12Video,
            color: ColorInfo(matrix: .bt709, transfer: .bt709),
            planes: [luma, [UInt8](repeating: 128, count: 16 * 8)]
        ),
        101
    )
    let stripes = drawOne(gpu, pipe, fullDraw(surface, 16.0, 16.0), 16, 16, [0, 0, 0, 1])
    assertClose(px(stripes, 16, 4, 8), [255, 255, 255, 255], 2, "1:1 white stripe")
    assertClose(px(stripes, 16, 5, 8), [0, 0, 0, 255], 2, "1:1 black stripe")

    // 3. Aspect fit, fill, rounded corners (local to the node), clip and opacity.
    push(surface, nv12Solid(32, 16, 235, 128, 128, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709)), 102)
    let fittedDraw = fullDraw(surface, 32.0, 32.0)
    let fitted = drawOne(gpu, pipe, fittedDraw, 32, 32, [0, 0, 0, 1])
    assertClose(px(fitted, 32, 16, 2), [0, 0, 0, 255], 1, "letterbox top bar")
    assertClose(px(fitted, 32, 16, 16), [255, 255, 255, 255], 2, "fitted centre")

    var filledRounded = fullDraw(surface, 32.0, 32.0)
    filledRounded.fit = .fill
    filledRounded.radii = [8.0, 8.0, 8.0, 8.0]
    let filled = drawOne(gpu, pipe, filledRounded, 32, 32, [0, 0, 0, 1])
    assertClose(px(filled, 32, 16, 2), [255, 255, 255, 255], 2, "filled top edge inside corner")
    assertClose(px(filled, 32, 0, 0), [0, 0, 0, 255], 2, "rounded corner outside")

    var clippedDraw = fullDraw(surface, 32.0, 16.0)
    clippedDraw.clip = [0.0, 0.0, 16.0, 16.0]
    clippedDraw.opacity = 0.5
    let clipped = drawOne(gpu, pipe, clippedDraw, 32, 16, [0, 0, 0, 1])
    let half = srgbByte(0.5)
    assertClose(px(clipped, 32, 8, 8), [half, half, half, 255], 3, "half opacity over black")
    assertClose(px(clipped, 32, 24, 8), [0, 0, 0, 255], 1, "clipped half")

    // 4. Retention and completion: rapid pushes before draw keep only the newest frame.
    for id in UInt64(200)..<220 {
        push(surface, syntheticSurfaceFrame(64, 36, id), id)
    }
    _ = drawOne(gpu, pipe, fullDraw(surface, 64.0, 36.0), 64, 36, [0, 0, 0, 1])
    let expectedCompleted = surface.counts().0
    waitCompleted(gpu, surface, expectedCompleted)
    let latestTiming = surface.timing()!
    #expect(latestTiming.frameId == 219)
    #expect(latestTiming.completedAt != nil)
    #expect(latestTiming.completedAt! >= latestTiming.submittedAt)
    if gpu.metalDevice.timestampQueryEnabled {
        let a = latestTiming.gpuStartSeconds!
        let b = latestTiming.gpuEndSeconds!
        #expect(b >= a && a > 0.0, "expected monotonic GPU timestamps: \(latestTiming)")
    }
    let observedDone = seenLock.withLock {
        seen.contains { $0.frameId == 219 && $0.completedAt != nil }
    }
    #expect(observedDone)

    // Evicting the surface from prepared draws drops cached textures once GPU work finishes.
    surface.clear()
    pipe.prepare(gpu.metalDevice, gpu.metalQueue, [], (16, 16))
    _ = gpu.metalDevice.poll(.waitIndefinitely())
}

@Suite("NativeSurface GPU Integration Tests")
struct NativeSurfaceIntegrationTests {
    #if canImport(Metal)
    @Test("queued video frames then readback")
    func queuedVideoFramesThenReadback() {
        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let surface = NativeSurface()

        // Nine draws without waiting in between: more than TIMING_SLOTS (8).
        for id in UInt64(1)...9 {
            _ = surface.pushBytes(syntheticSurfaceFrame(64, 36, id), id)
            let target = Offscreen(gpu.metalDevice, 64, 36)
            pipe.prepare(gpu.metalDevice, gpu.metalQueue, [fullDraw(surface, 64.0, 36.0)], (64, 36))
            let encoder = gpu.metalDevice.createCommandEncoder()
            let pass = encoder.beginRenderPass(
                colorAttachments: [MetalColorAttachment(view: target.view, load: .clear(r: 0, g: 0, b: 0, a: 1))],
                timestampWrites: pipe.timestampWrites()
            )
            pipe.draw(pass, 0)
            pass.end()
            pipe.submit(gpu.metalQueue, encoder)
        }

        // Now block on a readback, while timestamp callbacks from the queued draws also run.
        _ = surface.pushBytes(syntheticSurfaceFrame(64, 36, 10), 10)
        _ = drawOne(gpu, pipe, fullDraw(surface, 64.0, 36.0), 64, 36, [0, 0, 0, 1])
        waitCompleted(gpu, surface, 10)
        #expect(surface.timing()?.frameId == 10)
    }

    @Test("video GPU colour, sharpness, geometry and lifetime")
    func videoGpuColourSharpnessGeometryAndLifetime() {
        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)

        checkSurfaceSuite(gpu, pipe) { s, f, id in
            guard case .success = s.pushBytes(f, id) else {
                Issue.record("pushBytes failed")
                return
            }
        }

        #if os(macOS)
        // Zero-copy IOSurface-backed CVPixelBuffer path via CVMetalTextureCache.
        checkSurfaceSuite(gpu, pipe) { s, f, id in
            guard case .success(let pb) = PixelBuffer.fromBytes(f),
                  case .success = s.push(pb, id)
            else {
                Issue.record("PixelBuffer.fromBytes / push failed")
                return
            }
        }
        #expect(pipe.livePlanes() == 0, "CVMetalTexture planes leaked after clear + poll")

        // Also test PixelBuffer.fromIOSurface wrapping an existing IOSurface without copying.
        let s = NativeSurface()
        if case .success(let pb) = PixelBuffer.fromBytes(
            nv12Solid(32, 32, 82, 90, 240, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709))
        ), let io = CVPixelBufferGetIOSurface(pb.cvBuffer) {
            let rawIO = io.toOpaque()
            if case .success(let wrapped) = PixelBuffer.fromIOSurface(
                rawIO,
                ColorInfo(matrix: .bt709, transfer: .bt709)
            ) {
                _ = s.push(wrapped, 1)
                let out = drawOne(gpu, pipe, fullDraw(s, 32.0, 32.0), 32, 32, [0, 0, 0, 1])
                let ref = nv12Reference(82, 90, 240, .nv12Video, ColorInfo(matrix: .bt709, transfer: .bt709))
                assertClose(px(out, 32, 16, 16), [srgbByte(ref[0]), srgbByte(ref[1]), srgbByte(ref[2]), 255], 2, "IOSurface import")
            }
        }
        pipe.prepare(gpu.metalDevice, gpu.metalQueue, [], (16, 16))
        _ = gpu.metalDevice.poll(.waitIndefinitely())
        #expect(pipe.livePlanes() == 0)
        #endif
    }

    @Test("mirrored video is exact, cropped centred and toggles without a new frame")
    func mirroredVideoIsExactCroppedCentredAndTogglesWithoutANewFrame() {
        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)
        let surface = NativeSurface()
        let wokenLock = NSLock()
        nonisolated(unsafe) var woken = 0
        surface.setWaker {
            wokenLock.lock()
            woken += 1
            wokenLock.unlock()
        }

        // 4x2 BGRA with four distinct columns: red, green, blue, white.
        let cols: [[UInt8]] = [
            [0, 0, 255, 255],
            [0, 255, 0, 255],
            [255, 0, 0, 255],
            [255, 255, 255, 255],
        ]
        var bgra = [UInt8]()
        for _ in 0..<2 {
            for col in cols {
                bgra.append(contentsOf: col)
            }
        }
        _ = surface.pushBytes(
            ByteFrame(width: 4, height: 2, format: .bgra, color: ColorInfo(matrix: .bt709, transfer: .srgb), planes: [bgra, []]),
            1
        )
        #expect(!surface.isMirrored())
        #expect(woken == 1)

        let normal = drawOne(gpu, pipe, fullDraw(surface, 4.0, 2.0), 4, 2, [0, 0, 0, 1])
        assertClose(px(normal, 4, 0, 0), [255, 0, 0, 255], 1, "unmirrored col 0")
        assertClose(px(normal, 4, 1, 0), [0, 255, 0, 255], 1, "unmirrored col 1")
        assertClose(px(normal, 4, 2, 0), [0, 0, 255, 255], 1, "unmirrored col 2")
        assertClose(px(normal, 4, 3, 0), [255, 255, 255, 255], 1, "unmirrored col 3")

        // Flip without pushing a new frame: cached textures stay, waker fires once, columns reverse.
        surface.setMirrored(true)
        surface.setMirrored(true)
        #expect(surface.isMirrored())
        #expect(woken == 2, "no-op setMirrored must not wake")
        let flipped = drawOne(gpu, pipe, fullDraw(surface, 4.0, 2.0), 4, 2, [0, 0, 0, 1])
        assertClose(px(flipped, 4, 0, 0), [255, 255, 255, 255], 1, "mirrored col 0")
        assertClose(px(flipped, 4, 1, 0), [0, 0, 255, 255], 1, "mirrored col 1")
        assertClose(px(flipped, 4, 2, 0), [0, 255, 0, 255], 1, "mirrored col 2")
        assertClose(px(flipped, 4, 3, 0), [255, 0, 0, 255], 1, "mirrored col 3")

        // Fill into a 2x2 square crops the outer columns (red and white) and flips the middle two.
        var fill = fullDraw(surface, 2.0, 2.0)
        fill.fit = .fill
        let cropped = drawOne(gpu, pipe, fill, 2, 2, [0, 0, 0, 1])
        assertClose(px(cropped, 2, 0, 0), [0, 0, 255, 255], 1, "cropped mirrored left is col 2")
        assertClose(px(cropped, 2, 1, 0), [0, 255, 0, 255], 1, "cropped mirrored right is col 1")
    }
    #endif

    @Test("orientations come from quarter-turn transforms only")
    func orientationsComeFromQuarterTurnTransformsOnly() {
        #expect(SurfaceOrient.fromTransform(1.0, 0.0, 0.0, 1.0) == .UP)
        let cw90 = SurfaceOrient.fromTransform(0.0, 1.0, -1.0, 0.0)
        #expect(cw90.swaps())
        #expect(cw90.upright([1920, 1080]) == [1080, 1920])
        let rot180 = SurfaceOrient.fromTransform(-1.0, 0.0, 0.0, -1.0)
        #expect(!rot180.swaps())
        #expect(rot180.upright([1920, 1080]) == [1920, 1080])
        // Arbitrary scale or skew falls back to upright rather than distorting the picture.
        #expect(SurfaceOrient.fromTransform(2.0, 0.0, 0.0, 2.0) == .UP)
        #expect(SurfaceOrient.fromTransform(0.7, 0.7, -0.7, 0.7) == .UP)
    }

    #if canImport(Metal)
    @Test("oriented frames draw like frames turned upright")
    func orientedFramesDrawLikeFramesTurnedUpright() {
        func bgra(_ w: UInt32, _ h: UInt32, _ at: (UInt32, UInt32) -> [UInt8]) -> ByteFrame {
            var bytes = [UInt8]()
            bytes.reserveCapacity(Int(w * h * 4))
            for y in 0..<h {
                for x in 0..<w {
                    let c = at(x, y)
                    bytes.append(contentsOf: [c[2], c[1], c[0], 255])
                }
            }
            return ByteFrame(width: w, height: h, format: .bgra, color: ColorInfo(matrix: .bt709, transfer: .srgb), planes: [bytes, []])
        }

        // Upright picture is 2x4 (portrait), with four distinct corners.
        let uprightAt: (UInt32, UInt32) -> [UInt8] = { x, y in
            switch (x < 1, y < 2) {
            case (true, true): return [255, 0, 0]     // top-left: red
            case (false, true): return [0, 255, 0]    // top-right: green
            case (true, false): return [0, 0, 255]    // bottom-left: blue
            case (false, false): return [255, 255, 0] // bottom-right: yellow
            }
        }
        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)

        let refSurface = NativeSurface()
        _ = refSurface.pushBytes(bgra(2, 4, uprightAt), 1)
        let reference = drawOne(gpu, pipe, fullDraw(refSurface, 2.0, 4.0), 2, 4, [0, 0, 0, 1])

        // Every QuickTime orientation a phone or screen recorder writes: 90° CW, 180°, 90° CCW,
        // and horizontally flipped portrait.
        let cases: [(String, (Double, Double, Double, Double), UInt32, UInt32, (UInt32, UInt32) -> [UInt8])] = [
            ("90cw", (0.0, 1.0, -1.0, 0.0), 4, 2, { bx, by in uprightAt(1 - by, bx) }),
            ("180", (-1.0, 0.0, 0.0, -1.0), 2, 4, { bx, by in uprightAt(1 - bx, 3 - by) }),
            ("90ccw", (0.0, -1.0, 1.0, 0.0), 4, 2, { bx, by in uprightAt(by, 3 - bx) }),
            ("flip", (-1.0, 0.0, 0.0, 1.0), 2, 4, { bx, by in uprightAt(1 - bx, by) }),
        ]

        for (name, t, bw, bh, stored) in cases {
            let orient = SurfaceOrient.fromTransform(t.0, t.1, t.2, t.3)
            let s = NativeSurface()
            _ = s.pushBytesOriented(bgra(bw, bh, stored), 1, orient)
            #expect(s.size() == (2, 4), "\(name): upright size")
            let got = drawOne(gpu, pipe, fullDraw(s, 2.0, 4.0), 2, 4, [0, 0, 0, 1])
            for y in UInt32(0)..<4 {
                for x in UInt32(0)..<2 {
                    assertClose(px(got, 2, x, y), px(reference, 2, x, y), 1, "\(name) at (\(x),\(y))")
                }
            }

            // Letterbox fit into a 4x4 square uses the upright 2:4 aspect, leaving black bars left/right.
            let fitted = drawOne(gpu, pipe, fullDraw(s, 4.0, 4.0), 4, 4, [0, 0, 0, 1])
            assertClose(px(fitted, 4, 0, 2), [0, 0, 0, 255], 1, "\(name) pillarbox")
            assertClose(px(fitted, 4, 1, 0), [255, 0, 0, 255], 1, "\(name) fitted top-left")
            assertClose(px(fitted, 4, 2, 3), [255, 255, 0, 255], 1, "\(name) fitted bottom-right")
        }

        // Front-camera preview on a portrait phone: 90° CW buffer + horizontal mirror in upright space.
        let s = NativeSurface()
        _ = s.pushBytesOriented(bgra(4, 2) { bx, by in uprightAt(1 - by, bx) }, 1, SurfaceOrient.fromTransform(0.0, 1.0, -1.0, 0.0))
        s.setMirrored(true)
        let mirrored = drawOne(gpu, pipe, fullDraw(s, 2.0, 4.0), 2, 4, [0, 0, 0, 1])
        assertClose(px(mirrored, 2, 0, 0), [0, 255, 0, 255], 1, "mirrored top-left is green")
        assertClose(px(mirrored, 2, 1, 0), [255, 0, 0, 255], 1, "mirrored top-right is red")
        assertClose(px(mirrored, 2, 0, 3), [255, 255, 0, 255], 1, "mirrored bottom-left is yellow")
        assertClose(px(mirrored, 2, 1, 3), [0, 0, 255, 255], 1, "mirrored bottom-right is blue")
    }
    #endif

    #if os(macOS)
    @Test("rotated clip buffers draw upright like its poster")
    func rotatedClipBuffersDrawUprightLikeItsPoster() {
        let clipPath = VideoTestFixtures.writeFixture(
            name: "quadrants-rot90.mp4",
            base64: VideoTestFixtures.quadrantsRot90MP4Base64
        )
        let clip = MediaSource.file(clipPath)
        guard case .success(let (poster, raw, orient)) = videoTestFrames(clip, 0.1) else {
            Issue.record("expected videoTestFrames to succeed for quadrants-rot90.mp4")
            return
        }
        #expect((poster.width, poster.height) == (32, 64))
        #expect((raw.width, raw.height) == (64, 32))
        #expect(orient.swaps())

        let gpu = Gpu.headless()
        let pipe = SurfaceRenderer(gpu.metalDevice, OFFSCREEN_FORMAT)

        let posterSurface = NativeSurface()
        _ = posterSurface.pushBytes(poster, 1)
        let want = drawOne(gpu, pipe, fullDraw(posterSurface, 32.0, 64.0), 32, 64, [0, 0, 0, 1])

        let playerSurface = NativeSurface()
        _ = playerSurface.pushBytesOriented(raw, 1, orient)
        let got = drawOne(gpu, pipe, fullDraw(playerSurface, 32.0, 64.0), 32, 64, [0, 0, 0, 1])

        for (x, y, label) in [(8, 16, "top-left"), (24, 16, "top-right"), (8, 48, "bottom-left"), (24, 48, "bottom-right")] as [(UInt32, UInt32, String)] {
            assertClose(px(got, 32, x, y), px(want, 32, x, y), 4, label)
        }
    }
    #endif
}
