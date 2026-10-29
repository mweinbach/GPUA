// Tests ported from: crates/gpui/src/text_system/line_wrapper.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import GPUI

@Suite("LineWrapper Tests")
struct LineWrapperTests {

    @MainActor
    private func buildWrapper() -> LineWrapper {
        let textSystem = TextSystem(platformTextSystem: NoopTextSystem())
        let id = textSystem.resolveFont(font(".ZedMono"))
        return LineWrapper(fontId: id, fontSize: px(16.0), textSystem: textSystem)
    }

    private func generateTestRuns(_ inputRunLen: [Int]) -> [TextRun] {
        inputRunLen.map { runLen in
            TextRun(
                len: runLen,
                font: Font(
                    family: "Dummy",
                    features: FontFeatures(),
                    fallbacks: nil,
                    weight: .normal,
                    style: .normal
                ),
                color: black(),
                backgroundColor: nil,
                underline: nil,
                strikethrough: nil
            )
        }
    }

    // MARK: - Upstream Behavioral Tests

    @Test("test_wrap_line")
    @MainActor
    func test_wrap_line() {
        let wrapper = buildWrapper()

        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("aa bbb cccc ddddd eeee")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("aaa aaaaaaaaaaaaaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 4, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("     aaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 5),
                Boundary.new(ix: 9, nextIndent: 5),
                Boundary.new(ix: 11, nextIndent: 5),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("                            ")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 14, nextIndent: 0),
                Boundary.new(ix: 21, nextIndent: 0),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("          aaaaaaaaaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 14, nextIndent: 3),
                Boundary.new(ix: 18, nextIndent: 3),
                Boundary.new(ix: 22, nextIndent: 3),
            ]
        )

        // Multiple text fragments
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.text("aa bbb "),
                    LineFragment.text("cccc ddddd eeee"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )

        // Mix of text and element fragments
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.text("aa "),
                    LineFragment.element(px(20.0), 1),
                    LineFragment.text(" bbb "),
                    LineFragment.element(px(30.0), 1),
                    LineFragment.text(" cccc"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 5, nextIndent: 0),
                Boundary.new(ix: 9, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
            ]
        )

        // Element at the beginning
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.element(px(50.0), 1),
                    LineFragment.text(" aaaa bbbb cccc dddd"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 2, nextIndent: 0),
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 17, nextIndent: 0),
            ]
        )

        // Large element that forces wrapping
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.text("short text "),
                    LineFragment.element(px(100.0), 1),
                    LineFragment.text(" more text"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 6, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )
    }

    @Test("test_wrap_line_with_indent")
    @MainActor
    func test_wrap_line_with_indent() {
        let wrapper = buildWrapper()
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("     aaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 5),
                Boundary.new(ix: 9, nextIndent: 5),
                Boundary.new(ix: 11, nextIndent: 5),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("          aaaaaaaaaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 14, nextIndent: 3),
                Boundary.new(ix: 18, nextIndent: 3),
                Boundary.new(ix: 22, nextIndent: 3),
            ]
        )
    }

    @Test("test_wrap_line_with_tabs")
    @MainActor
    func test_wrap_line_with_tabs() {
        let wrapper = buildWrapper()
        let result = wrapper.wrapLine(
            fragments: [LineFragment.text("hello\tworld\tthis\tis\ta\ttest\tof\tline\twrapping")],
            wrapWidth: px(72.0)
        )
        #expect(!result.isEmpty)
    }

    @Test("test_wrap_line_mid_word")
    @MainActor
    func test_wrap_line_mid_word() {
        let wrapper = buildWrapper()
        #expect(
            wrapper.wrapLine(
                fragments: [LineFragment.text("aaa aaaaaaaaaaaaaaaaaa")],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 4, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )
    }

    @Test("test_truncate_line_end")
    @MainActor
    func test_truncate_line_end() {
        let wrapper = buildWrapper()

        func performTest(text: String, expected: String, ellipsis: String) {
            let dummyRunLens = [text.utf8.count]
            let dummyRuns = generateTestRuns(dummyRunLens)
            let (result, outRuns) = wrapper.truncateLine(
                line: SharedString(text),
                truncateWidth: px(220.0),
                truncationAffix: ellipsis,
                runs: dummyRuns,
                truncateFrom: .end
            )
            #expect(result.asString == expected)
            #expect(outRuns.first?.len == result.asString.utf8.count)
        }

        performTest(
            text: "aa bbb cccc ddddd eeee ffff gggg",
            expected: "aa bbb cccc ddddd eeee",
            ellipsis: ""
        )
        performTest(
            text: "aa bbb cccc ddddd eeee ffff gggg",
            expected: "aa bbb cccc ddddd eee…",
            ellipsis: "…"
        )
        performTest(
            text: "aa bbb cccc ddddd eeee ffff gggg",
            expected: "aa bbb cccc dddd......",
            ellipsis: "......"
        )
        performTest(
            text: "aa bbb cccc 🦀🦀🦀🦀🦀 eeee ffff gggg",
            expected: "aa bbb cccc 🦀🦀🦀🦀…",
            ellipsis: "…"
        )
    }

    @Test("test_truncate_line_start")
    @MainActor
    func test_truncate_line_start() {
        let wrapper = buildWrapper()

        func performTest(text: String, expected: String, ellipsis: String) {
            let dummyRunLens = [text.utf8.count]
            let dummyRuns = generateTestRuns(dummyRunLens)
            let (result, outRuns) = wrapper.truncateLine(
                line: SharedString(text),
                truncateWidth: px(220.0),
                truncationAffix: ellipsis,
                runs: dummyRuns,
                truncateFrom: .start
            )
            #expect(result.asString == expected)
            #expect(outRuns.first?.len == result.asString.utf8.count)
        }

        performTest(
            text: "aaaa bbbb cccc ddddd eeee fff gg",
            expected: "cccc ddddd eeee fff gg",
            ellipsis: ""
        )
        performTest(
            text: "aaaa bbbb cccc ddddd eeee fff gg",
            expected: "…ccc ddddd eeee fff gg",
            ellipsis: "…"
        )
        performTest(
            text: "aaaa bbbb cccc ddddd eeee fff gg",
            expected: "......dddd eeee fff gg",
            ellipsis: "......"
        )
        performTest(
            text: "aaaa bbbb cccc 🦀🦀🦀🦀🦀 eeee fff gg",
            expected: "…🦀🦀🦀🦀 eeee fff gg",
            ellipsis: "…"
        )
    }

    @Test("test_wrap_with_fixed_width_items")
    @MainActor
    func test_wrap_with_fixed_width_items() {
        let wrapper = buildWrapper()
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.text("aa "),
                    LineFragment.element(px(20.0), 1),
                    LineFragment.text(" bbb "),
                    LineFragment.element(px(30.0), 1),
                    LineFragment.text(" cccc"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 5, nextIndent: 0),
                Boundary.new(ix: 9, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.element(px(50.0), 1),
                    LineFragment.text(" aaaa bbbb cccc dddd"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 2, nextIndent: 0),
                Boundary.new(ix: 7, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 17, nextIndent: 0),
            ]
        )
        #expect(
            wrapper.wrapLine(
                fragments: [
                    LineFragment.text("short text "),
                    LineFragment.element(px(100.0), 1),
                    LineFragment.text(" more text"),
                ],
                wrapWidth: px(72.0)
            ) == [
                Boundary.new(ix: 6, nextIndent: 0),
                Boundary.new(ix: 11, nextIndent: 0),
                Boundary.new(ix: 12, nextIndent: 0),
                Boundary.new(ix: 18, nextIndent: 0),
            ]
        )
    }

    @Test("test_wrap_line_with_emoji")
    @MainActor
    func test_wrap_line_with_emoji() {
        let wrapper = buildWrapper()
        let result = wrapper.wrapLine(
            fragments: [LineFragment.text("hello 🦀🦀🦀🦀🦀 world")],
            wrapWidth: px(72.0)
        )
        #expect(!result.isEmpty)
    }

    @Test("test_truncate_multiple_runs_end")
    @MainActor
    func test_truncate_multiple_runs_end() {
        let wrapper = buildWrapper()

        func performTest(
            text: String,
            expected: String,
            runLens: [Int],
            resultRunLens: [Int],
            lineWidth: Pixels
        ) {
            let dummyRuns = generateTestRuns(runLens)
            let (result, outRuns) = wrapper.truncateLine(
                line: SharedString(text),
                truncateWidth: lineWidth,
                truncationAffix: "…",
                runs: dummyRuns,
                truncateFrom: .end
            )
            #expect(result.asString == expected)
            for (run, expectedLen) in zip(outRuns, resultRunLens) {
                #expect(run.len == expectedLen)
            }
        }

        // Case 0: Normal
        performTest(text: "abcdefghijkl", expected: "abcd…", runLens: [12], resultRunLens: [7], lineWidth: px(50.0))
        // Case 1: Drop some runs
        performTest(text: "abcdefghijkl", expected: "abcdef…", runLens: [4, 4, 4], resultRunLens: [4, 5], lineWidth: px(70.0))
        // Case 2: Truncate at start of some run
        performTest(text: "abcdefghijkl", expected: "abcdefgh…", runLens: [4, 4, 4], resultRunLens: [4, 4, 3], lineWidth: px(90.0))
    }

    @Test("test_truncate_multiple_runs_start")
    @MainActor
    func test_truncate_multiple_runs_start() {
        let wrapper = buildWrapper()

        func performTest(
            text: String,
            expected: String,
            runLens: [Int],
            resultRunLens: [Int],
            lineWidth: Pixels
        ) {
            let dummyRuns = generateTestRuns(runLens)
            let (result, outRuns) = wrapper.truncateLine(
                line: SharedString(text),
                truncateWidth: lineWidth,
                truncationAffix: "…",
                runs: dummyRuns,
                truncateFrom: .start
            )
            #expect(result.asString == expected)
            for (run, expectedLen) in zip(outRuns, resultRunLens) {
                #expect(run.len == expectedLen)
            }
        }

        // Case 0: Normal
        performTest(text: "abcdefghijkl", expected: "…ijkl", runLens: [12], resultRunLens: [7], lineWidth: px(50.0))
        // Case 1: Drop some runs
        performTest(text: "abcdefghijkl", expected: "…ghijkl", runLens: [4, 4, 4], resultRunLens: [5, 4], lineWidth: px(70.0))
        // Case 2: Truncate at start of some run
        performTest(text: "abcdefghijkl", expected: "…efghijkl", runLens: [4, 4, 4], resultRunLens: [3, 4, 4], lineWidth: px(90.0))
    }

    @Test("test_update_run_after_truncation_end")
    func test_update_run_after_truncation_end() {
        func performTest(result: String, runLens: [Int], resultRunLens: [Int]) {
            var dummyRuns = generateTestRuns(runLens)
            updateRunsAfterTruncation(result: result, ellipsis: "…", runs: &dummyRuns, truncateFrom: .end)
            for (run, expectedLen) in zip(dummyRuns, resultRunLens) {
                #expect(run.len == expectedLen)
            }
        }

        performTest(result: "abcd…", runLens: [12], resultRunLens: [7])
        performTest(result: "abcdef…", runLens: [4, 4, 4], resultRunLens: [4, 5])
        performTest(result: "abcdefgh…", runLens: [4, 4, 4], resultRunLens: [4, 4, 3])
    }

    @Test("test_is_word_char")
    func test_is_word_char() {
        func assertWord(_ word: String) {
            for c in word {
                #expect(LineWrapper.isWordChar(c), "Expected '\(c)' to be word char")
            }
        }

        func assertNotWord(_ word: String) {
            let found = word.contains { !LineWrapper.isWordChar($0) }
            #expect(found, "Expected non-word char in '\(word)'")
        }

        assertWord("Hello123")
        assertWord("non-English")
        assertWord("var_name")
        assertWord("123456")
        assertWord("3.1415")
        assertWord("10^2")
        assertWord("1~2")
        assertWord("100%")
        assertWord("@mention")
        assertWord("#hashtag")
        assertWord("$variable")
        assertWord("a=1")
        assertWord("Self::is_word_char")
        assertWord("more⋯")

        assertNotWord("foo bar")
        assertWord("github.com")
        assertNotWord("zed-industries/zed")
        assertNotWord("zed-industries\\zed")
        assertNotWord("a=1&b=2")
        assertNotWord("foo?b=2")

        assertWord("ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏ")
        assertWord("ĀāĂăĄąĆćĈĉĊċČčĎď")
        assertWord("ƀƁƂƃƄƅƆƇƈƉƊƋƌƍƎƏ")
        assertWord("АБВГДЕЖЗИЙКЛМНОП")
        assertWord("ThậmchíđếnkhithuachạychúngcònnhẫntâmgiếtnốtsốđôngtùchínhtrịởYênBáivàCaoBằng")
        assertWord("গিয়েছিলেন")
        assertWord("ছেলে")
        assertWord("হচ্ছিল")

        assertNotWord("你好")
        assertNotWord("안녕하세요")
        assertNotWord("こんにちは")
        assertNotWord("😀😁😂")
        assertNotWord("()[]{}<>")
    }

    // MARK: - Subsystem Tests: NoopTextSystem, LineLayoutCache, TestAppContext

    @Test("test_noop_text_system_metrics")
    func test_noop_text_system_metrics() throws {
        let noop = NoopTextSystem()
        let fontId = try noop.fontId(descriptor: font(".ZedMono"))
        let metrics = noop.fontMetrics(fontId: fontId)
        #expect(metrics.unitsPerEm == 1000)
        #expect(metrics.ascent == 1025.0)
        #expect(metrics.descent == -275.0)

        let advanceA = try noop.advance(fontId: fontId, glyphId: GlyphId(1))
        #expect(advanceA.width == 600.0)

        let advanceEmoji = try noop.advance(fontId: fontId, glyphId: GlyphId(2))
        #expect(advanceEmoji.width == 1200.0)
    }

    @Test("test_line_layout_cache_basic")
    @MainActor
    func test_line_layout_cache_basic() {
        let noop = NoopTextSystem()
        let cache = LineLayoutCache.new(platformTextSystem: noop)
        let idx0 = cache.layoutIndex()
        #expect(idx0.linesIndex == 0)

        let fontId = FontId(1)
        let layout1 = cache.layoutLine(
            text: "Hello, GPUA!",
            fontSize: px(16.0),
            runs: [FontRun(len: 12, fontId: fontId)]
        )
        #expect(layout1.width.value > 0)

        let idx1 = cache.layoutIndex()
        #expect(idx1.linesIndex == 1)

        cache.finishFrame()
        let layout2 = cache.layoutLine(
            text: "Hello, GPUA!",
            fontSize: px(16.0),
            runs: [FontRun(len: 12, fontId: fontId)]
        )
        #expect(layout2.width == layout1.width)
    }

    @Test("test_test_app_context_lifecycle")
    @MainActor
    func test_test_app_context_lifecycle() {
        let cx = TestAppContext.build(dispatcher: TestDispatcher.new(seed: 0))
        let textSys = cx.textSystem
        let fontId = textSys.resolveFont(font(".ZedMono"))
        #expect(fontId.value > 0)
    }
}
