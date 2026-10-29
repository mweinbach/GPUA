// Swift-only: Milestone 3 Gate Challenger 2 empirical stress test harness (Text Wrapping, TestDispatcher Determinism, List Follow-Tail)

import Foundation
import Testing
@testable import GPUI
@testable import Scheduler

// MARK: - Test Support Helpers

private final class AtomicLock<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

// MARK: - Suite 1: LineWrapper Boundary Widths & Pathological String Stress

@Suite("Challenger 2 Suite 1: LineWrapper Boundary Widths and Pathological String Stress")
struct LineWrapperBoundaryStressTests {

    @MainActor
    private func makeWrapper(fontSize: Pixels = px(16.0)) -> LineWrapper {
        let textSystem = TextSystem(platformTextSystem: NoopTextSystem())
        let fontId = textSystem.resolveFont(font(".ZedMono"))
        return LineWrapper(fontId: fontId, fontSize: fontSize, textSystem: textSystem)
    }

    @Test("test_wrap_zero_width_never_hangs_and_produces_monotonic_boundaries")
    @MainActor
    func test_wrap_zero_width_never_hangs_and_produces_monotonic_boundaries() {
        let wrapper = makeWrapper()
        let text = "The quick brown fox jumps over the lazy dog"
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(0.0)
        )

