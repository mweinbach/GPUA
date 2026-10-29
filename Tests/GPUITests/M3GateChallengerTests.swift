// Swift-only: Milestone 3 Gate Challenger empirical stress test harness

import Foundation
import Testing
@testable import GPUI

// MARK: - Test Recording Cell

final class EventLogCell: @unchecked Sendable {
    var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func clear() {
        events.removeAll()
    }
}

// MARK: - Helper

private func color(_ hex: UInt32) -> Hsla {
    Hsla(rgba: rgb(hex))
}

// MARK: - Suite 0: Critical Bug Reproductions

@Suite("Challenger Suite 0: Critical Bug Reproductions")
struct CriticalBugReproductionTests {

    @Test("test_stateful_div_child_causes_stack_overflow_crash")
    @MainActor
    func testStatefulDivChildStackOverflow() {
        // Calling .child() on Stateful<Div> (created by .id(...)) triggers infinite recursion in ParentElement.extend
        let parent = div().id("parent")
        _ = parent.child(div())
    }
}

// MARK: - Suite 1: Deep Element Nesting Stress

@Suite("Challenger Suite 1: Deep Element Nesting Lifecycle Stress")
struct DeepNestingStressTests {

    final class DeepNestingView: Render, @unchecked Sendable {
        let depth: Int
        let paddingPerLevel: Float

        init(depth: Int, paddingPerLevel: Float = 1.0) {
            self.depth = depth
            self.paddingPerLevel = paddingPerLevel
        }

        func render(_ window: inout Window, _ cx: inout Context<DeepNestingView>) -> AnyElement {
            var current: AnyElement = div()
                .id(ElementId(named: "leaf"))
                .w(px(50))
                .h(px(50))
                .bg(color(0xff0000))
                .intoAnyElement()

            for i in (0..<depth).reversed() {
                current = div()
                    .p(px(paddingPerLevel))
                    .bg(color(0x000000 | UInt32(i % 256)))
                    .child(current)
                    .intoAnyElement()
            }

            return current
        }
    }

    @Test("test_deeply_nested_100_divs_layout_bounds_and_quad_counts")
    @MainActor
    func testDeeplyNested100Divs() {
        let depth = 100
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<DeepNestingView>, VisualTestContext) = testCx.addWindowView { _, _ in
            DeepNestingView(depth: depth, paddingPerLevel: 1.0)
        }

        // Draw the window (Layout -> Prepaint -> Paint)
        cx.draw()

        cx.update { window, _ in
            let quads = window.renderedFrame.scene.quads

            // At depth 100, each level has a background quad plus the leaf (101 quads total)
            #expect(quads.count >= depth + 1)

            // The leaf quad bounds should be exactly offset by (100, 100) due to 1px padding per level
            let leafQuad = quads.last
            #expect(leafQuad != nil)
            if let leafQuad {
                #expect(leafQuad.bounds.origin.x.value == 100)
                #expect(leafQuad.bounds.origin.y.value == 100)
                #expect(leafQuad.bounds.size.width.value == 50)
                #expect(leafQuad.bounds.size.height.value == 50)
            }
        }
    }

    @Test("test_deeply_nested_200_divs_recursion_stability")
    @MainActor
    func testDeeplyNested200DivsRecursionStability() {
        let depth = 200
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<DeepNestingView>, VisualTestContext) = testCx.addWindowView { _, _ in
            DeepNestingView(depth: depth, paddingPerLevel: 0.5)
        }

        // Must survive layout, prepaint, and paint without recursion overflow
        cx.draw()

        cx.update { window, _ in
            let quads = window.renderedFrame.scene.quads
            #expect(quads.count >= depth + 1)

            let leafQuad = quads.last
            #expect(leafQuad != nil)
            if let leafQuad {
                // 200 levels with 0.5px padding snaps to 200px integer layout
                #expect(leafQuad.bounds.origin.x.value == 200)
                #expect(leafQuad.bounds.origin.y.value == 200)
                #expect(leafQuad.bounds.size.width.value == 50)
                #expect(leafQuad.bounds.size.height.value == 50)
            }
        }
    }
}

