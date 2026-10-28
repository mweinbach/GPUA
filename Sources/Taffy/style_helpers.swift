// Ported from: src/style_helpers.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// Trait to abstract over zero values
public protocol TaffyZero: Sendable {
    static var ZERO: Self { get }
}

/// Trait to abstract over auto values
public protocol TaffyAuto: Sendable {
    static var AUTO: Self { get }
}

/// Trait to abstract over min_content values
public protocol TaffyMinContent: Sendable {
    static var MIN_CONTENT: Self { get }
}

/// Trait to abstract over max_content values
public protocol TaffyMaxContent: Sendable {
    static var MAX_CONTENT: Self { get }
}

/// Trait to create `fit-content(…)` values
public protocol TaffyFitContent: Sendable {
    static func fitContent(_ argument: LengthPercentage) -> Self
}

/// Trait to create absolute length values
public protocol FromLength: Sendable {
    static func fromLength(_ value: Float) -> Self
}

/// Trait to create constant percent values
public protocol FromPercent: Sendable {
    static func fromPercent(_ percent: Float) -> Self
}

/// Trait to create fr track sizing values
public protocol FromFr: Sendable {
    static func fromFr(_ flex: Float) -> Self
}

/// Trait to abstract over grid line values
public protocol TaffyGridLine: Sendable {
    static func fromLineIndex(_ index: Int16) -> Self
}

/// Trait to abstract over grid span values
public protocol TaffyGridSpan: Sendable {
    static func fromSpan(_ span: UInt16) -> Self
}

// MARK: - Standard type conformances

extension Float: TaffyZero {
    public static let ZERO: Float = 0.0
}

extension Float: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Float {
        value
    }
}

extension Float: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Float {
        percent
    }
}

extension Optional: TaffyZero where Wrapped: TaffyZero {
    public static var ZERO: Wrapped? { .some(Wrapped.ZERO) }
}

extension Optional: TaffyAuto where Wrapped: TaffyAuto {
    public static var AUTO: Wrapped? { .some(Wrapped.AUTO) }
}

extension Optional: TaffyMinContent where Wrapped: TaffyMinContent {
    public static var MIN_CONTENT: Wrapped? { .some(Wrapped.MIN_CONTENT) }
}

extension Optional: TaffyMaxContent where Wrapped: TaffyMaxContent {
    public static var MAX_CONTENT: Wrapped? { .some(Wrapped.MAX_CONTENT) }
}

extension Optional: FromLength where Wrapped: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Wrapped? {
        .some(Wrapped.fromLength(value))
    }
}

extension Optional: FromPercent where Wrapped: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Wrapped? {
        .some(Wrapped.fromPercent(percent))
    }
}

// MARK: - Geometry type conformances

extension Point: TaffyZero where T: TaffyZero {
    public static var ZERO: Point<T> { Point(x: T.ZERO, y: T.ZERO) }
    @inlinable
    public static func zero() -> Point<T> { Point.ZERO }
}

extension Point: TaffyAuto where T: TaffyAuto {
    public static var AUTO: Point<T> { Point(x: T.AUTO, y: T.AUTO) }
    @inlinable
    public static func auto() -> Point<T> { Point.AUTO }
}

extension Point: TaffyMinContent where T: TaffyMinContent {
    public static var MIN_CONTENT: Point<T> { Point(x: T.MIN_CONTENT, y: T.MIN_CONTENT) }
    @inlinable
    public static func min_content() -> Point<T> { Point.MIN_CONTENT }
}

extension Point: TaffyMaxContent where T: TaffyMaxContent {
    public static var MAX_CONTENT: Point<T> { Point(x: T.MAX_CONTENT, y: T.MAX_CONTENT) }
    @inlinable
    public static func max_content() -> Point<T> { Point.MAX_CONTENT }
}

extension Point: TaffyFitContent where T: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> Point<T> {
        Point(x: T.fitContent(argument), y: T.fitContent(argument))
    }
}

extension Point: FromLength where T: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Point<T> {
        Point(x: T.fromLength(value), y: T.fromLength(value))
    }
}

extension Point: FromPercent where T: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Point<T> {
        Point(x: T.fromPercent(percent), y: T.fromPercent(percent))
    }
}

extension Line: TaffyZero where T: TaffyZero {
    public static var ZERO: Line<T> { Line(start: T.ZERO, end: T.ZERO) }
    @inlinable
    public static func zero() -> Line<T> { Line.ZERO }
}

