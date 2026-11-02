// Ported from: crates/rune/src/shape.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Vector shapes painted inside an element: strokes (polylines) and fills (simple polygons), in
//! the element's own points with the origin at its top-left corner.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

public enum LineCap: Sendable, Equatable, Hashable {
    /// Segments end at their points.
    case butt
    /// Half-discs past each end; also rounds every joint of a polyline.
    case round

    public static let Butt: LineCap = .butt
    public static let Round: LineCap = .round
}

public enum ShapeOp: Sendable, Equatable {
    case stroke(points: [[Float]], closed: Bool, width: Float, cap: LineCap, color: Color)
    case fill(points: [[Float]], color: Color)
}

/// How many points of line a fill fades in over as ``Shape/drawn(_:)`` reaches it.
public let DRAW_RAMP: Float = 8.0

/// A list of strokes and fills, painted in order over the element's fill and under its text.
public struct Shape: Sendable, Equatable {
    public internal(set) var ops: [ShapeOp]
    /// Coordinates span this box and stretch to the element's size (SVG `viewBox`).
    public internal(set) var viewBoxSize: [Float]?

    public init() {
        self.ops = []
        self.viewBoxSize = nil
    }

    public static func new() -> Shape {
        Shape()
    }

    /// An open polyline through `points`, `width` points wide, with round caps and joints.
    public func stroke(_ points: [[Float]], _ width: Float, _ color: Color) -> Shape {
        strokeWith(points, false, width, .round, color)
    }

    /// A polyline; `closed` joins the last point back to the first.
    public func strokeWith(
        _ points: [[Float]],
        _ closed: Bool,
        _ width: Float,
        _ cap: LineCap,
        _ color: Color
    ) -> Shape {
        var copy = self
        if points.count >= 2 && width > 0.0 {
            copy.ops.append(.stroke(points: points, closed: closed, width: width, cap: cap, color: color))
        }
        return copy
    }

    /// A straight line from `a` to `b`.
    public func line(_ a: [Float], _ b: [Float], _ width: Float, _ cap: LineCap, _ color: Color) -> Shape {
        strokeWith([a, b], false, width, cap, color)
    }

    /// The inside of the simple polygon through `points` (either winding; not self-intersecting).
    public func fill(_ points: [[Float]], _ color: Color) -> Shape {
        var copy = self
        if points.count >= 3 {
            copy.ops.append(.fill(points: points, color: color))
        }
        return copy
    }

    /// Strokes every subpath of `path`, closed ones back to their start.
    public func strokePath(_ path: Path, _ width: Float, _ cap: LineCap, _ color: Color) -> Shape {
        var out = self
        for sub in path.subpaths {
            out = out.strokeWith(sub.points, sub.closed, width, cap, color)
        }
        return out
    }

    /// Fills every subpath of `path` on its own (no holes between subpaths).
    public func fillPath(_ path: Path, _ color: Color) -> Shape {
        var out = self
        for sub in path.subpaths {
            out = out.fill(sub.points, color)
        }
        return out
    }

    /// Treats coordinates as spanning `width` × `height` and stretches them to whatever size the element lays out at.
    public func viewBox(_ width: Float, _ height: Float) -> Shape {
        var copy = self
        copy.viewBoxSize = (width > 0.0 && height > 0.0) ? [width, height] : nil
        return copy
    }

    public var isEmpty: Bool {
        ops.isEmpty
    }

    func overlaps() -> Bool {
        var pieces = 0
        for op in ops {
            switch op {
            case .stroke(let points, let closed, _, _, _):
                pieces += closed ? points.count : max(0, points.count - 1)
            case .fill:
                pieces += 1
            }
        }
        return pieces > 1
    }

