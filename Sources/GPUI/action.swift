// Ported from: crates/gpui/src/action.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation

/// Actions are used to implement keyboard-driven UI. When you declare an action, you can bind keys
/// to the action in the keymap and listeners for that action in the element tree.
public protocol Action: Sendable {
    /// Get the unique identifier name of this action type (e.g. "editor::MoveUp").
    static var name: String { get }

    /// A list of alternate, deprecated names for this action.
    static var deprecatedAliases: [String] { get }

    /// Returns the deprecation message for this action, if any.
    static var deprecationMessage: String? { get }

    /// The documentation for this action, if any.
    static var documentation: String? { get }

    /// Build this action from a JSON-compatible dictionary.
    static func build(json: [String: Any]) throws -> any Action

    /// Get the name of this action instance.
    var name: String { get }

    /// Do an equality check on this action and another type-erased action.
    func isEqual(to other: any Action) -> Bool

    /// Clone the action into an existential box.
    func boxedClone() -> any Action
}

extension Action {
    public var name: String {
        Self.name
    }

    public static var deprecatedAliases: [String] {
        []
    }

    public static var deprecationMessage: String? {
        nil
    }

    public static var documentation: String? {
        nil
    }

    public func boxedClone() -> any Action {
        self
    }

    /// Rust compatibility alias for partial_eq.
    public func partial_eq(_ other: any Action) -> Bool {
        isEqual(to: other)
    }
}

extension Action where Self: Equatable {
    public func isEqual(to other: any Action) -> Bool {
        guard let other = other as? Self else { return false }
        return self == other
    }
}

/// Unit actions take no parameters and provide a default empty initializer and builder.
public protocol UnitAction: Action, Equatable {
    init()
}

extension UnitAction {
    public static func build(json: [String: Any]) throws -> any Action {
        Self()
    }
}

/// Error type for dynamic action construction.
public enum ActionBuildError: Error, CustomStringConvertible, Sendable {
    /// Indicates that an action with this name has not been registered.
    case notFound(name: String)

    /// Indicates that an error occurred while building the action.
    case buildError(name: String, error: any Error)

    public var description: String {
        switch self {
        case .notFound(let name):
            return "Didn't find an action named \"\(name)\""
        case .buildError(let name, let error):
            return "Error while building action \"\(name)\": \(error)"
        }
    }
}

/// Dynamic action registry mapping action names and type IDs to dynamic builders.
// PORT NOTE: ActionRegistry synchronizes all mutable registry state via NSLock, matching upstream thread-safe action registration.
public final class ActionRegistry: @unchecked Sendable {
    // PORT NOTE: ActionData wraps dynamic build closures with type-erased JSON payloads protected by ActionRegistry.lock.
    private struct ActionData: @unchecked Sendable {
        let build: @Sendable ([String: Any]) throws -> any Action
    }

    private let lock = NSLock()
    private var byName: [String: ActionData] = [:]
    private var namesByTypeId: [ObjectIdentifier: String] = [:]
    private var allNames: [String] = []
    private var _deprecatedAliases: [String: String] = [:] // alias -> preferred name
    private var _deprecationMessages: [String: String] = [:] // action name -> deprecation message
    private var _documentation: [String: String] = [:] // action name -> documentation

    public init() {
        register(NoAction.self)
        register(Unbind.self)
    }

    /// Default registry with standard built-in actions registered.
    public static var `default`: ActionRegistry {
        ActionRegistry()
    }

    /// Register an Action type into the registry.
    public func register<A: Action>(_ type: A.Type) {
        lock.lock()
        defer { lock.unlock() }

        let name = type.name
        precondition(
            byName[name] == nil,
            "Action with name `\(name)` already registered"
        )

        let data = ActionData(build: { json in
            try type.build(json: json)
        })

        byName[name] = data
        namesByTypeId[ObjectIdentifier(type)] = name
        allNames.append(name)

        if let msg = type.deprecationMessage {
            _deprecationMessages[name] = msg
        }
        if let docs = type.documentation {
            _documentation[name] = docs
        }

        for alias in type.deprecatedAliases {
            precondition(
                byName[alias] == nil,
                "Action with name `\(alias)` already registered (specified in deprecatedAliases for `\(name)`)"
            )
            byName[alias] = data
            _deprecatedAliases[alias] = name
            allNames.append(alias)
        }
    }

    /// Construct an action based on its name and optional JSON parameters.
    public func buildAction(
        name: String,
        params: [String: Any]? = nil
    ) throws -> any Action {
        lock.lock()
        let data = byName[name]
        lock.unlock()

        guard let data else {
            throw ActionBuildError.notFound(name: name)
        }

        do {
            return try data.build(params ?? [:])
        } catch {
            throw ActionBuildError.buildError(name: name, error: error)
        }
    }

    /// Construct an action based on its type identifier.
    public func buildActionType(_ typeId: ObjectIdentifier) throws -> any Action {
        lock.lock()
        let name = namesByTypeId[typeId]
        lock.unlock()

        guard let name else {
            throw ActionBuildError.notFound(name: "\(typeId)")
        }

        return try buildAction(name: name, params: nil)
    }

    /// List of all registered action names and aliases.
    public func allActionNames() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return allNames
    }

    /// Mapping of deprecated aliases to canonical action names.
    public func deprecatedAliases() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return _deprecatedAliases
    }

    /// Mapping of action names to deprecation messages.
    public func deprecationMessages() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return _deprecationMessages
    }

    /// Mapping of action names to documentation.
    public func documentation() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return _documentation
    }
}

// MARK: - Control Actions

/// Action with special handling which unbinds the keybinding this is associated with,
/// if it is the highest precedence match.
public struct NoAction: UnitAction {
    public static let name = "zed::NoAction"

    public init() {}
}

/// Action with special handling which unbinds later bindings for the same keystrokes when they
/// dispatch the named action, regardless of that action's context.
public struct Unbind: Action, Equatable {
    public static let name = "zed::Unbind"
    public var actionName: SharedString

    public init(_ actionName: SharedString) {
        self.actionName = actionName
    }

    public static func build(json: [String: Any]) throws -> any Action {
        if let action = json["action"] as? String {
            return Unbind(SharedString(action))
        }
        if let actionName = json["actionName"] as? String {
            return Unbind(SharedString(actionName))
        }
        if let first = json.values.first as? String {
            return Unbind(SharedString(first))
        }
        throw ActionBuildError.buildError(
            name: name,
            error: NSError(
                domain: "GPUI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Missing action name in Unbind params"]
            )
        )
    }
}

/// Returns whether or not this action represents a removed key binding.
public func isNoAction(_ action: any Action) -> Bool {
    action is NoAction
}

/// Rust compatibility alias.
public func is_no_action(_ action: any Action) -> Bool {
    isNoAction(action)
}

/// Returns whether or not this action represents an unbind marker.
public func isUnbind(_ action: any Action) -> Bool {
    action is Unbind
}

/// Rust compatibility alias.
public func is_unbind(_ action: any Action) -> Bool {
    isUnbind(action)
}