// MARK: - Suite 2: Hitbox Hit-Testing Boundary & Precision Stress

@Suite("Challenger Suite 2: Hitbox Hit-Testing Boundary and Precision Stress")
struct HitboxHitTestingStressTests {

    final class BoundaryTestView: Render, @unchecked Sendable {
        func render(_ window: inout Window, _ cx: inout Context<BoundaryTestView>) -> AnyElement {
            // Box A: origin=(100, 100), size=(100, 100) -> [100, 200) x [100, 200)
            // Box B: origin=(200, 100), size=(100, 100) -> [200, 300) x [100, 200)
            let boxA = div()
                .id("boxA")
                .w(px(100))
                .h(px(100))
                .bg(color(0x0000ff))
                .onClick { _, _, _ in }

            let boxB = div()
                .id("boxB")
                .w(px(100))
                .h(px(100))
                .bg(color(0x00ff00))
                .onClick { _, _, _ in }

            return div()
                .sizeFull()
                .p(px(100))
                .flex()
                .flexRow()
                .child(boxA)
                .child(boxB)
                .intoAnyElement()
        }
    }

    @Test("test_half_open_boundary_precision_and_abutting_boxes")
    @MainActor
    func testHalfOpenBoundaryPrecisionAndAbuttingBoxes() {
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<BoundaryTestView>, VisualTestContext) = testCx.addWindowView { _, _ in
            BoundaryTestView()
        }

        cx.draw()

