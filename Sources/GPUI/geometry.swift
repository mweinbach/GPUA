// Ported from: crates/gpui/src/geometry.rs
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Foundation
import Refineable

// MARK: - Axis

/// Axis in a 2D cartesian space.
public enum Axis: Sendable, Equatable, Hashable, Codable {
    /// The y axis, or up and down
    case vertical
    /// The x axis, or left and right
    case horizontal

    /// Swap this axis to the opposite axis.
    public func invert() -> Axis {
        switch self {
        case .vertical: return .horizontal
        case .horizontal: return .vertical
        }
    }
}

// MARK: - Along Protocol

/// A trait for accessing the given unit along a certain axis.
public protocol Along {
    associatedtype Unit
    /// Returns the unit along the given axis.
    func along(_ axis: Axis) -> Unit
    /// Applies the given function to the unit along the given axis and returns a new value.
    func applyAlong(_ axis: Axis, _ f: (Unit) -> Unit) -> Self
}

// MARK: - Point

/// Describes a location in a 2D cartesian space.
public struct Point<T: Sendable & Equatable>: Sendable, Equatable {
    /// The x coordinate of the point.
    public var x: T
    /// The y coordinate of the point.
    public var y: T

    public init(x: T, y: T) {
        self.x = x
        self.y = y
    }

    public init(_ x: T, _ y: T) {
        self.x = x
        self.y = y
    }

    public func map<U: Sendable & Equatable>(_ f: (T) -> U) -> Point<U> {
        Point<U>(x: f(x), y: f(y))
    }
}

/// Constructs a new `Point<T>` with the given x and y coordinates.
public func point<T: Sendable & Equatable>(_ x: T, _ y: T) -> Point<T> {
    Point(x: x, y: y)
}

extension Point: Along {
    public typealias Unit = T

    public func along(_ axis: Axis) -> T {
        switch axis {
        case .horizontal: return x
        case .vertical: return y
        }
    }

    public func applyAlong(_ axis: Axis, _ f: (T) -> T) -> Point<T> {
        var copy = self
        switch axis {
        case .horizontal: copy.x = f(copy.x)
        case .vertical: copy.y = f(copy.y)
        }
        return copy
    }
}

extension Point where T: AdditiveArithmetic {
    public static var zero: Point<T> {
        Point(x: .zero, y: .zero)
    }

