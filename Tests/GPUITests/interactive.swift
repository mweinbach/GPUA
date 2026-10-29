// Tests ported from: crates/gpui/src/interactive.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

private struct TestAction: UnitAction {
    static let name = "test_only::TestAction"
    init() {}
}

private final class TestViewState: @unchecked Sendable {
    var sawKeyDown = false
    var sawAction = false
    var focusHandle: FocusHandle?
}

private struct TestView: Render {
    let state: TestViewState

    mutating func render(_ window: inout Window, _ cx: inout Context<TestView>) -> AnyElement {
        let st = state
        let focusHandle = st.focusHandle ?? window.focusHandle()
        st.focusHandle = focusHandle

        let parentContext = (try? KeyContext.parse("parent")) ?? KeyContext()
        let nestedContext = (try? KeyContext.parse("nested")) ?? KeyContext()

        return Div()
            .id(ElementId(named: "testview"))
            .child(
                Div()
                    .keyContext(parentContext)
                    .onKeyDown { event, window, app in
                        window.stopPropagation()
                        st.sawKeyDown = true
                    }
                    .onAction { (_: TestAction, window, app) in
                        st.sawAction = true
                    }
                    .child(
                        Div()
                            .keyContext(nestedContext)
                            .trackFocus(focusHandle)
                    )
            )
            .intoAnyElement()
    }
}

@Suite("Interactive Tests")
struct InteractiveTests {
    @Test("test_on_events")
    @MainActor
    func test_on_events() throws {
        let testCx = TestAppContext.single()
        let state = TestViewState()

        let (_, cx): (Entity<TestView>, VisualTestContext) = testCx.addWindowView { window, viewCx in
            TestView(state: state)
        }

        testCx.app.bindKeys([
            KeyBinding(keystrokes: "ctrl-g", action: TestAction(), context: "parent")
        ])

        cx.draw()

        if let fh = state.focusHandle {
            cx.update { window, app in
                var app = app
                window.focus(fh, &app)
            }
        }

        cx.draw()

        let aKeystroke = try Keystroke.parse("a")
        let ctrlGKeystroke = try Keystroke.parse("ctrl-g")

        _ = testCx.dispatchKeystroke(cx.window, aKeystroke)
        _ = testCx.dispatchKeystroke(cx.window, ctrlGKeystroke)

        #expect(state.sawKeyDown || state.sawAction)
        #expect(state.sawKeyDown)
        #expect(state.sawAction)
    }

    @Test("test_interactive_event_types_and_helpers")
    func test_interactive_event_types_and_helpers() {
        let down = MouseDownEvent(button: .left, position: Point(x: px(10), y: px(20)), modifiers: Modifiers.none(), clickCount: 1)
        let up = MouseUpEvent(button: .left, position: Point(x: px(10), y: px(20)), modifiers: Modifiers.none(), clickCount: 1)
        let click = ClickEvent.mouse(MouseClickEvent(down: down, up: up))

        #expect(click.position == Point(x: px(10), y: px(20)))
        #expect(click.standardClick)
        #expect(!click.isRightClick)
        #expect(!click.isMiddleClick)
        #expect(!click.isKeyboard)

        let scroll1 = ScrollDelta.pixels(Point(x: px(5), y: px(10)))
        let scroll2 = ScrollDelta.pixels(Point(x: px(15), y: px(20)))
        let coalesced = scroll1.coalesce(scroll2)
        #expect(coalesced == .pixels(Point(x: px(20), y: px(30))))
    }
}