        cx.update { window, _ in
            let frame = window.renderedFrame
            #expect(frame.hitboxes.count >= 2)

            let hitboxes = frame.hitboxes
            guard let hbA = hitboxes.first(where: { $0.bounds.origin.x == px(100) }),
                  let hbB = hitboxes.first(where: { $0.bounds.origin.x == px(200) }) else {
                Issue.record("Hitboxes A and B not found")
                return
            }

            // Top-left corner of Box A: (100.0, 100.0) -> MUST be contained in Box A
            let hitTopLeft = frame.hitTest(point(px(100.0), px(100.0)))
            #expect(hitTopLeft.ids.contains(hbA.id))
            #expect(!hitTopLeft.ids.contains(hbB.id))

            // Subpixel just outside top-left of Box A: (99.99, 100.0) -> MISS
            let hitOutsideLeft = frame.hitTest(point(px(99.99), px(100.0)))
            #expect(!hitOutsideLeft.ids.contains(hbA.id))

            let hitOutsideTop = frame.hitTest(point(px(100.0), px(99.99)))
            #expect(!hitOutsideTop.ids.contains(hbA.id))

            // Boundary between Box A and Box B: x = 200.0
            // Since interval is [origin, origin + size), x=200.0 is OUTSIDE Box A and INSIDE Box B!
            let hitBoundary = frame.hitTest(point(px(200.0), px(150.0)))
            #expect(!hitBoundary.ids.contains(hbA.id), "x=200 must not be in Box A (half-open [100, 200))")
            #expect(hitBoundary.ids.contains(hbB.id), "x=200 must be inside Box B ([200, 300))")

            // Subpixel just inside Box A at x = 199.99
            let hitJustInsideA = frame.hitTest(point(px(199.99), px(150.0)))
            #expect(hitJustInsideA.ids.contains(hbA.id), "x=199.99 must be inside Box A")
            #expect(!hitJustInsideA.ids.contains(hbB.id), "x=199.99 must not be inside Box B")

            // Bottom-right corner of Box B: x=300.0, y=200.0 -> OUTSIDE Box B
            let hitBottomRightB = frame.hitTest(point(px(300.0), px(200.0)))
            #expect(!hitBottomRightB.ids.contains(hbB.id), "Corner (300, 200) must be outside Box B")

            // Just inside bottom-right corner of Box B: (299.99, 199.99) -> INSIDE Box B
            let hitInsideB = frame.hitTest(point(px(299.99), px(199.99)))
            #expect(hitInsideB.ids.contains(hbB.id), "Point (299.99, 199.99) must be inside Box B")
        }
    }

    final class OcclusionTestView: Render, @unchecked Sendable {
        let behavior: HitboxBehavior

        init(behavior: HitboxBehavior) {
            self.behavior = behavior
        }

        func render(_ window: inout Window, _ cx: inout Context<OcclusionTestView>) -> AnyElement {
            let overlayBehavior = self.behavior
            var topDiv = div()
                .id("topLayer")
                .absolute()
                .left(Length.pixels(px(50)))
                .top(Length.pixels(px(50)))
                .size(px(100))
                .bg(color(0x999999))
                .onClick { _, _, _ in }

            if overlayBehavior == .blockMouse {
                topDiv = topDiv.occludeMouse()
            } else if overlayBehavior == .blockMouseExceptScroll {
                topDiv.interactivity.hitboxBehavior = .blockMouseExceptScroll
            }

            let bottomDiv = div()
                .id("bottomLayer")
                .absolute()
                .left(Length.pixels(px(0)))
                .top(Length.pixels(px(0)))
                .size(px(200))
                .bg(color(0x111111))
                .onClick { _, _, _ in }

            return div()
                .sizeFull()
                .child(bottomDiv)
                .child(topDiv)
                .intoAnyElement()
        }
    }

    @Test("test_hitbox_occlusion_and_scroll_pass_through")
    @MainActor
    func testHitboxOcclusionAndScrollPassThrough() {
        // Case 1: .blockMouse blocks hit testing completely for bottom layer
        do {
            let testCx = TestAppContext.single()
            let (_, cx): (Entity<OcclusionTestView>, VisualTestContext) = testCx.addWindowView { _, _ in
                OcclusionTestView(behavior: .blockMouse)
            }
            cx.draw()

            cx.update { window, _ in
                let frame = window.renderedFrame
                let bottomHb = frame.hitboxes.first(where: { $0.bounds.size.width == px(200) })!
                let topHb = frame.hitboxes.first(where: { $0.bounds.size.width == px(100) })!

                // Hit test at center of overlap (75, 75)
                let hit = frame.hitTest(point(px(75), px(75)))
                #expect(hit.ids.contains(topHb.id))
                #expect(!hit.ids.contains(bottomHb.id), "blockMouse must block underlying hitboxes from hitTest")
            }
        }

        // Case 2: .blockMouseExceptScroll allows underlying hitboxes to receive scroll events
        do {
            let testCx = TestAppContext.single()
            let (_, cx): (Entity<OcclusionTestView>, VisualTestContext) = testCx.addWindowView { _, _ in
                OcclusionTestView(behavior: .blockMouseExceptScroll)
            }
            cx.draw()

            cx.update { window, _ in
                let frame = window.renderedFrame
                let bottomHb = frame.hitboxes.first(where: { $0.bounds.size.width == px(200) })!
                let topHb = frame.hitboxes.first(where: { $0.bounds.size.width == px(100) })!

                let hit = frame.hitTest(point(px(75), px(75)))
                // Top hitbox is front
                #expect(hit.ids.first == topHb.id)
                // Bottom hitbox is in hit.ids (for scroll)
                #expect(hit.ids.contains(bottomHb.id))
                // But hoverHitboxCount only includes top hitbox!
                #expect(hit.hoverHitboxCount == 1)

                // Verify hovered status: top is hovered, bottom is NOT hovered
                var win = window
                win.mouseHitTest = hit
                #expect(topHb.isHovered(win))
                #expect(!bottomHb.isHovered(win), "bottomHb must not be hovered under blockMouseExceptScroll")

                // Verify scroll status: bottom CAN handle scroll
                #expect(bottomHb.shouldHandleScroll(win), "bottomHb should handle scroll under blockMouseExceptScroll")
            }
        }
    }

    final class ContentMaskHitTestView: Render, @unchecked Sendable {
        func render(_ window: inout Window, _ cx: inout Context<ContentMaskHitTestView>) -> AnyElement {
            // Parent: bounds (50, 50, 100, 100), overflowHidden
            // Child: bounds (50, 50, 300, 300) inside parent, with click listener
            div()
                .sizeFull()
                .child(
                    div()
                        .absolute()
                        .left(Length.pixels(px(50)))
                        .top(Length.pixels(px(50)))
                        .size(px(100))
                        .overflowHidden()
                        .child(
                            div()
                                .id("clippedChild")
                                .size(px(300))
                                .onClick { _, _, _ in }
                        )
                )
                .intoAnyElement()
        }
    }

    @Test("test_content_mask_clipping_in_hit_testing")
    @MainActor
    func testContentMaskClippingInHitTesting() {
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<ContentMaskHitTestView>, VisualTestContext) = testCx.addWindowView { _, _ in
            ContentMaskHitTestView()
        }
        cx.draw()

        cx.update { window, _ in
            let frame = window.renderedFrame
            guard let childHb = frame.hitboxes.first(where: { $0.bounds.size.width == px(300) }) else {
                Issue.record("Child hitbox not found")
                return
            }

            // Hit test at (75, 75) is inside the content mask (50..150) -> MUST hit childHb
            let hitInsideMask = frame.hitTest(point(px(75), px(75)))
            #expect(hitInsideMask.ids.contains(childHb.id), "Point inside content mask should hit child")

            // Hit test at (200, 200) is inside child's unclipped bounds (50..350) but OUTSIDE content mask (50..150) -> MUST NOT hit childHb
            let hitOutsideMask = frame.hitTest(point(px(200), px(200)))
            #expect(!hitOutsideMask.ids.contains(childHb.id), "Point outside content mask must NOT hit child")
        }
    }
}

