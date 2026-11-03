// Tests ported from: crates/rune/src/text/measure/ink_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Text ink measurement and cache")
struct InkTests {
    @Test("ink_sits_inside_the_box_and_spaces_have_none")
    func inkSitsInsideBoxAndSpacesHaveNone() {
        let style = TextStyle.new(12.0, 400.0).lh(16.0)
        let (w, h) = measure("H", [], style, nil)
        let hInk = ink("H", style)
        #expect(hInk != nil, "H draws")
        guard let hInk else { return }
        let x = hInk.bounds[0]
        let y = hInk.bounds[1]
        let iw = hInk.bounds[2]
        let ih = hInk.bounds[3]
        #expect(x >= 0.0 && y >= 0.0 && x + iw <= w && y + ih <= h, "\(hInk) in \(w)×\(h)")
        #expect(ih > 7.0 && ih < 10.0, "an H is about cap height: \(ih)")
        let c = hInk.centre()
        #expect(abs(hInk.mass[0] - c[0]) < 0.2, "H is symmetric: \(hInk)")
        #expect(ink(" ", style) == nil)
    }

    @Test("a_wider_word_has_wider_ink")
    func widerWordHasWiderInk() {
        let style = TextStyle.new(12.0, 400.0)
        let hh = ink("HH", style)!
        let h = ink("H", style)!
        #expect(hh.bounds[2] > h.bounds[2] * 1.8)
    }

    @Test("the_cache_stays_bounded_in_entries_and_bytes")
    func cacheStaysBoundedInEntriesAndBytes() {
        let style = TextStyle.new(12.0, 400.0)
        let cache = ThreadInkCache()
        for i in 0..<(INK_MAX_ENTRIES + 50) {
            let text = "t\(i)"
            cache.insert(ThreadInkCache.key(text, style), text, style, nil)
        }
        #expect(cache.entries.count == INK_MAX_ENTRIES)
        #expect(cache.activeOrderCount == INK_MAX_ENTRIES)
        #expect(cache.get(ThreadInkCache.key("t0", style), "t0", style) == nil, "the oldest went")
        let last = "t\(INK_MAX_ENTRIES + 49)"
        #expect(cache.get(ThreadInkCache.key(last, style), last, style) == .some(nil), "the newest stays")

        let longPrefix = String(repeating: "x", count: INK_MAX_BYTES / 8)
        for i in 0..<16 {
            let text = "\(longPrefix)\(i)"
            cache.insert(ThreadInkCache.key(text, style), text, style, nil)
        }
        #expect(cache.bytes <= INK_MAX_BYTES, "\(cache.bytes) bytes")
        let summed = cache.entries.values.reduce(0) { $0 + $1.byteCost() }
        #expect(cache.bytes == summed)
        let huge = String(repeating: "x", count: INK_MAX_BYTES)
        cache.insert(ThreadInkCache.key(huge, style), huge, style, nil)
        #expect(cache.get(ThreadInkCache.key(huge, style), huge, style) == nil, "one text over the budget isn't kept")
    }

    @Test("a_hit_checks_the_text_and_style_not_only_the_hash")
    func hitChecksTextAndStyleNotOnlyHash() {
        let style = TextStyle.new(12.0, 400.0)
        let cache = ThreadInkCache()
        let val = TextInk(bounds: [1.0, 2.0, 3.0, 4.0], mass: [2.0, 3.0])
        cache.insert(7, "H", style, val)
        #expect(cache.get(7, "H", style) == .some(val))
        #expect(cache.get(7, "I", style) == nil)
        #expect(cache.get(7, "H", TextStyle.new(13.0, 400.0)) == nil)
        cache.insert(7, "I", style, nil)
        #expect(cache.get(7, "I", style) == .some(nil))
        #expect(cache.entries.count == 1)
    }
}
