// Tests ported from: crates/gpui_macos/src/text_system.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(macOS)
import GPUI
import Testing
@testable import GPUIMacOS

@Suite("GPUIMacOS TextSystem Tests")
struct MacTextSystemTests {
    @Test("test_layout_line_bom_char")
    func testLayoutLineBomChar() throws {
        let fonts = MacTextSystem.new()
        let fontId = try fonts.fontId(descriptor: font("Helvetica"))

        var line = "\u{feff}"
        var style = [
            FontRun(len: line.utf8.count, fontId: fontId),
        ]
        var layout = fonts.layoutLine(text: line, fontSize: px(16.0), runs: style)
        #expect(layout.len == line.utf8.count)
        #expect(layout.runs.isEmpty)

        line = "a\u{feff}b"
        style = [
            FontRun(len: line.utf8.count, fontId: fontId),
        ]
        layout = fonts.layoutLine(text: line, fontSize: px(16.0), runs: style)
        #expect(layout.len == line.utf8.count)
        #expect(layout.runs.count == 1)
        #expect(layout.runs[0].glyphs.count == 2)
        #expect(layout.runs[0].glyphs[0].id == GlyphId(68)) // a
        #expect(layout.runs[0].glyphs[1].id == GlyphId(69)) // b

        line = "\u{feff}ab"
        style = [
            FontRun(len: "\u{feff}".utf8.count, fontId: fontId),
            FontRun(len: "ab".utf8.count, fontId: fontId),
        ]
        layout = fonts.layoutLine(text: line, fontSize: px(16.0), runs: style)
        #expect(layout.len == line.utf8.count)
        #expect(layout.runs.count == 1)
        #expect(layout.runs[0].glyphs.count == 2)
        #expect(layout.runs[0].glyphs[0].id == GlyphId(68)) // a
        #expect(layout.runs[0].glyphs[0].index == 3)
        #expect(layout.runs[0].glyphs[1].id == GlyphId(69)) // b
        #expect(layout.runs[0].glyphs[1].index == 4)

        // Mid-line FontRun starting with U+FEFF must not strip BOM or shift subsequent UTF-8 indices
        line = "a\u{feff}bc"
        style = [
            FontRun(len: "a".utf8.count, fontId: fontId),
            FontRun(len: "\u{feff}bc".utf8.count, fontId: fontId),
        ]
        layout = fonts.layoutLine(text: line, fontSize: px(16.0), runs: style)
        #expect(layout.len == line.utf8.count)
        #expect(layout.runs.count == 1)
        #expect(layout.runs[0].glyphs.count == 3)
        #expect(layout.runs[0].glyphs[0].id == GlyphId(68)) // a
        #expect(layout.runs[0].glyphs[0].index == 0)
        #expect(layout.runs[0].glyphs[1].id == GlyphId(69)) // b (exact UTF-8 byte 4 after 1-byte 'a' + 3-byte U+FEFF)
        #expect(layout.runs[0].glyphs[1].index == 4)
        #expect(layout.runs[0].glyphs[2].id == GlyphId(70)) // c (exact UTF-8 byte 5)
        #expect(layout.runs[0].glyphs[2].index == 5)
    }

    @Test("test_layout_line_zwnj_insertion")
    func testLayoutLineZwnjInsertion() throws {
        let fonts = MacTextSystem.new()
        let fontId = try fonts.fontId(descriptor: font("Helvetica"))
        let fontId2 = try fonts.fontId(descriptor: font("Times"))

        let text = "hello world"
        let runs = [
            FontRun(len: 5, fontId: fontId),  // "hello"
            FontRun(len: 6, fontId: fontId),  // " world"
        ]
        let layout = fonts.layoutLine(text: text, fontSize: px(16.0), runs: runs)
        #expect(layout.len == text.utf8.count)
        for run in layout.runs {
            for glyph in run.glyphs {
                #expect(glyph.index < text.utf8.count, "Glyph index \(glyph.index) is out of bounds for text length \(text.utf8.count)")
            }
        }

        let runsDifferentFonts = [
            FontRun(len: 5, fontId: fontId),   // "hello"
            FontRun(len: 6, fontId: fontId2),  // " world"
        ]
        let layout2 = fonts.layoutLine(text: text, fontSize: px(16.0), runs: runsDifferentFonts)
        #expect(layout2.len == text.utf8.count)
        for run in layout2.runs {
            for glyph in run.glyphs {
                #expect(glyph.index < text.utf8.count, "Glyph index \(glyph.index) is out of bounds for text length \(text.utf8.count)")
            }
        }
    }

    @Test("test_layout_line_zwnj_edge_cases")
    func testLayoutLineZwnjEdgeCases() throws {
        let fonts = MacTextSystem.new()
        let fontId = try fonts.fontId(descriptor: font("Helvetica"))

        // Single run - no font size tweak needed
        let text1 = "hello"
        let runs1 = [FontRun(len: 5, fontId: fontId)]
        let layout1 = fonts.layoutLine(text: text1, fontSize: px(16.0), runs: runs1)
        #expect(layout1.len == text1.utf8.count)

        // Multiple single-char runs
        let text2 = "abc"
        let runs2 = [
            FontRun(len: 1, fontId: fontId),
            FontRun(len: 1, fontId: fontId),
            FontRun(len: 1, fontId: fontId),
        ]
        let layout2 = fonts.layoutLine(text: text2, fontSize: px(16.0), runs: runs2)
        #expect(layout2.len == text2.utf8.count)
        for run in layout2.runs {
            for glyph in run.glyphs {
                #expect(glyph.index < text2.utf8.count, "Glyph index \(glyph.index) should be < \(text2.utf8.count)")
            }
        }

        // Empty runs list
        let text3 = ""
        let runs3: [FontRun] = []
        let layout3 = fonts.layoutLine(text: text3, fontSize: px(16.0), runs: runs3)
        #expect(layout3.len == 0)
        #expect(layout3.runs.isEmpty)
    }
}
#endif
