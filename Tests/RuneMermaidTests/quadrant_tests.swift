// Tests ported from: crates/rune-mermaid/src/quadrant_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct QuadrantTests {
    private func parseQuadrant(_ src: String) -> quadrant.Quadrant {
        guard let parsed = RuneMermaid.parse(src), case .quadrant(let q) = parsed.diagram else {
            fatalError("not a quadrant chart: \(src)")
        }
        return q
    }

    @Test func axesQuadrantsPointsAndClasses() {
        let q = parseQuadrant(
            "quadrantChart\n    title Reach and engagement\n    x-axis Low Reach --> High Reach\n    y-axis Engagement\n    quadrant-1 We should expand\n    quadrant-4 May be improved\n    quadrant-9 Nope\n    Campaign A: [0.3, 0.6]\n    Campaign B: [0.45, 0.23] radius: 12, color: #ff3300, stroke-color: #10f0f0, stroke-width: 5px\n    Point C:::hot: [1.4, -0.2]\n    Broken: [x, 1]\n    classDef hot color: #109060, radius : 10"
        )
        #expect(q.title == "Reach and engagement")
        #expect(q.x == ["Low Reach", "High Reach"])
        #expect(q.y == ["Engagement", ""])
        #expect(q.names[0] == "We should expand")
        #expect(q.names[3] == "May be improved")
        #expect(q.names[1] == "")
        #expect(q.points.map { $0.name } == ["Campaign A", "Campaign B", "Point C"])
        #expect(q.points[1].look.radius == 12.0)
        #expect(q.points[1].look.strokeWidth == 5.0)
        #expect(q.points[1].look.color != nil && q.points[1].look.stroke != nil)
        #expect(q.points[2].at == [1.0, 0.0])
        #expect(q.points[2].look.radius == 10.0)
        #expect(RuneMermaid.parse("quadrantChart\n    title Only a title") == nil)
        let budget = "quadrantChart\n" + (0...MAX_ITEMS).map { "p\($0): [0.5, 0.5]" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func pointsLandByTheirValues() {
        let paint = DiagramStyle.neutral(false)
        let s = buildScene("quadrantChart\nquadrant-1 Q1\nquadrant-3 Q3\nHigh: [0.9, 0.9]\nLow: [0.1, 0.1]", paint, nil)!
        let at: (String) -> [Float] = { t in s.labels.first(where: { $0.text == t })!.at }
        #expect(at("High")[0] > at("Low")[0] && at("High")[1] < at("Low")[1])
        #expect(at("Q1")[0] > at("Q3")[0] && at("Q1")[1] < at("Q3")[1])
    }
}
