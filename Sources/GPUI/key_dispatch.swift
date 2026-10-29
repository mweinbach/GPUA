// Ported from: crates/gpui/src/key_dispatch.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// ID of a node within DispatchTree. Note that these are not stable between frames.
@frozen
public struct DispatchNodeId: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A replayed keystroke when pending chording input fails to match.
public struct Replay: Sendable, Equatable {
    public var keystroke: Keystroke
    public var bindings: [KeyBinding]

    public init(keystroke: Keystroke = Keystroke(), bindings: [KeyBinding] = []) {
        self.keystroke = keystroke
        self.bindings = bindings
    }
}

/// Result of dispatching a keystroke through the tree.
public struct DispatchResult: Sendable, Equatable {
    public var pending: [Keystroke]
    public var pendingHasBinding: Bool
    public var bindings: [KeyBinding]
    public var toReplay: [Replay]
    public var contextStack: [KeyContext]

    public init(
        pending: [Keystroke] = [],
        pendingHasBinding: Bool = false,
        bindings: [KeyBinding] = [],
        toReplay: [Replay] = [],
        contextStack: [KeyContext] = []
    ) {
        self.pending = pending
        self.pendingHasBinding = pendingHasBinding
        self.bindings = bindings
        self.toReplay = toReplay
        self.contextStack = contextStack
    }
}

public typealias KeyListener = @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void
public typealias ModifiersChangedListener = @Sendable (ModifiersChangedEvent, inout Window, inout App) -> Void

public struct DispatchActionListener {
    public var actionType: ObjectIdentifier
    public var listener: @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void

    public init(
        actionType: ObjectIdentifier,
        listener: @escaping @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void
    ) {
        self.actionType = actionType
        self.listener = listener
    }
}

public struct DispatchNode {
    public var keyListeners: [KeyListener]
    public var actionListeners: [DispatchActionListener]
    public var modifiersChangedListeners: [ModifiersChangedListener]
    public var context: KeyContext?
    public var focusId: FocusId?
    public var viewId: EntityId?
    public var parent: DispatchNodeId?

    public init(
        keyListeners: [KeyListener] = [],
        actionListeners: [DispatchActionListener] = [],
        modifiersChangedListeners: [ModifiersChangedListener] = [],
        context: KeyContext? = nil,
        focusId: FocusId? = nil,
        viewId: EntityId? = nil,
        parent: DispatchNodeId? = nil
    ) {
        self.keyListeners = keyListeners
        self.actionListeners = actionListeners
        self.modifiersChangedListeners = modifiersChangedListeners
        self.context = context
        self.focusId = focusId
        self.viewId = viewId
        self.parent = parent
    }
}

public struct ReusedSubtree: Sendable {
    public var oldRange: Range<Int>
    public var newRange: Range<Int>
    public var containsFocus: Bool

    public init(oldRange: Range<Int>, newRange: Range<Int>, containsFocus: Bool) {
        self.oldRange = oldRange
        self.newRange = newRange
        self.containsFocus = containsFocus
    }

    public func refreshNodeId(_ nodeId: DispatchNodeId) -> DispatchNodeId {
        assert(
            oldRange.contains(nodeId.rawValue),
            "node \(nodeId.rawValue) was not part of the reused subtree \(oldRange)"
        )
        return DispatchNodeId((nodeId.rawValue - oldRange.lowerBound) + newRange.lowerBound)
    }

    public func contains_focus() -> Bool {
        containsFocus
    }
}

/// Key dispatch tree mirroring the rendered element hierarchy for input dispatching.
public struct DispatchTree {
    private var nodeStack: [DispatchNodeId] = []
    public var contextStack: [KeyContext] = []
    private var viewStack: [EntityId] = []
    public private(set) var nodes: [DispatchNode] = []
    private var focusableNodeIds: [FocusId: DispatchNodeId] = [:]
    private var viewNodeIds: [EntityId: DispatchNodeId] = [:]

    public var keymap: Keymap
    public var actionRegistry: ActionRegistry

