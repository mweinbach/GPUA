// Tests ported from: crates/rune/src/runtime/truncate_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let samplePath = "~/Projects/rune/crates/rune-kit/src/components/settings/appearance_panel.rs"

private func truncStyle() -> TextStyle {
    TextStyle.new(13.0, 400.0).lh(16.0)
}

private func makeTruncRuntime(_ content: String, width: Float, fade: Bool = false) -> Runtime<String> {
    let rt = Runtime.new(content, { str, _ in
        var t = rtSelectable(text(str).key("t").font(truncStyle()).wFull().truncate(true), true)
        if fade {
            t.textSpec?.value.truncateFade = true
        }
        return col().wFull().child(t)
    }, (width, 40.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    return rt
}

private func textNode(_ rt: Runtime<String>) -> Node {
    rt.nodes.first { $0.key == "t" }!
}

private func drawnLineInfo(_ rt: Runtime<String>) -> (shown: String, truncated: Bool, width: Float, boxWidth: Float) {
    let n = textNode(rt)
    let layout = n.textLayout!
    let line = layout.lines[0]
    let prefix = sliceUtf8Safely(n.textSpec!.content, line.byteStart..<line.byteEnd)
    let hasEllipsis = line.glyphs.contains { $0.isEllipsis }
    let shown = hasEllipsis ? (prefix + "…") : prefix
    return (shown, layout.truncated, layout.width, n.layoutRect[2])
}

@Suite("RuntimeTruncateTests")
struct RuntimeTruncateTests {
    @Test("Truncated text fits within width, preserves full ElementInfo.text, and refits on resize")
    func truncationFitsAndRefitsOnResize() {
        let rt = makeTruncRuntime(samplePath, width: 200.0)
        let narrow = drawnLineInfo(rt)
        #expect(narrow.truncated)
        #expect(narrow.width <= narrow.boxWidth + 0.5)
        #expect(narrow.shown.hasPrefix("~/Projects"))
        #expect(narrow.shown.hasSuffix("…"))
        // Tools and accessibility still read the entire untruncated string
        #expect(rtElement(rt, "t")?.text == samplePath)

        // Widening keeps more text
        rt.setViewport((320.0, 40.0), 2.0)
        _ = rt.frame(0.1)
        let wider = drawnLineInfo(rt)
        #expect(wider.width <= wider.boxWidth + 0.5)
        #expect(wider.shown.count > narrow.shown.count)

        // Room for everything: no ellipsis or truncation
        rt.setViewport((900.0, 40.0), 2.0)
        _ = rt.frame(0.1)
        let full = drawnLineInfo(rt)
        #expect(!full.truncated)
        #expect(full.shown == samplePath)

        // Narrowing again cuts identically to before
        rt.setViewport((200.0, 40.0), 2.0)
        _ = rt.frame(0.1)
        #expect(drawnLineInfo(rt).shown == narrow.shown)
    }

    @Test("Truncation cuts always fall on valid extended grapheme cluster boundaries")
    func cutsFallBetweenGraphemes() {
        let mixed = "👩‍👩‍👧‍👦 cafe\u{301} שלום עולם 🇯🇵 नमस्ते e\u{301}e\u{301}e\u{301} 👩‍👩‍👧‍👦 done"
        var validBoundaries: Set<Int> = [0]
        var cursor = 0
        for ch in mixed {
            cursor += ch.utf8.count
            validBoundaries.insert(cursor)
        }

        let rt = makeTruncRuntime(mixed, width: 60.0)
        var cutCount = 0
        for w in stride(from: 60, to: 400, by: 7) {
            rt.setViewport((Float(w), 40.0), 2.0)
            _ = rt.frame(1.0 / 60.0)
            let n = textNode(rt)
            let layout = n.textLayout!
            if layout.truncated {
                cutCount += 1
                let line = layout.lines[0]
                #expect(layout.width <= n.layoutRect[2] + 0.5)
                #expect(validBoundaries.contains(line.byteStart))
                #expect(validBoundaries.contains(line.byteEnd))
            }
        }
        #expect(cutCount > 10)
    }

    @Test("Selecting all or dragging across truncated text copies the full untruncated string")
    func copyingCutTextCopiesAllOfIt() {
        let rt = makeTruncRuntime(samplePath, width: 200.0)
        #expect(drawnLineInfo(rt).truncated)

        // Cmd+A selects the entire underlying text, including characters hidden behind `…`
        _ = rt.keyDown(KeyEvent(key: .command(Character("a")), mods: Mods(cmd: true)))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.selectedText() == samplePath)
    }

    @Test("Truncate fade ramps trailing glyph alpha without appending an ellipsis glyph")
    func truncateFadeRampsAlphaWithoutEllipsis() {
        let rt = makeTruncRuntime(samplePath, width: 180.0, fade: true)
        let n = textNode(rt)
        let layout = n.textLayout!
        #expect(layout.truncated)
        #expect(layout.truncatedFadeWidth > 0.0)
        let glyphs = layout.lines[0].glyphs
        #expect(glyphs.allSatisfy { !$0.isEllipsis })
        #expect(glyphs.first!.alpha == 1.0)
        #expect(glyphs.last!.alpha < 1.0)
    }
}
