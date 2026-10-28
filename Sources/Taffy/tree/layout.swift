// Ported from: src/tree/layout.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Whether we are performing a full layout, or we merely need to size the node
public enum RunMode: Sendable, Copyable, Hashable, Equatable {
    /// A full layout for this node and all children should be computed
    case performLayout
    /// The layout algorithm should be executed such that an accurate container size for the node can be determined.
    /// Layout steps that aren't necessary for determining the container size of the current node can be skipped.
    case computeSize
    /// This node should have a null layout set as it has been hidden (i.e. using `Display::None`)
    case performHiddenLayout
}

/// Whether styles should be taken into account when computing size
public enum SizingMode: Sendable, Copyable, Hashable, Equatable {
    /// Only content contributions should be taken into account
    case contentSize
    /// Inherent size styles should be taken into account in addition to content contributions
    case inherentSize
}

/// A set of margins that are available for collapsing with for block layout's margin collapsing
public struct CollapsibleMarginSet: Sendable, Copyable, Hashable, Equatable {
    /// The largest positive margin
    public var positive: Float
    /// The smallest negative margin (with largest absolute value)
    public var negative: Float

    @inlinable
    public init(positive: Float = 0.0, negative: Float = 0.0) {
        self.positive = positive
        self.negative = negative
    }

    /// A default margin set with no collapsible margins
    public static let ZERO = CollapsibleMarginSet(positive: 0.0, negative: 0.0)

    /// Create a set from a single margin
    @inlinable
    public static func fromMargin(_ margin: Float) -> CollapsibleMarginSet {
        if margin >= 0.0 {
            return CollapsibleMarginSet(positive: margin, negative: 0.0)
        } else {
            return CollapsibleMarginSet(positive: 0.0, negative: margin)
        }
    }

    /// Collapse a single margin with this set
    @inlinable
    public func collapseWithMargin(_ margin: Float) -> CollapsibleMarginSet {
        var copy = self
        if margin >= 0.0 {
            copy.positive = f32_max(copy.positive, margin)
        } else {
            copy.negative = f32_min(copy.negative, margin)
        }
        return copy
    }

    /// Collapse another margin set with this set
    @inlinable
    public func collapseWithSet(_ other: CollapsibleMarginSet) -> CollapsibleMarginSet {
        var copy = self
        copy.positive = f32_max(copy.positive, other.positive)
        copy.negative = f32_min(copy.negative, other.negative)
        return copy
    }

    /// Resolve the resultant margin from this set once all collapsible margins have been collapsed into it
    @inlinable
    public func resolve() -> Float {
        positive + negative
    }
}

/// An axis that layout algorithms can be requested to compute a size for
public enum RequestedAxis: Sendable, Copyable, Hashable, Equatable {
    /// The horizontal axis
    case horizontal
    /// The vertical axis
    case vertical
    /// Both axes
    case both

    @inlinable
    public init(_ axis: AbsoluteAxis) {
        switch axis {
        case .horizontal: self = .horizontal
        case .vertical: self = .vertical
        }
    }

    @inlinable
    public func toAbsoluteAxis() -> AbsoluteAxis? {
        switch self {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        case .both: return nil
        }
    }
}

/// A struct containing the inputs constraints/hints for laying out a node, which are passed in by the parent
public struct LayoutInput: Sendable, Copyable, Equatable {
    /// Whether we only need to know the Node's size, or whether full layout is needed
    public var runMode: RunMode
    /// Whether a Node's style sizes should be taken into account or ignored
    public var sizingMode: SizingMode
    /// Which axis we need the size of
    public var axis: RequestedAxis

    /// Known dimensions represent dimensions (width/height) which should be taken as fixed when performing layout.
    public var knownDimensions: Size<Float?>
    /// Parent size dimensions are intended to be used for percentage resolution.
    public var parentSize: Size<Float?>
    /// Available space represents an amount of space to layout into, and is used as a soft constraint
    public var availableSpace: Size<AvailableSpace>
    /// Specific to CSS Block layout. Used for correctly computing margin collapsing.
    public var verticalMarginsAreCollapsible: Line<Bool>

    @inlinable
    public init(
        runMode: RunMode,
        sizingMode: SizingMode,
        axis: RequestedAxis,
        knownDimensions: Size<Float?>,
        parentSize: Size<Float?>,
        availableSpace: Size<AvailableSpace>,
        verticalMarginsAreCollapsible: Line<Bool>
    ) {
        self.runMode = runMode
        self.sizingMode = sizingMode
        self.axis = axis
        self.knownDimensions = knownDimensions
        self.parentSize = parentSize
        self.availableSpace = availableSpace
        self.verticalMarginsAreCollapsible = verticalMarginsAreCollapsible
    }

    /// A LayoutInput that can be used to request hidden layout
    public static let HIDDEN = LayoutInput(
        runMode: .performHiddenLayout,
        sizingMode: .inherentSize,
        axis: .both,
        knownDimensions: Size<Float?>.NONE,
        parentSize: Size<Float?>.NONE,
        availableSpace: Size<AvailableSpace>.MAX_CONTENT,
        verticalMarginsAreCollapsible: Line.FALSE
    )
}