    public init(
        keymap: Keymap = Keymap(),
        actionRegistry: ActionRegistry = ActionRegistry()
    ) {
        self.keymap = keymap
        self.actionRegistry = actionRegistry
    }

    public mutating func clear() {
        nodeStack.removeAll()
        contextStack.removeAll()
        viewStack.removeAll()
        nodes.removeAll()
        focusableNodeIds.removeAll()
        viewNodeIds.removeAll()
    }

    public var count: Int {
        nodes.count
    }

    public var len: Int {
        nodes.count
    }

    public mutating func pushNode() -> DispatchNodeId {
        let parent = nodeStack.last
        let nodeId = DispatchNodeId(nodes.count)

        nodes.append(DispatchNode(parent: parent))
        nodeStack.append(nodeId)
        return nodeId
    }

    public mutating func push_node() -> DispatchNodeId {
        pushNode()
    }

    public mutating func setActiveNode(_ nodeId: DispatchNodeId) {
        let nextNodeParent = nodes[nodeId.rawValue].parent
        while nodeStack.last != nextNodeParent && !nodeStack.isEmpty {
            popNode()
        }

        if nodeStack.last == nextNodeParent {
            nodeStack.append(nodeId)
            let activeNode = nodes[nodeId.rawValue]
            if let viewId = activeNode.viewId {
                viewStack.append(viewId)
            }
            if let context = activeNode.context {
                contextStack.append(context)
            }
        } else {
            assert(nodeStack.isEmpty)

            var currentNodeId: DispatchNodeId? = nodeId
            while let current = currentNodeId {
                let node = nodes[current.rawValue]
                if let context = node.context {
                    contextStack.append(context)
                }
                if let viewId = node.viewId {
                    viewStack.append(viewId)
                }
                nodeStack.append(current)
                currentNodeId = node.parent
            }

            contextStack.reverse()
            viewStack.reverse()
            nodeStack.reverse()
        }
    }

    public mutating func set_active_node(_ nodeId: DispatchNodeId) {
        setActiveNode(nodeId)
    }

    public mutating func setKeyContext(_ context: KeyContext) {
        guard let activeId = activeNodeId() else { return }
        nodes[activeId.rawValue].context = context
        contextStack.append(context)
    }

    public mutating func set_key_context(_ context: KeyContext) {
        setKeyContext(context)
    }

    public func currentContextStack() -> [KeyContext] {
        contextStack
    }

    public func current_context_stack() -> [KeyContext] {
        currentContextStack()
    }

    public mutating func setFocusId(_ focusId: FocusId) {
        guard let nodeId = nodeStack.last else { return }
        nodes[nodeId.rawValue].focusId = focusId
        focusableNodeIds[focusId] = nodeId
    }

    public mutating func set_focus_id(_ focusId: FocusId) {
        setFocusId(focusId)
    }

    public mutating func setViewId(_ viewId: EntityId) {
        if viewStack.last != viewId {
            guard let nodeId = nodeStack.last else { return }
            nodes[nodeId.rawValue].viewId = viewId
            viewNodeIds[viewId] = nodeId
            viewStack.append(viewId)
        }
    }

    public mutating func set_view_id(_ viewId: EntityId) {
        setViewId(viewId)
    }

    public mutating func popNode() {
        guard let activeId = activeNodeId() else { return }
        let node = nodes[activeId.rawValue]
        if node.context != nil {
            contextStack.removeLast()
        }
        if node.viewId != nil {
            viewStack.removeLast()
        }
        nodeStack.removeLast()
    }

    public mutating func pop_node() {
        popNode()
    }

    private mutating func moveNode(source: inout DispatchNode) {
        _ = pushNode()
        if let context = source.context {
            setKeyContext(context)
        }
        if let focusId = source.focusId {
            setFocusId(focusId)
        }
        if let viewId = source.viewId {
            setViewId(viewId)
        }

        let targetId = activeNodeId()!.rawValue
        nodes[targetId].keyListeners = source.keyListeners
        nodes[targetId].actionListeners = source.actionListeners
        nodes[targetId].modifiersChangedListeners = source.modifiersChangedListeners

        source.keyListeners = []
        source.actionListeners = []
        source.modifiersChangedListeners = []
    }

