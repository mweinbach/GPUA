// Tests ported from: crates/gpui/src/key_dispatch.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

struct TestDispatchAction: UnitAction {
    static let name = "dispatch_test::TestAction"
    init() {}
}

struct SecondaryTestAction: UnitAction {
    static let name = "dispatch_test::SecondaryTestAction"
    init() {}
}

func testDispatchTree(bindings: [KeyBinding]) -> DispatchTree {
    let registry = ActionRegistry()
    registry.register(TestDispatchAction.self)
    registry.register(SecondaryTestAction.self)
    let keymap = Keymap(bindings: bindings)
    return DispatchTree(keymap: keymap, actionRegistry: registry)
}

@Suite("KeyDispatchTests")
struct KeyDispatchTests {
    @Test("Test keybinding for action bounds")
    func testKeybindingForActionBounds() throws {
        let tree = testDispatchTree(bindings: [
            KeyBinding(keystrokes: "cmd-n", action: TestDispatchAction(), context: "ProjectPanel")
        ])

        let contexts = [
            try KeyContext.parse("Workspace"),
            try KeyContext.parse("ProjectPanel"),
        ]

        let keybindings = tree.bindingsForAction(TestDispatchAction(), contexts)
        #expect(keybindings.count == 1)
        #expect(keybindings[0].action.isEqual(to: TestDispatchAction()))
    }

    @Test("Test bindings for action hides targeted unbind in active context")
    func testBindingsForActionHidesTargetedUnbind() throws {
        let tree = testDispatchTree(bindings: [
            KeyBinding(keystrokes: "tab", action: TestDispatchAction(), context: "Editor"),
            KeyBinding(
                keystrokes: "tab",
                action: Unbind(SharedString("dispatch_test::TestAction")),
                context: "Editor && edit_prediction"
            ),
            KeyBinding(
                keystrokes: "tab",
                action: SecondaryTestAction(),
                context: "Editor && showing_completions"
            ),
        ])

        let contexts = [
            try KeyContext.parse("Workspace"),
            try KeyContext.parse("Editor showing_completions edit_prediction"),
        ]

        let bindings = tree.bindingsForAction(TestDispatchAction(), contexts)
        #expect(bindings.isEmpty)

        let highest = tree.highestPrecedenceBindingForAction(TestDispatchAction(), contexts)
        #expect(highest == nil)

        let fallbackBindings = tree.bindingsForAction(SecondaryTestAction(), contexts)
        #expect(fallbackBindings.count == 1)
        #expect(fallbackBindings[0].action.isEqual(to: SecondaryTestAction()))
    }

    @Test("Test bindings for action keeps targeted binding outside unbind context")
    func testBindingsForActionKeepsTargetedBindingOutsideUnbindContext() throws {
        let tree = testDispatchTree(bindings: [
            KeyBinding(keystrokes: "tab", action: TestDispatchAction(), context: "Editor"),
            KeyBinding(
                keystrokes: "tab",
                action: Unbind(SharedString("dispatch_test::TestAction")),
                context: "Editor && edit_prediction"
            ),
            KeyBinding(
                keystrokes: "tab",
                action: SecondaryTestAction(),
                context: "Editor && showing_completions"
            ),
        ])

        let contexts = [
            try KeyContext.parse("Workspace"),
            try KeyContext.parse("Editor"),
        ]

        let bindings = tree.bindingsForAction(TestDispatchAction(), contexts)
        #expect(bindings.count == 1)
        #expect(bindings[0].action.isEqual(to: TestDispatchAction()))

        let highest = tree.highestPrecedenceBindingForAction(TestDispatchAction(), contexts)
        #expect(highest?.action.isEqual(to: TestDispatchAction()) == true)
    }

    @Test("Test pending has binding state")
    func testPendingHasBindingState() throws {
        let bindings = [
            KeyBinding(keystrokes: "ctrl-b h", action: TestDispatchAction(), context: nil),
            KeyBinding(keystrokes: "space", action: TestDispatchAction(), context: "ContextA"),
            KeyBinding(keystrokes: "space f g", action: TestDispatchAction(), context: "ContextB"),
        ]
        var tree = testDispatchTree(bindings: bindings)

        let emptyPath: [DispatchNodeId] = []
        let result1 = tree.dispatchKey([], try Keystroke.parse("ctrl-b"), emptyPath)
        #expect(result1.pending.count == 1)
        #expect(!result1.pendingHasBinding)

        let result2 = tree.dispatchKey(result1.pending, try Keystroke.parse("h"), emptyPath)
        #expect(result2.pending.isEmpty)
        #expect(result2.bindings.count == 1)
        #expect(!result2.pendingHasBinding)

        let nodeId = tree.pushNode()
        tree.setKeyContext(try KeyContext.parse("ContextB"))
        tree.popNode()

        let dispatchPath = tree.dispatchPath(nodeId)
        let result3 = tree.dispatchKey([], try Keystroke.parse("space"), dispatchPath)
        #expect(result3.pending.count == 1)
        #expect(!result3.pendingHasBinding)
    }

    @Test("Test focus contains hierarchy")
    func testFocusContainsHierarchy() {
        var tree = DispatchTree()
        _ = tree.pushNode()
        let rootFocus = FocusId(1)
        tree.setFocusId(rootFocus)

        _ = tree.pushNode()
        let childFocus = FocusId(2)
        tree.setFocusId(childFocus)

        _ = tree.pushNode()
        let grandchildFocus = FocusId(3)
        tree.setFocusId(grandchildFocus)

        #expect(tree.focusContains(parent: rootFocus, child: rootFocus))
        #expect(tree.focusContains(parent: rootFocus, child: childFocus))
        #expect(tree.focusContains(parent: rootFocus, child: grandchildFocus))
        #expect(tree.focusContains(parent: childFocus, child: grandchildFocus))
        #expect(!tree.focusContains(parent: grandchildFocus, child: childFocus))
        #expect(!tree.focusContains(parent: childFocus, child: rootFocus))
    }

    @Test("Test dispatch path calculation")
    func testDispatchPath() {
        var tree = DispatchTree()
        let node0 = tree.pushNode()
        let node1 = tree.pushNode()
        let node2 = tree.pushNode()

        let path = tree.dispatchPath(node2)
        #expect(path == [node0, node1, node2])
    }

    @Test("Test chord fallthrough and replay")
    func testChordReplay() throws {
        let bindings = [
            KeyBinding(keystrokes: "cmd-k", action: SecondaryTestAction()),
            KeyBinding(keystrokes: "cmd-k cmd-s", action: TestDispatchAction()),
        ]
        var tree = testDispatchTree(bindings: bindings)
        let emptyPath: [DispatchNodeId] = []

        // First key: "cmd-k" is a prefix for "cmd-k cmd-s"
        let res1 = tree.dispatchKey([], try Keystroke.parse("cmd-k"), emptyPath)
        #expect(res1.pending.count == 1)

        // Non-matching second key: "cmd-x" -> should replay "cmd-k" which matches SecondaryTestAction!
        let res2 = tree.dispatchKey(res1.pending, try Keystroke.parse("cmd-x"), emptyPath)
        #expect(res2.toReplay.count == 1)
        #expect(res2.toReplay[0].bindings.count == 1)
        #expect(res2.toReplay[0].bindings[0].action.isEqual(to: SecondaryTestAction()))
    }
}
