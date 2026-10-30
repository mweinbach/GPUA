// Ported from: src/geometry.rs
// Upstream commit: 599b1b7d7410d97e13bafc4c01fbe6d7a9cf060a
// Port status: ported

/// The simple absolute horizontal and vertical axis
public enum AbsoluteAxis: Sendable, Hashable {
    /// The horizontal axis
    case horizontal
    /// The vertical axis
    case vertical

    /// Returns the other variant of the enum
    @inlinable
    public func otherAxis() -> AbsoluteAxis {
        switch self {
        case .horizontal: return .vertical
        case .vertical: return .horizontal
        }
    }
}

/// The CSS abstract axis
/// <https://www.w3.org/TR/css-writing-modes-3/#abstract-axes>
public enum AbstractAxis: Sendable, Hashable {
    /// The axis in the inline dimension
    case inline
    /// The axis in the block dimension
    case block

    /// Returns the other variant of the enum
    @inlinable
    public func other() -> AbstractAxis {
        switch self {
        case .inline: return .block
        case .block: return .inline
        }
    }

    /// Convert an `AbstractAxis` into an `AbsoluteAxis` naively assuming inline is horizontal
    @inlinable
    public func asAbsNaive() -> AbsoluteAxis {
        switch self {
        case .inline: return .horizontal
        case .block: return .vertical
        }
    }
}

/// Container that holds an item in each absolute axis
public struct InBothAbsAxis<T: Sendable>: Sendable {
    /// The item in the horizontal axis
    public var horizontal: T
    /// The item in the vertical axis
    public var vertical: T

    @inlinable
    public init(horizontal: T, vertical: T) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// Get the contained item based on the AbsoluteAxis passed
    @inlinable
    public func get(axis: AbsoluteAxis) -> T {
        switch axis {
        case .horizontal: return horizontal
        case .vertical: return vertical
        }
    }
}

extension InBothAbsAxis: Equatable where T: Equatable {}
extension InBothAbsAxis: Hashable where T: Hashable {}

/// An axis-aligned UI rectangle
public struct Rect<T: Sendable>: Sendable {
    /// Starting edge x-coord or left padding
    public var left: T
    /// Ending edge x-coord or right padding
    public var right: T
    /// Top edge y-coord or top padding
    public var top: T
    /// Bottom edge y-coord or bottom padding
    public var bottom: T

    @inlinable
    public init(left: T, right: T, top: T, bottom: T) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }
}

extension Rect: Equatable where T: Equatable {}
extension Rect: Hashable where T: Hashable {}

extension Rect where T: AdditiveArithmetic {
    @inlinable
    public static func + (lhs: Rect<T>, rhs: Rect<T>) -> Rect<T> {
        Rect(
            left: lhs.left + rhs.left,
            right: lhs.right + rhs.right,
            top: lhs.top + rhs.top,
            bottom: lhs.bottom + rhs.bottom
        )
    }

    /// The sum of left and right
    @inlinable
    public func horizontalAxisSum() -> T {
        left + right
    }

    /// The sum of top and bottom
    @inlinable
    public func verticalAxisSum() -> T {
        top + bottom
    }

    /// Both horizontalAxisSum and verticalAxisSum as a Size<T>
    @inlinable
    public func sumAxes() -> Size<T> {
        Size(width: horizontalAxisSum(), height: verticalAxisSum())
    }

    /// The sum of the fields representing the main axis
    @inlinable
    public func mainAxisSum(direction: FlexDirection) -> T {
        if direction.isRow {
            return horizontalAxisSum()
        } else {
            return verticalAxisSum()
        }
    }

    /// The sum of the fields representing the cross axis
    @inlinable
    public func crossAxisSum(direction: FlexDirection) -> T {
        if direction.isRow {
            return verticalAxisSum()
        } else {
            return horizontalAxisSum()
        }
    }

    /// Get either horizontal or vertical sum depending on the AbsoluteAxis
    @inlinable
    public func gridAxisSum(axis: AbsoluteAxis) -> T {
        switch axis {
        case .horizontal: return left + right
        case .vertical: return top + bottom
        }
    }
}

