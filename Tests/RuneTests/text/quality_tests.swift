// Tests ported from: crates/rune/src/text/quality_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import struct RuneMotion.Animated
import struct RuneMotion.Spring
@testable import Rune

@Suite("Text rendering quality, pills, decorations, underlines, and atlas stability")
struct QualityTests {
    @Test("centred_wrapped_lines_centre_each_line_in_the_wrap_width")
    func centredWrappedLinesCentreEachLineInWrapWidth() {
        let text = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let content = "a much longer first line of words that wraps\nshort"
        let width: Float = 400.0
        let start = text.layoutRich(content, [], style, 2.0, width)
        let centred = text.layoutAligned(content, [], style, 2.0, width, .center)
        #expect(start !== centred, "alignment is part of the cache key")

        func offsets(_ l: TextLayout) -> [(Float, Float)] {
            l.lines().map { line in
                let m = line.metrics()
                return (m.offset, m.advance - m.hangingAdvance)
            }
        }
        #expect(offsets(start).allSatisfy { $0.0 == 0.0 })
        let lines = offsets(centred)
        #expect(lines.count >= 2)
        for (offset, adv) in lines {
            #expect(abs(offset - (width - adv) / 2.0) < 1.0, "offset \(offset) advance \(adv)")
        }
    }

    // PORT NOTE: Computes drawn line glyph extents directly from `TextSystem.layoutAligned` + `glyphsForLayout`
    // because `Runtime` is ported in a separate worker scope.
    private func lineSpans(_ content: String, _ align: Align, _ justify: Bool) -> [(Float, Float)] {
        let ts = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let width: Float = 300.0 * 2.0
        let layout = ts.layoutAligned(content, [], style, 2.0, width, TextAlignment(align, justify: justify))
        var quads: [GlyphQuad] = []
        ts.glyphsForLayout(layout, 2.0, [0.0, 0.0], false, &quads)
        let sorted = quads.sorted { ($0.rect[1] + $0.rect[3] * 0.5) < ($1.rect[1] + $1.rect[3] * 0.5) }
        var lines: [(Float, Float, Float)] = []
        for q in sorted {
            let cy = q.rect[1] + q.rect[3] * 0.5
            if let last = lines.last, cy - last.0 < 16.0 {
                lines[lines.count - 1].1 = min(last.1, q.rect[0])
                lines[lines.count - 1].2 = max(last.2, q.rect[0] + q.rect[2])
            } else {
                lines.append((cy, q.rect[0], q.rect[0] + q.rect[2]))
            }
        }
        return lines.map { ($0.1, $0.2) }
    }

    @Test("justified_text_fills_each_wrapped_line_but_the_last")
    func justifiedTextFillsEachWrappedLineButLast() {
        let content = "the quick brown fox jumps over the lazy dog while five boxing wizards jump quickly and pack my box with five dozen liquor jugs"
        let justified = lineSpans(content, .start, true)
        #expect(justified.count >= 3)
        for (l, r) in justified.dropLast() {
            #expect(l < 8.0 && r > 592.0, "justified line spans \(l)..\(r)")
        }
        let start = lineSpans(content, .start, false)
        #expect(start.count == justified.count, "justifying never rewraps")
        #expect(start.dropLast().contains { $0.1 < 592.0 }, "start lines stay ragged: \(start)")
    }

    @Test("wrapped_right_to_left_text_aligns_and_justifies_from_the_right")
    func wrappedRtlTextAlignsAndJustifiesFromRight() {
        let hebrew = "שלום עולם זהו טקסט ארוך שנשבר לכמה שורות כדי לבדוק יישור מימין לשמאל בתוך רוחב קבוע של האלמנט"
        let start = lineSpans(hebrew, .start, false)
        if start.isEmpty {
            return
        }
        #expect(start.count >= 2)
        #expect(start.allSatisfy { $0.1 > 592.0 }, "wrapped RTL start hugs the right edge: \(start)")
        let end = lineSpans(hebrew, .end, false)
        #expect(end.allSatisfy { $0.0 < 8.0 }, "wrapped RTL end hugs the left edge: \(end)")
        let justified = lineSpans(hebrew, .start, true)
        let last = justified.count - 1
        #expect(justified[0..<last].allSatisfy { $0.0 < 8.0 && $0.1 > 592.0 })
        #expect(justified[last].1 > 592.0, "justified RTL last line starts at the right: \(justified)")
    }