// MARK: - Suite 3: Event Propagation Stress (Capture, Bubble, Stoppage)

@Suite("Challenger Suite 3: Event Propagation Phased Dispatch and Stoppage Stress")
struct EventPropagationStressTests {

    final class NestedPropagationView: Render, @unchecked Sendable {
        let logCell: EventLogCell
        let stopInCapture: Bool
        let stopInBubble: Bool
        let useAppStopPropagation: Bool

        init(
            logCell: EventLogCell,
            stopInCapture: Bool = false,
            stopInBubble: Bool = false,
            useAppStopPropagation: Bool = false
        ) {
            self.logCell = logCell
            self.stopInCapture = stopInCapture
            self.stopInBubble = stopInBubble
            self.useAppStopPropagation = useAppStopPropagation
        }

        func render(_ window: inout Window, _ cx: inout Context<NestedPropagationView>) -> AnyElement {
            let log = self.logCell
            let stopCap = self.stopInCapture
            let stopBub = self.stopInBubble
            let useAppStop = self.useAppStopPropagation

            let childDiv = div()
                .size(px(200))
                .captureAnyMouseDown { _, _, _ in
                    log.append("child_capture")
                }
                .onMouseDown(.left) { _, window, app in
                    log.append("child_bubble")
                    if stopBub {
                        if useAppStop {
                            MainActor.assumeIsolated {
                                app.stopPropagation()
                            }
                        } else {
                            window.stopPropagation()
                        }
                    }
                }
                .id("child")

            let parentDiv = div()
                .size(px(400))
                .captureAnyMouseDown { _, window, app in
                    log.append("parent_capture")
                    if stopCap {
                        if useAppStop {
                            MainActor.assumeIsolated {
                                app.stopPropagation()
                            }
                        } else {
                            window.stopPropagation()
                        }
                    }
                }
                .onMouseDown(.left) { _, _, _ in
                    log.append("parent_bubble")
                }
                .child(childDiv)
                .id("parent")

            return div()
                .sizeFull()
                .captureAnyMouseDown { _, _, _ in
                    log.append("grandparent_capture")
                }
                .onMouseDown(.left) { _, _, _ in
                    log.append("grandparent_bubble")
                }
                .child(parentDiv)
                .id("grandparent")
                .intoAnyElement()
        }
    }

