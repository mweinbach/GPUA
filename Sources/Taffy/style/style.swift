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

// PORT NOTE: StyleStorage is an internal COW storage class guarded by value semantics to reduce stack size on deep recursion.
final class StyleStorage<S: Sendable & Hashable>: @unchecked Sendable, Hashable {
    var display: Display
    var itemIsTable: Bool
    var itemIsReplaced: Bool
    var boxSizing: BoxSizing
    var overflow: Point<Overflow>
    var scrollbarWidth: Float
    var position: Position
    var inset: Rect<LengthPercentageAuto>
    var size: Size<Dimension>
    var minSize: Size<Dimension>
    var maxSize: Size<Dimension>
    var aspectRatio: Float?
    var margin: Rect<LengthPercentageAuto>
    var padding: Rect<LengthPercentage>
    var border: Rect<LengthPercentage>
    var alignItems: AlignItems?
    var alignSelf: AlignSelf?
    var justifyItems: AlignItems?
    var justifySelf: AlignSelf?
    var alignContent: AlignContent?
    var justifyContent: JustifyContent?
    var gap: Size<LengthPercentage>
    var textAlign: TextAlign
    var flexDirection: FlexDirection
    var flexWrap: FlexWrap
    var flexBasis: Dimension
    var flexGrow: Float
    var flexShrink: Float
    var gridTemplateRows: [GridTemplateComponent<S>]
    var gridTemplateColumns: [GridTemplateComponent<S>]
    var gridAutoRows: [TrackSizingFunction]
    var gridAutoColumns: [TrackSizingFunction]
    var gridAutoFlow: GridAutoFlow
    var gridTemplateAreas: [GridTemplateArea<S>]
    var gridTemplateColumnNames: [[S]]
    var gridTemplateRowNames: [[S]]
    var gridRow: Line<GridPlacement<S>>
    var gridColumn: Line<GridPlacement<S>>