        #expect(!boundaries.isEmpty, "Zero width wrap should produce boundaries for non-empty text")
        // Verify monotonicity and bounded indents
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx, "Boundary index must strictly increase: got \(b.ix) after \(prevIx)")
            #expect(b.ix <= text.utf8.count, "Boundary index cannot exceed text byte length")
            #expect(b.nextIndent <= LineWrapper.maxIndent, "Indent must be within maxIndent")
            prevIx = b.ix
        }
    }

    @Test("test_wrap_negative_width_graceful_handling")
    @MainActor
    func test_wrap_negative_width_graceful_handling() {
        let wrapper = makeWrapper()
        let text = "Negative width stress test string"
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(-100.0)
        )

        #expect(!boundaries.isEmpty)
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx)
            #expect(b.nextIndent <= LineWrapper.maxIndent)
            prevIx = b.ix
        }
    }

    @Test("test_wrap_subpixel_width_smaller_than_single_glyph")
    @MainActor
    func test_wrap_subpixel_width_smaller_than_single_glyph() {
        let wrapper = makeWrapper()
        let text = "abcdefgh"
        // Subpixel width 0.001px is much smaller than character advance (~9.6px)
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(0.001)
        )

        #expect(!boundaries.isEmpty)
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx)
            prevIx = b.ix
        }
    }

    @Test("test_wrap_huge_wrap_width_produces_zero_boundaries")
    @MainActor
    func test_wrap_huge_wrap_width_produces_zero_boundaries() {
        let wrapper = makeWrapper()
        let text = "A moderate line of text that should fit comfortably within a huge viewport"
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(100_000.0)
        )

        #expect(boundaries.isEmpty, "Huge wrap width should not wrap lines")
    }

    @Test("test_wrap_empty_fragments_and_empty_text")
    @MainActor
    func test_wrap_empty_fragments_and_empty_text() {
        let wrapper = makeWrapper()

        let b0 = wrapper.wrapLine(fragments: [], wrapWidth: px(100.0))
        #expect(b0.isEmpty)

        let b1 = wrapper.wrapLine(fragments: [LineFragment.text("")], wrapWidth: px(100.0))
        #expect(b1.isEmpty)

        let b2 = wrapper.wrapLine(fragments: [LineFragment.text(""), LineFragment.text("")], wrapWidth: px(100.0))
        #expect(b2.isEmpty)
    }

    @Test("test_wrap_long_unbroken_word_stress")
    @MainActor
    func test_wrap_long_unbroken_word_stress() {
        let wrapper = makeWrapper()
        // 5000 characters without spaces
        let longWord = String(repeating: "x", count: 5000)
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(longWord)],
            wrapWidth: px(80.0) // ~8 chars per line
        )

        #expect(boundaries.count > 100, "5000-char unbroken word should produce hundreds of wraps")
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx)
            #expect(b.ix <= 5000)
            prevIx = b.ix
        }
    }

    @Test("test_wrap_pathological_whitespace_and_tabs")
    @MainActor
    func test_wrap_pathological_whitespace_and_tabs() {
        let wrapper = makeWrapper()
        let whitespaceOnly = String(repeating: " ", count: 500)
        let b1 = wrapper.wrapLine(
            fragments: [LineFragment.text(whitespaceOnly)],
            wrapWidth: px(72.0)
        )
        #expect(!b1.isEmpty)
        for b in b1 {
            #expect(b.nextIndent <= LineWrapper.maxIndent)
        }

        let mixedTabs = "\t\t\t\thello\t\tworld\t\t\tthis\t\tis\t\ta\ttest"
        let b2 = wrapper.wrapLine(
            fragments: [LineFragment.text(mixedTabs)],
            wrapWidth: px(72.0)
        )
        #expect(!b2.isEmpty)
    }

    @Test("test_wrap_unicode_combining_zalgo_and_emoji")
    @MainActor
    func test_wrap_unicode_combining_zalgo_and_emoji() {
        let wrapper = makeWrapper()
        // Zalgo / combining accents
        let zalgo = "T\u{0300}\u{0301}\u{0302}\u{0303}e\u{0304}\u{0305}\u{0306}s\u{0307}\u{0308}t\u{0309}\u{030A} " +
                    "Z\u{030B}\u{030C}\u{030D}\u{030E}a\u{030F}\u{0310}l\u{0311}\u{0312}g\u{0313}o\u{0314}"
        let bZalgo = wrapper.wrapLine(
            fragments: [LineFragment.text(zalgo)],
            wrapWidth: px(50.0)
        )
        #expect(!bZalgo.isEmpty)
        var prevIx = 0
        for b in bZalgo {
            #expect(b.ix > prevIx)
            prevIx = b.ix
        }

        // Multi-codepoint emoji: Family + Flags + Zero-width joiners
        let emojiText = "👨‍👩‍👧‍👦 🇺🇸 👩🏾‍💻 🏳️‍🌈 🏎️ 🦀🦀🦀🦀🦀"
        let bEmoji = wrapper.wrapLine(
            fragments: [LineFragment.text(emojiText)],
            wrapWidth: px(60.0)
        )
        #expect(!bEmoji.isEmpty)
        prevIx = 0
        for b in bEmoji {
            #expect(b.ix > prevIx)
            prevIx = b.ix
        }
    }

    @Test("test_wrap_zero_and_extreme_element_fragments")
    @MainActor
    func test_wrap_zero_and_extreme_element_fragments() {
        let wrapper = makeWrapper()
        let fragments: [LineFragment] = [
            .element(px(0.0), 0),
            .text("abc"),
            .element(px(500.0), 1),
            .text("def"),
            .element(px(0.0), 1),
            .text("ghi"),
        ]

        let boundaries = wrapper.wrapLine(fragments: fragments, wrapWidth: px(50.0))
        #expect(!boundaries.isEmpty)
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix >= prevIx)
            prevIx = b.ix
        }
    }

    @Test("test_truncation_adversarial_boundary_widths")
    @MainActor
    func test_truncation_adversarial_boundary_widths() {
        let wrapper = makeWrapper()
        let text = "The quick brown fox jumps over the lazy dog"
        let dummyRun = [TextRun(
            len: text.utf8.count,
            font: Font(family: "Dummy", features: FontFeatures(), fallbacks: nil, weight: .normal, style: .normal),
            color: black(),
            backgroundColor: nil,
            underline: nil,
            strikethrough: nil
        )]

        // 1. Truncate width = 0
        let (res0, runs0) = wrapper.truncateLine(
            line: SharedString(text),
            truncateWidth: px(0.0),
            truncationAffix: "…",
            runs: dummyRun,
            truncateFrom: .end
        )
        #expect(res0.asString.contains("…"))
        #expect(runs0.map { $0.len }.reduce(0, +) == res0.asString.utf8.count)

        // 2. Truncate width smaller than affix itself
        let (resSmall, runsSmall) = wrapper.truncateLine(
            line: SharedString(text),
            truncateWidth: px(2.0),
            truncationAffix: "………[very long ellipsis]………",
            runs: dummyRun,
            truncateFrom: .end
        )
        #expect(runsSmall.map { $0.len }.reduce(0, +) == resSmall.asString.utf8.count)

        // 3. Truncate from start with zero width
        let (resStart, runsStart) = wrapper.truncateLine(
            line: SharedString(text),
            truncateWidth: px(0.0),
            truncationAffix: "…",
            runs: dummyRun,
            truncateFrom: .start
        )
        #expect(resStart.asString.hasPrefix("…"))
        #expect(runsStart.map { $0.len }.reduce(0, +) == resStart.asString.utf8.count)

        // 4. Truncate empty text
        let (resEmpty, runsEmpty) = wrapper.truncateLine(
            line: SharedString(""),
            truncateWidth: px(50.0),
            truncationAffix: "…",
            runs: [],
            truncateFrom: .end
        )
        #expect(resEmpty.asString == "")
        #expect(runsEmpty.isEmpty)
    }
}

