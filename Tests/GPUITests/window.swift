// Swift-only: Comprehensive behavioral tests for Window lifecycle, dual-frame model, layout pass, drawing pipeline, and event routing

import Testing
import Foundation
@testable import GPUI

@Suite("Window Lifecycle, Layout, Drawing, and Event Dispatch Tests")
struct WindowTests {

    @Test("Window initialization with default options")
    @MainActor
    func windowInitialization() {
        let window = Window()
        #expect(window.scaleFactor == 1.0)
        #expect(window.viewportSize == size(px(800.0), px(600.0)))
        #expect(window.remSize == px(16.0))
        #expect(window.invalidator.isDirty)
        #expect(window.invalidator.drawPhase == .none)
        #expect(window.invalidator.notDrawing)
        #expect(window.effectiveMouseCursor() == .arrow)
    }

    @Test("Window invalidator phase transitions and dirty tracking")
    @MainActor
    func windowInvalidatorPhases() {
        var app = App()
        let invalidator = WindowInvalidator()
        #expect(invalidator.isDirty)
        #expect(invalidator.notDrawing)

        invalidator.setDirty(false)
        #expect(!invalidator.isDirty)

        let entityId = EntityId(42)
        let didInvalidate = invalidator.invalidateView(entityId, &app)
        #expect(didInvalidate)
        #expect(invalidator.isDirty)

        let taken = invalidator.takeViews()
        #expect(taken.contains(entityId))
        #expect(invalidator.takeViews().isEmpty)

        invalidator.setPhase(.prepaint)
        #expect(invalidator.drawPhase == .prepaint)
        #expect(!invalidator.notDrawing)

        invalidator.setPhase(.paint)
        #expect(invalidator.drawPhase == .paint)

        invalidator.setPhase(.none)
        #expect(invalidator.drawPhase == .none)
        #expect(invalidator.notDrawing)
    }

    @Test("Dual-frame model and draw presentation swap")
    @MainActor
    func dualFrameSwap() {
        var app = App()
        let mockPlatform = DefaultPlatformWindow()
        var window = Window(platformWindow: mockPlatform)

        // Queue next frame callback
        var callbackExecuted = false
        window.onNextFrame { _, _ in
            callbackExecuted = true
        }

        // Insert quad into scene during preparation
        let quad = Quad(
            borderStyle: .solid,
            bounds: Bounds(origin: .zero, size: size(ScaledPixels(100), ScaledPixels(100))),
            contentMask: ContentMask(bounds: Bounds(origin: .zero, size: size(ScaledPixels(800), ScaledPixels(600)))),
            background: solidBackground(hsla(0.5, 0.5, 0.5, 1.0)),
            borderColor: hsla(0, 0, 0, 0),
            cornerRadii: .zero,
            borderWidths: .zero
        )
        window.paintQuad(quad)

        // Insert hitbox
        let hitboxId = window.insertHitbox(
            bounds: Bounds(origin: .zero, size: size(px(100), px(100))),
            behavior: .normal
        )

        #expect(window.invalidator.isDirty)
        #expect(window.renderedFrame.hitboxes.isEmpty)
        #expect(window.nextFrame.hitboxes.count == 1)

        // Execute draw pipeline
        window.draw(cx: &app)

        #expect(callbackExecuted)
        #expect(!window.invalidator.isDirty)
        #expect(window.invalidator.drawPhase == .none)

        // Swapped: renderedFrame now has the hitbox and quad, nextFrame is cleared
        #expect(window.renderedFrame.hitboxes.count == 1)
        #expect(window.renderedFrame.hitboxes[0].id == hitboxId)
        #expect(window.nextFrame.hitboxes.isEmpty)
        #expect(mockPlatform.lastDrawnScene != nil)
    }

    @Test("Hitbox insertion and hit testing across behavioral modes")
    @MainActor
    func hitboxHitTesting() {
        var app = App()
        var window = Window()

        // 1. Normal hitbox covering (0,0)-(200,200)
        let id1 = window.insertHitbox(
            bounds: Bounds(origin: point(px(0), px(0)), size: size(px(200), px(200))),
            behavior: .normal
        )

        // 2. BlockMouse hitbox covering (50,50)-(150,150)
        let id2 = window.insertHitbox(
            bounds: Bounds(origin: point(px(50), px(50)), size: size(px(100), px(100))),
            behavior: .blockMouse
        )

        // 3. BlockMouseExceptScroll hitbox covering (250,250)-(300,300)
        let id3 = window.insertHitbox(
            bounds: Bounds(origin: point(px(250), px(250)), size: size(px(50), px(50))),
            behavior: .blockMouseExceptScroll
        )

        window.draw(cx: &app)

        // Hit test inside id2: id2 is on top and blocks mouse, so id1 is not reached
        let hitAt75 = window.renderedFrame.hitTest(point(px(75), px(75)))
        #expect(hitAt75.ids == [id2])

        // Hit test at (180, 180): inside id1, outside id2
        let hitAt180 = window.renderedFrame.hitTest(point(px(180), px(180)))
        #expect(hitAt180.ids == [id1])

        // Hit test at (275, 275): inside id3 (blockMouseExceptScroll)
        let hitAt275 = window.renderedFrame.hitTest(point(px(275), px(275)))
        #expect(hitAt275.ids == [id3])
        #expect(hitAt275.hoverHitboxCount == 1)

        // Hit test outside all hitboxes
        let hitAt500 = window.renderedFrame.hitTest(point(px(500), px(500)))
        #expect(hitAt500.ids.isEmpty)
    }