    private func byteOffset(of needle: String, in haystack: String) -> Int {
        guard let r = haystack.range(of: needle) else { return 0 }
        return haystack.utf8.distance(from: haystack.utf8.startIndex, to: r.lowerBound)
    }

    @Test("inline_code_and_its_padding_share_one_chip")
    func inlineCodeAndItsPaddingShareOneChip() {
        let text = TextSystem()
        let bg = Color.BLACK.alpha(0.08)
        let content = "say \u{202f}code\u{202f} now"
        let a = byteOffset(of: "c", in: content)
        let b = byteOffset(of: " now", in: content)
        func pad(_ s: Int, _ e: Int) -> Span {
            var sp = Span.new(s, e)
            sp.bg = bg
            return sp
        }
        var code = Span.new(a, b - 3)
        code.mono = true
        code.size = 13.0 * 0.9
        code.bg = bg
        let spans = [pad(4, a), code, pad(b - 3, b)]
        let style = TextStyle.new(13.0, 400.0)
        let layout = text.layoutRich(content, spans, style, 2.0, nil)
        var decos: [Deco] = []
        text.decorations(layout, spans, 2.0, [0.0, 0.0], &decos)
        #expect(decos.count == 1)

        var alone: [Deco] = []
        let codeOnly = text.layoutRich(content, [code], style, 2.0, nil)
        text.decorations(codeOnly, [code], 2.0, [0.0, 0.0], &alone)
        #expect(decos[0].rect[1] == alone[0].rect[1] && decos[0].rect[3] == alone[0].rect[3], "the code's height")
        #expect(decos[0].rect[2] > alone[0].rect[2], "padding widens it")
    }