    public mutating func reuseSubtree(
        oldRange: Range<Int>,
        source: inout DispatchTree,
        focus: FocusId?
    ) -> ReusedSubtree {
        let newRange = nodes.count..<(nodes.count + oldRange.count)
        var containsFocus = false
        var sourceStack: [DispatchNodeId] = []

        for sourceIndex in oldRange {
            let sourceNodeId = DispatchNodeId(sourceIndex)
            let sourceNode = source.nodes[sourceIndex]

            while let sourceAncestor = sourceStack.last {
                if sourceNode.parent == sourceAncestor {
                    break
                } else {
                    sourceStack.removeLast()
                    popNode()
                }
            }

            sourceStack.append(sourceNodeId)
            if let fId = sourceNode.focusId, fId == focus {
                containsFocus = true
            }

            var tempNode = sourceNode
            moveNode(source: &tempNode)
            source.nodes[sourceIndex] = tempNode
        }

        while !sourceStack.isEmpty {
            sourceStack.removeLast()
            popNode()
        }

        return ReusedSubtree(
            oldRange: oldRange,
            newRange: newRange,
            containsFocus: containsFocus
        )
    }

    public mutating func reuse_subtree(
        _ oldRange: Range<Int>,
        _ source: inout DispatchTree,
        _ focus: FocusId?
    ) -> ReusedSubtree {
        reuseSubtree(oldRange: oldRange, source: &source, focus: focus)
    }

    public mutating func truncate(_ index: Int) {
        for node in nodes[index...] {
            if let focusId = node.focusId {
                focusableNodeIds.removeValue(forKey: focusId)
            }
            if let viewId = node.viewId {
                viewNodeIds.removeValue(forKey: viewId)
            }
        }
        nodes.removeSubrange(index...)
    }

    public mutating func onKeyEvent(_ listener: @escaping KeyListener) {
        guard let activeId = activeNodeId() else { return }
        nodes[activeId.rawValue].keyListeners.append(listener)
    }

    public mutating func on_key_event(_ listener: @escaping KeyListener) {
        onKeyEvent(listener)
    }

    public mutating func onModifiersChanged(_ listener: @escaping ModifiersChangedListener) {
        guard let activeId = activeNodeId() else { return }
        nodes[activeId.rawValue].modifiersChangedListeners.append(listener)
    }

    public mutating func on_modifiers_changed(_ listener: @escaping ModifiersChangedListener) {
        onModifiersChanged(listener)
    }

    public mutating func onAction(
        actionType: ObjectIdentifier,
        listener: @escaping @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void
    ) {
        guard let activeId = activeNodeId() else { return }
        nodes[activeId.rawValue].actionListeners.append(
            DispatchActionListener(actionType: actionType, listener: listener)
        )
    }

    public mutating func on_action(
        _ actionType: ObjectIdentifier,
        _ listener: @escaping @Sendable (Any, DispatchPhase, inout Window, inout App) -> Void
    ) {
        onAction(actionType: actionType, listener: listener)
    }

    public func focusContains(parent: FocusId, child: FocusId) -> Bool {
        if parent == child {
            return true
        }

        guard let parentNodeId = focusableNodeIds[parent] else {
            return false
        }

        var currentNodeId = focusableNodeIds[child]
        while let nodeId = currentNodeId {
            if nodeId == parentNodeId {
                return true
            }
            currentNodeId = nodes[nodeId.rawValue].parent
        }
        return false
    }

    public func focus_contains(_ parent: FocusId, _ child: FocusId) -> Bool {
        focusContains(parent: parent, child: child)
    }

