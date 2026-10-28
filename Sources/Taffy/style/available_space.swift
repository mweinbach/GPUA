// Ported from: src/style/available_space.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The amount of space available to a node in a given axis
/// <https://www.w3.org/TR/css-sizing-3/#available>
public enum AvailableSpace: Sendable, Hashable {
    /// The amount of space available is the specified number of pixels
    case definite(Float)
    /// The amount of space available is indefinite and the node should be laid out under a min-content constraint
    case minContent
    /// The amount of space available is indefinite and the node should be laid out under a max-content constraint
    case maxContent

    /// Returns true for definite values, else false
    @inlinable
    public var isDefinite: Bool {
        if case .definite = self { return true }
        return false
    }

    /// Convert to Option
    /// Definite values become Some(value). Constraints become None.
    @inlinable
    public func intoOption() -> Float? {
        switch self {
        case .definite(let val): return val
        case .minContent, .maxContent: return nil
        }
    }

    /// Return the definite value or a default value
    @inlinable
    public func unwrapOr(_ defaultValue: Float) -> Float {
        intoOption() ?? defaultValue
    }

    /// Return the definite value. Precondition failure if not definite.
    @inlinable
    public func unwrap() -> Float {
        guard let val = intoOption() else {
            fatalError("Called AvailableSpace.unwrap() on non-definite value")
        }
        return val
    }

    /// Return self if definite or a default value
    @inlinable
    public func or(_ defaultValue: AvailableSpace) -> AvailableSpace {
        if case .definite = self { return self }
        return defaultValue
    }

    /// Return self if definite or the result of the default value callback
    @inlinable
    public func orElse(_ defaultCb: () -> AvailableSpace) -> AvailableSpace {
        if case .definite = self { return self }
        return defaultCb()
    }

    /// Return the definite value or the result of the default value callback
    @inlinable
    public func unwrapOrElse(_ defaultCb: () -> Float) -> Float {
        intoOption() ?? defaultCb()
    }

    /// If passed value is Some then return AvailableSpace::Definite containing that value, else return self
    @inlinable
    public func maybeSet(_ value: Float?) -> AvailableSpace {
        guard let val = value else { return self }
        return .definite(val)
    }

    /// If definite then apply mapFunction to value, else return self
    @inlinable
    public func mapDefiniteValue(_ mapFunction: (Float) -> Float) -> AvailableSpace {
        switch self {
        case .definite(let val): return .definite(mapFunction(val))
        case .minContent, .maxContent: return self
        }
    }

    /// Compute free_space given the passed used_space
    @inlinable
    public func computeFreeSpace(usedSpace: Float) -> Float {
        switch self {
        case .maxContent: return Float.infinity
        case .minContent: return 0.0
        case .definite(let available): return available - usedSpace
        }
    }

    /// Compare equality with another AvailableSpace, treating definite values
    /// that are within Float.ulpOfOne (or Float.leastNonzeroMagnitude) as equal
    @inlinable
    public func isRoughlyEqual(to other: AvailableSpace) -> Bool {
        switch (self, other) {
        case (.definite(let a), .definite(let b)):
            return abs(a - b) < Float.ulpOfOne
        case (.minContent, .minContent):
            return true
        case (.maxContent, .maxContent):
            return true
        default:
            return false
        }
    }
}

extension AvailableSpace: TaffyZero {
    public static let ZERO: AvailableSpace = .definite(0.0)
}

extension AvailableSpace: TaffyMaxContent {
    public static let MAX_CONTENT: AvailableSpace = .maxContent
}

extension AvailableSpace: TaffyMinContent {
    public static let MIN_CONTENT: AvailableSpace = .minContent
}

extension AvailableSpace: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> AvailableSpace {
        .definite(value)
    }
}

extension AvailableSpace: ExpressibleByFloatLiteral {
    @inlinable
    public init(floatLiteral value: Float) {
        self = .definite(value)
    }
}

extension AvailableSpace {
    @inlinable
    public init(_ value: Float) {
        self = .definite(value)
    }

    @inlinable
    public init(_ option: Float?) {
        if let val = option {
            self = .definite(val)
        } else {
            self = .maxContent
        }
    }
}

extension Size where T == AvailableSpace {
    /// Convert `Size<AvailableSpace>` into `Size<Option<Float>>`
    @inlinable
    public func intoOptions() -> Size<Float?> {
        Size<Float?>(width: self.width.intoOption(), height: self.height.intoOption())
    }

    /// If passed value is Some then return AvailableSpace::Definite containing that value, else return self
    @inlinable
    public func maybeSet(_ value: Size<Float?>) -> Size<AvailableSpace> {
        Size<AvailableSpace>(
            width: self.width.maybeSet(value.width),
            height: self.height.maybeSet(value.height)
        )
    }
}
