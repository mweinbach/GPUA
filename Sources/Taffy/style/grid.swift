// Ported from: src/style/grid.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Defines a grid area
public struct GridTemplateArea<CustomIdent: Sendable & Hashable>: Sendable, Hashable {
    public var name: CustomIdent
    public var rowStart: UInt16
    public var rowEnd: UInt16
    public var columnStart: UInt16
    public var columnEnd: UInt16

    @inlinable
    public init(name: CustomIdent, rowStart: UInt16, rowEnd: UInt16, columnStart: UInt16, columnEnd: UInt16) {
        self.name = name
        self.rowStart = rowStart
        self.rowEnd = rowEnd
        self.columnStart = columnStart
        self.columnEnd = columnEnd
    }
}

/// Defines a named grid line
public struct NamedGridLine<CustomIdent: Sendable & Hashable>: Sendable, Hashable {
    public var name: CustomIdent
    public var index: UInt16

    @inlinable
    public init(name: CustomIdent, index: UInt16) {
        self.name = name
        self.index = index
    }
}

/// Axis as `Row` or `Column`
public enum GridAreaAxis: Sendable, Hashable {
    case row
    case column
}

/// Logical end (`Start` or `End`)
public enum GridAreaEnd: Sendable, Hashable {
    case start
    case end
}

/// A trait for the different coordinates used to define grid lines.
public protocol GridCoordinate: Sendable, Hashable, Copyable {
    var isDefiniteLine: Bool { get }
}

/// Represents a grid line position in "CSS Grid Line" coordinates (1-based, 0 invalid, negative counts from end)
public struct GridLine: Sendable, Hashable, GridCoordinate {
    public var rawValue: Int16

    @inlinable
    public var isDefiniteLine: Bool {
        rawValue != 0
    }

    @inlinable
    public init(_ rawValue: Int16) {
        self.rawValue = rawValue
    }

    @inlinable
    public func asI16() -> Int16 {
        rawValue
    }

    /// Convert into OriginZero coordinates using specified explicit track count
    @inlinable
    public func intoOriginZeroLine(explicitTrackCount: UInt16) -> OriginZeroLine {
        let explicitLineCount = Int16(explicitTrackCount) + 1
        if rawValue > 0 {
            return OriginZeroLine(rawValue - 1)
        } else if rawValue < 0 {
            return OriginZeroLine(rawValue + explicitLineCount)
        } else {
            fatalError("Grid line of zero is invalid")
        }
    }
}

extension GridLine: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: Int16) {
        self.rawValue = value
    }
}

/// Represents a grid line position in "OriginZero" coordinates (0-based normalized)
public struct OriginZeroLine: Sendable, Hashable, Comparable, GridCoordinate {
    public var rawValue: Int16

    @inlinable
    public var isDefiniteLine: Bool {
        true
    }

    @inlinable
    public init(_ rawValue: Int16) {
        self.rawValue = rawValue
    }

    @inlinable
    public static func < (lhs: OriginZeroLine, rhs: OriginZeroLine) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    @inlinable
    public static func + (lhs: OriginZeroLine, rhs: OriginZeroLine) -> OriginZeroLine {
        OriginZeroLine(lhs.rawValue + rhs.rawValue)
    }

    @inlinable
    public static func - (lhs: OriginZeroLine, rhs: OriginZeroLine) -> OriginZeroLine {
        OriginZeroLine(lhs.rawValue - rhs.rawValue)
    }

    @inlinable
    public static func + (lhs: OriginZeroLine, rhs: UInt16) -> OriginZeroLine {
        OriginZeroLine(lhs.rawValue + Int16(rhs))
    }

    @inlinable
    public static func - (lhs: OriginZeroLine, rhs: UInt16) -> OriginZeroLine {
        OriginZeroLine(lhs.rawValue - Int16(rhs))
    }

    @inlinable
    public func impliedNegativeImplicitTracks() -> UInt16 {
        if rawValue < 0 {
            return UInt16(-rawValue)
        } else {
            return 0
        }
    }

    @inlinable
    public func impliedPositiveImplicitTracks(explicitTrackCount: UInt16) -> UInt16 {
        if rawValue > Int16(explicitTrackCount) {
            return UInt16(rawValue) - explicitTrackCount
        } else {
            return 0
        }
    }
}

