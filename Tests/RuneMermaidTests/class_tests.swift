// Tests ported from: crates/rune-mermaid/src/class_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct ClassTests {
    private func cls(_ src: String) -> `class`.ClassDiagram {
        guard let parsed = RuneMermaid.parse(src), case .class(let c) = parsed.diagram else {
            fatalError("not a class diagram: \(src)")
        }
        return c
    }

    @Test func classesMembersStereotypesNamespacesAndRelations() {
        let c = cls(
            "classDiagram\ndirection LR\nnamespace core {\n  class Runtime~S~ {\n    <<struct>>\n    +S state\n    +Scene motion\n    +frame(dt: f64)\n    +update(f)\n  }\n  class El {\n    +key(k)\n    +child(el)\n  }\n}\nRuntime \"1\" *-- \"*\" El : builds\nWidget <|.. Button : implements\nstyle Runtime fill:#dcf5dc"
        )
        #expect(c.dir == .right)
        #expect(c.namespaces.count == 1)
        #expect(c.namespaces[0].title == "core")
        let rt = c.classes.first(where: { $0.id == "Runtime" })!
        #expect(rt.label == "Runtime<S>")
        #expect(rt.stereo == "struct")
        #expect(rt.fields.count == 2)
        #expect(rt.methods.count == 2)
        #expect(rt.style.fill != nil)
        #expect(c.edges.count == 2)
        #expect(c.edges[0].start == .diamondFilled)
        #expect(c.edges[1].start == .openTriangle)
        let paint = DiagramStyle.neutral(true)
        #expect(`class`.draw(c, paint, nil) != nil)
    }

    @Test func onlySourcesWhereNothingReadsAreRejected() {
        for src in ["classDiagram", "classDiagram\n}", "classDiagram\njust garbage words here"] {
            #expect(RuneMermaid.parse(src) == nil)
        }
    }

    @Test func aStatementThatDoesNotReadIsSkippedWithItsBody() {
        let c1 = cls("classDiagram\nclass Open {\n  +x")
        #expect(c1.classes[0].fields == ["+x"])
        let c2 = cls("classDiagram\njust garbage words here\nclass Bad<<x {\n  +y\n}\nA --> B")
        #expect(c2.classes.map { $0.id } == ["A", "B"] && c2.edges.count == 1)
    }

    @Test func everyPrefixDrawsOrFallsBackWithoutPanicking() {
        assertPrefixesNeverPanic(
            "classDiagram\n  class A {\n    +i32 x\n    +run()\n  }\n  A --> B : calls",
            false
        )
    }
}
