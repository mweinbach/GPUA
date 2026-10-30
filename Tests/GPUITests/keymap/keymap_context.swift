// Tests ported from: crates/gpui/src/keymap/context.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("KeymapContextTests")
struct KeymapContextTests {
    @Test("Test actions definition")
    func test_actions_definition() {
        struct ActionA: Action, Equatable {
            static let name = "test_only::A"
            static func build(json: [String: Any]) throws -> any Action { ActionA() }
            func isEqual(to other: any Action) -> Bool { (other as? ActionA) == self }
        }
        struct ActionB: Action, Equatable {
            static let name = "test_only::B"
            static func build(json: [String: Any]) throws -> any Action { ActionB() }
            func isEqual(to other: any Action) -> Bool { (other as? ActionB) == self }
        }

        #expect(ActionA.name == "test_only::A")
        #expect(ActionB.name == "test_only::B")
        #expect(ActionA().isEqual(to: ActionA()))
        #expect(!ActionA().isEqual(to: ActionB()))
    }

    @Test("Parse context strings")
    func testParseContext() throws {
        var expected = KeyContext()
        expected.add("baz")
        expected.set("foo", "bar")

        #expect(try KeyContext.parse("baz foo=bar") == expected)
        #expect(try KeyContext.parse("baz foo = bar") == expected)
        #expect(try KeyContext.parse("  baz foo   =   bar baz") == expected)
        #expect(try KeyContext.parse(" baz foo = bar") == expected)
    }

    @Test("Parse identifiers")
    func testParseIdentifiers() throws {
        #expect(try KeyBindingContextPredicate.parse("abc12") == .identifier(SharedString("abc12")))
        #expect(try KeyBindingContextPredicate.parse("_1a") == .identifier(SharedString("_1a")))
    }

    @Test("Parse negations")
    func testParseNegations() throws {
        #expect(try KeyBindingContextPredicate.parse("!abc") == .not(.identifier(SharedString("abc"))))
        #expect(try KeyBindingContextPredicate.parse(" ! ! abc") == .not(.not(.identifier(SharedString("abc")))))
    }

