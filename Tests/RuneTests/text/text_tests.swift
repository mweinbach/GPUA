// Tests ported from: crates/rune/src/text/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

@Suite("Text shaping, fallbacks, tabs, ligatures, oblique, emoji, and Run cells")
struct TextShapingTests {
    private func glyphIds(_ text: String) -> [UInt16] {
        let ts = TextSystem()
        let layout = ts.layoutRich(text, [], TextStyle.new(13.0, 400.0), 2.0, nil)
        var ids: [UInt16] = []
        for line in layout.lines() {
            for item in line.items() {
                if case .glyphRun(let run) = item {
                    ids.append(contentsOf: run.glyphs().map { $0.id })
                }
            }
        }
        return ids
    }

    @Test("cjk_falls_back_to_an_installed_font")
    func cjkFallsBackToInstalledFont() {
        if systemFontFiles(CJK_FONT_FILES).isEmpty {
            return
        }
        let han = glyphIds("你好世界")
        #expect(han.count == 4)
        #expect(han.allSatisfy { $0 != 0 }, "tofu: \(han)")
        #expect(glyphIds("Hello") == glyphIds("Hello"))
    }

    @Test("hangul_kana_and_han_fall_back_to_installed_fonts")
    func hangulKanaAndHanFallBackToInstalledFonts() {
        let installed = { (fragments: [String]) in !systemFontFiles(fragments).isEmpty }
        let korean = installed(["applesdgothicneo", "malgun", "notosanskr", "notosanscjk", "applegothic"])
        let japanese = installed(["hiragino", "yugoth", "meiryo", "notosansjp", "notosanscjk"])
        for (text, hasFont) in [("안녕하세요 세계", korean), ("こんにちは世界", japanese), ("你好世界", installed(CJK_FONT_FILES))] {
            guard hasFont else { continue }
            let ids = glyphIds(text)
            #expect(ids.allSatisfy { $0 != 0 }, "tofu in \(text): \(ids)")
        }
    }

    @Test("a_tab_draws_as_a_space")
    func tabDrawsAsSpace() {
        #expect(glyphIds("a\tb") == glyphIds("a b"))
        let ts = TextSystem()
        let sans = TextStyle.new(13.0, 400.0)
        #expect(ts.measure("\tx", sans, 2.0) == ts.measure(" x", sans, 2.0))
    }

    @Test("mono_tabs_fill_to_four_column_stops")
    func monoTabsFillToFourColumnStops() {
        let ts = TextSystem()
        let mono = TextStyle.new(13.0, 400.0).family(.mono)
        func width(_ text: String, _ spans: [Span], _ style: TextStyle) -> Float {
            ts.layoutRich(text, spans, style, 2.0, nil).fullWidth()
        }
        let pairs = [
            ("\tx", "    x"),
            ("ab\tx", "ab  x"),
            ("abc\tx", "abc x"),
            ("abcd\tx", "abcd    x"),
            ("\t\tx", "        x"),
            ("  \tx", "    x")
        ]
        for (tabbed, spaced) in pairs {
            let a = width(tabbed, [], mono)
            let b = width(spaced, [], mono)
            #expect(abs(a - b) < 0.01, "\(tabbed): \(a) vs \(spaced): \(b)")
        }

        let sans = TextStyle.new(13.0, 400.0)
        func monoSpan(_ text: String, _ from: Int) -> [Span] {
            [Span.new(from, text.utf8.count).mono()]
        }
        let tabbed = "Run a\tb"
        let spaced = "Run a   b"
        let a = width(tabbed, monoSpan(tabbed, 4), sans)
        let b = width(spaced, monoSpan(spaced, 4), sans)
        #expect(abs(a - b) < 0.01, "\(a) vs \(b)")

        let l1 = ts.layoutRich("x\n\ty", monoSpan("x\n\ty", 0), sans, 2.0, nil)
        let y1 = clusterFromByteIndex(l1, 3)!.2
        let l2 = ts.layoutRich("x\n    y", monoSpan("x\n    y", 0), sans, 2.0, nil)
        let y2 = clusterFromByteIndex(l2, 6)!.2
        #expect(abs(y1 - y2) < 0.01, "\(y1) vs \(y2)")

        #expect(ts.measure("\tx", sans, 2.0) == ts.measure(" x", sans, 2.0))
    }

