// Tests ported from: crates/rune-mermaid/src/shape_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct ShapeTests {
    private static let allShapes: [NodeShape] = [
        .rect, .round, .stadium, .subroutine, .cylinder, .circle, .doubleCircle, .asymmetric,
        .diamond, .hexagon, .leanRight, .leanLeft, .trapBottom, .trapTop, .smallCircle,
        .filledCircle, .framedCircle, .crossedCircle, .bang, .cloud, .card, .hourglass,
        .bolt, .braceLeft, .braceRight, .braces, .delay, .hCylinder, .linedCylinder,
        .curvedTrapezoid, .dividedRect, .document, .linedDocument, .documents, .taggedDocument,
        .triangle, .flippedTriangle, .fork, .windowPane, .linedRect, .notchedPentagon,
        .slopedRect, .stackedRect, .flag, .bowRect, .taggedRect, .text, .note,
    ]

    private func inside(_ p: [Float], _ c: [Float], _ s: [Float], _ slack: Float) -> Bool {
        abs(p[0] - c[0]) <= s[0] / 2.0 + slack && abs(p[1] - c[1]) <= s[1] / 2.0 + slack
    }

    @Test func everyShapeStaysInItsBoxAndHoldsItsLabel() {
        let paint = DiagramStyle.neutral(false)
        let label = RuneMermaid.measure("Process step", paint.font)
        let c: [Float] = [100.0, 80.0]
        for shape in Self.allShapes {
            let size = nodeSize(shape, label.size)
            let poly = outline(shape, c, size)
            #expect(poly.count >= 3, "\(shape)")
            #expect(poly.allSatisfy { inside($0, c, size, 0.5) }, "\(shape) outline leaves its box")
            var canvas = Canvas()
            drawShape(&canvas, shape, label, c, size, [paint.nodeFill, paint.nodeBorder, paint.text], paint)
            for op in canvas.ops {
                let points: [[Float]]
                switch op {
                case .fill(let pts, _), .stroke(let pts, _, _, _, _):
                    points = pts
                }
                #expect(points.allSatisfy { inside($0, c, size, 0.5) }, "\(shape) draws outside its box")
            }
            if shape.unlabelled() {
                #expect(canvas.labels.isEmpty, "\(shape) is too small for a label")
            } else {
                let l = canvas.labels[0]
                let lo = l.at
                let hi: [Float] = [l.at[0] + l.size[0], l.at[1] + l.size[1]]
                #expect(inside(lo, c, size, 0.5) && inside(hi, c, size, 0.5), "\(shape) label leaves its box")
            }
        }
    }

    @Test func boundaryPointsStayOnOrInTheBox() {
        let c: [Float] = [0.0, 0.0]
        let dirs: [[Float]] = [[0.0, 200.0], [0.0, -200.0], [200.0, 0.0], [-150.0, 90.0]]
        for shape in Self.allShapes {
            let size = nodeSize(shape, [80.0, 18.0])
            for toward in dirs {
                let b = boundary(shape, c, size, toward)
                #expect(inside(b, c, size, 0.5), "\(shape) toward \(toward): \(b)")
                #expect(abs(b[0]) + abs(b[1]) > 3.0, "\(shape) toward \(toward) stops at centre")
            }
        }
    }

    @Test func aRayLeavesATriangleOnItsSlantedSide() {
        let size: [Float] = [100.0, 60.0]
        let b1 = boundary(.triangle, [0.0, 0.0], size, [0.0, -100.0])
        #expect(abs(b1[1] + 30.0) < 1e-3)
        let b2 = boundary(.triangle, [0.0, 0.0], size, [100.0, -60.0])
        #expect(b2[0] < 50.0 && b2[0] > 0.0 && b2[1] > -30.0)
    }

    @Test func aCylinderHasMermaidsRimsAndItsLabelUnderTheFrontOne() {
        let paint = DiagramStyle.neutral(false)
        let label = RuneMermaid.measure("Note: lasts, has versions", paint.font)
        let size = nodeSize(.cylinder, label.size)
        let ry = shapeRim(size[0])
        #expect(abs(ry - size[0] / 2.0 / (2.5 + size[0] / 50.0)) < 1e-3)
        var c = Canvas()
        drawShape(&c, .cylinder, label, [0.0, 0.0], size, [paint.nodeFill, paint.nodeBorder, paint.text], paint)
        let top = -size[1] / 2.0
        let bottom = size[1] / 2.0
        let body = outline(.cylinder, [0.0, 0.0], size)
        let rims: [[[Float]]] = c.ops.map { op in
            switch op {
            case .fill(let pts, _), .stroke(let pts, _, _, _, _):
                return pts
            }
        }.filter { $0 != body }
        #expect(!rims.isEmpty)
        let minRimY: Float = top - 0.01
        let maxRimY: Float = top + 2.0 * ry + 0.01
        let allInRimBand = rims.allSatisfy { pts in
            pts.allSatisfy { pt in pt[1] >= minRimY && pt[1] <= maxRimY }
        }
        #expect(allInRimBand)
        let l = c.labels[0]
        #expect(l.at[1] >= top + 2.0 * ry)
        #expect(l.at[1] + l.size[1] <= bottom - ry)
    }
}
