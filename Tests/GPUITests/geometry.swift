// Tests ported from: crates/gpui/src/geometry.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f4f6f85d42c965831935568ac1162
// Port status: ported

import Testing
@testable import GPUI

@Suite("Geometry Tests")
struct GeometryTests {

    // MARK: - Upstream Test Port
    // Ported from geometry.rs line 3838
    @Test("Upstream test_bounds_intersects")
    func test_bounds_intersects() {
        let bounds1 = Bounds(
            origin: Point(x: 0.0, y: 0.0),
            size: Size(width: 5.0, height: 5.0)
        )
        let bounds2 = Bounds(
            origin: Point(x: 4.0, y: 4.0),
            size: Size(width: 5.0, height: 5.0)
        )
        let bounds3 = Bounds(
            origin: Point(x: 10.0, y: 10.0),
            size: Size(width: 5.0, height: 5.0)
        )

        // Test Case 1: Intersecting bounds
        #expect(bounds1.intersects(bounds2))

        // Test Case 2: Non-Intersecting bounds
        #expect(!bounds1.intersects(bounds3))

        // Test Case 3: Bounds intersecting with themselves
        #expect(bounds1.intersects(bounds1))
    }

    // MARK: - Bounds Intersect & Disjoint Math
    @Test("Bounds intersect and disjoint zero-size at origin max")
    func test_bounds_intersection_math() {
        let b1 = Bounds(origin: Point(x: 0.0, y: 0.0), size: Size(width: 10.0, height: 10.0))
        let b2 = Bounds(origin: Point(x: 5.0, y: 5.0), size: Size(width: 10.0, height: 10.0))
        let intersection = b1.intersect(b2)
        #expect(intersection.origin == Point(x: 5.0, y: 5.0))
        #expect(intersection.size == Size(width: 5.0, height: 5.0))

        // Disjoint bounds: should return empty bounds with zero size located at self.origin.max(other.origin)
        let disjoint = Bounds(origin: Point(x: 20.0, y: 30.0), size: Size(width: 5.0, height: 5.0))
        let disjointIntersection = b1.intersect(disjoint)
        #expect(disjointIntersection.origin == Point(x: 20.0, y: 30.0))
        #expect(disjointIntersection.size == Size(width: 0.0, height: 0.0))
        #expect(disjointIntersection.isEmpty)

        // Adjacent bounds sharing an edge: strict inequality means NOT intersecting
        let adjacent = Bounds(origin: Point(x: 10.0, y: 0.0), size: Size(width: 10.0, height: 10.0))
        #expect(!b1.intersects(adjacent))
        let adjIntersection = b1.intersect(adjacent)
        #expect(adjIntersection.size.width == 0.0)
    }

    // MARK: - Bounds Union & SpaceWithin
    @Test("Bounds union and spaceWithin")
    func test_bounds_union_and_space() {
        let b1 = Bounds(origin: Point(x: 0.0, y: 0.0), size: Size(width: 10.0, height: 10.0))
        let b2 = Bounds(origin: Point(x: 5.0, y: 5.0), size: Size(width: 15.0, height: 15.0))
        let union = b1.union(b2)
        #expect(union.origin == Point(x: 0.0, y: 0.0))
        #expect(union.size == Size(width: 20.0, height: 20.0))

        let outer = Bounds(origin: Point(x: 0.0, y: 0.0), size: Size(width: 100.0, height: 100.0))
        let inner = Bounds(origin: Point(x: 10.0, y: 20.0), size: Size(width: 50.0, height: 40.0))
        let space = inner.spaceWithin(outer)
        #expect(space.top == 20.0)
        #expect(space.left == 10.0)
        #expect(space.right == 40.0)
        #expect(space.bottom == 40.0)
    }

