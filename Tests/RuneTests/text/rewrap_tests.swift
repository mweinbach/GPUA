// Tests ported from: crates/rune/src/text/rewrap_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Layout re-breaking without reshaping")
struct RewrapTests {
    private struct Case {
        var name: String
        var text: String
        var spans: [Span] = []
        var blocks: [Block] = []
        var pills: [PillChip] = []
        var style: TextStyle
        var align: TextAlignment = .start
        var wrapAnywhere: Bool = false
    }

    private func byteOffset(of needle: String, in haystack: String) -> Int {
        guard let r = haystack.range(of: needle) else { return 0 }
        return haystack.utf8.distance(from: haystack.utf8.startIndex, to: r.lowerBound)
    }

    private func geometry(_ l: TextLayout) -> [[UInt32]] {
        var out: [[UInt32]] = [[
            l.fullWidth().bitPattern,
            l.width().bitPattern,
            l.height().bitPattern,
            UInt32(l.len())
        ]]
        for line in l.lines() {
            let m = line.metrics()
            let r = line.textRange()
            out.append([
                UInt32(r.lowerBound),
                UInt32(r.upperBound),
                m.offset.bitPattern,
                m.baseline.bitPattern,
                m.advance.bitPattern,
                m.inlineMinCoord.bitPattern
            ])
            for item in line.items() {
                switch item {
                case .glyphRun(let run):
                    var g: [UInt32] = [
                        run.font.index,
                        run.fontSize.bitPattern,
                        run.baseline().bitPattern,
                        run.offset().bitPattern
                    ]
                    for p in run.positionedGlyphs() {
                        g.append(UInt32(p.id))
                        g.append(p.x.bitPattern)
                        g.append(p.y.bitPattern)
                    }
                    out.append(g)
                case .inlineBox(let b):
                    out.append([UInt32(truncatingIfNeeded: b.id), b.x.bitPattern, b.y.bitPattern])
                }
            }
        }
        return out
    }

    private func cases() -> [Case] {
        let body = TextStyle.new(15.0, 400.0).lh(22.0)
        let rich = "The quick brown fox jumps over the_lazy_dog and keeps running past https://example.com/a/very/long/unbreakable/path/that/overflows/any/line while larger words sit beside it."
        var spans: [Span] = [
            Span.new(byteOffset(of: "jumps", in: rich), byteOffset(of: "jumps", in: rich) + 5).bold(),
            Span.new(byteOffset(of: "the_lazy_dog", in: rich), byteOffset(of: "the_lazy_dog", in: rich) + 12).mono(),
            Span.new(byteOffset(of: "keeps", in: rich), byteOffset(of: "keeps", in: rich) + 5).italic(),
            Span.new(byteOffset(of: "larger", in: rich), byteOffset(of: "larger", in: rich) + 12).size(22.0)
        ]
        spans.sort { $0.start < $1.start }

        let paragraphs = "First a plain paragraph that wraps over a few lines of text.\nA bullet item long enough to wrap onto a second line at most widths.\nA quoted line that also wraps when the width narrows enough.\nlet code = run(\"a long line of code\");"
        let pillText = "ask @code-reviewer about @src/main.rs and @notes today please, then wrap"
        let pills: [PillChip] = ["@code-reviewer", "@src/main.rs", "@notes"].map { label in
            let s = UInt32(byteOffset(of: label, in: pillText))
            return PillChip(start: s, end: s + UInt32(label.utf8.count), icon: nil, bg: nil, fg: nil)
        }

        return [
            Case(name: "spans", text: rich, spans: spans, style: body),
            Case(name: "wrap anywhere", text: rich, spans: spans, style: body, wrapAnywhere: true),
            Case(name: "centred", text: rich, spans: spans, style: body, align: .center),
            Case(name: "end", text: rich, spans: spans, style: body, align: .end),
            Case(name: "justified", text: rich, spans: spans, style: body, align: .justify),
            Case(name: "right to left", text: "مرحبا بالعالم هذا نص طويل يلتف عبر عدة أسطر في التخطيط، ثم שלום עולם וטקסט נוסף", style: body),
            Case(name: "right to left justified", text: "مرحبا بالعالم هذا نص طويل يلتف عبر عدة أسطر في التخطيط والمزيد من الكلمات هنا", style: body, align: .justify),
            Case(name: "mixed fonts", text: "Mixed 中文字符和日本語のテキスト with emoji 🎉🚀 and math 𝑥² ∑ beside Latin words that wrap", style: body),
            Case(name: "mono tabs", text: "fn main() {\n\tlet x = 1;\t// a comment that runs long enough to wrap\n}", style: TextStyle.new(13.0, 400.0).family(.mono)),
            Case(name: "blocks", text: paragraphs, blocks: [.paragraph, .bullet(0), .quote, .code], style: body),
            Case(name: "pills", text: pillText, pills: pills, style: TextStyle.new(14.0, 400.0))
        ]
    }

    private func lay(_ ts: TextSystem, _ c: Case, _ width: Float?) -> TextLayout {
        ts.layoutBlocksInner(
            text: c.text,
            spans: c.spans,
            blocks: c.blocks,
            pills: c.pills,
            style: c.style,
            scale: 2.0,
            maxWidth: width,
            align: c.align,
            wrapAnywhere: c.wrapAnywhere,
            retain: true
        )
    }