    @Test("pill_chips_keep_room_and_never_overlap_at_wraps")
    func pillChipsKeepRoomAndNeverOverlapAtWraps() {
        let dot = Icon(name: "dot", view: 24.0, body: #"<circle cx="12" cy="12" r="8"/>"#)
        let text = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let content = "ask @code-reviewer about @src/main.rs and @notes today please"
        let pills: [PillChip] = ["@code-reviewer", "@src/main.rs", "@notes"].enumerated().map { k, label in
            let s = UInt32(byteOffset(of: label, in: content))
            return PillChip(start: s, end: s + UInt32(label.utf8.count), icon: k == 1 ? dot : nil, bg: nil, fg: nil)
        }
        let scale: Float = 2.0
        let bare = text.layoutBlocks(content, [], [], [], style, scale, nil, .start)
        let one = text.layoutBlocks(content, [], [], pills, style, scale, nil, .start)
        let pm = PillMetrics(14.0)
        let room = (pm.lead(false) + pm.lead(true) + pm.lead(false) + 3.0 * pm.trail()) * scale
        #expect(abs(one.fullWidth() - bare.fullWidth() - room) < 4.0, "\(one.fullWidth()) vs \(bare.fullWidth())")

        let utf8Bytes = Array(content.utf8)
        for width in stride(from: 123, through: 420, by: 9) {
            let maxW = Float(width) * scale
            let layout = text.layoutBlocks(content, [], [], pills, style, scale, maxW, .start)
            var chips: [PaintedDeco] = []
            var icons: [(Icon, UInt32, [Float], Color?)] = []
            pillChips(layout, pills, 14.0, scale, [0.0, 0.0], Color.BLACK, &chips, &icons)
            #expect(chips.count == 3, "each pill draws one chip at width \(width)")
            #expect(icons.count == 1)
            let (_, px, at, _) = icons[0]
            let chip = chips[1].deco.rect
            #expect(at[0] >= chip[0] && at[0] + Float(px) <= chip[0] + chip[2] + 0.5, "icon inside its chip at width \(width)")

            func lineOf(_ byte: Int) -> Int {
                layout.lines().firstIndex(where: { $0.textRange().contains(byte) }) ?? 0
            }
            for p in pills {
                #expect(lineOf(Int(p.start)) == lineOf(Int(p.end) - 1), "no wrap inside a pill at width \(width)")
            }
            for (k, c) in chips.enumerated() {
                let r = c.deco.rect
                let fits = r[0] + r[2] <= maxW + 0.5 || r[0] <= pm.margin * scale + 0.5
                #expect(fits, "chip \(k) \(r) overflows \(maxW) at width \(width)")
                for (j, d) in chips.enumerated() where j != k {
                    let sameRow = abs(r[1] - d.deco.rect[1]) < 1.0
                    #expect(!sameRow || r[0] + r[2] <= d.deco.rect[0] + 0.5 || d.deco.rect[0] + d.deco.rect[2] <= r[0] + 0.5, "chips \(k) and \(j) overlap")
                }
            }
            for (li, line) in layout.lines().enumerated() {
                for item in line.items() {
                    guard case .glyphRun(let gr) = item else { continue }
                    var x = gr.offset()
                    for cl in gr.visualClusters() {
                        let w = cl.advance
                        let x0 = x
                        let x1 = x + w
                        x += w
                        let range = cl.textRange
                        let isWs = utf8Bytes[range].allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A }
                        for (p, c) in zip(pills, chips) {
                            let inside = Int(p.start) <= range.lowerBound && range.upperBound <= Int(p.end)
                            let row = lineOf(Int(p.start)) == li
                            if row && !inside && !isWs {
                                #expect(x1 <= c.deco.rect[0] + 0.5 || c.deco.rect[0] + c.deco.rect[2] <= x0 + 0.5)
                            }
                            if inside {
                                #expect(x0 >= c.deco.rect[0] && x1 <= c.deco.rect[0] + c.deco.rect[2] + 0.5)
                            }
                        }
                    }
                }
            }
            for (p, c) in zip(pills, chips) {
                for (atByte, before) in [(Int(p.start), true), (Int(p.end), false)] {
                    let cur = TextCursor.fromByteIndex(layout, atByte, .downstream)
                    let x = Float(cursorGeometry(cur, layout, 1.0).x0)
                    let line = lineOf(min(atByte, utf8Bytes.count - 1))
                    if line == lineOf(Int(p.start)) {
                        let outside = before ? (x <= c.deco.rect[0] + 0.5) : (x >= c.deco.rect[0] + c.deco.rect[2] - 0.5)
                        #expect(outside, "caret at \(atByte) (\(x)) inside chip \(c.deco.rect) at width \(width)")
                    }
                }
            }
        }
    }

    @Test("a_pill_wider_than_its_line_wraps_inside_it")
    func pillWiderThanItsLineWrapsInsideIt() {
        let text = TextSystem()
        let style = TextStyle.new(14.0, 400.0)
        let label = "@Migrate config loader to the new schema"
        let content = "as in \(label) did"
        let start = UInt32(byteOffset(of: label, in: content))
        let pills = [PillChip(start: start, end: start + UInt32(label.utf8.count), icon: nil, bg: nil, fg: nil)]
        let scale: Float = 2.0

        for width in stride(from: 90, through: 200, by: 7) {
            let maxW = Float(width) * scale
            let layout = text.layoutBlocks(content, [], [], pills, style, scale, maxW, .start)
            var chips: [PaintedDeco] = []
            var icons: [(Icon, UInt32, [Float], Color?)] = []
            pillChips(layout, pills, 14.0, scale, [0.0, 0.0], Color.BLACK, &chips, &icons)
            let rows = layout.lines().filter { l in
                let r = l.textRange()
                return r.lowerBound < Int(pills[0].end) && Int(pills[0].start) < r.upperBound
            }
            #expect(rows.count >= 2, "the label wraps at width \(width)")
            #expect(chips.count == rows.count, "one chip per line at width \(width)")
            #expect(layout.width() <= maxW + 0.5, "the text stays inside \(maxW) at width \(width): \(layout.width())")
            for c in chips {
                let r = c.deco.rect
                #expect(r[0] >= -0.5 && r[0] + r[2] <= maxW + 0.5, "chip \(r) inside \(maxW) at width \(width)")
            }
        }
    }

