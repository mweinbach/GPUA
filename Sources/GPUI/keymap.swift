// Ported from: crates/gpui/src/keymap.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// An opaque identifier of which version of the keymap is currently active.
/// The keymap's version is changed whenever bindings are added or removed.
@frozen
public struct KeymapVersion: Sendable, Equatable, Hashable, RawRepresentable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int = 0) {
        self.rawValue = rawValue
    }
}

/// Index of a binding within a keymap.
@frozen
public struct BindingIndex: Sendable, Equatable, Comparable, Hashable, RawRepresentable {
    public var rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: BindingIndex, rhs: BindingIndex) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

private func disabledBindingMatchesContext(
    disabledBinding: KeyBinding,
    binding: KeyBinding
) -> Bool {
    switch (disabledBinding.contextPredicate, binding.contextPredicate) {
    case (.none, _):
        return true
    case (.some, .none):
        return false
    case (.some(let disabledPredicate), .some(let predicate)):
        return disabledPredicate.isSuperset(of: predicate)
    }
}

private func bindingIsUnbound(
    disabledBinding: KeyBinding,
    binding: KeyBinding
) -> Bool {
    guard disabledBinding.keystrokes == binding.keystrokes else {
        return false
    }
    if let unbind = disabledBinding.action as? Unbind {
        return unbind.actionName.asString == binding.action.name
    }
    return false
}

/// A collection of key bindings for the user's application.
public struct Keymap: Sendable {
    private var _bindings: [KeyBinding] = []
    private var bindingIndicesByActionId: [ObjectIdentifier: [Int]] = [:]
    private var disabledBindingIndices: [Int] = []
    public private(set) var version: KeymapVersion = KeymapVersion(0)

    public init(bindings: [KeyBinding] = []) {
        addBindings(bindings)
    }

    /// Add more bindings to the keymap.
    public mutating func addBindings<T: Sequence<KeyBinding>>(_ newBindings: T) {
        for binding in newBindings {
            let actionId = ObjectIdentifier(type(of: binding.action))
            if isNoAction(binding.action) || isUnbind(binding.action) {
                disabledBindingIndices.append(_bindings.count)
            } else {
                bindingIndicesByActionId[actionId, default: []].append(_bindings.count)
            }
            _bindings.append(binding)
        }
        version.rawValue += 1
    }

    public mutating func add_bindings<T: Sequence<KeyBinding>>(_ newBindings: T) {
        addBindings(newBindings)
    }

    /// Reset this keymap to its initial state.
    public mutating func clear() {
        _bindings.removeAll()
        bindingIndicesByActionId.removeAll()
        disabledBindingIndices.removeAll()
        version.rawValue += 1
    }

    /// Array of all bindings, in the order they were added.
    public var bindings: [KeyBinding] {
        _bindings
    }

    /// Iterate over all bindings for the given action, in the order they were added.
    public func bindingsForAction(_ action: any Action) -> [KeyBinding] {
        let actionId = ObjectIdentifier(type(of: action))
        guard let indices = bindingIndicesByActionId[actionId] else {
            return []
        }

        return indices.compactMap { ix in
            let binding = _bindings[ix]
            if !binding.action.isEqual(to: action) {
                return nil
            }

            for disabledIx in disabledBindingIndices {
                if disabledIx > ix {
                    let disabledBinding = _bindings[disabledIx]
                    if disabledBinding.keystrokes != binding.keystrokes {
                        continue
                    }

                    if isNoAction(disabledBinding.action) {
                        if disabledBindingMatchesContext(disabledBinding: disabledBinding, binding: binding) {
                            return nil
                        }
                    } else if isUnbind(disabledBinding.action)
                                && disabledBindingMatchesContext(disabledBinding: disabledBinding, binding: binding)
                                && bindingIsUnbound(disabledBinding: disabledBinding, binding: binding) {
                        return nil
                    }
                }
            }

            return binding
        }
    }

    public func bindings_for_action(_ action: any Action) -> [KeyBinding] {
        bindingsForAction(action)
    }

    /// Returns all bindings that might match the input without checking context.
    public func allBindingsForInput(_ input: [Keystroke]) -> [KeyBinding] {
        _bindings.reversed().filter { binding in
            binding.matchKeystrokes(input) == false
        }
    }