extension Line: TaffyAuto where T: TaffyAuto {
    public static var AUTO: Line<T> { Line(start: T.AUTO, end: T.AUTO) }
    @inlinable
    public static func auto() -> Line<T> { Line.AUTO }
}

extension Line: TaffyMinContent where T: TaffyMinContent {
    public static var MIN_CONTENT: Line<T> { Line(start: T.MIN_CONTENT, end: T.MIN_CONTENT) }
    @inlinable
    public static func min_content() -> Line<T> { Line.MIN_CONTENT }
}

extension Line: TaffyMaxContent where T: TaffyMaxContent {
    public static var MAX_CONTENT: Line<T> { Line(start: T.MAX_CONTENT, end: T.MAX_CONTENT) }
    @inlinable
    public static func max_content() -> Line<T> { Line.MAX_CONTENT }
}

extension Line: TaffyFitContent where T: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> Line<T> {
        Line(start: T.fitContent(argument), end: T.fitContent(argument))
    }
}

extension Line: FromLength where T: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Line<T> {
        Line(start: T.fromLength(value), end: T.fromLength(value))
    }
}

extension Line: FromPercent where T: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Line<T> {
        Line(start: T.fromPercent(percent), end: T.fromPercent(percent))
    }
}

extension Size: TaffyZero where T: TaffyZero {
    public static var ZERO: Size<T> { Size(width: T.ZERO, height: T.ZERO) }
    @inlinable
    public static func zero() -> Size<T> { Size.ZERO }
}

extension Size: TaffyAuto where T: TaffyAuto {
    public static var AUTO: Size<T> { Size(width: T.AUTO, height: T.AUTO) }
    @inlinable
    public static func auto() -> Size<T> { Size.AUTO }
}

extension Size: TaffyMinContent where T: TaffyMinContent {
    public static var MIN_CONTENT: Size<T> { Size(width: T.MIN_CONTENT, height: T.MIN_CONTENT) }
    @inlinable
    public static func min_content() -> Size<T> { Size.MIN_CONTENT }
}

extension Size: TaffyMaxContent where T: TaffyMaxContent {
    public static var MAX_CONTENT: Size<T> { Size(width: T.MAX_CONTENT, height: T.MAX_CONTENT) }
    @inlinable
    public static func max_content() -> Size<T> { Size.MAX_CONTENT }
}

extension Size: TaffyFitContent where T: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> Size<T> {
        Size(width: T.fitContent(argument), height: T.fitContent(argument))
    }
}

extension Size: FromLength where T: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Size<T> {
        Size(width: T.fromLength(value), height: T.fromLength(value))
    }
}

extension Size: FromPercent where T: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Size<T> {
        Size(width: T.fromPercent(percent), height: T.fromPercent(percent))
    }
}

extension Rect: TaffyZero where T: TaffyZero {
    public static var ZERO: Rect<T> { Rect(left: T.ZERO, right: T.ZERO, top: T.ZERO, bottom: T.ZERO) }
    @inlinable
    public static func zero() -> Rect<T> { Rect.ZERO }
}

extension Rect: TaffyAuto where T: TaffyAuto {
    public static var AUTO: Rect<T> { Rect(left: T.AUTO, right: T.AUTO, top: T.AUTO, bottom: T.AUTO) }
    @inlinable
    public static func auto() -> Rect<T> { Rect.AUTO }
}

extension Rect: TaffyMinContent where T: TaffyMinContent {
    public static var MIN_CONTENT: Rect<T> { Rect(left: T.MIN_CONTENT, right: T.MIN_CONTENT, top: T.MIN_CONTENT, bottom: T.MIN_CONTENT) }
    @inlinable
    public static func min_content() -> Rect<T> { Rect.MIN_CONTENT }
}

extension Rect: TaffyMaxContent where T: TaffyMaxContent {
    public static var MAX_CONTENT: Rect<T> { Rect(left: T.MAX_CONTENT, right: T.MAX_CONTENT, top: T.MAX_CONTENT, bottom: T.MAX_CONTENT) }
    @inlinable
    public static func max_content() -> Rect<T> { Rect.MAX_CONTENT }
}

extension Rect: TaffyFitContent where T: TaffyFitContent {
    @inlinable
    public static func fitContent(_ argument: LengthPercentage) -> Rect<T> {
        Rect(left: T.fitContent(argument), right: T.fitContent(argument), top: T.fitContent(argument), bottom: T.fitContent(argument))
    }
}