    @Test("live_layouts_do_not_accumulate_between_commits")
    func liveLayoutsDoNotAccumulateBetweenCommits() {
        let text = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let stable = text.layoutRich("stable label", [], style, 2.0, nil)
        for tick in 0..<256 {
            _ = text.layoutLive("\(tick)", style, 2.0)
        }
        #expect(text.layouts.count == 1)
        #expect(stable === text.layoutRich("stable label", [], style, 2.0, nil))
    }

    @Test("a_view_shown_again_after_a_while_does_not_reshape")
    func viewShownAgainAfterAWhileDoesNotReshape() {
        let text = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let row = text.layoutRich("Back to the list", [], style, 2.0, nil)
        for _ in 0..<8 {
            text.endCommit()
        }
        let shaped = text.shaped
        #expect(row === text.layoutRich("Back to the list", [], style, 2.0, nil))
        #expect(text.shaped == shaped)
    }

    @Test("stale_layouts_stay_within_their_budget_newest_kept")
    func staleLayoutsStayWithinBudgetNewestKept() {
        let text = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let labels = (0..<1200).map { i in "label \(1000 + i)" }
        for label in labels {
            _ = text.layoutRich(label, [], style, 2.0, nil)
            text.endCommit()
        }
        for _ in 0..<2 {
            text.endCommit()
        }
        let cost = text.layouts.values.reduce(0) { $0 + Int($1.cost) }
        #expect(cost <= STALE_BYTES)
        #expect(cost > STALE_BYTES * 9 / 10)
        let kLast = textHash(labels[1199], [], style, 2.0, nil)
        let kFirst = textHash(labels[0], [], style, 2.0, nil)
        #expect(text.layouts[kLast] != nil)
        #expect(text.layouts[kFirst] == nil)
    }

    @Test("a_view_over_the_budget_keeps_a_budget_of_its_layouts")
    func viewOverBudgetKeepsBudgetOfItsLayouts() {
        let text = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let labels = (0..<1200).map { i in "label \(1000 + i)" }
        func show() {
            for label in labels {
                _ = text.layoutRich(label, [], style, 2.0, nil)
            }
        }
        show()
        for _ in 0..<2 {
            text.endCommit()
            #expect(text.layouts.count == 1200, "the current and previous commits are never evicted")
        }
        text.endCommit()
        let cost = text.layouts.values.reduce(0) { $0 + Int($1.cost) }
        #expect(cost <= STALE_BYTES)
        #expect(cost > STALE_BYTES * 9 / 10)
        let kept = text.layouts.count
        let shaped = text.shaped
        show()
        #expect(Int(text.shaped - shaped) == 1200 - kept, "shown again, only what was dropped reshapes")
        for _ in 0..<2 {
            text.endCommit()
            #expect(text.layouts.count == 1200, "the current and previous commits are never evicted")
        }
    }

    @Test("optical_size_default_keeps_static_font_glyphs_byte_identical")
    func opticalSizeDefaultKeepsStaticFontGlyphsByteIdentical() {
        let a = TextSystem()
        let b = TextSystem()
        for scale in [Float(1.0), Float(2.0)] {
            for size in [Float(11.0), Float(13.0), Float(24.0)] {
                let style = TextStyle.new(size, 400.0)
                var qa: [GlyphQuad] = []
                var qb: [GlyphQuad] = []
                a.glyphs("Hello ffi 0123456789", style, scale, [0.0, 0.0], &qa)
                b.glyphs("Hello ffi 0123456789", style.opticalSizing(.fontDefault), scale, [0.0, 0.0], &qb)
                #expect(qa == qb)
                #expect(a.atlas.data == b.atlas.data)
            }
        }
    }

