// Swift-only: Adversarial stress testing for WebGPU renderer, atlas packing, buffer growth, and path rasterization

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Testing
import Foundation
import GPUI
@testable import GPUIWGPU

#if os(Linux)
import CWebGPU
#endif

@Suite("WgpuStressTests")
struct WgpuStressTests {

    // MARK: - Scenario 1: Atlas Bin-Packing & Texture Resizing Stress

    @Test
    func test_atlas_bin_packing_irregular_sizes_and_overlap_oracle() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(2048), height: DevicePixels(2048)))
        var allocatedBounds: [Bounds<DevicePixels>] = []

        // Irregular sizes to trigger shelf wrapping, best-fit shelf reuse, and new shelf allocation
        let sampleSizes: [(Int32, Int32)] = [
            (1, 1), (15, 30), (64, 64), (128, 256), (512, 128),
            (3, 17), (31, 31), (200, 50), (400, 100), (7, 19),
            (25, 60), (45, 12), (90, 90), (120, 30), (250, 40),
            (500, 70), (16, 16), (32, 48), (64, 12), (18, 55)
        ]

        var successCount = 0
        for i in 0..<1000 {
            let (w, h) = sampleSizes[i % sampleSizes.count]
            let requestedSize = Size(width: DevicePixels(w), height: DevicePixels(h))
            if let (_, bounds) = allocator.allocate(size: requestedSize) {
                successCount += 1

                // In-bounds oracle
                #expect(bounds.origin.x.value >= 0)
                #expect(bounds.origin.y.value >= 0)
                #expect(bounds.origin.x.value + bounds.size.width.value <= 2048)
                #expect(bounds.origin.y.value + bounds.size.height.value <= 2048)
                #expect(bounds.size.width.value == w)
                #expect(bounds.size.height.value == h)

                // Overlap oracle: no two allocated rectangles on this sheet can intersect
                for existing in allocatedBounds {
                    let noOverlap = (bounds.origin.x.value + bounds.size.width.value <= existing.origin.x.value) ||
                                    (existing.origin.x.value + existing.size.width.value <= bounds.origin.x.value) ||
                                    (bounds.origin.y.value + bounds.size.height.value <= existing.origin.y.value) ||
                                    (existing.origin.y.value + existing.size.height.value <= bounds.origin.y.value)
                    #expect(noOverlap, "Overlap detected between \(bounds) and \(existing)")
                }
                allocatedBounds.append(bounds)
            }
        }

        #expect(successCount > 50, "Expected at least 50 allocations in 2048x2048 sheet, got \(successCount)")
    }

    #if os(Linux)
    @Test
    func test_atlas_dynamic_sheet_expansion_and_cache_determinism() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let atlas = WgpuAtlas.new(device: context.device, queue: context.queue)

        var insertedTiles: [(AtlasKey, AtlasTile)] = []
        let irregularSizes: [(Int32, Int32)] = [
            (32, 32), (64, 64), (128, 128), (256, 128), (512, 128),
            (16, 32), (48, 48), (96, 64), (150, 75), (200, 100)
        ]

        // Insert 300 monochrome items to force multiple 1024x1024 texture sheets to be created
        for i in 0..<300 {
            let (w, h) = irregularSizes[i % irregularSizes.count]
            let key = AtlasKey.glyph(RenderGlyphParams(
                fontId: FontId(i / 50),
                glyphId: GlyphId(UInt32(i)),
                fontSize: Pixels(16),
                subpixelVariant: Point(x: 0, y: 0)
            ))

            let pixelCount = Int(w * h)
            let dummyData = Data(repeating: UInt8(i % 255), count: pixelCount)

            let tile = try #require(atlas.getOrInsertWith(key: key) {
                (Size(width: DevicePixels(w), height: DevicePixels(h)), dummyData)
            })

            insertedTiles.append((key, tile))
        }

        // Verify no overlapping bounds among tiles assigned to the SAME texture sheet
        var tilesByTexture: [UInt32: [Bounds<DevicePixels>]] = [:]
        for (_, tile) in insertedTiles {
            let texIdx = tile.textureId.index
            let bounds = tile.bounds

            if let existingList = tilesByTexture[texIdx] {
                for existing in existingList {
                    let noOverlap = (bounds.origin.x.value + bounds.size.width.value <= existing.origin.x.value) ||
                                    (existing.origin.x.value + existing.size.width.value <= bounds.origin.x.value) ||
                                    (bounds.origin.y.value + bounds.size.height.value <= existing.origin.y.value) ||
                                    (existing.origin.y.value + existing.size.height.value <= bounds.origin.y.value)
                    #expect(noOverlap, "Overlap detected on texture sheet \(texIdx) between \(bounds) and \(existing)")
                }
            }
            tilesByTexture[texIdx, default: []].append(bounds)
        }

        #expect(tilesByTexture.keys.count >= 2, "Expected at least 2 texture sheets to be allocated, got \(tilesByTexture.keys.count)")

        // Flush uploads to verify GPU texture writes execute cleanly without validation errors
        atlas.beforeFrame()

        // Cache hit determinism: re-query all keys, build closure must NOT be invoked
        var buildCalled = false
        for (key, originalTile) in insertedTiles {
            let cached = try #require(atlas.getOrInsertWith(key: key) {
                buildCalled = true
                return nil
            })
            #expect(!buildCalled, "Build closure was invoked for existing cached key \(key)")
            #expect(cached.tileId == originalTile.tileId)
            #expect(cached.textureId == originalTile.textureId)
            #expect(cached.bounds == originalTile.bounds)
        }
    }

    // MARK: - Scenario 2: Dynamic Instance Buffer Growth & Limits

    @Test
    func test_dynamic_instance_buffer_growth_under_massive_primitive_load() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let config = WgpuSurfaceConfig(
            size: Size(width: DevicePixels(128), height: DevicePixels(128)),
            transparent: false
        )
        let renderer = try WgpuRenderer.newOffscreen(context: context, config: config)
        let atlas = renderer.spriteAtlas()

        // Allocate a sample monochrome sprite tile
        let spriteTile = try #require(atlas.getOrInsertWith(
            key: .svg(RenderSvgParams(path: "stress_sprite", size: Size(width: DevicePixels(4), height: DevicePixels(4))))
        ) {
            (Size(width: DevicePixels(4), height: DevicePixels(4)), Data(repeating: 255, count: 16))
        })

        // Build a massive scene designed to exceed initial 2MB instance buffer capacity:
        // 10,000 Quads (~1.12 MB) + 5,000 Shadows (~0.56 MB) + 2,000 Paths (~0.83 MB) + 5,000 Sprites (~0.32 MB) = ~2.83 MB
        var scene = Scene()

        let viewportBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(128), height: ScaledPixels(128)))
        let mask = ContentMask(bounds: viewportBounds)

        // 1. 10,000 Quads
        for i in 0..<10000 {
            let quad = Quad(
                order: DrawOrder(UInt32(i + 1)),
                borderStyle: .solid,
                bounds: Bounds(
                    origin: Point(x: ScaledPixels(Float(i % 120)), y: ScaledPixels(Float((i / 120) % 120))),
                    size: Size(width: ScaledPixels(8), height: ScaledPixels(8))
                ),
                contentMask: mask,
                background: solidBackground(Rgba(r: 0.1, g: 0.2, b: 0.3, a: 1.0)),
                borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
                cornerRadii: .zero,
                borderWidths: .zero
            )
            scene.insertQuad(quad)
        }

        // 2. 5,000 Shadows
        for i in 0..<5000 {
            let shadow = Shadow(
                order: DrawOrder(UInt32(10001 + i)),
                blurRadius: ScaledPixels(2),
                bounds: Bounds(
                    origin: Point(x: ScaledPixels(Float(i % 120)), y: ScaledPixels(Float((i / 120) % 120))),
                    size: Size(width: ScaledPixels(6), height: ScaledPixels(6))
                ),
                cornerRadii: .zero,
                contentMask: mask,
                color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 0.0, a: 0.2))
            )
            scene.insertShadow(shadow)
        }

        // 3. 2,000 Triangulated Paths
        var pathBuilder = PathBuilder.fill()
        pathBuilder.addPolygon([
            Point(x: Pixels(0), y: Pixels(0)),
            Point(x: Pixels(4), y: Pixels(0)),
            Point(x: Pixels(4), y: Pixels(4)),
            Point(x: Pixels(0), y: Pixels(4))
        ], closed: true)
        let baseFillPath = try pathBuilder.build()

        for i in 0..<2000 {
            var scaledPath = baseFillPath.scale(1.0)
            scaledPath.order = DrawOrder(UInt32(15001 + i))
            scaledPath.color = solidBackground(Rgba(r: 0.8, g: 0.8, b: 0.1, a: 1.0))
            let pb = Bounds(
                origin: Point<ScaledPixels>(x: ScaledPixels(Float(i % 120)), y: ScaledPixels(Float((i / 120) % 120))),
                size: Size(width: ScaledPixels(4), height: ScaledPixels(4))
            )
            scaledPath.bounds = pb
            scaledPath.contentMask = ContentMask(bounds: pb)
            scene.insertPath(scaledPath)
        }

        // 4. 5,000 Monochrome Sprites
        for i in 0..<5000 {
            let sprite = MonochromeSprite(
                order: DrawOrder(UInt32(17001 + i)),
                bounds: Bounds(
                    origin: Point<ScaledPixels>(x: ScaledPixels(Float(i % 120)), y: ScaledPixels(Float((i / 120) % 120))),
                    size: Size(width: ScaledPixels(4), height: ScaledPixels(4))
                ),
                contentMask: mask,
                color: Hsla(rgba: Rgba(r: 0.2, g: 0.7, b: 0.9, a: 1.0)),
                tile: spriteTile
            )
            scene.insertMonochromeSprite(sprite)
        }

        // Render scene: this triggers the instance buffer overflow retry loop and buffer capacity doubling
        renderer.draw(scene)

        // Readback to ensure rendering actually completed on the GPU
        let pixels = try renderer.readbackPixelsRGBA()
        #expect(pixels.count == 128 * 128 * 4)

        // Ensure non-trivial pixels were written
        let nonZero = pixels.contains { $0 != 0 }
        #expect(nonZero, "Frame buffer was completely empty after rendering massive primitive scene")
    }

    // MARK: - Scenario 3: Two-Pass Path Rasterization Intermediate Unnesting

    @Test
    func test_two_pass_path_rasterization_intermediate_unnesting_and_load_preservation() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let config = WgpuSurfaceConfig(
            size: Size(width: DevicePixels(64), height: DevicePixels(64)),
            transparent: false
        )
        let renderer = try WgpuRenderer.newOffscreen(context: context, config: config)

        var scene = Scene()
        let viewport = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(64), height: ScaledPixels(64)))
        let mask = ContentMask(bounds: viewport)

        // 1. Red background quad covering entire viewport (Batch 1: Quads)
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: viewport,
            contentMask: mask,
            background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        // 2. Complex overlapping vector star path (Batch 2: Paths)
        // This will end the main render pass, run intermediate path rasterization,
        // and reopen the main pass with WGPULoadOp_Load!
        var starBuilder = PathBuilder.fill()
        starBuilder.addPolygon([
            Point(x: Pixels(16), y: Pixels(16)),
            Point(x: Pixels(32), y: Pixels(8)),
            Point(x: Pixels(48), y: Pixels(16)),
            Point(x: Pixels(40), y: Pixels(32)),
            Point(x: Pixels(48), y: Pixels(48)),
            Point(x: Pixels(32), y: Pixels(40)),
            Point(x: Pixels(16), y: Pixels(48)),
            Point(x: Pixels(24), y: Pixels(32))
        ], closed: true)
        let starPath = try starBuilder.build()
        var scaledStar = starPath.scale(1.0)
        scaledStar.order = DrawOrder(2)
        scaledStar.color = solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)) // Green fill
        let starBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(16), y: ScaledPixels(8)), size: Size(width: ScaledPixels(32), height: ScaledPixels(40)))
        scaledStar.bounds = starBounds
        scaledStar.contentMask = ContentMask(bounds: starBounds)
        scene.insertPath(scaledStar)

        // 3. A second quad over a corner (Batch 3: Quads)
        let cornerQuad = Quad(
            order: DrawOrder(3),
            borderStyle: .solid,
            bounds: Bounds(origin: Point(x: ScaledPixels(48), y: ScaledPixels(48)), size: Size(width: ScaledPixels(16), height: ScaledPixels(16))),
            contentMask: mask,
            background: solidBackground(Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)), // Blue
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(cornerQuad)

        // 4. A second path overlapping both the background and the star (Batch 4: Paths)
        // This tests repeated ending and reopening of the render pass on the same command encoder
        var triBuilder = PathBuilder.fill()
        triBuilder.addPolygon([
            Point(x: Pixels(28), y: Pixels(28)),
            Point(x: Pixels(36), y: Pixels(28)),
            Point(x: Pixels(32), y: Pixels(36))
        ], closed: true)
        let triPath = try triBuilder.build()
        var scaledTri = triPath.scale(1.0)
        scaledTri.order = DrawOrder(4)
        scaledTri.color = solidBackground(Rgba(r: 1.0, g: 1.0, b: 0.0, a: 1.0)) // Yellow
        let triBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(28), y: ScaledPixels(28)), size: Size(width: ScaledPixels(8), height: ScaledPixels(8)))
        scaledTri.bounds = triBounds
        scaledTri.contentMask = ContentMask(bounds: triBounds)
        scene.insertPath(scaledTri)

        // Render scene
        renderer.draw(scene)

        let pixels = try renderer.readbackPixelsRGBA()
        #expect(pixels.count == 64 * 64 * 4)

        func pixelAt(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let idx = (y * 64 + x) * 4
            return (pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
        }

        // Assertion 1: Uncovered corner (4, 4) must remain Red, proving WGPULoadOp_Load preserved the background
        let bgPixel = pixelAt(x: 4, y: 4)
        #expect(bgPixel.r > 200, "Background red was lost or overwritten (r: \(bgPixel.r))")
        #expect(bgPixel.g < 50)
        #expect(bgPixel.b < 50)

        // Assertion 2: Star path interior at (32, 20) must be Green
        let starPixel = pixelAt(x: 32, y: 20)
        #expect(starPixel.g > 200, "Star path green was not rasterized (g: \(starPixel.g))")
        #expect(starPixel.r < 50)
        #expect(starPixel.b < 50)

        // Assertion 3: Second quad at (56, 56) must be Blue
        let quadPixel = pixelAt(x: 56, y: 56)
        #expect(quadPixel.b > 200, "Corner quad blue was not drawn (b: \(quadPixel.b))")
        #expect(quadPixel.r < 50)
        #expect(quadPixel.g < 50)

        // Assertion 4: Second path at (32, 30) must be Yellow (Red + Green)
        let triPixel = pixelAt(x: 32, y: 30)
        #expect(triPixel.r > 200, "Second path yellow red component missing (r: \(triPixel.r))")
        #expect(triPixel.g > 200, "Second path yellow green component missing (g: \(triPixel.g))")
        #expect(triPixel.b < 50)
    }

    // MARK: - Scenario 4: Lavapipe Pixel Readback Exactness

    @Test
    func test_lavapipe_pixel_readback_exactness_and_format_swizzle() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let config = WgpuSurfaceConfig(
            size: Size(width: DevicePixels(128), height: DevicePixels(128)),
            transparent: false
        )
        let renderer = try WgpuRenderer.newOffscreen(context: context, config: config)
        let atlas = renderer.spriteAtlas()

        var scene = Scene()
        let viewport = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(128), height: ScaledPixels(128)))
        let mask = ContentMask(bounds: viewport)

        // 1. Red base quad covering entire (0, 0, 128, 128)
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: viewport,
            contentMask: mask,
            background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        // 2. Green quad covering (16, 16, 32, 32)
        let greenBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(16), y: ScaledPixels(16)), size: Size(width: ScaledPixels(32), height: ScaledPixels(32)))
        let greenQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: greenBounds,
            contentMask: ContentMask(bounds: greenBounds),
            background: solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(greenQuad)

        // 3. Blue quad covering (64, 16, 32, 32)
        let blueBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(64), y: ScaledPixels(16)), size: Size(width: ScaledPixels(32), height: ScaledPixels(32)))
        let blueQuad = Quad(
            order: DrawOrder(3),
            borderStyle: .solid,
            bounds: blueBounds,
            contentMask: ContentMask(bounds: blueBounds),
            background: solidBackground(Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(blueQuad)

        // 4. White monochrome sprite covering (16, 64, 32, 32)
        let monoTile = try #require(atlas.getOrInsertWith(
            key: .svg(RenderSvgParams(path: "white_mono", size: Size(width: DevicePixels(32), height: DevicePixels(32))))
        ) {
            (Size(width: DevicePixels(32), height: DevicePixels(32)), Data(repeating: 255, count: 32 * 32))
        })
        let monoBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(16), y: ScaledPixels(64)), size: Size(width: ScaledPixels(32), height: ScaledPixels(32)))
        let monoSprite = MonochromeSprite(
            order: DrawOrder(4),
            bounds: monoBounds,
            contentMask: ContentMask(bounds: monoBounds),
            color: Hsla(rgba: Rgba(r: 1.0, g: 1.0, b: 1.0, a: 1.0)),
            tile: monoTile
        )
        scene.insertMonochromeSprite(monoSprite)

        // 5. Cyan polychrome sprite covering (64, 64, 32, 32)
        // Polychrome sprite textures use BGRA8Unorm: Cyan is B=255, G=255, R=0, A=255
        var cyanPixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        for i in 0..<(32 * 32) {
            cyanPixels[i * 4 + 0] = 255 // B
            cyanPixels[i * 4 + 1] = 255 // G
            cyanPixels[i * 4 + 2] = 0   // R
            cyanPixels[i * 4 + 3] = 255 // A
        }
        let polyTile = try #require(atlas.getOrInsertWith(
            key: .image(RenderImageParams(imageId: ImageId(42), frameIndex: 0))
        ) {
            (Size(width: DevicePixels(32), height: DevicePixels(32)), Data(cyanPixels))
        })
        let polyBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(64), y: ScaledPixels(64)), size: Size(width: ScaledPixels(32), height: ScaledPixels(32)))
        let polySprite = PolychromeSprite(
            order: DrawOrder(5),
            bounds: polyBounds,
            contentMask: ContentMask(bounds: polyBounds),
            tile: polyTile
        )
        scene.insertPolychromeSprite(polySprite)

        // Render scene
        renderer.draw(scene)

        let pixels = try renderer.readbackPixelsRGBA()
        #expect(pixels.count == 128 * 128 * 4)

        func pixelAt(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let idx = (y * 128 + x) * 4
            return (pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
        }

        // Verification 1: Base background at (8, 8) must be Red (channel 0 = R > 200, channel 2 = B < 50)
        // If swizzle were reversed, Red would be at channel 2!
        let redPixel = pixelAt(x: 8, y: 8)
        #expect(redPixel.r > 200, "Expected Red in channel 0, got \(redPixel.r)")
        #expect(redPixel.g < 50)
        #expect(redPixel.b < 50, "Expected Blue < 50, got \(redPixel.b) (indicates incorrect BGRA swizzle)")
        #expect(redPixel.a > 200)

        // Verification 2: Green quad at (24, 24) must be Green
        let greenPixel = pixelAt(x: 24, y: 24)
        #expect(greenPixel.r < 50)
        #expect(greenPixel.g > 200)
        #expect(greenPixel.b < 50)
        #expect(greenPixel.a > 200)

        // Verification 3: Blue quad at (72, 24) must be Blue (channel 2 = B > 200, channel 0 = R < 50)
        let bluePixel = pixelAt(x: 72, y: 24)
        #expect(bluePixel.r < 50, "Expected Red < 50, got \(bluePixel.r) (indicates incorrect BGRA swizzle)")
        #expect(bluePixel.g < 50)
        #expect(bluePixel.b > 200, "Expected Blue in channel 2, got \(bluePixel.b)")
        #expect(bluePixel.a > 200)

        // Verification 4: White monochrome sprite at (24, 72) must be White
        let whitePixel = pixelAt(x: 24, y: 72)
        #expect(whitePixel.r > 200)
        #expect(whitePixel.g > 200)
        #expect(whitePixel.b > 200)
        #expect(whitePixel.a > 200)

        // Verification 5: Cyan polychrome sprite at (72, 72) must be Cyan (G > 200, B > 200, R < 50)
        let cyanPixel = pixelAt(x: 72, y: 72)
        #expect(cyanPixel.r < 50, "Expected Red < 50 for Cyan, got \(cyanPixel.r)")
        #expect(cyanPixel.g > 200, "Expected Green > 200 for Cyan, got \(cyanPixel.g)")
        #expect(cyanPixel.b > 200, "Expected Blue > 200 for Cyan, got \(cyanPixel.b)")
        #expect(cyanPixel.a > 200)
    }
    #endif
}
#endif