extension Rect {
    /// Applies function f to all four sides of the rect using size dimensions
    @inlinable
    public func zipSize<R, U>(size: Size<U>, _ f: (T, U) -> R) -> Rect<R> {
        Rect<R>(
            left: f(self.left, size.width),
            right: f(self.right, size.width),
            top: f(self.top, size.height),
            bottom: f(self.bottom, size.height)
        )
    }

    /// Transforms a Rect<T> into a Rect<R>
    @inlinable
    public func map<R>(_ f: (T) -> R) -> Rect<R> {
        Rect<R>(left: f(left), right: f(right), top: f(top), bottom: f(bottom))
    }

    /// Returns a Line<T> representing left and right
    @inlinable
    public func horizontalComponents() -> Line<T> {
        Line(start: left, end: right)
    }

    /// Returns a Line<T> representing top and bottom
    @inlinable
    public func verticalComponents() -> Line<T> {
        Line(start: top, end: bottom)
    }

    /// Main start value based on FlexDirection
    @inlinable
    public func mainStart(direction: FlexDirection) -> T {
        direction.isRow ? left : top
    }

    /// Main end value based on FlexDirection
    @inlinable
    public func mainEnd(direction: FlexDirection) -> T {
        direction.isRow ? right : bottom
    }

    /// Cross start value based on FlexDirection
    @inlinable
    public func crossStart(direction: FlexDirection) -> T {
        direction.isRow ? top : left
    }

    /// Cross end value based on FlexDirection
    @inlinable
    public func crossEnd(direction: FlexDirection) -> T {
        direction.isRow ? bottom : right
    }
}

extension Rect where T == Float {
    /// Creates a new Rect with 0.0 as all parameters
    public static let ZERO: Rect<Float> = Rect(left: 0.0, right: 0.0, top: 0.0, bottom: 0.0)

    /// Creates a new Rect
    @inlinable
    public static func new(start: Float, end: Float, top: Float, bottom: Float) -> Rect<Float> {
        Rect(left: start, right: end, top: top, bottom: bottom)
    }
}

/// An abstract "line". Represents any type that has a start and an end
public struct Line<T: Sendable>: Sendable {
    /// The start position of a line
    public var start: T
    /// The end position of a line
    public var end: T

    @inlinable
    public init(start: T, end: T) {
        self.start = start
        self.end = end
    }

    /// Transforms a Line<T> into a Line<R>
    @inlinable
    public func map<R>(_ f: (T) -> R) -> Line<R> {
        Line<R>(start: f(start), end: f(end))
    }
}

extension Line: Equatable where T: Equatable {}
extension Line: Hashable where T: Hashable {}

extension Line where T == Bool {
    public static let TRUE = Line(start: true, end: true)
    public static let FALSE = Line(start: false, end: false)
}

extension Line where T: AdditiveArithmetic {
    /// Adds start and end together
    @inlinable
    public func sum() -> T {
        start + end
    }
}

/// The width and height of a rectangle
public struct Size<T: Sendable>: Sendable {
    /// The x extent
    public var width: T
    /// The y extent
    public var height: T

    @inlinable
    public init(width: T, height: T) {
        self.width = width
        self.height = height
    }

    /// Get either width or height depending on the AbsoluteAxis
    @inlinable
    public func getAbs(axis: AbsoluteAxis) -> T {
        switch axis {
        case .horizontal: return width
        case .vertical: return height
        }
    }

    @inlinable
    public func getAbs(_ axis: AbsoluteAxis) -> T {
        getAbs(axis: axis)
    }
}

extension Size: Equatable where T: Equatable {}
extension Size: Hashable where T: Hashable {}

