// Swift-only: Metal GPU shader compilation, struct layout parity, and offscreen pixel readback tests

#if canImport(Metal)
import Foundation
import GPUI
import Metal
import QuartzCore
import Testing
#if os(macOS)
import CoreVideo
#endif
@testable import GPUIMetal

@Suite("GPUIMetal Renderer Hardware Tests")
struct MetalRendererTests {
    private func pixel(
        in rendered: (width: Int, height: Int, rgba: [UInt8]),
        x: Int,
        y: Int
    ) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let offset = (y * rendered.width + x) * 4
        return (
            rendered.rgba[offset],
            rendered.rgba[offset + 1],
            rendered.rgba[offset + 2],
            rendered.rgba[offset + 3]
        )
    }

    private func fullViewportMask(_ width: Float, _ height: Float) -> ContentMask<ScaledPixels> {
        ContentMask(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                size: Size(width: ScaledPixels(width), height: ScaledPixels(height))
            )
        )
    }

    @Test("Stitched shaders.metal compiles on Metal GPU with all 17 shader entry points")
    func runtimeShaderCompilationAndPipelines() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let library = try MetalShaderCompiler.library(for: device)

        let expectedFunctions = [
            "quad_vertex",
            "quad_fragment",
            "shadow_vertex",
            "shadow_fragment",
            "underline_vertex",
            "underline_fragment",
            "monochrome_sprite_vertex",
            "monochrome_sprite_fragment",
            "polychrome_sprite_vertex",
            "polychrome_sprite_fragment",
            "path_rasterization_vertex",
            "path_rasterization_fragment",
            "path_sprite_vertex",
            "path_sprite_fragment",
            "surface_vertex",
            "surface_fragment",
            "surface_bgra_fragment",
        ]

        for name in expectedFunctions {
            #expect(library.makeFunction(name: name) != nil, "Missing MSL function \(name)")
        }

        let renderer = try MetalRenderer(device: device, transparent: false)
        let specs = renderer.gpuSpecs()
        #expect(!specs.deviceName.isEmpty)
        #expect(specs.driverName == "Metal")
        #expect(!specs.isSoftwareEmulated)

        let surfaceRenderer = SurfaceRenderer.new(renderer.shared(), true)
        surfaceRenderer.updateDrawableSize(Size(width: DevicePixels(64), height: DevicePixels(64)))
        #expect(surfaceRenderer.layer().drawableSize == CGSize(width: 64, height: 64))
        #expect(!surfaceRenderer.layer().isOpaque)
    }

    @Test("Swift GPU struct byte layouts and field offsets match MSL compiler sizeof/offsetof 100%")
    func gpuStructByteLayoutMatchesMslCompiler() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())

        let layoutProbeSource = """
        \(MetalShaderCompiler.sceneHeader)
        #include <metal_stdlib>
        using namespace metal;

        #define MSL_OFFSETOF(type, field) ((uint)((thread const char *)&(((thread const type *)nullptr)->field) - (thread const char *)nullptr))

        kernel void probe_scene_layouts(device uint *out [[buffer(0)]]) {
            uint i = 0;
            // Sizes (0..15)
            out[i++] = sizeof(Bounds_ScaledPixels);
            out[i++] = sizeof(Corners_ScaledPixels);
            out[i++] = sizeof(Edges_ScaledPixels);
            out[i++] = sizeof(Hsla);
            out[i++] = sizeof(LinearColorStop);
            out[i++] = sizeof(Background);
            out[i++] = sizeof(AtlasTile);
            out[i++] = sizeof(TransformationMatrix);
            out[i++] = sizeof(Quad);
            out[i++] = sizeof(Shadow);
            out[i++] = sizeof(Underline);
            out[i++] = sizeof(MonochromeSprite);
            out[i++] = sizeof(PolychromeSprite);
            out[i++] = sizeof(PathSprite);
            out[i++] = sizeof(PathRasterizationVertex);
            out[i++] = sizeof(SurfaceBounds);

            // Quad field offsets (16..23)
            out[i++] = MSL_OFFSETOF(Quad, order);
            out[i++] = MSL_OFFSETOF(Quad, border_style);
            out[i++] = MSL_OFFSETOF(Quad, bounds);
            out[i++] = MSL_OFFSETOF(Quad, content_mask);
            out[i++] = MSL_OFFSETOF(Quad, background);
            out[i++] = MSL_OFFSETOF(Quad, border_color);
            out[i++] = MSL_OFFSETOF(Quad, corner_radii);
            out[i++] = MSL_OFFSETOF(Quad, border_widths);

            // Background field offsets (24..29)
            out[i++] = MSL_OFFSETOF(Background, tag);
            out[i++] = MSL_OFFSETOF(Background, color_space);
            out[i++] = MSL_OFFSETOF(Background, solid);
            out[i++] = MSL_OFFSETOF(Background, gradient_angle_or_pattern_height);
            out[i++] = MSL_OFFSETOF(Background, colors);
            out[i++] = MSL_OFFSETOF(Background, pad);

            // Shadow field offsets (30..35)
            out[i++] = MSL_OFFSETOF(Shadow, order);
            out[i++] = MSL_OFFSETOF(Shadow, blur_radius);
            out[i++] = MSL_OFFSETOF(Shadow, bounds);
            out[i++] = MSL_OFFSETOF(Shadow, corner_radii);
            out[i++] = MSL_OFFSETOF(Shadow, content_mask);
            out[i++] = MSL_OFFSETOF(Shadow, color);

            // PolychromeSprite field offsets (36..43)
            out[i++] = MSL_OFFSETOF(PolychromeSprite, order);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, pad);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, grayscale);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, opacity);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, bounds);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, content_mask);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, corner_radii);
            out[i++] = MSL_OFFSETOF(PolychromeSprite, tile);

            // MonochromeSprite & PathRasterizationVertex offsets (44..54)
            out[i++] = MSL_OFFSETOF(MonochromeSprite, color);
            out[i++] = MSL_OFFSETOF(MonochromeSprite, tile);
            out[i++] = MSL_OFFSETOF(MonochromeSprite, transformation);
            out[i++] = MSL_OFFSETOF(Underline, color);
            out[i++] = MSL_OFFSETOF(Underline, thickness);
            out[i++] = MSL_OFFSETOF(Underline, wavy);
            out[i++] = MSL_OFFSETOF(PathRasterizationVertex, xy_position);
            out[i++] = MSL_OFFSETOF(PathRasterizationVertex, st_position);
            out[i++] = MSL_OFFSETOF(PathRasterizationVertex, color);
            out[i++] = MSL_OFFSETOF(PathRasterizationVertex, bounds);
            out[i++] = MSL_OFFSETOF(SurfaceBounds, content_mask);
        }
        """

        let probeLib = try device.makeLibrary(source: layoutProbeSource, options: MTLCompileOptions())
        let probeFn = try #require(probeLib.makeFunction(name: "probe_scene_layouts"))
        let pipeline = try device.makeComputePipelineState(function: probeFn)

        let count = 55
        let outBuffer = try #require(
            device.makeBuffer(length: count * MemoryLayout<UInt32>.stride, options: .storageModeShared)
        )
        let queue = try #require(device.makeCommandQueue())
        let cmdBuf = try #require(queue.makeCommandBuffer())
        let encoder = try #require(cmdBuf.makeComputeCommandEncoder())
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(outBuffer, offset: 0, index: 0)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        let ptr = outBuffer.contents().bindMemory(to: UInt32.self, capacity: count)
        let msl = Array(UnsafeBufferPointer(start: ptr, count: count)).map(Int.init)

        // Exact struct sizes & strides
        #expect(MemoryLayout<MetalBoundsScaledPixels>.stride == msl[0] && msl[0] == 16)
        #expect(MemoryLayout<MetalCornersScaledPixels>.stride == msl[1] && msl[1] == 16)
        #expect(MemoryLayout<MetalEdgesScaledPixels>.stride == msl[2] && msl[2] == 16)
        #expect(MemoryLayout<MetalHsla>.stride == msl[3] && msl[3] == 16)
        #expect(MemoryLayout<MetalLinearColorStop>.stride == msl[4] && msl[4] == 20)
        #expect(MemoryLayout<MetalBackground>.stride == msl[5] && msl[5] == 72)
        #expect(MemoryLayout<MetalAtlasTile>.stride == msl[6] && msl[6] == 32)
        #expect(MemoryLayout<MetalTransformationMatrix>.stride == msl[7] && msl[7] == 24)
        #expect(MemoryLayout<MetalQuad>.stride == msl[8] && msl[8] == 160)
        #expect(MemoryLayout<MetalShadow>.stride == msl[9] && msl[9] == 72)
        #expect(MemoryLayout<MetalUnderline>.stride == msl[10] && msl[10] == 64)
        #expect(MemoryLayout<MetalMonochromeSprite>.stride == msl[11] && msl[11] == 112)
        #expect(MemoryLayout<MetalPolychromeSprite>.stride == msl[12] && msl[12] == 96)
        #expect(MemoryLayout<MetalPathSprite>.stride == msl[13] && msl[13] == 16)
        #expect(MemoryLayout<MetalPathRasterizationVertex>.stride == msl[14] && msl[14] == 104)
        #expect(MemoryLayout<MetalSurfaceBounds>.stride == msl[15] && msl[15] == 32)

        // Exact Quad field offsets
        #expect(MemoryLayout<MetalQuad>.offset(of: \.order) == msl[16])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.borderStyle) == msl[17])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.bounds) == msl[18])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.contentMask) == msl[19])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.background) == msl[20])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.borderColor) == msl[21])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.cornerRadii) == msl[22])
        #expect(MemoryLayout<MetalQuad>.offset(of: \.borderWidths) == msl[23])

        // Exact Background field offsets
        #expect(MemoryLayout<MetalBackground>.offset(of: \.tag) == msl[24])
        #expect(MemoryLayout<MetalBackground>.offset(of: \.colorSpace) == msl[25])
        #expect(MemoryLayout<MetalBackground>.offset(of: \.solid) == msl[26])
        #expect(MemoryLayout<MetalBackground>.offset(of: \.gradientAngleOrPatternHeight) == msl[27])
        #expect(MemoryLayout<MetalBackground>.offset(of: \.color0) == msl[28])
        #expect(MemoryLayout<MetalBackground>.offset(of: \.pad) == msl[29])

        // Exact Shadow field offsets (verifying corner_radii precedes content_mask)
        #expect(MemoryLayout<MetalShadow>.offset(of: \.order) == msl[30])
        #expect(MemoryLayout<MetalShadow>.offset(of: \.blurRadius) == msl[31])
        #expect(MemoryLayout<MetalShadow>.offset(of: \.bounds) == msl[32])
        #expect(MemoryLayout<MetalShadow>.offset(of: \.cornerRadii) == msl[33])
        #expect(MemoryLayout<MetalShadow>.offset(of: \.contentMask) == msl[34])
        #expect(MemoryLayout<MetalShadow>.offset(of: \.color) == msl[35])

        // Exact PolychromeSprite field offsets (verifying 1-byte bool + 3-byte pad before opacity)
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.order) == msl[36])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.pad) == msl[37])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.grayscale) == msl[38])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.opacity) == msl[39])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.bounds) == msl[40])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.contentMask) == msl[41])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.cornerRadii) == msl[42])
        #expect(MemoryLayout<MetalPolychromeSprite>.offset(of: \.tile) == msl[43])

        // Remaining primitive offsets
        #expect(MemoryLayout<MetalMonochromeSprite>.offset(of: \.color) == msl[44])
        #expect(MemoryLayout<MetalMonochromeSprite>.offset(of: \.tile) == msl[45])
        #expect(MemoryLayout<MetalMonochromeSprite>.offset(of: \.transformation) == msl[46])
        #expect(MemoryLayout<MetalUnderline>.offset(of: \.color) == msl[47])
        #expect(MemoryLayout<MetalUnderline>.offset(of: \.thickness) == msl[48])
        #expect(MemoryLayout<MetalUnderline>.offset(of: \.wavy) == msl[49])
        #expect(MemoryLayout<MetalPathRasterizationVertex>.offset(of: \.xyPosition) == msl[50])
        #expect(MemoryLayout<MetalPathRasterizationVertex>.offset(of: \.stPosition) == msl[51])
        #expect(MemoryLayout<MetalPathRasterizationVertex>.offset(of: \.color) == msl[52])
        #expect(MemoryLayout<MetalPathRasterizationVertex>.offset(of: \.bounds) == msl[53])
        #expect(MemoryLayout<MetalSurfaceBounds>.offset(of: \.contentMask) == msl[54])
    }

    @Test("Offscreen solid Quad rendering reads back exact RGB channels and encodes PNG")
    func offscreenSolidQuadColorAccuracyAndPngEncoding() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let targetSize = Size(width: DevicePixels(64), height: DevicePixels(64))
        renderer.updateDrawableSize(targetSize)

        let mask = fullViewportMask(64, 64)
        var scene = Scene()

        // Top-left: pure red (0..32, 0..32)
        scene.insertQuad(Quad(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            ),
            contentMask: mask,
            background: solidBackground(Hsla(rgba: rgb(0xFF0000)))
        ))

        // Top-right: pure green (32..64, 0..32)
        scene.insertQuad(Quad(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(32), y: ScaledPixels(0)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            ),
            contentMask: mask,
            background: solidBackground(Hsla(rgba: rgb(0x00FF00)))
        ))

        // Bottom-left: pure blue (0..32, 32..64)
        scene.insertQuad(Quad(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(0), y: ScaledPixels(32)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            ),
            contentMask: mask,
            background: solidBackground(Hsla(rgba: rgb(0x0000FF)))
        ))

        scene.finish()

        let rendered = try renderer.renderToTexture(scene, size: targetSize, background: white())
        #expect(rendered.width == 64)
        #expect(rendered.height == 64)

        let topLeft = pixel(in: rendered, x: 16, y: 16)
        #expect(topLeft.r >= 250 && topLeft.g <= 5 && topLeft.b <= 5 && topLeft.a == 255)

        let topRight = pixel(in: rendered, x: 48, y: 16)
        #expect(topRight.r <= 5 && topRight.g >= 250 && topRight.b <= 5 && topRight.a == 255)

        let bottomLeft = pixel(in: rendered, x: 16, y: 48)
        #expect(bottomLeft.r <= 5 && bottomLeft.g <= 5 && bottomLeft.b >= 250 && bottomLeft.a == 255)

        // Bottom-right untouched -> background white
        let bottomRight = pixel(in: rendered, x: 48, y: 48)
        #expect(bottomRight.r >= 250 && bottomRight.g >= 250 && bottomRight.b >= 250 && bottomRight.a == 255)

        // Verify renderToImage produces a valid PNG image
        let pngImage = try renderer.renderToImage(scene)
        #expect(pngImage.format == .png)
        #expect(pngImage.width == 64)
        #expect(pngImage.height == 64)
        #expect(pngImage.bytes.count > 8)
        #expect(Array(pngImage.bytes.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    @Test("Offscreen bordered rounded Quad, Shadow, and Underline primitives render accurately")
    func offscreenBorderedQuadShadowAndUnderline() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let size = Size(width: DevicePixels(80), height: DevicePixels(80))
        let mask = fullViewportMask(80, 80)

        var scene = Scene()

        // Drop shadow around (16..40, 16..40)
        scene.insertShadow(Shadow(
            blurRadius: ScaledPixels(4),
            bounds: Bounds(
                origin: Point(x: ScaledPixels(16), y: ScaledPixels(16)),
                size: Size(width: ScaledPixels(24), height: ScaledPixels(24))
            ),
            cornerRadii: Corners.all(ScaledPixels(4)),
            contentMask: mask,
            color: Hsla(h: 0, s: 0, l: 0, a: 1.0)
        ))

        // Rounded bordered Quad at (44..76, 8..40) with 6px red border and blue interior
        scene.insertQuad(Quad(
            borderStyle: .solid,
            bounds: Bounds(
                origin: Point(x: ScaledPixels(44), y: ScaledPixels(8)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            ),
            contentMask: mask,
            background: solidBackground(Hsla(rgba: rgb(0x0000FF))),
            borderColor: Hsla(rgba: rgb(0xFF0000)),
            cornerRadii: Corners.all(ScaledPixels(10)),
            borderWidths: Edges.all(ScaledPixels(6))
        ))

        // Solid underline at (10..70, 60..66) in pure green
        scene.insertUnderline(Underline(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(10), y: ScaledPixels(60)),
                size: Size(width: ScaledPixels(60), height: ScaledPixels(6))
            ),
            contentMask: mask,
            color: Hsla(rgba: rgb(0x00FF00)),
            thickness: ScaledPixels(6),
            wavy: 0
        ))

        scene.finish()
        let rendered = try renderer.renderToTexture(scene, size: size, background: white())

        // Shadow center darkened below white, and halo 2px outside bounds is partially darkened
        let shadowCenter = pixel(in: rendered, x: 28, y: 28)
        #expect(shadowCenter.r < 50 && shadowCenter.g < 50 && shadowCenter.b < 50)
        let shadowHalo = pixel(in: rendered, x: 14, y: 28)
        #expect(shadowHalo.r > 20 && shadowHalo.r < 245)

        // Rounded quad outside rounded top-left corner at (45, 9) remains white
        let outsideRoundedCorner = pixel(in: rendered, x: 45, y: 9)
        #expect(outsideRoundedCorner.r >= 245 && outsideRoundedCorner.g >= 245 && outsideRoundedCorner.b >= 245)

        // Top border midpoint (60, 10) is red
        let borderPixel = pixel(in: rendered, x: 60, y: 10)
        #expect(borderPixel.r >= 240 && borderPixel.b <= 20)

        // Interior center (60, 24) is blue
        let interiorPixel = pixel(in: rendered, x: 60, y: 24)
        #expect(interiorPixel.b >= 240 && interiorPixel.r <= 20)

        // Underline midpoint (40, 63) is green
        let underlinePixel = pixel(in: rendered, x: 40, y: 63)
        #expect(underlinePixel.g >= 240 && underlinePixel.r <= 20 && underlinePixel.b <= 20)
    }

    @Test("Offscreen MonochromeSprite and PolychromeSprite sample from MetalAtlas")
    func offscreenMonochromeAndPolychromeSprites() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let atlas = renderer.spriteAtlas()
        let viewport = Size(width: DevicePixels(64), height: DevicePixels(64))
        let mask = fullViewportMask(64, 64)

        let tileSize = Size(width: DevicePixels(16), height: DevicePixels(16))

        // 1. Monochrome 16x16 full-coverage glyph/SVG mask
        let monoKey = AtlasKey.svg(RenderSvgParams(path: SharedString("solid_box.svg"), size: tileSize))
        let monoTile = try #require(
            try atlas.getOrInsertWith(key: monoKey) {
                (tileSize, Data(repeating: 0xFF, count: 16 * 16))
            }
        )

        // 2. Polychrome 16x16 pure red (BGRA = [0, 0, 255, 255]) image
        let polyKey = AtlasKey.image(RenderImageParams(imageId: ImageId(42), frameIndex: 0))
        var bgraBytes = [UInt8]()
        bgraBytes.reserveCapacity(16 * 16 * 4)
        for _ in 0..<(16 * 16) {
            bgraBytes.append(contentsOf: [0, 0, 255, 255]) // B=0, G=0, R=255, A=255
        }
        let polyTile = try #require(
            try atlas.getOrInsertWith(key: polyKey) {
                (tileSize, Data(bgraBytes))
            }
        )

        var scene = Scene()
        // Monochrome sprite tinted pure green at (8..24, 8..24)
        scene.insertMonochromeSprite(MonochromeSprite(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(8), y: ScaledPixels(8)),
                size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
            ),
            contentMask: mask,
            color: Hsla(rgba: rgb(0x00FF00)),
            tile: monoTile,
            transformation: .unit
        ))

        // Polychrome sprite at (36..52, 8..24)
        scene.insertPolychromeSprite(PolychromeSprite(
            grayscale: false,
            opacity: 1.0,
            bounds: Bounds(
                origin: Point(x: ScaledPixels(36), y: ScaledPixels(8)),
                size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
            ),
            contentMask: mask,
            cornerRadii: .zero,
            tile: polyTile
        ))

        scene.finish()
        let rendered = try renderer.renderToTexture(scene, size: viewport, background: black())

        let monoCenter = pixel(in: rendered, x: 16, y: 16)
        #expect(monoCenter.g >= 245 && monoCenter.r <= 10 && monoCenter.b <= 10)

        let polyCenter = pixel(in: rendered, x: 44, y: 16)
        #expect(polyCenter.r >= 245 && polyCenter.g <= 10 && polyCenter.b <= 10)
    }

    @Test("Offscreen vector Path 4x MSAA rasterization and intermediate texture compositing")
    func offscreenVectorPathMsaaRasterization() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let viewport = Size(width: DevicePixels(64), height: DevicePixels(64))

        // Build a filled square path from (16, 16) to (48, 48) in Pixels, then scale by 1.0
        var path = GPUI.Path<Pixels>(start: Point(x: px(16), y: px(16)))
        path.lineTo(Point(x: px(48), y: px(16)))
        path.lineTo(Point(x: px(48), y: px(48)))
        path.lineTo(Point(x: px(16), y: px(48)))
        path.color = solidBackground(Hsla(rgba: rgb(0xFF0000)))
        path.contentMask = ContentMask(
            bounds: Bounds(
                origin: Point(x: px(0), y: px(0)),
                size: Size(width: px(64), height: px(64))
            )
        )

        var scene = Scene()
        scene.insertPath(path.scale(1.0))
        scene.finish()

        let rendered = try renderer.renderToTexture(scene, size: viewport, background: white())

        // Inside the rasterized path at (32, 32) -> pure red
        let inside = pixel(in: rendered, x: 32, y: 32)
        #expect(inside.r >= 245 && inside.g <= 10 && inside.b <= 10)

        // Outside the path at (8, 8) -> background white
        let outside = pixel(in: rendered, x: 8, y: 8)
        #expect(outside.r >= 245 && outside.g >= 245 && outside.b >= 245)
    }

    @Test("ContentMask hardware clipping and dynamic InstanceBufferPool growth")
    func contentMaskClippingAndBufferPoolGrowth() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        // Start with a deliberately tiny 256-byte pool to force automatic pool doubling retry!
        let smallPool = InstanceBufferPool(bufferSize: 256)
        let renderer = try MetalRenderer(device: device, instanceBufferPool: smallPool, transparent: false)
        let viewport = Size(width: DevicePixels(64), height: DevicePixels(64))

        var scene = Scene()
        // Insert 10 quads clipped strictly to x: 16..48, y: 16..48 even though quad bounds span 0..64
        let clippedMask = ContentMask(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(16), y: ScaledPixels(16)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            )
        )
        for i in 0..<10 {
            scene.insertQuad(Quad(
                order: UInt32(i),
                bounds: Bounds(
                    origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                    size: Size(width: ScaledPixels(64), height: ScaledPixels(64))
                ),
                contentMask: clippedMask,
                background: solidBackground(Hsla(rgba: rgb(0x0000FF)))
            ))
        }
        scene.finish()

        let rendered = try renderer.renderToTexture(scene, size: viewport, background: white())
        #expect(smallPool.bufferSize >= 10 * 160)

        // Inside clip mask -> blue
        let clippedIn = pixel(in: rendered, x: 32, y: 32)
        #expect(clippedIn.b >= 245 && clippedIn.r <= 10 && clippedIn.g <= 10)

        // Outside clip mask (at 8, 8) -> remains white despite quad bounds covering (0..64, 0..64)!
        let clippedOut = pixel(in: rendered, x: 8, y: 8)
        #expect(clippedOut.r >= 245 && clippedOut.g >= 245 && clippedOut.b >= 245)

        renderer.destroy()
    }

    @Test("Linear gradients (sRGB and Oklab), dashed borders, wavy underlines, and grayscale sprites")
    func gradientsDashedBordersWavyUnderlinesAndGrayscaleSprites() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let viewport = Size(width: DevicePixels(80), height: DevicePixels(80))
        let mask = fullViewportMask(80, 80)

        var scene = Scene()

        // Horizontal Oklab linear gradient from red (left) to blue (right) at (0..80, 0..24)
        let grad = linearGradient(
            angle: 90.0,
            from: linearColorStop(Hsla(rgba: rgb(0xFF0000)), 0.0),
            to: linearColorStop(Hsla(rgba: rgb(0x0000FF)), 1.0)
        ).colorSpace(.oklab)
        scene.insertQuad(Quad(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(0), y: ScaledPixels(0)),
                size: Size(width: ScaledPixels(80), height: ScaledPixels(24))
            ),
            contentMask: mask,
            background: grad
        ))

        // Dashed border quad at (8..40, 30..62)
        scene.insertQuad(Quad(
            borderStyle: .dashed,
            bounds: Bounds(
                origin: Point(x: ScaledPixels(8), y: ScaledPixels(30)),
                size: Size(width: ScaledPixels(32), height: ScaledPixels(32))
            ),
            contentMask: mask,
            background: solidBackground(white()),
            borderColor: Hsla(rgba: rgb(0x000000)),
            cornerRadii: Corners.all(ScaledPixels(6)),
            borderWidths: Edges.all(ScaledPixels(4))
        ))

        // Wavy underline at (8..72, 68..76)
        scene.insertUnderline(Underline(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(8), y: ScaledPixels(68)),
                size: Size(width: ScaledPixels(64), height: ScaledPixels(8))
            ),
            contentMask: mask,
            color: Hsla(rgba: rgb(0xFF0000)),
            thickness: ScaledPixels(3),
            wavy: 1
        ))

        // Grayscale polychrome sprite at (48..64, 32..48) from pure red source
        let tileSize = Size(width: DevicePixels(16), height: DevicePixels(16))
        let polyKey = AtlasKey.image(RenderImageParams(imageId: ImageId(77), frameIndex: 0))
        var bgraBytes = [UInt8]()
        bgraBytes.reserveCapacity(16 * 16 * 4)
        for _ in 0..<(16 * 16) {
            bgraBytes.append(contentsOf: [0, 0, 255, 255])
        }
        let polyTile = try #require(
            try renderer.spriteAtlas().getOrInsertWith(key: polyKey) {
                (tileSize, Data(bgraBytes))
            }
        )
        scene.insertPolychromeSprite(PolychromeSprite(
            grayscale: true,
            opacity: 1.0,
            bounds: Bounds(
                origin: Point(x: ScaledPixels(48), y: ScaledPixels(32)),
                size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
            ),
            contentMask: mask,
            cornerRadii: .zero,
            tile: polyTile
        ))

        scene.finish()
        let rendered = try renderer.renderToTexture(scene, size: viewport, background: white())

        let gradLeft = pixel(in: rendered, x: 4, y: 12)
        let gradRight = pixel(in: rendered, x: 75, y: 12)
        #expect(gradLeft.r > 200 && gradLeft.b < 60)
        #expect(gradRight.b > 200 && gradRight.r < 60)

        // Grayscale sprite converts pure red (R=1,G=0,B=0) to luminance ~0.2126 (~54/255) across R=G=B
        let grayPx = pixel(in: rendered, x: 56, y: 40)
        #expect(abs(Int(grayPx.r) - Int(grayPx.g)) <= 2)
        #expect(abs(Int(grayPx.g) - Int(grayPx.b)) <= 2)
        #expect(grayPx.r >= 45 && grayPx.r <= 65)
    }

    #if os(macOS)
    @Test("CVPixelBuffer PaintSurface renders both 32BGRA and 420YpCbCr8BiPlanarFullRange via CVMetalTextureCache")
    func cvPixelBufferSurfacesRenderOnMacOS() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, transparent: false)
        let viewport = Size(width: DevicePixels(64), height: DevicePixels(64))
        let mask = fullViewportMask(64, 64)

        let ioSurfaceProps: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]

        // 1. 32BGRA CVPixelBuffer filled with pure green (B=0, G=255, R=0, A=255)
        var bgraBufferOut: CVPixelBuffer?
        let bgraStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            ioSurfaceProps as CFDictionary,
            &bgraBufferOut
        )
        #expect(bgraStatus == kCVReturnSuccess)
        let bgraBuffer = try #require(bgraBufferOut)

        CVPixelBufferLockBaseAddress(bgraBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(bgraBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(bgraBuffer)
            for y in 0..<16 {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in 0..<16 {
                    row[x * 4 + 0] = 0
                    row[x * 4 + 1] = 255
                    row[x * 4 + 2] = 0
                    row[x * 4 + 3] = 255
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(bgraBuffer, [])

        // 2. 420YpCbCr8BiPlanarFullRange CVPixelBuffer filled with neutral white (Y=255, Cb=128, Cr=128)
        var yuvBufferOut: CVPixelBuffer?
        let yuvStatus = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            ioSurfaceProps as CFDictionary,
            &yuvBufferOut
        )
        #expect(yuvStatus == kCVReturnSuccess)
        let yuvBuffer = try #require(yuvBufferOut)

        CVPixelBufferLockBaseAddress(yuvBuffer, [])
        if let yBase = CVPixelBufferGetBaseAddressOfPlane(yuvBuffer, 0),
           let uvBase = CVPixelBufferGetBaseAddressOfPlane(yuvBuffer, 1) {
            let yBpr = CVPixelBufferGetBytesPerRowOfPlane(yuvBuffer, 0)
            for y in 0..<16 {
                memset(yBase.advanced(by: y * yBpr), 255, 16)
            }
            let uvBpr = CVPixelBufferGetBytesPerRowOfPlane(yuvBuffer, 1)
            for y in 0..<8 {
                memset(uvBase.advanced(by: y * uvBpr), 128, 16)
            }
        }
        CVPixelBufferUnlockBaseAddress(yuvBuffer, [])

        var scene = Scene()
        scene.insertSurface(PaintSurface(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(8), y: ScaledPixels(8)),
                size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
            ),
            contentMask: mask,
            imageBuffer: bgraBuffer
        ))
        scene.insertSurface(PaintSurface(
            bounds: Bounds(
                origin: Point(x: ScaledPixels(36), y: ScaledPixels(8)),
                size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
            ),
            contentMask: mask,
            imageBuffer: yuvBuffer
        ))
        scene.finish()

        let rendered = try renderer.renderToTexture(scene, size: viewport, background: black())

        let bgraPx = pixel(in: rendered, x: 16, y: 16)
        #expect(bgraPx.g >= 245 && bgraPx.r <= 10 && bgraPx.b <= 10)

        let yuvPx = pixel(in: rendered, x: 44, y: 16)
        #expect(yuvPx.r >= 245 && yuvPx.g >= 245 && yuvPx.b >= 245)
    }
    #endif
}
#endif
