// Swift-only: Behavioral and unit tests for Action, UnitAction, and ActionRegistry

import Foundation
import Testing
@testable import GPUI

struct TestMoveUp: UnitAction {
    static let name = "editor::MoveUp"
    init() {}
}

struct TestMoveDown: UnitAction {
    static let name = "editor::MoveDown"
    static let deprecatedAliases = ["editor::Down", "editor::MoveCursorDown"]
    static let deprecationMessage: String? = "Use editor::MoveDown instead"
    static let documentation: String? = "Move the cursor down by one row"
    init() {}
}

struct TestSelectNext: Action, Equatable {
    static let name = "editor::SelectNext"
    var replaceNewest: Bool

    init(replaceNewest: Bool) {
        self.replaceNewest = replaceNewest
    }

    static func build(json: [String: Any]) throws -> any Action {
        guard let replaceNewest = json["replace_newest"] as? Bool ?? json["replaceNewest"] as? Bool else {
            throw ActionBuildError.buildError(
                name: name,
                error: NSError(domain: "GPUI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing replace_newest"])
            )
        }
        return TestSelectNext(replaceNewest: replaceNewest)
    }
}

@Suite("ActionSystemTests")
struct ActionSystemTests {
    @Test("UnitAction build and equality")
    func testUnitAction() throws {
        let action1 = TestMoveUp()
        let action2 = try TestMoveUp.build(json: [:])

        #expect(action1.name == "editor::MoveUp")
        #expect(action1.isEqual(to: action2))
        #expect(action1.partial_eq(action2))

        let moveDown = TestMoveDown()
        #expect(!action1.isEqual(to: moveDown))
    }

    @Test("Parametric Action build and equality")
    func testParametricAction() throws {
        let action1 = TestSelectNext(replaceNewest: true)
        let built = try TestSelectNext.build(json: ["replace_newest": true])

        #expect(action1.isEqual(to: built))

        let action2 = TestSelectNext(replaceNewest: false)
        #expect(!action1.isEqual(to: action2))

        #expect(throws: ActionBuildError.self) {
            _ = try TestSelectNext.build(json: [:])
        }
    }

    @Test("ActionRegistry registration and build")
    func testActionRegistry() throws {
        let registry = ActionRegistry()
        registry.register(TestMoveUp.self)
        registry.register(TestMoveDown.self)
        registry.register(TestSelectNext.self)

        let action = try registry.buildAction(name: "editor::MoveUp")
        #expect(action is TestMoveUp)

        let aliasAction = try registry.buildAction(name: "editor::Down")
        #expect(aliasAction is TestMoveDown)

        let parametric = try registry.buildAction(
            name: "editor::SelectNext",
            params: ["replace_newest": true]
        )
        guard let selectNext = parametric as? TestSelectNext else {
            Issue.record("Expected TestSelectNext")
            return
        }
        #expect(selectNext.replaceNewest == true)

        let byType = try registry.buildActionType(ObjectIdentifier(TestMoveUp.self))
        #expect(byType is TestMoveUp)

        #expect(registry.deprecatedAliases()["editor::Down"] == "editor::MoveDown")
        #expect(registry.deprecationMessages()["editor::MoveDown"] == "Use editor::MoveDown instead")
        #expect(registry.documentation()["editor::MoveDown"] == "Move the cursor down by one row")

        #expect(throws: ActionBuildError.self) {
            _ = try registry.buildAction(name: "unknown::Action")
        }
    }

    @Test("NoAction and Unbind control actions")
    func testControlActions() throws {
        let noAction = NoAction()
        #expect(isNoAction(noAction))
        #expect(is_no_action(noAction))
        #expect(!isUnbind(noAction))

        let unbind = Unbind(SharedString("editor::NewLine"))
        #expect(isUnbind(unbind))
        #expect(is_unbind(unbind))
        #expect(!isNoAction(unbind))
        #expect(unbind.actionName == "editor::NewLine")

        let builtUnbind = try Unbind.build(json: ["action": "editor::Save"])
        guard let ub = builtUnbind as? Unbind else {
            Issue.record("Expected Unbind")
            return
        }
        #expect(ub.actionName == "editor::Save")
    }
}
