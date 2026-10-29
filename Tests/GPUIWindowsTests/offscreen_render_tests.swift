// Swift-only: Headless offscreen rendering and pixel readback smoke tests for GPUIWindows Direct3D 11

#if os(Windows)
import Foundation
import Testing
import GPUI
import GPUICollections
import GPUIUtil
@testable import GPUIWindows
#if canImport(CWinSys)
import CWinSys
#endif

@Suite("DirectXOffscreenRenderTests")
struct DirectXOffscreenRenderTests {
    @Test
    func test_struct_memory_layouts() {
        #expect(MemoryLayout<GlobalParams>.size == 32)
        #expect(MemoryLayout<GlobalParams>.stride == 32)
        #expect(MemoryLayout<GlobalParams>.size % 16 == 0) // D3D11 constant buffer alignment requirement

        #expect(MemoryLayout<PathSprite>.size == 16)
        #expect(MemoryLayout<PathSprite>.stride == 16)

        #expect(MemoryLayout<PathRasterizationSprite>.size == 104)
        #expect(MemoryLayout<PathRasterizationSprite>.stride == 104)
    }

    @Test
    func test_shelf_atlas_allocator() {
        var allocator = ShelfAtlasAllocator(size: Size(width: DevicePixels(256), height: DevicePixels(256)))

        let tile1 = allocator.allocate(size: Size(width: DevicePixels(32), height: DevicePixels(32)))
        #expect(tile1 != nil)
        #expect(tile1?.1.origin.x.value == 0)
        #expect(tile1?.1.origin.y.value == 0)

        let tile2 = allocator.allocate(size: Size(width: DevicePixels(64), height: DevicePixels(32)))
        #expect(tile2 != nil)
        #expect(tile2?.1.origin.x.value == 32)
        #expect(tile2?.1.origin.y.value == 0)

        allocator.clear()
        #expect(allocator.shelves.isEmpty)
        #expect(allocator.nextTileId == 1)
    }

