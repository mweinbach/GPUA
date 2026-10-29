// Tests ported from: crates/gpui/src/app/test_context.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation
import Testing
@testable import GPUI

@Suite("TestAppContext Tests")
struct TestAppContextTests {

    struct MyGlobal: Global {
        var message: String
    }

    final class SimpleView: Render {
        var title: String

        init(title: String = "Default") {
            self.title = title
        }

        func render(_ window: inout Window, _ cx: inout Context<SimpleView>) -> AnyElement {
            div().child(self.title).intoAnyElement()
        }
    }

    @Test("test_test_app_context_lifecycle")
    @MainActor
    func test_test_app_context_lifecycle() {
        let cx = TestAppContext.build(dispatcher: TestDispatcher.new(seed: 0))
        let textSys = cx.textSystem
        let fontId = textSys.resolveFont(font(".ZedMono"))
        #expect(fontId.value > 0)
    }

    @Test("test_test_app_context_clipboard_and_prompt")
    @MainActor
    func test_test_app_context_clipboard_and_prompt() {
        let cx = TestAppContext.single()
        #expect(!cx.hasPendingPrompt())
        #expect(cx.pendingPrompt() == nil)

        cx.writeToClipboard(ClipboardItem(text: "copied text"))
        let readItem = cx.readFromClipboard()
        #expect(readItem?.text == "copied text")
    }

    @Test("test_test_app_context_globals_and_lifecycle")
    @MainActor
    func test_test_app_context_globals_and_lifecycle() throws {
        let cx = TestAppContext.single()
        var quitFired = false
        cx.onQuit {
            quitFired = true
        }

        #expect(!cx.hasGlobal(MyGlobal.self))
        cx.setGlobal(MyGlobal(message: "hello"))
        #expect(cx.hasGlobal(MyGlobal.self))

        cx.readGlobal(MyGlobal.self) { g, _ in
            #expect(g.message == "hello")
        }

        cx.updateGlobal(MyGlobal.self) { g, _ in
            g.message = "world"
        }

        cx.readGlobal(MyGlobal.self) { g, _ in
            #expect(g.message == "world")
        }

        try cx.refresh()
        cx.quit()
        #expect(quitFired)
    }

    @Test("test_test_app_context_window_view")
    @MainActor
    func test_test_app_context_window_view() {
        let cx = TestAppContext.single()
        let (view, vcx) = cx.addWindowView { _, _ in
            SimpleView(title: "Hello Window")
        }

        vcx.draw()
        view.update(cx.app) { v, _ in
            #expect(v.title == "Hello Window")
            v.title = "Updated Window"
        }

        #expect(view.read(cx.app).title == "Updated Window")
    }
}
