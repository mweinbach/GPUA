// Tests ported from: crates/gpui/src/elements/list.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
import Foundation
@testable import GPUI

// PORT NOTE: IntCell stores an integer across test view renders matching upstream Rc<Cell<usize>>.
final class IntCell: @unchecked Sendable {
    var value: Int
    init(_ value: Int) { self.value = value }
}

@Suite("List Element Tests")
struct ListElementTests {

    struct SimpleTestView: Render, IntoElement {
        let state: ListState
        let itemHeight: Pixels

        init(_ state: ListState, itemHeight: Pixels = px(10.0)) {
            self.state = state
            self.itemHeight = itemHeight
        }

        typealias ElementType = AnyElement

        func render(_ window: inout Window, _ cx: inout Context<SimpleTestView>) -> AnyElement {
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

    struct DynamicHeightTestView: Render, IntoElement {
        typealias ElementType = AnyElement
        let state: ListState
        let heightCell: IntCell

        init(state: ListState, heightCell: IntCell) {
            self.state = state
            self.heightCell = heightCell
        }

        func render(_ window: inout Window, _ cx: inout Context<DynamicHeightTestView>) -> AnyElement {
            intoAnyElement()
        }

        func intoElement() -> AnyElement {
            let h = px(Float(heightCell.value))
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

    @Test
    @MainActor
    func test_reset_after_paint_before_scroll() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(5, .top, px(10.0))

        // Ensure that the list is scrolled to the top
        state.scrollTo(ListOffset(itemIx: 0, offsetInItem: px(0.0)))

        // Paint
        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(20.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(10.0))
        }

        // Reset
        state.reset(5)

        // And then receive a scroll event _before_ the next paint
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(1.0), px(1.0)),
            delta: .pixels(point(px(0.0), px(-500.0)))
        ))

