// Tests ported from: crates/rune-mermaid/src/mindmap_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct MindmapTests {
    private func parseMindmap(_ src: String) -> mindmap.Mindmap {
        guard let parsed = RuneMermaid.parse(src), case .mindmap(let m) = parsed.diagram else {
            fatalError("not a mindmap: \(src)")
        }
        return m
    }

    private func texts(_ m: mindmap.Mindmap, _ i: Int) -> [String] {
        m.nodes[i].children.map { m.nodes[$0].text }
    }

    @Test func nestsByIndentationWithShapes() {
        let m = parseMindmap(
            "mindmap\n  root((mindmap))\n    Origins\n      Long history\n      ::icon(fa fa-book)\n      Popularisation\n        British author\n    Research\n      a[On effectiveness<br/>and features]\n      b))Bang((\n      c)Cloud(\n      d{{Hex}}\n      e(Rounded):::urgent\n    Tools\n      f[unclosed"
        )
        #expect(m.nodes[0].text == "mindmap")
        #expect(m.nodes[0].look == .circle)
        #expect(texts(m, 0) == ["Origins", "Research", "Tools"])
        #expect(texts(m, 1) == ["Long history", "Popularisation"])
        let research = m.nodes[0].children[1]
        #expect(texts(m, research) == ["On effectiveness\nand features", "Bang", "Cloud", "Hex", "Rounded"])
        #expect(m.nodes[research].children.map { m.nodes[$0].look } == [.square, .bang, .cloud, .hexagon, .rounded])
        let tools = m.nodes[0].children[2]
        let f = m.nodes[tools].children[0]
        #expect(m.nodes[f].text == "f[unclosed" && m.nodes[f].look == .plain)
    }

    @Test func oneRootAndBounds() {
        let m = parseMindmap("mindmap\n    Root\n  Shallower\n  Sibling\n    Child")
        #expect(texts(m, 0) == ["Shallower", "Sibling"])
        #expect(texts(m, 2) == ["Child"])
        #expect(RuneMermaid.parse("mindmap") == nil)
        let deep = (0...(MAX_DEPTH + 1)).map { "\(String(repeating: " ", count: $0 * 2))n\($0)\n" }.joined()
        #expect(RuneMermaid.parse("mindmap\n\(deep)") == nil)
        let wide = "mindmap\nroot\n" + (0..<MAX_ITEMS).map { "  n\($0)" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(wide) == nil)
    }

    @Test func branchesSplitLeftAndRight() {
        let paint = DiagramStyle.neutral(true)
        let s = buildScene("mindmap\n  Centre\n    One\n    Two\n    Three\n    Four", paint, nil)!
        let at: (String) -> Float = { t in
            let l = s.labels.first(where: { $0.text == t })!
            return l.at[0] + l.size[0] / 2.0
        }
        let centre = at("Centre")
        #expect(at("One") > centre && at("Two") > centre)
        #expect(at("Three") < centre && at("Four") < centre)
    }
}