    @Test("moving_glyphs_reuse_four_phases_and_land_without_atlas_work")
    func movingGlyphsReuseFourPhasesAndLandWithoutAtlasWork() {
        let text = TextSystem()
        let layout = text.layoutRich("lHEx ", [], TextStyle.new(13.0, 400.0), 2.0, nil)
        var quads: [GlyphQuad] = []
        for step in 0..<256 {
            quads.removeAll(keepingCapacity: true)
            text.glyphsForLayout(layout, 2.0, [-2.0 + Float(step) / 64.0, 12.37], false, &quads)
            #expect(quads.count == 4, "dilation must not turn whitespace into empty draw instances")
            #expect(quads.allSatisfy { $0.rect[0].truncatingRemainder(dividingBy: 1.0) == 0.0 && $0.rect[1].truncatingRemainder(dividingBy: 1.0) == 0.0 })
        }
        let entries = text.atlas.map.count
        #expect(entries <= 5 * 4, "four glyphs plus cached whitespace have at most four x phases")

        var track = Animated.new(Float(-2.0)).withClass(.spatial)
        track.animateTo(8.0, Spring.new(0.3, 0.0), 0.0)
        let end = track.settleTime()
        #expect(end.isFinite)

        text.atlas.dirty = nil
        quads.removeAll(keepingCapacity: true)
        text.glyphsForLayout(layout, 2.0, [8.0, 12.37], false, &quads)
        let landed = quads
        for frame in 0..<120 {
            let x = track.sample(end + Double(frame) / 120.0)
            #expect(x == 8.0, "the analytic tail lands on its target exactly")
            quads.removeAll(keepingCapacity: true)
            text.glyphsForLayout(layout, 2.0, [x, 12.37], false, &quads)
            #expect(quads == landed)
        }
        #expect(text.atlas.map.count == entries)
        #expect(text.atlas.dirty == nil)
    }

    @Test("glyphs_at_the_same_device_ppem_share_a_mask")
    func glyphsAtSameDevicePpemShareMask() {
        let text = TextSystem()
        text.setFontSmoothing(.on)
        let small = text.layoutRich("H", [], TextStyle.new(12.0, 400.0), 2.0, nil)
        let large = text.layoutRich("H", [], TextStyle.new(24.0, 400.0), 1.0, nil)
        var a: [GlyphQuad] = []
        var b: [GlyphQuad] = []
        text.glyphsForLayout(small, 2.0, [0.0, 0.0], false, &a)
        text.glyphsForLayout(large, 1.0, [0.0, 0.0], false, &b)
        #expect(a[0].uv == b[0].uv, "same device ppem and ink, same CoreGraphics mask")
    }

    @Test("atlas_capacity_never_overwrites_current_or_pinned_placements")
    func atlasCapacityNeverOverwritesCurrentOrPinnedPlacements() {
        var atlas = Atlas()
        let side = ATLAS_SIZE - 2
        let bitmap = [UInt8](repeating: 137, count: Int(side * side))
        for page in 0..<MAX_OVERFLOW_PAGES {
            let g = atlas.put(side, side, bitmap, 0, 0)!
            #expect(Int(g.page) == page)
        }
        #expect(atlas.put(side, side, bitmap, 0, 0) == nil)
        #expect(atlas.resets() == 0, "capacity must not invalidate emitted quads")

        atlas.beginFrame((1 << MAX_OVERFLOW_PAGES) - 1)
        #expect(atlas.put(side, side, bitmap, 0, 0) == nil)
        #expect(atlas.resets() == 0, "pinned pages cannot be recycled either")
        for page in 0..<MAX_OVERFLOW_PAGES {
            #expect(atlas.pageData(page)![Int(ATLAS_SIZE) + 1] == 137)
        }
        atlas.beginFrame(0)
        #expect(atlas.put(side, side, bitmap, 0, 0) != nil, "failure is retryable next frame")
    }