    @Test
    func test_headless_offscreen_render_and_pixel_readback() throws {
        // 1. Create WARP software rasterizer device
        var dev: UnsafeMutableRawPointer?
        var ctx: UnsafeMutableRawPointer?
        var fl: UInt32 = 0
        let devHr = cwin_d3d11_create_device_warp(1, &dev, &ctx, &fl)
        guard devHr == 0, let device = dev, let context = ctx else {
            throw DirectXError.deviceCreationFailure(devHr)
        }
        defer {
            cwin_release_com_object(context)
            cwin_release_com_object(device)
        }

        // 2. Create 200x200 offscreen texture and render target view
        let width: UInt32 = 200
        let height: UInt32 = 200
        var tex: UnsafeMutableRawPointer?
        var srv: UnsafeMutableRawPointer?
        let texHr = cwin_d3d11_create_texture_2d(
            device,
            width,
            height,
            87, // DXGI_FORMAT_B8G8R8A8_UNORM
            0x20 | 0x8, // D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE
            0,
            &tex,
            &srv
        )
        guard texHr == 0, let texture = tex else {
            throw DirectXError.textureCreationFailure(texHr)
        }
        defer {
            if let s = srv { cwin_release_com_object(s) }
            cwin_release_com_object(texture)
        }

        var rtv: UnsafeMutableRawPointer?
        let rtvHr = cwin_d3d11_create_render_target_view(device, texture, &rtv)
        guard rtvHr == 0, let renderTargetView = rtv else {
            throw DirectXError.textureCreationFailure(rtvHr)
        }
        defer {
            cwin_release_com_object(renderTargetView)
        }

        // 3. Attach DirectXRenderer to offscreen render target
        let renderer = try DirectXRenderer(
            device: device,
            deviceContext: context,
            renderTargetView: renderTargetView,
            width: width,
            height: height
        )

        // 4. Construct test Scene
        var scene = Scene()

        // 4a. Solid black background quad covering entire 200x200 viewport
        let bgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: Size(width: ScaledPixels(Float(width)), height: ScaledPixels(Float(height)))
        )
        let bgQuad = Quad(
            order: DrawOrder(1),
            borderStyle: .solid,
            bounds: bgBounds,
            contentMask: ContentMask(bounds: bgBounds),
            background: solidBackground(Rgba(r: 0.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(bgQuad)

        // 4b. Contrasting red inner quad covering (50, 50, 100, 100)
        let innerBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(50), y: ScaledPixels(50)),
            size: Size(width: ScaledPixels(100), height: ScaledPixels(100))
        )
        let innerQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: innerBounds,
            contentMask: ContentMask(bounds: innerBounds),
            background: solidBackground(Rgba(r: 1.0, g: 0.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(innerQuad)

        // 4c. Blue monochrome sprite covering (10, 10, 16, 16)
        let atlas = renderer.spriteAtlas()
        let tile = try #require(atlas.getOrInsertWith(
            key: .svg(RenderSvgParams(path: "win_test_blue_icon", size: Size(width: DevicePixels(16), height: DevicePixels(16))))
        ) {
            (Size(width: DevicePixels(16), height: DevicePixels(16)), Data(repeating: 255, count: 256))
        })
        let spriteBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(10), y: ScaledPixels(10)),
            size: Size(width: ScaledPixels(16), height: ScaledPixels(16))
        )
        let sprite = MonochromeSprite(
            order: DrawOrder(3),
            bounds: spriteBounds,
            contentMask: ContentMask(bounds: spriteBounds),
            color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)),
            tile: tile
        )
        scene.insertMonochromeSprite(sprite)

        // 4d. Green triangulated path at (10, 160, 20, 20)
        var builder = PathBuilder.fill()
        builder.addPolygon([
            Point(x: Pixels(10), y: Pixels(160)),
            Point(x: Pixels(30), y: Pixels(160)),
            Point(x: Pixels(30), y: Pixels(180)),
            Point(x: Pixels(10), y: Pixels(180))
        ], closed: true)
        let path = try builder.build()
        var scaledPath = path.scale(1.0)
        scaledPath.order = DrawOrder(4)
        scaledPath.color = solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0))
        let pathBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(10), y: ScaledPixels(160)),
            size: Size(width: ScaledPixels(20), height: ScaledPixels(20))
        )
        scaledPath.bounds = pathBounds
        scaledPath.contentMask = ContentMask(bounds: pathBounds)
        scene.insertPath(scaledPath)

        // 5. Draw the scene through DirectXRenderer
        try renderer.draw(scene: scene, backgroundAppearance: .opaque)

        // 6. Read back rendered pixels from offscreen render target (with BGRA->RGBA swizzle)
        var rowPitch: UInt32 = 0
        var pixelPtr: UnsafeMutablePointer<UInt8>? = nil
        let readHr = cwin_d3d11_readback_texture_pixels(
            device,
            context,
            texture,
            width,
            height,
            &rowPitch,
            1, // swizzle BGRA to RGBA
            &pixelPtr
        )
        guard readHr == 0, let pixels = pixelPtr else {
            throw DirectXError.textureCreationFailure(readHr)
        }
        defer {
            cwin_d3d11_free_pixel_buffer(pixels)
        }

        func pixelAt(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let offset = y * Int(rowPitch) + x * 4
            return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
        }

        // Test center pixel (100, 100): Should be inside inner Quad -> Red!
        let centerPixel = pixelAt(x: 100, y: 100)
        #expect(centerPixel.r > 200)
        #expect(centerPixel.g < 50)
        #expect(centerPixel.b < 50)

        // Test corner pixel (5, 5): Should be in background Quad -> Black!
        let cornerPixel = pixelAt(x: 5, y: 5)
        #expect(cornerPixel.r < 50)
        #expect(cornerPixel.g < 50)
        #expect(cornerPixel.b < 50)

        // Test sprite pixel (18, 18): Should be inside MonochromeSprite -> Blue!
        let spritePixel = pixelAt(x: 18, y: 18)
        #expect(spritePixel.r < 50)
        #expect(spritePixel.g < 50)
        #expect(spritePixel.b > 200)

        // Test path pixel (20, 170): Should be inside Path -> Green!
        let pathPixel = pixelAt(x: 20, y: 170)
        #expect(pathPixel.r < 50)
        #expect(pathPixel.g > 200)
        #expect(pathPixel.b < 50)
    }
}

#endif
