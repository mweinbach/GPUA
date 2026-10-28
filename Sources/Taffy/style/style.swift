// Ported from: src/style/mod.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Sets the layout used for the children of this node
public enum Display: Sendable, Hashable {
    case block
    case flex
    case grid
    case none

    public static let `default`: Display = .flex

    @inlinable
    public init() {
        self = .flex
    }
}

/// An abstracted version of the CSS `display` property where any value other than "none" is represented by "normal"
public enum BoxGenerationMode: Sendable, Hashable {
    case normal
    case none

    public static let `default`: BoxGenerationMode = .normal

    @inlinable
    public init() {
        self = .normal
    }
}

/// The positioning strategy for this item.
public enum Position: Sendable, Hashable {
    case relative
    case absolute

    public static let `default`: Position = .relative

    @inlinable
    public init() {
        self = .relative
    }
}

/// Specifies whether size styles for this node are assigned to the node's "content box" or "border box"
public enum BoxSizing: Sendable, Hashable {
    case borderBox
    case contentBox

    public static let `default`: BoxSizing = .borderBox

    @inlinable
    public init() {
        self = .borderBox
    }
}

/// How children overflowing their container should affect layout
public enum Overflow: Sendable, Hashable {
    case visible
    case clip
    case hidden
    case scroll

    public static let `default`: Overflow = .visible

    @inlinable
    public init() {
        self = .visible
    }

    /// Returns true for overflow modes that contain their contents (hidden or scroll)
    @inlinable
    public var isScrollContainer: Bool {
        switch self {
        case .visible, .clip: return false
        case .hidden, .scroll: return true
        }
    }

    /// Returns Some(0.0) if overflow mode would cause automatic minimum size to be 0
    @inlinable
    public func maybeIntoAutomaticMinSize() -> Float? {
        isScrollContainer ? 0.0 : nil
    }
}

/// The core set of styles shared between all CSS layout nodes
public protocol CoreStyle: Sendable {
    associatedtype CustomIdent: Sendable & Hashable = String

    var boxGenerationMode: BoxGenerationMode { get }
    var isBlock: Bool { get }
    var isCompressibleReplaced: Bool { get }
    var boxSizing: BoxSizing { get }
    var overflow: Point<Overflow> { get }
    var scrollbarWidth: Float { get }
    var position: Position { get }
    var inset: Rect<LengthPercentageAuto> { get }
    var size: Size<Dimension> { get }
    var minSize: Size<Dimension> { get }
    var maxSize: Size<Dimension> { get }
    var aspectRatio: Float? { get }
    var margin: Rect<LengthPercentageAuto> { get }
    var padding: Rect<LengthPercentage> { get }
    var border: Rect<LengthPercentage> { get }
}

/// A typed representation of the CSS style information for a single node.
public struct Style<S: Sendable & Hashable>: Sendable, Hashable {
    public var display: Display
    public var itemIsTable: Bool
    public var itemIsReplaced: Bool
    public var boxSizing: BoxSizing

    // Overflow properties
    public var overflow: Point<Overflow>
    public var scrollbarWidth: Float

    // Position properties
    public var position: Position
    public var inset: Rect<LengthPercentageAuto>

    // Size properties
    public var size: Size<Dimension>
    public var minSize: Size<Dimension>
    public var maxSize: Size<Dimension>
    public var aspectRatio: Float?

    // Spacing properties
    public var margin: Rect<LengthPercentageAuto>
    public var padding: Rect<LengthPercentage>
    public var border: Rect<LengthPercentage>

    // Alignment properties
    public var alignItems: AlignItems?
    public var alignSelf: AlignSelf?
    public var justifyItems: AlignItems?
    public var justifySelf: AlignSelf?
    public var alignContent: AlignContent?
    public var justifyContent: JustifyContent?
    public var gap: Size<LengthPercentage>

    // Block container properties
    public var textAlign: TextAlign

    // Flexbox container properties
    public var flexDirection: FlexDirection
    public var flexWrap: FlexWrap

    // Flexbox item properties
    public var flexBasis: Dimension
    public var flexGrow: Float
    public var flexShrink: Float

    // Grid container properties
    public var gridTemplateRows: [GridTemplateComponent<S>]
    public var gridTemplateColumns: [GridTemplateComponent<S>]
    public var gridAutoRows: [TrackSizingFunction]
    public var gridAutoColumns: [TrackSizingFunction]
    public var gridAutoFlow: GridAutoFlow

    // Grid container named properties
    public var gridTemplateAreas: [GridTemplateArea<S>]
    public var gridTemplateColumnNames: [[S]]
    public var gridTemplateRowNames: [[S]]

