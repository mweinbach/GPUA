// Ported from: crates/gpui/src/path_builder.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - Lyon Geometry & Tessellation Types

/// 2D angle in radians or degrees.
public struct Angle: Sendable, Equatable {
    public var radians: Float

    public var degrees: Float {
        radians * 180.0 / Float.pi
    }

    public init(radians: Float) {
        self.radians = radians
    }

    public static func radians(_ rad: Float) -> Angle {
        Angle(radians: rad)
    }

    public static func degrees(_ deg: Float) -> Angle {
        Angle(radians: deg * Float.pi / 180.0)
    }
}

/// 2D vector for geometry calculations.
public struct Vector2D: Sendable, Equatable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

/// 2D Affine Transform (matrix: a c tx; b d ty).
public struct Transform: Sendable, Equatable {
    public var a: Float
    public var b: Float
    public var c: Float
    public var d: Float
    public var tx: Float
    public var ty: Float

    public init(a: Float = 1.0, b: Float = 0.0, c: Float = 0.0, d: Float = 1.0, tx: Float = 0.0, ty: Float = 0.0) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static func identity() -> Transform {
        Transform()
    }

    public static func translation(_ tx: Float, _ ty: Float) -> Transform {
        Transform(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: tx, ty: ty)
    }

    public static func scale(_ sx: Float, _ sy: Float) -> Transform {
        Transform(a: sx, b: 0.0, c: 0.0, d: sy, tx: 0.0, ty: 0.0)
    }

    public static func rotation(_ angle: Angle) -> Transform {
        let cosA = Float(cos(Double(angle.radians)))
        let sinA = Float(sin(Double(angle.radians)))
        return Transform(a: cosA, b: sinA, c: -sinA, d: cosA, tx: 0.0, ty: 0.0)
    }

    public func thenTranslate(_ v: Vector2D) -> Transform {
        Transform(
            a: self.a,
            b: self.b,
            c: self.c,
            d: self.d,
            tx: self.tx + self.a * v.x + self.c * v.y,
            ty: self.ty + self.b * v.x + self.d * v.y
        )
    }

    public func thenScale(_ sx: Float, _ sy: Float) -> Transform {
        Transform(
            a: self.a * sx,
            b: self.b * sx,
            c: self.c * sy,
            d: self.d * sy,
            tx: self.tx,
            ty: self.ty
        )
    }

    public func thenRotate(_ angle: Angle) -> Transform {
        let rot = Transform.rotation(angle)
        return Transform(
            a: self.a * rot.a + self.b * rot.c,
            b: self.a * rot.b + self.b * rot.d,
            c: self.c * rot.a + self.d * rot.c,
            d: self.c * rot.b + self.d * rot.d,
            tx: self.tx * rot.a + self.ty * rot.c,
            ty: self.tx * rot.b + self.ty * rot.d
        )
    }

    public func transformPoint(_ p: Point<Pixels>) -> Point<Pixels> {
        let pxVal = p.x.value
        let pyVal = p.y.value
        let nx = self.a * pxVal + self.c * pyVal + self.tx
        let ny = self.b * pxVal + self.d * pyVal + self.ty
        return point(px(nx), px(ny))
    }
}

/// Fill rule for path tessellation.
public enum FillRule: Sendable, Equatable {
    case nonZero
    case evenOdd
}

/// Options for fill tessellation.
public struct FillOptions: Sendable, Equatable {
    public var fillRule: FillRule
    public var tolerance: Float

    public init(fillRule: FillRule = .nonZero, tolerance: Float = 0.1) {
        self.fillRule = fillRule
        self.tolerance = tolerance
    }

    public func withFillRule(_ rule: FillRule) -> FillOptions {
        var opt = self
        opt.fillRule = rule
        return opt
    }

    public func withTolerance(_ tolerance: Float) -> FillOptions {
        var opt = self
        opt.tolerance = tolerance
        return opt
    }
}

