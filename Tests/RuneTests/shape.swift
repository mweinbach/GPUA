// Tests ported from: crates/rune/src/shape.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

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
import Testing
@testable import Rune

private func polygonTriArea(_ points: [[Float]], _ tris: [([Int], UInt32)]) -> Float {
    var sum: Float = 0.0
    for (tri, _) in tris {
        let a = points[tri[0]]
        let b = points[tri[1]]
        let c = points[tri[2]]
        sum += abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) * 0.5
    }
    return sum
}

private func shapeStrokes(_ s: Shape) -> [[[Float]]] {
    s.ops.compactMap { op in
        if case .stroke(let points, _, _, _, _) = op {
            return points
        }
        return nil
    }
}

private func shapeFillAlpha(_ s: Shape) -> Float? {
    for op in s.ops {
        if case .fill(_, let color) = op {
            return color.a
        }
    }
    return nil
}

@Suite("ShapeTests")
struct ShapeTests {
    @Test("a concave polygon triangulates to its area with boundary edges marked")
    func concavePolygonTriangulatesToAreaWithBoundaryEdgesMarked() {
        let l: [[Float]] = [
            [0.0, 0.0],
            [20.0, 0.0],
            [20.0, 10.0],
            [10.0, 10.0],
            [10.0, 30.0],
            [0.0, 30.0],
        ]
        let tris = triangulate(l)
        #expect(tris.count == 4)
        #expect(abs(polygonTriArea(l, tris) - 400.0) < 1e-3)
        let boundaryEdges = tris.reduce(0) { $0 + $1.1.nonzeroBitCount }
        #expect(boundaryEdges == 6)
    }

    @Test("a waveform envelope triangulates completely")
    func waveformEnvelopeTriangulatesCompletely() {
        let top: [[Float]] = (0..<200).map { i in
            let x = Float(i)
            return [x, 20.0 - abs(sinf(x * 0.2)) * 18.0 - 1.0]
        }
        var env = top
        env.append(contentsOf: top.reversed().map { p in [p[0], 40.0 - p[1]] })
        let tris = triangulate(env)
        #expect(tris.count == env.count - 2)
        var signedArea: Float = 0.0
        for i in 0..<env.count {
            let a = env[i]
            let b = env[(i + 1) % env.count]
            signedArea += a[0] * b[1] - b[0] * a[1]
        }
        let exact = abs(signedArea) * 0.5
        #expect(abs(polygonTriArea(env, tris) - exact) < exact * 1e-3)
    }

    @Test("curves flatten within tolerance and end on their points")
    func curvesFlattenWithinToleranceAndEndOnTheirPoints() {
        let p = Path.new()
            .moveTo([0.0, 0.0])
            .cubicTo([0.0, 50.0], [100.0, 50.0], [100.0, 0.0])
            .close()
        let s = p.subpaths[0]
        #expect(s.closed)
        #expect(s.points.last == [100.0, 0.0])
        let mid = s.points[s.points.count / 2]
        #expect(abs(mid[1] - 37.5) < 1.0)
    }

    @Test("a drawn shape traces its strokes in order and lands its head last")
    func drawnShapeTracesStrokesInOrderAndLandsHeadLast() {
        let s = Shape.new()
            .stroke([[0.0, 0.0], [0.0, 60.0], [40.0, 60.0]], 1.0, Color.WHITE)
            .stroke([[40.0, 70.0], [40.0, 90.0]], 1.0, Color.WHITE)
            .fill([[36.0, 90.0], [44.0, 90.0], [40.0, 96.0]], Color.WHITE)
        #expect(shapeStrokes(s.drawn(0.0)).isEmpty)
        #expect(shapeFillAlpha(s.drawn(0.0)) == nil)
        // 60 of 120 points: down the first leg, not yet round the corner.
        #expect(shapeStrokes(s.drawn(0.5)) == [[[0.0, 0.0], [0.0, 60.0]]])
        // 80 points: round the corner, halfway along the second leg.
        #expect(shapeStrokes(s.drawn(80.0 / 120.0)) == [[[0.0, 0.0], [0.0, 60.0], [20.0, 60.0]]])
        // The head fades in over the last 8 points of line.
        #expect(shapeFillAlpha(s.drawn(108.0 / 120.0)) == nil)
        let a = shapeFillAlpha(s.drawn(116.0 / 120.0))!
        #expect(abs(a - 0.5) < 1e-4)
        #expect(s.drawn(1.0) == s)
        #expect(s.drawn(.nan) == s)
    }

    @Test("a closed stroke draws on round to its start and fills alone fade")
    func closedStrokeDrawsOnRoundToStartAndFillsAloneFade() {
        let square: [[Float]] = [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]]
        let s = Shape.new().strokeWith(square, true, 1.0, .round, Color.WHITE)
        #expect(
            shapeStrokes(s.drawn(0.875))
                == [[[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0], [0.0, 5.0]]]
        )
        let dot = Shape.new().fill([[0.0, 0.0], [4.0, 0.0], [2.0, 4.0]], Color.WHITE)
        #expect(shapeFillAlpha(dot.drawn(0.25)) == 0.25)
    }

    @Test("empty and degenerate ops are dropped")
    func emptyAndDegenerateOpsAreDropped() {
        let s = Shape.new()
            .stroke([[0.0, 0.0]], 1.0, Color.WHITE)
            .fill([[0.0, 0.0], [1.0, 1.0]], Color.WHITE)
        #expect(s.isEmpty)
    }
}
