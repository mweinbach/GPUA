// Tests ported from: crates/rune-mermaid/src/sankey_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct SankeyTests {
    private func parseSankey(_ src: String) -> sankey.Sankey {
        guard let parsed = RuneMermaid.parse(src), case .sankey(let s) = parsed.diagram else {
            fatalError("not a sankey diagram: \(src)")
        }
        return s
    }

    @Test func rowsReadAsCsv() {
        let s = parseSankey(
            "sankey-beta\n\nAgricultural 'waste',Bio-conversion,124.729\n\"Bio, conversion\",Liquid,0.597\n\"Say \"\"hi\"\"\",Losses,26.862\nbad row\nA,A,3\nA,B,-1\nA,B,x"
        )
        #expect(s.nodes == ["Agricultural 'waste'", "Bio-conversion", "Bio, conversion", "Liquid", "Say \"hi\"", "Losses"])
        #expect(s.links.count == 3)
        #expect(s.links[2].0 == 4 && s.links[2].1 == 5 && abs(s.links[2].2 - 26.862) < 1e-3)
        #expect(RuneMermaid.parse("sankey-beta\nnot,a number,here") == nil)
        let budget = "sankey-beta\n" + (0..<MAX_ITEMS).map { "a\($0),b\($0),1" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func sinksGoLastAndCyclesStayBounded() {
        let s = parseSankey("sankey-beta\nA,B,5\nB,C,3\nA,D,2\nC,B,1")
        let col = sankey.columns(s)
        #expect(col[0] == 0)
        #expect(col[3] == col.max())
        #expect(col.allSatisfy { $0 < s.nodes.count })
    }

    @Test func flowsRunLeftToRight() {
        let paint = DiagramStyle.neutral(true)
        let s = buildScene("sankey-beta\nSolar,Grid,10\nWind,Grid,20\nGrid,Homes,30", paint, nil)!
        let at: (String) -> [Float] = { t in s.labels.first(where: { $0.text.hasPrefix(t) })!.at }
        #expect(at("Solar")[0] < at("Grid")[0] && at("Grid")[0] < at("Homes")[0])
        #expect(s.labels.contains { $0.text == "Grid 30" })
    }
}