// MARK: - Suite 2: TestDispatcher & Deterministic Scheduler Timing Stress

@Suite("Challenger 2 Suite 2: TestDispatcher Determinism and Clock Advancement Stress", .timeLimit(.minutes(2)))
struct TestDispatcherDeterminismStressTests {

    @Test("test_deterministic_order_under_high_task_volume_and_priorities")
    func test_deterministic_order_under_high_task_volume_and_priorities() {
        let fixedSeed: UInt64 = 0xdeadbeef_cafebabe
        var baselineTrace: [String]? = nil

        // Repeat 5 times with exact same seed
        for runIdx in 0..<5 {
            let dispatcher = TestDispatcher(seed: fixedSeed)
            let trace = AtomicLock([String]())

            // Spawn 60 tasks across priorities
            for i in 0..<20 {
                dispatcher.dispatch({
                    trace.withLock { $0.append("high-\(i)") }
                }, priority: .high)

                dispatcher.dispatch({
                    trace.withLock { $0.append("med-\(i)") }
                }, priority: .medium)

                dispatcher.dispatch({
                    trace.withLock { $0.append("low-\(i)") }
                }, priority: .low)
            }

            dispatcher.runUntilParked()
            let currentTrace = trace.get()
            #expect(currentTrace.count == 60, "Run \(runIdx): All 60 tasks must complete")

            if let base = baselineTrace {
                #expect(
                    currentTrace == base,
                    "Execution order must be bit-for-bit identical for same seed on run \(runIdx)"
                )
            } else {
                baselineTrace = currentTrace
            }
        }
    }

    @Test("test_different_seeds_produce_divergent_orderings")
    func test_different_seeds_produce_divergent_orderings() {
        var observedTraces = Set<[String]>()
        let numSeeds = 15

        for seed in 0..<numSeeds {
            let dispatcher = TestDispatcher(seed: UInt64(seed + 100))
            let trace = AtomicLock([String]())

            for i in 0..<10 {
                dispatcher.dispatch({
                    trace.withLock { $0.append("h-\(i)") }
                }, priority: .high)
                dispatcher.dispatch({
                    trace.withLock { $0.append("m-\(i)") }
                }, priority: .medium)
            }

            dispatcher.runUntilParked()
            observedTraces.insert(trace.get())
        }

        #expect(
            observedTraces.count >= 10,
            "15 different seeds should produce at least 10 distinct task orderings (got \(observedTraces.count))"
        )
    }

    @Test("test_clock_advancement_triggers_timers_at_exact_duration")
    func test_clock_advancement_triggers_timers_at_exact_duration() {
        let dispatcher = TestDispatcher(seed: 123)
        let bg = BackgroundExecutor(scheduler: dispatcher.schedulerInstance)
        let fired = AtomicLock([Int]())

        // Schedule timers: 10ms, 20ms, 30ms, 50ms, 100ms
        let delaysMs = [10, 20, 30, 50, 100]
        for delay in delaysMs {
            let dur = Duration.milliseconds(delay)
            bg.spawn {
                await bg.timer(dur).wait()
                fired.withLock { $0.append(delay) }
            }.detach()
        }

        dispatcher.runUntilParked()
        #expect(fired.get().isEmpty, "No timers should fire before clock advances")

        // Advance by 15ms -> 10ms should fire
        dispatcher.advanceClock(by: .milliseconds(15))
        #expect(fired.get() == [10], "Only 10ms timer should fire at 15ms")

        // Advance by another 20ms (now 35ms) -> 20ms and 30ms should fire
        dispatcher.advanceClock(by: .milliseconds(20))
        #expect(fired.get() == [10, 20, 30], "20ms and 30ms timers should have fired")

        // Advance to next timer using advanceClockToNextTimer()
        let hasNext1 = dispatcher.advanceClockToNextTimer()
        #expect(hasNext1)
        dispatcher.runUntilParked()
        #expect(fired.get() == [10, 20, 30, 50])

        let hasNext2 = dispatcher.advanceClockToNextTimer()
        #expect(hasNext2)
        dispatcher.runUntilParked()
        #expect(fired.get() == [10, 20, 30, 50, 100])

        let hasNext3 = dispatcher.advanceClockToNextTimer()
        #expect(!hasNext3, "No more timers pending")
    }

    @Test("test_concurrent_multi_threaded_dispatch_zero_deadlocks")
    func test_concurrent_multi_threaded_dispatch_zero_deadlocks() async {
        let dispatcher = TestDispatcher(seed: 999)
        let completed = AtomicLock(0)
        let totalThreads = 4
        let tasksPerThread = 50

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<totalThreads {
                group.addTask {
                    for _ in 0..<tasksPerThread {
                        dispatcher.dispatch({
                            completed.withLock { $0 += 1 }
                        }, priority: .medium)
                    }
                }
            }
        }

        dispatcher.runUntilParked()
        #expect(
            completed.get() == totalThreads * tasksPerThread,
            "All concurrent tasks must complete without deadlock or drops"
        )
    }

    @Test("test_drain_tasks_cleans_up_safely")
    func test_drain_tasks_cleans_up_safely() {
        let dispatcher = TestDispatcher(seed: 42)
        let completed = AtomicLock(0)

        for _ in 0..<20 {
            dispatcher.dispatch({
                completed.withLock { $0 += 1 }
            }, priority: .low)
        }

        // Drain tasks before running
        dispatcher.drainTasks()
        dispatcher.runUntilParked()
        #expect(completed.get() == 0, "Drained tasks should not execute")
    }
}