    public func availableActions(target: DispatchNodeId) -> [any Action] {
        var actions: [any Action] = []
        var seen = Set<ObjectIdentifier>()

        for nodeId in dispatchPath(target) {
            let node = nodes[nodeId.rawValue]
            for actionListener in node.actionListeners {
                if !seen.contains(actionListener.actionType) {
                    seen.insert(actionListener.actionType)
                    if let action = try? actionRegistry.buildActionType(actionListener.actionType) {
                        actions.append(action)
                    }
                }
            }
        }
        return actions
    }

    public func available_actions(_ target: DispatchNodeId) -> [any Action] {
        availableActions(target: target)
    }

    public func isActionAvailable(_ action: any Action, target: DispatchNodeId) -> Bool {
        let actionId = ObjectIdentifier(type(of: action))
        for nodeId in dispatchPath(target) {
            let node = nodes[nodeId.rawValue]
            if node.actionListeners.contains(where: { $0.actionType == actionId }) {
                return true
            }
        }
        return false
    }

    public func is_action_available(_ action: any Action, _ target: DispatchNodeId) -> Bool {
        isActionAvailable(action, target: target)
    }

    public func bindingsForAction(
        _ action: any Action,
        _ contextStack: [KeyContext]
    ) -> [KeyBinding] {
        keymap.bindingsForAction(action).filter { binding in
            bindingMatchesPredicateAndNotShadowed(binding: binding, contextStack: contextStack)
        }
    }

    public func bindings_for_action(
        _ action: any Action,
        _ context_stack: [KeyContext]
    ) -> [KeyBinding] {
        bindingsForAction(action, context_stack)
    }

    public func highestPrecedenceBindingForAction(
        _ action: any Action,
        _ contextStack: [KeyContext]
    ) -> KeyBinding? {
        keymap.bindingsForAction(action).reversed().first { binding in
            bindingMatchesPredicateAndNotShadowed(binding: binding, contextStack: contextStack)
        }
    }

    public func highest_precedence_binding_for_action(
        _ action: any Action,
        _ context_stack: [KeyContext]
    ) -> KeyBinding? {
        highestPrecedenceBindingForAction(action, context_stack)
    }

    private func bindingMatchesPredicateAndNotShadowed(
        binding: KeyBinding,
        contextStack: [KeyContext]
    ) -> Bool {
        let (bindings, _) = keymap.bindingsForInput(binding.keystrokes, contextStack)
        if let found = bindings.first {
            return found.action.isEqual(to: binding.action)
        }
        return false
    }

    private func bindingsForInput(
        _ input: [Keystroke],
        dispatchPath: [DispatchNodeId]
    ) -> (bindings: [KeyBinding], partial: Bool, contextStack: [KeyContext]) {
        let contextStack: [KeyContext] = dispatchPath.compactMap {
            nodes[$0.rawValue].context
        }

        let (bindings, partial) = keymap.bindingsForInput(input, contextStack)
        return (bindings, partial, contextStack)
    }

    public func possibleNextBindingsForInput(
        _ input: [Keystroke],
        _ contextStack: [KeyContext]
    ) -> [KeyBinding] {
        keymap.possibleNextBindingsForInput(input, contextStack)
    }

    public func possible_next_bindings_for_input(
        _ input: [Keystroke],
        _ context_stack: [KeyContext]
    ) -> [KeyBinding] {
        possibleNextBindingsForInput(input, context_stack)
    }

    public mutating func dispatchKey(
        _ input: [Keystroke],
        _ keystroke: Keystroke,
        _ dispatchPath: [DispatchNodeId]
    ) -> DispatchResult {
        var mutableInput = input
        mutableInput.append(keystroke)
        let (bindings, pending, contextStack) = bindingsForInput(mutableInput, dispatchPath: dispatchPath)

        if pending {
            return DispatchResult(
                pending: mutableInput,
                pendingHasBinding: !bindings.isEmpty,
                bindings: [],
                toReplay: [],
                contextStack: contextStack
            )
        } else if !bindings.isEmpty {
            return DispatchResult(
                pending: [],
                pendingHasBinding: false,
                bindings: bindings,
                toReplay: [],
                contextStack: contextStack
            )
        } else if mutableInput.count == 1 {
            return DispatchResult(
                pending: [],
                pendingHasBinding: false,
                bindings: [],
                toReplay: [],
                contextStack: contextStack
            )
        }

        mutableInput.removeLast()
        let (suffix, toReplay) = replayPrefix(input: mutableInput, dispatchPath: dispatchPath)
        var result = dispatchKey(suffix, keystroke, dispatchPath)
        var combinedReplay = toReplay
        combinedReplay.append(contentsOf: result.toReplay)
        result.toReplay = combinedReplay
        return result
    }

