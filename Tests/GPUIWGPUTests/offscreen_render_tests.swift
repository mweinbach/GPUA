// Swift-only: Headless offscreen rendering and pixel readback tests for GPUIWGPU

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Testing
import Foundation
import GPUI
@testable import GPUIWGPU

@Suite("OffscreenRenderTests")
struct OffscreenRenderTests {
    @Test
    func test_struct_memory_layouts() {
        #expect(MemoryLayout<GlobalParams>.size == 16)
        #expect(MemoryLayout<GlobalParams>.stride == 16)

        #expect(MemoryLayout<GammaParams>.size == 32)
        #expect(MemoryLayout<GammaParams>.stride == 32)

        #expect(MemoryLayout<SurfaceParams>.size == 32)
        #expect(MemoryLayout<SurfaceParams>.stride == 32)

        #expect(MemoryLayout<PathSprite>.size == 16)
        #expect(MemoryLayout<PathSprite>.stride == 16)

        #expect(MemoryLayout<PathRasterizationVertex>.size == 104)
        #expect(MemoryLayout<PathRasterizationVertex>.stride == 104)
    }

    #if os(Linux)
    @Test
    func test_headless_offscreen_render_and_pixel_readback() throws {
        let instance = WgpuContext.instance()
        let context = try WgpuContext.new(instance: instance, surface: nil)
        let config = WgpuSurfaceConfig(
            size: Size(width: DevicePixels(64), height: DevicePixels(64)),
            transparent: false
        )
        let renderer = try WgpuRenderer.newOffscreen(context: context, config: config)

        var scene = Scene()

        // 1. Red background quad covering entire 64x64 viewport
        let bgBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)), size: Size(width: ScaledPixels(64), height: ScaledPixels(64)))
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: bgBounds,
            contentMask: ContentMask(bounds: bgBounds),
            background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        // 2. Contrasting green inner quad covering (16, 16, 20, 20)
        let innerBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(16), y: ScaledPixels(16)), size: Size(width: ScaledPixels(20), height: ScaledPixels(20)))
        let innerQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: innerBounds,
            contentMask: ContentMask(bounds: innerBounds),
            background: solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(innerQuad)

        // 3. Blue monochrome sprite covering (40, 8, 8, 8)
        let atlas = renderer.spriteAtlas()
        let tile = try #require(atlas.getOrInsertWith(
            key: .svg(RenderSvgParams(path: "test_blue_icon", size: Size(width: DevicePixels(8), height: DevicePixels(8))))
        ) {
            (Size(width: DevicePixels(8), height: DevicePixels(8)), Data(repeating: 255, count: 64))
        })
        let spriteBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(40), y: ScaledPixels(8)), size: Size(width: ScaledPixels(8), height: ScaledPixels(8)))
        let sprite = MonochromeSprite(
            order: DrawOrder(3),
            bounds: spriteBounds,
            contentMask: ContentMask(bounds: spriteBounds),
            color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)),
            tile: tile
        )
        scene.insertMonochromeSprite(sprite)

        // 4. Yellow triangulated path covering (8, 40, 16, 16)
        var builder = PathBuilder.fill()
        builder.addPolygon([
            Point(x: Pixels(8), y: Pixels(40)),
            Point(x: Pixels(24), y: Pixels(40)),
            Point(x: Pixels(24), y: Pixels(56)),
            Point(x: Pixels(8), y: Pixels(56))
        ], closed: true)
        let path = try builder.build()
        var scaledPath = path.scale(1.0)
        scaledPath.order = DrawOrder(4)
        scaledPath.color = solidBackground(Rgba(r: 1.0, g: 1.0, b: 0.0, a: 1.0))
        let pathBounds = Bounds(origin: Point<ScaledPixels>(x: ScaledPixels(8), y: ScaledPixels(40)), size: Size(width: ScaledPixels(16), height: ScaledPixels(16)))
        scaledPath.bounds = pathBounds
        scaledPath.contentMask = ContentMask(bounds: pathBounds)
        scene.insertPath(scaledPath)

        // Draw scene through WebGPU renderer
        renderer.draw(scene)

        #expect(renderer.viewportSize().width.value == 64)
        #expect(renderer.viewportSize().height.value == 64)

        // Read back rendered RGBA pixels from offscreen render target
        let pixels = try renderer.readbackPixelsRGBA()
        #expect(pixels.count == 64 * 64 * 4)

        func pixelAt(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let idx = (y * 64 + x) * 4
            return (pixels[idx], pixels[idx + 1], pixels[idx + 2], pixels[idx + 3])
        }

        // Test 1: Background Quad at (4, 4) should be Red
        let bgPixel = pixelAt(x: 4, y: 4)
        #expect(bgPixel.r > 200)
        #expect(bgPixel.g < 50)
        #expect(bgPixel.b < 50)

        // Test 2: Inner Quad at (20, 20) should be Green
        let innerPixel = pixelAt(x: 20, y: 20)
        #expect(innerPixel.r < 50)
        #expect(innerPixel.g > 200)
        #expect(innerPixel.b < 50)

        // Test 3: Monochrome Sprite at (44, 12) should be Blue
        let spritePixel = pixelAt(x: 44, y: 12)
        #expect(spritePixel.r < 50)
        #expect(spritePixel.g < 50)
        #expect(spritePixel.b > 200)

        // Test 4: Triangulated Path at (16, 48) should be Yellow (Red + Green)
        let pathPixel = pixelAt(x: 16, y: 48)
        #expect(pathPixel.r > 200)
        #expect(pathPixel.g > 200)
        #expect(pathPixel.b < 50)
    }
    #endif
}
#endif