    @Test("test_capture_and_bubble_exact_sequence")
    @MainActor
    func testCaptureAndBubbleExactSequence() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<NestedPropagationView>, VisualTestContext) = testCx.addWindowView { _, _ in
            NestedPropagationView(logCell: log)
        }

        cx.draw()

        // Simulate click at (50, 50) which hits child, parent, and grandparent
        cx.simulateMouseDown(position: point(px(50), px(50)))

        #expect(log.events == [
            "grandparent_capture",
            "parent_capture",
            "child_capture",
            "child_bubble",
            "parent_bubble",
            "grandparent_bubble"
        ])
    }

    @Test("test_window_stop_propagation_in_capture_phase")
    @MainActor
    func testWindowStopPropagationInCapturePhase() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<NestedPropagationView>, VisualTestContext) = testCx.addWindowView { _, _ in
            NestedPropagationView(logCell: log, stopInCapture: true, useAppStopPropagation: false)
        }

        cx.draw()
        cx.simulateMouseDown(position: point(px(50), px(50)))

        // Since parent stopped propagation during capture:
        // grandparent_capture ran, parent_capture ran and stopped.
        // child_capture, child_bubble, parent_bubble, grandparent_bubble must NOT run!
        #expect(log.events == [
            "grandparent_capture",
            "parent_capture"
        ])
    }

    @Test("test_window_stop_propagation_in_bubble_phase")
    @MainActor
    func testWindowStopPropagationInBubblePhase() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<NestedPropagationView>, VisualTestContext) = testCx.addWindowView { _, _ in
            NestedPropagationView(logCell: log, stopInBubble: true, useAppStopPropagation: false)
        }

        cx.draw()
        cx.simulateMouseDown(position: point(px(50), px(50)))

        // All captures run, child_bubble runs and stops propagation.
        // parent_bubble and grandparent_bubble must NOT run!
        #expect(log.events == [
            "grandparent_capture",
            "parent_capture",
            "child_capture",
            "child_bubble"
        ])
    }

    @Test("test_app_stop_propagation_parity")
    @MainActor
    func testAppStopPropagationParity() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<NestedPropagationView>, VisualTestContext) = testCx.addWindowView { _, _ in
            NestedPropagationView(logCell: log, stopInBubble: true, useAppStopPropagation: true)
        }

        cx.draw()
        cx.simulateMouseDown(position: point(px(50), px(50)))

        // Challenger check: Does calling app.stopPropagation() stop event propagation?
        // Note: In upstream GPUI, propagation is controlled by cx.propagate_event.
        #expect(log.events == [
            "grandparent_capture",
            "parent_capture",
            "child_capture",
            "child_bubble"
        ])
    }
}

// MARK: - Suite 4: Dynamic View Tree Mutation Stress

@Suite("Challenger Suite 4: Dynamic View Tree Mutation Stress")
struct DynamicMutationStressTests {

    final class RapidMutationView: Render, @unchecked Sendable {
        var items: [Int] = []

        func render(_ window: inout Window, _ cx: inout Context<RapidMutationView>) -> AnyElement {
            var container = div()
                .sizeFull()
                .flex()
                .flexCol()

            for item in items {
                container = container.child(
                    div()
                        .id(ElementId(named: "item-\(item)"))
                        .w(px(200))
                        .h(px(20))
                        .bg(color(0x222222 | UInt32(item * 17 % 0xffffff)))
                        .onClick { _, _, _ in }
                )
            }

            return container.intoAnyElement()
        }
    }

    @Test("test_rapid_50_mutation_cycles_zero_memory_leak_or_ghost_hitboxes")
    @MainActor
    func testRapid50MutationCycles() {
        let testCx = TestAppContext.single()
        let (view, cx): (Entity<RapidMutationView>, VisualTestContext) = testCx.addWindowView { _, _ in
            RapidMutationView()
        }

        let sizes = [0, 5, 20, 50, 10, 0, 35, 1, 100, 0]

        for cycle in 0..<50 {
            let targetCount = sizes[cycle % sizes.count]
            view.update(cx.cx.app) { v, _ in
                v.items = Array(0..<targetCount)
            }
            cx.update { window, _ in
                window.refresh()
            }
            cx.draw()

            cx.update { window, _ in
                let frame = window.renderedFrame
                // Exactly targetCount hitboxes should exist in this frame (no accumulation from prior frames)
                #expect(frame.hitboxes.count == targetCount, "Cycle \(cycle): hitboxes count should be \(targetCount)")
                #expect(frame.scene.quads.count >= targetCount, "Cycle \(cycle): scene quads should match targetCount")
            }
        }
    }
}