extension OriginZeroLine: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: Int16) {
        self.rawValue = value
    }
}

extension Line where T == OriginZeroLine {
    /// The number of tracks between the start and end lines
    @inlinable
    public func span() -> UInt16 {
        UInt16(Swift.max(end.rawValue - start.rawValue, 0))
    }
}

/// Controls whether grid items are placed row-wise or column-wise. And whether sparse or dense packing is used.
///
/// Defaults to `GridAutoFlow.row`.
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/grid-auto-flow)
public enum GridAutoFlow: Sendable, Hashable {
    case row
    case column
    case rowDense
    case columnDense

    public static let `default`: GridAutoFlow = .row

    @inlinable
    public init() {
        self = .row
    }

    @inlinable
    public var isDense: Bool {
        switch self {
        case .row, .column: return false
        case .rowDense, .columnDense: return true
        }
    }

    @inlinable
    public var primaryAxis: AbsoluteAxis {
        switch self {
        case .row, .rowDense: return .horizontal
        case .column, .columnDense: return .vertical
        }
    }
}

/// A grid line placement specification generic over the coordinate system
public enum GenericGridPlacement<LineType: GridCoordinate>: Sendable, Hashable {
    case auto
    case line(LineType)
    case span(UInt16)
}

public typealias OriginZeroGridPlacement = GenericGridPlacement<OriginZeroLine>
public typealias NonNamedGridPlacement = GenericGridPlacement<GridLine>

/// A grid line placement specification
public enum GridPlacement<S: Sendable & Hashable>: Sendable, Hashable {
    case auto
    case line(GridLine)
    case namedLine(S, Int16)
    case span(UInt16)
    case namedSpan(S, UInt16)

    @inlinable
    public init() {
        self = .auto
    }

    @inlinable
    public func intoOriginZeroPlacementIgnoringNamed(explicitTrackCount: UInt16) -> OriginZeroGridPlacement {
        switch self {
        case .auto:
            return .auto
        case .span(let s):
            return .span(s)
        case .line(let line):
            if line.asI16() == 0 {
                return .auto
            } else {
                return .line(line.intoOriginZeroLine(explicitTrackCount: explicitTrackCount))
            }
        case .namedLine, .namedSpan:
            return .auto
        }
    }
}

public protocol TaffyDefinitePlacement: Sendable {
    var isDefinitePlacement: Bool { get }
}

extension GridPlacement: TaffyDefinitePlacement {
    @inlinable
    public var isDefinitePlacement: Bool {
        switch self {
        case .line(let line): return line.asI16() != 0
        case .namedLine: return true
        default: return false
        }
    }
}

extension GenericGridPlacement: TaffyDefinitePlacement {
    @inlinable
    public var isDefinitePlacement: Bool {
        switch self {
        case .line(let line): return line.isDefiniteLine
        default: return false
        }
    }
}

extension Line where T: TaffyDefinitePlacement {
    @inlinable
    public var isDefinite: Bool {
        start.isDefinitePlacement || end.isDefinitePlacement
    }
}

extension Line {
    @inlinable
    public func intoOriginZeroIgnoringNamed<S: Sendable & Hashable>(explicitTrackCount: UInt16) -> Line<OriginZeroGridPlacement> where T == GridPlacement<S> {
        Line<OriginZeroGridPlacement>(
            start: start.intoOriginZeroPlacementIgnoringNamed(explicitTrackCount: explicitTrackCount),
            end: end.intoOriginZeroPlacementIgnoringNamed(explicitTrackCount: explicitTrackCount)
        )
    }
}

extension Line {
    @inlinable
    public func indefiniteSpan<Coordinate: GridCoordinate>() -> UInt16 where T == GenericGridPlacement<Coordinate> {
        switch (start, end) {
        case (.line, .auto), (.auto, .line), (.auto, .auto):
            return 1
        case (.line, .span(let s)), (.span(let s), .line), (.span(let s), .auto), (.auto, .span(let s)), (.span(let s), .span):
            return s
        case (.line, .line):
            fatalError("indefiniteSpan should only be called on indefinite grid tracks")
        }
    }
}

extension Line where T == OriginZeroGridPlacement {