    // MARK: - Bounds Containment (Half-Open Interval)
    @Test("Bounds contains half-open interval")
    func test_bounds_contains() {
        let b = Bounds(origin: Point(x: 10.0, y: 20.0), size: Size(width: 30.0, height: 40.0))

        // Top-left is included [origin.x, origin.x + size.width)
        #expect(b.contains(Point(x: 10.0, y: 20.0)))
        // Interior is included
        #expect(b.contains(Point(x: 25.0, y: 35.0)))
        // Bottom and right edges are NOT included
        #expect(!b.contains(Point(x: 40.0, y: 20.0))) // right edge
        #expect(!b.contains(Point(x: 10.0, y: 60.0))) // bottom edge
        #expect(!b.contains(Point(x: 40.0, y: 60.0))) // bottom-right corner
        // Outside points
        #expect(!b.contains(Point(x: 9.9, y: 20.0)))
        #expect(!b.contains(Point(x: 10.0, y: 19.9)))

        // Localize
        #expect(b.localize(Point(x: 15.0, y: 25.0)) == Point(x: 5.0, y: 5.0))
        #expect(b.localize(Point(x: 5.0, y: 5.0)) == nil)
    }

    // MARK: - Point Operations
    @Test("Point arithmetic and methods")
    func test_point_operations() {
        let p1 = Point(x: 10.0, y: 20.0)
        let p2 = Point(x: 5.0, y: 15.0)

        #expect(p1 + p2 == Point(x: 15.0, y: 35.0))
        #expect(p1 - p2 == Point(x: 5.0, y: 5.0))
        #expect(-p1 == Point(x: -10.0, y: -20.0))
        #expect(p1.min(p2) == Point(x: 5.0, y: 15.0))
        #expect(p1.max(p2) == Point(x: 10.0, y: 20.0))
        #expect(p1.clamp(min: Point(x: 12.0, y: 12.0), max: Point(x: 18.0, y: 18.0)) == Point(x: 12.0, y: 18.0))

        // Along
        #expect(p1.along(.horizontal) == 10.0)
        #expect(p1.along(.vertical) == 20.0)
        #expect(p1.applyAlong(.horizontal) { $0 * 2 } == Point(x: 20.0, y: 20.0))

        // Pixels magnitude
        let pxPoint = Point(x: Pixels(3.0), y: Pixels(4.0))
        #expect(pxPoint.magnitude() == 5.0)
    }

    // MARK: - Size Operations
    @Test("Size arithmetic and methods")
    func test_size_operations() {
        let s1 = Size(width: 100.0, height: 200.0)
        let s2 = Size(width: 50.0, height: 300.0)

        #expect(s1.center() == Point(x: 50.0, y: 100.0))
        #expect(s1.max(s2) == Size(width: 100.0, height: 300.0))
        #expect(s1.min(s2) == Size(width: 50.0, height: 200.0))

        let pxSize = Size(width: px(10.5), height: px(20.4))
        let scaledSize = pxSize.scale(2.0)
        #expect(scaledSize.width == ScaledPixels(21.0))
        #expect(scaledSize.height == ScaledPixels(40.8))

        let devSize = pxSize.toDevicePixels(2.0)
        #expect(devSize.width == DevicePixels(21))
        #expect(devSize.height == DevicePixels(41))
    }

    // MARK: - Corners & clampRadiiForQuadSize
    @Test("Corners and clampRadiiForQuadSize")
    func test_corners_clamping() {
        let corners = Corners(
            topLeft: Pixels(20.0),
            topRight: Pixels(30.0),
            bottomRight: Pixels(40.0),
            bottomLeft: Pixels(50.0)
        )
        // Quad size 30x10 -> max radius is min(30, 10) / 2.0 = 5.0
        let clamped = corners.clampRadiiForQuadSize(Size(width: Pixels(30.0), height: Pixels(10.0)))
        #expect(clamped.topLeft == Pixels(5.0))
        #expect(clamped.topRight == Pixels(5.0))
        #expect(clamped.bottomRight == Pixels(5.0))
        #expect(clamped.bottomLeft == Pixels(5.0))

        // Corner methods
        #expect(Corner.topLeft.oppositeCorner() == .bottomRight)
        #expect(Corner.topRight.oppositeCorner() == .bottomLeft)
        #expect(Corner.topLeft.otherSideCornerAlong(.horizontal) == .topRight)
        #expect(Corner.topLeft.otherSideCornerAlong(.vertical) == .bottomLeft)
    }