    @Test("atlas_eviction_preserves_cached_empty_outlines")
    func atlasEvictionPreservesCachedEmptyOutlines() {
        var atlas = Atlas()
        let key = GlyphKey(font: 0, index: 0, glyph: 0, size: 0, coords: 0, subpx: 0, subpy: 0, dilation: 0, apple: 0, skew: 0)
        atlas.map[key] = .some(nil)
        atlas.icons[IconCacheKey(rawId: 0, px: 0)] = .some(nil)
        atlas.evictPage(0)
        #expect(atlas.map.keys.contains(key))
        #expect(atlas.icons.keys.contains(IconCacheKey(rawId: 0, px: 0)))
    }

    @Test("colour_budget_retires_unused_scales_without_flushing_active_images")
    func colourBudgetRetiresUnusedScalesWithoutFlushingActiveImages() {
        let text = TextSystem()
        let key = GlyphKey(font: 0, index: 0, glyph: 0, size: 0, coords: 0, subpx: 0, subpy: 0, dilation: 0, apple: 0, skew: 0)
        let p1 = Pixels.new()
        p1.set(1, 1, [255, 255, 255, 255])
        let p2 = Pixels.new()
        p2.set(1, 1, [255, 255, 255, 255])
        text.colorPixels = [p1, p2]
        let active = ColorGlyph(index: 2, used: true, left: 0, top: 0, w: 4096, h: 4096)
        text.colorGlyphs[key] = ColorGlyph(index: 1, used: false, left: 0, top: 0, w: 4096, h: 4096)
        var activeKey = key
        activeKey.glyph = 1
        text.colorGlyphs[activeKey] = active
        text.colorBytes = COLOR_GLYPH_BUDGET + 1
        text.beginFrame()
        #expect(text.colorGlyphs[key] == nil)
        #expect(text.colorPixels.count == 1)
        #expect(text.colorGlyphs[activeKey]?.index == 1)
        #expect(text.colorGlyph(1).rgba() == [255, 255, 255, 255])

        text.colorGlyphs[activeKey]?.used = true
        text.beginFrame()
        #expect(text.colorGlyphs.count == 1)
        text.beginFrame()
        #expect(text.colorGlyphs.isEmpty, "unused working set can be retired")
        #expect(text.colorBytes == 0)
    }

