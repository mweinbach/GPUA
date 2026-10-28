// Ported from: crates/refineable/src/refineable.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

public protocol IsEmpty {
    var isEmpty: Bool { get }
}

public protocol DefaultInitializable {
    init()
}

/// A protocol for types that can be refined with partial updates.
///
/// The `Refineable` protocol enables hierarchical configuration patterns where a base
/// configuration can be selectively overridden by refinements. This is particularly useful
/// for styling, settings, and theme hierarchies.
public protocol Refineable: Sendable {
    associatedtype Refinement: Refineable & IsEmpty & DefaultInitializable where Refinement.Refinement == Refinement

    /// Applies the given refinement to this instance, modifying it in place.
    mutating func refine(with refinement: Refinement)

    /// Returns a new instance with the refinement applied.
    func refined(with refinement: Refinement) -> Self

    /// Returns `true` if this instance contains all values from the refinement.
    func isSuperset(of refinement: Refinement) -> Bool

    /// Returns a refinement that represents the difference between this instance and the given refinement.
    func subtract(_ refinement: Refinement) -> Refinement
}

extension Refineable {
    public func refined(with refinement: Refinement) -> Self {
        var copy = self
        copy.refine(with: refinement)
        return copy
    }
}

extension Refineable where Self: DefaultInitializable {
    /// Creates an instance from a cascade by merging all refinements atop the default value.
    public static func fromCascade(_ cascade: Cascade<Self>) -> Self {
        Self().refined(with: cascade.merged())
    }
}

/// A handle to a specific slot in a cascade.
public struct CascadeSlot: Hashable, Sendable {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }
}

/// A cascade of refinements that can be merged in priority order.
///
/// A cascade maintains a sequence of optional refinements where later entries
/// take precedence over earlier ones. The first slot (index 0) is always the
/// base refinement and is guaranteed to be present.
public struct Cascade<S: Refineable>: Sendable where S.Refinement: Sendable {
    private var slots: [S.Refinement?]

    public init() {
        self.slots = [S.Refinement()]
    }

    /// Reserves a new slot in the cascade and returns a handle to it.
    public mutating func reserve() -> CascadeSlot {
        slots.append(nil)
        return CascadeSlot(index: slots.count - 1)
    }

    /// Accesses the base refinement (slot 0).
    public var base: S.Refinement {
        get {
            slots[0] ?? S.Refinement()
        }
        set {
            slots[0] = newValue
        }
    }

    /// Sets the refinement for a specific slot in the cascade.
    public mutating func set(_ slot: CascadeSlot, _ refinement: S.Refinement?) {
        guard slot.index < slots.count else { return }
        slots[slot.index] = refinement
    }

    /// Merges all refinements in the cascade into a single refinement.
    ///
    /// Refinements are applied in order, with later slots taking precedence.
    /// Empty slots (`nil`) are skipped during merging.
    public func merged() -> S.Refinement {
        var merged = slots[0] ?? S.Refinement()
        for i in 1..<slots.count {
            if let ref = slots[i], !ref.isEmpty {
                merged.refine(with: ref)
            }
        }
        return merged
    }
}