    @Test("mono_text_has_no_ligatures")
    func monoTextHasNoLigatures() {
        #if !os(WASI)
        guard upstreamRuneCrateDir() != nil else { return }
        #endif
        let ts = TextSystem()
        func ids(_ text: String, _ spans: [Span], _ style: TextStyle) -> [UInt16] {
            let layout = ts.layoutRich(text, spans, style, 2.0, nil)
            var out: [UInt16] = []
            for line in layout.lines() {
                for item in line.items() {
                    if case .glyphRun(let run) = item {
                        out.append(contentsOf: run.glyphs().map { $0.id })
                    }
                }
            }
            return out
        }
        let sans = TextStyle.new(13.0, 400.0)
        let mono = sans.family(.mono)
        let apart = ["a", "-", ">", "b"].flatMap { ids($0, [], mono) }
        #if os(macOS)
        #expect(ids("a->b", [], sans) != apart, "fixture: Inter's arrow in prose")
        let proseArrow = ids("a->b", [], sans)
        let mixed = ids("a->ba->ba->b", [Span.new(4, 8).mono()], sans)
        #expect(mixed == proseArrow + apart + proseArrow)
        #endif
        #expect(ids("a->b", [], mono) == apart)
        #expect(ids("a->b", [Span.new(0, 4).mono()], sans) == apart)
        #expect(ids("a->b", [Span.new(0, 4).mono().size(20.0)], sans) == apart)
    }

    @Test("system_mono_is_monospaced_or_the_mono_slot")
    func systemMonoIsMonospacedOrMonoSlot() {
        let ts = TextSystem()
        let style = TextStyle.new(13.0, 400.0).family(.systemMono)
        func width(_ text: String, _ s: TextStyle) -> Float {
            ts.layoutRich(text, [], s, 2.0, nil).fullWidth()
        }
        if ts.systemMono().isEmpty {
            #expect(width("iiii MMMM", style) == width("iiii MMMM", style.mono()))
            return
        }
        let narrow = width("iiiiiiii", style)
        let wide = width("MMMMMMMM", style)
        #expect(abs(narrow - wide) < 0.5, "\(narrow) vs \(wide)")
        #expect(width("iiiiiiii", TextStyle.new(13.0, 400.0)) < narrow * 0.7, "the sans slot is proportional")
        let italic = width("iiiiiiii", style.italic())
        #expect(abs(italic - narrow) < 0.5, "italic keeps the cell: \(italic) vs \(narrow)")
    }

    @Test("ui_monospace_in_the_mono_slot_is_system_mono")
    func uiMonospaceInMonoSlotIsSystemMono() {
        func fontIds(_ ts: TextSystem, _ text: String, _ spans: [Span], _ style: TextStyle) -> [(UInt64, UInt32)] {
            let layout = ts.layoutRich(text, spans, style, 2.0, nil)
            var out: [(UInt64, UInt32)] = []
            for line in layout.lines() {
                for item in line.items() {
                    if case .glyphRun(let run) = item {
                        out.append((run.font.fontId, run.font.index))
                    }
                }
            }
            return out
        }
        let code = [Span.new(4, 8).mono()]
        let ts = TextSystem([], ("Inter", "ui-monospace, Inter"))
        let block = fontIds(ts, "code", [], TextStyle.new(13.0, 400.0).family(.systemMono))
        let spans = fontIds(ts, "see code", code, TextStyle.new(13.0, 400.0))
        #expect(spans.last?.0 == block.last?.0 && spans.last?.1 == block.last?.1)
        let monoSlot = fontIds(ts, "code", [], TextStyle.new(13.0, 400.0).mono())
        #expect(monoSlot.map(\.0) == block.map(\.0))
        if !ts.systemMono().isEmpty {
            let plain = TextSystem([], ("Inter", "Inter"))
            let plainSpans = fontIds(plain, "see code", code, TextStyle.new(13.0, 400.0))
            #expect(plainSpans.last?.0 != block.last?.0)
        }
    }

    @Test("ui_monospace_with_no_mono_font_falls_back_to_sans")
    func uiMonospaceWithNoMonoFontFallsBackToSans() {
        func names(_ list: String, _ mono: [String]) -> [String] {
            parsedFamilyList(list, mono, "Inter, sans-serif").map { item in
                switch item {
                case .named(let n): return n
                case .generic(let g): return g.rawValue
                }
            }
        }
        #expect(names("ui-monospace", []) == ["Inter", "SansSerif"])
        #expect(names("ui-monospace", ["Menlo"]) == ["Menlo"])
        #expect(names("ui-monospace, Iosevka", []) == ["Iosevka"])
        #expect(names("monospace", []) == ["Monospace"])
    }

