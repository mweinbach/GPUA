// Ported from: src/style/dimension.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// A unit of linear measurement: length or percentage.
///
/// This is commonly combined with `Rect`, `Point` and `Size<T>`.
public struct LengthPercentage: Sendable, Hashable {
    public var value: CompactLength

    @inlinable
    public init(_ value: CompactLength) {
        self.value = value
    }

    /// An absolute length in abstract units.
    @inlinable
    public static func length(_ val: Float) -> LengthPercentage {
        LengthPercentage(CompactLength.length(val))
    }

    /// A percentage length relative to the size of the containing block [0.0, 1.0].
    @inlinable
    public static func percent(_ val: Float) -> LengthPercentage {
        LengthPercentage(CompactLength.percent(val))
    }

    /// Create a LengthPercentage from a raw `CompactLength`.
    @inlinable
    public static func fromRaw(_ val: CompactLength) -> LengthPercentage {
        LengthPercentage(val)
    }

    /// Get the underlying `CompactLength` representation of the value.
    @inlinable
    public func intoRaw() -> CompactLength {
        self.value
    }
}

extension LengthPercentage: TaffyZero {
    public static let ZERO: LengthPercentage = LengthPercentage(CompactLength.ZERO)
}

extension LengthPercentage: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> LengthPercentage {
        .length(value)
    }
}

extension LengthPercentage: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> LengthPercentage {
        .percent(percent)
    }
}

/// A unit of linear measurement: length, percentage, or auto.
///
/// This is commonly combined with `Rect`, `Point` and `Size<T>`.
public struct LengthPercentageAuto: Sendable, Hashable {
    public var value: CompactLength

    @inlinable
    public init(_ value: CompactLength) {
        self.value = value
    }

    @inlinable
    public init(_ lp: LengthPercentage) {
        self.value = lp.value
    }

    /// An absolute length in abstract units.
    @inlinable
    public static func length(_ val: Float) -> LengthPercentageAuto {
        LengthPercentageAuto(CompactLength.length(val))
    }

    /// A percentage length relative to the size of the containing block [0.0, 1.0].
    @inlinable
    public static func percent(_ val: Float) -> LengthPercentageAuto {
        LengthPercentageAuto(CompactLength.percent(val))
    }

    /// The dimension should be automatically computed.
    @inlinable
    public static func auto() -> LengthPercentageAuto {
        LengthPercentageAuto(CompactLength.auto)
    }

    /// Create a LengthPercentageAuto from a raw `CompactLength`.
    @inlinable
    public static func fromRaw(_ val: CompactLength) -> LengthPercentageAuto {
        LengthPercentageAuto(val)
    }

    /// Get the underlying `CompactLength` representation of the value.
    @inlinable
    public func intoRaw() -> CompactLength {
        self.value
    }

    /// Returns:
    ///   - Some(length) for Length variants
    ///   - Some(resolved) using the provided context for Percent variants
    ///   - None for Auto variants
    @inlinable
    public func resolveToOption(
        context: Float,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        switch self.value {
        case .length(let len):
            return len
        case .percent(let p):
            return context * p
        case .auto:
            return nil
        default:
            return nil
        }
    }

    /// Returns true if value is LengthPercentageAuto::Auto
    @inlinable
    public var isAuto: Bool {
        self.value.isAuto
    }
}

extension LengthPercentageAuto: TaffyZero {
    public static let ZERO: LengthPercentageAuto = LengthPercentageAuto(CompactLength.ZERO)
}

extension LengthPercentageAuto: TaffyAuto {
    public static let AUTO: LengthPercentageAuto = LengthPercentageAuto(CompactLength.auto)
}

extension LengthPercentageAuto: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> LengthPercentageAuto {
        .length(value)
    }
}

extension LengthPercentageAuto: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> LengthPercentageAuto {
        .percent(percent)
    }
}

/// A unit of linear measurement: length, percentage, or auto.
///
/// This is commonly combined with `Rect`, `Point` and `Size<T>`.
public struct Dimension: Sendable, Hashable {
    public var value: CompactLength

    @inlinable
    public init(_ value: CompactLength) {
        self.value = value
    }

    @inlinable
    public init(_ lp: LengthPercentage) {
        self.value = lp.value
    }

    @inlinable
    public init(_ lpa: LengthPercentageAuto) {
        self.value = lpa.value
    }

    /// An absolute length in abstract units.
    @inlinable
    public static func length(_ val: Float) -> Dimension {
        Dimension(CompactLength.length(val))
    }

    /// A percentage length relative to the size of the containing block [0.0, 1.0].
    @inlinable
    public static func percent(_ val: Float) -> Dimension {
        Dimension(CompactLength.percent(val))
    }

    /// The dimension should be automatically computed.
    @inlinable
    public static func auto() -> Dimension {
        Dimension(CompactLength.auto)
    }

    /// Create a Dimension from a raw `CompactLength`.
    @inlinable
    public static func fromRaw(_ val: CompactLength) -> Dimension {
        Dimension(val)
    }

    /// Get the underlying `CompactLength` representation of the value.
    @inlinable
    public func intoRaw() -> CompactLength {
        self.value
    }

    /// Get Length value if value is Length variant
    @inlinable
    public func intoOption() -> Float? {
        if case .length(let len) = self.value {
            return len
        }
        return nil
    }

    /// Returns true if value is Auto
    @inlinable
    public var isAuto: Bool {
        self.value.isAuto
    }

    /// Get the raw `CompactLength` tag
    @inlinable
    public var tag: UInt {
        self.value.tag
    }

    /// Get the raw `CompactLength` value
    @inlinable
    public var numericValue: Float {
        self.value.value
    }
}

extension Dimension: TaffyZero {
    public static let ZERO: Dimension = Dimension(CompactLength.ZERO)
}

extension Dimension: TaffyAuto {
    public static let AUTO: Dimension = Dimension(CompactLength.auto)
}

extension Dimension: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Dimension {
        .length(value)
    }
}

extension Dimension: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Dimension {
        .percent(percent)
    }
}

extension Rect where T == Dimension {
    /// Create a new Rect with length values
    @inlinable
    public static func fromLength(start: Float, end: Float, top: Float, bottom: Float) -> Rect<Dimension> {
        Rect(
            left: Dimension.length(start),
            right: Dimension.length(end),
            top: Dimension.length(top),
            bottom: Dimension.length(bottom)
        )
    }

    /// Create a new Rect with percentage values
    @inlinable
    public static func fromPercent(start: Float, end: Float, top: Float, bottom: Float) -> Rect<Dimension> {
        Rect(
            left: Dimension.percent(start),
            right: Dimension.percent(end),
            top: Dimension.percent(top),
            bottom: Dimension.percent(bottom)
        )
    }
}