extension Rect: FromLength where T: FromLength {
    @inlinable
    public static func fromLength(_ value: Float) -> Rect<T> {
        Rect(left: T.fromLength(value), right: T.fromLength(value), top: T.fromLength(value), bottom: T.fromLength(value))
    }
}

extension Rect: FromPercent where T: FromPercent {
    @inlinable
    public static func fromPercent(_ percent: Float) -> Rect<T> {
        Rect(left: T.fromPercent(percent), right: T.fromPercent(percent), top: T.fromPercent(percent), bottom: T.fromPercent(percent))
    }
}

// MARK: - Global Helper Functions

/// Returns the zero value for that type
@inlinable
public func zero<T: TaffyZero>() -> T {
    T.ZERO
}

/// Returns the auto value for that type
@inlinable
public func auto<T: TaffyAuto>() -> T {
    T.AUTO
}

/// Returns the min_content value for that type
@inlinable
public func min_content<T: TaffyMinContent>() -> T {
    T.MIN_CONTENT
}

/// Returns the max_content value for that type
@inlinable
public func max_content<T: TaffyMaxContent>() -> T {
    T.MAX_CONTENT
}

/// Returns a fit_content value
@inlinable
public func fit_content<T: TaffyFitContent>(_ argument: LengthPercentage) -> T {
    T.fitContent(argument)
}

/// Returns a value representing an absolute length
@inlinable
public func length<T: FromLength>(_ value: Float) -> T {
    T.fromLength(value)
}

/// Returns a value representing a percentage
@inlinable
public func percent<T: FromPercent>(_ percent: Float) -> T {
    T.fromPercent(percent)
}

/// Creates a fraction track sizing function
@inlinable
public func fr<T: FromFr>(_ flex: Float) -> T {
    T.fromFr(flex)
}

/// Specifies a grid line
@inlinable
public func line<T: TaffyGridLine>(_ index: Int16) -> T {
    T.fromLineIndex(index)
}

/// Returns a GridPlacement::Span
@inlinable
public func span<T: TaffyGridSpan>(_ spanCount: UInt16) -> T {
    T.fromSpan(spanCount)
}

/// Returns a MinMax with min value of min and max value of max
@inlinable
public func minmax(_ min: MinTrackSizingFunction, _ max: MaxTrackSizingFunction) -> TrackSizingFunction {
    TrackSizingFunction(min: min, max: max)
}

/// Returns a GridTemplateComponent containing a MinMax
@_disfavoredOverload
@inlinable
public func minmax<S: Sendable & Hashable>(_ min: MinTrackSizingFunction, _ max: MaxTrackSizingFunction) -> GridTemplateComponent<S> {
    .single(TrackSizingFunction(min: min, max: max))
}

/// Shorthand for minmax(0, Nfr)
@inlinable
public func flex(_ flexFraction: Float) -> TrackSizingFunction {
    TrackSizingFunction(min: .ZERO, max: .fr(flexFraction))
}

/// Returns an auto-repeated track definition
@inlinable
public func repeat_<S: Sendable & Hashable>(_ count: RepetitionCount, _ tracks: [TrackSizingFunction]) -> GridTemplateComponent<S> {
    .repeat_(GridTemplateRepetition(count: count, tracks: tracks))
}

/// Returns an auto-repeated track definition from string ("auto-fit" or "auto-fill")
@inlinable
public func repeat_<S: Sendable & Hashable>(_ countStr: String, _ tracks: [TrackSizingFunction]) -> GridTemplateComponent<S> {
    let repCount: RepetitionCount
    switch countStr {
    case "auto-fit": repCount = .autoFit
    case "auto-fill": repCount = .autoFill
    default: fatalError("String can only be converted to RepetitionCount if value is 'auto-fit' or 'auto-fill'")
    }
    return .repeat_(GridTemplateRepetition(count: repCount, tracks: tracks))
}

/// Returns an auto-repeated track definition from count
@inlinable
public func repeat_<S: Sendable & Hashable>(_ count: UInt16, _ tracks: [TrackSizingFunction]) -> GridTemplateComponent<S> {
    .repeat_(GridTemplateRepetition(count: .count(count), tracks: tracks))
}

/// Returns a grid template containing `count` evenly sized tracks
@inlinable
public func evenlySizedTracks<S: Sendable & Hashable>(_ count: UInt16) -> [GridTemplateComponent<S>] {
    let repeated = [flex(1.0)]
    return [repeat_(count, repeated)]
}
