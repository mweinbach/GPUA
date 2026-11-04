// Tests ported from: crates/rune-mermaid/src/requirement_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct RequirementTests {
    private func reqs(_ src: String) -> requirement.Requirements {
        guard let parsed = RuneMermaid.parse(src), case .requirement(let r) = parsed.diagram else {
            fatalError("not a requirement diagram: \(src)")
        }
        return r
    }

    @Test func blocksFieldsAndRelationships() {
        let d = reqs(
            "requirementDiagram\n    direction LR\n    requirement test_req {\n    id: 1\n    text: the test text.\n    risk: high\n    verifymethod: test\n    }\n    functionalRequirement \"Fast start\":::hot {\n    id: 1.1\n    risk: LOW }\n    element test_entity {\n    type: simulation\n    docref: reqs/test_entity\n    }\n    test_entity - satisfies -> test_req\n    test_req - contains -> \"Fast start\"\n    test_req <- copies - other\n    a - likes -> b\n    classDef hot fill:#f96"
        )
        #expect(d.dir == .right)
        #expect(d.nodes.map { $0.name } == ["test_req", "Fast start", "test_entity", "other"])
        #expect(d.nodes[0].fields == ["ID: 1", "Text: the test text.", "Risk: High", "Verification: Test"])
        #expect(d.nodes[1].kind == "Functional Requirement" && d.nodes[1].fields == ["ID: 1.1", "Risk: Low"])
        #expect(d.nodes[2].fields == ["Type: simulation", "Doc Ref: reqs/test_entity"])
        #expect(d.nodes[3].kind == "")
        #expect(d.nodes[1].style.fill != nil)
        #expect(d.edges.count == 3)
        #expect(d.edges[0].from == 2 && d.edges[0].to == 0 && d.edges[0].label == "«satisfies»")
        #expect(d.edges[1].start == .contains && d.edges[1].line == .solid)
        #expect(d.edges[2].from == 3 && d.edges[2].to == 0 && d.edges[2].end == .arrow)
        #expect(RuneMermaid.parse("requirementDiagram\n    direction TB") == nil)
    }

    @Test func drawsEachBoxWithItsFields() {
        let s = buildScene(
            "requirementDiagram\nrequirement r {\nid: 7\n}\nelement e {\ntype: code\n}\ne - verifies -> r",
            DiagramStyle.neutral(false),
            nil
        )!
        for t in ["«Requirement»", "r", "ID: 7", "«Element»", "Type: code", "«verifies»"] {
            #expect(s.labels.contains { $0.text == t })
        }
    }
}