    public static func + (lhs: Point<T>, rhs: Point<T>) -> Point<T> {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func += (lhs: inout Point<T>, rhs: Point<T>) {
        lhs.x += rhs.x
        lhs.y += rhs.y
    }

    public static func - (lhs: Point<T>, rhs: Point<T>) -> Point<T> {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func -= (lhs: inout Point<T>, rhs: Point<T>) {
        lhs.x -= rhs.x
        lhs.y -= rhs.y
    }

    public func relativeTo(_ origin: Point<T>) -> Point<T> {
        self - origin
    }
}

extension Point where T: SignedNumeric {
    public static prefix func - (operand: Point<T>) -> Point<T> {
        Point(x: -operand.x, y: -operand.y)
    }
}

extension Point where T: Comparable {
    public func max(_ other: Point<T>) -> Point<T> {
        Point(x: Swift.max(self.x, other.x), y: Swift.max(self.y, other.y))
    }

    public func min(_ other: Point<T>) -> Point<T> {
        Point(x: Swift.min(self.x, other.x), y: Swift.min(self.y, other.y))
    }

    public func clamp(min: Point<T>, max: Point<T>) -> Point<T> {
        self.max(min).min(max)
    }
}

extension Point where T == Pixels {
    public func scale(_ factor: Float) -> Point<ScaledPixels> {
        Point<ScaledPixels>(x: x.scale(factor), y: y.scale(factor))
    }

    public func magnitude() -> Double {
        let xVal = Double(x.value)
        let yVal = Double(y.value)
        return (xVal * xVal + yVal * yVal).squareRoot()
    }

    public func floor() -> Point<Pixels> {
        Point(x: x.floor(), y: y.floor())
    }

    public func round() -> Point<Pixels> {
        Point(x: x.round(), y: y.round())
    }

    public func ceil() -> Point<Pixels> {
        Point(x: x.ceil(), y: y.ceil())
    }
}

extension Point where T == ScaledPixels {
    public func toDevicePixels() -> Point<DevicePixels> {
        Point<DevicePixels>(x: x.toDevicePixels(), y: y.toDevicePixels())
    }
}

extension Point where T == DevicePixels {
    public func toPixels(_ scaleFactor: Float) -> Point<Pixels> {
        Point<Pixels>(x: Pixels(Float(x.value) / scaleFactor), y: Pixels(Float(y.value) / scaleFactor))
    }
}

extension Point where T == Float {
    public static func * (lhs: Point<Float>, rhs: Float) -> Point<Float> {
        Point(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: Point<Float>, rhs: Float) -> Point<Float> {
        Point(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Point where T == Pixels {
    public static func * (lhs: Point<Pixels>, rhs: Float) -> Point<Pixels> {
        Point(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public static func / (lhs: Point<Pixels>, rhs: Float) -> Point<Pixels> {
        Point(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Point: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Point(x: \(x), y: \(y))"
    }

    public var debugDescription: String {
        description
    }
}

extension Point: Hashable where T: Hashable {}

// MARK: - Size

/// Describes dimensions in a 2D cartesian space.
public struct Size<T: Sendable & Equatable>: Sendable, Equatable {
    /// The width of the size.
    public var width: T
    /// The height of the size.
    public var height: T

    public init(width: T, height: T) {
        self.width = width
        self.height = height
    }

    public init(_ width: T, _ height: T) {
        self.width = width
        self.height = height
    }

    public func map<U: Sendable & Equatable>(_ f: (T) -> U) -> Size<U> {
        Size<U>(width: f(width), height: f(height))
    }
}

/// Constructs a new `Size<T>` with the given width and height.
public func size<T: Sendable & Equatable>(_ width: T, _ height: T) -> Size<T> {
    Size(width: width, height: height)
}

extension Size: Along {
    public typealias Unit = T

    public func along(_ axis: Axis) -> T {
        switch axis {
        case .horizontal: return width
        case .vertical: return height
        }
    }

    public func applyAlong(_ axis: Axis, _ f: (T) -> T) -> Size<T> {
        var copy = self
        switch axis {
        case .horizontal: copy.width = f(copy.width)
        case .vertical: copy.height = f(copy.height)
        }
        return copy
    }
}

extension Size where T: AdditiveArithmetic {
    public static var zero: Size<T> {
        Size(width: .zero, height: .zero)
    }

    public static func + (lhs: Size<T>, rhs: Size<T>) -> Size<T> {
        Size(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    public static func += (lhs: inout Size<T>, rhs: Size<T>) {
        lhs.width += rhs.width
        lhs.height += rhs.height
    }

    public static func - (lhs: Size<T>, rhs: Size<T>) -> Size<T> {
        Size(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }

    public static func -= (lhs: inout Size<T>, rhs: Size<T>) {
        lhs.width -= rhs.width
        lhs.height -= rhs.height
    }
}

extension Size where T: Half {
    public func center() -> Point<T> {
        Point(x: width.half(), y: height.half())
    }
}

extension Size where T: Comparable {
    public func max(_ other: Size<T>) -> Size<T> {
        Size(width: Swift.max(self.width, other.width), height: Swift.max(self.height, other.height))
    }

    public func min(_ other: Size<T>) -> Size<T> {
        Size(width: Swift.min(self.width, other.width), height: Swift.min(self.height, other.height))
    }

    public func clamp(min: Size<T>, max: Size<T>) -> Size<T> {
        self.max(min).min(max)
    }
}

extension Size where T == Pixels {
    public func scale(_ factor: Float) -> Size<ScaledPixels> {
        Size<ScaledPixels>(width: width.scale(factor), height: height.scale(factor))
    }

    public func toDevicePixels(_ factor: Float) -> Size<DevicePixels> {
        Size<DevicePixels>(
            width: DevicePixels(Int32((width.value * factor).rounded())),
            height: DevicePixels(Int32((height.value * factor).rounded()))
        )
    }

    public static func * (lhs: Size<Pixels>, rhs: Float) -> Size<Pixels> {
        Size(width: lhs.width * rhs, height: lhs.height * rhs)
    }

    public static func / (lhs: Size<Pixels>, rhs: Float) -> Size<Pixels> {
        Size(width: lhs.width / rhs, height: lhs.height / rhs)
    }
}

extension Size where T == ScaledPixels {
    public func toDevicePixels() -> Size<DevicePixels> {
        Size<DevicePixels>(width: width.toDevicePixels(), height: height.toDevicePixels())
    }

    public static func * (lhs: Size<ScaledPixels>, rhs: Float) -> Size<ScaledPixels> {
        Size(width: lhs.width * rhs, height: lhs.height * rhs)
    }

    public static func / (lhs: Size<ScaledPixels>, rhs: Float) -> Size<ScaledPixels> {
        Size(width: lhs.width / rhs, height: lhs.height / rhs)
    }
}

extension Size where T == DevicePixels {
    public func toPixels(_ scaleFactor: Float) -> Size<Pixels> {
        Size<Pixels>(
            width: Pixels(Float(width.value) / scaleFactor),
            height: Pixels(Float(height.value) / scaleFactor)
        )
    }
}

extension Size where T == Length {
    public static func full() -> Size<Length> {
        Size(width: .definite(relative(1.0)), height: .definite(relative(1.0)))
    }

    public static func auto() -> Size<Length> {
        Size(width: .auto, height: .auto)
    }
}

extension Size: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Size(width: \(width), height: \(height))"
    }

    public var debugDescription: String {
        description
    }
}

// Conversions between Point and Size
extension Size {
    public init(_ point: Point<T>) {
        self.width = point.x
        self.height = point.y
    }
}

extension Point {
    public init(_ size: Size<T>) {
        self.x = size.width
        self.y = size.height
    }
}

extension Size: Hashable where T: Hashable {}

// MARK: - Bounds

/// Represents a rectangle in a 2D space defined by origin and size.
public struct Bounds<T: Sendable & Equatable>: Sendable, Equatable {
    /// The origin (top-left point) of the bounds.
    public var origin: Point<T>
    /// The size (width and height) of the bounds.
    public var size: Size<T>

    public init(origin: Point<T>, size: Size<T>) {
        self.origin = origin
        self.size = size
    }

    public func map<U: Sendable & Equatable>(_ f: (T) -> U) -> Bounds<U> {
        Bounds<U>(origin: origin.map(f), size: size.map(f))
    }

    public func mapOrigin(_ f: (Point<T>) -> Point<T>) -> Bounds<T> {
        Bounds(origin: f(origin), size: size)
    }

    public func mapSize(_ f: (Size<T>) -> Size<T>) -> Bounds<T> {
        Bounds(origin: origin, size: f(size))
    }
}

/// Constructs a new `Bounds<T>` with the given origin and size.
public func bounds<T: Sendable & Equatable>(_ origin: Point<T>, _ size: Size<T>) -> Bounds<T> {
    Bounds(origin: origin, size: size)
}

extension Bounds where T: AdditiveArithmetic {
    public static var zero: Bounds<T> {
        Bounds(origin: .zero, size: .zero)
    }

    public init(topLeft: Point<T>, bottomRight: Point<T>) {
        self.origin = topLeft
        self.size = Size(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)
    }

    public static func fromCorners(_ topLeft: Point<T>, _ bottomRight: Point<T>) -> Bounds<T> {
        Bounds(topLeft: topLeft, bottomRight: bottomRight)
    }

    public var top: T { origin.y }
    public var bottom: T { origin.y + size.height }
    public var left: T { origin.x }
    public var right: T { origin.x + size.width }

    public var topLeft: Point<T> { origin }
    public var topRight: Point<T> { Point(x: origin.x + size.width, y: origin.y) }
    public var bottomLeft: Point<T> { Point(x: origin.x, y: origin.y + size.height) }
    public var bottomRight: Point<T> { Point(x: origin.x + size.width, y: origin.y + size.height) }

    public func corner(_ corner: Corner) -> Point<T> {
        switch corner {
        case .topLeft: return topLeft
        case .topRight: return topRight
        case .bottomLeft: return bottomLeft
        case .bottomRight: return bottomRight
        }
    }

    public func halfPerimeter() -> T {
        size.width + size.height
    }

    public static func + (lhs: Bounds<T>, rhs: Point<T>) -> Bounds<T> {
        Bounds(origin: lhs.origin + rhs, size: lhs.size)
    }

    public static func - (lhs: Bounds<T>, rhs: Point<T>) -> Bounds<T> {
        Bounds(origin: lhs.origin - rhs, size: lhs.size)
    }

    public func extend(_ edges: Edges<T>) -> Bounds<T> {
        Bounds(
            origin: Point(x: origin.x - edges.left, y: origin.y - edges.top),
            size: Size(width: size.width + edges.left + edges.right, height: size.height + edges.top + edges.bottom)
        )
    }

    public func spaceWithin(_ outer: Bounds<T>) -> Edges<T> {
        Edges(
            top: top - outer.top,
            right: outer.right - right,
            bottom: outer.bottom - bottom,
            left: left - outer.left
        )
    }
}

extension Bounds where T: AdditiveArithmetic {
    public static func fromCornerAndSize(corner: Corner, origin: Point<T>, size: Size<T>) -> Bounds<T> {
        Bounds(corner: corner, origin: origin, size: size)
    }

    public init(corner: Corner, origin: Point<T>, size: Size<T>) {
        switch corner {
        case .topLeft:
            self.origin = origin
        case .topRight:
            self.origin = Point(x: origin.x - size.width, y: origin.y)
        case .bottomLeft:
            self.origin = Point(x: origin.x, y: origin.y - size.height)
        case .bottomRight:
            self.origin = Point(x: origin.x - size.width, y: origin.y - size.height)
        }
        self.size = size
    }

    public func dilate(_ amount: T) -> Bounds<T> {
        Bounds(
            origin: Point(x: origin.x - amount, y: origin.y - amount),
            size: Size(width: size.width + amount + amount, height: size.height + amount + amount)
        )
    }

    public func inset(_ amount: T) -> Bounds<T> {
        Bounds(
            origin: Point(x: origin.x + amount, y: origin.y + amount),
            size: Size(width: size.width - amount - amount, height: size.height - amount - amount)
        )
    }
}

extension Bounds where T: AdditiveArithmetic & Half {
    public init(center: Point<T>, size: Size<T>) {
        self.origin = Point(x: center.x - size.width.half(), y: center.y - size.height.half())
        self.size = size
    }

    public func center() -> Point<T> {
        Point(x: origin.x + size.width.half(), y: origin.y + size.height.half())
    }
}

extension Bounds where T: AdditiveArithmetic & Comparable {
    /// Checks if this bounds intersects with another bounds using strict inequality.
    /// Touching edges is not considered an intersection.
    public func intersects(_ other: Bounds<T>) -> Bool {
        let myLowerRight = self.bottomRight
        let theirLowerRight = other.bottomRight

        return origin.x < theirLowerRight.x
            && myLowerRight.x > other.origin.x
            && origin.y < theirLowerRight.y
            && myLowerRight.y > other.origin.y
    }

    /// Computes intersection with another bounds.
    /// Disjoint bounds yield an empty bounds with zero size located at self.origin.max(other.origin).
    public func intersect(_ other: Bounds<T>) -> Bounds<T> {
        let upperLeft = self.origin.max(other.origin)
        let bottomRt = self.bottomRight.min(other.bottomRight).max(upperLeft)
        return Bounds(topLeft: upperLeft, bottomRight: bottomRt)
    }

    /// Computes union of two bounds.
    public func union(_ other: Bounds<T>) -> Bounds<T> {
        let topLeft = self.origin.min(other.origin)
        let bottomRt = self.bottomRight.max(other.bottomRight)
        return Bounds(topLeft: topLeft, bottomRight: bottomRt)
    }

    /// Checks if the point is within [origin, origin + size) (half-open interval).
    public func contains(_ point: Point<T>) -> Bool {
        point.x >= origin.x
            && point.x < origin.x + size.width
            && point.y >= origin.y
            && point.y < origin.y + size.height
    }

    /// Checks if this bounds is completely contained within another bounds.
    public func isContainedWithin(_ other: Bounds<T>) -> Bool {
        other.contains(self.origin) && other.contains(self.bottomRight)
    }

    public func localize(_ point: Point<T>) -> Point<T>? {
        contains(point) ? point.relativeTo(origin) : nil
    }

    public var isEmpty: Bool {
        size.width <= .zero || size.height <= .zero
    }
}

extension Bounds where T == Pixels {
    public func scale(_ factor: Float) -> Bounds<ScaledPixels> {
        Bounds<ScaledPixels>(origin: origin.scale(factor), size: size.scale(factor))
    }

    public func toDevicePixels(_ factor: Float) -> Bounds<DevicePixels> {
        Bounds<DevicePixels>(
            origin: Point<DevicePixels>(
                x: DevicePixels(Int32((origin.x.value * factor).rounded())),
                y: DevicePixels(Int32((origin.y.value * factor).rounded()))
            ),
            size: size.toDevicePixels(factor)
        )
    }
}

extension Bounds where T == ScaledPixels {
    public func toDevicePixels() -> Bounds<DevicePixels> {
        Bounds<DevicePixels>(origin: origin.toDevicePixels(), size: size.toDevicePixels())
    }
}

extension Bounds where T == DevicePixels {
    public func toPixels(_ scaleFactor: Float) -> Bounds<Pixels> {
        Bounds<Pixels>(origin: origin.toPixels(scaleFactor), size: size.toPixels(scaleFactor))
    }
}

extension Bounds: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Bounds(origin: \(origin), size: \(size))"
    }

    public var debugDescription: String {
        description
    }
}

extension Bounds: Hashable where T: Hashable {}

// MARK: - Edges

/// Represents the edges of a box in a 2D space, such as padding or margin.
public struct Edges<T: Sendable & Equatable>: Sendable, Equatable {
    public var top: T
    public var right: T
    public var bottom: T
    public var left: T

    public init(top: T, right: T, bottom: T, left: T) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public static func all(_ value: T) -> Edges<T> {
        Edges(top: value, right: value, bottom: value, left: value)
    }

    public func map<U: Sendable & Equatable>(_ f: (T) -> U) -> Edges<U> {
        Edges<U>(top: f(top), right: f(right), bottom: f(bottom), left: f(left))
    }

    public func any(_ predicate: (T) -> Bool) -> Bool {
        predicate(top) || predicate(right) || predicate(bottom) || predicate(left)
    }
}

extension Edges where T: AdditiveArithmetic {
    public static var zero: Edges<T> {
        Edges(top: .zero, right: .zero, bottom: .zero, left: .zero)
    }

    public static func + (lhs: Edges<T>, rhs: Edges<T>) -> Edges<T> {
        Edges(top: lhs.top + rhs.top, right: lhs.right + rhs.right, bottom: lhs.bottom + rhs.bottom, left: lhs.left + rhs.left)
    }
}

extension Edges where T == Pixels {
    public func scale(_ factor: Float) -> Edges<ScaledPixels> {
        Edges<ScaledPixels>(top: top.scale(factor), right: right.scale(factor), bottom: bottom.scale(factor), left: left.scale(factor))
    }

    public func max() -> Pixels {
        Swift.max(top, Swift.max(right, Swift.max(bottom, left)))
    }
}

extension Edges where T == Length {
    public static func auto() -> Edges<Length> {
        Edges.all(.auto)
    }

    public static var zero: Edges<Length> {
        Edges.all(.definite(.absolute(.pixels(Pixels(0.0)))))
    }
}

extension Edges where T == DefiniteLength {
    public static var zero: Edges<DefiniteLength> {
        Edges.all(.absolute(.pixels(Pixels(0.0))))
    }

    public func toPixels(parentSize: Size<AbsoluteLength>, remSize: Pixels) -> Edges<Pixels> {
        Edges<Pixels>(
            top: top.toPixels(baseSize: parentSize.height, remSize: remSize),
            right: right.toPixels(baseSize: parentSize.width, remSize: remSize),
            bottom: bottom.toPixels(baseSize: parentSize.height, remSize: remSize),
            left: left.toPixels(baseSize: parentSize.width, remSize: remSize)
        )
    }

    public func toPixels(parentSize: Size<Pixels>, remSize: Pixels) -> Edges<Pixels> {
        toPixels(parentSize: parentSize.map { AbsoluteLength.pixels($0) }, remSize: remSize)
    }
}

extension Edges where T == AbsoluteLength {
    public static var zero: Edges<AbsoluteLength> {
        Edges.all(.pixels(Pixels(0.0)))
    }

    public func toPixels(remSize: Pixels) -> Edges<Pixels> {
        Edges<Pixels>(
            top: top.toPixels(remSize: remSize),
            right: right.toPixels(remSize: remSize),
            bottom: bottom.toPixels(remSize: remSize),
            left: left.toPixels(remSize: remSize)
        )
    }
}

extension Edges: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Edges(top: \(top), right: \(right), bottom: \(bottom), left: \(left))"
    }

    public var debugDescription: String {
        description
    }
}

extension Edges: Hashable where T: Hashable {}

// MARK: - Corner & Corners

/// Identifies a corner of a 2d box.
public enum Corner: Sendable, Equatable, Hashable, Codable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public func oppositeCorner() -> Corner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }

    public func otherSideCornerAlong(_ axis: Axis) -> Corner {
        switch axis {
        case .vertical:
            switch self {
            case .topLeft: return .bottomLeft
            case .topRight: return .bottomRight
            case .bottomLeft: return .topLeft
            case .bottomRight: return .topRight
            }
        case .horizontal:
            switch self {
            case .topLeft: return .topRight
            case .topRight: return .topLeft
            case .bottomLeft: return .bottomRight
            case .bottomRight: return .bottomLeft
            }
        }
    }
}

/// Represents the corners of a box in a 2D space, such as border radius.
public struct Corners<T: Sendable & Equatable>: Sendable, Equatable {
    public var topLeft: T
    public var topRight: T
    public var bottomRight: T
    public var bottomLeft: T

    public init(topLeft: T, topRight: T, bottomRight: T, bottomLeft: T) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public static func all(_ value: T) -> Corners<T> {
        Corners(topLeft: value, topRight: value, bottomRight: value, bottomLeft: value)
    }

    public func corner(_ corner: Corner) -> T {
        switch corner {
        case .topLeft: return topLeft
        case .topRight: return topRight
        case .bottomLeft: return bottomLeft
        case .bottomRight: return bottomRight
        }
    }

    public func map<U: Sendable & Equatable>(_ f: (T) -> U) -> Corners<U> {
        Corners<U>(topLeft: f(topLeft), topRight: f(topRight), bottomRight: f(bottomRight), bottomLeft: f(bottomLeft))
    }
}

extension Corners where T: AdditiveArithmetic {
    public static var zero: Corners<T> {
        Corners(topLeft: .zero, topRight: .zero, bottomRight: .zero, bottomLeft: .zero)
    }
}

extension Corners where T: Comparable & FloatingPoint {
    public func clampRadiiForQuadSize(_ size: Size<T>) -> Corners<T> {
        let maxRadius = Swift.min(size.width, size.height) / 2
        return Corners(
            topLeft: Swift.min(topLeft, maxRadius),
            topRight: Swift.min(topRight, maxRadius),
            bottomRight: Swift.min(bottomRight, maxRadius),
            bottomLeft: Swift.min(bottomLeft, maxRadius)
        )
    }
}

extension Corners where T == Pixels {
    public func clampRadiiForQuadSize(_ size: Size<Pixels>) -> Corners<Pixels> {
        let maxRadius = Swift.min(size.width.value, size.height.value) / 2.0
        let maxPx = Pixels(maxRadius)
        return Corners(
            topLeft: Swift.min(topLeft, maxPx),
            topRight: Swift.min(topRight, maxPx),
            bottomRight: Swift.min(bottomRight, maxPx),
            bottomLeft: Swift.min(bottomLeft, maxPx)
        )
    }

    public func scale(_ factor: Float) -> Corners<ScaledPixels> {
        Corners<ScaledPixels>(
            topLeft: topLeft.scale(factor),
            topRight: topRight.scale(factor),
            bottomRight: bottomRight.scale(factor),
            bottomLeft: bottomLeft.scale(factor)
        )
    }

    public func max() -> Pixels {
        Swift.max(topLeft, Swift.max(topRight, Swift.max(bottomRight, bottomLeft)))
    }
}

extension Corners where T == AbsoluteLength {
    public static var zero: Corners<AbsoluteLength> {
        Corners.all(.pixels(Pixels(0.0)))
    }

    public func toPixels(remSize: Pixels) -> Corners<Pixels> {
        Corners<Pixels>(
            topLeft: topLeft.toPixels(remSize: remSize),
            topRight: topRight.toPixels(remSize: remSize),
            bottomRight: bottomRight.toPixels(remSize: remSize),
            bottomLeft: bottomLeft.toPixels(remSize: remSize)
        )
    }
}

extension Corners where T == ScaledPixels {
    public func clampRadiiForQuadSize(_ size: Size<ScaledPixels>) -> Corners<ScaledPixels> {
        let maxRadius = Swift.min(size.width.value, size.height.value) / 2.0
        let maxPx = ScaledPixels(maxRadius)
        return Corners(
            topLeft: Swift.min(topLeft, maxPx),
            topRight: Swift.min(topRight, maxPx),
            bottomRight: Swift.min(bottomRight, maxPx),
            bottomLeft: Swift.min(bottomLeft, maxPx)
        )
    }
}

extension Corners: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "Corners(topLeft: \(topLeft), topRight: \(topRight), bottomRight: \(bottomRight), bottomLeft: \(bottomLeft))"
    }

    public var debugDescription: String {
        description
    }
}

extension Corners: Hashable where T: Hashable {}

// MARK: - Radians & Percentage

/// Represents an angle in Radians.
public struct Radians: Sendable, Equatable, Hashable, Comparable, AdditiveArithmetic {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public static var zero: Radians { Radians(0.0) }

    public static func + (lhs: Radians, rhs: Radians) -> Radians {
        Radians(lhs.value + rhs.value)
    }

    public static func - (lhs: Radians, rhs: Radians) -> Radians {
        Radians(lhs.value - rhs.value)
    }

    public static func < (lhs: Radians, rhs: Radians) -> Bool {
        lhs.value < rhs.value
    }
}

public func radians(_ value: Float) -> Radians {
    Radians(value)
}

/// A type representing a percentage value in [0.0, 1.0].
public struct Percentage: Sendable, Equatable, Hashable, Comparable {
    public var value: Float

    public init(_ value: Float) {
        assert(value >= 0.0 && value <= 1.0, "Percentage must be between 0 and 1")
        self.value = value
    }

    public static func < (lhs: Percentage, rhs: Percentage) -> Bool {
        lhs.value < rhs.value
    }

    public func toRadians() -> Radians {
        radians(value * Float.pi * 2.0)
    }
}

public func percentage(_ value: Float) -> Percentage {
    Percentage(value)
}

// MARK: - Pixels

/// Represents a length in pixels, the base unit of measurement in the UI framework.
public struct Pixels: Sendable, Equatable, Hashable, Comparable, AdditiveArithmetic, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public init(floatLiteral value: Float) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = Float(value)
    }