    @Test("four_hundred_scales_never_exhaust_the_atlas_or_poison_glyphs")
    func fourHundredScalesNeverExhaustAtlasOrPoisonGlyphs() {
        let icon = Icon(name: "box", view: 16.0, body: #"<rect x="2" y="2" width="12" height="12" fill="currentColor"/>"#)
        let text = TextSystem()
        #expect(text.iconQuad(icon, ATLAS_SIZE, [0.0, 0.0]) == nil)
        #expect(!text.atlas.icons.keys.contains(IconCacheKey(icon, ATLAS_SIZE)))

        let sample = "The quick brown fox jumps over the lazy dog 0123456789"
        let expectedCount = sample.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        var quads: [GlyphQuad] = []
        for i in 0..<400 {
            text.beginFrame()
            quads.removeAll(keepingCapacity: true)
            let size = 18.0 + Float(i) * 0.45
            text.glyphs(sample, TextStyle.new(size, 400.0), 2.0, [0.0, 0.0], &quads)
            #expect(quads.count == expectedCount, "missing glyph at step \(i) (size=\(size))")
            let iconPx = UInt32(24 + (i % 96))
            #expect(text.iconQuad(icon, iconPx, [0.0, 0.0]) != nil, "missing icon at step \(i)")
        }
        #expect(text.atlas.resets() >= 4, "400 scales must cycle the atlas multiple times")
        #expect(text.atlas.pageCount() <= MAX_STEADY_PAGES)

        text.beginFrame()
        let fresh = "Sphinx of black quartz, judge my vow! 9876543210"
        let expectedFresh = fresh.unicodeScalars.filter { !$0.properties.isWhitespace }.count
        quads.removeAll(keepingCapacity: true)
        text.glyphs(fresh, TextStyle.new(16.0, 400.0), 1.0, [0.0, 0.0], &quads)
        #expect(quads.count == expectedFresh)
        for (idx, q) in quads.enumerated() {
            let page = Int(UInt32(q.uv[1]) / ATLAS_SIZE)
            let ax = UInt32(q.uv[0])
            let ay = UInt32(q.uv[1]) % ATLAS_SIZE
            let w = UInt32(q.rect[2])
            let h = UInt32(q.rect[3])
            let buf = text.atlas.pageData(page)!
            var sum: UInt64 = 0
            for row in 0..<h {
                let start = Int((ay + row) * ATLAS_SIZE + ax)
                for col in 0..<Int(w) {
                    sum += UInt64(buf[start + col])
                }
            }
            #expect(sum > 0, "fresh glyph \(idx) must have nonzero coverage in page \(page)")
        }
        #expect(text.atlas.map.values.contains(where: { $0 == nil }), "empty space glyph is cached as nil")
    }

    @Test("single_frame_exceeding_one_page_places_every_glyph_across_overflow_pages")
    func singleFrameExceedingOnePagePlacesEveryGlyphAcrossOverflowPages() {
        let icon = Icon(name: "box", view: 16.0, body: #"<rect x="1" y="1" width="14" height="14" fill="currentColor"/>"#)
        let text = TextSystem()
        text.beginFrame()
        var placed: [(UInt32, GlyphQuad)] = []
        for i in 0..<UInt32(32) {
            let px = 380 + i
            let q = text.iconQuad(icon, px, [0.0, 0.0])!
            placed.append((px, q))
        }
        #expect(text.atlas.pageCount() >= 2)
        #expect(text.atlas.resets() == 0)
        for (px, q) in placed {
            let page = Int(UInt32(q.uv[1]) / ATLAS_SIZE)
            let ax = UInt32(q.uv[0])
            let ay = UInt32(q.uv[1]) % ATLAS_SIZE
            let buf = text.atlas.pageData(page)!
            let mid = Int((ay + px / 2) * ATLAS_SIZE + ax + px / 2)
            #expect(buf[mid] == 255)
        }
    }

    // PORT NOTE: Tests `decorationsWithRings` and `underlineEdges` directly because `Runtime` is ported
    // in a separate worker scope.
    @Test("span_rings_split_backgrounds_and_underlined_words_in_a_row_meet_without_gaps")
    func spanRingsAndRowUnderlinesMeetWithoutGaps() {
        let ts = TextSystem()
        let style = TextStyle.new(13.0, 400.0)
        let s = "aa STRASSE zz"
        let spans = [
            Span.new(0, 3).bg(.WHITE, 3.0),
            Span.new(3, 10).bg(.WHITE, 3.0),
            Span.new(10, 13).bg(.WHITE, 3.0)
        ]
        let layout = ts.layoutRich(s, spans, style, 1.0, nil)
        var out: [PaintedDeco] = []
        ts.decorationsWithRings(layout, spans, [(3, 10, .BLACK, 1.0)], 1.0, [0.0, 0.0], &out)
        #expect(out.count == 3, "ring boundaries split one background into three pieces")
        #expect(out.filter { $0.ring != nil }.count == 1)

        // Row of underlined words: each element's measured width (`ceil(fullWidth)/scale`) flows into the next
        // origin, and `underlineEdges` extends each trailing-space word's underline to `ceil(advance)`.
        let words = ["Watch ", "Kaizen ", "× ", "OpenCode ", "(4:12, ", "1080p60) ", "→"]
        let lineColor = oklcha(0.6, 0.15, 260.0, 0.4)
        var xPt: Float = 0.0
        var segments: [(Float, Float)] = []
        for w in words {
            let wSpans = [Span.new(0, w.utf8.count).underline(lineColor)]
            let l = ts.layoutRich(w, wSpans, style, 2.0, nil)
            var decos: [Deco] = []
            ts.decorations(l, wSpans, 2.0, [xPt * 2.0, 0.0], &decos)
            for d in decos where d.rect[3] == 2.0 {
                segments.append((d.rect[0], d.rect[0] + d.rect[2]))
            }
            xPt += ts.measure(w, style, 2.0).0
        }
        #expect(segments.count == 7)
        for i in 0..<(segments.count - 1) {
            #expect(segments[i].1 == segments[i + 1].0, "each line meets the next: \(segments)")
        }
    }
}
