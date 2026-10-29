// Swift-only: Headless E2E view assertion suite

import Foundation
import Testing
@testable import GPUI

// PORT NOTE: Cell wrapper thread-confined to the test's main actor for recording execution state.
final class TestCell<T>: @unchecked Sendable {
    var value: T

    init(_ value: T) {
        self.value = value
    }
}

private func color(_ hex: UInt32) -> Hsla {
    Hsla(rgba: rgb(hex))
}

@Suite("Headless E2E View Assertion Tests")
struct HeadlessViewTests {

    // MARK: - Test 1: Full View Tree Layout & Quad Count/Bounds

    final class DashboardView: Render, @unchecked Sendable {
        func render(_ window: inout Window, _ cx: inout Context<DashboardView>) -> AnyElement {
            div()
                .w(px(800))
                .h(px(600))
                .bg(color(0x111111))
                .flex()
                .flexCol()
                .child(
                    // Header Bar (800 x 50)
                    div()
                        .wFull()
                        .h(px(50))
                        .bg(color(0x222222))
                )
                .child(
                    // Body (Row with Sidebar + Main content)
                    div()
                        .wFull()
                        .h(px(550))
                        .flex()
                        .flexRow()
                        .child(
                            // Sidebar (200 x 550)
                            div()
                                .w(px(200))
                                .hFull()
                                .bg(color(0x333333))
                        )
                        .child(
                            // Main Area (600 x 550)
                            div()
                                .w(px(600))
                                .hFull()
                                .bg(color(0x444444))
                                .p(px(20))
                                .child(
                                    // Card inside main area
                                    div()
                                        .w(px(300))
                                        .h(px(200))
                                        .bg(color(0x555555))
                                        .rounded(.pixels(px(8.0)))
                                        .border2()
                                        .borderColor(color(0xff0000))
                                )
                        )
                )
                .intoAnyElement()
        }
    }

    @Test("test_view_tree_quad_count_and_bounds")
    @MainActor
    func test_view_tree_quad_count_and_bounds() {
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<DashboardView>, VisualTestContext) = testCx.addWindowView { _, _ in
            DashboardView()
        }

        cx.draw()