    public static var zero: Pixels { Pixels(0.0) }
    public static let max: Pixels = Pixels(Float.greatestFiniteMagnitude)
    public static let min: Pixels = Pixels(-Float.greatestFiniteMagnitude)

    public var asF32: Float { value }

    public func floor() -> Pixels { Pixels(value.rounded(.down)) }
    public func round() -> Pixels { Pixels(value.rounded()) }
    public func ceil() -> Pixels { Pixels(value.rounded(.up)) }
    public func scale(_ factor: Float) -> ScaledPixels { ScaledPixels(value * factor) }
    public func pow(_ exponent: Float) -> Pixels { Pixels(powf(value, exponent)) }
    public func abs() -> Pixels { Pixels(Swift.abs(value)) }
    public func signum() -> Float { value == 0 ? 0 : (value > 0 ? 1.0 : -1.0) }
    public func toF64() -> Double { Double(value) }

    public static func + (lhs: Pixels, rhs: Pixels) -> Pixels { Pixels(lhs.value + rhs.value) }
    public static func - (lhs: Pixels, rhs: Pixels) -> Pixels { Pixels(lhs.value - rhs.value) }
    public static prefix func - (operand: Pixels) -> Pixels { Pixels(-operand.value) }

    public static func * (lhs: Pixels, rhs: Float) -> Pixels { Pixels(lhs.value * rhs) }
    public static func * (lhs: Float, rhs: Pixels) -> Pixels { Pixels(lhs * rhs.value) }
    public static func * (lhs: Pixels, rhs: Int) -> Pixels { Pixels(lhs.value * Float(rhs)) }
    public static func * (lhs: Int, rhs: Pixels) -> Pixels { Pixels(Float(lhs) * rhs.value) }

