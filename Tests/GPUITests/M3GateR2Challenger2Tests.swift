// Swift-only: Milestone 3 Re-Gate Iteration 2 Challenger 2 Empirical Stress Test Harness

import Foundation
import Testing
@testable import GPUI
@testable import Scheduler

// MARK: - Concurrency Lock Helper

private final class ThreadSafeBox<T>: @unchecked Sendable {
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

// MARK: - Suite 1: UniformList Large-Item Virtualization & Boundary Stress

@Suite("Challenger 2 Re-Gate Suite 1: UniformList Large Virtualization and Precision Stress")
struct UniformListLargeVirtualizationStressTests {

    private final class VirtualizedListView: Render, @unchecked Sendable {
        let itemCount: Int
        let itemHeight: Pixels
        let scrollHandle: UniformListScrollHandle
        let visibleRangeBox: ThreadSafeBox<Range<Int>>

        init(
            itemCount: Int,
            itemHeight: Pixels = px(20.0),
            scrollHandle: UniformListScrollHandle,
            visibleRangeBox: ThreadSafeBox<Range<Int>>
        ) {
            self.itemCount = itemCount
            self.itemHeight = itemHeight
            self.scrollHandle = scrollHandle
            self.visibleRangeBox = visibleRangeBox
        }

        func render(_ window: inout Window, _ cx: inout Context<VirtualizedListView>) -> AnyElement {
            let count = self.itemCount
            let h = self.itemHeight
            let handle = self.scrollHandle
            let rangeBox = self.visibleRangeBox

            return div()
                .sizeFull()
                .child(
                    uniformList(
                        ElementId(named: "virtual-list"),
                        count,
                        { range, window, cx in
                            rangeBox.set(range)
                            return range.map { ix in
                                div().h(h).wFull().child("Item \(ix)").intoAnyElement()
                            }
                        }
                    )
                    .trackScroll(handle)
                    .h(px(200.0))
                )
                .intoAnyElement()
        }
    }

    @Test("test_uniform_list_one_million_items_virtualization")
    @MainActor
    func test_uniform_list_one_million_items_virtualization() {
        let testCx = TestAppContext.single()
        let handle = UniformListScrollHandle.new()
        let rangeBox = ThreadSafeBox<Range<Int>>(0..<0)
        let totalItems = 1_000_000

        let (_, cx): (Entity<VirtualizedListView>, VisualTestContext) = testCx.addWindowView { _, _ in
            VirtualizedListView(
                itemCount: totalItems,
                itemHeight: px(20.0),
                scrollHandle: handle,
                visibleRangeBox: rangeBox
            )
        }

        // 1. Initial draw at top: viewport 200px / 20px = 10 items
        cx.draw()
        let r0 = rangeBox.get()
        #expect(r0.lowerBound == 0, "Top lowerBound must be 0")
        #expect(r0.count <= 11, "Must virtualize and render only ~10 visible items, got \(r0.count)")

        // 2. Scroll to middle: item 500,000 with strategy .top
        handle.scrollToItemStrict(500_000, strategy: .top)
        cx.update { window, _ in window.refresh() }
        cx.draw()

        let rMiddle = rangeBox.get()
        #expect(rMiddle.lowerBound == 500_000, "Lower bound must match scrolled index 500,000")
        #expect(rMiddle.count <= 11, "Must maintain O(1) rendered items at huge indices")

        // 3. Scroll to the absolute last item (999,999) with strategy .bottom
        handle.scrollToItemStrict(totalItems - 1, strategy: .bottom)
        cx.update { window, _ in window.refresh() }
        cx.draw()

        let rTail = rangeBox.get()
        #expect(rTail.upperBound == totalItems, "Tail upperBound must reach 1,000,000")
        #expect(rTail.lowerBound == totalItems - 10, "Tail lowerBound must be exactly 999,990")
    }