// MARK: - Suite 3: List Follow-Tail State Machine Stress

@Suite("Challenger 2 Suite 3: List Follow-Tail State Machine and Rapid Additions Stress")
struct ListFollowTailStressTests {

    private struct DynamicListView: Render, IntoElement {
        let state: ListState
        let itemHeight: Pixels

        init(_ state: ListState, itemHeight: Pixels = px(20.0)) {
            self.state = state
            self.itemHeight = itemHeight
        }

        typealias ElementType = AnyElement

        func render(_ window: inout Window, _ cx: inout Context<DynamicListView>) -> AnyElement {
            intoAnyElement()
        }

        func intoElement() -> AnyElement {
            let h = itemHeight
            return list(state) { _, _, _ in
                div().h(h).wFull().intoAnyElement()
            }
            .wFull()
            .hFull()
            .intoAnyElement()
        }

        func intoAnyElement() -> AnyElement {
            intoElement()
        }
    }

    @Test("test_follow_tail_under_rapid_100_burst_additions")
    @MainActor
    func test_follow_tail_under_rapid_100_burst_additions() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        var currentItemCount = 10
        let state = ListState.new(currentItemCount, .top, px(0.0)).measureAll()
        state.setFollowMode(.tail)

        // Initial paint: viewport 200w x 100h, itemHeight 20px -> 5 visible items
        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(100.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }

        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == currentItemCount - 5)

        // Burst additions: 50 times add 3 items and redraw
        for _ in 0..<50 {
            state.splice(currentItemCount..<currentItemCount, count: 3)
            currentItemCount += 3

            cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(100.0))) { _, _ in
                DynamicListView(state, itemHeight: px(20.0))
            }

            #expect(state.isFollowingTail(), "Follow tail must stay active during continuous additions")
            #expect(
                state.logicalScrollTop().itemIx == currentItemCount - 5,
                "Logical scroll top must stay anchored to tail top (\(currentItemCount - 5))"
            )
        }
    }

    @Test("test_follow_tail_interleaved_user_scroll_disengagement_and_reengagement")
    @MainActor
    func test_follow_tail_interleaved_user_scroll_disengagement_and_reengagement() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        var currentCount = 20
        let state = ListState.new(currentCount, .top, px(2000.0))
        state.setFollowMode(.tail)

        // Viewport 200px, 20 items * 20px = 400px total -> 10 visible items (200 / 20 = 10)
        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }
        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == 10)

        // 1. User scrolls UP: delta.y = 80px > 0 (4 items up)
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(50.0)),
            delta: .pixels(point(px(0.0), px(80.0)))
        ))
        #expect(!state.isFollowingTail(), "User scrolling up must immediately disengage follow-tail")
        #expect(state.logicalScrollTop().itemIx == 6)

        // 2. Add 20 items programmatically while disengaged
        state.splice(currentCount..<currentCount, count: 20)
        currentCount += 20

        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }

        // Must remain disengaged and NOT jump to tail!
        #expect(!state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == 6)

        // 3. User scrolls DOWN to bottom: delta.y = -10,000px
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(50.0)),
            delta: .pixels(point(px(0.0), px(-10000.0)))
        ))

        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }

        // Must re-engage follow-tail when hitting bottom
        #expect(state.isFollowingTail(), "Scrolling back to bottom must re-engage follow-tail")
        #expect(state.logicalScrollTop().itemIx == currentCount - 10)

        // 4. Subsequent additions continue following tail
        state.splice(currentCount..<currentCount, count: 5)
        currentCount += 5

        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }
        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == currentCount - 10)
    }

    @Test("test_follow_tail_rapid_cyclic_scroll_and_additions")
    @MainActor
    func test_follow_tail_rapid_cyclic_scroll_and_additions() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        var count = 30
        let state = ListState.new(count, .top, px(5000.0))
        state.setFollowMode(.tail)

        // 10 cycles of: add items -> scroll away -> add items -> scroll back to bottom
        for cycle in 0..<10 {
            // Draw at bottom: viewport 150px, item 25px -> 6 visible items
            cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(150.0))) { _, _ in
                DynamicListView(state, itemHeight: px(25.0))
            }
            #expect(state.isFollowingTail(), "Cycle \(cycle): Should be following tail initially")
            #expect(state.logicalScrollTop().itemIx == count - 6)

            // Scroll up to disengage (2 items up = 50px)
            cx.simulateEvent(ScrollWheelEvent(
                position: point(px(50.0), px(50.0)),
                delta: .pixels(point(px(0.0), px(50.0)))
            ))
            #expect(!state.isFollowingTail(), "Cycle \(cycle): Must disengage on scroll up")

            // Programmatic addition while scrolled up
            state.splice(count..<count, count: 4)
            count += 4

            cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(150.0))) { _, _ in
                DynamicListView(state, itemHeight: px(25.0))
            }
            #expect(!state.isFollowingTail(), "Cycle \(cycle): Must stay disengaged after addition")

            // Scroll down to bottom
            cx.simulateEvent(ScrollWheelEvent(
                position: point(px(50.0), px(50.0)),
                delta: .pixels(point(px(0.0), px(-5000.0)))
            ))

            cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(150.0))) { _, _ in
                DynamicListView(state, itemHeight: px(25.0))
            }
            #expect(state.isFollowingTail(), "Cycle \(cycle): Must re-engage after scrolling to bottom")
            #expect(state.logicalScrollTop().itemIx == count - 6)
        }
    }

    @Test("test_follow_tail_with_middle_and_tail_splices")
    @MainActor
    func test_follow_tail_with_middle_and_tail_splices() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(50, .top, px(0.0)).measureAll()
        state.setFollowMode(.tail)

        // Viewport 200px, item 20px -> 10 visible items
        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }
        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == 40) // 50 - 10

        // Delete 20 items from middle: 10..<30
        state.splice(10..<30, count: 0)
        #expect(state.itemCount() == 30)

        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }
        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == 20) // 30 - 10

        // Delete from the very end: 25..<30
        state.splice(25..<30, count: 0)
        #expect(state.itemCount() == 25)

        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            DynamicListView(state, itemHeight: px(20.0))
        }
        #expect(state.isFollowingTail())
        #expect(state.logicalScrollTop().itemIx == 15) // 25 - 10
    }
}