    public static func / (lhs: Pixels, rhs: Pixels) -> Float { lhs.value / rhs.value }
    public static func / (lhs: Pixels, rhs: Float) -> Pixels { Pixels(lhs.value / rhs) }

    public static func < (lhs: Pixels, rhs: Pixels) -> Bool {
        lhs.value < rhs.value
    }

    public init?(parsing string: String) {
        guard string.hasSuffix("px") else { return nil }
        let numStr = string.dropLast(2)
        guard let f = Float(numStr) else { return nil }
        self.value = f
    }
}

public func px(_ value: Float) -> Pixels {
    Pixels(value)
}

extension Pixels: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(value)px"
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - DevicePixels

/// Represents physical pixels on the display.
public struct DevicePixels: Sendable, Equatable, Hashable, Comparable, AdditiveArithmetic, ExpressibleByIntegerLiteral {
    public var value: Int32

    public init(_ value: Int32) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = Int32(value)
    }

    public static var zero: DevicePixels { DevicePixels(0) }

    public func toBytes(bytesPerPixel: UInt8) -> UInt32 {
        UInt32(value) * UInt32(bytesPerPixel)
    }

    public static func + (lhs: DevicePixels, rhs: DevicePixels) -> DevicePixels { DevicePixels(lhs.value + rhs.value) }
    public static func - (lhs: DevicePixels, rhs: DevicePixels) -> DevicePixels { DevicePixels(lhs.value - rhs.value) }
    public static prefix func - (operand: DevicePixels) -> DevicePixels { DevicePixels(-operand.value) }

    public static func < (lhs: DevicePixels, rhs: DevicePixels) -> Bool { lhs.value < rhs.value }
}