/// Options for stroke tessellation.
public struct StrokeOptions: Sendable, Equatable {
    public var lineWidth: Float
    public var tolerance: Float
    public var miterLimit: Float

    public init(lineWidth: Float = 1.0, tolerance: Float = 0.1, miterLimit: Float = 4.0) {
        self.lineWidth = lineWidth
        self.tolerance = tolerance
        self.miterLimit = miterLimit
    }

    public func withLineWidth(_ width: Float) -> StrokeOptions {
        var opt = self
        opt.lineWidth = width
        return opt
    }

    public func withTolerance(_ tolerance: Float) -> StrokeOptions {
        var opt = self
        opt.tolerance = tolerance
        return opt
    }
}

/// Style of the PathBuilder.
public enum PathStyle: Sendable, Equatable {
    case stroke(StrokeOptions)
    case fill(FillOptions)
}

/// Vertex buffers produced during tessellation.
public struct VertexBuffers<V: Sendable, I: Sendable>: Sendable {
    public var vertices: [V]
    public var indices: [I]

    public init(vertices: [V] = [], indices: [I] = []) {
        self.vertices = vertices
        self.indices = indices
    }
}

// MARK: - Internal Path Command Model

private enum PathCommand: Sendable {
    case moveTo(Point<Pixels>)
    case lineTo(Point<Pixels>)
    case curveTo(to: Point<Pixels>, ctrl: Point<Pixels>)
    case cubicBezierTo(to: Point<Pixels>, ctrlA: Point<Pixels>, ctrlB: Point<Pixels>)
    case arcTo(radii: Point<Pixels>, xRotation: Pixels, largeArc: Bool, sweep: Bool, to: Point<Pixels>)
    case close
}

// MARK: - PathBuilder

/// A [`Path`] builder that constructs 2D vector geometry and tessellates
/// Béziers, arcs, and polygons into triangles for rendering.
public struct PathBuilder: Sendable {
    private var commands: [PathCommand]
    private var transformMatrix: Transform?
    public var style: PathStyle
    private var dashArrayValues: [Pixels]?

    public init(
        style: PathStyle = .fill(FillOptions()),
        transform: Transform? = nil,
        dashArray: [Pixels]? = nil
    ) {
        self.commands = []
        self.style = style
        self.transformMatrix = transform
        self.dashArrayValues = dashArray
    }

    /// Creates a new [`PathBuilder`] to build a Stroke path.
    public static func stroke(_ width: Pixels) -> Self {
        PathBuilder(style: .stroke(StrokeOptions().withLineWidth(width.value)))
    }

    /// Creates a new [`PathBuilder`] to build a Fill path.
    public static func fill() -> Self {
        PathBuilder(style: .fill(FillOptions()))
    }

    /// Sets the style of the [`PathBuilder`].
    public func withStyle(_ style: PathStyle) -> Self {
        var builder = self
        builder.style = style
        return builder
    }

    /// Sets the dash array of the [`PathBuilder`].
    public func dashArray(_ dashArray: [Pixels]) -> Self {
        var builder = self
        // If an odd number of values is provided, repeat to yield an even number.
        if dashArray.count % 2 == 1 {
            var duplicated = dashArray
            duplicated.append(contentsOf: dashArray)
            builder.dashArrayValues = duplicated
        } else {
            builder.dashArrayValues = dashArray
        }
        return builder
    }

    /// Move the current point to the given point.
    public mutating func moveTo(_ to: Point<Pixels>) {
        commands.append(.moveTo(to))
    }

    /// Draw a straight line from the current point to the given point.
    public mutating func lineTo(_ to: Point<Pixels>) {
        commands.append(.lineTo(to))
    }

    /// Draw a curve from the current point to the given point, using the given control point.
    public mutating func curveTo(_ to: Point<Pixels>, ctrl: Point<Pixels>) {
        commands.append(.curveTo(to: to, ctrl: ctrl))
    }