    public mutating func dispatch_key(
        _ input: [Keystroke],
        _ keystroke: Keystroke,
        _ dispatch_path: [DispatchNodeId]
    ) -> DispatchResult {
        dispatchKey(input, keystroke, dispatch_path)
    }

    public func dispatchKeyWithContextStack(
        _ input: [Keystroke],
        _ keystroke: Keystroke,
        _ contextStack: [KeyContext]
    ) -> DispatchResult {
        var mutableInput = input
        mutableInput.append(keystroke)
        let (bindings, pending) = keymap.bindingsForInput(mutableInput, contextStack)

        if pending {
            return DispatchResult(
                pending: mutableInput,
                pendingHasBinding: !bindings.isEmpty,
                bindings: [],
                toReplay: [],
                contextStack: contextStack
            )
        } else if !bindings.isEmpty {
            return DispatchResult(
                pending: [],
                pendingHasBinding: false,
                bindings: bindings,
                toReplay: [],
                contextStack: contextStack
            )
        } else if mutableInput.count == 1 {
            return DispatchResult(
                pending: [],
                pendingHasBinding: false,
                bindings: [],
                toReplay: [],
                contextStack: contextStack
            )
        }

        mutableInput.removeLast()
        let (suffix, toReplay) = replayPrefixWithContextStack(input: mutableInput, contextStack: contextStack)
        var result = dispatchKeyWithContextStack(suffix, keystroke, contextStack)
        var combinedReplay = toReplay
        combinedReplay.append(contentsOf: result.toReplay)
        result.toReplay = combinedReplay
        return result
    }

    public func dispatch_key_with_context_stack(
        _ input: [Keystroke],
        _ keystroke: Keystroke,
        _ context_stack: [KeyContext]
    ) -> DispatchResult {
        dispatchKeyWithContextStack(input, keystroke, context_stack)
    }

    public func flushDispatch(
        input: [Keystroke],
        dispatchPath: [DispatchNodeId]
    ) -> [Replay] {
        let (suffix, toReplay) = replayPrefix(input: input, dispatchPath: dispatchPath)
        var allReplay = toReplay
        if !suffix.isEmpty {
            allReplay.append(contentsOf: flushDispatch(input: suffix, dispatchPath: dispatchPath))
        }
        return allReplay
    }

    public func flush_dispatch(
        _ input: [Keystroke],
        _ dispatch_path: [DispatchNodeId]
    ) -> [Replay] {
        flushDispatch(input: input, dispatchPath: dispatch_path)
    }

    public func flushDispatchWithContextStack(
        input: [Keystroke],
        contextStack: [KeyContext]
    ) -> [Replay] {
        let (suffix, toReplay) = replayPrefixWithContextStack(input: input, contextStack: contextStack)
        var allReplay = toReplay
        if !suffix.isEmpty {
            allReplay.append(contentsOf: flushDispatchWithContextStack(input: suffix, contextStack: contextStack))
        }
        return allReplay
    }

    public func flush_dispatch_with_context_stack(
        _ input: [Keystroke],
        _ context_stack: [KeyContext]
    ) -> [Replay] {
        flushDispatchWithContextStack(input: input, contextStack: context_stack)
    }

