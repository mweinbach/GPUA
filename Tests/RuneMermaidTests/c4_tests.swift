// Tests ported from: crates/rune-mermaid/src/c4_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct C4Tests {
    private func parseC4(_ src: String) -> c4.C4 {
        guard let parsed = RuneMermaid.parse(src), case .c4(let c) = parsed.diagram else {
            fatalError("not a C4 diagram: \(src)")
        }
        return c
    }

    @Test func elementsBoundariesAndRelationships() {
        let d = parseC4(#"""
        C4Context
            title System Context diagram for Internet Banking System
            Enterprise_Boundary(b0, "BankBoundary0") {
              Person(customerA, "Banking Customer A", "A customer of the bank, with personal bank accounts.")
              System(SystemAA, "Internet Banking System", "Allows customers to view information.", $tags="v1.0")
              Boundary(b1, "BankBoundary", "boundary") {
                SystemDb_Ext(SystemE, "Mainframe Banking System", "Stores all of the core banking information.")
              }
            }
            ContainerQueue(q, "Events", "Kafka", "Domain events")
            Person_Ext(other, "Visitor")
            Rel(customerA, SystemAA, "Uses")
            BiRel(SystemAA, SystemE, "Uses", "XML/HTTPS")
            Rel_Back(q, SystemAA, "Feeds")
            Rel_U(other, customerA, "Asks")
            Rel(customerA, nobody, "Lost")
            UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
        """#)
        #expect(d.title == "System Context diagram for Internet Banking System")
        #expect(d.elements.map { $0.label } == ["Banking Customer A", "Internet Banking System", "Mainframe Banking System", "Events", "Visitor"])
        #expect(d.boundaries.count == 2)
        #expect(d.boundaries[0].title == "BankBoundary0\n[Enterprise]" && d.boundaries[1].parent == 0)
        #expect(d.elements[0].boundary == 0 && d.elements[2].boundary == 1 && d.elements[3].boundary == nil)
        #expect(d.elements[2].store == .db && d.elements[2].external)
        #expect(d.elements[3].techn == "Kafka" && d.elements[3].descr == "Domain events")
        #expect(c4.stereotype(d.elements[2]) == "«external_system_db»")
        #expect(d.edges.count == 4)
        #expect(d.edges[1].label == "Uses\n[XML/HTTPS]")
        #expect(d.edges[1].start == .arrow && d.edges[1].end == .arrow)
        #expect(d.edges[2].from == 3 && d.edges[2].start == .arrow && d.edges[2].end == .none)
        #expect(d.edges[3].from == 0 && d.edges[3].to == 4 && d.edges[3].start == .arrow)
        #expect(RuneMermaid.parse("C4Context\n    title Empty") == nil)
    }

    @Test func dynamicDiagramsNumberTheirSteps() {
        let d = parseC4("C4Dynamic\n    Container(a, \"App\")\n    ContainerDb(b, \"DB\")\n    RelIndex(1, a, b, \"Reads\")\n    Rel(b, a, \"Rows\")")
        #expect(d.edges.map { $0.label! } == ["1: Reads", "2: Rows"])
        let deep = "C4Deployment\n\(String(repeating: "Deployment_Node(n, \"N\") {\n", count: MAX_DEPTH + 1))Node(x, \"X\")"
        #expect(RuneMermaid.parse(deep) == nil)
    }

    @Test func drawsCardsInsideTheirFrames() {
        let s = buildScene(
            "C4Container\nSystem_Boundary(s, \"Shop\") {\nContainer(web, \"Web\", \"Rust\", \"Serves pages\")\n}\nPerson(u, \"User\")\nRel(u, web, \"Visits\", \"HTTPS\")",
            DiagramStyle.neutral(true),
            nil
        )!
        let at: (String) -> [Float] = { t in s.labels.first(where: { $0.text == t })!.at }
        for t in ["«container»", "[Rust]", "Serves pages", "«person»", "Shop\n[System]", "Visits\n[HTTPS]"] {
            _ = at(t)
        }
        #expect(at("User")[1] < at("Web")[1])
    }
}