extension DevicePixels: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(value) px (device)"
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - ScaledPixels

/// Represents scaled pixels that take into account the device's scale factor.
public struct ScaledPixels: Sendable, Equatable, Hashable, Comparable, AdditiveArithmetic, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public init(floatLiteral value: Float) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = Float(value)
    }

    public static var zero: ScaledPixels { ScaledPixels(0.0) }

    public var asF32: Float { value }

    public func floor() -> ScaledPixels { ScaledPixels(value.rounded(.down)) }
    public func round() -> ScaledPixels { ScaledPixels(value.rounded()) }
    public func ceil() -> ScaledPixels { ScaledPixels(value.rounded(.up)) }

    public func toDevicePixels() -> DevicePixels {
        DevicePixels(Int32(value.rounded(.up)))
    }

    public static func + (lhs: ScaledPixels, rhs: ScaledPixels) -> ScaledPixels { ScaledPixels(lhs.value + rhs.value) }
    public static func - (lhs: ScaledPixels, rhs: ScaledPixels) -> ScaledPixels { ScaledPixels(lhs.value - rhs.value) }
    public static prefix func - (operand: ScaledPixels) -> ScaledPixels { ScaledPixels(-operand.value) }

    public static func * (lhs: ScaledPixels, rhs: Float) -> ScaledPixels { ScaledPixels(lhs.value * rhs) }
    public static func * (lhs: Float, rhs: ScaledPixels) -> ScaledPixels { ScaledPixels(lhs * rhs.value) }
    public static func / (lhs: ScaledPixels, rhs: ScaledPixels) -> Float { lhs.value / rhs.value }
    public static func / (lhs: ScaledPixels, rhs: Float) -> ScaledPixels { ScaledPixels(lhs.value / rhs) }

    public static func < (lhs: ScaledPixels, rhs: ScaledPixels) -> Bool {
        lhs.value < rhs.value
    }
}