        // Scroll position should stay at the top of the list
        #expect(state.logicalScrollTop().itemIx == 0)
        #expect(state.logicalScrollTop().offsetInItem == px(0.0))
    }

    @Test
    @MainActor
    func test_scroll_by_positive_and_negative_distance() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(5, .top, px(10.0))

        // Paint
        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(100.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(20.0))
        }

        // Test positive distance: start at item 1, move down 30px
        state.scrollBy(px(30.0))

        // Should move to item 2
        let offset = state.logicalScrollTop()
        #expect(offset.itemIx == 1)
        #expect(offset.offsetInItem == px(10.0))

        // Test negative distance: start at item 2, move up 30px
        state.scrollBy(px(-30.0))

        // Should move back to item 1
        let offset2 = state.logicalScrollTop()
        #expect(offset2.itemIx == 0)
        #expect(offset2.offsetInItem == px(0.0))

        // Test zero distance
        state.scrollBy(px(0.0))
        let offset3 = state.logicalScrollTop()
        #expect(offset3.itemIx == 0)
        #expect(offset3.offsetInItem == px(0.0))
    }

    @Test
    @MainActor
    func test_measure_all_after_width_change() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0)).measureAll()
        let view = cx.update { _, cx in
            cx.new { _ in SimpleTestView(state, itemHeight: px(50.0)) }
        }

        // First draw at width 100: all 10 items measured (total 500px).
        // Viewport is 200px, so max scroll offset should be 300px.
        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(state.maxOffsetForScrollbar().y == px(300.0))

        // Second draw at a different width: items get invalidated.
        cx.draw(point(px(0.0), px(0.0)), size(px(200.0), px(200.0))) { _, _ in
            view
        }
        #expect(state.maxOffsetForScrollbar().y == px(300.0))
    }

    @Test
    @MainActor
    func test_remeasure() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let itemHeight = IntCell(100)
        let state = ListState.new(10, .top, px(10.0))

        let view = cx.update { _, cx in
            cx.new { _ in DynamicHeightTestView(state: state, heightCell: itemHeight) }
        }

        // Simulate scrolling 40px inside the element with index 2.
        state.scrollTo(ListOffset(itemIx: 2, offsetInItem: px(40.0)))

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset = state.logicalScrollTop()
        #expect(offset.itemIx == 2)
        #expect(offset.offsetInItem == px(40.0))

        // Update itemHeight to be 50px instead of 100px so scroll position is proportionally preserved
        itemHeight.value = 50
        state.remeasure()

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset2 = state.logicalScrollTop()
        #expect(offset2.itemIx == 2)
        #expect(offset2.offsetInItem == px(20.0))
    }

    @Test
    @MainActor
    func test_follow_tail_stays_at_bottom_as_items_grow() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let itemHeight = IntCell(50)
        let state = ListState.new(10, .top, px(0.0))

        let view = cx.update { _, cx in
            cx.new { _ in DynamicHeightTestView(state: state, heightCell: itemHeight) }
        }

        state.setFollowMode(.tail)

        // First paint — items are 50px, total 500px, viewport 200px.
        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset = state.logicalScrollTop()
        #expect(offset.itemIx == 6)
        #expect(offset.offsetInItem == px(0.0))
        #expect(state.isFollowingTail())

        // Simulate items growing: 10 items x 80px = 800px total.
        itemHeight.value = 80
        state.remeasure()

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset2 = state.logicalScrollTop()
        #expect(offset2.itemIx == 7)
        #expect(offset2.offsetInItem == px(40.0))
        #expect(state.isFollowingTail())
    }

    @Test
    @MainActor
    func test_follow_tail_disengages_on_user_scroll() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0))

        state.setFollowMode(.tail)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(50.0))
        }
        #expect(state.isFollowingTail())

        // Simulate user scrolling up
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(100.0)))
        ))

        #expect(!state.isFollowingTail())
    }

    @Test
    @MainActor
    func test_follow_tail_disengages_on_scrollbar_reposition() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0)).measureAll()
        let view = cx.update { _, cx in
            cx.new { _ in SimpleTestView(state, itemHeight: px(50.0)) }
        }

        state.setFollowMode(.tail)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(state.isFollowingTail())

        state.setOffsetFromScrollbar(point(px(0.0), px(150.0)))

        let offset = state.logicalScrollTop()
        #expect(offset.itemIx == 3)
        #expect(offset.offsetInItem == px(0.0))
        #expect(!state.isFollowingTail())

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset2 = state.logicalScrollTop()
        #expect(offset2.itemIx == 3)
        #expect(offset2.offsetInItem == px(0.0))
    }

    @Test
    @MainActor
    func test_set_follow_tail_snaps_to_bottom() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0))
        let view = cx.update { _, cx in
            cx.new { _ in SimpleTestView(state, itemHeight: px(50.0)) }
        }

        state.scrollTo(ListOffset(itemIx: 3, offsetInItem: px(0.0)))

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset = state.logicalScrollTop()
        #expect(offset.itemIx == 3)
        #expect(offset.offsetInItem == px(0.0))
        #expect(!state.isFollowingTail())

        state.setFollowMode(.tail)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        let offset2 = state.logicalScrollTop()
        #expect(offset2.itemIx == 6)
        #expect(offset2.offsetInItem == px(0.0))
        #expect(state.isFollowingTail())
    }

    @Test
    @MainActor
    func test_bottom_aligned_scrollbar_offset_at_end() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let items = 10
        let itemSize: Float = 50.0

        let state = ListState.new(
            items,
            .bottom,
            px(Float(items) * itemSize)
        )

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(100.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(itemSize))
        }

        #expect(state.logicalScrollTop().itemIx == items)

        let maxOffset = state.maxOffsetForScrollbar()
        let scrollOffset = state.scrollPxOffsetForScrollbar()

        #expect(-scrollOffset.y == maxOffset.y)
    }

    @Test
    @MainActor
    func test_follow_tail_reengages_when_scrolled_back_to_bottom() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0))

        state.setFollowMode(.tail)
        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(50.0))
        }
        #expect(state.isFollowingTail())

        // Scroll up — follow_tail suspends
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(50.0)))
        ))
        #expect(!state.isFollowingTail())

        // Scroll back down to the bottom
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(-10000.0)))
        ))

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            SimpleTestView(state, itemHeight: px(50.0))
        }
        #expect(state.isFollowingTail())
    }

    @Test
    @MainActor
    func test_follow_tail_reengagement_not_fooled_by_unmeasured_items() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(20, .top, px(1000.0))
        let view = cx.update { _, cx in
            cx.new { _ in SimpleTestView(state, itemHeight: px(50.0)) }
        }

        state.setFollowMode(.tail)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(state.isFollowingTail())

        // Scroll up 200px
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(200.0)))
        ))
        #expect(!state.isFollowingTail())

        state.remeasureItems(19..<20)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(!state.isFollowingTail())
    }

    @Test
    @MainActor
    func test_follow_tail_suspended_state_cleared_by_explicit_actions() {
        let testCx = TestAppContext.single()
        let cx = testCx.addEmptyWindow()

        let state = ListState.new(10, .top, px(0.0)).measureAll()
        let view = cx.update { _, cx in
            cx.new { _ in SimpleTestView(state, itemHeight: px(50.0)) }
        }

        state.setFollowMode(.tail)

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        // Scroll up — suspends
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(50.0)))
        ))
        #expect(!state.isFollowingTail())

        // Scroll back to bottom — re-engages
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(-10000.0)))
        ))

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(state.isFollowingTail())

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }

        // Drag scrollbar to middle
        state.setOffsetFromScrollbar(point(px(0.0), px(150.0)))

        // Scroll to bottom
        cx.simulateEvent(ScrollWheelEvent(
            position: point(px(50.0), px(100.0)),
            delta: .pixels(point(px(0.0), px(-10000.0)))
        ))

        cx.draw(point(px(0.0), px(0.0)), size(px(100.0), px(200.0))) { _, _ in
            view
        }
        #expect(!state.isFollowingTail())
    }
}
