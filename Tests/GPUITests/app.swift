// Tests ported from: crates/gpui/src/app.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("App Tests")
struct AppTests {

    struct MyState: Sendable, Equatable {
        var value: Bool
    }

    struct CounterState: Sendable, Equatable {
        var count: Int
    }

    enum CounterEvent: Sendable, Equatable {
        case incremented(Int)
        case decremented(Int)
    }

    struct EmitterState: EventEmitter, Sendable {
        typealias Event = CounterEvent
        var value: Int
    }

    struct TestConfig: Global, Default, Sendable, Equatable {
        var name: String

        static func `default`() -> TestConfig {
            TestConfig(name: "default_config")
        }
    }

    @Test("test_gpui_borrow")
    @MainActor
    func test_gpui_borrow() {
        let app = App()
        var observationCount = 0

        let state: Entity<MyState> = app.update { cx in
            let state = cx.new { _ in MyState(value: false) }
            cx.observe(state) { _, _ in
                observationCount += 1
                return true
            }.detach()
            return state
        }

        app.update { cx in
            let borrow = state.asMut(cx)
            borrow.value.value = true
        }

        app.update { cx in
            state.write(cx, MyState(value: false))
        }

        #expect(observationCount == 2)
    }

    @Test("test_entity_lifecycle_and_effects")
    @MainActor
    func test_entity_lifecycle_and_effects() {
        let app = App()

        var notifiedCount = 0
        let entity: Entity<CounterState> = app.update { cx in
            let e = cx.new { _ in CounterState(count: 0) }
            cx.observe(e) { _, _ in
                notifiedCount += 1
                return true
            }.detach()
            return e
        }

        // Updating entity updates state and triggers effects
        app.update { cx in
            cx.updateEntity(entity) { state, cx in
                state.count = 42
                cx.notify()
            }
        }

        #expect(notifiedCount == 1)
        #expect(entity.read(app).count == 42)

        // Multiple notifications coalesce during single update
        app.update { cx in
            cx.updateEntity(entity) { state, cx in
                state.count += 1
                cx.notify()
            }
            cx.updateEntity(entity) { state, cx in
                state.count += 1
                cx.notify()
            }
        }

        #expect(notifiedCount == 2)
        #expect(entity.read(app).count == 44)
    }

    @Test("test_event_emitter_and_subscribe")
    @MainActor
    func test_event_emitter_and_subscribe() {
        let app = App()

        var receivedEvents: [CounterEvent] = []
        let entity: Entity<EmitterState> = app.update { cx in
            let e = cx.new { _ in EmitterState(value: 10) }
            cx.subscribe(e) { (_: Entity<EmitterState>, event: CounterEvent, _: App) in
                receivedEvents.append(event)
                return true
            }.detach()
            return e
        }

        app.update { cx in
            cx.updateEntity(entity) { state, cx in
                state.value += 1
                cx.emit(CounterEvent.incremented(state.value))
            }
        }

        #expect(receivedEvents == [.incremented(11)])
    }

    @Test("test_globals_lifecycle")
    @MainActor
    func test_globals_lifecycle() {
        let app = App()

        #expect(!app.hasGlobal(TestConfig.self))

        // Update default global initializes if missing
        var observedCount = 0
        app.observeGlobal(TestConfig.self) { _ in
            observedCount += 1
            return true
        }.detach()

        app.updateDefaultGlobal { (config: inout TestConfig, cx: App) in
            #expect(config.name == "default_config")
            config.name = "custom_config"
        }

        #expect(app.hasGlobal(TestConfig.self))
        #expect(app.global(TestConfig.self).name == "custom_config")
        #expect(observedCount == 1)

        // Reading global
        let readName = app.readGlobal { (config: TestConfig, _) in
            config.name
        }
        #expect(readName == "custom_config")
    }

    struct TestAction: Action, Equatable {
        static var name: String { "test::TestAction" }
        static var deprecatedAliases: [String] { [] }
        static var deprecationMessage: String? { nil }
        static var documentation: String? { nil }
        static func build(json: [String: Any]) throws -> any Action { TestAction() }
        var name: String { Self.name }
        func isEqual(to other: any Action) -> Bool {
            guard let other = other as? TestAction else { return false }
            return self == other
        }
    }

    @Test("test_system_window_tab_controller")
    @MainActor
    func test_system_window_tab_controller() {
        let app = App()
        SystemWindowTabController.`init`(app)

        let handle1 = AnyWindowHandle(id: 1)
        let handle2 = AnyWindowHandle(id: 2)

        let tab1 = SystemWindowTab.new(title: SharedString("Tab 1"), handle: handle1)
        let tab2 = SystemWindowTab.new(title: SharedString("Tab 2"), handle: handle2)

        SystemWindowTabController.addTab(app, handle1.windowId(), [tab1, tab2])

        let tabs = SystemWindowTabController.removeTab(app, handle2.windowId())
        #expect(tabs?.id == handle2.windowId())

        SystemWindowTabController.updateTabTitle(app, handle1.windowId(), SharedString("Updated Tab 1"))
        let controller = app.global(SystemWindowTabController.self)
        let groupTabs = controller.tabs(handle1.windowId())
        #expect(groupTabs?.first?.title == SharedString("Updated Tab 1"))
    }

    @Test("test_application_builder")
    @MainActor
    func test_application_builder() {
        let platform = DefaultPlatform()
        let application = Application.withPlatform(platform)
            .withQuitMode(.explicit)

        var launched = false
        application.run { app in
            launched = true
            #expect(app.quitMode == .explicit)
        }
        #expect(launched)
    }

    @Test("test_app_actions_and_keymap")
    @MainActor
    func test_app_actions_and_keymap() {
        let app = App()

        var actionDispatched = false
        _ = app.onAction { (action: TestAction, _) in
            actionDispatched = true
        }

        #expect(app.isActionAvailable(TestAction()))
        app.dispatchGlobalAction(TestAction())
        #expect(actionDispatched)

        let keymap = app.keyBindings()
        #expect(keymap.allBindingsForInput([]).isEmpty)
    }

    @Test("test_app_clipboard_and_platform")
    @MainActor
    func test_app_clipboard_and_platform() {
        let app = App()

        let item = ClipboardItem(text: "Hello GPUI")
        app.writeToClipboard(item)
        #expect(app.readFromClipboard()?.text == "Hello GPUI")

        #expect(!app.displays().isEmpty)
        #expect(app.primaryDisplay() != nil)
    }
}