    @Test("italic_uses_the_real_face_or_a_synthetic_oblique")
    func italicUsesRealFaceOrSyntheticOblique() {
        let ts = TextSystem()
        let upright = TextStyle.new(13.0, 400.0)
        func skews(_ text: String, _ spans: [Span], _ style: TextStyle) -> [(Range<Int>, UInt8)] {
            let layout = ts.layoutRich(text, spans, style, 2.0, nil)
            var out: [(Range<Int>, UInt8)] = []
            for line in layout.lines() {
                for item in line.items() {
                    if case .glyphRun(let run) = item {
                        out.append((run.textRange, run.font.skewDegrees))
                    }
                }
            }
            return out
        }
        #expect(skews("Hello", [], upright).allSatisfy { $0.1 == 0 })
        #expect(skews("Hello", [], upright.italic()).allSatisfy { $0.1 > 0 }, "Inter has no italic")
        let spans = [Span.new(6, 10).italic()]
        for (range, skew) in skews("plain emph", spans, upright) {
            #expect((skew > 0) == (range.lowerBound >= 6))
        }
        func firstQuad(_ s: TextStyle) -> GlyphQuad {
            let l = ts.layoutRich("l", [], s, 2.0, nil)
            var q: [GlyphQuad] = []
            ts.glyphsForLayout(l, 2.0, [0.0, 0.0], false, &q)
            return q[0]
        }
        let a = firstQuad(upright)
        let b = firstQuad(upright.italic())
        #expect(b.rect[2] >= a.rect[2] + 3.0, "upright \(a.rect), oblique \(b.rect)")

        #if os(macOS)
        let real = "System Font"
        #else
        let real = "DejaVu Sans"
        #endif
        if ts.hasFamily(real) {
            let style = upright.family(.named(real)).italic()
            for (_, skew) in skews("Hello", [], style) {
                #expect(skew == 0)
            }
        }
    }

    @Test("scripts_load_their_system_fonts_on_first_use")
    func scriptsLoadTheirSystemFontsOnFirstUse() {
        let ts = TextSystem()
        _ = ts.layoutRich("Hello, “café” — naïve…", [], TextStyle.new(13.0, 400.0), 2.0, nil)
        #expect(ts.scriptsMask == 0, "Latin text must not load script fallbacks")
        let samples = ["שלום עולם", "مرحبا بالعالم", "नमस्ते दुनिया", "ওহে বিশ্ব", "สวัสดีชาวโลก"]
        for (fonts, sample) in zip(SCRIPT_FONTS, samples) {
            #expect(sample.unicodeScalars.contains { fonts.covers($0) })
            if systemFontFiles(fonts.files).isEmpty {
                continue
            }
            let layout = ts.layoutRich("a \(sample)", [], TextStyle.new(13.0, 400.0), 2.0, nil)
            for line in layout.lines() {
                for item in line.items() {
                    if case .glyphRun(let run) = item {
                        #expect(run.glyphs().allSatisfy { $0.id != 0 }, "tofu in \(sample)")
                    }
                }
            }
        }
    }

    @Test("routes_merge_math_and_emoji_presentation")
    func routesMergeMathAndEmojiPresentation() {
        let r1 = routes("a 𝐀𝐁 b 𝟎")
        #expect(r1.count == 2)
        #expect(r1[0].0 == 2..<10 && r1[0].1 == .math)
        #expect(r1[1].0 == 13..<17 && r1[1].1 == .math)
        #expect(routes("plain ascii").isEmpty)

        let heart = "❤\u{FE0F}"
        let flag = "🏳\u{FE0F}\u{200D}🌈"
        let flagAt = 1 + heart.utf8.count + "❤".utf8.count
        let r2 = routes("a\(heart)❤\(flag)")
        #expect(r2.count == 2)
        #expect(r2[0].0 == 1..<(1 + heart.utf8.count) && r2[0].1 == .emoji)
        #expect(r2[1].0 == flagAt..<(flagAt + flag.utf8.count) && r2[1].1 == .emoji)
    }