extension ScaledPixels: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(value)px (scaled)"
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - Rems

/// Represents a length in rems, a unit based on the font-size of the window.
public struct Rems: Sendable, Equatable, Hashable, Comparable, AdditiveArithmetic, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    public var value: Float

    public init(_ value: Float) {
        self.value = value
    }

    public init(floatLiteral value: Float) {
        self.value = value
    }

    public init(integerLiteral value: Int) {
        self.value = Float(value)
    }

    public static var zero: Rems { Rems(0.0) }

    public func toPixels(remSize: Pixels) -> Pixels {
        Pixels(value * remSize.value)
    }

    public static func + (lhs: Rems, rhs: Rems) -> Rems { Rems(lhs.value + rhs.value) }
    public static func - (lhs: Rems, rhs: Rems) -> Rems { Rems(lhs.value - rhs.value) }
    public static prefix func - (operand: Rems) -> Rems { Rems(-operand.value) }

    public static func * (lhs: Rems, rhs: Pixels) -> Pixels { Pixels(lhs.value * rhs.value) }
    public static func * (lhs: Rems, rhs: Float) -> Rems { Rems(lhs.value * rhs) }

    public static func < (lhs: Rems, rhs: Rems) -> Bool {
        lhs.value < rhs.value
    }

    public init?(parsing string: String) {
        guard string.hasSuffix("rem") else { return nil }
        let numStr = string.dropLast(3)
        guard let f = Float(numStr) else { return nil }
        self.value = f
    }
}

public func rems(_ value: Float) -> Rems {
    Rems(value)
}

extension Rems: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "\(value)rem"
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - AbsoluteLength

/// Represents an absolute length in pixels or rems.
public enum AbsoluteLength: Sendable, Equatable, Hashable {
    case pixels(Pixels)
    case rems(Rems)

    public var isZero: Bool {
        switch self {
        case .pixels(let px): return px.value == 0.0
        case .rems(let r): return r.value == 0.0
        }
    }

    public func toPixels(remSize: Pixels) -> Pixels {
        switch self {
        case .pixels(let px): return px
        case .rems(let r): return r.toPixels(remSize: remSize)
        }
    }

    public func toRems(remSize: Pixels) -> Rems {
        switch self {
        case .pixels(let px): return Rems(px.value / remSize.value)
        case .rems(let r): return r
        }
    }

    public init?(parsing string: String) {
        if let p = Pixels(parsing: string) {
            self = .pixels(p)
        } else if let r = Rems(parsing: string) {
            self = .rems(r)
        } else {
            return nil
        }
    }

    public init(_ px: Pixels) {
        self = .pixels(px)
    }

    public init(_ r: Rems) {
        self = .rems(r)
    }
}

extension AbsoluteLength: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .pixels(let px): return px.description
        case .rems(let r): return r.description
        }
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - DefiniteLength

/// A non-auto length that can be defined in pixels, rems, or percent of parent.
public enum DefiniteLength: Sendable, Equatable, Hashable {
    case absolute(AbsoluteLength)
    case fraction(Float)

    public static var zero: DefiniteLength { .absolute(.pixels(Pixels(0.0))) }
    public static func pixels(_ px: Pixels) -> DefiniteLength { .absolute(.pixels(px)) }
    public static func rems(_ r: Rems) -> DefiniteLength { .absolute(.rems(r)) }

    public var isZero: Bool {
        switch self {
        case .absolute(let abs): return abs.isZero
        case .fraction(let f): return f == 0.0
        }
    }

    public func toPixels(baseSize: AbsoluteLength, remSize: Pixels) -> Pixels {
        switch self {
        case .absolute(let abs):
            return abs.toPixels(remSize: remSize)
        case .fraction(let f):
            switch baseSize {
            case .pixels(let px):
                return px * f
            case .rems(let r):
                return r.toPixels(remSize: remSize) * f
            }
        }
    }

    public init?(parsing string: String) {
        if string.hasSuffix("%") {
            let numStr = string.dropLast(1)
            guard let f = Float(numStr) else { return nil }
            self = .fraction(f / 100.0)
        } else if let abs = AbsoluteLength(parsing: string) {
            self = .absolute(abs)
        } else {
            return nil
        }
    }
}

public func relative(_ fraction: Float) -> DefiniteLength {
    DefiniteLength.fraction(fraction)
}

public func phi() -> DefiniteLength {
    relative(1.618034)
}

extension DefiniteLength: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .absolute(let abs): return abs.description
        case .fraction(let f): return "\(Int(f * 100.0))%"
        }
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - Length

/// A length that can be defined in pixels, rems, percent of parent, or auto.
public enum Length: Sendable, Equatable, Hashable {
    case definite(DefiniteLength)
    case auto

    public var isZero: Bool {
        switch self {
        case .definite(let def): return def.isZero
        case .auto: return false
        }
    }

    public init?(parsing string: String) {
        if string == "auto" {
            self = .auto
        } else if let def = DefiniteLength(parsing: string) {
            self = .definite(def)
        } else {
            return nil
        }
    }

    public init(_ px: Pixels) {
        self = .definite(.pixels(px))
    }

    public init(_ r: Rems) {
        self = .definite(.rems(r))
    }

    public init(_ def: DefiniteLength) {
        self = .definite(def)
    }

    public static func pixels(_ px: Pixels) -> Length {
        .definite(.pixels(px))
    }

    public static func rems(_ r: Rems) -> Length {
        .definite(.rems(r))
    }
}

extension DefiniteLength {
    public init(_ px: Pixels) {
        self = .absolute(.pixels(px))
    }

    public init(_ r: Rems) {
        self = .absolute(.rems(r))
    }
}

public func auto() -> Length {
    Length.auto
}

