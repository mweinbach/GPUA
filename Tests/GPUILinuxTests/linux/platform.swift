// Tests ported from: crates/gpui_linux/src/linux/platform.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Linux)
import Foundation
import Testing
@testable import GPUILinux
import GPUI
import GPUIWGPU
import CLinuxSys
import CWebGPU

@Suite("LinuxPlatformTests")
struct LinuxPlatformTests {
    @Test
    func testIsWithinClickDistance() {
        let zero = Point<Pixels>(x: px(0.0), y: px(0.0))
        #expect(isWithinClickDistance(zero, Point(x: px(5.0), y: px(5.0))))
        #expect(isWithinClickDistance(zero, Point(x: px(-4.9), y: px(5.0))))
        #expect(isWithinClickDistance(Point(x: px(3.0), y: px(2.0)), Point(x: px(-2.0), y: px(-2.0))))
        #expect(!isWithinClickDistance(zero, Point(x: px(5.0), y: px(5.1))))
    }

    @Test
    func testGuessCompositor() {
        let comp = guessCompositor()
        #expect(["Wayland", "X11", "Headless"].contains(comp))
    }

    private static func loadFontFixture() -> Data? {
        let candidates = [
            "Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            "/workspace/Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
        ]
        for path in candidates {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    @Test
    func testX11WindowWebGPURenderingSmoke() throws {
        // Only run when DISPLAY is available (e.g. under xvfb-run or real X11)
        guard let displayEnv = ProcessInfo.processInfo.environment["DISPLAY"], !displayEnv.isEmpty else {
            return
        }

        let client = try X11Client.new()
        let displays = client.displays()
        #expect(!displays.isEmpty)

        let window = try client.openWindow(
            handle: AnyWindowHandle(id: 42),
            options: WindowOptions(
                windowBounds: .windowed(Bounds(origin: .zero, size: Size(width: px(128), height: px(128)))),
                kind: .normal
            )
        )
        guard let x11Window = window as? X11Window else {
            Issue.record("Expected window to be X11Window")
            return
        }

        // Map window and synchronize with X server before drawing
        guard let conn = x11Window.ptr.connection else {
            Issue.record("Missing XCB connection")
            return
        }
        xcb_map_window(conn, x11Window.ptr.xWindow)
        xcb_flush(conn)
        if let display = client.ptr.state.x11Display {
            XSync(display, 0)
        }

        // Initialize CosmicTextSystem to shape real text from font fixture
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let glyphA = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"), "Failed to find glyph for 'A'")

        var scene = Scene()

        // 1. Red background quad covering entire 128x128 window
        let bgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(0), y: ScaledPixels(0)),
            size: Size(width: ScaledPixels(128), height: ScaledPixels(128))
        )
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

        // 2. Contrasting green quad in center (32..96, 32..96)
        let fgBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(32), y: ScaledPixels(32)),
            size: Size(width: ScaledPixels(64), height: ScaledPixels(64))
        )
        let fgQuad = Quad(
            order: DrawOrder(2),
            borderStyle: .solid,
            bounds: fgBounds,
            contentMask: ContentMask(bounds: fgBounds),
            background: solidBackground(Rgba(r: 0.0, g: 1.0, b: 0.0, a: 1.0)),
            borderColor: Hsla(h: 0, s: 0, l: 0, a: 1),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        scene.insertQuad(fgQuad)

        // 3. Rasterize real glyph 'A' through CosmicTextSystem and render into atlas
        let renderer = x11Window.ptr.state.renderer
        let atlas = renderer.spriteAtlas()
        let glyphParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphA,
            fontSize: px(24),
            subpixelVariant: Point(x: 0, y: 0),
            scaleFactor: 1.0,
            isEmoji: false,
            subpixelRendering: false
        )
        let glyphBounds = try textSystem.glyphRasterBounds(params: glyphParams)
        let (glyphSize, glyphBitmap) = try textSystem.rasterizeGlyph(params: glyphParams, rasterBounds: glyphBounds)
        #expect(glyphSize.width.value > 0 && glyphSize.height.value > 0)
        #expect(glyphBitmap.contains(where: { $0 > 0 }))

        let tile = try #require(try atlas.getOrInsertWith(key: AtlasKey.glyph(glyphParams), build: {
            (glyphSize, glyphBitmap)
        }))

        let spriteBounds = Bounds(
            origin: Point<ScaledPixels>(x: ScaledPixels(48), y: ScaledPixels(48)),
            size: Size(width: ScaledPixels(Float(glyphSize.width.value)), height: ScaledPixels(Float(glyphSize.height.value)))
        )
        let sprite = MonochromeSprite(
            order: DrawOrder(3),
            bounds: spriteBounds,
            contentMask: ContentMask(bounds: spriteBounds),
            color: Hsla(rgba: Rgba(r: 0.0, g: 0.0, b: 1.0, a: 1.0)),
            tile: tile
        )
        scene.insertMonochromeSprite(sprite)

        // Draw and present the scene with a retry poll loop for Xvfb presentation under concurrent test load
        var bgR: UInt8 = 0
        var bgG: UInt8 = 0
        var bgB: UInt8 = 0
        var fgR: UInt8 = 0
        var fgG: UInt8 = 0
        var fgB: UInt8 = 0
        var foundBlueGlyphPixel = false

        for _ in 0..<20 {
            x11Window.draw(scene: scene)

            xcb_flush(conn)
            if let display = client.ptr.state.x11Display {
                XSync(display, 0)
            }
            try? client.processX11Events(conn)

            // Verify window rendered pixels via xcb_get_image
            let cookie = xcb_get_image(
                conn,
                UInt8(XCB_IMAGE_FORMAT_Z_PIXMAP.rawValue),
                x11Window.ptr.xWindow,
                0,
                0,
                128,
                128,
                UInt32.max
            )
            guard let reply = xcb_get_image_reply(conn, cookie, nil) else {
                usleep(10_000)
                continue
            }

            let len = Int(xcb_get_image_data_length(reply))
            guard len >= 128 * 128 * 4, let data = xcb_get_image_data(reply) else {
                free(reply)
                usleep(10_000)
                continue
            }

            // Assert specific rendered pixel colors in 32-bit BGRX/BGRA (little-endian X11):
            // Pixel at (x, y): offset = (y * 128 + x) * 4
            // data[offset + 0] = B, data[offset + 1] = G, data[offset + 2] = R

            // 1. Red background at (10, 10): R > 200, G < 50, B < 50
            let bgOffset = (10 * 128 + 10) * 4
            bgB = data[bgOffset]
            bgG = data[bgOffset + 1]
            bgR = data[bgOffset + 2]

            // 2. Green inner quad at (36, 36): G > 200, R < 50, B < 50
            let fgOffset = (36 * 128 + 36) * 4
            fgB = data[fgOffset]
            fgG = data[fgOffset + 1]
            fgR = data[fgOffset + 2]

            // 3. Blue-blended glyph pixel inside the sprite bounds: at least one pixel with B > 100
            foundBlueGlyphPixel = false
            for y in 48..<min(128, 48 + Int(glyphSize.height.value)) {
                for x in 48..<min(128, 48 + Int(glyphSize.width.value)) {
                    let offset = (y * 128 + x) * 4
                    let b = data[offset]
                    if b > 100 {
                        foundBlueGlyphPixel = true
                        break
                    }
                }
                if foundBlueGlyphPixel { break }
            }

            free(reply)

            if bgR > 200 && fgG > 200 && foundBlueGlyphPixel {
                break
            }
            usleep(15_000)
        }

        #expect(bgR > 200 && bgG < 50 && bgB < 50, "Expected red background at (10, 10), got R:\(bgR) G:\(bgG) B:\(bgB)")
        #expect(fgG > 200 && fgR < 50 && fgB < 50, "Expected green quad at (36, 36), got R:\(fgR) G:\(fgG) B:\(fgB)")
        #expect(foundBlueGlyphPixel, "Expected at least one blue glyph pixel with B > 100 inside sprite region")
    }
}
#endif
