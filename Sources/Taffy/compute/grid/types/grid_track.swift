// Ported from: src/compute/grid/types/grid_track.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Whether a GridTrack represents an actual track or a gutter.
public enum GridTrackKind: Sendable, Hashable, Equatable {
    /// Track is an actual track
    case track
    /// Track is a gutter (aka grid line) (aka gap)
    case gutter
}

/// Internal sizing information for a single grid track (row/column)
/// Gutters between tracks are sized similarly to actual tracks, so they
/// are also represented by this struct
public struct GridTrack: Sendable, Equatable {
    /// Whether the track is a full track, a gutter, or a placeholder that has not yet been initialised
    public var kind: GridTrackKind

    /// Whether the track is a collapsed track/gutter. Collapsed tracks are effectively treated as if
    /// they don't exist for the purposes of grid sizing. Gutters between collapsed tracks are also collapsed.
    public var isCollapsed: Bool

    /// The minimum track sizing function of the track
    public var minTrackSizingFunction: MinTrackSizingFunction

    /// The maximum track sizing function of the track
    public var maxTrackSizingFunction: MaxTrackSizingFunction

    /// The distance of the start of the track from the start of the grid container
    public var offset: Float

    /// The size (width/height as applicable) of the track
    public var baseSize: Float

    /// A temporary scratch value when sizing tracks
    /// Note: can be infinity
    public var growthLimit: Float

    /// A temporary scratch value when sizing tracks. Is used as an additional amount to add to the
    /// estimate for the available space in the opposite axis when content sizing items
    public var contentAlignmentAdjustment: Float

    /// A temporary scratch value when "distributing space" to avoid clobbering planned increase variable
    public var itemIncurredIncrease: Float
    /// A temporary scratch value when "distributing space" to avoid clobbering the main variable
    public var baseSizePlannedIncrease: Float
    /// A temporary scratch value when "distributing space" to avoid clobbering the main variable
    public var growthLimitPlannedIncrease: Float
    /// A temporary scratch value when "distributing space"
    public var infinitelyGrowable: Bool

    public init(
        kind: GridTrackKind,
        minTrackSizingFunction: MinTrackSizingFunction,
        maxTrackSizingFunction: MaxTrackSizingFunction
    ) {
        self.kind = kind
        self.isCollapsed = false
        self.minTrackSizingFunction = minTrackSizingFunction
        self.maxTrackSizingFunction = maxTrackSizingFunction
        self.offset = 0.0
        self.baseSize = 0.0
        self.growthLimit = 0.0
        self.contentAlignmentAdjustment = 0.0
        self.itemIncurredIncrease = 0.0
        self.baseSizePlannedIncrease = 0.0
        self.growthLimitPlannedIncrease = 0.0
        self.infinitelyGrowable = false
    }

    /// Create new GridTrack representing an actual track (not a gutter)
    @inlinable
    public static func new(
        minTrackSizingFunction: MinTrackSizingFunction,
        maxTrackSizingFunction: MaxTrackSizingFunction
    ) -> GridTrack {
        GridTrack(
            kind: .track,
            minTrackSizingFunction: minTrackSizingFunction,
            maxTrackSizingFunction: maxTrackSizingFunction
        )
    }

    /// Create a new GridTrack representing a gutter
    @inlinable
    public static func gutter(size: LengthPercentage) -> GridTrack {
        let minSizing: MinTrackSizingFunction
        let maxSizing: MaxTrackSizingFunction
        switch size.value {
        case .length(let v):
            minSizing = .length(v)
            maxSizing = .length(v)
        case .percent(let p):
            minSizing = .percent(p)
            maxSizing = .percent(p)
        default:
            minSizing = .length(0.0)
            maxSizing = .length(0.0)
        }
        return GridTrack(
            kind: .gutter,
            minTrackSizingFunction: minSizing,
            maxTrackSizingFunction: maxSizing
        )
    }

    /// Mark a GridTrack as collapsed. Also sets both of the track's sizing functions
    /// to fixed zero-sized sizing functions.
    @inlinable
    public mutating func collapse() {
        self.isCollapsed = true
        self.minTrackSizingFunction = .ZERO
        self.maxTrackSizingFunction = .ZERO
    }

    /// Returns true if the track is flexible (has a Flex MaxTrackSizingFunction), else false.
    @inlinable
    public var isFlexible: Bool {
        maxTrackSizingFunction.isFr
    }

    /// Returns true if the track uses a percentage sizing function.
    @inlinable
    public var usesPercentage: Bool {
        minTrackSizingFunction.usesPercentage || maxTrackSizingFunction.usesPercentage
    }

    /// Returns true if the track has an intrinsic min and or max sizing function
    @inlinable
    public var hasIntrinsicSizingFunction: Bool {
        minTrackSizingFunction.isIntrinsic || maxTrackSizingFunction.isIntrinsic
    }

    @inlinable
    public func fitContentLimit(axisAvailableGridSpace: Float?) -> Float {
        switch maxTrackSizingFunction.value {
        case .fitContentPx(let limit):
            return limit
        case .fitContentPercent(let limit):
            if let space = axisAvailableGridSpace {
                return space * limit
            } else {
                return .infinity
            }
        default:
            return .infinity
        }
    }

    @inlinable
    public func fitContentLimitedGrowthLimit(axisAvailableGridSpace: Float?) -> Float {
        Swift.min(growthLimit, fitContentLimit(axisAvailableGridSpace: axisAvailableGridSpace))
    }

    @inlinable
    public func flexFactor() -> Float {
        switch maxTrackSizingFunction.value {
        case .fr(let factor):
            return factor
        default:
            return 0.0
        }
    }
}
