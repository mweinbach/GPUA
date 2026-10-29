// Ported from: crates/gpui_macros/src/derive_inspector_reflection.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Describes an inspectable property discovered by inspector reflection.
public struct InspectorProperty: Sendable, Equatable, Hashable {
    public var name: String
    public var category: String
    public var typeDescription: String

    public init(name: String, category: String = "general", typeDescription: String = "") {
        self.name = name
        self.category = category
        self.typeDescription = typeDescription
    }
}

/// Registry for inspectable properties generated or registered for GPUI elements and styles.
// PORT NOTE: InspectorReflectionRegistry uses NSLock to synchronize property registration.
public final class InspectorReflectionRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var propertiesByType: [String: [InspectorProperty]] = [:]

    public static let shared = InspectorReflectionRegistry()

    public init() {}

    public func registerProperties(_ properties: [InspectorProperty], forTypeName typeName: String) {
        lock.withLock {
            var existing = propertiesByType[typeName] ?? []
            existing.append(contentsOf: properties)
            propertiesByType[typeName] = existing
        }
    }

    public func properties(forTypeName typeName: String) -> [InspectorProperty] {
        lock.withLock {
            propertiesByType[typeName] ?? []
        }
    }

    public func allRegisteredTypes() -> [String] {
        lock.withLock {
            Array(propertiesByType.keys)
        }
    }

    public func clear() {
        lock.withLock {
            propertiesByType.removeAll()
        }
    }
}