    init() {
        self.display = .flex
        self.itemIsTable = false
        self.itemIsReplaced = false
        self.boxSizing = .borderBox
        self.overflow = Point(x: .visible, y: .visible)
        self.scrollbarWidth = 0.0
        self.position = .relative
        self.inset = Rect(left: .auto(), right: .auto(), top: .auto(), bottom: .auto())
        self.size = Size(width: .auto(), height: .auto())
        self.minSize = Size(width: .auto(), height: .auto())
        self.maxSize = Size(width: .auto(), height: .auto())
        self.aspectRatio = nil
        self.margin = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0))
        self.padding = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0))
        self.border = Rect(left: .length(0.0), right: .length(0.0), top: .length(0.0), bottom: .length(0.0))
        self.alignItems = nil
        self.alignSelf = nil
        self.justifyItems = nil
        self.justifySelf = nil
        self.alignContent = nil
        self.justifyContent = nil
        self.gap = Size(width: .length(0.0), height: .length(0.0))
        self.textAlign = .auto
        self.flexDirection = .row
        self.flexWrap = .noWrap
        self.flexBasis = .auto()
        self.flexGrow = 0.0
        self.flexShrink = 1.0
        self.gridTemplateRows = []
        self.gridTemplateColumns = []
        self.gridAutoRows = []
        self.gridAutoColumns = []
        self.gridAutoFlow = .row
        self.gridTemplateAreas = []
        self.gridTemplateColumnNames = []
        self.gridTemplateRowNames = []
        self.gridRow = Line(start: .auto, end: .auto)
        self.gridColumn = Line(start: .auto, end: .auto)
    }

    init(
        display: Display,
        itemIsTable: Bool,
        itemIsReplaced: Bool,
        boxSizing: BoxSizing,
        overflow: Point<Overflow>,
        scrollbarWidth: Float,
        position: Position,
        inset: Rect<LengthPercentageAuto>,
        size: Size<Dimension>,
        minSize: Size<Dimension>,
        maxSize: Size<Dimension>,
        aspectRatio: Float?,
        margin: Rect<LengthPercentageAuto>,
        padding: Rect<LengthPercentage>,
        border: Rect<LengthPercentage>,
        alignItems: AlignItems?,
        alignSelf: AlignSelf?,
        justifyItems: AlignItems?,
        justifySelf: AlignSelf?,
        alignContent: AlignContent?,
        justifyContent: JustifyContent?,
        gap: Size<LengthPercentage>,
        textAlign: TextAlign,
        flexDirection: FlexDirection,
        flexWrap: FlexWrap,
        flexBasis: Dimension,
        flexGrow: Float,
        flexShrink: Float,
        gridTemplateRows: [GridTemplateComponent<S>],
        gridTemplateColumns: [GridTemplateComponent<S>],
        gridAutoRows: [TrackSizingFunction],
        gridAutoColumns: [TrackSizingFunction],
        gridAutoFlow: GridAutoFlow,
        gridTemplateAreas: [GridTemplateArea<S>],
        gridTemplateColumnNames: [[S]],
        gridTemplateRowNames: [[S]],
        gridRow: Line<GridPlacement<S>>,
        gridColumn: Line<GridPlacement<S>>
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

    func clone() -> StyleStorage<S> {
        StyleStorage(
            display: display,
            itemIsTable: itemIsTable,
            itemIsReplaced: itemIsReplaced,
            boxSizing: boxSizing,
            overflow: overflow,
            scrollbarWidth: scrollbarWidth,
            position: position,
            inset: inset,
            size: size,
            minSize: minSize,
            maxSize: maxSize,
            aspectRatio: aspectRatio,
            margin: margin,
            padding: padding,
            border: border,
            alignItems: alignItems,
            alignSelf: alignSelf,
            justifyItems: justifyItems,
            justifySelf: justifySelf,
            alignContent: alignContent,
            justifyContent: justifyContent,
            gap: gap,
            textAlign: textAlign,
            flexDirection: flexDirection,
            flexWrap: flexWrap,
            flexBasis: flexBasis,
            flexGrow: flexGrow,
            flexShrink: flexShrink,
            gridTemplateRows: gridTemplateRows,
            gridTemplateColumns: gridTemplateColumns,
            gridAutoRows: gridAutoRows,
            gridAutoColumns: gridAutoColumns,
            gridAutoFlow: gridAutoFlow,
            gridTemplateAreas: gridTemplateAreas,
            gridTemplateColumnNames: gridTemplateColumnNames,
            gridTemplateRowNames: gridTemplateRowNames,
            gridRow: gridRow,
            gridColumn: gridColumn
        )
    }

    static func == (lhs: StyleStorage<S>, rhs: StyleStorage<S>) -> Bool {
        lhs === rhs || (
            lhs.display == rhs.display &&
            lhs.itemIsTable == rhs.itemIsTable &&
            lhs.itemIsReplaced == rhs.itemIsReplaced &&
            lhs.boxSizing == rhs.boxSizing &&
            lhs.overflow == rhs.overflow &&
            lhs.scrollbarWidth == rhs.scrollbarWidth &&
            lhs.position == rhs.position &&
            lhs.inset == rhs.inset &&
            lhs.size == rhs.size &&
            lhs.minSize == rhs.minSize &&
            lhs.maxSize == rhs.maxSize &&
            lhs.aspectRatio == rhs.aspectRatio &&
            lhs.margin == rhs.margin &&
            lhs.padding == rhs.padding &&
            lhs.border == rhs.border &&
            lhs.alignItems == rhs.alignItems &&
            lhs.alignSelf == rhs.alignSelf &&
            lhs.justifyItems == rhs.justifyItems &&
            lhs.justifySelf == rhs.justifySelf &&
            lhs.alignContent == rhs.alignContent &&
            lhs.justifyContent == rhs.justifyContent &&
            lhs.gap == rhs.gap &&
            lhs.textAlign == rhs.textAlign &&
            lhs.flexDirection == rhs.flexDirection &&
            lhs.flexWrap == rhs.flexWrap &&
            lhs.flexBasis == rhs.flexBasis &&
            lhs.flexGrow == rhs.flexGrow &&
            lhs.flexShrink == rhs.flexShrink &&
            lhs.gridTemplateRows == rhs.gridTemplateRows &&
            lhs.gridTemplateColumns == rhs.gridTemplateColumns &&
            lhs.gridAutoRows == rhs.gridAutoRows &&
            lhs.gridAutoColumns == rhs.gridAutoColumns &&
            lhs.gridAutoFlow == rhs.gridAutoFlow &&
            lhs.gridTemplateAreas == rhs.gridTemplateAreas &&
            lhs.gridTemplateColumnNames == rhs.gridTemplateColumnNames &&
            lhs.gridTemplateRowNames == rhs.gridTemplateRowNames &&
            lhs.gridRow == rhs.gridRow &&
            lhs.gridColumn == rhs.gridColumn
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(display)
        hasher.combine(itemIsTable)
        hasher.combine(itemIsReplaced)
        hasher.combine(boxSizing)
        hasher.combine(overflow)
        hasher.combine(scrollbarWidth)
        hasher.combine(position)
        hasher.combine(inset)
        hasher.combine(size)
        hasher.combine(minSize)
        hasher.combine(maxSize)
        hasher.combine(aspectRatio)
        hasher.combine(margin)
        hasher.combine(padding)
        hasher.combine(border)
        hasher.combine(alignItems)
        hasher.combine(alignSelf)
        hasher.combine(justifyItems)
        hasher.combine(justifySelf)
        hasher.combine(alignContent)
        hasher.combine(justifyContent)
        hasher.combine(gap)
        hasher.combine(textAlign)
        hasher.combine(flexDirection)
        hasher.combine(flexWrap)
        hasher.combine(flexBasis)
        hasher.combine(flexGrow)
        hasher.combine(flexShrink)
        hasher.combine(gridTemplateRows)
        hasher.combine(gridTemplateColumns)
        hasher.combine(gridAutoRows)
        hasher.combine(gridAutoColumns)
        hasher.combine(gridAutoFlow)
        hasher.combine(gridTemplateAreas)
        hasher.combine(gridTemplateColumnNames)
        hasher.combine(gridTemplateRowNames)
        hasher.combine(gridRow)
        hasher.combine(gridColumn)
    }
}

/// A typed representation of the CSS style information for a single node.
public struct Style<S: Sendable & Hashable>: Sendable, Hashable {
    private var storage: StyleStorage<S>

    @inline(__always)
    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }

    public var display: Display {
        get { storage.display }
        set { ensureUnique(); storage.display = newValue }
        _modify { ensureUnique(); yield &storage.display }
    }
    public var itemIsTable: Bool {
        get { storage.itemIsTable }
        set { ensureUnique(); storage.itemIsTable = newValue }
        _modify { ensureUnique(); yield &storage.itemIsTable }
    }
    public var itemIsReplaced: Bool {
        get { storage.itemIsReplaced }
        set { ensureUnique(); storage.itemIsReplaced = newValue }
        _modify { ensureUnique(); yield &storage.itemIsReplaced }
    }
    public var boxSizing: BoxSizing {
        get { storage.boxSizing }
        set { ensureUnique(); storage.boxSizing = newValue }
        _modify { ensureUnique(); yield &storage.boxSizing }
    }

    // Overflow properties
    public var overflow: Point<Overflow> {
        get { storage.overflow }
        set { ensureUnique(); storage.overflow = newValue }
        _modify { ensureUnique(); yield &storage.overflow }
    }
    public var scrollbarWidth: Float {
        get { storage.scrollbarWidth }
        set { ensureUnique(); storage.scrollbarWidth = newValue }
        _modify { ensureUnique(); yield &storage.scrollbarWidth }
    }

    // Position properties
    public var position: Position {
        get { storage.position }
        set { ensureUnique(); storage.position = newValue }
        _modify { ensureUnique(); yield &storage.position }
    }
    public var inset: Rect<LengthPercentageAuto> {
        get { storage.inset }
        set { ensureUnique(); storage.inset = newValue }
        _modify { ensureUnique(); yield &storage.inset }
    }

    // Size properties
    public var size: Size<Dimension> {
        get { storage.size }
        set { ensureUnique(); storage.size = newValue }
        _modify { ensureUnique(); yield &storage.size }
    }
    public var minSize: Size<Dimension> {
        get { storage.minSize }
        set { ensureUnique(); storage.minSize = newValue }
        _modify { ensureUnique(); yield &storage.minSize }
    }
    public var maxSize: Size<Dimension> {
        get { storage.maxSize }
        set { ensureUnique(); storage.maxSize = newValue }
        _modify { ensureUnique(); yield &storage.maxSize }
    }
    public var aspectRatio: Float? {
        get { storage.aspectRatio }
        set { ensureUnique(); storage.aspectRatio = newValue }
        _modify { ensureUnique(); yield &storage.aspectRatio }
    }

    // Spacing properties
    public var margin: Rect<LengthPercentageAuto> {
        get { storage.margin }
        set { ensureUnique(); storage.margin = newValue }
        _modify { ensureUnique(); yield &storage.margin }
    }
    public var padding: Rect<LengthPercentage> {
        get { storage.padding }
        set { ensureUnique(); storage.padding = newValue }
        _modify { ensureUnique(); yield &storage.padding }
    }
    public var border: Rect<LengthPercentage> {
        get { storage.border }
        set { ensureUnique(); storage.border = newValue }
        _modify { ensureUnique(); yield &storage.border }
    }

    // Alignment properties
    public var alignItems: AlignItems? {
        get { storage.alignItems }
        set { ensureUnique(); storage.alignItems = newValue }
        _modify { ensureUnique(); yield &storage.alignItems }
    }
    public var alignSelf: AlignSelf? {
        get { storage.alignSelf }
        set { ensureUnique(); storage.alignSelf = newValue }
        _modify { ensureUnique(); yield &storage.alignSelf }
    }
    public var justifyItems: AlignItems? {
        get { storage.justifyItems }
        set { ensureUnique(); storage.justifyItems = newValue }
        _modify { ensureUnique(); yield &storage.justifyItems }
    }
    public var justifySelf: AlignSelf? {
        get { storage.justifySelf }
        set { ensureUnique(); storage.justifySelf = newValue }
        _modify { ensureUnique(); yield &storage.justifySelf }
    }
    public var alignContent: AlignContent? {
        get { storage.alignContent }
        set { ensureUnique(); storage.alignContent = newValue }
        _modify { ensureUnique(); yield &storage.alignContent }
    }
    public var justifyContent: JustifyContent? {
        get { storage.justifyContent }
        set { ensureUnique(); storage.justifyContent = newValue }
        _modify { ensureUnique(); yield &storage.justifyContent }
    }
    public var gap: Size<LengthPercentage> {
        get { storage.gap }
        set { ensureUnique(); storage.gap = newValue }
        _modify { ensureUnique(); yield &storage.gap }
    }

    // Block container properties
    public var textAlign: TextAlign {
        get { storage.textAlign }
        set { ensureUnique(); storage.textAlign = newValue }
        _modify { ensureUnique(); yield &storage.textAlign }
    }

    // Flexbox container properties
    public var flexDirection: FlexDirection {
        get { storage.flexDirection }
        set { ensureUnique(); storage.flexDirection = newValue }
        _modify { ensureUnique(); yield &storage.flexDirection }
    }
    public var flexWrap: FlexWrap {
        get { storage.flexWrap }
        set { ensureUnique(); storage.flexWrap = newValue }
        _modify { ensureUnique(); yield &storage.flexWrap }
    }

    // Flexbox item properties
    public var flexBasis: Dimension {
        get { storage.flexBasis }
        set { ensureUnique(); storage.flexBasis = newValue }
        _modify { ensureUnique(); yield &storage.flexBasis }
    }
    public var flexGrow: Float {
        get { storage.flexGrow }
        set { ensureUnique(); storage.flexGrow = newValue }
        _modify { ensureUnique(); yield &storage.flexGrow }
    }
    public var flexShrink: Float {
        get { storage.flexShrink }
        set { ensureUnique(); storage.flexShrink = newValue }
        _modify { ensureUnique(); yield &storage.flexShrink }
    }

    // Grid container properties
    public var gridTemplateRows: [GridTemplateComponent<S>] {
        get { storage.gridTemplateRows }
        set { ensureUnique(); storage.gridTemplateRows = newValue }
        _modify { ensureUnique(); yield &storage.gridTemplateRows }
    }
    public var gridTemplateColumns: [GridTemplateComponent<S>] {
        get { storage.gridTemplateColumns }
        set { ensureUnique(); storage.gridTemplateColumns = newValue }
        _modify { ensureUnique(); yield &storage.gridTemplateColumns }
    }
    public var gridAutoRows: [TrackSizingFunction] {
        get { storage.gridAutoRows }
        set { ensureUnique(); storage.gridAutoRows = newValue }
        _modify { ensureUnique(); yield &storage.gridAutoRows }
    }
    public var gridAutoColumns: [TrackSizingFunction] {
        get { storage.gridAutoColumns }
        set { ensureUnique(); storage.gridAutoColumns = newValue }
        _modify { ensureUnique(); yield &storage.gridAutoColumns }
    }
    public var gridAutoFlow: GridAutoFlow {
        get { storage.gridAutoFlow }
        set { ensureUnique(); storage.gridAutoFlow = newValue }
        _modify { ensureUnique(); yield &storage.gridAutoFlow }
    }

    // Grid container named properties
    public var gridTemplateAreas: [GridTemplateArea<S>] {
        get { storage.gridTemplateAreas }
        set { ensureUnique(); storage.gridTemplateAreas = newValue }
        _modify { ensureUnique(); yield &storage.gridTemplateAreas }
    }
    public var gridTemplateColumnNames: [[S]] {
        get { storage.gridTemplateColumnNames }
        set { ensureUnique(); storage.gridTemplateColumnNames = newValue }
        _modify { ensureUnique(); yield &storage.gridTemplateColumnNames }
    }
    public var gridTemplateRowNames: [[S]] {
        get { storage.gridTemplateRowNames }
        set { ensureUnique(); storage.gridTemplateRowNames = newValue }
        _modify { ensureUnique(); yield &storage.gridTemplateRowNames }
    }

    // Grid child properties
    public var gridRow: Line<GridPlacement<S>> {
        get { storage.gridRow }
        set { ensureUnique(); storage.gridRow = newValue }
        _modify { ensureUnique(); yield &storage.gridRow }
    }
    public var gridColumn: Line<GridPlacement<S>> {
        get { storage.gridColumn }
        set { ensureUnique(); storage.gridColumn = newValue }
        _modify { ensureUnique(); yield &storage.gridColumn }
    }

    public init() {
        self.storage = StyleStorage<S>()
    }

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
        self.storage = StyleStorage(
            display: display,
            itemIsTable: itemIsTable,
            itemIsReplaced: itemIsReplaced,
            boxSizing: boxSizing,
            overflow: overflow,
            scrollbarWidth: scrollbarWidth,
            position: position,
            inset: inset,
            size: size,
            minSize: minSize,
            maxSize: maxSize,
            aspectRatio: aspectRatio,
            margin: margin,
            padding: padding,
            border: border,
            alignItems: alignItems,
            alignSelf: alignSelf,
            justifyItems: justifyItems,
            justifySelf: justifySelf,
            alignContent: alignContent,
            justifyContent: justifyContent,
            gap: gap,
            textAlign: textAlign,
            flexDirection: flexDirection,
            flexWrap: flexWrap,
            flexBasis: flexBasis,
            flexGrow: flexGrow,
            flexShrink: flexShrink,
            gridTemplateRows: gridTemplateRows,
            gridTemplateColumns: gridTemplateColumns,
            gridAutoRows: gridAutoRows,
            gridAutoColumns: gridAutoColumns,
            gridAutoFlow: gridAutoFlow,
            gridTemplateAreas: gridTemplateAreas,
            gridTemplateColumnNames: gridTemplateColumnNames,
            gridTemplateRowNames: gridTemplateRowNames,
            gridRow: gridRow,
            gridColumn: gridColumn
        )
    }

    public static var DEFAULT: Style<S> {
        Style<S>()
    }

    public static func == (lhs: Style<S>, rhs: Style<S>) -> Bool {
        lhs.storage == rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(storage)
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
