// Tests ported from: crates/gpui/src/keymap.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

struct ActionAlpha: UnitAction {
    static let name = "test_only::ActionAlpha"
    init() {}
}

struct ActionBeta: UnitAction {
    static let name = "test_only::ActionBeta"
    init() {}
}

struct ActionGamma: UnitAction {
    static let name = "test_only::ActionGamma"
    init() {}
}

struct ActionDelta: UnitAction {
    static let name = "test_only::ActionDelta"
    init() {}
}

@Suite("KeymapTests")
struct KeymapTests {
    @Test("Test keymap basic context matching")
    func testKeymap() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-a", action: ActionAlpha(), context: nil),
            KeyBinding(keystrokes: "ctrl-a", action: ActionBeta(), context: "pane"),
            KeyBinding(keystrokes: "ctrl-a", action: ActionGamma(), context: "editor && mode==full"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        // Global bindings are enabled in all contexts
        #expect(keymap.bindingEnabled(bindings[0], contexts: []) == 0)
        #expect(keymap.bindingEnabled(bindings[0], contexts: [try KeyContext.parse("terminal")]) == 1)

        // Contextual bindings are enabled in contexts that match their predicate
        #expect(keymap.bindingEnabled(bindings[1], contexts: [try KeyContext.parse("barf x=y")]) == nil)
        #expect(keymap.bindingEnabled(bindings[1], contexts: [try KeyContext.parse("pane x=y")]) == 1)

        #expect(keymap.bindingEnabled(bindings[2], contexts: [try KeyContext.parse("editor")]) == nil)
        #expect(keymap.bindingEnabled(bindings[2], contexts: [try KeyContext.parse("editor mode=full")]) == 1)
    }

    @Test("Test depth precedence")
    func testDepthPrecedence() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-a", action: ActionBeta(), context: "pane"),
            KeyBinding(keystrokes: "ctrl-a", action: ActionGamma(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-a")],
            [
                try KeyContext.parse("pane"),
                try KeyContext.parse("editor"),
            ]
        )

        #expect(!pending)
        #expect(result.count == 2)
        #expect(result[0].action.isEqual(to: ActionGamma()))
        #expect(result[1].action.isEqual(to: ActionBeta()))
    }

