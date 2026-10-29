// Tests ported from: crates/gpui/src/elements/div.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Testing
@testable import GPUI

@Suite("DivTests")
struct DivTests {
    @Test("scroll_handle_aligns_wide_children_to_left_edge")
    func scrollHandleAlignsWideChildrenToLeftEdge() {
        let handle = ScrollHandle.new()
        let state = handle.state
        state.bounds = Bounds(origin: point(px(0), px(0)), size: size(px(80), px(20)))
        state.childBounds = [Bounds(origin: point(px(25), px(0)), size: size(px(200), px(20)))]
        state.overflow.x = .scroll
        state.activeItem = ScrollActiveItem(index: 0, strategy: .default)

        handle.scrollToActiveItem()

        #expect(handle.offset().x == px(-25))
    }

    @Test("scroll_handle_aligns_tall_children_to_top_edge")
    func scrollHandleAlignsTallChildrenToTopEdge() {
        let handle = ScrollHandle.new()
        let state = handle.state
        state.bounds = Bounds(origin: point(px(0), px(0)), size: size(px(20), px(80)))
        state.childBounds = [Bounds(origin: point(px(0), px(25)), size: size(px(20), px(200)))]
        state.overflow.y = .scroll
        state.activeItem = ScrollActiveItem(index: 0, strategy: .default)

        handle.scrollToActiveItem()

        #expect(handle.offset().y == px(-25))
    }

    @Test("div construction and styling")
    func divConstructionAndStyling() {
        let d = div()
            .flex()
            .flexCol()
            .w(px(100))
            .h(px(50))
            .p(px(10))

        #expect(d.style.size.width == .pixels(px(100)))
        #expect(d.style.size.height == .pixels(px(50)))
        #expect(d.style.display == .flex)
        #expect(d.style.flexDirection == .column)
    }

    @Test("div children hierarchy")
    func divChildrenHierarchy() {
        let parent = div()
            .child(div().id("child1"))
            .child(div().id("child2"))

        #expect(parent.children.count == 2)
    }
}