    @Test("Parse equality operators")
    func testParseEqualityOperators() throws {
        #expect(try KeyBindingContextPredicate.parse("a == b") == .equal(SharedString("a"), SharedString("b")))
        #expect(try KeyBindingContextPredicate.parse("c!=d") == .notEqual(SharedString("c"), SharedString("d")))

        #expect(throws: ContextParseError.self) {
            _ = try KeyBindingContextPredicate.parse("c == !d")
        }
    }

    @Test("Parse boolean operators")
    func testParseBooleanOperators() throws {
        #expect(try KeyBindingContextPredicate.parse("a || b") == .or(
            .identifier(SharedString("a")),
            .identifier(SharedString("b"))
        ))

        #expect(try KeyBindingContextPredicate.parse("a || !b && c") == .or(
            .identifier(SharedString("a")),
            .and(
                .not(.identifier(SharedString("b"))),
                .identifier(SharedString("c"))
            )
        ))

        #expect(try KeyBindingContextPredicate.parse("a && b || c&&d") == .or(
            .and(.identifier(SharedString("a")), .identifier(SharedString("b"))),
            .and(.identifier(SharedString("c")), .identifier(SharedString("d")))
        ))

        #expect(try KeyBindingContextPredicate.parse("a == b && c || d == e && f") == .or(
            .and(.equal(SharedString("a"), SharedString("b")), .identifier(SharedString("c"))),
            .and(.equal(SharedString("d"), SharedString("e")), .identifier(SharedString("f")))
        ))

        #expect(try KeyBindingContextPredicate.parse("a && b && c && d") == .and(
            .and(
                .and(.identifier(SharedString("a")), .identifier(SharedString("b"))),
                .identifier(SharedString("c"))
            ),
            .identifier(SharedString("d"))
        ))
    }

    @Test("Parse parenthesized expressions")
    func testParseParenthesizedExpressions() throws {
        #expect(try KeyBindingContextPredicate.parse("a && (b == c || d != e)") == .and(
            .identifier(SharedString("a")),
            .or(
                .equal(SharedString("b"), SharedString("c")),
                .notEqual(SharedString("d"), SharedString("e"))
            )
        ))

        #expect(try KeyBindingContextPredicate.parse(" ( a || b ) ") == .or(
            .identifier(SharedString("a")),
            .identifier(SharedString("b"))
        ))
    }

    @Test("isSuperset predicate evaluation")
    func testIsSuperset() throws {
        func assertIsSuperset(_ a: String, _ b: String, _ expected: Bool) throws {
            let predA = try KeyBindingContextPredicate.parse(a)
            let predB = try KeyBindingContextPredicate.parse(b)
            #expect(predA.isSuperset(of: predB) == expected, "(\(predA)).isSuperset(\(predB))")
        }

        try assertIsSuperset("editor", "editor", true)
        try assertIsSuperset("editor", "workspace", false)
        try assertIsSuperset("editor", "editor && vim_mode", true)
        try assertIsSuperset("editor", "mode == full && editor", true)
        try assertIsSuperset("editor && mode == full", "editor", false)
        try assertIsSuperset("editor", "something > editor", true)
        try assertIsSuperset("editor", "editor > menu", false)
        try assertIsSuperset("foo || bar || baz", "bar", true)
        try assertIsSuperset("foo || bar || baz", "quux", false)
    }

    @Test("Child / descendant operator evaluation")
    func testChildOperator() throws {
        let predicate = try KeyBindingContextPredicate.parse("parent > child")

        let parentContext = try KeyContext.parse("parent")
        let childContext = try KeyContext.parse("child")

        let contexts = [parentContext, childContext]
        #expect(predicate.eval(contexts))

        let grandparentContext = try KeyContext.parse("grandparent")
        let contexts2 = [grandparentContext, parentContext, childContext]
        #expect(predicate.eval(contexts2))

        let otherContext = try KeyContext.parse("other")
        let contexts3 = [otherContext, childContext]
        #expect(!predicate.eval(contexts3))

        let contexts4 = [parentContext, otherContext, childContext]
        #expect(predicate.eval(contexts4))

        #expect(!predicate.eval([]))
        #expect(!predicate.eval([childContext]))
        #expect(!predicate.eval([parentContext]))

        let zanyPredicate = try KeyBindingContextPredicate.parse("child > child")
        #expect(!zanyPredicate.eval([childContext]))
        #expect(zanyPredicate.eval([childContext, childContext]))
    }

    @Test("Not operator evaluation")
    func testNotOperator() throws {
        let notPredicate = try KeyBindingContextPredicate.parse("!editor")
        let editorContext = try KeyContext.parse("editor")
        let workspaceContext = try KeyContext.parse("workspace")
        let parentContext = try KeyContext.parse("parent")
        let childContext = try KeyContext.parse("child")

        #expect(notPredicate.eval([workspaceContext]))
        #expect(!notPredicate.eval([editorContext]))
        #expect(!notPredicate.eval([editorContext, workspaceContext]))
        #expect(!notPredicate.eval([workspaceContext, editorContext]))

        let complexNot = try KeyBindingContextPredicate.parse("!editor && workspace")
        #expect(complexNot.eval([workspaceContext]))
        #expect(!complexNot.eval([editorContext, workspaceContext]))

        let notModePredicate = try KeyBindingContextPredicate.parse("!(mode == full)")
        var modeContext = KeyContext()
        modeContext.set("mode", "full")
        #expect(!notModePredicate.eval([modeContext]))

        var otherModeContext = KeyContext()
        otherModeContext.set("mode", "partial")
        #expect(notModePredicate.eval([otherModeContext]))

        let notDescendant = try KeyBindingContextPredicate.parse("!(parent > child)")
        #expect(notDescendant.eval([parentContext]))
        #expect(notDescendant.eval([childContext]))
        #expect(!notDescendant.eval([parentContext, childContext]))

        let notDescendant2 = try KeyBindingContextPredicate.parse("parent > !child")
        #expect(!notDescendant2.eval([parentContext]))
        #expect(!notDescendant2.eval([childContext]))
        #expect(!notDescendant2.eval([parentContext, childContext]))

        let doubleNot = try KeyBindingContextPredicate.parse("!!editor")
        #expect(doubleNot.eval([editorContext]))
        #expect(!doubleNot.eval([workspaceContext]))

        // Workspace > Pane > Editor
        let workspaceContext2 = try KeyContext.parse("Workspace")
        let paneContext = try KeyContext.parse("Pane")
        let editorContext2 = try KeyContext.parse("Editor")

        let workspacePaneEditor = [workspaceContext2, paneContext, editorContext2]

        let panePaneEditor = try KeyBindingContextPredicate.parse("Pane > (Pane > Editor)")
        #expect(!panePaneEditor.eval(workspacePaneEditor))

        let workspacePaneEditorPredicate = try KeyBindingContextPredicate.parse("Workspace > Pane > Editor")
        #expect(workspacePaneEditorPredicate.eval(workspacePaneEditor))

        let panePaneThenEditor = try KeyBindingContextPredicate.parse("(Pane > Pane) > Editor")
        #expect(!panePaneThenEditor.eval(workspacePaneEditor))

        let paneNotWorkspace = try KeyBindingContextPredicate.parse("Pane > !Workspace")
        #expect(paneNotWorkspace.eval([paneContext, editorContext2]))
        #expect(!paneNotWorkspace.eval([paneContext, workspaceContext2]))

        let notWorkspace = try KeyBindingContextPredicate.parse("!Workspace")
        #expect(!notWorkspace.eval([workspaceContext2]))
        #expect(notWorkspace.eval([paneContext]))
        #expect(notWorkspace.eval([editorContext2]))
        #expect(!notWorkspace.eval(workspacePaneEditor))
    }

    @Test("Context display / to_string roundtrip")
    func testContextDisplay() throws {
        func ident(_ s: String) -> KeyBindingContextPredicate {
            .identifier(SharedString(s))
        }
        func eq(_ a: String, _ b: String) -> KeyBindingContextPredicate {
            .equal(SharedString(a), SharedString(b))
        }
        func notEq(_ a: String, _ b: String) -> KeyBindingContextPredicate {
            .notEqual(SharedString(a), SharedString(b))
        }
        func and(_ a: KeyBindingContextPredicate, _ b: KeyBindingContextPredicate) -> KeyBindingContextPredicate {
            .and(a, b)
        }
        func or(_ a: KeyBindingContextPredicate, _ b: KeyBindingContextPredicate) -> KeyBindingContextPredicate {
            .or(a, b)
        }
        func descendant(_ a: KeyBindingContextPredicate, _ b: KeyBindingContextPredicate) -> KeyBindingContextPredicate {
            .descendant(a, b)
        }
        func not(_ a: KeyBindingContextPredicate) -> KeyBindingContextPredicate {
            .not(a)
        }

        let testCases: [(KeyBindingContextPredicate, String)] = [
            (ident("a"), "a"),
            (eq("a", "b"), "a == b"),
            (notEq("a", "b"), "a != b"),
            (descendant(ident("a"), ident("b")), "a > b"),
            (not(ident("a")), "!a"),
            (not(and(ident("a"), ident("b"))), "!(a && b)"),
            (not(or(ident("a"), ident("b"))), "!(a || b)"),
            (and(ident("a"), ident("b")), "a && b"),
            (and(and(ident("a"), ident("b")), ident("c")), "a && b && c"),
            (or(ident("a"), ident("b")), "a || b"),
            (or(or(ident("a"), ident("b")), ident("c")), "a || b || c"),
            (or(ident("a"), and(ident("b"), ident("c"))), "a || (b && c)"),
            (
                and(
                    and(
                        and(ident("a"), eq("b", "c")),
                        not(descendant(ident("d"), ident("e")))
                    ),
                    eq("f", "g")
                ),
                "a && b == c && !(d > e) && f == g"
            ),
            (
                and(and(ident("a"), or(ident("b"), ident("c"))), ident("d")),
                "a && (b || c) && d"
            ),
            (
                or(or(ident("a"), and(ident("b"), ident("c"))), ident("d")),
                "a || (b && c) || d"
            ),
        ]

        for (predicate, expected) in testCases {
            let actual = "\(predicate)"
            #expect(actual == expected)
            let parsed = try KeyBindingContextPredicate.parse(actual)
            #expect(parsed == predicate)
        }
    }
}