    // MARK: - Unit Conversions & Rounding
    @Test("Unit conversions and rounding")
    func test_unit_conversions() {
        let pxVal = Pixels(10.4)
        #expect(pxVal.floor() == Pixels(10.0))
        #expect(pxVal.ceil() == Pixels(11.0))
        #expect(pxVal.round() == Pixels(10.0))
        #expect(Pixels(10.0).pow(2.0) == Pixels(100.0))
        #expect(abs(pxVal.pow(2.0).value - 108.16) < 0.001)

        let scaled = ScaledPixels(10.2)
        let dev = scaled.toDevicePixels()
        #expect(dev == DevicePixels(11)) // ceil conversion

        let devPx = DevicePixels(10)
        #expect(devPx.toBytes(bytesPerPixel: 4) == 40)

        let rem = Rems(2.0)
        #expect(rem.toPixels(remSize: Pixels(16.0)) == Pixels(32.0))

        // Parsing
        #expect(Pixels(parsing: "15.5px") == Pixels(15.5))
        #expect(Pixels(parsing: "15.5") == nil)
        #expect(Rems(parsing: "2.5rem") == Rems(2.5))
        #expect(Rems(parsing: "2.5") == nil)
    }

    // MARK: - Length Types
    @Test("Length abstractions")
    func test_lengths() {
        let absPx = AbsoluteLength.pixels(Pixels(20.0))
        let absRem = AbsoluteLength.rems(Rems(2.0))
        let remSize = Pixels(16.0)

        #expect(absPx.toPixels(remSize: remSize) == Pixels(20.0))
        #expect(absRem.toPixels(remSize: remSize) == Pixels(32.0))
        #expect(absPx.toRems(remSize: remSize) == Rems(1.25))

        let fracLen = DefiniteLength.fraction(0.5)
        #expect(fracLen.toPixels(baseSize: .pixels(Pixels(200.0)), remSize: remSize) == Pixels(100.0))

        #expect(DefiniteLength(parsing: "50%") == .fraction(0.5))
        #expect(DefiniteLength(parsing: "20px") == .absolute(.pixels(Pixels(20.0))))
        #expect(Length(parsing: "auto") == .auto)

        #expect(phi() == .fraction(1.618034))
        #expect(auto() == .auto)
    }

    // MARK: - IsZero & Half
    @Test("IsZero and Half trait behavior")
    func test_is_zero_and_half() {
        #expect(Pixels(0.0).isZero)
        #expect(!Pixels(1.0).isZero)

        // Point: both must be zero
        #expect(Point(x: Pixels(0.0), y: Pixels(0.0)).isZero)
        #expect(!Point(x: Pixels(0.0), y: Pixels(5.0)).isZero)

        // Size: either being zero makes size zero
        #expect(Size(width: Pixels(0.0), height: Pixels(100.0)).isZero)
        #expect(Size(width: Pixels(100.0), height: Pixels(0.0)).isZero)
        #expect(!Size(width: Pixels(10.0), height: Pixels(10.0)).isZero)

        // Half
        #expect(Int32(10).half() == 5)
        #expect(Float(10.0).half() == 5.0)
        #expect(Pixels(10.0).half() == Pixels(5.0))
        #expect(DevicePixels(10).half() == DevicePixels(5))
    }

    // MARK: - ContentMask
    @Test("ContentMask scale and intersect")
    func test_content_mask() {
        let mask1 = ContentMask(bounds: Bounds(origin: Point(x: px(0), y: px(0)), size: Size(width: px(100), height: px(100))))
        let mask2 = ContentMask(bounds: Bounds(origin: Point(x: px(50), y: px(50)), size: Size(width: px(100), height: px(100))))

        let scaled = mask1.scale(2.0)
        #expect(scaled.bounds.size.width == ScaledPixels(200.0))

        let intersected = mask1.intersect(mask2)
        #expect(intersected.bounds.origin == Point(x: px(50), y: px(50)))
        #expect(intersected.bounds.size == Size(width: px(50), height: px(50)))
    }
}