    /// Adds a cubic Bézier to the [`Path`] given its two control points and its end point.
    public mutating func cubicBezierTo(
        _ to: Point<Pixels>,
        controlA: Point<Pixels>,
        controlB: Point<Pixels>
    ) {
        commands.append(.cubicBezierTo(to: to, ctrlA: controlA, ctrlB: controlB))
    }

    /// Adds an elliptical arc.
    public mutating func arcTo(
        radii: Point<Pixels>,
        xRotation: Pixels,
        largeArc: Bool,
        sweep: Bool,
        to: Point<Pixels>
    ) {
        commands.append(.arcTo(
            radii: radii,
            xRotation: xRotation,
            largeArc: largeArc,
            sweep: sweep,
            to: to
        ))
    }

    /// Equivalent to `arc_to` in relative coordinates.
    public mutating func relativeArcTo(
        radii: Point<Pixels>,
        xRotation: Pixels,
        largeArc: Bool,
        sweep: Bool,
        to: Point<Pixels>
    ) {
        let current = currentPoint()
        let absoluteTo = point(current.x + to.x, current.y + to.y)
        arcTo(
            radii: radii,
            xRotation: xRotation,
            largeArc: largeArc,
            sweep: sweep,
            to: absoluteTo
        )
    }

    /// Adds a polygon.
    public mutating func addPolygon(_ points: [Point<Pixels>], closed: Bool) {
        guard let first = points.first else { return }
        moveTo(first)
        for p in points.dropFirst() {
            lineTo(p)
        }
        if closed {
            close()
        }
    }

    /// Close the current sub-path.
    public mutating func close() {
        commands.append(.close)
    }

    /// Applies a transform to the path.
    public mutating func transform(_ transform: Transform) {
        if let current = self.transformMatrix {
            let combined = Transform(
                a: current.a * transform.a + current.b * transform.c,
                b: current.a * transform.b + current.b * transform.d,
                c: current.c * transform.a + current.d * transform.c,
                d: current.c * transform.b + current.d * transform.d,
                tx: current.tx * transform.a + current.ty * transform.c + transform.tx,
                ty: current.tx * transform.b + current.ty * transform.d + transform.ty
            )
            self.transformMatrix = combined
        } else {
            self.transformMatrix = transform
        }
    }

    /// Applies a translation to the path.
    public mutating func translate(_ to: Point<Pixels>) {
        if let current = self.transformMatrix {
            self.transformMatrix = current.thenTranslate(Vector2D(x: to.x.value, y: to.y.value))
        } else {
            self.transformMatrix = Transform.translation(to.x.value, to.y.value)
        }
    }

    /// Applies a scale to the path.
    public mutating func scale(_ scale: Float) {
        if let current = self.transformMatrix {
            self.transformMatrix = current.thenScale(scale, scale)
        } else {
            self.transformMatrix = Transform.scale(scale, scale)
        }
    }

    /// Applies a rotation to the path in degrees (0.0 to 360.0).
    public mutating func rotate(_ angle: Float) {
        let radians = angle * Float.pi / 180.0
        let rot = Angle.radians(radians)
        if let current = self.transformMatrix {
            self.transformMatrix = current.thenRotate(rot)
        } else {
            self.transformMatrix = Transform.rotation(rot)
        }
    }

    private func currentPoint() -> Point<Pixels> {
        var cur = point(px(0), px(0))
        for cmd in commands {
            switch cmd {
            case .moveTo(let p), .lineTo(let p):
                cur = p
            case .curveTo(let to, _):
                cur = to
            case .cubicBezierTo(let to, _, _):
                cur = to
            case .arcTo(_, _, _, _, let to):
                cur = to
            case .close:
                break
            }
        }
        return cur
    }

    // MARK: - Building and Tessellation