    @inlinable
    public func resolveDefiniteGridLines() -> Line<OriginZeroLine> {
        switch (start, end) {
        case let (.line(line1), .line(line2)):
            if line1 == line2 {
                return Line<OriginZeroLine>(start: line1, end: line1 + 1)
            } else {
                return Line<OriginZeroLine>(start: Swift.min(line1, line2), end: Swift.max(line1, line2))
            }
        case let (.line(line), .span(spanVal)):
            return Line<OriginZeroLine>(start: line, end: line + spanVal)
        case let (.line(line), .auto):
            return Line<OriginZeroLine>(start: line, end: line + 1)
        case let (.span(spanVal), .line(line)):
            return Line<OriginZeroLine>(start: line - spanVal, end: line)
        case let (.auto, .line(line)):
            return Line<OriginZeroLine>(start: line - 1, end: line)
        default:
            fatalError("resolveDefiniteGridLines should only be called on definite grid tracks")
        }
    }

    @inlinable
    public func resolveAbsolutelyPositionedGridTracks() -> Line<OriginZeroLine?> {
        switch (start, end) {
        case let (.line(track1), .line(track2)):
            if track1 == track2 {
                return Line<OriginZeroLine?>(start: track1, end: track1 + 1)
            } else {
                return Line<OriginZeroLine?>(start: Swift.min(track1, track2), end: Swift.max(track1, track2))
            }
        case let (.line(track), .span(spanVal)):
            return Line<OriginZeroLine?>(start: track, end: track + spanVal)
        case let (.line(track), .auto):
            return Line<OriginZeroLine?>(start: track, end: nil)
        case let (.span(spanVal), .line(track)):
            return Line<OriginZeroLine?>(start: track - spanVal, end: track)
        case let (.auto, .line(track)):
            return Line<OriginZeroLine?>(start: nil, end: track)
        default:
            return Line<OriginZeroLine?>(start: nil, end: nil)
        }
    }

    @inlinable
    public func resolveIndefiniteGridTracks(start: OriginZeroLine) -> Line<OriginZeroLine> {
        switch (self.start, self.end) {
        case (.auto, .auto):
            return Line<OriginZeroLine>(start: start, end: start + 1)
        case (.span(let s), .auto), (.auto, .span(let s)), (.span(let s), .span):
            return Line<OriginZeroLine>(start: start, end: start + s)
        default:
            fatalError("resolveIndefiniteGridTracks should only be called on indefinite grid tracks")
        }
    }
}

extension Line where T == NonNamedGridPlacement {

    @inlinable
    public func intoOriginZero(explicitTrackCount: UInt16) -> Line<OriginZeroGridPlacement> {
        Line<OriginZeroGridPlacement>(
            start: start.intoOriginZeroPlacement(explicitTrackCount: explicitTrackCount),
            end: end.intoOriginZeroPlacement(explicitTrackCount: explicitTrackCount)
        )
    }
}

extension NonNamedGridPlacement {
    @inlinable
    public func intoOriginZeroPlacement(explicitTrackCount: UInt16) -> OriginZeroGridPlacement {
        switch self {
        case .auto: return .auto
        case .span(let s): return .span(s)
        case .line(let line):
            if line.asI16() == 0 {
                return .auto
            } else {
                return .line(line.intoOriginZeroLine(explicitTrackCount: explicitTrackCount))
            }
        }
    }
}

extension GridPlacement: TaffyAuto {
    public static var AUTO: GridPlacement { .auto }
}

extension GridPlacement: TaffyGridLine {
    @inlinable
    public static func fromLineIndex(_ index: Int16) -> GridPlacement {
        .line(GridLine(index))
    }
}

extension GridPlacement: TaffyGridSpan {
    @inlinable
    public static func fromSpan(_ span: UInt16) -> GridPlacement {
        .span(span)
    }
}

/// Maximum track sizing function
public struct MaxTrackSizingFunction: Sendable, Hashable {
    public var value: CompactLength

    @inlinable
    public init(_ value: CompactLength) {
        self.value = value
    }

