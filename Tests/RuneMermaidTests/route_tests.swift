// Tests ported from: crates/rune-mermaid/src/route_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct RouteTests {
    private func sharpestTurn(_ pts: [[Float]]) -> Float {
        guard pts.count >= 2 else { return 0.0 }
        var dirs: [Float] = []
        for i in 0..<(pts.count - 1) where dist(pts[i], pts[i + 1]) > 1e-3 {
            dirs.append(mAtan2(pts[i + 1][1] - pts[i][1], pts[i + 1][0] - pts[i][0]))
        }
        guard dirs.count >= 2 else { return 0.0 }
        var maxDeg: Float = 0.0
        for i in 0..<(dirs.count - 1) {
            var a = abs((dirs[i + 1] - dirs[i]) * (180.0 / .pi))
            if a > 180.0 {
                a = 360.0 - a
            }
            maxDeg = max(maxDeg, a)
        }
        return maxDeg
    }

    @Test func curvesLeaveAndArriveAlongTheRankAxis() {
        let pts = routeCurve([[0.0, 0.0], [40.0, 100.0], [40.0, 200.0]])
        #expect(pts.first == [0.0, 0.0])
        #expect(pts.last == [40.0, 200.0])
        let a = pts[0]
        let b = pts[1]
        #expect(abs(b[0] - a[0]) < abs(b[1] - a[1]) * 0.05)
        #expect(sharpestTurn(pts) < 6.0)
        #expect(routeCubic([5.0, 0.0], [5.0, 90.0]).count == 2)
    }

    @Test func flowchartEdgesDrawWithoutKinks() {
        let src = "flowchart TD\n  A[Audio] --> B[Parakeet writes text<br/>'went to the capuchin']\n  B --> C{Any word that looks<br/>or sounds like a term?}\n  C -- no --> F[Paste as is]\n  C -- \"capuchin ≈ Cappuccino\" --> D[Score the same audio twice:<br/>as 'capuchin' and as 'Cappuccino']\n  D --> E{Cappuccino score + boost<br/>≥ capuchin score?}\n  E -- yes --> G[Write Cappuccino]\n  E -- no --> F"
        let paint = DiagramStyle.neutral(true)
        guard let parsed = RuneMermaid.parse(src), case .flowchart(let f) = parsed.diagram else {
            Issue.record("Expected flowchart")
            return
        }
        let c = flowchart.drawCanvas(f, paint, (.edges, paint.text))!
        let lines: [[[Float]]] = c.ops.compactMap { op in
            if case .stroke(let points, false, _, _, let color) = op, color == paint.line {
                return points
            }
            return nil
        }
        #expect(lines.count == 11)
        for l in lines {
            #expect(sharpestTurn(l) < 12.0)
        }
        #expect(c.traces.count == 7)
        #expect(buildScene(src, paint, nil) != nil)
    }

    @Test func arrowsPointIntoTheNodeTheyReach() {
        let paint = DiagramStyle.neutral(true)
        guard let parsed = RuneMermaid.parse("flowchart TD\n  A[Audio] --> B[Parakeet]"),
              case .flowchart(let f) = parsed.diagram else {
            Issue.record("Expected flowchart")
            return
        }
        let c = flowchart.drawCanvas(f, paint, (.edges, paint.text))!
        let head = c.ops.compactMap { op -> [[Float]]? in
            if case .fill(let p, let col) = op, col == paint.line && p.count == 3 {
                return p
            }
            return nil
        }.first
        let tip = head![0]
        let bTop = c.regions[1].map { $0[1] }.min()!
        #expect(abs(tip[1] - bTop) < 0.5)
    }

    @Test func longEdgesStayClearOfTheNodesTheyPass() {
        let paint = DiagramStyle.neutral(true)
        let src = "flowchart TD\n  A[Audio] --> B[Parakeet writes text]\n  B --> C{Any word that looks<br/>or sounds like a term?}\n  C -- no --> F[Paste as is]\n  C -- \"capuchin ≈ Cappuccino\" --> D[Score the same audio twice:<br/>as 'capuchin' and as 'Cappuccino']\n  D --> E{Cappuccino score + boost<br/>≥ capuchin score?}\n  E -- yes --> G[Write Cappuccino]\n  E -- no --> F"
        guard let parsed = RuneMermaid.parse(src), case .flowchart(let f) = parsed.diagram else {
            Issue.record("Expected flowchart")
            return
        }
        let c = flowchart.drawCanvas(f, paint, (.edges, paint.text))!
        let d = c.regions[4]
        let e = c.regions[5]
        let lines: [[[Float]]] = c.ops.compactMap { op in
            if case .stroke(let points, false, _, _, let color) = op, color == paint.line {
                return points
            }
            return nil
        }
        for l in lines[2..<4] where l.count >= 2 {
            for i in 0..<(l.count - 1) {
                for k in 0...8 {
                    let p = lerp(l[i], l[i + 1], Float(k) / 8.0)
                    #expect(!routeInside(d, p) && !routeInside(e, p))
                }
            }
        }
    }

    @Test func labelsBreakTheLineInsteadOfCoveringIt() {
        let rect: [Float] = [10.0, 40.0, 30.0, 60.0]
        let runs = connector.outside([[20.0, 0.0], [20.0, 50.0], [20.0, 100.0]], rect)
        #expect(runs.count == 2)
        #expect(abs(runs[0].last![1] - 40.0) < 0.1 && abs(runs[1][0][1] - 60.0) < 0.1)
        #expect(connector.outside([[0.0, 0.0], [0.0, 9.0]], rect).count == 1)
    }

    @Test func everyDirectionDrawsSmoothEdgesThatReachTheirNodes() {
        let paint = DiagramStyle.neutral(true)
        for dir in ["TD", "BT", "LR", "RL"] {
            let src = "flowchart \(dir)\n  A[Start] --> B[Left]\n  A --> C[Right]\n  B --> D[End]\n  C -- label --> D\n  A --> D"
            guard let parsed = RuneMermaid.parse(src), case .flowchart(let f) = parsed.diagram else {
                Issue.record("Expected flowchart")
                return
            }
            let c = flowchart.drawCanvas(f, paint, (.edges, paint.text))!
            var lineCount = 0
            for op in c.ops {
                if case .stroke(let points, false, _, _, let color) = op, color == paint.line {
                    lineCount += 1
                    #expect(sharpestTurn(points) < 12.0, "\(dir): sharp turn")
                }
            }
            #expect(lineCount >= 5)
            let tips: [[Float]] = c.ops.compactMap { op in
                if case .fill(let p, let col) = op, col == paint.line && p.count == 3 {
                    return p[0]
                }
                return nil
            }
            #expect(tips.count == 5)
            for t in tips {
                let touching = c.regions.contains { r in
                    guard !r.isEmpty else { return false }
                    return (0..<r.count).contains { k in
                        segDist(t, r[k], r[(k + 1) % r.count]) < 1.0
                    }
                }
                #expect(touching, "\(dir): arrow tip \(t) doesn't touch a node")
            }
        }
    }
}