    /// Builds into a [`Path`].
    public func build() throws -> Path<Pixels> {
        let subpaths = discretizeCommands()
        let transformedSubpaths: [[Point<Pixels>]]
        if let transform = self.transformMatrix {
            transformedSubpaths = subpaths.map { subpath in
                subpath.map { transform.transformPoint($0) }
            }
        } else {
            transformedSubpaths = subpaths
        }

        switch style {
        case .stroke(let options):
            return tessellateStroke(subpaths: transformedSubpaths, options: options, dashArray: self.dashArrayValues)
        case .fill(let options):
            return tessellateFill(subpaths: transformedSubpaths, options: options)
        }
    }

    /// Builds a [`Path`] from a [`VertexBuffers`].
    public static func buildPath(_ buf: VertexBuffers<Point<Pixels>, UInt16>) -> Path<Pixels> {
        if buf.vertices.isEmpty {
            return Path(start: point(px(0), px(0)))
        }

        let firstPoint = buf.vertices[0]
        var path = Path(start: firstPoint)
        let triCount = buf.indices.count / 3
        for i in 0..<triCount {
            let i0 = Int(buf.indices[i * 3])
            let i1 = Int(buf.indices[i * 3 + 1])
            let i2 = Int(buf.indices[i * 3 + 2])

            guard i0 < buf.vertices.count, i1 < buf.vertices.count, i2 < buf.vertices.count else { continue }
            let v0 = buf.vertices[i0]
            let v1 = buf.vertices[i1]
            let v2 = buf.vertices[i2]

            path.pushTriangle(
                xy: (v0, v1, v2),
                st: (point(0.0, 1.0), point(0.0, 1.0), point(0.0, 1.0))
            )
        }

        return path
    }

    // MARK: - Curve Discretization

    private func discretizeCommands() -> [[Point<Pixels>]] {
        var subpaths: [[Point<Pixels>]] = []
        var currentSubpath: [Point<Pixels>] = []
        var current = point(px(0), px(0))
        var subpathStart = point(px(0), px(0))

        for cmd in commands {
            switch cmd {
            case .moveTo(let p):
                if !currentSubpath.isEmpty {
                    subpaths.append(currentSubpath)
                    currentSubpath = []
                }
                current = p
                subpathStart = p
                currentSubpath.append(p)

            case .lineTo(let p):
                currentSubpath.append(p)
                current = p

            case .curveTo(let to, let ctrl):
                let pts = discretizeQuadraticBezier(p0: current, p1: ctrl, p2: to)
                for pt in pts.dropFirst() {
                    currentSubpath.append(pt)
                }
                current = to

            case .cubicBezierTo(let to, let ctrlA, let ctrlB):
                let pts = discretizeCubicBezier(p0: current, p1: ctrlA, p2: ctrlB, p3: to)
                for pt in pts.dropFirst() {
                    currentSubpath.append(pt)
                }
                current = to

            case .arcTo(let radii, let xRotation, let largeArc, let sweep, let to):
                let pts = discretizeArc(
                    start: current,
                    end: to,
                    rx: radii.x.value,
                    ry: radii.y.value,
                    xAxisRotationDeg: xRotation.value,
                    largeArc: largeArc,
                    sweep: sweep
                )
                for pt in pts.dropFirst() {
                    currentSubpath.append(pt)
                }
                current = to

            case .close:
                if !currentSubpath.isEmpty && current != subpathStart {
                    currentSubpath.append(subpathStart)
                    current = subpathStart
                }
            }
        }

        if !currentSubpath.isEmpty {
            subpaths.append(currentSubpath)
        }

        return subpaths
    }