    @inlinable
    public static func length(_ val: Float) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.length(val))
    }

    @inlinable
    public static func percent(_ val: Float) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.percent(val))
    }

    @inlinable
    public static func auto() -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.auto)
    }

    @inlinable
    public static func min_content() -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.minContent)
    }

    @inlinable
    public static func max_content() -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.maxContent)
    }

    @inlinable
    public static func fit_content_px(_ limit: Float) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.fitContentPx(limit))
    }

    @inlinable
    public static func fit_content_percent(_ limit: Float) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.fitContentPercent(limit))
    }

    @inlinable
    public static func fr(_ val: Float) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(.fr(val))
    }

    @inlinable
    public static func fromRaw(_ val: CompactLength) -> MaxTrackSizingFunction {
        MaxTrackSizingFunction(val)
    }

    @inlinable
    public func intoRaw() -> CompactLength {
        value
    }

    @inlinable
    public var isIntrinsic: Bool { value.isIntrinsic }
    @inlinable
    public var isMaxContentAlike: Bool { value.isMaxContentAlike }
    @inlinable
    public var isFr: Bool { value.isFr }
    @inlinable
    public var isAuto: Bool { value.isAuto }
    @inlinable
    public var isMinContent: Bool { value.isMinContent }
    @inlinable
    public var isMaxContent: Bool { value.isMaxContent }
    @inlinable
    public var isFitContent: Bool { value.isFitContent }
    @inlinable
    public var isMaxOrFitContent: Bool { value.isMaxOrFitContent }

    @inlinable
    public func hasDefiniteValue(parentSize: Float?) -> Bool {
        switch value {
        case .length: return true
        case .percent: return parentSize != nil
        default: return false
        }
    }

    @inlinable
    public func definiteValue(
        parentSize: Float?,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        switch value {
        case .length(let val): return val
        case .percent(let p): return parentSize.map { $0 * p }
        default: return nil
        }
    }

    @inlinable
    public func definiteLimit(
        parentSize: Float?,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        switch value {
        case .fitContentPx(let limit): return limit
        case .fitContentPercent(let p): return parentSize.map { $0 * p }
        default: return definiteValue(parentSize: parentSize, calcResolver: calcResolver)
        }
    }

    @inlinable
    public func resolvedPercentageSize(
        parentSize: Float,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        value.resolvedPercentageSize(parentSize: parentSize, calcResolver: calcResolver)
    }

    @inlinable
    public var usesPercentage: Bool {
        value.usesPercentage
    }
}

extension MaxTrackSizingFunction: TaffyZero {
    public static let ZERO = MaxTrackSizingFunction(CompactLength.ZERO)
}

extension MaxTrackSizingFunction: TaffyAuto {
    public static let AUTO = MaxTrackSizingFunction(.auto)
}

extension MaxTrackSizingFunction: TaffyMinContent {
    public static let MIN_CONTENT = MaxTrackSizingFunction(.minContent)
}

extension MaxTrackSizingFunction: TaffyMaxContent {
    public static let MAX_CONTENT = MaxTrackSizingFunction(.maxContent)
}

extension MaxTrackSizingFunction: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> MaxTrackSizingFunction {
        .length(value)
    }
}

extension MaxTrackSizingFunction: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> MaxTrackSizingFunction {
        .percent(percent)
    }
}

extension MaxTrackSizingFunction: FromFr {
    @inlinable
    public static func fromFr(_ flex: Float) -> MaxTrackSizingFunction {
        .fr(flex)
    }
}

extension MaxTrackSizingFunction: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> MaxTrackSizingFunction {
        switch argument.value {
        case .length(let len): return .fit_content_px(len)
        case .percent(let p): return .fit_content_percent(p)
        default: fatalError("Invalid fit_content argument")
        }
    }
}

/// Minimum track sizing function
public struct MinTrackSizingFunction: Sendable, Hashable {
    public var value: CompactLength

    @inlinable
    public init(_ value: CompactLength) {
        self.value = value
    }

    @inlinable
    public static func length(_ val: Float) -> MinTrackSizingFunction {
        MinTrackSizingFunction(.length(val))
    }

    @inlinable
    public static func percent(_ val: Float) -> MinTrackSizingFunction {
        MinTrackSizingFunction(.percent(val))
    }

    @inlinable
    public static func auto() -> MinTrackSizingFunction {
        MinTrackSizingFunction(.auto)
    }

    @inlinable
    public static func min_content() -> MinTrackSizingFunction {
        MinTrackSizingFunction(.minContent)
    }

    @inlinable
    public static func max_content() -> MinTrackSizingFunction {
        MinTrackSizingFunction(.maxContent)
    }

    @inlinable
    public static func fromRaw(_ val: CompactLength) -> MinTrackSizingFunction {
        MinTrackSizingFunction(val)
    }