    @Test("test_uniform_list_subpixel_item_height")
    @MainActor
    func test_uniform_list_subpixel_item_height() {
        let testCx = TestAppContext.single()
        let handle = UniformListScrollHandle.new()
        let rangeBox = ThreadSafeBox<Range<Int>>(0..<0)

        let (_, cx): (Entity<VirtualizedListView>, VisualTestContext) = testCx.addWindowView { _, _ in
            VirtualizedListView(
                itemCount: 500,
                itemHeight: px(12.5),
                scrollHandle: handle,
                visibleRangeBox: rangeBox
            )
        }

        cx.draw()
        let r0 = rangeBox.get()
        #expect(r0.lowerBound == 0)
        // 200px / 12.5px = 16 items
        #expect(r0.count >= 16 && r0.count <= 18)

        // Scroll to item 123
        handle.scrollToItemStrict(123, strategy: .top)
        cx.update { window, _ in window.refresh() }
        cx.draw()

        let r123 = rangeBox.get()
        #expect(r123.lowerBound == 123)
        #expect(r123.count >= 16 && r123.count <= 18)
    }

    @Test("test_uniform_list_dynamic_item_count_shrink_while_scrolled")
    @MainActor
    func test_uniform_list_dynamic_item_count_shrink_while_scrolled() {
        let testCx = TestAppContext.single()
        let handle = UniformListScrollHandle.new()
        let rangeBox = ThreadSafeBox<Range<Int>>(0..<0)

        final class MutableCountListView: Render, @unchecked Sendable {
            var count: Int
            let handle: UniformListScrollHandle
            let rangeBox: ThreadSafeBox<Range<Int>>

            init(count: Int, handle: UniformListScrollHandle, rangeBox: ThreadSafeBox<Range<Int>>) {
                self.count = count
                self.handle = handle
                self.rangeBox = rangeBox
            }

            func render(_ window: inout Window, _ cx: inout Context<MutableCountListView>) -> AnyElement {
                let currentCount = self.count
                let h = handle
                let box = self.rangeBox
                return div().sizeFull().child(
                    uniformList(ElementId(named: "shrink-list"), currentCount, { range, _, _ in
                        box.set(range)
                        return range.map { ix in div().h(px(20.0)).child("Item \(ix)").intoAnyElement() }
                    })
                    .trackScroll(h)
                    .h(px(200.0))
                ).intoAnyElement()
            }
        }

        let (view, cx): (Entity<MutableCountListView>, VisualTestContext) = testCx.addWindowView { _, _ in
            MutableCountListView(count: 10_000, handle: handle, rangeBox: rangeBox)
        }

        // Scroll deep into list
        cx.draw()
        handle.scrollToItemStrict(5000, strategy: .top)
        cx.update { window, _ in window.refresh() }
        cx.draw()
        #expect(rangeBox.get().lowerBound == 5000)

        // Suddenly shrink to 5 items!
        view.update(cx.cx.app) { v, _ in
            v.count = 5
        }
        cx.update { window, _ in window.refresh() }
        cx.draw()

        // Must not crash with inverted range, and must clamp cleanly
        let shrunkRange = rangeBox.get()
        #expect(shrunkRange.lowerBound >= 0)
        #expect(shrunkRange.upperBound <= 5)
    }

    @Test("test_uniform_list_zero_item_count_and_zero_viewport")
    @MainActor
    func test_uniform_list_zero_item_count_and_zero_viewport() {
        let testCx = TestAppContext.single()
        let handle = UniformListScrollHandle.new()
        let rangeBox = ThreadSafeBox<Range<Int>>(0..<0)

        let (_, cx): (Entity<VirtualizedListView>, VisualTestContext) = testCx.addWindowView { _, _ in
            VirtualizedListView(
                itemCount: 0,
                itemHeight: px(20.0),
                scrollHandle: handle,
                visibleRangeBox: rangeBox
            )
        }

        cx.draw()
        #expect(rangeBox.get().isEmpty, "Zero item list must render empty range")
    }
}

// MARK: - Suite 2: List Variable-Height Measurement & Splice Stress

@Suite("Challenger 2 Re-Gate Suite 2: List Variable-Height Measurement and Splice Stress")
struct ListVariableHeightAndSpliceStressTests {

    private struct VariableHeightView: Render, IntoElement {
        let state: ListState
        let heights: [Pixels]

        typealias ElementType = AnyElement

        func render(_ window: inout Window, _ cx: inout Context<VariableHeightView>) -> AnyElement {
            intoAnyElement()
        }

