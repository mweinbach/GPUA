// Tests ported from: crates/rune-mermaid/src/er_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct ErTests {
    private struct ErEnds: Equatable {
        var from: String
        var start: Head
        var line: Line
        var end: Head
        var to: String
        init(_ from: String, _ start: Head, _ line: Line, _ end: Head, _ to: String) {
            self.from = from
            self.start = start
            self.line = line
            self.end = end
            self.to = to
        }
    }

    private func parseEr(_ src: String) -> er.ErDiagram {
        guard let parsed = RuneMermaid.parse(src), case .er(let d) = parsed.diagram else {
            fatalError("not an ER diagram: \(src)")
        }
        return d
    }

    private func ends(_ d: er.ErDiagram, _ i: Int) -> ErEnds {
        let e = d.edges[i]
        return ErEnds(d.entities[e.from].id, e.start, e.line, e.end, d.entities[e.to].id)
    }

    @Test func entitiesAttributesAndCrowsFeet() {
        let d = parseEr(
            "erDiagram\nCUSTOMER ||--o{ ORDER : places\nORDER ||--|{ LINE-ITEM : contains\nCUSTOMER }|..|{ DELIVERY-ADDRESS : uses\nPERSON |o--o| SEAT : \"sits in\"\nCUSTOMER {\n  string name\n  string custNumber PK \"the key\"\n  list~string~ tags\n  int orderId FK, UK\n}\np[\"A person\"] { string first }"
        )
        #expect(d.dir == .down)
        #expect(ends(d, 0) == ErEnds("CUSTOMER", .onlyOne, .solid, .zeroOrMore, "ORDER"))
        #expect(ends(d, 1) == ErEnds("ORDER", .onlyOne, .solid, .oneOrMore, "LINE-ITEM"))
        #expect(ends(d, 2) == ErEnds("CUSTOMER", .oneOrMore, .dotted, .oneOrMore, "DELIVERY-ADDRESS"))
        #expect(ends(d, 3) == ErEnds("PERSON", .zeroOrOne, .solid, .zeroOrOne, "SEAT"))
        #expect(d.edges[3].label == "sits in")
        let c = d.entities.first(where: { $0.id == "CUSTOMER" })!
        #expect(c.attrs.count == 4)
        #expect(c.attrs[1] == er.Attr(ty: "string", name: "custNumber", keys: "PK", comment: "the key"))
        #expect(c.attrs[2].ty == "list<string>")
        #expect(c.attrs[3].keys == "FK, UK")
        let p = d.entities.first(where: { $0.id == "p" })!
        #expect(p.label == "A person" && p.attrs.count == 1)
    }

    @Test func wordedCardinalitiesAndDirection() {
        let d = parseEr(
            "erDiagram\ndirection LR\nCAR 1 to zero or more NAMED-DRIVER : allows\nPERSON many(0) optionally to 1+ \"Club House\" : joins"
        )
        #expect(d.dir == .right)
        #expect(ends(d, 0) == ErEnds("CAR", .onlyOne, .solid, .zeroOrMore, "NAMED-DRIVER"))
        #expect(ends(d, 1) == ErEnds("PERSON", .zeroOrMore, .dotted, .oneOrMore, "Club House"))
    }

    @Test func badLinesAndBlocksAreSkipped() {
        let d = parseEr(
            "erDiagram\nA ||--o{ B : ok\nthis is not a relation\nC ??--?? D : nope\nE bad name {\n  string x\n}\nB {\n  string fine\n  not-an-attribute\n}"
        )
        #expect(d.entities.map { $0.id } == ["A", "B"])
        #expect(d.entities[1].attrs.count == 1)
        #expect(RuneMermaid.parse("erDiagram\n  nothing here at all") == nil)
    }

    @Test func drawsTablesAndFeet() {
        let paint = DiagramStyle.neutral(false)
        let s = buildScene("erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\n string name PK\n}", paint, nil)!
        let texts = s.labels.map { $0.text }
        for t in ["CUSTOMER", "ORDER", "places", "string", "name", "PK"] {
            #expect(texts.contains(t))
        }
        let budget = "erDiagram\n" + (0..<MAX_ITEMS).map { "E\($0) ||--o{ F\($0) : r" }.joined(separator: "\n")
        #expect(RuneMermaid.parse(budget) == nil)
    }
}