    @inlinable
    public func intoRaw() -> CompactLength {
        value
    }

    @inlinable
    public var isIntrinsic: Bool { value.isIntrinsic }
    @inlinable
    public var isMinOrMaxContent: Bool { value.isMinOrMaxContent }
    @inlinable
    public var isFr: Bool { value.isFr }
    @inlinable
    public var isAuto: Bool { value.isAuto }
    @inlinable
    public var isMinContent: Bool { value.isMinContent }
    @inlinable
    public var isMaxContent: Bool { value.isMaxContent }

    @inlinable
    public func definiteValue(
        parentSize: Float?,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        switch value {
        case .length(let val): return val
        case .percent(let p): return parentSize.map { $0 * p }
        default: return nil
        }
    }

    @inlinable
    public func resolvedPercentageSize(
        parentSize: Float,
        calcResolver: ((UnsafeRawPointer?, Float) -> Float)? = nil
    ) -> Float? {
        value.resolvedPercentageSize(parentSize: parentSize, calcResolver: calcResolver)
    }

    @inlinable
    public var usesPercentage: Bool {
        value.usesPercentage
    }
}

extension MinTrackSizingFunction: TaffyZero {
    public static let ZERO = MinTrackSizingFunction(CompactLength.ZERO)
}

extension MinTrackSizingFunction: TaffyAuto {
    public static let AUTO = MinTrackSizingFunction(.auto)
}

extension MinTrackSizingFunction: TaffyMinContent {
    public static let MIN_CONTENT = MinTrackSizingFunction(.minContent)
}

extension MinTrackSizingFunction: TaffyMaxContent {
    public static let MAX_CONTENT = MinTrackSizingFunction(.maxContent)
}

extension MinTrackSizingFunction: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> MinTrackSizingFunction {
        .length(value)
    }
}

extension MinTrackSizingFunction: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> MinTrackSizingFunction {
        .percent(percent)
    }
}

/// The sizing function for a grid track (row/column)
public typealias TrackSizingFunction = MinMax<MinTrackSizingFunction, MaxTrackSizingFunction>

extension TrackSizingFunction {
    @inlinable
    public func minSizingFunction() -> MinTrackSizingFunction {
        min
    }

    @inlinable
    public func maxSizingFunction() -> MaxTrackSizingFunction {
        max
    }

    @inlinable
    public func hasFixedComponent() -> Bool {
        min.value.isLengthOrPercentage || max.value.isLengthOrPercentage
    }
}

extension TrackSizingFunction: TaffyAuto {
    public static let AUTO = TrackSizingFunction(min: .AUTO, max: .AUTO)
}

extension TrackSizingFunction: TaffyMinContent {
    public static let MIN_CONTENT = TrackSizingFunction(min: .MIN_CONTENT, max: .MIN_CONTENT)
}

extension TrackSizingFunction: TaffyMaxContent {
    public static let MAX_CONTENT = TrackSizingFunction(min: .MAX_CONTENT, max: .MAX_CONTENT)
}

extension TrackSizingFunction: TaffyZero {
    public static let ZERO = TrackSizingFunction(min: .ZERO, max: .ZERO)
}

extension TrackSizingFunction: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> TrackSizingFunction {
        TrackSizingFunction(min: .fromLength(value), max: .fromLength(value))
    }
}

extension TrackSizingFunction: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> TrackSizingFunction {
        TrackSizingFunction(min: .fromPercent(percent), max: .fromPercent(percent))
    }
}

extension TrackSizingFunction: FromFr {
    @inlinable
    public static func fromFr(_ flex: Float) -> TrackSizingFunction {
        TrackSizingFunction(min: .AUTO, max: .fromFr(flex))
    }
}

extension TrackSizingFunction: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> TrackSizingFunction {
        TrackSizingFunction(min: .AUTO, max: MaxTrackSizingFunction.fitContent(argument))
    }
}

/// Repetition type for grid-template repeat()
public enum RepetitionCount: Sendable, Hashable {
    case autoFill
    case autoFit
    case count(UInt16)
}

extension RepetitionCount: ExpressibleByIntegerLiteral {
    @inlinable
    public init(integerLiteral value: UInt16) {
        self = .count(value)
    }
}

