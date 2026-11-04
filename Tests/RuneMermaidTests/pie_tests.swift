// Tests ported from: crates/rune-mermaid/src/pie_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct PieTests {
    private struct SliceItem: Equatable {
        var name: String
        var value: Double
        init(_ name: String, _ value: Double) {
            self.name = name
            self.value = value
        }
    }

    private func parsePie(_ src: String) -> pie.Pie {
        guard let parsed = RuneMermaid.parse(src), case .pie(let p) = parsed.diagram else {
            fatalError("not a pie chart: \(src)")
        }
        return p
    }

    @Test func slicesTitlesAndShowData() {
        let p = parsePie("pie showData title Pets adopted\n\"Dogs\" : 386\n\"Cats\" : 85.5\nRats : 15\n\"Bad\" : -3\n\"Zero\" : 0\nnot a slice\n\"x\" : lots")
        #expect(p.title == "Pets adopted")
        #expect(p.showData)
        #expect(p.slices.map { SliceItem($0.0, $0.1) } == [
            SliceItem("Dogs", 386.0),
            SliceItem("Cats", 85.5),
            SliceItem("Rats", 15.0),
        ])
        let p2 = parsePie("pie\n  title Key: value\n  \"A: one\" : 1")
        #expect(p2.title == "Key: value")
        #expect(p2.slices[0].0 == "A: one")
        #expect(!p2.showData)
        #expect(RuneMermaid.parse("pie title Empty") == nil)
    }

    @Test func numbersPrintShort() {
        #expect(pie.number(386.0) == "386")
        #expect(pie.number(85.5) == "85.5")
        #expect(pie.number(1.0 / 3.0) == "0.33")
    }

    @Test func drawsPercentagesAndALegend() {
        let paint = DiagramStyle.neutral(false)
        let s = buildScene("pie showData\n\"Dogs\" : 70\n\"Cats\" : 26\n\"Fish\" : 4", paint, nil)!
        let texts = s.labels.map { $0.text }
        for t in ["70%", "26%", "Dogs", "Cats", "Fish", "70", "4"] {
            #expect(texts.contains(t))
        }
        #expect(!texts.contains("4%"))
        let budget = "pie\n" + (0...MAX_ITEMS).map { "\"s\($0)\" : 1" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }
}
