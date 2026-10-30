// Tests ported from: crates/gpui/tests/action_macros.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Action Macros Tests")
struct ActionMacrosTests {
    struct SomeAction: Action, Equatable {
        static let name = "test_only::SomeAction"
        static func build(json: [String: Any]) throws -> any Action { SomeAction() }
        func isEqual(to other: any Action) -> Bool {
            (other as? SomeAction) == self
        }
    }

    /// Documented action
    struct SomeActionWithDocs: Action, Equatable {
        static let name = "test_only::SomeActionWithDocs"
        static var documentation: String? { "Documented action" }
        static func build(json: [String: Any]) throws -> any Action { SomeActionWithDocs() }
        func isEqual(to other: any Action) -> Bool {
            (other as? SomeActionWithDocs) == self
        }
    }

    struct AnotherAction: Action, Equatable {
        static let name = "test_only::AnotherAction"
        static func build(json: [String: Any]) throws -> any Action { AnotherAction() }
        func isEqual(to other: any Action) -> Bool {
            (other as? AnotherAction) == self
        }
    }

    @Test func test_action_macros() {
        let a1 = SomeAction()
        let a2 = SomeActionWithDocs()
        let a3 = AnotherAction()

        #expect(a1.name == "test_only::SomeAction")
        #expect(a2.name == "test_only::SomeActionWithDocs")
        #expect(SomeActionWithDocs.documentation == "Documented action")
        #expect(a3.name == "test_only::AnotherAction")

        #expect(a1.isEqual(to: a1.boxedClone()))
        #expect(!a1.isEqual(to: a3))
    }
}
