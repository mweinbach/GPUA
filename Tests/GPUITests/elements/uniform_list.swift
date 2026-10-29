// Tests ported from: crates/gpui/src/elements/uniform_list.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

struct SelectNext: UnitAction {
    static let name = "example::SelectNext"
}

struct SelectPrev: UnitAction {
    static let name = "example::SelectPrev"
}

// PORT NOTE: RangeCell stores visible range recorded during render for test assertions.
final class RangeCell: @unchecked Sendable {
    var range: Range<Int> = 0..<0
}

@Suite("UniformList Element Tests")
struct UniformListElementTests {

    // PORT NOTE: TestView is thread-confined to main actor during test execution.
    final class TestView: Render, @unchecked Sendable {
        var index: Int
        var length: Int
        var scrollHandle: UniformListScrollHandle
        var focusHandle: FocusHandle
        let visibleRangeCell: RangeCell

        var visibleRange: Range<Int> {
            visibleRangeCell.range
        }

        init(
            index: Int = 0,
            length: Int = 47,
            scrollHandle: UniformListScrollHandle = UniformListScrollHandle.new(),
            focusHandle: FocusHandle,
            visibleRangeCell: RangeCell = RangeCell()
        ) {
            self.index = index
            self.length = length
            self.scrollHandle = scrollHandle
            self.focusHandle = focusHandle
            self.visibleRangeCell = visibleRangeCell
        }

        func selectNext(_ action: SelectNext, _ window: inout Window) {
            if index + 1 == length {
                index = 0
            } else {
                index += 1
            }
            scrollHandle.scrollToItem(index, strategy: .nearest)
            window.refresh()
        }

        func selectPrevious(_ action: SelectPrev, _ window: inout Window) {
            if index == 0 {
                index = length - 1
            } else {
                index -= 1
            }
            scrollHandle.scrollToItem(index, strategy: .nearest)
            window.refresh()
        }

        func render(_ window: inout Window, _ cx: inout Context<TestView>) -> AnyElement {
            let lengthCopy = self.length
            let scrollHandleCopy = self.scrollHandle
            let cell = self.visibleRangeCell

            return div()
                .trackFocus(focusHandle)
                .onAction { [weak self] (action: SelectNext, window: inout Window, app: inout App) in
                    self?.selectNext(action, &window)
                }
                .onAction { [weak self] (action: SelectPrev, window: inout Window, app: inout App) in
                    self?.selectPrevious(action, &window)
                }
                .sizeFull()
                .child(
                    uniformList(
                        ElementId(named: "entries"),
                        lengthCopy,
                        { range, window, cx in
                            cell.range = range
                            return range.map { ix in
                                div().h(px(20.0)).child("Item \(ix)").intoAnyElement()
                            }
                        }
                    )
                    .trackScroll(scrollHandleCopy)
                    .h(px(200.0))
                )
                .intoAnyElement()
        }
    }

    @Test
    @MainActor
    func test_scroll_strategy_nearest() {
        let testCx = TestAppContext.single()
        let (view, cx): (Entity<TestView>, VisualTestContext) = testCx.addWindowView { window, cx in
            let focusHandle = window.focusHandle()
            window.focus(focusHandle, &cx.app)
            return TestView(
                index: 0,
                length: 47,
                scrollHandle: UniformListScrollHandle.new(),
                focusHandle: focusHandle,
                visibleRangeCell: RangeCell()
            )
        }

        // Draw initial layout: 10 out of 47 items are visible
        cx.draw()
        view.readWith(cx) { view, _ in
            #expect(view.visibleRange == 0..<10)
        }

        // First 9 times selecting next item does not scroll
        for ix in 1..<10 {
            cx.dispatchAction(SelectNext())
            cx.draw()
            view.readWith(cx) { view, _ in
                #expect(view.index == ix)
                #expect(view.visibleRange == 0..<10)
            }
        }

        // Now each time the list scrolls down by 1
        for ix in 10..<47 {
            cx.dispatchAction(SelectNext())
            cx.draw()
            view.readWith(cx) { view, _ in
                #expect(view.index == ix)
                #expect(view.visibleRange == (ix - 9)..<(ix + 1))
            }
        }

        // After the last item we move back to the start
        cx.dispatchAction(SelectNext())
        cx.draw()
        view.readWith(cx) { view, _ in
            #expect(view.index == 0)
            #expect(view.visibleRange == 0..<10)
        }

        // Return to the last element
        cx.dispatchAction(SelectPrev())
        cx.draw()
        view.readWith(cx) { view, _ in
            #expect(view.index == 46)
            #expect(view.visibleRange == 37..<47)
        }

        // First 9 times selecting previous does not scroll
        for ix in (37..<46).reversed() {
            cx.dispatchAction(SelectPrev())
            cx.draw()
            view.readWith(cx) { view, _ in
                #expect(view.index == ix)
                #expect(view.visibleRange == 37..<47)
            }
        }

        // Now each time the list scrolls up by 1
        for ix in (0..<37).reversed() {
            cx.dispatchAction(SelectPrev())
            cx.draw()
            view.readWith(cx) { view, _ in
                #expect(view.index == ix)
                #expect(view.visibleRange == ix..<(ix + 10))
            }
        }
    }
}