        func intoElement() -> AnyElement {
            let hList = self.heights
            return list(state) { ix, _, _ in
                let h = ix < hList.count ? hList[ix] : px(20.0)
                return div().h(h).wFull().child("Item \(ix)").intoAnyElement()
            }
            .wFull()
            .hFull()
            .intoAnyElement()
        }

        func intoAnyElement() -> AnyElement {
            intoElement()
        }
    }

    @Test("test_list_variable_height_sumtree_measurement")
    @MainActor
    func test_list_variable_height_sumtree_measurement() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        // 30 items with wildly varying heights: 10px, 80px, 150px, 25px, etc.
        var heights: [Pixels] = []
        var expectedTotal: Float = 0.0
        for i in 0..<30 {
            let hVal: Float = Float((i * 37) % 180 + 15) // [15, 195]
            heights.append(px(hVal))
            expectedTotal += hVal
        }

        let state = ListState.new(heights.count, .top, px(0.0)).measureAll()

        // Draw in a 200px tall window
        cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
            VariableHeightView(state: state, heights: heights)
        }

        let maxScroll = state.maxOffsetForScrollbar().y
        let expectedMaxScroll = px(expectedTotal - 200.0)
        #expect(abs(maxScroll.value - expectedMaxScroll.value) < 1.0, "Total height measured by SumTree must match sum of item heights")

        // Scroll to item 15 with .top
        state.scrollTo(ListOffset(itemIx: 15, offsetInItem: px(0.0)))
        cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
            VariableHeightView(state: state, heights: heights)
        }
        #expect(state.logicalScrollTop().itemIx == 15)
        #expect(state.logicalScrollTop().offsetInItem == px(0.0))
    }

    @Test("test_list_splices_at_various_positions")
    @MainActor
    func test_list_splices_at_various_positions() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        var heights = Array(repeating: px(25.0), count: 50)
        let state = ListState.new(50, .top, px(0.0)).measureAll()

        cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
            VariableHeightView(state: state, heights: heights)
        }
        #expect(state.itemCount() == 50)

        // 1. Splice Head: Insert 5 items at index 0
        state.splice(0..<0, count: 5)
        heights.insert(contentsOf: Array(repeating: px(25.0), count: 5), at: 0)
        #expect(state.itemCount() == 55)

        // 2. Splice Middle: Replace 10 items (10..<20) with 20 items
        state.splice(10..<20, count: 20)
        heights.replaceSubrange(10..<20, with: Array(repeating: px(25.0), count: 20))
        #expect(state.itemCount() == 65)

        // 3. Splice Tail: Delete 15 items from the end (50..<65)
        state.splice(50..<65, count: 0)
        heights.removeSubrange(50..<65)
        #expect(state.itemCount() == 50)

        // Measure all newly spliced items
        _ = state.measureAll()

        cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
            VariableHeightView(state: state, heights: heights)
        }

        #expect(state.itemCount() == 50)
        let expectedTotalPx = 50.0 * 25.0
        let expectedMaxScroll = px(Float(expectedTotalPx) - 200.0)
        #expect(abs(state.maxOffsetForScrollbar().y.value - expectedMaxScroll.value) < 1.0)
    }

    @Test("test_list_rapid_scroll_alternation_stress")
    @MainActor
    func test_list_rapid_scroll_alternation_stress() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let heights = Array(repeating: px(30.0), count: 100)
        let state = ListState.new(100, .top, px(0.0)).measureAll()

        // Rapidly alternate scrolling between top and bottom 20 times
        for _ in 0..<20 {
            state.scrollTo(ListOffset(itemIx: 0, offsetInItem: px(0.0)))
            cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
                VariableHeightView(state: state, heights: heights)
            }
            #expect(state.logicalScrollTop().itemIx == 0)

            state.scrollTo(ListOffset(itemIx: 90, offsetInItem: px(0.0)))
            cx.draw(point(px(0.0), px(0.0)), size(px(300.0), px(200.0))) { _, _ in
                VariableHeightView(state: state, heights: heights)
            }
            #expect(state.logicalScrollTop().itemIx >= 90)
        }
    }
}

// MARK: - Suite 3: LineWrapper Pathological Unicode & Boundary Stress

@Suite("Challenger 2 Re-Gate Suite 3: LineWrapper Pathological Unicode and Boundary Stress")
struct LineWrapperPathologicalUnicodeStressTests {

