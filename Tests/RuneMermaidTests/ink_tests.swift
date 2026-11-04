// Tests ported from: crates/rune-mermaid/src/ink_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct InkTests {
    private static let flow = "flowchart LR\n  R1[Retry at once] -->|fails| R2[Back off 1 s]\n  R2 -->|fails| Off[Offline]\n  R1 -->|ok| On[Online]"

    private func insideCount(_ points: [[Float]], _ p: [Float]) -> Int {
        guard !points.isEmpty else { return 0 }
        var odd = false
        var j = points.count - 1
        for i in 0..<points.count {
            let a = points[i]
            let c = points[j]
            if (a[1] > p[1]) != (c[1] > p[1]) && p[0] < (c[0] - a[0]) * (p[1] - a[1]) / (c[1] - a[1]) + a[0] {
                odd.toggle()
            }
            j = i
        }
        return odd ? 1 : 0
    }

    private func covers(_ a: [Float], _ b: [Float], _ width: Float, _ cap: LineCap, _ p: [Float]) -> Bool {
        let len = max(dist(a, b), 1e-6)
        let d: [Float] = [(b[0] - a[0]) / len, (b[1] - a[1]) / len]
        let t = (p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]
        let n = abs((p[0] - a[0]) * -d[1] + (p[1] - a[1]) * d[0])
        switch cap {
        case .butt:
            return (0.0...len).contains(t) && n <= width / 2.0
        case .round:
            return dist(p, lerp(a, b, clampF(t / len, 0.0, 1.0))) <= width / 2.0
        }
    }

    private func painted(_ ops: [Op], _ surface: Color, _ p: [Float]) -> Color {
        var under = surface
        for op in ops {
            switch op {
            case .fill(let points, let color):
                for _ in 0..<insideCount(points, p) {
                    under = ink.over(color, under)
                }
            case .stroke(let points, let closed, let width, let cap, let color):
                var segs: [([Float], [Float])] = []
                if points.count >= 2 {
                    for i in 0..<(points.count - 1) {
                        segs.append((points[i], points[i + 1]))
                    }
                }
                if closed && points.count > 2 {
                    segs.append((points[points.count - 1], points[0]))
                }
                for (a, b) in segs where covers(a, b, width, cap, p) {
                    under = ink.over(color, under)
                }
            }
        }
        return under
    }

    private func brighter(_ a: Color, _ b: Color) -> Float {
        a.luminance() - b.luminance()
    }

    @Test func aLineIsNoBrighterAtItsJointsUnderItsHeadOrRoundACorner() {
        let paint = DiagramStyle.neutral(true)
        let ops = buildScene(Self.flow, paint, nil)!.ops
        var checked = 0
        for op in ops {
            guard case .stroke(let points, let closed, _, _, _) = op, points.count >= 2 else { continue }
            var bestIdx = 0
            var bestLen = dist(points[0], points[1])
            for i in 1..<(points.count - 1) {
                let d = dist(points[i], points[i + 1])
                if !totalLess(d, bestLen) {
                    bestLen = d
                    bestIdx = i
                }
            }
            let body = painted(ops, paint.surface, lerp(points[bestIdx], points[bestIdx + 1], 0.5))
            let start = closed ? 0 : 1
            for p in points[start...] {
                let lift = brighter(painted(ops, paint.surface, p), body)
                #expect(lift < 0.002, "brighter by \(lift) at \(p)")
                checked += 1
            }
        }
        #expect(checked > 40)
    }

    @Test func everyDiagramDrawsItsInkOpaqueOverAnOpaqueSurface() {
        let sources = [
            Self.flow,
            "flowchart TD\n  subgraph S [Box]\n    A --> B\n  end\n  B -.-> C\n  C ==> A",
            "sequenceDiagram\n  participant A\n  participant B\n  A->>B: hi\n  B-->>A: back\n  A-)B: async\n  Note over A,B: note",
            "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy : go\n  Busy --> [*]",
            "classDiagram\n  Animal <|-- Duck\n  Animal *-- Leg\n  Animal o-- Tail\n  class Animal {\n    +int age\n    +eat()\n  }",
            "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER ||--|{ LINE : contains",
            "journey\n  title Day\n  section Work\n    Code: 5: Me\n    Meet: 2: Me, You",
            "timeline\n  2024 : one\n  2025 : two : three",
            "gitGraph\n  commit\n  branch dev\n  commit\n  checkout main\n  merge dev",
        ]
        for dark in [true, false] {
            let paint = DiagramStyle.neutral(dark)
            #expect(paint.surface.a == 1.0)
            for src in sources {
                let ops = buildScene(src, paint, nil)!.ops
                for op in ops {
                    switch op {
                    case .stroke(_, _, _, _, let color):
                        #expect(color.a == 1.0, "translucent stroke in \(src)")
                    case .fill(let points, let color) where points.count == 3:
                        #expect(color.a == 1.0, "translucent arrowhead in \(src)")
                    default:
                        break
                    }
                }
            }
        }
    }

    @Test func inkTakesTheColourOfTheFillsBeneathIt() {
        let surface = Color(r: 0.02, g: 0.02, b: 0.02, a: 1.0)
        let tint = Color.WHITE.alpha(0.1)
        let inkCol = Color.WHITE.alpha(0.5)
        var c = Canvas()
        c.fill([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]], tint)
        c.stroke([[10.0, 50.0], [90.0, 50.0]], false, 1.0, inkCol)
        c.stroke([[110.0, 50.0], [190.0, 50.0]], false, 1.0, inkCol)
        c.fill([[150.0, 40.0], [160.0, 50.0], [150.0, 60.0]], inkCol)
        var emptyTraces: [Trace] = []
        ink.flatten(&c.ops, &emptyTraces, surface)
        let colors: [Color] = c.ops.map { op in
            switch op {
            case .fill(_, let col), .stroke(_, _, _, _, let col):
                return col
            }
        }
        #expect(colors[0] == tint)
        #expect(colors[1] == ink.over(inkCol, ink.over(tint, surface)))
        #expect(colors[2] == ink.over(inkCol, surface))
        #expect(colors[3] == colors[2])
    }

    @Test func hoverTracesLightInOpaqueInkToo() {
        let paint = DiagramStyle.neutral(true)
        guard let parsed = RuneMermaid.parse(Self.flow), case .flowchart(let f) = parsed.diagram else {
            Issue.record("Expected flowchart")
            return
        }
        var c = flowchart.drawCanvas(f, paint, (.edges, paint.text.alpha(0.9)))!
        ink.flatten(&c.ops, &c.traces, paint.surface)
        let alphas: [Float] = c.traces.flatMap { $0.ops }.compactMap { op in
            if case .stroke(_, _, _, _, let color) = op { return color.a }
            return nil
        }
        #expect(alphas.count >= 3)
        #expect(alphas.allSatisfy { $0 == 1.0 })
    }
}