    @Test("a_new_width_rebreaks_without_shaping_and_matches_a_fresh_layout")
    func newWidthRebreaksWithoutShapingAndMatchesFreshLayout() {
        let ts = TextSystem()
        let fresh = TextSystem()
        let widths: [Float?] = [1200.0, 601.0, 433.5, 210.0, 80.0, 0.0, nil, 900.0]

        for c in cases() {
            let wide = lay(ts, c, 1800.0)
            let wideGeom = geometry(wide)
            for width in widths {
                let shaped = ts.shaped
                let rebroken = ts.rebroken
                let l = lay(ts, c, width)
                #expect(ts.shaped == shaped && ts.rebroken == rebroken + 1, "\(c.name) at \(String(describing: width)): re-broken, not shaped")
                #expect(geometry(wide) == wideGeom, "\(c.name): re-breaking must not mutate an earlier layout in place")

                let savedLayouts = ts.layouts
                let savedShapes = ts.shapes
                ts.layouts = [:]
                ts.shapes = [:]
                let f = lay(ts, c, width)
                #expect(ts.shaped == shaped + 1)
                ts.layouts = savedLayouts
                ts.shapes = savedShapes

                fresh.layouts.removeAll()
                fresh.shapes.removeAll()
                let fOther = lay(fresh, c, width)
                let a = geometry(l)
                let b = geometry(f)
                let bOther = geometry(fOther)
                #expect(a == b, "\(c.name) at \(String(describing: width))")
                #expect(a == bOther, "\(c.name) at \(String(describing: width)): fresh TextSystem")
            }
            let shaped = ts.shaped
            let rebroken = ts.rebroken
            #expect(lay(ts, c, 210.0).len() > 1, "\(c.name) wraps")
            #expect(ts.shaped == shaped && ts.rebroken == rebroken, "\(c.name): cached width hits without re-breaking")
        }
    }

    @Test("a_text_style_span_or_scale_change_still_shapes")
    func textStyleSpanOrScaleChangeStillShapes() {
        let ts = TextSystem()
        let style = TextStyle.new(15.0, 400.0)
        let text = "a paragraph long enough to wrap at a narrow width"
        _ = ts.layoutRich(text, [], style, 2.0, 400.0)
        func shapes(_ body: () -> Void) -> UInt32 {
            let n = ts.shaped
            body()
            return ts.shaped - n
        }
        #expect(shapes { _ = ts.layoutRich(text, [], style, 2.0, 300.0) } == 0)
        #expect(shapes { _ = ts.layoutRich("another paragraph entirely", [], style, 2.0, 300.0) } == 1)
        #expect(shapes { _ = ts.layoutRich(text, [], TextStyle.new(15.0, 600.0), 2.0, 300.0) } == 1)
        #expect(shapes { _ = ts.layoutRich(text, [Span.new(0, 1).bold()], style, 2.0, 300.0) } == 1)
        #expect(shapes { _ = ts.layoutRich(text, [], style, 3.0, 300.0) } == 1)
        #expect(shapes {
            _ = ts.layoutBlocksInner(text: text, spans: [], blocks: [], pills: [], style: style, scale: 2.0, maxWidth: 300.0, align: .start, wrapAnywhere: true, retain: true)
        } == 1)
        #expect(shapes {
            _ = ts.layoutBlocksInner(text: text, spans: [], blocks: [], pills: [], style: style, scale: 2.0, maxWidth: 200.0, align: .start, wrapAnywhere: true, retain: true)
        } == 0)
    }

    @Test("the_rebreak_index_keeps_to_the_layout_cache")
    func rebreakIndexKeepsToLayoutCache() {
        let ts = TextSystem()
        let style = TextStyle.new(15.0, 400.0)
        let text = "a paragraph long enough to wrap at a narrow width"
        _ = ts.layoutRich(text, [], style, 2.0, 400.0)
        _ = ts.layoutRich(text, [], style, 2.0, 300.0)
        for _ in 0..<6 {
            _ = ts.layoutRich(text, [], style, 2.0, 400.0)
            ts.endCommit()
        }
        let shaped = ts.shaped
        _ = ts.layoutRich(text, [], style, 2.0, 250.0)
        #expect(ts.shaped == shaped, "the width in use is the one re-broken")
        for i in 0..<2000 {
            _ = ts.layoutRich("filler label \(i) with a few words", [], style, 2.0, 300.0)
            ts.endCommit()
        }
        #expect(ts.shapes.count <= ts.layouts.count)
        #expect(ts.shapes.values.allSatisfy { ts.layouts[$0] != nil })
    }

    @Test("a_layout_nothing_holds_rebreaks_in_place_at_a_new_width")
    func layoutNothingHoldsRebreaksInPlaceAtNewWidth() {
        let ts = TextSystem()
        let style = TextStyle.new(15.0, 400.0)
        let text = "a paragraph long enough to wrap over several lines at a narrow width"
        var atId: ObjectIdentifier!
        do {
            let wide = ts.layoutRich(text, [], style, 2.0, 400.0)
            atId = ObjectIdentifier(wide)
        }
        ts.endCommit()
        let narrow = ts.layoutRich(text, [], style, 2.0, 300.0)
        #expect(ObjectIdentifier(narrow) == atId, "moved, not copied")
        #expect(ts.cachedLayoutCount() == 1, "the old width's entry moved with it")
        #expect(geometry(narrow) == geometry(TextSystem().layoutRich(text, [], style, 2.0, 300.0)))

        // Handed out this commit: copied, and the width it was at still hits.
        let shaped = ts.shaped
        let rebroken = ts.rebroken
        let narrower = ts.layoutRich(text, [], style, 2.0, 200.0)
        #expect(ObjectIdentifier(narrower) != atId)
        #expect(ts.layoutRich(text, [], style, 2.0, 300.0) === narrow)
        #expect(ts.shaped == shaped && ts.rebroken == rebroken + 1)

        // Held from an earlier commit: copied, and the holder's layout is untouched.
        ts.endCommit()
        let before = geometry(narrower)
        let other = ts.layoutRich(text, [], style, 2.0, 150.0)
        #expect(other !== narrower)
        #expect(geometry(narrower) == before)
    }
}
