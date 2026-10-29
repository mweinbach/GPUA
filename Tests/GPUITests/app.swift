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
}