    /// This shape drawn on to `t` (0 to 1), as SVG's `pathLength` trim draws a line.
    public func drawn(_ rawT: Float) -> Shape {
        let t: Float = rawT.isNaN ? 1.0 : min(max(rawT, 0.0), 1.0)
        if t >= 1.0 {
            return self
        }
        func polyLen(_ points: [[Float]], _ closed: Bool) -> Float {
            guard points.count >= 2 else { return 0.0 }
            var open: Float = 0.0
            for i in 0..<(points.count - 1) {
                open += pointDist(points[i], points[i + 1])
            }
            if closed && points.count > 2 {
                open += pointDist(points[points.count - 1], points[0])
            }
            return open
        }
        var total: Float = 0.0
        for op in ops {
            if case .stroke(let points, let closed, _, _, _) = op {
                total += polyLen(points, closed)
            }
        }
        let at = t * total
        var done: Float = 0.0
        var outOps: [ShapeOp] = []
        for op in ops {
            switch op {
            case .stroke(let points, let closed, let width, let cap, let color):
                let l = polyLen(points, closed)
                if at >= done + l {
                    outOps.append(op)
                } else if at > done {
                    var ring = points
                    if closed {
                        ring.append(points[0])
                    }
                    let cut = trimPolyline(ring, at - done)
                    if cut.count >= 2 {
                        outOps.append(.stroke(points: cut, closed: false, width: width, cap: cap, color: color))
                    }
                }
                done += l
            case .fill(let points, let color):
                let a: Float
                if total <= 0.0 {
                    a = t
                } else if done <= 0.0 {
                    a = 1.0
                } else {
                    let ramp = min(DRAW_RAMP, done)
                    a = min(max((at - (done - ramp)) / ramp, 0.0), 1.0)
                }
                if a > 0.0 {
                    outOps.append(.fill(points: points, color: color.alpha(color.a * a)))
                }
            }
        }
        var res = Shape()
        res.ops = outOps
        res.viewBoxSize = viewBoxSize
        return res
    }
}

private func trimPolyline(_ points: [[Float]], _ length: Float) -> [[Float]] {
    guard !points.isEmpty else { return [] }
    var out: [[Float]] = [points[0]]
    var left = length
    for i in 0..<(points.count - 1) {
        let a = points[i]
        let b = points[i + 1]
        let d = pointDist(a, b)
        if d >= left {
            let k: Float = d > 0.0 ? (left / d) : 0.0
            out.append([a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k])
            return out
        }
        out.append(b)
        left -= d
    }
    return out
}

public struct Subpath: Sendable, Equatable {
    public var points: [[Float]]
    public var closed: Bool

    public init(points: [[Float]] = [], closed: Bool = false) {
        self.points = points
        self.closed = closed
    }
}

private let flattenTolerance: Float = 0.1

/// A path built from lines and Bézier curves, flattened to polylines for ``Shape``.
public struct Path: Sendable, Equatable {
    public internal(set) var subpaths: [Subpath]

    public init() {
        self.subpaths = []
    }

    public static func new() -> Path {
        Path()
    }

    private func lastPoint() -> [Float] {
        subpaths.last?.points.last ?? [0.0, 0.0]
    }

    private mutating func ensureCurrentIndex() -> Int {
        if subpaths.last == nil || subpaths.last!.closed {
            let start = lastPoint()
            subpaths.append(Subpath(points: [start], closed: false))
        }
        return subpaths.count - 1
    }

    public func moveTo(_ p: [Float]) -> Path {
        var copy = self
        if let lastIdx = copy.subpaths.indices.last,
           copy.subpaths[lastIdx].points.count == 1 && !copy.subpaths[lastIdx].closed
        {
            copy.subpaths[lastIdx].points[0] = p
        } else {
            copy.subpaths.append(Subpath(points: [p], closed: false))
        }
        return copy
    }

    public func lineTo(_ p: [Float]) -> Path {
        var copy = self
        let idx = copy.ensureCurrentIndex()
        copy.subpaths[idx].points.append(p)
        return copy
    }

    public func quadTo(_ c: [Float], _ p: [Float]) -> Path {
        var copy = self
        let a = copy.lastPoint()
        let n = curveSegments(pointDist(a, c) + pointDist(c, p))
        let idx = copy.ensureCurrentIndex()
        for i in 1...n {
            let t = Float(i) / Float(n)
            let u = 1.0 - t
            copy.subpaths[idx].points.append([
                u * u * a[0] + 2.0 * u * t * c[0] + t * t * p[0],
                u * u * a[1] + 2.0 * u * t * c[1] + t * t * p[1],
            ])
        }
        return copy
    }