    #if os(macOS)
    @Test("plex_keyboard_symbols_and_cap_height_and_colour_emoji")
    func macosKeyboardSymbolsAndColourEmoji() {
        var plexFonts: [[UInt8]] = []
        if let crateDir = upstreamRuneCrateDir() {
            let plexPath = "\(crateDir)/../../themes/opencode/assets/fonts/IBMPlexMono-Regular.ttf"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: plexPath)) {
                plexFonts = [[UInt8](data)]
            }
        }
        if !plexFonts.isEmpty && !systemFontFiles(["sfnsttf"]).isEmpty {
            let ts = TextSystem(plexFonts, ("IBM Plex Mono", "IBM Plex Mono"))
            for size in [Float(13.0), Float(15.0)] {
                let layout = ts.layoutRich("H⌘⇧⏎⌫⎋⌥", [], TextStyle.new(size, 400.0).mono(), 2.0, nil)
                var extents: [(Double, Double)] = []
                for line in layout.lines() {
                    for item in line.items() {
                        guard case .glyphRun(let gr) = item else { continue }
                        for g in gr.glyphs() {
                            if let outline = ts.extractDesignOutline(font: gr.font, glyph: UInt16(clamping: g.id), ppem: Double(gr.fontSize)) {
                                var maxY = -Double.infinity
                                var minY = Double.infinity
                                for cmd in outline {
                                    switch cmd {
                                    case .move(let p), .line(let p):
                                        maxY = max(maxY, p.y); minY = min(minY, p.y)
                                    case .quad(_, let p), .cubic(_, _, let p):
                                        maxY = max(maxY, p.y); minY = min(minY, p.y)
                                    case .close:
                                        break
                                    }
                                }
                                extents.append((maxY, minY))
                            }
                        }
                    }
                }
                if extents.count == 7 {
                    let cap = extents[0].0
                    for (idx, (top, bottom)) in extents.enumerated().dropFirst() {
                        #expect(abs(top / cap - 1.0) < 0.12, "symbol \(idx) at \(size)pt: top \(top) vs cap \(cap)")
                        #expect(abs(bottom) < cap * 0.06, "symbol \(idx) at \(size)pt: bottom \(bottom)")
                    }
                }
            }
        }

        let ts = TextSystem()
        func colourCount(_ text: String) -> Int {
            let layout = ts.layoutRich(text, [], TextStyle.new(13.0, 400.0), 2.0, nil)
            var quads: [GlyphQuad] = []
            ts.glyphsForLayout(layout, 2.0, [0.0, 0.0], false, &quads)
            return quads.filter { $0.color != 0 }.count
        }
        #expect(colourCount("a❤\u{FE0F}b ☀\u{FE0F} ✔\u{FE0F}") == 3)
        #expect(colourCount("a❤b ☺\u{FE0E}") == 0)
        #expect(colourCount("🏳\u{FE0F}\u{200D}🌈 👩🏽\u{200D}💻") == 2)

        let style = TextStyle.new(13.0, 400.0)
        let layout = ts.layoutRich("Done 🎉", [], style, 2.0, nil)
        var quads: [GlyphQuad] = []
        ts.glyphsForLayout(layout, 2.0, [0.0, 0.0], false, &quads)
        let letters = quads.filter { $0.color == 0 }
        let emoji = quads.filter { $0.color != 0 }
        #expect(letters.count == 4 && emoji.count == 1)
        let e = emoji[0]
        let d = letters[0]
        #expect(e.rect[0] > letters[3].rect[0] + letters[3].rect[2])
        #expect((20.0..<40.0).contains(e.rect[3]))
        #expect(e.rect[1] < d.rect[1] + d.rect[3] && e.rect[1] + e.rect[3] > d.rect[1])
        let pixels = ts.colorGlyph(e.color)
        let (pw, ph) = pixels.size()
        #expect(Float(pw) == e.rect[2] && Float(ph) == e.rect[3])

        var again: [GlyphQuad] = []
        ts.glyphsForLayout(layout, 2.0, [0.0, 0.0], false, &again)
        #expect(again.filter { $0.color != 0 }.map(\.color) == [e.color])
        #expect(ts.colorPixels.count >= 1)
    }
    #endif

    @Test("run_cells_draw_the_run_glyphs_and_marks_stay_with_their_base")
    func runCellsDrawRunGlyphsAndMarksStayWithBase() {
        let ts = TextSystem()
        let style = tok.type_.BODY
        let run = Run.new("x\u{301}yAV")
        let r = ts.runLayout(run, style, 2.0)
        var whole: [GlyphQuad] = []
        ts.glyphsForLayout(r.layout!, 2.0, [0.0, 0.0], false, &whole)
        var cells: [[GlyphQuad]] = []
        for at in [0, 3, 4, 5] {
            var one: [GlyphQuad] = []
            ts.glyphsIn(r, at, 2.0, [0.0, 0.0], &one)
            cells.append(one)
        }
        #expect(cells.map(\.count) == [2, 1, 1, 1], "the accent draws in the x cell")
        let rects = cells.flatMap { $0 }.map(\.rect)
        #expect(rects == whole.map(\.rect), "cells draw exactly the run's glyphs")
        let sum = [0, 3, 4, 5].reduce(Float(0)) { $0 + (r.advance($1, 2.0) ?? 0) }
        #expect(abs(sum - ts.measure(run.asStr(), style, 2.0).0) < 1e-3, "\(sum)")
    }

    @Test("run_lookups_off_a_grapheme_start_find_nothing")
    func runLookupsOffGraphemeStartFindNothing() {
        let ts = TextSystem()
        let run = Run.new("x\u{301}y")
        let r = ts.runLayout(run, tok.type_.BODY, 2.0)
        for at in [1, 2, 4, 99] {
            #expect(r.x(at) == nil && r.advance(at, 2.0) == nil, "byte \(at)")
            var out: [GlyphQuad] = []
            ts.glyphsIn(r, at, 2.0, [0.0, 0.0], &out)
            #expect(out.isEmpty)
        }
    }
}