    @Test("Focus handle management and circular tab stop navigation")
    @MainActor
    func focusAndTabNavigation() {
        var app = App()
        var window = Window()

        let focus1 = window.focusHandle().tabIndex(0).tabStop(true)
        let focus2 = window.focusHandle().tabIndex(1).tabStop(true)
        let focus3 = window.focusHandle().tabIndex(2).tabStop(true)

        // Register in next frame tab stops
        window.nextFrame.tabStops.insert(focus1)
        window.nextFrame.tabStops.insert(focus2)
        window.nextFrame.tabStops.insert(focus3)

        window.draw(cx: &app)

        #expect(window.focused(app) == nil)

        // Focus first handle
        window.focus(focus1, &app)
        #expect(window.isFocused(focus1))
        #expect(window.focused(app)?.id == focus1.id)

        // Tab next: focus1 -> focus2
        window.focusNext(&app)
        #expect(window.isFocused(focus2))

        // Tab next: focus2 -> focus3
        window.focusNext(&app)
        #expect(window.isFocused(focus3))

        // Tab next wraps circularly: focus3 -> focus1
        window.focusNext(&app)
        #expect(window.isFocused(focus1))

        // Tab prev wraps circularly backwards: focus1 -> focus3
        window.focusPrev(&app)
        #expect(window.isFocused(focus3))

        // Blur removes active focus
        window.blur(&app)
        #expect(window.focused(app) == nil)
        #expect(!window.isFocused(focus3))
    }

    @Test("Content mask, element offset, and opacity stacks")
    @MainActor
    func scopingStacks() {
        var window = Window(viewportSize: size(px(800), px(600)))

        #expect(window.contentMaskStack.count == 1)
        #expect(window.elementOffsetStack == [.zero])
        #expect(window.elementOpacity == 1.0)

        let childMask = ContentMask(bounds: Bounds(origin: point(px(10), px(10)), size: size(px(200), px(200))))
        window.withContentMask(childMask) { win in
            #expect(win.contentMaskStack.count == 2)
            #expect(win.contentMaskStack.last?.bounds == childMask.bounds)

            win.withElementOffset(point(px(50), px(50))) { innerWin in
                #expect(innerWin.elementOffsetStack.last == point(px(50), px(50)))

                innerWin.withOpacity(0.5) { opWin in
                    #expect(opWin.elementOpacity == 0.5)
                }
                #expect(innerWin.elementOpacity == 1.0)
            }
            #expect(win.elementOffsetStack.last == .zero)
        }
        #expect(window.contentMaskStack.count == 1)
    }

    @Test("Taffy layout engine integration within window pass")
    @MainActor
    func layoutPass() {
        var app = App()
        var window = Window()

        let style = Style()
        let layoutId = window.requestLayout(style: style, children: [])

        window.computeLayout(
            id: layoutId,
            availableSpace: size(.definite(px(400)), .definite(px(300))),
            cx: &app
        )

        let bounds = window.layoutBounds(id: layoutId)
        #expect(bounds.size.width >= Pixels.zero)
        #expect(bounds.size.height >= Pixels.zero)
    }

    @Test("Platform event dispatching updates window state")
    @MainActor
    func eventDispatch() {
        var app = App()
        var window = Window()

        _ = window.insertHitbox(
            bounds: Bounds(origin: point(px(0), px(0)), size: size(px(200), px(200))),
            behavior: .normal
        )
        window.draw(cx: &app)

        // Mouse Move Event
        let moveEvent = PlatformInput.mouseMove(MouseMoveEvent(
            position: point(px(100), px(100)),
            modifiers: Modifiers.none()
        ))
        let moveResult = window.dispatchEvent(event: moveEvent, cx: &app)
        #expect(moveResult.propagate)
        #expect(window.mousePosition == point(px(100), px(100)))
        #expect(!window.mouseHitTest.ids.isEmpty)

        // Mouse Down Event
        let downEvent = PlatformInput.mouseDown(MouseDownEvent(
            button: .left,
            position: point(px(50), px(50)),
            modifiers: Modifiers.none(),
            clickCount: 1,
            firstMouse: true
        ))
        let downResult = window.dispatchEvent(event: downEvent, cx: &app)
        #expect(downResult.propagate)
        #expect(window.mousePosition == point(px(50), px(50)))

        // Mouse Exited
        let exitEvent = PlatformInput.mouseExited(MouseExitEvent())
        _ = window.dispatchEvent(event: exitEvent, cx: &app)
        #expect(window.mouseHitTest.ids.isEmpty)
    }

