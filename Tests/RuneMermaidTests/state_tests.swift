// Tests ported from: crates/rune-mermaid/src/state_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct StateTests {
    private func parseState(_ src: String) -> state.StateDiagram {
        guard let parsed = RuneMermaid.parse(src), case .state(let s) = parsed.diagram else {
            fatalError("not a state diagram: \(src)")
        }
        return s
    }

    @Test func transitionsPseudostatesDescriptionsAndComposites() {
        let s = parseState(
            "stateDiagram-v2\ndirection LR\n[*] --> Queued\nstate \"In flight\" as Working {\n  Queued --> Applying : turn starts\n  Applying --> Check\n  state Check <<choice>>\n  Check --> Applied : commit landed\n  Check --> Unapplied : stalled\n}\nApplied : Card moves to Review\nApplied --> [*]"
        )
        #expect(s.dir == .right)
        #expect(s.composites.count == 1)
        #expect(s.composites[0].title == "In flight")
        #expect(s.states.contains { $0.kind == .start })
        #expect(s.states.contains { $0.kind == .end })
        #expect(s.states.contains { $0.id == "Check" && $0.kind == .choice })
        #expect(s.states.first(where: { $0.id == "Applied" })?.desc == ["Card moves to Review"])
        let paint = DiagramStyle.neutral(true)
        #expect(state.draw(s, paint, nil) != nil)
    }

    @Test func notesSitBesideTheirStateOnADottedLine() {
        let s = parseState("stateDiagram-v2\n  Idle --> Busy\n  note right of Idle : waits here\n  note left of Busy\n    does the work\n    then stops\n  end note")
        let notes = s.states.filter { $0.kind == .note }.map { $0.label }
        #expect(notes == ["waits here", "does the work\nthen stops"])
        let dotted = s.edges.filter { $0.line == .dotted }.map { [s.states[$0.from].id, s.states[$0.to].id] }
        #expect(dotted.count == 2)
        #expect(dotted[0][0] == "Idle")
        #expect(dotted[1][1] == "Busy")
        #expect(s.edges.filter { $0.line == .dotted }.allSatisfy { $0.end == .none })
        #expect(state.draw(s, DiagramStyle.neutral(false), nil) != nil)
        let open = parseState("stateDiagram-v2\nnote right of A\n  never closed")
        #expect(open.states.filter { $0.kind == .note }.count == 1)
    }

    @Test func concurrentRegionsSplitAComposite() {
        let s = parseState(
            "stateDiagram-v2\n  [*] --> Active\n  state Active {\n    [*] --> NumOff\n    NumOff --> NumOn\n    --\n    [*] --> CapsOff\n    CapsOff --> CapsOn\n    --\n    [*] --> ScrollOff\n  }\n  Active --> Done"
        )
        let regions = (0..<s.composites.count).filter { s.composites[$0].region }
        #expect(regions.count == 3)
        #expect(regions.allSatisfy { s.composites[$0].parent == 0 })
        let regionOf: (String) -> Int? = { id in s.states.first(where: { $0.id == id })!.cluster }
        #expect(regionOf("NumOn") == regions[0])
        #expect(regionOf("CapsOn") == regions[1])
        #expect(regionOf("ScrollOff") == regions[2])
        #expect(regionOf("Done") == nil)
        #expect(!s.states.contains { $0.id == "Active" })
        let id: (Int) -> String = { s.states[$0].id }
        let drawn = s.edges.filter { $0.line == .solid && id($0.to) == "Done" }.map { [id($0.from), id($0.to)] }
        #expect(drawn == [["NumOn", "Done"]])
        let held = s.edges.filter { $0.line == .invisible && id($0.to) == "Done" }.map { [id($0.from), id($0.to)] }
        #expect(held == [["CapsOn", "Done"], ["ScrollOff", "Done"]])
        #expect(s.edges.filter { $0.line == .invisible && s.states[$0.from].kind == .start && s.states[$0.from].cluster == nil }.count == 2)
        #expect(state.draw(s, DiagramStyle.neutral(true), nil) != nil)
        let back = parseState("stateDiagram-v2\n  [*] --> Busy\n  state Busy {\n    [*] --> A\n    --\n    [*] --> B\n  }\n  Busy --> Check\n  Check --> Busy : retry")
        #expect(back.edges.filter { $0.line == .invisible }.count == 2)
    }

    @Test func forkJoinAndChoice() {
        let s = parseState("stateDiagram-v2\n  state f <<fork>>\n  state j <<join>>\n  state c <<choice>>\n  [*] --> f\n  f --> A\n  f --> B\n  A --> j\n  B --> j\n  j --> c\n  c --> [*]")
        let kind: (String) -> state.StateKind = { id in s.states.first(where: { $0.id == id })!.kind }
        #expect(kind("f") == .bar && kind("j") == .bar && kind("c") == .choice)
        #expect(state.draw(s, DiagramStyle.neutral(false), nil) != nil)
    }

    @Test func onlySourcesWhereNothingReadsAreRejected() {
        for src in ["stateDiagram-v2", "stateDiagram\n}", "stateDiagram-v2\n-->\n--"] {
            #expect(RuneMermaid.parse(src) == nil)
        }
    }

    @Test func aStatementThatDoesNotReadIsSkipped() {
        let s1 = parseState("stateDiagram-v2\nstate Open {\n  A --> B")
        #expect(s1.states.count == 2 && s1.edges.count == 1 && s1.composites.count == 1)
        let s2 = parseState("stateDiagram-v2\ndirection diagonal\nA --> B")
        #expect(s2.dir == .down && s2.edges.count == 1)
        let s3 = parseState("stateDiagram-v2\nstate \"no id\" {\n  A --> B\n}\nC --> A")
        #expect(s3.composites[0].title == "no id")
        #expect(s3.states.filter { $0.cluster == nil }.count == 1)
    }

    @Test func everyPrefixDrawsOrFallsBackWithoutPanicking() {
        assertPrefixesNeverPanic(
            "stateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy : prompt\n  Busy --> Idle : done\n  Idle --> [*]",
            false
        )
    }
}
