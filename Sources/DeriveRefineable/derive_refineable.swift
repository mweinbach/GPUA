// Ported from: crates/refineable/derive_refineable/src/derive_refineable.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

/// Type-erased or concrete field descriptor for automatic structural refinement via KeyPaths.
/// Replaces upstream proc-macro `derive(Refineable)` with genuine pure-Swift KeyPath reflection.
public struct RefineableField<Target, Refinement>: Sendable {
    public let applyToTarget: @Sendable (inout Target, Refinement) -> Void
    public let applyToRefinement: @Sendable (inout Refinement, Refinement) -> Void
    public let isFieldEmpty: @Sendable (Refinement) -> Bool
    public let isFieldSuperset: @Sendable (Refinement, Refinement) -> Bool
    public let subtractField: @Sendable (Refinement, Refinement, inout Refinement) -> Void

    public init(
        applyToTarget: @escaping @Sendable (inout Target, Refinement) -> Void,
        applyToRefinement: @escaping @Sendable (inout Refinement, Refinement) -> Void,
        isFieldEmpty: @escaping @Sendable (Refinement) -> Bool,
        isFieldSuperset: @escaping @Sendable (Refinement, Refinement) -> Bool,
        subtractField: @escaping @Sendable (Refinement, Refinement, inout Refinement) -> Void
    ) {
        self.applyToTarget = applyToTarget
        self.applyToRefinement = applyToRefinement
        self.isFieldEmpty = isFieldEmpty
        self.isFieldSuperset = isFieldSuperset
        self.subtractField = subtractField
    }

    /// Creates a field refinement for an optional property where `Refinement` contains `Field?`.
    public static func scalar<Field: Equatable & Sendable>(
        target: (any WritableKeyPath<Target, Field> & Sendable),
        refinement: (any WritableKeyPath<Refinement, Field?> & Sendable)
    ) -> RefineableField<Target, Refinement> {
        RefineableField(
            applyToTarget: { tgt, ref in
                if let val = ref[keyPath: refinement] {
                    tgt[keyPath: target] = val
                }
            },
            applyToRefinement: { base, override in
                if let val = override[keyPath: refinement] {
                    base[keyPath: refinement] = val
                }
            },
            isFieldEmpty: { ref in
                ref[keyPath: refinement] == nil
            },
            isFieldSuperset: { a, b in
                guard let bVal = b[keyPath: refinement] else { return true }
                return a[keyPath: refinement] == bVal
            },
            subtractField: { a, b, result in
                if let aVal = a[keyPath: refinement], aVal != b[keyPath: refinement] {
                    result[keyPath: refinement] = aVal
                }
            }
        )
    }
}

/// A descriptor that encapsulates automatic structural refinement logic for a type.
public struct RefineableDescriptor<Target, Refinement>: Sendable {
    public let fields: [RefineableField<Target, Refinement>]

    public init(fields: [RefineableField<Target, Refinement>]) {
        self.fields = fields
    }

    public func refine(target: inout Target, from refinement: Refinement) {
        for field in fields {
            field.applyToTarget(&target, refinement)
        }
    }

    public func refine(base: inout Refinement, from override: Refinement) {
        for field in fields {
            field.applyToRefinement(&base, override)
        }
    }

    public func isEmpty(_ refinement: Refinement) -> Bool {
        for field in fields {
            if !field.isFieldEmpty(refinement) {
                return false
            }
        }
        return true
    }

    public func isSuperset(_ a: Refinement, of b: Refinement) -> Bool {
        for field in fields {
            if !field.isFieldSuperset(a, b) {
                return false
            }
        }
        return true
    }

    public func subtract(_ a: Refinement, from b: Refinement, into initial: Refinement) -> Refinement {
        var result = initial
        for field in fields {
            field.subtractField(a, b, &result)
        }
        return result
    }
}
