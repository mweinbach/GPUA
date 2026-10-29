// Ported from: crates/gpui_macros/src/derive_action.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Describes metadata for an action derived via `#[derive(Action)]` or pure-Swift Action helpers.
public struct ActionDescriptor: Sendable, Equatable, Hashable {
    public var name: String
    public var namespace: String?
    public var deprecatedAliases: [String]
    public var noJson: Bool
    public var documentation: String?

    public init(
        name: String,
        namespace: String? = nil,
        deprecatedAliases: [String] = [],
        noJson: Bool = false,
        documentation: String? = nil
    ) {
        self.name = name
        self.namespace = namespace
        self.deprecatedAliases = deprecatedAliases
        self.noJson = noJson
        self.documentation = documentation
    }

    /// Full qualified name (e.g. `editor.Save` or `workspace.Close`).
    public var qualifiedName: String {
        if let ns = namespace, !ns.isEmpty {
            return "\(ns).\(name)"
        }
        return name
    }
}

/// Helper protocol for types that carry action metadata.
public protocol ActionMetadata: Sendable {
    static var actionDescriptor: ActionDescriptor { get }
}

/// Helper to produce an `ActionDescriptor` from a type name and optional namespace.
public func defaultActionDescriptor<T>(
    for type: T.Type,
    namespace: String? = nil,
    deprecatedAliases: [String] = [],
    noJson: Bool = false,
    documentation: String? = nil
) -> ActionDescriptor {
    let rawName = String(describing: type)
    let cleanName = rawName.split(separator: "<").first.map(String.init) ?? rawName
    return ActionDescriptor(
        name: cleanName,
        namespace: namespace,
        deprecatedAliases: deprecatedAliases,
        noJson: noJson,
        documentation: documentation
    )
}