    @MainActor
    private func makeWrapper() -> LineWrapper {
        let textSystem = TextSystem(platformTextSystem: NoopTextSystem())
        let fontId = textSystem.resolveFont(font(".ZedMono"))
        return LineWrapper(fontId: fontId, fontSize: px(16.0), textSystem: textSystem)
    }

    @Test("test_line_wrapper_complex_emoji_zwj_sequences")
    @MainActor
    func test_line_wrapper_complex_emoji_zwj_sequences() {
        let wrapper = makeWrapper()
        // Complex ZWJ emoji sequences: family with 4 members, kiss with skin tones, polar bear ZWJ
        let text = "👨‍👩‍👧‍👦 👩🏽‍❤️‍💋‍👨🏻 🐻‍❄️ 🏳️‍⚧️ 🧑🏼‍💻 🧑🏻‍🚀"
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(30.0) // Very narrow width forces frequent wraps
        )

        #expect(!boundaries.isEmpty, "Should wrap multi-codepoint emoji lines")
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx, "Boundary index must strictly increase")
            #expect(b.ix <= text.utf8.count, "Boundary index cannot exceed text byte length")
            prevIx = b.ix
        }
    }

    @Test("test_line_wrapper_rtl_and_bidi_marks")
    @MainActor
    func test_line_wrapper_rtl_and_bidi_marks() {
        let wrapper = makeWrapper()
        // Mixed Arabic, Hebrew, and Latin with explicit directional marks
        let bidiText = "\u{200E}English text \u{200F}مرحبا بالعالم \u{200E}more English \u{200F}שלום עולם \u{200C}test"
        let boundaries = wrapper.wrapLine(
            fragments: [LineFragment.text(bidiText)],
            wrapWidth: px(50.0)
        )

        #expect(!boundaries.isEmpty)
        var prevIx = 0
        for b in boundaries {
            #expect(b.ix > prevIx)
            prevIx = b.ix
        }
    }

    @Test("test_line_wrapper_subpixel_and_extreme_widths")
    @MainActor
    func test_line_wrapper_subpixel_and_extreme_widths() {
        let wrapper = makeWrapper()
        let text = "Swift GPUI Cross Platform Native Framework"

        // 1. Extreme subpixel width (0.00001 px)
        let bSubpixel = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(0.00001)
        )
        #expect(!bSubpixel.isEmpty)

        // 2. Huge width (10,000,000 px) -> no wraps
        let bHuge = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(10_000_000.0)
        )
        #expect(bHuge.isEmpty)

        // 3. Negative width (-100 px) -> treats safely
        let bNegative = wrapper.wrapLine(
            fragments: [LineFragment.text(text)],
            wrapWidth: px(-100.0)
        )
        #expect(!bNegative.isEmpty)
    }

    @Test("test_line_wrapper_truncation_extreme_affixes")
    @MainActor
    func test_line_wrapper_truncation_extreme_affixes() {
        let wrapper = makeWrapper()
        let shortText = "abc"
        let dummyRun = [TextRun(
            len: shortText.utf8.count,
            font: Font(family: "Dummy", features: FontFeatures(), fallbacks: nil, weight: .normal, style: .normal),
            color: black(),
            backgroundColor: nil,
            underline: nil,
            strikethrough: nil
        )]

        // Affix much longer than source text itself
        let giantAffix = "....................[EXTREMELY_LONG_ELLIPSIS]...................."
        let (truncated, runs) = wrapper.truncateLine(
            line: SharedString(shortText),
            truncateWidth: px(10.0),
            truncationAffix: giantAffix,
            runs: dummyRun,
            truncateFrom: .end
        )

        let totalRunLen = runs.map { $0.len }.reduce(0, +)
        #expect(totalRunLen == truncated.asString.utf8.count, "Total text run lengths must match truncated string length")
    }
}

// MARK: - Suite 4: TestDispatcher High-Load Determinism Stress

@Suite("Challenger 2 Re-Gate Suite 4: TestDispatcher High-Load Determinism and Precision Stress", .timeLimit(.minutes(2)))
struct TestDispatcherHighLoadDeterminismStressTests {

