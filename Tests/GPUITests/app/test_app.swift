// Tests ported from: crates/gpui/src/app/test_app.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("TestApp Tests")
struct TestAppTests {

    final class Counter: Render, Focusable {
        var count: Int
        let focusHandle: FocusHandle?

        init(window: inout Window, cx: App) {
            self.focusHandle = window.focusHandle()
            self.count = 0
        }

        init(count: Int, focusHandle: FocusHandle? = nil) {
            self.count = count
            self.focusHandle = focusHandle
        }

        func increment() {
            count += 1
        }

        func focusHandle(_ cx: App) -> FocusHandle {
            focusHandle ?? FocusHandle(handles: FocusMap())
        }

        func render(_ window: inout Window, _ cx: inout Context<Counter>) -> AnyElement {
            div().intoAnyElement()
        }
    }

    struct MyGlobal: Global {
        var value: String
    }

    @Test("test_basic_usage")
    @MainActor
    func test_basic_usage() {
        let app = TestApp()
        let window = app.openWindow { window, cx in
            Counter(window: &window, cx: cx)
        }

        window.update { counter, _, _ in
            counter.increment()
        }

        window.read { counter, _ in
            #expect(counter.count == 1)
        }

        app.update { cx in
            cx.shutdown()
        }
    }

    @Test("test_entity_creation")
    @MainActor
    func test_entity_creation() {
        let app = TestApp()

        let entity = app.newEntity { _ in
            Counter(count: 42)
        }

        app.readEntity(entity) { counter, _ in
            #expect(counter.count == 42)
        }

        app.updateEntity(entity) { counter, _ in
            counter.count += 1
        }

        app.readEntity(entity) { counter, _ in
            #expect(counter.count == 43)
        }
    }

    @Test("test_globals")
    @MainActor
    func test_globals() {
        let app = TestApp()

        #expect(!app.hasGlobal(MyGlobal.self))

        app.setGlobal(MyGlobal(value: "hello"))

        #expect(app.hasGlobal(MyGlobal.self))

        app.readGlobal(MyGlobal.self) { global, _ in
            #expect(global.value == "hello")
        }

        app.updateGlobal(MyGlobal.self) { global, _ in
            global.value = "world"
        }

        app.readGlobal(MyGlobal.self) { global, _ in
            #expect(global.value == "world")
        }
    }
}