    public func cubicTo(_ c1: [Float], _ c2: [Float], _ p: [Float]) -> Path {
        var copy = self
        let a = copy.lastPoint()
        let n = curveSegments(pointDist(a, c1) + pointDist(c1, c2) + pointDist(c2, p))
        let idx = copy.ensureCurrentIndex()
        for i in 1...n {
            let t = Float(i) / Float(n)
            let u = 1.0 - t
            let b0 = u * u * u
            let b1 = 3.0 * u * u * t
            let b2 = 3.0 * u * t * t
            let b3 = t * t * t
            copy.subpaths[idx].points.append([
                b0 * a[0] + b1 * c1[0] + b2 * c2[0] + b3 * p[0],
                b0 * a[1] + b1 * c1[1] + b2 * c2[1] + b3 * p[1],
            ])
        }
        return copy
    }

    public func close() -> Path {
        var copy = self
        if let idx = copy.subpaths.indices.last {
            copy.subpaths[idx].closed = true
        }
        return copy
    }
}

@inline(__always)
private func pointDist(_ a: [Float], _ b: [Float]) -> Float {
    let dx = b[0] - a[0]
    let dy = b[1] - a[1]
    return sqrtf(dx * dx + dy * dy)
}

@inline(__always)
private func curveSegments(_ length: Float) -> Int {
    let raw = ceilf(sqrtf(max(length, 0.0) / flattenTolerance) * 0.5)
    return Int(min(max(raw, 1.0), 256.0))
}

/// Ear-clips a simple polygon. Each triangle is three vertex indices and a mask of which of its
/// edges (a→b, b→c, c→a as bits 0, 1, 2) lie on the polygon's boundary.
public func triangulate(_ points: [[Float]]) -> [([Int], UInt32)] {
    let n = points.count
    if n < 3 {
        return []
    }
    var area: Float = 0.0
    for i in 0..<n {
        let a = points[i]
        let b = points[(i + 1) % n]
        area += a[0] * b[1] - b[0] * a[1]
    }
    let ccw = area > 0.0
    @inline(__always)
    func cross(_ a: [Float], _ b: [Float], _ c: [Float]) -> Float {
        let v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        return ccw ? v : -v
    }
    @inline(__always)
    func isBoundary(_ i: Int, _ j: Int) -> Bool {
        (i + 1) % n == j || (j + 1) % n == i
    }
    @inline(__always)
    func edgeMask(_ a: Int, _ b: Int, _ c: Int) -> UInt32 {
        (isBoundary(a, b) ? 1 : 0) | (isBoundary(b, c) ? 2 : 0) | (isBoundary(c, a) ? 4 : 0)
    }

    var ring = Array(0..<n)
    var out: [([Int], UInt32)] = []
    out.reserveCapacity(n - 2)
    var misses = 0
    var i = 0
    while ring.count > 3 {
        let m = ring.count
        let ia = ring[(i + m - 1) % m]
        let ib = ring[i % m]
        let ic = ring[(i + 1) % m]
        let a = points[ia]
        let b = points[ib]
        let c = points[ic]
        let convex = cross(a, b, c) > 0.0
        var empty = convex
        if empty {
            for k in ring where k != ia && k != ib && k != ic {
                let p = points[k]
                if cross(a, b, p) >= 0.0 && cross(b, c, p) >= 0.0 && cross(c, a, p) >= 0.0 {
                    empty = false
                    break
                }
            }
        }
        if empty || (misses >= m && cross(a, b, c) == 0.0) {
            if empty {
                out.append(([ia, ib, ic], edgeMask(ia, ib, ic)))
            }
            ring.remove(at: i % m)
            misses = 0
            i %= ring.count
        } else {
            misses += 1
            if misses > 2 * m {
                for k in 1..<(ring.count - 1) {
                    let x = ring[0]
                    let y = ring[k]
                    let z = ring[k + 1]
                    out.append(([x, y, z], edgeMask(x, y, z)))
                }
                return out
            }
            i = (i + 1) % m
        }
    }
    out.append(([ring[0], ring[1], ring[2]], edgeMask(ring[0], ring[1], ring[2])))
    return out
}