/// A typed representation of a `repeat(..)` in `grid-template-*` value
public struct GridTemplateRepetition<S: Sendable & Hashable>: Sendable, Hashable {
    public var count: RepetitionCount
    public var tracks: [TrackSizingFunction]
    public var lineNames: [[S]]

    @inlinable
    public init(count: RepetitionCount, tracks: [TrackSizingFunction], lineNames: [[S]] = []) {
        self.count = count
        self.tracks = tracks
        self.lineNames = lineNames
    }

    @inlinable
    public var trackCount: UInt16 {
        UInt16(tracks.count)
    }
}

/// An element in a `grid-template-columns` or `grid-template-rows` definition
public enum GridTemplateComponent<S: Sendable & Hashable>: Sendable, Hashable {
    case single(TrackSizingFunction)
    case repeat_(GridTemplateRepetition<S>)

    @inlinable
    public var isAutoRepetition: Bool {
        switch self {
        case .single: return false
        case .repeat_(let rep):
            switch rep.count {
            case .autoFit, .autoFill: return true
            case .count: return false
            }
        }
    }
}

extension GridTemplateComponent: TaffyAuto {
    public static var AUTO: GridTemplateComponent { .single(.AUTO) }
}

extension GridTemplateComponent: TaffyMinContent {
    public static var MIN_CONTENT: GridTemplateComponent { .single(.MIN_CONTENT) }
}

extension GridTemplateComponent: TaffyMaxContent {
    public static var MAX_CONTENT: GridTemplateComponent { .single(.MAX_CONTENT) }
}

extension GridTemplateComponent: TaffyZero {
    public static var ZERO: GridTemplateComponent { .single(.ZERO) }
}

extension GridTemplateComponent: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> GridTemplateComponent {
        .single(.fromLength(value))
    }
}

extension GridTemplateComponent: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> GridTemplateComponent {
        .single(.fromPercent(percent))
    }
}

extension GridTemplateComponent: FromFr {
    @inlinable
    public static func fromFr(_ flex: Float) -> GridTemplateComponent {
        .single(.fromFr(flex))
    }
}

extension GridTemplateComponent: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> GridTemplateComponent {
        .single(.fitContent(argument))
    }
}

/// The set of styles required for a CSS Grid container
public protocol GridContainerStyle: CoreStyle {
    var gridTemplateRows: [GridTemplateComponent<CustomIdent>] { get }
    var gridTemplateColumns: [GridTemplateComponent<CustomIdent>] { get }
    var gridAutoRows: [TrackSizingFunction] { get }
    var gridAutoColumns: [TrackSizingFunction] { get }
    var gridTemplateAreas: [GridTemplateArea<CustomIdent>] { get }
    var gridTemplateColumnNames: [[CustomIdent]] { get }
    var gridTemplateRowNames: [[CustomIdent]] { get }
    var gridAutoFlow: GridAutoFlow { get }
    var gap: Size<LengthPercentage> { get }
    var alignContent: AlignContent? { get }
    var justifyContent: JustifyContent? { get }
    var alignItems: AlignItems? { get }
    var justifyItems: AlignItems? { get }
}

extension GridContainerStyle {
    @inlinable
    public func gridTemplateTracks(axis: AbsoluteAxis) -> [GridTemplateComponent<CustomIdent>]? {
        switch axis {
        case .horizontal: return gridTemplateColumns.isEmpty ? nil : gridTemplateColumns
        case .vertical: return gridTemplateRows.isEmpty ? nil : gridTemplateRows
        }
    }

    @inlinable
    public func gridAlignContent(axis: AbstractAxis) -> AlignContent {
        switch axis {
        case .inline: return justifyContent ?? .stretch
        case .block: return alignContent ?? .stretch
        }
    }
}

/// The set of styles required for a CSS Grid item
public protocol GridItemStyle: CoreStyle {
    var gridRow: Line<GridPlacement<CustomIdent>> { get }
    var gridColumn: Line<GridPlacement<CustomIdent>> { get }
    var alignSelf: AlignSelf? { get }
    var justifySelf: AlignSelf? { get }
}

extension GridItemStyle {
    @inlinable
    public func gridPlacement(axis: AbsoluteAxis) -> Line<GridPlacement<CustomIdent>> {
        switch axis {
        case .horizontal: return gridColumn
        case .vertical: return gridRow
        }
    }
}