    @Test("test_dispatcher_100_iteration_seed_determinism_deep_graph")
    func test_dispatcher_100_iteration_seed_determinism_deep_graph() {
        let fixedSeed: UInt64 = 0xfeedface_12345678
        var baselineTrace: [String]? = nil

        // 100 iterations: every iteration must produce the exact bit-for-bit task order
        for iteration in 0..<100 {
            let dispatcher = TestDispatcher(seed: fixedSeed)
            let trace = ThreadSafeBox([String]())

            // Complex task DAG: High, Med, Low priority tasks spawning subtasks
            for i in 0..<15 {
                dispatcher.dispatch({
                    trace.withLock { $0.append("H-\(i)") }
                    dispatcher.dispatch({
                        trace.withLock { $0.append("H_sub-\(i)") }
                    }, priority: .high)
                }, priority: .high)

                dispatcher.dispatch({
                    trace.withLock { $0.append("M-\(i)") }
                }, priority: .medium)

                dispatcher.dispatch({
                    trace.withLock { $0.append("L-\(i)") }
                }, priority: .low)
            }

            dispatcher.runUntilParked()
            let currentTrace = trace.get()
            #expect(currentTrace.count == 60, "Iteration \(iteration): All 60 tasks must complete")

            if let base = baselineTrace {
                #expect(
                    currentTrace == base,
                    "Iteration \(iteration) diverged from baseline seed ordering"
                )
            } else {
                baselineTrace = currentTrace
            }
        }
    }

    @Test("test_dispatcher_distinct_seeds_high_divergence")
    func test_dispatcher_distinct_seeds_high_divergence() {
        var observedTraces = Set<[String]>()
        let numSeeds = 30

        for s in 0..<numSeeds {
            let dispatcher = TestDispatcher(seed: UInt64(s * 997 + 1))
            let trace = ThreadSafeBox([String]())

            for i in 0..<8 {
                dispatcher.dispatch({ trace.withLock { $0.append("h\(i)") } }, priority: .high)
                dispatcher.dispatch({ trace.withLock { $0.append("m\(i)") } }, priority: .medium)
                dispatcher.dispatch({ trace.withLock { $0.append("l\(i)") } }, priority: .low)
            }

            dispatcher.runUntilParked()
            observedTraces.insert(trace.get())
        }

        #expect(
            observedTraces.count >= 25,
            "30 distinct seeds must produce at least 25 unique execution traces (got \(observedTraces.count))"
        )
    }

    @Test("test_dispatcher_microsecond_timer_precision_and_cancellation")
    func test_dispatcher_microsecond_timer_precision_and_cancellation() {
        let dispatcher = TestDispatcher(seed: 777)
        let bg = BackgroundExecutor(scheduler: dispatcher.schedulerInstance)
        let fired = ThreadSafeBox([Int]())

        // Spawn timers at 10ms, 20ms, 30ms, 50ms, 100ms
        let t10 = bg.spawn {
            await bg.timer(.milliseconds(10)).wait()
            fired.withLock { $0.append(10) }
        }
        let t20 = bg.spawn {
            await bg.timer(.milliseconds(20)).wait()
            fired.withLock { $0.append(20) }
        }
        let t30 = bg.spawn {
            await bg.timer(.milliseconds(30)).wait()
            fired.withLock { $0.append(30) }
        }
        let t50 = bg.spawn {
            await bg.timer(.milliseconds(50)).wait()
            fired.withLock { $0.append(50) }
        }

        // Cancel t20 immediately before clock advances
        t20.cancel()

        t10.detach()
        t30.detach()
        t50.detach()

        dispatcher.runUntilParked()
        #expect(fired.get().isEmpty)

        // Advance by 15ms -> 10ms fires, 20ms was cancelled (does not fire!)
        dispatcher.advanceClock(by: .milliseconds(15))
        dispatcher.runUntilParked()
        #expect(fired.get() == [10])

        // Advance to next timer (30ms)
        let hasNext = dispatcher.advanceClockToNextTimer()
        #expect(hasNext)
        dispatcher.runUntilParked()
        #expect(fired.get() == [10, 30])

        // Advance to 50ms
        let hasNext2 = dispatcher.advanceClockToNextTimer()
        #expect(hasNext2)
        dispatcher.runUntilParked()
        #expect(fired.get() == [10, 30, 50])

        // Verify cancelled timer 20 never fired
        #expect(!fired.get().contains(20))
    }
}
