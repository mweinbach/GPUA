// Tests ported from: crates/rune/src/runtime/tests/glyph_replay.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

@testable import Rune
import RuneMotion
import Testing

private let rtReplayProse =
    "Amber lantern orchard quiet harbor, copper meadow signal drift. Pebble willow "
    + "ember tide under a juniper kestrel; nimbus opal prism and a quiet harbor beneath the lantern. "

private func rtReplayProseView(_: Void, _: Cx<Void>) -> El {
    let items: [El] = (0..<40).map { i in
        var p = text("\(i). \(String(repeating: rtReplayProse, count: 1 + (i % 3)))")
            .key("p\(i)")
            .font(TextStyle(size: 13.0, weight: 400.0))
            .color(.WHITE)
            .wFull()
        p.textSpec?.value.wrap = true
        return p
    }
    return col()
        .key("scroll")
        .size(320.0, 240.0)
        .scroll(ScrollSpec(stickBottom: false))
        .children(items)
}

@Suite
struct RtGlyphReplayTests {
    @Test
    func scrollingReplaysGlyphsItHasDrawn() {
        let rt = Runtime.new((), rtReplayProseView, (320.0, 240.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        for _ in 0..<12 {
            rt.wheel(160.0, 120.0, 0.0, -7.0)
            _ = rt.frame(1.0 / 120.0)
        }
        let flattened = rt.glyphCache.flattened
        #expect(flattened > 0)

        for _ in 0..<12 {
            rt.wheel(160.0, 120.0, 0.0, 7.0)
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(rt.glyphCache.flattened == flattened)

        for _ in 0..<12 {
            rt.wheel(160.0, 120.0, 0.0, -7.0)
            _ = rt.frame(1.0 / 120.0)
        }
        #expect(rt.glyphCache.flattened == flattened)

        for _ in 0..<60 {
            _ = rt.frame(1.0 / 120.0)
        }

        let fresh = Runtime.new((), rtReplayProseView, (320.0, 240.0), Env.new(true, 2.0))
        _ = fresh.frame(0.0)
        fresh.wheel(160.0, 120.0, 0.0, -84.0)
        for _ in 0..<60 {
            _ = fresh.frame(1.0 / 120.0)
        }

        let rtOffset = rt.scrolls.values.first?.offset ?? -1.0
        let freshOffset = fresh.scrolls.values.first?.offset ?? -2.0
        #expect(abs(rtOffset - freshOffset) < 0.05)
        #expect(rt.instances.count > 200)
        #expect(rt.instances == fresh.instances)
    }

    @Test
    func secureFieldsKeepNoGlyphs() {
        func view(_ s: TextEdit, _: Cx<TextEdit>) -> El {
            var field = textInput(s, TextStyle(size: 16.0, weight: 400.0)).key("secret").size(200.0, 40.0)
            field.input?.edit.setSingleLine(true)
            field.textSpec?.value.wrap = false
            return field
        }

        let secret = TextEdit.new("hunter2").secure()
        let rt = Runtime.new(secret, view, (200.0, 40.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.instances.contains(where: { $0.params[1] == KIND_GLYPH }))
        #expect(rt.glyphCache.len() == 0)
        #expect(rt.textLayoutCache.isEmpty)
    }
}
