// Ported from: crates/gpui_macros/src/register_action.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

public typealias ActionBuilder = @Sendable (Data?) throws -> (any Sendable)?

/// Thread-safe action registry matching upstream `register_action!` functionality.
// PORT NOTE: ActionRegistry uses NSLock to synchronize access across threads.
public final class ActionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [String: ActionDescriptor] = [:]
    private var builders: [String: ActionBuilder] = [:]

    public static let shared = ActionRegistry()

    public init() {}

    public func register(descriptor: ActionDescriptor, builder: ActionBuilder? = nil) {
        lock.withLock {
            descriptors[descriptor.qualifiedName] = descriptor
            for alias in descriptor.deprecatedAliases {
                descriptors[alias] = descriptor
            }
            if let b = builder {
                builders[descriptor.qualifiedName] = b
            }
        }
    }

    public func descriptor(for name: String) -> ActionDescriptor? {
        lock.withLock {
            descriptors[name]
        }
    }

    public func allActions() -> [ActionDescriptor] {
        lock.withLock {
            Array(descriptors.values)
        }
    }

    public func build(name: String, data: Data?) throws -> (any Sendable)? {
        let builder = lock.withLock {
            builders[name]
        }
        guard let b = builder else { return nil }
        return try b(data)
    }

    public func clear() {
        lock.withLock {
            descriptors.removeAll()
            builders.removeAll()
        }
    }
}

/// Convenience helper to register an action descriptor.
public func registerAction(
    _ descriptor: ActionDescriptor,
    builder: ActionBuilder? = nil
) {
    ActionRegistry.shared.register(descriptor: descriptor, builder: builder)
}
