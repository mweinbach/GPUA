// Ported from: src/style/compact_length.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

// PORT NOTE: CompactLength represented as idiomatic Swift enum instead of raw tagged pointer
// for type safety and strict concurrency.

/// A representation of a length as a compact value.
/// Wrapped by types in the `dimension` and `grid` modules.
public enum CompactLength: Sendable, Hashable {
    /// An absolute length in abstract units
    case length(Float)
    /// A percentage length relative to the containing block [0.0, 1.0]
    case percent(Float)
    /// Automatically computed dimension
    case auto
    /// The dimension as a fraction of the total available grid space (`fr` units in CSS)
    case fr(Float)
    /// Smallest size that can fit contents with all soft line-wrapping taken
    case minContent
    /// Smallest size that can fit contents with no soft line-wrapping taken
    case maxContent
    /// Fit content with px limit
    case fitContentPx(Float)
    /// Fit content with percent limit
    case fitContentPercent(Float)

    /// The tag indicating a length value
    public static let LENGTH_TAG: UInt = 0b0000_0001
    /// The tag indicating a percentage value
    public static let PERCENT_TAG: UInt = 0b0000_0010
    /// The tag indicating an auto value
    public static let AUTO_TAG: UInt = 0b0000_0011
    /// The tag indicating an fr value
    public static let FR_TAG: UInt = 0b0000_0100
    /// The tag indicating a min-content value
    public static let MIN_CONTENT_TAG: UInt = 0b0000_0111
    /// The tag indicating a max-content value
    public static let MAX_CONTENT_TAG: UInt = 0b0000_1111
    /// The tag indicating a fit-content value with px limit
    public static let FIT_CONTENT_PX_TAG: UInt = 0b0001_0111
    /// The tag indicating a fit-content value with percent limit
    public static let FIT_CONTENT_PERCENT_TAG: UInt = 0b0001_1111



    /// The size should be the min-content size.
    @inlinable
    public static func min_content() -> CompactLength {
        .minContent
    }

    /// The size should be the max-content size.
    @inlinable
    public static func max_content() -> CompactLength {
        .maxContent
    }

    /// The size should be computed according to the fit content formula with px limit.
    @inlinable
    public static func fit_content_px(_ limit: Float) -> CompactLength {
        .fitContentPx(limit)
    }

    /// The size should be computed according to the fit content formula with percent limit.
    @inlinable
    public static func fit_content_percent(_ limit: Float) -> CompactLength {
        .fitContentPercent(limit)
    }

    /// Get the primary tag
    @inlinable
    public var tag: UInt {
        switch self {
        case .length: return Self.LENGTH_TAG
        case .percent: return Self.PERCENT_TAG
        case .auto: return Self.AUTO_TAG
        case .fr: return Self.FR_TAG
        case .minContent: return Self.MIN_CONTENT_TAG
        case .maxContent: return Self.MAX_CONTENT_TAG
        case .fitContentPx: return Self.FIT_CONTENT_PX_TAG
        case .fitContentPercent: return Self.FIT_CONTENT_PERCENT_TAG
        }
    }

    /// Get the numeric value associated with the `CompactLength`
    @inlinable
    public var value: Float {
        switch self {
        case .length(let v), .percent(let v), .fitContentPx(let v), .fitContentPercent(let v), .fr(let v):
            return v
        case .auto, .minContent, .maxContent:
            return 0.0
        }
    }

    /// Zero length
    public static let ZERO: CompactLength = .length(0.0)

    /// Returns true if the value is 0 px
    @inlinable
    public var isZero: Bool {
        if case .length(let val) = self {
            return val == 0.0
        }
        return false
    }

    /// Returns true if the value is a length or percentage value
    @inlinable
    public var isLengthOrPercentage: Bool {
        switch self {
        case .length, .percent: return true
        default: return false
        }
    }

    /// Returns true if the value is auto
    @inlinable
    public var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }

    /// Returns true if the value is min-content
    @inlinable
    public var isMinContent: Bool {
        if case .minContent = self { return true }
        return false
    }

    /// Returns true if the value is max-content
    @inlinable
    public var isMaxContent: Bool {
        if case .maxContent = self { return true }
        return false
    }

    /// Returns true if the value is a fit-content(...) value
    @inlinable
    public var isFitContent: Bool {
        switch self {
        case .fitContentPx, .fitContentPercent: return true
        default: return false
        }
    }

    /// Returns true if the value is max-content or a fit-content(...) value
    @inlinable
    public var isMaxOrFitContent: Bool {
        switch self {
        case .maxContent, .fitContentPx, .fitContentPercent: return true
        default: return false
        }
    }

    /// Returns true if the max track sizing function is MaxContent, FitContent or Auto
    @inlinable
    public var isMaxContentAlike: Bool {
        switch self {
        case .auto, .maxContent, .fitContentPx, .fitContentPercent: return true
        default: return false
        }
    }

    /// Returns true if the min track sizing function is MinContent or MaxContent
    @inlinable
    public var isMinOrMaxContent: Bool {
        switch self {
        case .minContent, .maxContent: return true
        default: return false
        }
    }

    /// Returns true if the value is auto, min-content, max-content, or fit-content(...)
    @inlinable
    public var isIntrinsic: Bool {
        switch self {
        case .auto, .minContent, .maxContent, .fitContentPx, .fitContentPercent: return true
        default: return false
        }
    }

    /// Returns true if the value is an fr value
    @inlinable
    public var isFr: Bool {
        if case .fr = self { return true }
        return false
    }

    /// Whether the track sizing functions depends on the size of the parent node
    @inlinable
    public var usesPercentage: Bool {
        switch self {
        case .percent, .fitContentPercent: return true
        default: return false
        }
    }

    /// Resolve percentage values against the passed parent_size, returning Some(value)
    /// Non-percentage values always return None.
    @inlinable
    public func resolvedPercentageSize(
        parentSize: Float,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        switch self {
        case .percent(let p):
            return p * parentSize
        default:
            return nil
        }
    }
}
