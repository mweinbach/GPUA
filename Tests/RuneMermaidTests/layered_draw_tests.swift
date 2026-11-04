// Tests ported from: crates/rune-mermaid/src/layered_draw_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct LayeredDrawTests {
    private static let chat = "flowchart LR\n  subgraph Thing[\"The chat (task): has a history\"]\n    H1[your point] --> H2[result 1] --> H3[your reply] --> H4[result 2]\n  end\n  H4 -->|\"newest turn is a question\"| N[Needs you]\n  H4 -->|\"newest turn is a result you haven't read\"| R[Ready]\n  Note[(Note: lasts, has versions)] -.linked.- Thing"

    private func paintAt(_ dark: Bool, _ maxWidth: Float) -> DiagramStyle {
        var s = DiagramStyle.neutral(dark)
        s.maxWidth = maxWidth
        return s
    }

    private func makeCanvas(_ src: String, _ paint: DiagramStyle) -> Canvas {
        guard let parsed = RuneMermaid.parse(src), case .flowchart(let f) = parsed.diagram else {
            fatalError("parses: \(src)")
        }
        return flowchart.drawCanvas(f, paint, (.edges, paint.text))!
    }

    private func findLabel(_ c: Canvas, _ text: String) -> Label {
        c.labels.first(where: { $0.text == text })!
    }

    private func rect(_ l: Label) -> [Float] {
        [l.at[0], l.at[1], l.at[0] + l.size[0], l.at[1] + l.size[1]]
    }

    private func cluster(_ c: Canvas) -> [Float] {
        guard case .fill(let pts, _) = c.ops.first else {
            fatalError("a cluster first")
        }
        var b: [Float] = [.greatestFiniteMagnitude, .greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        for p in pts {
            b[0] = min(b[0], p[0])
            b[1] = min(b[1], p[1])
            b[2] = max(b[2], p[0])
            b[3] = max(b[3], p[1])
        }
        return b
    }

    private func lines(_ c: Canvas) -> [[[Float]]] {
        c.ops.compactMap { op in
            if case .stroke(let points, false, _, _, _) = op {
                return points
            }
            return nil
        }
    }

    private func hits(_ a: [Float], _ b: [Float], _ r: [Float]) -> Bool {
        (0...16).contains { k in
            let p = lerp(a, b, Float(k) / 16.0)
            return p[0] > r[0] && p[0] < r[2] && p[1] > r[1] && p[1] < r[3]
        }
    }

    @Test func noEdgeCrossesASubgraphTitle() {
        for dark in [false, true] {
            for width: Float in [680.0, 420.0, 2000.0] {
                let paint = paintAt(dark, width)
                let c = makeCanvas(Self.chat, paint)
                let title = rect(findLabel(c, "The chat (task): has a history"))
                for l in lines(c) where l.count >= 2 {
                    for i in 0..<(l.count - 1) {
                        #expect(!hits(l[i], l[i + 1], title), "edge crosses title at width \(width)")
                    }
                }
            }
        }
    }

    @Test func anEdgeToASubgraphStopsOnItsBorder() {
        let paint = DiagramStyle.neutral(false)
        let c = makeCanvas(Self.chat, paint)
        let b = cluster(c)
        let dashes: [[[Float]]] = c.ops.compactMap { op in
            if case .stroke(let points, _, _, .butt, _) = op {
                return points
            }
            return nil
        }
        #expect(!dashes.isEmpty)
        let inner: [Float] = [b[0] + 0.5, b[1] + 0.5, b[2] - 0.5, b[3] - 0.5]
        for d in dashes {
            #expect(!d.contains { $0[0] > inner[0] && $0[0] < inner[2] && $0[1] > inner[1] && $0[1] < inner[3] })
        }
        let minDist = dashes.flatMap { $0 }.map { p -> Float in
            let dx = max(max(b[0] - p[0], p[0] - b[2]), 0.0)
            let dy = max(max(b[1] - p[1], p[1] - b[3]), 0.0)
            return max(dx, dy)
        }.min() ?? .greatestFiniteMagnitude
        #expect(minDist < 1.5)
    }

    private func titleGap(_ dir: String) -> Float {
        let paint = paintAt(false, 4000.0)
        let c = makeCanvas("flowchart \(dir)\n  subgraph S[A title]\n    A[One] --> B[Two]\n  end", paint)
        let t = rect(findLabel(c, "A title"))
        let top = c.regions.flatMap { $0 }.map { $0[1] }.min()!
        return top - t[3]
    }

    @Test func aSubgraphTitleKeepsTheSameGapAboveItsNodesEitherWay() {
        let down = titleGap("TD")
        let right = titleGap("LR")
        #expect(abs(down - right) < 0.5)
        #expect(abs(down - 14.0) < 0.5)
    }

    @Test func edgesLeaveASubgraphSteeply() {
        for width: Float in [680.0, 2000.0] {
            let paint = paintAt(false, width)
            let c = makeCanvas(Self.chat, paint)
            let b = cluster(c)
            let turned = b[3] - b[1] > b[2] - b[0]
            var crossings = 0
            for l in lines(c) where l.count >= 2 {
                for i in 0..<(l.count - 1) {
                    let a = l[i]
                    let z = l[i + 1]
                    let (along, across, edge) = turned ? (1, 0, b[3]) : (0, 1, b[2])
                    if (a[along] - edge) * (z[along] - edge) < 0.0 && a[across] > b[across] && a[across] < b[across + 2] {
                        crossings += 1
                        let slope = abs(z[across] - a[across]) / abs(z[along] - a[along])
                        #expect(slope < 0.6)
                    }
                }
            }
            #expect(crossings == 2)
        }
    }

    @Test func wrappedLabelsBalanceTheirLines() {
        let paint = DiagramStyle.neutral(false)
        let m = measureBalanced("newest turn is a result you haven't read", paint.font)
        let one = measureBalanced("newest", paint.font).size[1]
        #expect(m.wrap && m.size[1] < one * 2.5)
        #expect(m.size[0] < 160.0)
    }

    @Test func aChartThatFitsItsCardKeepsItsDirection() {
        let narrow = paintAt(false, 300.0)
        let wide = paintAt(false, 2000.0)
        let tall: (Canvas) -> Bool = { c in
            let b = cluster(c)
            return b[3] - b[1] > b[2] - b[0]
        }
        #expect(!tall(makeCanvas(Self.chat, wide)))
        #expect(tall(makeCanvas(Self.chat, narrow)))
    }

    @Test func anEdgeRunsStraightThroughItsLabel() {
        for width: Float in [420.0, 680.0, 2000.0] {
            let c = makeCanvas(Self.chat, paintAt(false, width))
            for text in ["newest turn is a question", "newest turn is a result you haven't read"] {
                let r = rect(findLabel(c, text))
                let off: ([Float]) -> Float = { p in
                    max(max(r[0] - p[0], p[0] - r[2]), max(r[1] - p[1], p[1] - r[3]))
                }
                let ends: [[Float]] = lines(c).flatMap { [$0[0], $0[$0.count - 1]] }.filter { off($0) > -0.5 && off($0) < 10.0 }
                #expect(ends.count == 2)
                if ends.count == 2 {
                    let a = ends[0]
                    let b = ends[1]
                    #expect(abs(a[0] - b[0]) < 1.0 || abs(a[1] - b[1]) < 1.0)
                }
            }
        }
    }
}
