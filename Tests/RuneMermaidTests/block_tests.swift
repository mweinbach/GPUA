// Tests ported from: crates/rune-mermaid/src/block_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct BlockTests {
    private func parseBlocks(_ src: String) -> block.BlockDiagram {
        guard let parsed = RuneMermaid.parse(src), case .block(let b) = parsed.diagram else {
            fatalError("not a block diagram: \(src)")
        }
        return b
    }

    private func find(_ d: block.BlockDiagram, _ id: String) -> block.Block {
        d.blocks.first(where: { $0.id == id })!
    }

    @Test func rowsSpansGroupsAndArrows() {
        let d = parseBlocks(
            "block-beta\n  columns 3\n  a[\"Front end\"] b:2\n  space c((DB))\n  block:back:2\n    columns 2\n    d e\n  end\n  f<[\"go\"]>(right)\n  a --> b\n  b -- \"calls\" --> c\n  style a fill:#f96\n  classDef hot stroke:#f00\n  class c hot\n  g[unclosed"
        )
        #expect(d.blocks[0].kind == .group(columns: 3, children: [1, 2, 3, 4, 5, 8, 9]))
        #expect(find(d, "a").label == "Front end")
        #expect(find(d, "b").span == 2)
        #expect(d.blocks[3].kind == .space)
        #expect(find(d, "c").shape == .circle)
        #expect(find(d, "back").kind == .group(columns: 2, children: [6, 7]))
        #expect(find(d, "f").kind == .arrow(.right))
        #expect(find(d, "g").label == "unclosed")
        #expect(d.edges.count == 2)
        #expect(d.edges[1].label == "calls")
        #expect(find(d, "a").style.fill != nil && find(d, "c").style.stroke != nil)
        #expect(RuneMermaid.parse("block-beta\n  columns 2") == nil)
        let deep = "block-beta\n\(String(repeating: "block\n", count: MAX_DEPTH + 1))x\n"
        #expect(RuneMermaid.parse(deep) == nil)
        let budget = "block-beta\n" + (0..<MAX_ITEMS).map { "b\($0)" }.joined(separator: " ")
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func blocksWrapAtTheirColumns() {
        let paint = DiagramStyle.neutral(false)
        let s = buildScene("block-beta\ncolumns 2\nOne Two\nThree", paint, nil)!
        let at: (String) -> [Float] = { t in s.labels.first(where: { $0.text == t })!.at }
        #expect(at("One")[0] < at("Two")[0] && abs(at("One")[1] - at("Two")[1]) < 1.0)
        #expect(at("Three")[1] > at("One")[1] + 10.0)
        let auto = buildScene("block\nOne Two Three", paint, nil)!
        let ys = auto.labels.map { $0.at[1] }
        #expect(ys.allSatisfy { abs($0 - ys[0]) < 1.0 })
    }
}