extension Size where T: AdditiveArithmetic {
    @inlinable
    public static func + (lhs: Size<T>, rhs: Size<T>) -> Size<T> {
        Size(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    @inlinable
    public static func - (lhs: Size<T>, rhs: Size<T>) -> Size<T> {
        Size(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
}

extension Size {
    /// Transforms Size<T> into Size<R>
    @inlinable
    public func map<R>(_ f: (T) -> R) -> Size<R> {
        Size<R>(width: f(width), height: f(height))
    }

    /// Transforms width
    @inlinable
    public func mapWidth(_ f: (T) -> T) -> Size<T> {
        Size(width: f(width), height: height)
    }

    /// Transforms height
    @inlinable
    public func mapHeight(_ f: (T) -> T) -> Size<T> {
        Size(width: width, height: f(height))
    }

    /// Applies f to both width and height of this value and another
    @inlinable
    public func zipMap<Other, Ret>(_ other: Size<Other>, _ f: (T, Other) -> Ret) -> Size<Ret> {
        Size<Ret>(width: f(self.width, other.width), height: f(self.height, other.height))
    }

    /// Sets the extent of the main layout axis
    @inlinable
    public mutating func setMain(direction: FlexDirection, value: T) {
        if direction.isRow {
            width = value
        } else {
            height = value
        }
    }

    /// Sets the extent of the cross layout axis
    @inlinable
    public mutating func setCross(direction: FlexDirection, value: T) {
        if direction.isRow {
            height = value
        } else {
            width = value
        }
    }

    /// Returns a new Size with main axis set to value
    @inlinable
    public func withMain(direction: FlexDirection, value: T) -> Size<T> {
        var copy = self
        copy.setMain(direction: direction, value: value)
        return copy
    }

    /// Returns a new Size with cross axis set to value
    @inlinable
    public func withCross(direction: FlexDirection, value: T) -> Size<T> {
        var copy = self
        copy.setCross(direction: direction, value: value)
        return copy
    }

    /// Returns a new Size with main axis modified
    @inlinable
    public func mapMain(direction: FlexDirection, _ mapper: (T) -> T) -> Size<T> {
        var copy = self
        if direction.isRow {
            copy.width = mapper(copy.width)
        } else {
            copy.height = mapper(copy.height)
        }
        return copy
    }

    /// Returns a new Size with cross axis modified
    @inlinable
    public func mapCross(direction: FlexDirection, _ mapper: (T) -> T) -> Size<T> {
        var copy = self
        if direction.isRow {
            copy.height = mapper(copy.height)
        } else {
            copy.width = mapper(copy.width)
        }
        return copy
    }

    /// Gets extent of the main axis
    @inlinable
    public func main(direction: FlexDirection) -> T {
        direction.isRow ? width : height
    }

    /// Gets extent of the cross axis
    @inlinable
    public func cross(direction: FlexDirection) -> T {
        direction.isRow ? height : width
    }

    /// Gets the extent of the specified layout axis
    @inlinable
    public func get(axis: AbstractAxis) -> T {
        switch axis {
        case .inline: return width
        case .block: return height
        }
    }

    /// Sets the extent of the specified layout axis
    @inlinable
    public mutating func set(axis: AbstractAxis, value: T) {
        switch axis {
        case .inline: width = value
        case .block: height = value
        }
    }
}

extension Size where T == Float {
    /// Zero size
    public static let ZERO = Size<Float>(width: 0.0, height: 0.0)

    /// Applies f32_max to each component
    @inlinable
    public func f32Max(_ rhs: Size<Float>) -> Size<Float> {
        Size<Float>(width: f32_max(width, rhs.width), height: f32_max(height, rhs.height))
    }

    /// Applies f32_min to each component
    @inlinable
    public func f32Min(_ rhs: Size<Float>) -> Size<Float> {
        Size<Float>(width: f32_min(width, rhs.width), height: f32_min(height, rhs.height))
    }

    /// Return true if both width and height are greater than 0
    @inlinable
    public func hasNonZeroArea() -> Bool {
        width > 0.0 && height > 0.0
    }
}

extension Size where T == Float? {
    /// Size with nil width and height
    public static let NONE = Size<Float?>(width: nil, height: nil)

    @inlinable
    public static func new(width: Float, height: Float) -> Size<Float?> {
        Size<Float?>(width: width, height: height)
    }

    /// Creates a Size<Float?> from cross axis value
    @inlinable
    public static func fromCross(direction: FlexDirection, value: Float?) -> Size<Float?> {
        var s = Self.NONE
        if direction.isRow {
            s.height = value
        } else {
            s.width = value
        }
        return s
    }

    /// Applies aspect ratio
    @inlinable
    public func maybeApplyAspectRatio(_ aspectRatio: Float?) -> Size<Float?> {
        guard let ratio = aspectRatio else { return self }
        switch (width, height) {
        case let (.some(w), .none):
            return Size<Float?>(width: w, height: w / ratio)
        case let (.none, .some(h)):
            return Size<Float?>(width: h * ratio, height: h)
        default:
            return self
        }
    }

    /// Applies aspect ratio
    @inlinable
    public func maybeApplyAspectRatio(aspectRatio: Float?) -> Size<Float?> {
        maybeApplyAspectRatio(aspectRatio)
    }
}

extension Size {
    /// Performs unwrap or default on each component
    @inlinable
    public func unwrapOr<Wrapped>(_ alt: Size<Wrapped>) -> Size<Wrapped> where T == Wrapped? {
        Size<Wrapped>(width: width ?? alt.width, height: height ?? alt.height)
    }

    /// Performs or on each component
    @inlinable
    public func or<Wrapped>(_ alt: Size<Wrapped?>) -> Size<Wrapped?> where T == Wrapped? {
        Size<Wrapped?>(width: width ?? alt.width, height: height ?? alt.height)
    }

    /// Returns true if both components are non-nil
    @inlinable
    public func bothAxisDefined<Wrapped>() -> Bool where T == Wrapped? {
        width != nil && height != nil
    }
}

extension Size where T == Dimension {
    /// Generates a Size<Dimension> using length values
    @inlinable
    public static func fromLengths(width: Float, height: Float) -> Size<Dimension> {
        Size(width: .length(width), height: .length(height))
    }

    /// Generates a Size<Dimension> using percentage values
    @inlinable
    public static func fromPercent(width: Float, height: Float) -> Size<Dimension> {
        Size(width: .percent(width), height: .percent(height))
    }
}

/// A 2-dimensional coordinate
public struct Point<T: Sendable>: Sendable {
    /// The x-coordinate
    public var x: T
    /// The y-coordinate
    public var y: T

    @inlinable
    public init(x: T, y: T) {
        self.x = x
        self.y = y
    }
}

extension Point: Equatable where T: Equatable {}
extension Point: Hashable where T: Hashable {}

extension Point where T: AdditiveArithmetic {
    @inlinable
    public static func + (lhs: Point<T>, rhs: Point<T>) -> Point<T> {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

extension Point {
    /// Transforms Point<T> into Point<R>
    @inlinable
    public func map<R>(_ f: (T) -> R) -> Point<R> {
        Point<R>(x: f(x), y: f(y))
    }

    /// Converts a Point into a Size
    @inlinable
    public func intoSize() -> Size<T> {
        Size<T>(width: x, height: y)
    }

    /// Gets extent of specified abstract axis
    @inlinable
    public func get(axis: AbstractAxis) -> T {
        switch axis {
        case .inline: return x
        case .block: return y
        }
    }

    /// Sets extent of specified abstract axis
    @inlinable
    public mutating func set(axis: AbstractAxis, value: T) {
        switch axis {
        case .inline: x = value
        case .block: y = value
        }
    }

    /// Swap x and y components
    @inlinable
    public func transpose() -> Point<T> {
        Point(x: y, y: x)
    }

    /// Main component based on FlexDirection
    @inlinable
    public func main(direction: FlexDirection) -> T {
        direction.isRow ? x : y
    }

    /// Cross component based on FlexDirection
    @inlinable
    public func cross(direction: FlexDirection) -> T {
        direction.isRow ? y : x
    }
}

extension Point where T == Float {
    public static let ZERO = Point<Float>(x: 0.0, y: 0.0)
}

extension Point where T == Float? {
    public static let NONE = Point<Float?>(x: nil, y: nil)
}

extension Size {
    @inlinable
    public init(from point: Point<T>) {
        self.init(width: point.x, height: point.y)
    }
}

/// Generic struct which holds a min value and a max value
public struct MinMax<Min: Sendable, Max: Sendable>: Sendable {
    /// The value representing minimum
    public var min: Min
    /// The value representing maximum
    public var max: Max

    @inlinable
    public init(min: Min, max: Max) {
        self.min = min
        self.max = max
    }
}

extension MinMax: Equatable where Min: Equatable, Max: Equatable {}
extension MinMax: Hashable where Min: Hashable, Max: Hashable {}