    public func all_bindings_for_input(_ input: [Keystroke]) -> [KeyBinding] {
        allBindingsForInput(input)
    }

    /// Check if the given binding is enabled, given a certain key context.
    /// Returns the deepest depth at which the binding matches, or nil if it doesn't match.
    public func bindingEnabled(_ binding: KeyBinding, contexts: [KeyContext]) -> Int? {
        if let predicate = binding.contextPredicate {
            return predicate.depthOf(contexts)
        } else {
            return contexts.count
        }
    }

    public func binding_enabled(_ binding: KeyBinding, _ contexts: [KeyContext]) -> Int? {
        bindingEnabled(binding, contexts: contexts)
    }

    /// Returns a list of bindings that match the given input, and a boolean indicating whether
    /// or not more bindings might match if the input was longer.
    public func bindingsForInput(
        _ input: [any AsKeystroke],
        _ contextStack: [KeyContext]
    ) -> (bindings: [KeyBinding], hasPending: Bool) {
        var matchedBindings: [(depth: Int, index: BindingIndex, binding: KeyBinding)] = []
        var pendingBindings: [(index: BindingIndex, binding: KeyBinding)] = []

        for (ix, binding) in _bindings.enumerated().reversed() {
            guard let depth = bindingEnabled(binding, contexts: contextStack) else {
                continue
            }
            guard let pending = binding.matchKeystrokes(input) else {
                continue
            }

            if !pending {
                matchedBindings.append((depth: depth, index: BindingIndex(rawValue: ix), binding: binding))
            } else {
                pendingBindings.append((index: BindingIndex(rawValue: ix), binding: binding))
            }
        }

        matchedBindings.sort { a, b in
            if a.depth != b.depth {
                return a.depth > b.depth
            }
            return a.index > b.index
        }

        var result: [KeyBinding] = []
        var firstBindingIndex: BindingIndex?
        var unboundBindings: [KeyBinding] = []

        for (_, ix, binding) in matchedBindings {
            if isNoAction(binding.action) {
                // Only break if this is a user-defined NoAction binding (meta == 0)
                if let meta = binding.meta {
                    if meta.rawValue == 0 {
                        break
                    }
                } else {
                    break
                }
                continue
            }

            if isUnbind(binding.action) {
                unboundBindings.append(binding)
                continue
            }

            if unboundBindings.contains(where: { bindingIsUnbound(disabledBinding: $0, binding: binding) }) {
                continue
            }

            result.append(binding)
            if firstBindingIndex == nil {
                firstBindingIndex = ix
            }
        }

        var pendingSet = Set<[KeybindingKeystroke]>()
        for (ix, binding) in pendingBindings.reversed() {
            if let firstIx = firstBindingIndex, firstIx > ix {
                continue
            }
            if isNoAction(binding.action) || isUnbind(binding.action) {
                pendingSet.remove(binding.keystrokes)
                continue
            }
            pendingSet.insert(binding.keystrokes)
        }

        return (result, !pendingSet.isEmpty)
    }

    public func bindings_for_input(
        _ input: [any AsKeystroke],
        _ context_stack: [KeyContext]
    ) -> (bindings: [KeyBinding], hasPending: Bool) {
        bindingsForInput(input, context_stack)
    }

    /// Find the bindings that can follow the current input sequence.
    public func possibleNextBindingsForInput(
        _ input: [Keystroke],
        _ contextStack: [KeyContext]
    ) -> [KeyBinding] {
        var matches: [(depth: Int, index: BindingIndex, binding: KeyBinding)] = []

        for (ix, binding) in _bindings.enumerated().reversed() {
            guard let depth = bindingEnabled(binding, contexts: contextStack) else {
                continue
            }
            guard let pending = binding.matchKeystrokes(input) else {
                continue
            }
            if !pending || isNoAction(binding.action) || isUnbind(binding.action) {
                continue
            }
            matches.append((depth: depth, index: BindingIndex(rawValue: ix), binding: binding))
        }

        matches.sort { a, b in
            if a.depth != b.depth {
                return a.depth > b.depth
            }
            return a.index > b.index
        }

        return matches.map { $0.binding }
    }

    public func possible_next_bindings_for_input(
        _ input: [Keystroke],
        _ context_stack: [KeyContext]
    ) -> [KeyBinding] {
        possibleNextBindingsForInput(input, context_stack)
    }
}
