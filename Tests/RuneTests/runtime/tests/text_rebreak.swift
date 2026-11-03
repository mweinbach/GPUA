// Tests ported from: crates/rune/src/runtime/tests/text_rebreak.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite struct RtTextRebreakTests {
    @Test
    func resizingWrapsTextWhileExitingNodeRetainsItsTextLayout() {
        struct RebreakState: Sendable {
            var showThird: Bool
        }
        let style14 = TextStyle.new(14.0, 400.0)
        let para = "Paragraph text long enough to wrap over several lines as the window narrows."
        let rt = Runtime.new(RebreakState(showThird: true), { s, _ in
            let t0 = text("0. \(para)")
                .font(style14)
                .wrap()
                .wFull()
                .key("t0")
            var root = col().wFull().child(t0)
            if s.showThird {
                let t2 = text("2. \(para)").font(style14).wrap().wFull().key("t2").transition(.opacity())
                root = root.child(t2)
            }
            return root
        }, (700.0, 900.0), Env.new(true, 2.0))

        _ = rt.frame(0.0)
        let wideLines = rt.nodes.first { $0.key == "t0" }?.textLayout?.lines.count ?? 0
        #expect(wideLines == 1)

        // Remove `t2` so it enters `exitingNodes`, then resize narrower
        rt.update { s, _ in s.showThird = false }
        _ = rt.frame(1.0 / 60.0)
        rt.setViewport(300.0, 900.0)
        _ = rt.frame(1.0 / 60.0)

        let narrowLines = rt.nodes.first { $0.key == "t0" }?.textLayout?.lines.count ?? 0
        #expect(narrowLines >= 2)
        let exitingHasLayout = rt.exitingNodes.first { $0.key == "t2" }?.textLayout != nil
        #expect(exitingHasLayout)

        // Calling `contentHeight()` leaves drawn `textLayout` intact
        let h = rt.contentHeight()
        #expect(h > 0.0)
        let linesAfterMeasure = rt.nodes.first { $0.key == "t0" }?.textLayout?.lines.count ?? 0
        #expect(linesAfterMeasure == narrowLines)
    }

    @Test
    func sequentialEditsEvictOldLayoutsWhileReplacementsAndSharedTextsReuseCache() {
        let style14 = TextStyle.new(14.0, 400.0)
        let rt = Runtime.new("seed", { str, _ in
            col().wFull().child(text(str).font(style14).key("t"))
        }, (400.0, 300.0), Env.new(true, 1.0))

        _ = rt.frame(0.0)
        let initialCached = rt.textLayoutCache.count
        var buf = "Typing a paragraph: "
        for i in 0..<200 {
            buf.append(Character(UnicodeScalar(97 + (i % 26))!))
            let next = buf
            rt.update { s, _ in s = next }
            _ = rt.frame(1.0 / 120.0)
        }
        let finalCached = rt.textLayoutCache.count
        #expect(finalCached <= initialCached + 2)

        // Replacement (`!edited`) keeps previous note's layout cached for instant return
        let notesRt = Runtime.new(["The first note's opening paragraph"], { arr, _ in
            var c = col().wFull()
            for item in arr {
                c = c.child(text(item).font(style14))
            }
            return c
        }, (400.0, 300.0), Env.new(true, 2.0))
        _ = notesRt.frame(0.0)
        let shaped0 = notesRt.text.shaped
        notesRt.update { s, _ in s[0] = "Something else entirely, from another note" }
        rtStepFrames(notesRt, 3)
        notesRt.update { s, _ in s[0] = "The first note's opening paragraph" }
        rtStepFrames(notesRt, 3)
        let shapedAfterReturn = notesRt.text.shaped
        #expect(shapedAfterReturn == shaped0 + 1)

        // Shared text shown on sibling node stays cached when one copy is edited
        let sharedRt = Runtime.new(["same words", "same words"], { arr, _ in
            var c = col().wFull()
            for (idx, item) in arr.enumerated() {
                c = c.child(text(item).font(style14).key("n\(idx)"))
            }
            return c
        }, (400.0, 300.0), Env.new(true, 2.0))
        _ = sharedRt.frame(0.0)
        let shapedShared0 = sharedRt.text.shaped
        sharedRt.update { s, _ in s[0] = "same wordz" }
        rtStepFrames(sharedRt, 3)
        sharedRt.update { s, _ in s[0] = "same words" }
        rtStepFrames(sharedRt, 3)
        let shapedSharedAfter = sharedRt.text.shaped
        #expect(shapedSharedAfter == shapedShared0 + 1)
    }

    @Test
    func editHeuristicDistinguishesEditsFromReplacements() {
        #expect(edited("hello world", "hello world!"))
        #expect(edited("hello world", "hello, world"))
        #expect(edited("12", "13"))
        #expect(!edited("same", "same"))
        #expect(!edited("Show", "Hide"))
        #expect(!edited("The first note", "Another one"))
    }
}