    private func replayPrefix(
        input: [Keystroke],
        dispatchPath: [DispatchNodeId]
    ) -> (suffix: [Keystroke], toReplay: [Replay]) {
        var mutableInput = input
        var toReplay: [Replay] = []

        for last in (0..<mutableInput.count).reversed() {
            let prefix = Array(mutableInput[0...last])
            let (bindings, _, _) = bindingsForInput(prefix, dispatchPath: dispatchPath)
            if !bindings.isEmpty {
                let matching = Array(mutableInput[0...last])
                mutableInput.removeSubrange(0...last)
                toReplay.append(Replay(keystroke: matching.last!, bindings: bindings))
                break
            }
        }

        if toReplay.isEmpty && !mutableInput.isEmpty {
            toReplay.append(Replay(keystroke: mutableInput.removeFirst(), bindings: []))
        }

        return (mutableInput, toReplay)
    }

    private func replayPrefixWithContextStack(
        input: [Keystroke],
        contextStack: [KeyContext]
    ) -> (suffix: [Keystroke], toReplay: [Replay]) {
        var mutableInput = input
        var toReplay: [Replay] = []

        for last in (0..<mutableInput.count).reversed() {
            let prefix = Array(mutableInput[0...last])
            let (bindings, _) = keymap.bindingsForInput(prefix, contextStack)
            if !bindings.isEmpty {
                let matching = Array(mutableInput[0...last])
                mutableInput.removeSubrange(0...last)
                toReplay.append(Replay(keystroke: matching.last!, bindings: bindings))
                break
            }
        }

        if toReplay.isEmpty && !mutableInput.isEmpty {
            toReplay.append(Replay(keystroke: mutableInput.removeFirst(), bindings: []))
        }

        return (mutableInput, toReplay)
    }

    public func dispatchPath(_ target: DispatchNodeId) -> [DispatchNodeId] {
        guard target.rawValue < nodes.count else { return [] }
        var path: [DispatchNodeId] = []
        var current: DispatchNodeId? = target
        while let node = current, node.rawValue < nodes.count {
            path.append(node)
            current = nodes[node.rawValue].parent
        }
        path.reverse()
        return path
    }

    public func dispatch_path(_ target: DispatchNodeId) -> [DispatchNodeId] {
        dispatchPath(target)
    }

    public func focusPath(_ focusId: FocusId) -> [FocusId] {
        var path: [FocusId] = []
        var current = focusableNodeIds[focusId]
        while let node = current {
            if let fId = nodes[node.rawValue].focusId {
                path.append(fId)
            }
            current = nodes[node.rawValue].parent
        }
        path.reverse()
        return path
    }

    public func focus_path(_ focusId: FocusId) -> [FocusId] {
        focusPath(focusId)
    }

    public func viewPathReversed(_ viewId: EntityId) -> [EntityId] {
        var result: [EntityId] = []
        var current = viewNodeIds[viewId]
        while let node = current {
            if let vId = nodes[node.rawValue].viewId {
                result.append(vId)
            }
            current = nodes[node.rawValue].parent
        }
        return result
    }

    public func view_path_reversed(_ viewId: EntityId) -> [EntityId] {
        viewPathReversed(viewId)
    }

    public func viewNodeId(_ viewId: EntityId) -> DispatchNodeId? {
        viewNodeIds[viewId]
    }

    public func view_node_id(_ viewId: EntityId) -> DispatchNodeId? {
        viewNodeId(viewId)
    }

    public func node(_ nodeId: DispatchNodeId) -> DispatchNode {
        guard nodeId.rawValue < nodes.count else {
            return DispatchNode()
        }
        return nodes[nodeId.rawValue]
    }

    public func focusableNodeId(_ target: FocusId) -> DispatchNodeId? {
        focusableNodeIds[target]
    }

    public func focusable_node_id(_ target: FocusId) -> DispatchNodeId? {
        focusableNodeId(target)
    }

    public func rootNodeId() -> DispatchNodeId {
        assert(!nodes.isEmpty)
        return DispatchNodeId(0)
    }

    public func root_node_id() -> DispatchNodeId {
        rootNodeId()
    }

    public func activeNodeId() -> DispatchNodeId? {
        nodeStack.last
    }

    public func active_node_id() -> DispatchNodeId? {
        activeNodeId()
    }
}
