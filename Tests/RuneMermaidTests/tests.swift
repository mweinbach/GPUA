// Tests ported from: crates/rune-mermaid/src/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

func assertPrefixesNeverPanic(_ src: String, _ dark: Bool) {
    let paint = DiagramStyle.neutral(dark)
    var idx = src.unicodeScalars.startIndex
    while idx < src.unicodeScalars.endIndex {
        _ = buildScene(String(src[..<idx]), paint, nil)
        idx = src.unicodeScalars.index(after: idx)
    }
    #expect(buildScene(src, paint, nil) != nil)
}

@Suite struct CoreMermaidTests {
    @Test func cleanTurnsMarkupIntoText() {
        #expect(clean("a<br>b<br/>c<BR />d\\ne") == "a\nb\nc\nd\ne")
        #expect(clean("#quot;hi#quot; &amp; &lt;3 &apos;ok&apos;") == "\"hi\" & <3 'ok'")
        #expect(clean("`**md**`") == "**md**")
        #expect(clean("# not an entity & also not") == "# not an entity & also not")
        #expect(cleanQuoted(" \"capuchin ≈ Cappuccino\" ") == "capuchin ≈ Cappuccino")
    }

    @Test func otherDiagramTypesAndGarbageAreUnsupported() {
        for src in ["", "kanban\n  Todo", "pie title Pets", "gantt\ntitle x", "erDiagram", "hello", "%% only a comment"] {
            #expect(!supported(src), "\(src)")
        }
        let withTitle = buildScene("---\ntitle: Hi\n---\ngraph TD\nA-->B", DiagramStyle.neutral(true), nil)
        #expect(withTitle?.title == "Hi")
        #expect(supported("%%{\n  init: {'theme': 'dark'}\n}%%\nflowchart LR\nA-->B"))
        #expect(supported("stateDiagram-v2\n[*] --> Idle\nIdle --> [*]"))
        #expect(supported("classDiagram\nA <|-- B"))
        #expect(supported("flowchart TD\n  A[Runtime&lt;S&gt;] --> B[a; b]; B --> C"))
    }

    @Test func nodeStyleKeepsContrastInDarkAndLightThemes() {
        let pastel = parseStyleProps("fill:#dcf5dc,stroke:#333")
        for dark in [true, false] {
            let style = DiagramStyle.neutral(dark)
            let (fill, _, text) = pastel.resolve(style)
            let diff = abs(fill.toOklab()[0] - text.toOklab()[0])
            #expect(diff > 0.45, "dark=\(dark) contrast \(diff)")
        }
        #expect(parseColorSpec("rgb(30, 60, 90)") != nil)
        #expect(parseColorSpec("lightgreen") != nil)
    }

    @Test func dashesCoverTheLineInOnOffRuns() {
        var c = Canvas()
        c.dashed([[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]], 1.0, Color.WHITE, 3.0, 1.0)
        let dashes: [[[Float]]] = c.ops.map { op in
            switch op {
            case .stroke(let points, _, _, _, _):
                return points
            case .fill:
                Issue.record("Expected stroke op")
                return []
            }
        }
        #expect(dashes.count == 5)
        #expect(dashes[0].first == [0.0, 0.0])
        let corner = dashes[2]
        #expect(corner.count == 3)
        #expect(dist(corner[0], [8.0, 0.0]) < 1e-4 && dist(corner[1], [10.0, 0.0]) < 1e-4 && dist(corner[2], [10.0, 1.0]) < 1e-4)
    }

    @Test func smoothPassesThroughItsPoints() {
        let pts: [[Float]] = [[0.0, 0.0], [20.0, 40.0], [0.0, 80.0]]
        let curve = smooth(pts)
        #expect(curve.first == pts[0])
        #expect(curve.last == pts[2])
        #expect(curve.contains { dist($0, pts[1]) < 0.01 })
    }

    private func hostile(_ src: String, _ draws: Bool) {
        let paint = DiagramStyle.neutral(true)
        let clock = ContinuousClock()
        let start = clock.now
        let sc = buildScene(src, paint, nil)
        let elapsed = start.duration(to: clock.now)
        let secs = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        #expect((sc != nil) == draws, "\(src.prefix(80))…")
        #expect(secs < 5.0, "\(secs)s for \(src.prefix(80))…")
    }

    private func ids(_ prefix: String, _ n: Int) -> String {
        (1...n).map { "\(prefix)\($0)" }.joined(separator: " & ")
    }