    // Grid child properties
    public var gridRow: Line<GridPlacement<S>>
    public var gridColumn: Line<GridPlacement<S>>

    public init(
        display: Display = .flex,
        itemIsTable: Bool = false,
        itemIsReplaced: Bool = false,
        boxSizing: BoxSizing = .borderBox,
        overflow: Point<Overflow> = Point(x: .visible, y: .visible),
        scrollbarWidth: Float = 0.0,
        position: Position = .relative,
        inset: Rect<LengthPercentageAuto> = Rect(left: .auto(), right: .auto(), top: .auto(), bottom: .auto()),
        size: Size<Dimension> = Size(width: .auto(), height: .auto()),
        minSize: Size<Dimension> = Size(width: .auto(), height: .auto()),
        maxSize: Size<Dimension> = Size(width: .auto(), height: .auto()),
        aspectRatio: Float? = nil,
        margin: Rect<LengthPercentageAuto> = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0)),
        padding: Rect<LengthPercentage> = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0)),
        border: Rect<LengthPercentage> = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0)),
        alignItems: AlignItems? = nil,
        alignSelf: AlignSelf? = nil,
        justifyItems: AlignItems? = nil,
        justifySelf: AlignSelf? = nil,
        alignContent: AlignContent? = nil,
        justifyContent: JustifyContent? = nil,
        gap: Size<LengthPercentage> = Size(width: .length(0.0), height: .length(0.0)),
        textAlign: TextAlign = .auto,
        flexDirection: FlexDirection = .row,
        flexWrap: FlexWrap = .noWrap,
        flexBasis: Dimension = .auto(),
        flexGrow: Float = 0.0,
        flexShrink: Float = 1.0,
        gridTemplateRows: [GridTemplateComponent<S>] = [],
        gridTemplateColumns: [GridTemplateComponent<S>] = [],
        gridAutoRows: [TrackSizingFunction] = [],
        gridAutoColumns: [TrackSizingFunction] = [],
        gridAutoFlow: GridAutoFlow = .row,
        gridTemplateAreas: [GridTemplateArea<S>] = [],
        gridTemplateColumnNames: [[S]] = [],
        gridTemplateRowNames: [[S]] = [],
        gridRow: Line<GridPlacement<S>> = Line(start: .auto, end: .auto),
        gridColumn: Line<GridPlacement<S>> = Line(start: .auto, end: .auto)
    ) {
        self.display = display
        self.itemIsTable = itemIsTable
        self.itemIsReplaced = itemIsReplaced
        self.boxSizing = boxSizing
        self.overflow = overflow
        self.scrollbarWidth = scrollbarWidth
        self.position = position
        self.inset = inset
        self.size = size
        self.minSize = minSize
        self.maxSize = maxSize
        self.aspectRatio = aspectRatio
        self.margin = margin
        self.padding = padding
        self.border = border
        self.alignItems = alignItems
        self.alignSelf = alignSelf
        self.justifyItems = justifyItems
        self.justifySelf = justifySelf
        self.alignContent = alignContent
        self.justifyContent = justifyContent
        self.gap = gap
        self.textAlign = textAlign
        self.flexDirection = flexDirection
        self.flexWrap = flexWrap
        self.flexBasis = flexBasis
        self.flexGrow = flexGrow
        self.flexShrink = flexShrink
        self.gridTemplateRows = gridTemplateRows
        self.gridTemplateColumns = gridTemplateColumns
        self.gridAutoRows = gridAutoRows
        self.gridAutoColumns = gridAutoColumns
        self.gridAutoFlow = gridAutoFlow
        self.gridTemplateAreas = gridTemplateAreas
        self.gridTemplateColumnNames = gridTemplateColumnNames
        self.gridTemplateRowNames = gridTemplateRowNames
        self.gridRow = gridRow
        self.gridColumn = gridColumn
    }

    public static var DEFAULT: Style<S> {
        Style<S>()
    }
}

extension Style: CoreStyle {
    public typealias CustomIdent = S

    @inlinable
    public var boxGenerationMode: BoxGenerationMode {
        display == .none ? .none : .normal
    }

    @inlinable
    public var isBlock: Bool {
        display == .block
    }

    @inlinable
    public var isCompressibleReplaced: Bool {
        itemIsReplaced
    }
}

extension Style: BlockContainerStyle {}
extension Style: BlockItemStyle {}
extension Style: FlexboxContainerStyle {}
extension Style: FlexboxItemStyle {}
extension Style: GridContainerStyle {}
extension Style: GridItemStyle {}