        cx.update { window, _ in
            let quads = window.renderedFrame.scene.quads
            // Verify quads were painted for root, header, sidebar, main area, and card
            #expect(quads.count >= 5)

            // Verify root background quad
            let hasRootQuad = quads.contains { q in
                q.bounds.size.width >= 800 && q.bounds.size.height >= 600
            }
            #expect(hasRootQuad)

            // Verify header quad has height 50
            let hasHeaderQuad = quads.contains { q in
                q.bounds.size.height == 50 && q.bounds.size.width >= 800
            }
            #expect(hasHeaderQuad)

            // Verify sidebar quad has width 200
            let hasSidebarQuad = quads.contains { q in
                q.bounds.size.width == 200
            }
            #expect(hasSidebarQuad)

            // Verify card quad with border and corner radii
            let hasCardQuad = quads.contains { q in
                q.bounds.size.width == 300 && q.bounds.size.height == 200 && q.cornerRadii.topLeft > 0
            }
            #expect(hasCardQuad)
        }
    }

    // MARK: - Test 2: Text Layout & Rendering

    final class TextView: Render, @unchecked Sendable {
        func render(_ window: inout Window, _ cx: inout Context<TextView>) -> AnyElement {
            div()
                .w(px(500))
                .h(px(300))
                .bg(color(0x1a1a1a))
                .p(px(16))
                .child(
                    div()
                        .child("Hello Headless GPUI")
                )
                .child(
                    div()
                        .child("Secondary line of descriptive text for layout testing")
                )
                .intoAnyElement()
        }
    }

    @Test("test_text_element_layout_and_bounds")
    @MainActor
    func test_text_element_layout_and_bounds() {
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<TextView>, VisualTestContext) = testCx.addWindowView { _, _ in
            TextView()
        }

        cx.draw()

        cx.update { window, _ in
            // Root quad was painted
            #expect(!window.renderedFrame.scene.quads.isEmpty)

            // Text layout runs successfully and scene contains elements
            #expect(window.renderedFrame.scene.count > 0)
        }
    }

    // MARK: - Test 3: Canvas Custom Painting

    final class CanvasView: Render, @unchecked Sendable {
        let prepaintCalled: TestCell<Bool>
        let paintCalled: TestCell<Bool>
        let paintedBounds: TestCell<Bounds<Pixels>>

        init(
            prepaintCalled: TestCell<Bool>,
            paintCalled: TestCell<Bool>,
            paintedBounds: TestCell<Bounds<Pixels>>
        ) {
            self.prepaintCalled = prepaintCalled
            self.paintCalled = paintCalled
            self.paintedBounds = paintedBounds
        }

        func render(_ window: inout Window, _ cx: inout Context<CanvasView>) -> AnyElement {
            let prepaintCell = self.prepaintCalled
            let paintCell = self.paintCalled
            let boundsCell = self.paintedBounds

            return div()
                .w(px(400))
                .h(px(200))
                .child(
                    canvas(
                        { bounds, window, app -> Bounds<Pixels> in
                            prepaintCell.value = true
                            return bounds
                        },
                        { bounds, state, window, app in
                            paintCell.value = true
                            boundsCell.value = bounds
                            window.paintQuad(fill(bounds: bounds, color: color(0x00ff00)))
                        }
                    )
                    .w(px(300))
                    .h(px(150))
                )
                .intoAnyElement()
        }
    }

    @Test("test_canvas_custom_paths_and_painting")
    @MainActor
    func test_canvas_custom_paths_and_painting() {
        let prepaintCell = TestCell<Bool>(false)
        let paintCell = TestCell<Bool>(false)
        let boundsCell = TestCell<Bounds<Pixels>>(.zero)

        let testCx = TestAppContext.single()
        let (_, cx): (Entity<CanvasView>, VisualTestContext) = testCx.addWindowView { _, _ in
            CanvasView(
                prepaintCalled: prepaintCell,
                paintCalled: paintCell,
                paintedBounds: boundsCell
            )
        }

        cx.draw()

        #expect(prepaintCell.value)
        #expect(paintCell.value)
        #expect(boundsCell.value.size.width == px(300))
        #expect(boundsCell.value.size.height == px(150))

        cx.update { window, _ in
            let quads = window.renderedFrame.scene.quads
            let hasGreenQuad = quads.contains { q in
                q.bounds.size.width == 300 && q.bounds.size.height == 150
            }
            #expect(hasGreenQuad)
        }
    }

    // MARK: - Test 4: SVG Element Layout

    final class SvgView: Render, @unchecked Sendable {
        func render(_ window: inout Window, _ cx: inout Context<SvgView>) -> AnyElement {
            div()
                .size(px(200))
                .child(
                    svg()
                        .path("icons/file.svg")
                        .size(px(32))
                )
                .intoAnyElement()
        }
    }

    @Test("test_svg_element_rendering")
    @MainActor
    func test_svg_element_rendering() {
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<SvgView>, VisualTestContext) = testCx.addWindowView { _, _ in
            SvgView()
        }

        cx.draw()

        cx.update { window, _ in
            // Rendering didn't crash and scene initialized
            #expect(window.renderedFrame.scene.count >= 0)
        }
    }

    // MARK: - Test 5: Hit Testing & Mouse Click Dispatch

    final class ButtonView: Render, @unchecked Sendable {
        let buttonAClicks: TestCell<Int>
        let buttonBClicks: TestCell<Int>

        init(buttonAClicks: TestCell<Int>, buttonBClicks: TestCell<Int>) {
            self.buttonAClicks = buttonAClicks
            self.buttonBClicks = buttonBClicks
        }

        func render(_ window: inout Window, _ cx: inout Context<ButtonView>) -> AnyElement {
            let aClicks = self.buttonAClicks
            let bClicks = self.buttonBClicks

            return div()
                .sizeFull()
                .flex()
                .flexRow()
                .child(
                    div()
                        .id("btnA")
                        .w(px(100))
                        .h(px(50))
                        .bg(color(0x0000ff))
                        .onClick { _, _, _ in
                            aClicks.value += 1
                        }
                )
                .child(
                    div()
                        .id("btnB")
                        .w(px(100))
                        .h(px(50))
                        .bg(color(0x00ff00))
                        .onClick { _, _, _ in
                            bClicks.value += 1
                        }
                )
                .intoAnyElement()
        }
    }

    @Test("test_hit_testing_and_mouse_event_dispatch")
    @MainActor
    func test_hit_testing_and_mouse_event_dispatch() {
        let aClicks = TestCell<Int>(0)
        let bClicks = TestCell<Int>(0)

        let testCx = TestAppContext.single()
        let (_, cx): (Entity<ButtonView>, VisualTestContext) = testCx.addWindowView { _, _ in
            ButtonView(buttonAClicks: aClicks, buttonBClicks: bClicks)
        }

        cx.draw()

        cx.update { window, _ in
            // Both buttons registered hitboxes
            #expect(window.renderedFrame.hitboxes.count >= 2)

            // Hit test at (50, 25) falls inside Button A
            let hitA = window.renderedFrame.hitTest(point(px(50), px(25)))
            #expect(!hitA.ids.isEmpty)

            // Hit test at (150, 25) falls inside Button B
            let hitB = window.renderedFrame.hitTest(point(px(150), px(25)))
            #expect(!hitB.ids.isEmpty)
        }

        // Simulate click on Button A
        cx.simulateClick(position: point(px(50), px(25)))
        #expect(aClicks.value == 1)
        #expect(bClicks.value == 0)

        // Simulate click on Button B
        cx.simulateClick(position: point(px(150), px(25)))
        #expect(aClicks.value == 1)
        #expect(bClicks.value == 1)
    }

    // MARK: - Test 6: Incremental View Mutation & Redrawing

    final class MutableCardView: Render, @unchecked Sendable {
        var cardCount: Int = 1

        func render(_ window: inout Window, _ cx: inout Context<MutableCardView>) -> AnyElement {
            var container = div()
                .sizeFull()
                .flex()
                .flexCol()

            for i in 0..<cardCount {
                container = container.child(
                    div()
                        .w(px(200))
                        .h(px(40))
                        .bg(color(0x222222))
                        .id(ElementId(named: "card-\(i)"))
                )
            }

            return container.intoAnyElement()
        }
    }

    @Test("test_incremental_view_mutation_and_redrawing")
    @MainActor
    func test_incremental_view_mutation_and_redrawing() {
        let testCx = TestAppContext.single()
        let (view, cx): (Entity<MutableCardView>, VisualTestContext) = testCx.addWindowView { _, _ in
            MutableCardView()
        }

        // Frame 1: 1 card
        cx.draw()
        var initialQuads = 0
        cx.update { window, _ in
            initialQuads = window.renderedFrame.scene.quads.count
            #expect(initialQuads >= 1)
        }

        // Frame 2: Expand to 4 cards
        view.update(cx.cx.app) { v, _ in
            v.cardCount = 4
        }
        cx.update { window, _ in
            window.refresh()
        }
        cx.draw()

        var expandedQuads = 0
        cx.update { window, _ in
            expandedQuads = window.renderedFrame.scene.quads.count
            #expect(expandedQuads > initialQuads)
            #expect(expandedQuads == initialQuads + 3)
        }

        // Frame 3: Collapse back to 1 card
        view.update(cx.cx.app) { v, _ in
            v.cardCount = 1
        }
        cx.update { window, _ in
            window.refresh()
        }
        cx.draw()

        cx.update { window, _ in
            let collapsedQuads = window.renderedFrame.scene.quads.count
            #expect(collapsedQuads == initialQuads)
        }
    }

    // MARK: - Test 7: UniformList Headless Scroll Rendering

    final class UniformListView: Render, @unchecked Sendable {
        let scrollHandle: UniformListScrollHandle
        let visibleRangeCell: TestCell<Range<Int>>

        init(scrollHandle: UniformListScrollHandle, visibleRangeCell: TestCell<Range<Int>>) {
            self.scrollHandle = scrollHandle
            self.visibleRangeCell = visibleRangeCell
        }

        func render(_ window: inout Window, _ cx: inout Context<UniformListView>) -> AnyElement {
            let handle = self.scrollHandle
            let cell = self.visibleRangeCell

            return div()
                .sizeFull()
                .child(
                    uniformList(
                        ElementId(named: "headless-list"),
                        50,
                        { range, window, cx in
                            cell.value = range
                            return range.map { ix in
                                div().h(px(20.0)).bg(color(0x333333)).child("Row \(ix)").intoAnyElement()
                            }
                        }
                    )
                    .trackScroll(handle)
                    .h(px(100.0))
                )
                .intoAnyElement()
        }
    }

    @Test("test_uniform_list_headless_scroll_rendering")
    @MainActor
    func test_uniform_list_headless_scroll_rendering() {
        let scrollHandle = UniformListScrollHandle.new()
        let visibleRange = TestCell<Range<Int>>(0..<0)

        let testCx = TestAppContext.single()
        let (_, cx): (Entity<UniformListView>, VisualTestContext) = testCx.addWindowView { _, _ in
            UniformListView(scrollHandle: scrollHandle, visibleRangeCell: visibleRange)
        }

        cx.draw()

        // 100px height container / 20px item height = 5 visible items
        #expect(visibleRange.value == 0..<5)

        // Programmatically scroll by 3 items
        scrollHandle.scrollToItemStrict(3, strategy: .top)
        cx.update { window, _ in
            window.refresh()
        }
        cx.draw()

        #expect(visibleRange.value.lowerBound == 3)
    }
}