extension Length: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .definite(let def): return def.description
        case .auto: return "auto"
        }
    }

    public var debugDescription: String {
        description
    }
}

// MARK: - GridPlacement & GridLocation

public enum GridPlacement: Sendable, Equatable, Hashable {
    case line(Int16)
    case span(UInt16)
    case auto
}

public struct GridLocation: Sendable, Equatable, Hashable {
    public var row: Range<Int>
    public var column: Range<Int>

    public init(row: Range<Int>, column: Range<Int>) {
        self.row = row
        self.column = column
    }

    public init() {
        self.row = 0..<0
        self.column = 0..<0
    }
}

extension GridLocation: DefaultInitializable {}

// MARK: - Half & IsZero Protocols

/// Provides a trait for types that can calculate half of their value.
public protocol Half {
    func half() -> Self
}

extension Int32: Half {
    public func half() -> Int32 { self / 2 }
}

extension Float: Half {
    public func half() -> Float { self / 2.0 }
}

extension Double: Half {
    public func half() -> Double { self / 2.0 }
}

extension DevicePixels: Half {
    public func half() -> DevicePixels { DevicePixels(value / 2) }
}

extension ScaledPixels: Half {
    public func half() -> ScaledPixels { ScaledPixels(value / 2.0) }
}

extension Pixels: Half {
    public func half() -> Pixels { Pixels(value / 2.0) }
}

extension Rems: Half {
    public func half() -> Rems { Rems(value / 2.0) }
}

/// A trait for checking if a value is zero.
public protocol IsZero {
    var isZero: Bool { get }
}

extension DevicePixels: IsZero {
    public var isZero: Bool { value == 0 }
}

extension ScaledPixels: IsZero {
    public var isZero: Bool { value == 0.0 }
}

extension Pixels: IsZero {
    public var isZero: Bool { value == 0.0 }
}

extension Rems: IsZero {
    public var isZero: Bool { value == 0.0 }
}

extension AbsoluteLength: IsZero {}
extension DefiniteLength: IsZero {}
extension Length: IsZero {}

extension Point: IsZero where T: IsZero {
    public var isZero: Bool { x.isZero && y.isZero }
}

extension Size: IsZero where T: IsZero {
    public var isZero: Bool { width.isZero || height.isZero }
}

extension Bounds: IsZero where T: IsZero {
    public var isZero: Bool { size.isZero }
}

extension Corners: IsZero where T: IsZero {
    public var isZero: Bool {
        topLeft.isZero && topRight.isZero && bottomRight.isZero && bottomLeft.isZero
    }
}

// MARK: - ContentMask

/// Indicates which region of the window is visible.
public struct ContentMask<P: Sendable & Equatable>: Sendable, Equatable {
    public var bounds: Bounds<P>

    public init(bounds: Bounds<P>) {
        self.bounds = bounds
    }
}

extension ContentMask: Hashable where P: Hashable {}

extension ContentMask where P == Pixels {
    public func scale(_ factor: Float) -> ContentMask<ScaledPixels> {
        ContentMask<ScaledPixels>(bounds: bounds.scale(factor))
    }

    public func intersect(_ other: ContentMask<Pixels>) -> ContentMask<Pixels> {
        ContentMask(bounds: bounds.intersect(other.bounds))
    }
}

extension ContentMask where P == ScaledPixels {
    public func intersect(_ other: ContentMask<ScaledPixels>) -> ContentMask<ScaledPixels> {
        ContentMask(bounds: bounds.intersect(other.bounds))
    }
}

// MARK: - Refineable Conformances for Geometry Types

public struct PointRefinement<T: Sendable & Equatable>: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = PointRefinement<T>

    public var x: T?
    public var y: T?

    public init(x: T? = nil, y: T? = nil) {
        self.x = x
        self.y = y
    }

    public init() {
        self.x = nil
        self.y = nil
    }

    public var isEmpty: Bool {
        x == nil && y == nil
    }

    public mutating func refine(with refinement: PointRefinement<T>) {
        if let x = refinement.x { self.x = x }
        if let y = refinement.y { self.y = y }
    }

    public func isSuperset(of refinement: PointRefinement<T>) -> Bool {
        if let rx = refinement.x, x != rx { return false }
        if let ry = refinement.y, y != ry { return false }
        return true
    }

    public func subtract(_ refinement: PointRefinement<T>) -> PointRefinement<T> {
        PointRefinement(
            x: self.x == refinement.x ? nil : self.x,
            y: self.y == refinement.y ? nil : self.y
        )
    }
}

extension Point: Refineable {
    public typealias Refinement = PointRefinement<T>

    public mutating func refine(with refinement: PointRefinement<T>) {
        if let x = refinement.x { self.x = x }
        if let y = refinement.y { self.y = y }
    }

    public func isSuperset(of refinement: PointRefinement<T>) -> Bool {
        if let rx = refinement.x, self.x != rx { return false }
        if let ry = refinement.y, self.y != ry { return false }
        return true
    }

    public func subtract(_ refinement: PointRefinement<T>) -> PointRefinement<T> {
        PointRefinement(
            x: self.x == refinement.x ? nil : self.x,
            y: self.y == refinement.y ? nil : self.y
        )
    }
}

public struct SizeRefinement<T: Sendable & Equatable>: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = SizeRefinement<T>

    public var width: T?
    public var height: T?

    public init(width: T? = nil, height: T? = nil) {
        self.width = width
        self.height = height
    }

    public init() {
        self.width = nil
        self.height = nil
    }

    public var isEmpty: Bool {
        width == nil && height == nil
    }

    public mutating func refine(with refinement: SizeRefinement<T>) {
        if let w = refinement.width { self.width = w }
        if let h = refinement.height { self.height = h }
    }

    public func isSuperset(of refinement: SizeRefinement<T>) -> Bool {
        if let rw = refinement.width, width != rw { return false }
        if let rh = refinement.height, height != rh { return false }
        return true
    }

    public func subtract(_ refinement: SizeRefinement<T>) -> SizeRefinement<T> {
        SizeRefinement(
            width: self.width == refinement.width ? nil : self.width,
            height: self.height == refinement.height ? nil : self.height
        )
    }
}

extension Size: Refineable {
    public typealias Refinement = SizeRefinement<T>

    public mutating func refine(with refinement: SizeRefinement<T>) {
        if let w = refinement.width { self.width = w }
        if let h = refinement.height { self.height = h }
    }

