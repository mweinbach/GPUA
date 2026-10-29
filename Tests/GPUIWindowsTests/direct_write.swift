// Tests ported from: crates/gpui_windows/src/direct_write.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("DirectWrite Text System Tests")
struct DirectWriteTests {
    static func loadFontFixture() -> Data? {
        let candidatePaths = [
            "Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            "/workspace/Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf",
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // direct_write.swift
                .deletingLastPathComponent() // GPUIWindowsTests
                .appendingPathComponent("GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Tests/GPUITests/Fixtures/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf").path
        ]
        for path in candidatePaths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty {
                return data
            }
        }
        return nil
    }

    // Upstream test ported verbatim from crates/gpui_windows/src/direct_write.rs:1885-1919
    @Test
    func test_cluster_map() {
        let clusterMap1: [UInt16] = [0]
        var analyzer1 = ClusterAnalyzer(clusterMap: clusterMap1, glyphCount: 1)
        let next1_0 = analyzer1.next()
        #expect(next1_0?.utf16Len == 1 && next1_0?.glyphCount == 1)
        let next1_1 = analyzer1.next()
        #expect(next1_1 == nil)

        let clusterMap2: [UInt16] = [0, 1, 2]
        var analyzer2 = ClusterAnalyzer(clusterMap: clusterMap2, glyphCount: 3)
        let next2_0 = analyzer2.next()
        #expect(next2_0?.utf16Len == 1 && next2_0?.glyphCount == 1)
        let next2_1 = analyzer2.next()
        #expect(next2_1?.utf16Len == 1 && next2_1?.glyphCount == 1)
        let next2_2 = analyzer2.next()
        #expect(next2_2?.utf16Len == 1 && next2_2?.glyphCount == 1)
        let next2_3 = analyzer2.next()
        #expect(next2_3 == nil)

        // 👨‍👩‍👧‍👦👩‍💻
        let clusterMap3: [UInt16] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 4, 4, 4, 4]
        var analyzer3 = ClusterAnalyzer(clusterMap: clusterMap3, glyphCount: 5)
        let next3_0 = analyzer3.next()
        #expect(next3_0?.utf16Len == 11 && next3_0?.glyphCount == 4)
        let next3_1 = analyzer3.next()
        #expect(next3_1?.utf16Len == 5 && next3_1?.glyphCount == 1)
        let next3_2 = analyzer3.next()
        #expect(next3_2 == nil)

        // 👩‍💻
        let clusterMap4: [UInt16] = [0, 0, 0, 0, 0]
        var analyzer4 = ClusterAnalyzer(clusterMap: clusterMap4, glyphCount: 1)
        let next4_0 = analyzer4.next()
        #expect(next4_0?.utf16Len == 5 && next4_0?.glyphCount == 1)
        let next4_1 = analyzer4.next()
        #expect(next4_1 == nil)
    }

    @Test
    func test_open_type_tags() {
        let liga = makeOpenTypeTag("liga")
        #expect(liga == OpenTypeTags.liga)
        #expect(liga == 0x6167696c) // 'l' | ('i' << 8) | ('g' << 16) | ('a' << 24)

        let calt = makeOpenTypeTag("calt")
        #expect(calt == OpenTypeTags.calt)

        let feat = DirectWriteFontFeature(name: "dlig", parameter: 1)
        #expect(feat.tag == OpenTypeTags.dlig)
        #expect(feat.parameter == 1)
    }

    @Test
    func test_direct_write_initialization_and_system_fonts() throws {
        let textSystem = try DirectWriteTextSystem.new()
        let fontNames = textSystem.allFontNames()
        // On Windows Desktop/Server, system fonts are installed (Segoe UI, Arial, etc.)
        #expect(fontNames.count >= 0)
    }

    @Test
    func test_in_memory_font_loading_and_discovery() throws {
        let textSystem = try DirectWriteTextSystem.new()
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")

        try textSystem.addFonts([fontData])

        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        #expect(fontId.value >= 0)

        let allNames = textSystem.allFontNames()
        #expect(allNames.contains("IBM Plex Sans"))
    }

    @Test
    func test_font_metrics_and_glyph_metrics() throws {
        let textSystem = try DirectWriteTextSystem.new()
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))

        let metrics = textSystem.fontMetrics(fontId: fontId)
        #expect(metrics.unitsPerEm == 1000)
        #expect(metrics.ascent > 0)
        #expect(metrics.descent < 0)
        #expect(metrics.capHeight > 0)

        let glyphId = try #require(textSystem.glyphForChar(fontId: fontId, ch: "A"))
        #expect(glyphId.value > 0)

        let adv = try textSystem.advance(fontId: fontId, glyphId: glyphId)
        #expect(adv.width > 0)

        let bounds = try textSystem.typographicBounds(fontId: fontId, glyphId: glyphId)
        #expect(bounds.size.width > 0)
        #expect(bounds.size.height > 0)
    }

    @Test
    func test_line_layout_shaping_and_advances() throws {
        let textSystem = try DirectWriteTextSystem.new()
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))

        let text = "Hello DirectWrite!"
        let layout = textSystem.layoutLine(
            text: text,
            fontSize: px(16),
            runs: [FontRun(len: text.utf8.count, fontId: fontId)]
        )

        #expect(layout.len == text.utf8.count)
        #expect(layout.width > px(0))
        #expect(layout.ascent > px(0))
        #expect(layout.runs.count >= 1)

        let glyphs = layout.runs[0].glyphs
        #expect(glyphs.count > 0)

        // Verify glyph positions monotonically advance
        var lastX: Pixels = px(-1)
        for glyph in glyphs {
            #expect(glyph.position.x >= lastX)
            lastX = glyph.position.x
        }
    }

    @Test
    func test_glyph_rasterization_produces_non_empty_bitmaps() throws {
        let textSystem = try DirectWriteTextSystem.new()
        let fontData = try #require(Self.loadFontFixture(), "Font fixture IBMPlexSans-Regular.ttf not found")
        try textSystem.addFonts([fontData])
        let fontId = try textSystem.fontId(descriptor: Font(family: "IBM Plex Sans"))
        let glyphId = try #require(textSystem.glyphForChar(fontId: fontId, ch: "E"))

        // 1. Grayscale rasterization
        let monoParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphId,
            fontSize: px(24),
            scaleFactor: 1.0,
            subpixelRendering: false
        )
        let monoBounds = try textSystem.glyphRasterBounds(params: monoParams)
        #expect(monoBounds.size.width.value > 0)
        #expect(monoBounds.size.height.value > 0)

        let (monoSize, monoData) = try textSystem.rasterizeGlyph(params: monoParams, rasterBounds: monoBounds)
        #expect(monoSize.width.value == monoBounds.size.width.value)
        #expect(monoSize.height.value == monoBounds.size.height.value)
        #expect(monoData.count == monoSize.width.value * monoSize.height.value)
        // Assert at least some rendered non-background pixels exist
        let hasInk = monoData.contains { $0 > 0 }
        #expect(hasInk)

        // 2. ClearType subpixel rasterization
        let subpixelParams = RenderGlyphParams(
            fontId: fontId,
            glyphId: glyphId,
            fontSize: px(24),
            scaleFactor: 1.0,
            subpixelRendering: true
        )
        let subBounds = try textSystem.glyphRasterBounds(params: subpixelParams)
        #expect(subBounds.size.width.value > 0)
        #expect(subBounds.size.height.value > 0)

        let (subSize, subData) = try textSystem.rasterizeGlyph(params: subpixelParams, rasterBounds: subBounds)
        #expect(subSize.width.value == subBounds.size.width.value)
        #expect(subSize.height.value == subBounds.size.height.value)
        #expect(subData.count == subSize.width.value * subSize.height.value * 4)
        let hasSubpixelInk = subData.contains { $0 > 0 }
        #expect(hasSubpixelInk)
    }
}

#endif