    @Test("Window lifecycle, appearance, and observer callbacks")
    @MainActor
    func windowLifecycleAndObservers() {
        let mock = DefaultPlatformWindow()
        var window = Window(platformWindow: mock)

        var appearanceTriggered = false
        window.observeWindowAppearance { _ in
            appearanceTriggered = true
        }

        var buttonLayoutTriggered = false
        window.observeButtonLayoutChanged {
            buttonLayoutTriggered = true
        }

        window.appearanceChanged(.light)
        #expect(appearanceTriggered)
        #expect(window.invalidator.isDirty)

        window.buttonLayoutChanged()
        #expect(buttonLayoutTriggered)

        // Autoscroll request & take
        let scrollTarget = Bounds(origin: point(px(100), px(100)), size: size(px(50), px(50)))
        window.requestAutoscroll(scrollTarget)
        let taken = window.takeAutoscroll()
        #expect(taken == scrollTarget)
        #expect(window.takeAutoscroll() == nil)

        // Window resize
        window.resize(size(px(1024), px(768)))
        #expect(window.viewportSize == size(px(1024), px(768)))
        #expect(window.innerWindowBounds().size == size(px(1024), px(768)))

        // Window controls
        window.setWindowTitle("GPUA Test")
        #expect(window.windowTitle == "GPUA Test")

        window.setClientInset(px(12.0))
        #expect(window.clientInset() == px(12.0))

        window.toggleFullscreen()
        #expect(mock.isFullscreen())
        window.zoomWindow()
        #expect(mock.isMaximized())
        window.minimizeWindow()
        #expect(mock.isMinimizedState)
    }

    @Test("Element state storage using withElementState and useState")
    @MainActor
    func elementStates() {
        var window = Window()
        let elemId = GlobalElementId(ElementId(101))

        // useState creates state if not present
        let val1: Int = window.useState(elemId) { 42 }
        #expect(val1 == 42)

        // useState returns existing state
        let val2: Int = window.useState(elemId) { 999 }
        #expect(val2 == 42)

        // withElementState modifies state
        window.withElementState(elemId) { (state: inout Int?) in
            state = 100
        }
        let val3: Int? = window.withElementState(elemId) { $0 }
        #expect(val3 == 100)
    }

    final class TestBox<T>: @unchecked Sendable {
        var value: T
        init(_ value: T) { self.value = value }
    }

    @Test("Prompt models and fallback prompt builder")
    @MainActor
    func prompts() {
        var app = App()
        var window = Window()

        let respondedIndex = TestBox<Int?>(nil)
        let handle = PromptHandle.withHandler { index in
            respondedIndex.value = index
        }

        let buttonOk = PromptButton.ok("Accept")
        let buttonCancel = PromptButton.cancel("Dismiss")
        #expect(!buttonOk.isCancel)
        #expect(buttonCancel.isCancel)
        #expect(buttonOk.label == "Accept")

        let renderable = fallbackPromptRenderer(
            level: .info,
            message: "Save changes?",
            detail: "Unsaved work will be lost",
            actions: [buttonOk, buttonCancel],
            handle: handle,
            window: &window,
            cx: &app
        )
        #expect(renderable.view.entityId.rawValue > 0)

        handle.send(1)
        #expect(respondedIndex.value == 1)
    }

    @Test("Styled fluent modifiers apply expected StyleRefinement properties")
    func styledModifiers() {
        struct MockStyledElement: Styled {
            var style: StyleRefinement = StyleRefinement()
        }

        let el = MockStyledElement()
            .flex()
            .flexCol()
            .itemsCenter()
            .justifyBetween()
            .relative()
            .wFull()
            .h16()
            .p4()
            .m2()
            .roundedLg()
            .border1()
            .borderColor(hsla(0.2, 0.4, 0.6, 1.0))
            .shadowMd()
            .cursorPointer()

        #expect(el.style.display == .flex)
        #expect(el.style.flexDirection == .column)
        #expect(el.style.alignItems == .center)
        #expect(el.style.justifyContent == .spaceBetween)
        #expect(el.style.position == .relative)
        #expect(el.style.size.width == .definite(GPUI.relative(1.0)))
        #expect(el.style.size.height == .definite(.rems(GPUI.rems(4.0))))
        #expect(el.style.padding.top == .rems(GPUI.rems(1.0)))
        #expect(el.style.margin.top == .definite(.rems(GPUI.rems(0.5))))
        #expect(el.style.cornerRadii.topLeft == .rems(GPUI.rems(0.5)))
        #expect(el.style.borderWidths.top == .pixels(GPUI.px(1.0)))
        #expect(el.style.borderColor == hsla(0.2, 0.4, 0.6, 1.0))
        #expect(el.style.boxShadow != nil)
        #expect(el.style.mouseCursor == .pointingHand)
    }
}