    @Test("Test keymap disabled bindings")
    func testKeymapDisabled() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-a", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-b", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-a", action: NoAction(), context: "editor && mode==full"),
            KeyBinding(keystrokes: "ctrl-b", action: NoAction(), context: nil),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        // Binding is only enabled in a specific context
        #expect(
            keymap.bindingsForInput(
                [try Keystroke.parse("ctrl-a")],
                [try KeyContext.parse("barf")]
            ).bindings.isEmpty
        )
        #expect(
            !keymap.bindingsForInput(
                [try Keystroke.parse("ctrl-a")],
                [try KeyContext.parse("editor")]
            ).bindings.isEmpty
        )

        // Binding is disabled in a more specific context
        #expect(
            keymap.bindingsForInput(
                [try Keystroke.parse("ctrl-a")],
                [try KeyContext.parse("editor mode=full")]
            ).bindings.isEmpty
        )

        // Binding is globally disabled
        #expect(
            keymap.bindingsForInput(
                [try Keystroke.parse("ctrl-b")],
                [try KeyContext.parse("barf")]
            ).bindings.isEmpty
        )
    }

    @Test("Test multiple keystroke binding disabled")
    func testMultipleKeystrokeBindingDisabled() throws {
        let bindings = [
            KeyBinding(keystrokes: "space w w", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "space w w", action: NoAction(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let space = try Keystroke.parse("space")
        let w = try Keystroke.parse("w")

        let spaceW = [space, w]
        let spaceWW = [space, w, w]

        let workspaceContext = [try KeyContext.parse("workspace")]
        let editorWorkspaceContext = [
            try KeyContext.parse("workspace"),
            try KeyContext.parse("editor"),
        ]

        // Ensure space results in pending input on workspace, but not editor
        let spaceWorkspace = keymap.bindingsForInput([space], workspaceContext)
        #expect(spaceWorkspace.bindings.isEmpty)
        #expect(spaceWorkspace.hasPending)

        let spaceEditor = keymap.bindingsForInput([space], editorWorkspaceContext)
        #expect(spaceEditor.bindings.isEmpty)
        #expect(!spaceEditor.hasPending)

        // Ensure space w results in pending input on workspace, but not editor
        let spaceWWorkspace = keymap.bindingsForInput(spaceW, workspaceContext)
        #expect(spaceWWorkspace.bindings.isEmpty)
        #expect(spaceWWorkspace.hasPending)

        let spaceWEditor = keymap.bindingsForInput(spaceW, editorWorkspaceContext)
        #expect(spaceWEditor.bindings.isEmpty)
        #expect(!spaceWEditor.hasPending)

        // Ensure space w w results in binding in workspace, but not editor
        let spaceWWWorkspace = keymap.bindingsForInput(spaceWW, workspaceContext)
        #expect(!spaceWWWorkspace.bindings.isEmpty)
        #expect(!spaceWWWorkspace.hasPending)

        let spaceWWEditor = keymap.bindingsForInput(spaceWW, editorWorkspaceContext)
        #expect(spaceWWEditor.bindings.isEmpty)
        #expect(!spaceWWEditor.hasPending)

        // Test with another binding defined AFTER the NoAction
        let bindings2 = [
            KeyBinding(keystrokes: "space w w", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "space w w", action: NoAction(), context: "editor"),
            KeyBinding(keystrokes: "space w x", action: ActionAlpha(), context: "editor"),
        ]
        var keymap2 = Keymap()
        keymap2.addBindings(bindings2)

        let spaceEditor2 = keymap2.bindingsForInput([space], editorWorkspaceContext)
        #expect(spaceEditor2.bindings.isEmpty)
        #expect(spaceEditor2.hasPending)

        // Test with another binding defined BEFORE the NoAction
        let bindings3 = [
            KeyBinding(keystrokes: "space w w", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "space w x", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "space w w", action: NoAction(), context: "editor"),
        ]
        var keymap3 = Keymap()
        keymap3.addBindings(bindings3)

        let spaceEditor3 = keymap3.bindingsForInput([space], editorWorkspaceContext)
        #expect(spaceEditor3.bindings.isEmpty)
        #expect(spaceEditor3.hasPending)

        // Test with another binding defined at higher context
        let bindings4 = [
            KeyBinding(keystrokes: "space w w", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "space w x", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "space w w", action: NoAction(), context: "editor"),
        ]
        var keymap4 = Keymap()
        keymap4.addBindings(bindings4)

        let spaceEditor4 = keymap4.bindingsForInput([space], editorWorkspaceContext)
        #expect(spaceEditor4.bindings.isEmpty)
        #expect(spaceEditor4.hasPending)
    }

    @Test("Test override multikey")
    func testOverrideMultikey() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-w left", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-w", action: NoAction(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-w")],
            [try KeyContext.parse("editor")]
        )
        #expect(result.isEmpty)
        #expect(pending)

        let bindings2 = [
            KeyBinding(keystrokes: "ctrl-w left", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-w", action: ActionBeta(), context: "editor"),
        ]
        var keymap2 = Keymap()
        keymap2.addBindings(bindings2)

        let (result2, pending2) = keymap2.bindingsForInput(
            [try Keystroke.parse("ctrl-w")],
            [try KeyContext.parse("editor")]
        )
        #expect(result2.count == 1)
        #expect(!pending2)
    }

    @Test("Test simple disable")
    func testSimpleDisable() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-x", action: NoAction(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [try KeyContext.parse("editor")]
        )
        #expect(result.isEmpty)
        #expect(!pending)
    }

    @Test("Test fail to disable when disabled at wrong level")
    func testFailToDisable() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionAlpha(), context: "editor"),
            KeyBinding(keystrokes: "ctrl-x", action: NoAction(), context: "workspace"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("workspace"),
                try KeyContext.parse("editor"),
            ]
        )
        #expect(result.count == 1)
        #expect(!pending)
    }

    @Test("Test disable deeper")
    func testDisableDeeper() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionAlpha(), context: "workspace"),
            KeyBinding(keystrokes: "ctrl-x", action: NoAction(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("workspace"),
                try KeyContext.parse("editor"),
            ]
        )
        #expect(result.count == 0)
        #expect(!pending)
    }

    @Test("Test pending match enabled")
    func testPendingMatchEnabled() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionBeta(), context: "vim_mode == normal"),
            KeyBinding(keystrokes: "ctrl-x 0", action: ActionAlpha(), context: "Workspace"),
        ]
        var keymap = Keymap()
        keymap.addBindings(bindings)

        let matched = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("Workspace"),
                try KeyContext.parse("Pane"),
                try KeyContext.parse("Editor vim_mode=normal"),
            ]
        )
        #expect(matched.bindings.count == 1)
        #expect(matched.bindings[0].action.isEqual(to: ActionBeta()))
        #expect(matched.hasPending)
    }

    @Test("Test pending match enabled extended")
    func testPendingMatchEnabledExtended() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionBeta(), context: "vim_mode == normal"),
            KeyBinding(keystrokes: "ctrl-x 0", action: NoAction(), context: "Workspace"),
        ]
        var keymap = Keymap()
        keymap.addBindings(bindings)

        let matched = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("Workspace"),
                try KeyContext.parse("Pane"),
                try KeyContext.parse("Editor vim_mode=normal"),
            ]
        )
        #expect(matched.bindings.count == 1)
        #expect(matched.bindings[0].action.isEqual(to: ActionBeta()))
        #expect(!matched.hasPending)

        let bindings2 = [
            KeyBinding(keystrokes: "ctrl-x", action: ActionBeta(), context: "Workspace"),
            KeyBinding(keystrokes: "ctrl-x 0", action: NoAction(), context: "vim_mode == normal"),
        ]
        var keymap2 = Keymap()
        keymap2.addBindings(bindings2)

        let matched2 = keymap2.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("Workspace"),
                try KeyContext.parse("Pane"),
                try KeyContext.parse("Editor vim_mode=normal"),
            ]
        )
        #expect(matched2.bindings.count == 1)
        #expect(matched2.bindings[0].action.isEqual(to: ActionBeta()))
        #expect(!matched2.hasPending)
    }

    @Test("Test overriding prefix")
    func testOverridingPrefix() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-x 0", action: ActionAlpha(), context: "Workspace"),
            KeyBinding(keystrokes: "ctrl-x", action: ActionBeta(), context: "vim_mode == normal"),
        ]
        var keymap = Keymap()
        keymap.addBindings(bindings)

        let matched = keymap.bindingsForInput(
            [try Keystroke.parse("ctrl-x")],
            [
                try KeyContext.parse("Workspace"),
                try KeyContext.parse("Pane"),
                try KeyContext.parse("Editor vim_mode=normal"),
            ]
        )
        #expect(matched.bindings.count == 1)
        #expect(matched.bindings[0].action.isEqual(to: ActionBeta()))
        #expect(!matched.hasPending)
    }

    @Test("Test context precedence with same source")
    func testContextPrecedenceWithSameSource() throws {
        let bindings = [
            KeyBinding(keystrokes: "cmd-r", action: ActionAlpha(), context: "Workspace"),
            KeyBinding(keystrokes: "cmd-r", action: ActionBeta(), context: "Editor"),
        ]
        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, _) = keymap.bindingsForInput(
            [try Keystroke.parse("cmd-r")],
            [
                try KeyContext.parse("Workspace"),
                try KeyContext.parse("Editor"),
            ]
        )

        #expect(result.count == 2)
        #expect(result[0].action.isEqual(to: ActionBeta())) // Editor binding first
        #expect(result[1].action.isEqual(to: ActionAlpha())) // Workspace binding second
    }

    @Test("Test bindings for action")
    func testBindingsForAction() {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-a", action: ActionAlpha(), context: "pane"),
            KeyBinding(keystrokes: "ctrl-b", action: ActionBeta(), context: "editor && mode == full"),
            KeyBinding(keystrokes: "ctrl-c", action: ActionGamma(), context: "workspace"),
            KeyBinding(keystrokes: "ctrl-a", action: NoAction(), context: "pane && active"),
            KeyBinding(keystrokes: "ctrl-b", action: NoAction(), context: "editor"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        func assertBindings(_ action: any Action, _ expected: [String]) {
            let actual = keymap.bindingsForAction(action).map { $0.keystrokes[0].inner.unparse() }
            #expect(actual == expected, "for action \(action.name)")
        }

        assertBindings(ActionAlpha(), ["ctrl-a"])
        assertBindings(ActionBeta(), [])
        assertBindings(ActionGamma(), ["ctrl-c"])
    }

    @Test("Test targeted unbind ignores target context")
    func testTargetedUnbindIgnoresTargetContext() throws {
        let bindings = [
            KeyBinding(keystrokes: "tab", action: ActionAlpha(), context: "Editor"),
            KeyBinding(keystrokes: "tab", action: ActionBeta(), context: "Editor && showing_completions"),
            KeyBinding(
                keystrokes: "tab",
                action: Unbind(SharedString("test_only::ActionAlpha")),
                context: "Editor && edit_prediction"
            ),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        let (result, pending) = keymap.bindingsForInput(
            [try Keystroke.parse("tab")],
            [try KeyContext.parse("Editor showing_completions edit_prediction")]
        )

        #expect(!pending)
        #expect(result.count == 1)
        #expect(result[0].action.isEqual(to: ActionBeta()))
    }

    @Test("Test bindings for action keeps binding for narrower targeted unbind")
    func testBindingsForActionKeepsNarrowerUnbind() {
        let bindings = [
            KeyBinding(keystrokes: "tab", action: ActionAlpha(), context: "Editor"),
            KeyBinding(
                keystrokes: "tab",
                action: Unbind(SharedString("test_only::ActionAlpha")),
                context: "Editor && edit_prediction"
            ),
            KeyBinding(keystrokes: "tab", action: ActionBeta(), context: "Editor && showing_completions"),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        func assertBindings(_ action: any Action, _ expected: [String]) {
            let actual = keymap.bindingsForAction(action).map { $0.keystrokes[0].inner.unparse() }
            #expect(actual == expected, "for action \(action.name)")
        }

        assertBindings(ActionAlpha(), ["tab"])
        assertBindings(ActionBeta(), ["tab"])
    }

    @Test("Test bindings for action removes binding for broader targeted unbind")
    func testBindingsForActionRemovesBroaderUnbind() {
        let bindings = [
            KeyBinding(keystrokes: "tab", action: ActionAlpha(), context: "Editor && edit_prediction"),
            KeyBinding(
                keystrokes: "tab",
                action: Unbind(SharedString("test_only::ActionAlpha")),
                context: "Editor"
            ),
        ]

        var keymap = Keymap()
        keymap.addBindings(bindings)

        #expect(keymap.bindingsForAction(ActionAlpha()).isEmpty)
    }

    @Test("Test source precedence sorting (user overrides default)")
    func testSourcePrecedenceSorting() throws {
        var keymap = Keymap()

        // Default binding first
        var defaultBinding = KeyBinding(keystrokes: "cmd-r", action: ActionAlpha(), context: "Editor")
        defaultBinding.setMeta(KeyBindingMetaIndex(3)) // Default source
        keymap.addBindings([defaultBinding])

        // User binding second
        var userBinding = KeyBinding(keystrokes: "cmd-r", action: ActionBeta(), context: "Editor")
        userBinding.setMeta(KeyBindingMetaIndex(0)) // User source
        keymap.addBindings([userBinding])

        let (result, _) = keymap.bindingsForInput(
            [try Keystroke.parse("cmd-r")],
            [try KeyContext.parse("Editor")]
        )

        #expect(result.count == 2)
        #expect(result[0].action.isEqual(to: ActionBeta()))
        #expect(result[1].action.isEqual(to: ActionAlpha()))
    }
}