// MARK: - Suite 5: Mouse Interaction, Drag Threshold & Scroll Dispatch Stress

@Suite("Challenger Suite 5: Mouse Interaction, Drag Threshold and Scroll Dispatch Stress")
struct MouseInteractionStressTests {

    final class InteractionView: Render, @unchecked Sendable {
        let logCell: EventLogCell

        init(logCell: EventLogCell) {
            self.logCell = logCell
        }

        func render(_ window: inout Window, _ cx: inout Context<InteractionView>) -> AnyElement {
            let log = self.logCell

            return div()
                .sizeFull()
                .child(
                    div()
                        .id("targetBox")
                        .absolute()
                        .left(Length.pixels(px(50)))
                        .top(Length.pixels(px(50)))
                        .size(px(100))
                        .bg(color(0x333333))
                        .onClick { _, _, _ in
                            log.append("click")
                        }
                        .onScrollWheel { event, _, _ in
                            log.append("scroll_y_\(Int(event.delta.pixelDelta(lineHeight: px(1)).y.value))")
                        }
                        .onHover { isHovered, _, _ in
                            log.append(isHovered ? "hover_enter" : "hover_exit")
                        }
                )
                .intoAnyElement()
        }
    }

    @Test("test_mouse_down_and_up_outside_does_not_trigger_click")
    @MainActor
    func testMouseDownAndUpOutsideDoesNotTriggerClick() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<InteractionView>, VisualTestContext) = testCx.addWindowView { _, _ in
            InteractionView(logCell: log)
        }

        cx.draw()

        // 1. Mouse down inside targetBox at (75, 75)
        cx.simulateMouseDown(position: point(px(75), px(75)))
        // 2. Mouse up OUTSIDE targetBox at (200, 200)
        cx.simulateMouseUp(position: point(px(200), px(200)))

        // Click must NOT have fired because mouseUp was outside targetBox!
        #expect(!log.events.contains("click"))
    }

    @Test("test_click_fires_when_down_and_up_inside_bounds")
    @MainActor
    func testClickFiresWhenDownAndUpInsideBounds() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<InteractionView>, VisualTestContext) = testCx.addWindowView { _, _ in
            InteractionView(logCell: log)
        }

        cx.draw()

        // Click inside (75, 75)
        cx.simulateClick(position: point(px(75), px(75)))

        #expect(log.events.contains("click"))
    }

    @Test("test_scroll_wheel_event_dispatch_to_hitbox")
    @MainActor
    func testScrollWheelEventDispatchToHitbox() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<InteractionView>, VisualTestContext) = testCx.addWindowView { _, _ in
            InteractionView(logCell: log)
        }

        cx.draw()

        // Scroll inside targetBox at (75, 75)
        cx.simulateScroll(position: point(px(75), px(75)), delta: point(px(0), px(-20)))
        #expect(log.events.contains("scroll_y_-20"))

        // Scroll outside targetBox at (200, 200)
        log.clear()
        cx.simulateScroll(position: point(px(200), px(200)), delta: point(px(0), px(-20)))
        #expect(log.events.isEmpty, "Scroll outside target box must not trigger scroll handler")
    }

    @Test("test_hover_enter_and_exit_transitions")
    @MainActor
    func testHoverEnterAndExitTransitions() {
        let log = EventLogCell()
        let testCx = TestAppContext.single()
        let (_, cx): (Entity<InteractionView>, VisualTestContext) = testCx.addWindowView { _, _ in
            InteractionView(logCell: log)
        }

        cx.draw()

        // Move inside (75, 75)
        cx.simulateMouseMove(position: point(px(75), px(75)))
        #expect(log.events.contains("hover_enter"))

        // Move outside (250, 250)
        cx.simulateMouseMove(position: point(px(250), px(250)))
        #expect(log.events.contains("hover_exit"))
    }
}