    private func discretizeQuadraticBezier(
        p0: Point<Pixels>,
        p1: Point<Pixels>,
        p2: Point<Pixels>,
        steps: Int = 16
    ) -> [Point<Pixels>] {
        var result: [Point<Pixels>] = []
        result.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let oneMinusT = 1.0 - t
            let x = oneMinusT * oneMinusT * p0.x.value + 2.0 * oneMinusT * t * p1.x.value + t * t * p2.x.value
            let y = oneMinusT * oneMinusT * p0.y.value + 2.0 * oneMinusT * t * p1.y.value + t * t * p2.y.value
            result.append(point(px(x), px(y)))
        }
        return result
    }

    private func discretizeCubicBezier(
        p0: Point<Pixels>,
        p1: Point<Pixels>,
        p2: Point<Pixels>,
        p3: Point<Pixels>,
        steps: Int = 24
    ) -> [Point<Pixels>] {
        var result: [Point<Pixels>] = []
        result.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let oneMinusT = 1.0 - t
            let x = oneMinusT * oneMinusT * oneMinusT * p0.x.value
                + 3.0 * oneMinusT * oneMinusT * t * p1.x.value
                + 3.0 * oneMinusT * t * t * p2.x.value
                + t * t * t * p3.x.value
            let y = oneMinusT * oneMinusT * oneMinusT * p0.y.value
                + 3.0 * oneMinusT * oneMinusT * t * p1.y.value
                + 3.0 * oneMinusT * t * t * p2.y.value
                + t * t * t * p3.y.value
            result.append(point(px(x), px(y)))
        }
        return result
    }

    /// W3C SVG 1.1 Appendix F.6: Elliptical arc conversion and discretization.
    private func discretizeArc(
        start: Point<Pixels>,
        end: Point<Pixels>,
        rx: Float,
        ry: Float,
        xAxisRotationDeg: Float,
        largeArc: Bool,
        sweep: Bool
    ) -> [Point<Pixels>] {
        let x1 = Double(start.x.value)
        let y1 = Double(start.y.value)
        let x2 = Double(end.x.value)
        let y2 = Double(end.y.value)

        if x1 == x2 && y1 == y2 {
            return [start]
        }

        var radX = abs(Double(rx))
        var radY = abs(Double(ry))
        if radX == 0 || radY == 0 {
            return [start, end]
        }

        let phi = Double(xAxisRotationDeg) * Double.pi / 180.0
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (x1 - x2) / 2.0
        let dy = (y1 - y2) / 2.0
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        let prx2 = radX * radX
        let pry2 = radY * radY
        let px1p2 = x1p * x1p
        let py1p2 = y1p * y1p

        let check = px1p2 / prx2 + py1p2 / pry2
        if check > 1.0 {
            let scale = sqrt(check)
            radX *= scale
            radY *= scale
        }

        let rx2 = radX * radX
        let ry2 = radY * radY
        let sign = (largeArc == sweep) ? -1.0 : 1.0
        let num = max(0.0, (rx2 * ry2) - (rx2 * py1p2) - (ry2 * px1p2))
        let den = (rx2 * py1p2) + (ry2 * px1p2)
        let factor = sign * sqrt(num / max(den, 1e-12))
        let cxp = factor * (radX * y1p / radY)
        let cyp = factor * (-radY * x1p / radX)

        let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2.0
        let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2.0

        let vx1 = (x1p - cxp) / radX
        let vy1 = (y1p - cyp) / radY
        let theta1 = atan2(vy1, vx1)

        let vx2 = (-x1p - cxp) / radX
        let vy2 = (-y1p - cyp) / radY
        var deltaTheta = atan2(vy2, vx2) - theta1

        if sweep && deltaTheta < 0.0 {
            deltaTheta += 2.0 * Double.pi
        } else if !sweep && deltaTheta > 0.0 {
            deltaTheta -= 2.0 * Double.pi
        }

        let segments = max(4, Int((abs(deltaTheta) / (Double.pi / 12.0)).rounded(.up)))
        var points: [Point<Pixels>] = []
        points.reserveCapacity(segments + 1)
        for i in 0...segments {
            let t = Double(i) / Double(segments)
            let theta = theta1 + deltaTheta * t
            let cosT = cos(theta)
            let sinT = sin(theta)
            let ex = cosPhi * radX * cosT - sinPhi * radY * sinT + cx
            let ey = sinPhi * radX * cosT + cosPhi * radY * sinT + cy
            points.append(point(px(Float(ex)), px(Float(ey))))
        }
        return points
    }

    // MARK: - Tessellation Implementation

    private func tessellateStroke(
        subpaths: [[Point<Pixels>]],
        options: StrokeOptions,
        dashArray: [Pixels]?
    ) -> Path<Pixels> {
        var vertexBuf = VertexBuffers<Point<Pixels>, UInt16>()
        let halfWidth = max(0.5, options.lineWidth / 2.0)

        for subpath in subpaths {
            guard subpath.count >= 2 else { continue }
            let dashedSegments: [[Point<Pixels>]]
            if let dashes = dashArray, !dashes.isEmpty {
                dashedSegments = applyDashArray(subpath, dashes: dashes)
            } else {
                dashedSegments = [subpath]
            }

            for seg in dashedSegments {
                guard seg.count >= 2 else { continue }
                for i in 0..<(seg.count - 1) {
                    let p0 = seg[i]
                    let p1 = seg[i + 1]

                    let dx = p1.x.value - p0.x.value
                    let dy = p1.y.value - p0.y.value
                    let len = Float(sqrt(Double(dx * dx + dy * dy)))
                    guard len > 1e-4 else { continue }

                    let nx = (-dy / len) * halfWidth
                    let ny = (dx / len) * halfWidth

                    let v0 = point(p0.x + px(nx), p0.y + px(ny))
                    let v1 = point(p0.x - px(nx), p0.y - px(ny))
                    let v2 = point(p1.x + px(nx), p1.y + px(ny))
                    let v3 = point(p1.x - px(nx), p1.y - px(ny))

                    let base = UInt16(vertexBuf.vertices.count)
                    vertexBuf.vertices.append(v0)
                    vertexBuf.vertices.append(v1)
                    vertexBuf.vertices.append(v2)
                    vertexBuf.vertices.append(v3)

                    // Triangles: (0, 1, 2) and (2, 1, 3)
                    vertexBuf.indices.append(base)
                    vertexBuf.indices.append(base + 1)
                    vertexBuf.indices.append(base + 2)
                    vertexBuf.indices.append(base + 2)
                    vertexBuf.indices.append(base + 1)
                    vertexBuf.indices.append(base + 3)
                }
            }
        }

        return Self.buildPath(vertexBuf)
    }

    private func applyDashArray(_ points: [Point<Pixels>], dashes: [Pixels]) -> [[Point<Pixels>]] {
        var result: [[Point<Pixels>]] = []
        let dashCount = dashes.count
        guard dashCount > 0 else { return [points] }

        var dashIndex = 0
        var currentDashRemaining = dashes[0].value
        var isDrawing = true
        var currentSeg: [Point<Pixels>] = []

        var i = 0
        while i < points.count - 1 {
            let p0 = points[i]
            let p1 = points[i + 1]
            let dx = p1.x.value - p0.x.value
            let dy = p1.y.value - p0.y.value
            let segLen = Float(sqrt(Double(dx * dx + dy * dy)))

            if segLen <= 1e-4 {
                i += 1
                continue
            }

            var segProgress: Float = 0.0
            while segProgress < segLen {
                let remainingInSegment = segLen - segProgress
                if currentDashRemaining <= remainingInSegment {
                    segProgress += currentDashRemaining
                    let t = segProgress / segLen
                    let interPt = point(
                        px(p0.x.value + dx * t),
                        px(p0.y.value + dy * t)
                    )

                    if isDrawing {
                        if currentSeg.isEmpty {
                            currentSeg.append(p0)
                        }
                        currentSeg.append(interPt)
                        result.append(currentSeg)
                        currentSeg = []
                    } else {
                        currentSeg = [interPt]
                    }

                    dashIndex = (dashIndex + 1) % dashCount
                    currentDashRemaining = dashes[dashIndex].value
                    isDrawing.toggle()
                } else {
                    currentDashRemaining -= remainingInSegment
                    segProgress = segLen
                    if isDrawing {
                        if currentSeg.isEmpty {
                            currentSeg.append(p0)
                        }
                        currentSeg.append(p1)
                    }
                }
            }

            i += 1
        }

        if isDrawing && currentSeg.count >= 2 {
            result.append(currentSeg)
        }

        return result
    }

    private func tessellateFill(
        subpaths: [[Point<Pixels>]],
        options: FillOptions
    ) -> Path<Pixels> {
        var vertexBuf = VertexBuffers<Point<Pixels>, UInt16>()

        for subpath in subpaths {
            guard subpath.count >= 3 else { continue }
            // Deduplicate closing point if it matches the start.
            var poly = subpath
            if poly.first == poly.last && poly.count > 3 {
                poly.removeLast()
            }
            guard poly.count >= 3 else { continue }

            let indices = triangulatePolygonEarClipping(poly)
            let base = UInt16(vertexBuf.vertices.count)
            vertexBuf.vertices.append(contentsOf: poly)
            for idx in indices {
                vertexBuf.indices.append(base + idx)
            }
        }

        return Self.buildPath(vertexBuf)
    }

    /// Ear-clipping triangulation of simple 2D polygons.
    private func triangulatePolygonEarClipping(_ points: [Point<Pixels>]) -> [UInt16] {
        let n = points.count
        guard n >= 3 else { return [] }
        if n == 3 {
            return [0, 1, 2]
        }

        var indices = Array(0..<n)
        var result: [UInt16] = []
        result.reserveCapacity((n - 2) * 3)

        // Compute polygon signed area to determine winding.
        var area: Float = 0.0
        for i in 0..<n {
            let j = (i + 1) % n
            area += (points[i].x.value * points[j].y.value) - (points[j].x.value * points[i].y.value)
        }
        let isClockwise = area < 0.0

        var count = n
        var loopCount = 0
        let maxLoops = n * 4

        var i = 0
        while count > 3 && loopCount < maxLoops {
            loopCount += 1
            let prev = (i + count - 1) % count
            let curr = i % count
            let next = (i + 1) % count

            let p0 = points[indices[prev]]
            let p1 = points[indices[curr]]
            let p2 = points[indices[next]]

            // Check if vertex is convex.
            let cross = (p1.x.value - p0.x.value) * (p2.y.value - p0.y.value) - (p1.y.value - p0.y.value) * (p2.x.value - p0.x.value)
            let isConvex = isClockwise ? (cross <= 0.0) : (cross >= 0.0)

            if isConvex {
                // Check if any other point lies inside triangle (p0, p1, p2).
                var isEar = true
                for j in 0..<count {
                    if j == prev || j == curr || j == next { continue }
                    let pt = points[indices[j]]
                    if isPointInTriangle(pt: pt, a: p0, b: p1, c: p2) {
                        isEar = false
                        break
                    }
                }

                if isEar {
                    result.append(UInt16(indices[prev]))
                    result.append(UInt16(indices[curr]))
                    result.append(UInt16(indices[next]))
                    indices.remove(at: curr)
                    count -= 1
                    i = prev
                    continue
                }
            }

            i = (i + 1) % count
        }

        // Add remaining triangle.
        if count == 3 {
            result.append(UInt16(indices[0]))
            result.append(UInt16(indices[1]))
            result.append(UInt16(indices[2]))
        }

        return result
    }

    private func isPointInTriangle(pt: Point<Pixels>, a: Point<Pixels>, b: Point<Pixels>, c: Point<Pixels>) -> Bool {
        let ptx = pt.x.value
        let pty = pt.y.value
        let ax = a.x.value
        let ay = a.y.value
        let bx = b.x.value
        let by = b.y.value
        let cx = c.x.value
        let cy = c.y.value

        let d1 = (ptx - bx) * (ay - by) - (ax - bx) * (pty - by)
        let d2 = (ptx - cx) * (by - cy) - (bx - cx) * (pty - cy)
        let d3 = (ptx - ax) * (cy - ay) - (cx - ax) * (pty - ay)

        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
        return !(hasNeg && hasPos)
    }
}
