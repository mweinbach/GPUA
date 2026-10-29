// Swift-only: behavioral tests for AppContext protocol implementation

import Testing
@testable import GPUI

@Suite("AppContext Tests")
struct AppContextTests {

    struct State: Sendable, Equatable {
        var count: Int
    }

    struct GlobalConfig: Global, Default, Sendable, Equatable {
        var theme: String

        static func `default`() -> GlobalConfig {
            GlobalConfig(theme: "dark")
        }
    }

    @Test("test_app_context_entity_management")
    @MainActor
    func test_app_context_entity_management() {
        let app = App()

        let entity = app.new { _ in State(count: 10) }
        #expect(entity.read(app).count == 10)

        app.updateEntity(entity) { state, _ in
            state.count = 25
        }
        #expect(entity.read(app).count == 25)
    }

    @Test("test_app_context_reservation_insert")
    @MainActor
    func test_app_context_reservation_insert() {
        let app = App()

        let reservation = app.reserveEntity(State.self)
        let entity = app.insertEntity(reservation) { _ in
            State(count: 99)
        }

        #expect(entity.read(app).count == 99)
    }

    @Test("test_app_context_globals")
    @MainActor
    func test_app_context_globals() {
        let app = App()

        #expect(!app.hasGlobal(GlobalConfig.self))
        app.setGlobal(GlobalConfig(theme: "light"))
        #expect(app.hasGlobal(GlobalConfig.self))

        let config = app.global(GlobalConfig.self)
        #expect(config.theme == "light")

        app.updateGlobal { (cfg: inout GlobalConfig, _) in
            cfg.theme = "high-contrast"
        }
        #expect(app.global(GlobalConfig.self).theme == "high-contrast")
    }
}