    public func isSuperset(of refinement: SizeRefinement<T>) -> Bool {
        if let rw = refinement.width, self.width != rw { return false }
        if let rh = refinement.height, self.height != rh { return false }
        return true
    }

    public func subtract(_ refinement: SizeRefinement<T>) -> SizeRefinement<T> {
        SizeRefinement(
            width: self.width == refinement.width ? nil : self.width,
            height: self.height == refinement.height ? nil : self.height
        )
    }
}

public struct EdgesRefinement<T: Sendable & Equatable>: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = EdgesRefinement<T>

    public var top: T?
    public var right: T?
    public var bottom: T?
    public var left: T?

    public init(top: T? = nil, right: T? = nil, bottom: T? = nil, left: T? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init() {
        self.top = nil
        self.right = nil
        self.bottom = nil
        self.left = nil
    }

    public static func all(_ value: T) -> EdgesRefinement<T> {
        EdgesRefinement(top: value, right: value, bottom: value, left: value)
    }

    public var isEmpty: Bool {
        top == nil && right == nil && bottom == nil && left == nil
    }

    public mutating func refine(with refinement: EdgesRefinement<T>) {
        if let t = refinement.top { self.top = t }
        if let r = refinement.right { self.right = r }
        if let b = refinement.bottom { self.bottom = b }
        if let l = refinement.left { self.left = l }
    }

    public func isSuperset(of refinement: EdgesRefinement<T>) -> Bool {
        if let rt = refinement.top, top != rt { return false }
        if let rr = refinement.right, right != rr { return false }
        if let rb = refinement.bottom, bottom != rb { return false }
        if let rl = refinement.left, left != rl { return false }
        return true
    }

    public func subtract(_ refinement: EdgesRefinement<T>) -> EdgesRefinement<T> {
        EdgesRefinement(
            top: self.top == refinement.top ? nil : self.top,
            right: self.right == refinement.right ? nil : self.right,
            bottom: self.bottom == refinement.bottom ? nil : self.bottom,
            left: self.left == refinement.left ? nil : self.left
        )
    }
}

extension Edges: Refineable {
    public typealias Refinement = EdgesRefinement<T>

    public mutating func refine(with refinement: EdgesRefinement<T>) {
        if let t = refinement.top { self.top = t }
        if let r = refinement.right { self.right = r }
        if let b = refinement.bottom { self.bottom = b }
        if let l = refinement.left { self.left = l }
    }

    public func isSuperset(of refinement: EdgesRefinement<T>) -> Bool {
        if let rt = refinement.top, self.top != rt { return false }
        if let rr = refinement.right, self.right != rr { return false }
        if let rb = refinement.bottom, self.bottom != rb { return false }
        if let rl = refinement.left, self.left != rl { return false }
        return true
    }

    public func subtract(_ refinement: EdgesRefinement<T>) -> EdgesRefinement<T> {
        EdgesRefinement(
            top: self.top == refinement.top ? nil : self.top,
            right: self.right == refinement.right ? nil : self.right,
            bottom: self.bottom == refinement.bottom ? nil : self.bottom,
            left: self.left == refinement.left ? nil : self.left
        )
    }
}

public struct CornersRefinement<T: Sendable & Equatable>: Sendable, Equatable, Refineable, IsEmpty, DefaultInitializable {
    public typealias Refinement = CornersRefinement<T>

    public var topLeft: T?
    public var topRight: T?
    public var bottomRight: T?
    public var bottomLeft: T?

    public init(topLeft: T? = nil, topRight: T? = nil, bottomRight: T? = nil, bottomLeft: T? = nil) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init() {
        self.topLeft = nil
        self.topRight = nil
        self.bottomRight = nil
        self.bottomLeft = nil
    }

    public static func all(_ value: T) -> CornersRefinement<T> {
        CornersRefinement(topLeft: value, topRight: value, bottomRight: value, bottomLeft: value)
    }

    public var isEmpty: Bool {
        topLeft == nil && topRight == nil && bottomRight == nil && bottomLeft == nil
    }

    public mutating func refine(with refinement: CornersRefinement<T>) {
        if let tl = refinement.topLeft { self.topLeft = tl }
        if let tr = refinement.topRight { self.topRight = tr }
        if let br = refinement.bottomRight { self.bottomRight = br }
        if let bl = refinement.bottomLeft { self.bottomLeft = bl }
    }

    public func isSuperset(of refinement: CornersRefinement<T>) -> Bool {
        if let rtl = refinement.topLeft, topLeft != rtl { return false }
        if let rtr = refinement.topRight, topRight != rtr { return false }
        if let rbr = refinement.bottomRight, bottomRight != rbr { return false }
        if let rbl = refinement.bottomLeft, bottomLeft != rbl { return false }
        return true
    }

    public func subtract(_ refinement: CornersRefinement<T>) -> CornersRefinement<T> {
        CornersRefinement(
            topLeft: self.topLeft == refinement.topLeft ? nil : self.topLeft,
            topRight: self.topRight == refinement.topRight ? nil : self.topRight,
            bottomRight: self.bottomRight == refinement.bottomRight ? nil : self.bottomRight,
            bottomLeft: self.bottomLeft == refinement.bottomLeft ? nil : self.bottomLeft
        )
    }
}

extension Corners: Refineable {
    public typealias Refinement = CornersRefinement<T>

    public mutating func refine(with refinement: CornersRefinement<T>) {
        if let tl = refinement.topLeft { self.topLeft = tl }
        if let tr = refinement.topRight { self.topRight = tr }
        if let br = refinement.bottomRight { self.bottomRight = br }
        if let bl = refinement.bottomLeft { self.bottomLeft = bl }
    }

    public func isSuperset(of refinement: CornersRefinement<T>) -> Bool {
        if let rtl = refinement.topLeft, self.topLeft != rtl { return false }
        if let rtr = refinement.topRight, self.topRight != rtr { return false }
        if let rbr = refinement.bottomRight, self.bottomRight != rbr { return false }
        if let rbl = refinement.bottomLeft, self.bottomLeft != rbl { return false }
        return true
    }

    public func subtract(_ refinement: CornersRefinement<T>) -> CornersRefinement<T> {
        CornersRefinement(
            topLeft: self.topLeft == refinement.topLeft ? nil : self.topLeft,
            topRight: self.topRight == refinement.topRight ? nil : self.topRight,
            bottomRight: self.bottomRight == refinement.bottomRight ? nil : self.bottomRight,
            bottomLeft: self.bottomLeft == refinement.bottomLeft ? nil : self.bottomLeft
        )
    }
}

