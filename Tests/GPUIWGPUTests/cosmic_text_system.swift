// Swift-only: Behavioral test suite for cosmic_text_system.swift (FreeType/HarfBuzz/Fontconfig)

#if os(Linux) || os(Windows) || os(Android) || os(WASI)
import Foundation
import Testing
import GPUI
@testable import GPUIWGPU

@Suite("CosmicTextSystemTests")
struct CosmicTextSystemTests {
    private func loadFontFixture() -> Data? {
        let candidates = [
            "Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            "/workspace/Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            URL(fileURLWithPath: #filePath)
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

    @Test func testCosmicTextSystemConstructors() {
        let ts1 = CosmicTextSystem.new("sans-serif")
        #expect(ts1.recommendedRenderingMode(fontId: FontId(0), fontSize: Pixels(16)) == .subpixel)

        let ts2 = CosmicTextSystem.newWithoutSystemFonts("DejaVu Sans")
        #expect(ts2.recommendedRenderingMode(fontId: FontId(0), fontSize: Pixels(16)) == .subpixel)
    }

    #if os(Linux)
    @Test func testAddFontAndMetrics() throws {
        guard let fontData = loadFontFixture() else {
            Issue.record("Font fixture IBMPlexSans-Regular.ttf not found")
            return
        }

        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let names = textSystem.allFontNames()
        #expect(names.contains("IBM Plex Sans"))

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let metrics = textSystem.fontMetrics(fontId: fontId)

        #expect(metrics.unitsPerEm == 1000)
        #expect(metrics.ascent > 800)
        #expect(metrics.descent < 0)
        #expect(metrics.capHeight > 600)
        #expect(metrics.xHeight > 400)
        #expect(metrics.boundingBox.size.width > 0)
        #expect(metrics.boundingBox.size.height > 0)
    }

    @Test func testGlyphLookupAndTypographicBounds() throws {
        guard let fontData = loadFontFixture() else {
            Issue.record("Font fixture IBMPlexSans-Regular.ttf not found")
            return
        }

        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))

        let glyphA = textSystem.glyphForChar(fontId: fontId, ch: "A")
        #expect(glyphA != nil)

        let glyphSpace = textSystem.glyphForChar(fontId: fontId, ch: " ")
        #expect(glyphSpace != nil)

        if let glyphA = glyphA {
            let adv = try textSystem.advance(fontId: fontId, glyphId: glyphA)
            #expect(adv.width > 0)

            let bounds = try textSystem.typographicBounds(fontId: fontId, glyphId: glyphA)
            #expect(bounds.size.width > 0)
        }
    }

    @Test func testHarfBuzzShapingAndLineMeasurement() throws {
        guard let fontData = loadFontFixture() else {
            Issue.record("Font fixture IBMPlexSans-Regular.ttf not found")
            return
        }

        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let text = "Hello GPUI Linux!"
        let runs = [FontRun(len: text.utf8.count, fontId: fontId)]

        let layout = textSystem.layoutLine(text: text, fontSize: Pixels(16), runs: runs)

        #expect(layout.len == text.utf8.count)
        #expect(layout.width > Pixels(50.0))
        #expect(layout.ascent > Pixels(10.0))
        #expect(layout.descent >= Pixels(0.0))
        #expect(layout.runs.count == 1)

        let shapedRun = layout.runs[0]
        #expect(shapedRun.fontId == fontId)
        #expect(shapedRun.glyphs.count == text.count)

        // Verify that x position advances for consecutive glyphs
        for i in 1..<shapedRun.glyphs.count {
            #expect(shapedRun.glyphs[i].position.x > shapedRun.glyphs[i - 1].position.x)
        }

        // Test indexForX character lookup
        let indexAtZero = layout.indexForX(Pixels(0))
        #expect(indexAtZero == 0)

        let indexAtEnd = layout.indexForX(layout.width + Pixels(10))
        #expect(indexAtEnd == nil)
    }

    @Test func testGlyphRasterizationGrayscaleAndSubpixel() throws {
        guard let fontData = loadFontFixture() else {
            Issue.record("Font fixture IBMPlexSans-Regular.ttf not found")
            return
        }

        let textSystem = CosmicTextSystem.newWithoutSystemFonts("sans-serif")
        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        guard let glyphA = textSystem.glyphForChar(fontId: fontId, ch: "A") else {
            Issue.record("Failed to find glyph for 'A'")
            return
        }

        // 1. Grayscale rendering (normal mode)
        let grayParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphA,
            fontSize: Pixels(24),
            subpixelVariant: Point(x: 0, y: 0),
            scaleFactor: 1.0,
            isEmoji: false,
            subpixelRendering: false
        )
        let grayBounds = try textSystem.glyphRasterBounds(params: grayParams)
        #expect(grayBounds.size.width.value > 0)
        #expect(grayBounds.size.height.value > 0)

        let (graySize, grayBitmap) = try textSystem.rasterizeGlyph(
            params: grayParams,
            rasterBounds: grayBounds
        )
        #expect(graySize == grayBounds.size)
        #expect(grayBitmap.count == Int(graySize.width.value * graySize.height.value))
        // Verify genuine non-zero rasterization pixels
        #expect(grayBitmap.contains(where: { $0 > 0 }))

        // 2. Subpixel rendering (LCD mode)
        let subpixelParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphA,
            fontSize: Pixels(24),
            subpixelVariant: Point(x: 1, y: 0),
            scaleFactor: 1.0,
            isEmoji: false,
            subpixelRendering: true
        )
        let subBounds = try textSystem.glyphRasterBounds(params: subpixelParams)
        #expect(subBounds.size.width.value > 0)
        #expect(subBounds.size.height.value > 0)

        let (subSize, subBitmap) = try textSystem.rasterizeGlyph(
            params: subpixelParams,
            rasterBounds: subBounds
        )
        #expect(subSize == subBounds.size)
        // 4 bytes per pixel (BGRA) for WGPUTextureFormat_BGRA8Unorm
        #expect(subBitmap.count == Int(subSize.width.value * subSize.height.value * 4))
        // Verify genuine non-zero subpixel RGB data
        #expect(subBitmap.contains(where: { $0 > 0 }))
    }
    #endif
}
#endif