/// A struct containing the result of laying out a single node, which is returned up to the parent node
public struct LayoutOutput: Sendable, Copyable, Equatable {
    /// The size of the node
    public var size: Size<Float>
    /// The size of the content within the node
    public var contentSize: Size<Float>
    /// The first baseline of the node in each dimension, if any
    public var firstBaselines: Point<Float?>
    /// Top margin that can be collapsed with
    public var topMargin: CollapsibleMarginSet
    /// Bottom margin that can be collapsed with
    public var bottomMargin: CollapsibleMarginSet
    /// Whether margins can be collapsed through this node
    public var marginsCanCollapseThrough: Bool

    @inlinable
    public init(
        size: Size<Float>,
        contentSize: Size<Float> = Size.ZERO,
        firstBaselines: Point<Float?> = Point.NONE,
        topMargin: CollapsibleMarginSet = .ZERO,
        bottomMargin: CollapsibleMarginSet = .ZERO,
        marginsCanCollapseThrough: Bool = false
    ) {
        self.size = size
        self.contentSize = contentSize
        self.firstBaselines = firstBaselines
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.marginsCanCollapseThrough = marginsCanCollapseThrough
    }

    /// An all-zero `LayoutOutput` for hidden nodes
    public static let HIDDEN = LayoutOutput(
        size: Size.ZERO,
        contentSize: Size.ZERO,
        firstBaselines: Point.NONE,
        topMargin: .ZERO,
        bottomMargin: .ZERO,
        marginsCanCollapseThrough: false
    )

    /// A blank layout output
    public static let DEFAULT = LayoutOutput.HIDDEN

    /// Constructor to create a `LayoutOutput` from just the size and baselines
    @inlinable
    public static func fromSizesAndBaselines(
        size: Size<Float>,
        contentSize: Size<Float> = Size.ZERO,
        firstBaselines: Point<Float?> = Point.NONE
    ) -> LayoutOutput {
        LayoutOutput(
            size: size,
            contentSize: contentSize,
            firstBaselines: firstBaselines,
            topMargin: .ZERO,
            bottomMargin: .ZERO,
            marginsCanCollapseThrough: false
        )
    }

    /// Construct a `LayoutOutput` from just the container and content sizes
    @inlinable
    public static func fromSizes(size: Size<Float>, contentSize: Size<Float>) -> LayoutOutput {
        fromSizesAndBaselines(size: size, contentSize: contentSize, firstBaselines: Point.NONE)
    }

    /// Construct a `LayoutOutput` from just the container's size
    @inlinable
    public static func fromOuterSize(_ size: Size<Float>) -> LayoutOutput {
        fromSizes(size: size, contentSize: Size.ZERO)
    }
}

/// The final result of a layout algorithm for a single node
public struct Layout: Sendable, Copyable, Equatable {
    /// The relative ordering of the node
    public var order: UInt32
    /// The top-left corner of the node
    public var location: Point<Float>
    /// The width and height of the node
    public var size: Size<Float>
    /// The width and height of the content inside the node
    public var contentSize: Size<Float>
    /// The size of the scrollbars in each dimension
    public var scrollbarSize: Size<Float>
    /// The size of the borders of the node
    public var border: Rect<Float>
    /// The size of the padding of the node
    public var padding: Rect<Float>
    /// The size of the margin of the node
    public var margin: Rect<Float>

    @inlinable
    public init(
        order: UInt32 = 0,
        location: Point<Float> = Point.ZERO,
        size: Size<Float> = Size.ZERO,
        contentSize: Size<Float> = Size.ZERO,
        scrollbarSize: Size<Float> = Size.ZERO,
        border: Rect<Float> = Rect.ZERO,
        padding: Rect<Float> = Rect.ZERO,
        margin: Rect<Float> = Rect.ZERO
    ) {
        self.order = order
        self.location = location
        self.size = size
        self.contentSize = contentSize
        self.scrollbarSize = scrollbarSize
        self.border = border
        self.padding = padding
        self.margin = margin
    }

    /// Creates a new zero-[`Layout`].
    @inlinable
    public static func new() -> Layout {
        Layout()
    }

    /// Creates a new zero-[`Layout`] with the supplied `order` value.
    @inlinable
    public static func withOrder(_ order: UInt32) -> Layout {
        Layout(order: order)
    }

    /// Get the width of the node's content box
    @inlinable
    public func contentBoxWidth() -> Float {
        size.width - padding.left - padding.right - border.left - border.right
    }

    /// Get the height of the node's content box
    @inlinable
    public func contentBoxHeight() -> Float {
        size.height - padding.top - padding.bottom - border.top - border.bottom
    }

    /// Get the size of the node's content box
    @inlinable
    public func contentBoxSize() -> Size<Float> {
        Size(width: contentBoxWidth(), height: contentBoxHeight())
    }

    /// Get x offset of the node's content box relative to its parent's border box
    @inlinable
    public func contentBoxX() -> Float {
        location.x + border.left + padding.left
    }

    /// Get y offset of the node's content box relative to its parent's border box
    @inlinable
    public func contentBoxY() -> Float {
        location.y + border.top + padding.top
    }

    /// Return the scroll width of the node.
    @inlinable
    public func scrollWidth() -> Float {
        f32_max(
            0.0,
            contentSize.width + f32_min(scrollbarSize.width, size.width) - size.width + border.right
        )
    }

    /// Return the scroll height of the node.
    @inlinable
    public func scrollHeight() -> Float {
        f32_max(
            0.0,
            contentSize.height + f32_min(scrollbarSize.height, size.height) - size.height + border.bottom
        )
    }
}

/// The additional information from layout algorithm
public enum DetailedLayoutInfo: Sendable, Equatable {
    case none
}