    @Test func deepSubgraphsFallBack() {
        hostile("graph TD\n\(String(repeating: "subgraph s\n", count: 5000))A\n\(String(repeating: "end\n", count: 5000))", false)
        hostile("graph TD\n\(String(repeating: "subgraph s\n", count: 9))A\n\(String(repeating: "end\n", count: 9))", false)
        hostile("graph TD\n\(String(repeating: "subgraph s\n", count: 8))A\n\(String(repeating: "end\n", count: 8))", true)
        hostile("graph TD\nA\n\(String(repeating: "subgraph s\nend\n", count: 5000))", false)
    }

    @Test func aHugeCrossProductFallsBackBeforeItIsBuilt() {
        hostile("graph TD\n\(ids("A", 500)) --> \(ids("B", 500))", false)
        hostile("graph TD\n\(ids("A", 5000))", false)
        hostile("graph TD\n\(ids("A", 10)) --> \(ids("B", 10))", true)
    }

    @Test func aHugeDashCountDrawsAtTheLongestLink() {
        let paint = DiagramStyle.neutral(true)
        let tenKHyph = String(repeating: "-", count: 10_000)
        let tenKDots = String(repeating: ".", count: 10_000)
        hostile("graph TD\nA \(tenKHyph)> B", true)
        hostile("graph TD\nA -\(tenKDots)-> B", true)
        let longest = buildScene("graph TD\nA \(tenKHyph)> B", paint, nil)!
        let eight = buildScene("graph TD\nA \(String(repeating: "-", count: 9))> B", paint, nil)!
        #expect(longest.size == eight.size)
    }

    @Test func longChordsOverAChainFallBack() {
        let chain = (0..<129).map { "N\($0) --> N\($0 + 1)" }
        let chords = (0..<140).map { "N\($0 % 10) --> N\(120 + $0 % 10)" }
        hostile("graph TD\n\(chain.joined(separator: "\n"))\n\(chords.joined(separator: "\n"))", false)
        let short = (0..<4).map { "N\($0) --> N\(30 + $0)" }
        hostile("graph TD\n\(chain[..<40].joined(separator: "\n"))\n\(short.joined(separator: "\n"))", true)
    }

    @Test func theBiggestAllowedChartsDrawInBoundedTime() {
        var lines = ["graph LR"]
        for i in 0..<130 {
            lines.append("N\(i) --> N\((i * 7 + 1) % 130) & N\((i * 13 + 5) % 130)")
        }
        let src = lines.joined(separator: "\n")
        #expect(RuneMermaid.parse(src) != nil)
        let paint = DiagramStyle.neutral(true)
        let clock = ContinuousClock()
        var start = clock.now
        let drawn = buildScene(src, paint, nil) != nil
        #expect(!drawn, "dense 260-edge random graph hits MAX_DUMMIES and falls back")
        var elapsed = start.duration(to: clock.now)
        #expect(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18 < 5.0)

        var big = "graph TD\nsubgraph left\n"
        for i in 0..<59 {
            big += "N\(i) --> N\(i + 1)\n"
            if i == 30 {
                big += "end\nsubgraph right\n"
            }
        }
        big += "end\n"
        for k in 0..<40 {
            big += "N\(k % 20) --> N\(k % 20 + 37)\n"
        }
        start = clock.now
        #expect(buildScene(big, paint, nil) != nil)
        elapsed = start.duration(to: clock.now)
        #expect(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18 < 5.0)

        var nested = "graph TD\n"
        for d in 0..<8 {
            nested += "subgraph s\(d)\nA\(d) --> B\(d) --> C\(d)\n"
        }
        nested += String(repeating: "end\n", count: 8)
        nested += "A0 --> C7\nC7 --> A0"
        hostile(nested, true)
    }

    @Test func repeatedCreateIsSkippedWithoutRecursing() {
        hostile("sequenceDiagram\n\(String(repeating: "create ", count: 100_000))participant A\nA->>B: hi", true)
        hostile("sequenceDiagram\ncreate loop x\nA->>B: hi\nend", true)
        hostile("sequenceDiagram\ncreate participant A\nA->>B: hi", true)
        hostile("sequenceDiagram\nA->>B: hi\ncreate actor C as Carol\nB->>C: hello", true)
    }

    @Test func dashesStopOnHugeAndNonFiniteLengths() {
        let inkCol = Color.BLACK
        for end: Float in [1e9, .infinity, .nan] {
            var c = Canvas()
            c.dashed([[0.0, 0.0], [end, 0.0]], 1.0, inkCol, 4.0, 3.0)
            #expect(c.ops.count <= 20_000)
        }
    }
}
