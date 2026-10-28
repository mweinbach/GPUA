// Ported from: src/style/flex.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Controls whether flex items are forced onto one line or can wrap onto multiple lines.
///
/// Defaults to `FlexWrap.noWrap`.
///
/// [Specification](https://www.w3.org/TR/css-flexbox-1/#flex-wrap-property)
public enum FlexWrap: Sendable, Hashable {
    /// Items will not wrap and stay on a single line
    case noWrap
    /// Items will wrap according to this item's `FlexDirection`
    case wrap
    /// Items will wrap in the opposite direction to this item's `FlexDirection`
    case wrapReverse

    public static let `default`: FlexWrap = .noWrap

    @inlinable
    public init() {
        self = .noWrap
    }
}

/// The direction of the flexbox layout main axis.
///
/// There are always two perpendicular layout axes: main (or primary) and cross (or secondary).
/// Adding items will cause them to be positioned adjacent to each other along the main axis.
/// By varying this value throughout your tree, you can create complex axis-aligned layouts.
///
/// Items are always aligned relative to the cross axis, and justified relative to the main axis.
///
/// The default behavior is `FlexDirection.row`.
///
/// [Specification](https://www.w3.org/TR/css-flexbox-1/#flex-direction-property)
public enum FlexDirection: Sendable, Hashable {
    /// Defines +x as the main axis
    /// Items will be added from left to right in a row.
    case row
    /// Defines +y as the main axis
    /// Items will be added from top to bottom in a column.
    case column
    /// Defines -x as the main axis
    /// Items will be added from right to left in a row.
    case rowReverse
    /// Defines -y as the main axis
    /// Items will be added from bottom to top in a column.
    case columnReverse

    public static let `default`: FlexDirection = .row

    @inlinable
    public init() {
        self = .row
    }

    /// Is the direction `FlexDirection.row` or `FlexDirection.rowReverse`?
    @inlinable
    public var isRow: Bool {
        switch self {
        case .row, .rowReverse: return true
        case .column, .columnReverse: return false
        }
    }

    /// Is the direction `FlexDirection.column` or `FlexDirection.columnReverse`?
    @inlinable
    public var isColumn: Bool {
        switch self {
        case .column, .columnReverse: return true
        case .row, .rowReverse: return false
        }
    }

    /// Is the direction `FlexDirection.rowReverse` or `FlexDirection.columnReverse`?
    @inlinable
    public var isReverse: Bool {
        switch self {
        case .rowReverse, .columnReverse: return true
        case .row, .column: return false
        }
    }

    /// The `AbsoluteAxis` that corresponds to the main axis
    @inlinable
    public var mainAxis: AbsoluteAxis {
        switch self {
        case .row, .rowReverse: return .horizontal
        case .column, .columnReverse: return .vertical
        }
    }

    /// The `AbsoluteAxis` that corresponds to the cross axis
    @inlinable
    public var crossAxis: AbsoluteAxis {
        switch self {
        case .row, .rowReverse: return .vertical
        case .column, .columnReverse: return .horizontal
        }
    }
}

/// The set of styles required for a Flexbox container
public protocol FlexboxContainerStyle: CoreStyle {
    /// Which direction does the main axis flow in?
    var flexDirection: FlexDirection { get }
    /// Should elements wrap, or stay in a single line?
    var flexWrap: FlexWrap { get }
    /// How large should the gaps between items in a grid or flex container be?
    var gap: Size<LengthPercentage> { get }
    /// How should content contained within this item be aligned in the cross/block axis
    var alignContent: AlignContent? { get }
    /// How this node's children aligned in the cross/block axis?
    var alignItems: AlignItems? { get }
    /// How this node's children should be aligned in the inline axis
    var justifyContent: JustifyContent? { get }
}

/// The set of styles required for a Flexbox item (child of a Flexbox container)
public protocol FlexboxItemStyle: CoreStyle {
    /// Sets the initial main axis size of the item
    var flexBasis: Dimension { get }
    /// The relative rate at which this item grows when it is expanding to fill space
    var flexGrow: Float { get }
    /// The relative rate at which this item shrinks when it is contracting to fit into space
    var flexShrink: Float { get }
    /// How this node should be aligned in the cross/block axis
    var alignSelf: AlignSelf? { get }
}
