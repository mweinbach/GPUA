// Tests ported from: crates/rune-mermaid/src/sequence_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct SequenceTests {
    private struct PartTriple: Equatable {
        var id: String
        var label: String
        var kind: sequence.Kind
        init(_ id: String, _ label: String, _ kind: sequence.Kind) {
            self.id = id
            self.label = label
            self.kind = kind
        }
    }

    private func seq(_ src: String) -> sequence.Sequence {
        guard let parsed = RuneMermaid.parse(src), case .sequence(let s) = parsed.diagram else {
            fatalError("not a sequence diagram: \(src)")
        }
        return s
    }

    @Test func participantsMessagesAndActivation() {
        let s = seq(
            "sequenceDiagram\n  autonumber\n  actor U as User\n  participant A as API server\n  U->>+A: GET /items\n  A-->>-U: 200 OK\n  A->B: plain\n  B-->A: dotted\n  A-xB: lost\n  B--)A: async\n  A<<->>B: both\n  A->>A: think"
        )
        #expect(s.autonumber)
        #expect(s.participants.map { PartTriple($0.id, $0.label, $0.kind) } == [
            PartTriple("U", "User", .actor),
            PartTriple("A", "API server", .box),
            PartTriple("B", "B", .box),
        ])
        let msgs: [sequence.Message] = s.events.compactMap {
            if case .message(let m) = $0 { return m }
            return nil
        }
        #expect(msgs[0].from == 0 && msgs[0].to == 1 && msgs[0].text == "GET /items" && msgs[0].activate)
        #expect(msgs[1].dotted && msgs[1].tip == .filled && msgs[1].deactivate)
        #expect(!msgs[2].dotted && msgs[2].tip == .none)
        #expect(msgs[3].dotted && msgs[3].tip == .none)
        #expect(msgs[4].tip == .cross)
        #expect(msgs[5].dotted && msgs[5].tip == .open)
        #expect(msgs[6].both)
        #expect(msgs[7].from == 1 && msgs[7].to == 1)
    }

    @Test func notesFramesBoxesAndExplicitActivation() {
        let s = seq(
            "sequenceDiagram\ntitle Frame commit\nbox rgb(30, 60, 90) Desk\n  participant web-app\nend\nbox Storage\n  participant db\nend\nNote right of web-app: thinks\nnote over web-app,db: shared<br>two lines\nloop Every minute\n  web-app->>db: ping\nend\nalt ok\n  activate db\n  db-->>web-app: rows\n  deactivate db\nelse error\n  db-->>web-app: 500\nend\nrect rgb(40, 80, 60)\n  opt maybe\n    web-app->db: x\n  end\nend"
        )
        #expect(s.title == "Frame commit")
        #expect(s.boxes.count == 2)
        #expect(s.boxes[0].title == "Desk")
        #expect(s.boxes[0].color != nil)
        #expect(s.participants[0].group == 0)
        #expect(s.participants[1].group == 1)
        #expect(s.participants[0].id == "web-app")
        if case .note(.right(0), let t0) = s.events[0] {
            #expect(t0 == "thinks")
        } else {
            Issue.record("Expected Note right of 0")
        }
        if case .note(.over(0, 1), let t1) = s.events[1] {
            #expect(t1 == "shared\ntwo lines")
        } else {
            Issue.record("Expected Note over 0,1")
        }
        if case .open(let k, let lbl, _) = s.events[2] {
            #expect(k == "loop" && lbl == "Every minute")
        } else {
            Issue.record("Expected Open loop")
        }
        #expect(s.events.contains { if case .else(let l) = $0 { return l == "error" }; return false })
        #expect(s.events.contains { if case .activate(1) = $0 { return true }; return false })
        #expect(s.events.contains { if case .open(nil, _, let fill) = $0 { return fill != nil }; return false })
        #expect(s.events.filter { if case .end = $0 { return true }; return false }.count == 4)
        #expect(sequence.draw(s, DiagramStyle.neutral(true)) != nil)
    }

    @Test func onlySourcesWhereNothingReadsAreRejected() {
        for src in ["sequenceDiagram", "sequenceDiagram\nA something B", "sequenceDiagram\n->>B: no sender\nend\nelse x"] {
            #expect(RuneMermaid.parse(src) == nil)
        }
    }

    @Test func aLineThatDoesNotReadIsSkipped() {
        let msgsCount: (String) -> Int = { src in
            self.seq(src).events.filter { if case .message = $0 { return true }; return false }.count
        }
        for src in [
            "sequenceDiagram\nA something B\nA->>B: hi",
            "sequenceDiagram\n->>B: no sender\nA->>B: hi",
            "sequenceDiagram\nA->>: no receiver\nA->>B: hi",
            "sequenceDiagram\nend\nelse x\nA->>B: hi",
            "sequenceDiagram\nNote sideways of A: x\nNote over A no colon\nA->>B: hi",
        ] {
            #expect(msgsCount(src) == 1)
            #expect(seq(src).participants.count == 2)
        }
        let s1 = seq("sequenceDiagram\nloop unclosed\n  A->>B: hi\nbox unclosed\n  participant C")
        if let last = s1.events.last, case .end = last {
            // ok
        } else {
            Issue.record("Expected open frame to close at end")
        }
        #expect(s1.participants[2].group == 0)
        let s2 = seq("sequenceDiagram\nparticipant A@{ \"type\": \"database\" }\nA->>B: hi")
        #expect(s2.participants[0].label == "A")
    }

    @Test func participantTypesDrawTheirOwnHeads() {
        let src = "sequenceDiagram\n  participant W@{ \"type\": \"boundary\" }\n  participant C@{ \"type\" : \"control\" }\n  participant E@{ \"type\": \"entity\" }\n  participant D@{ \"type\": \"database\" }\n  participant L@{ \"type\": \"collections\" }\n  participant Q@{ \"type\": \"queue\" }\n  participant P@{ \"type\": \"mystery\" }\n  W->>C: a\n  C->>E: b\n  E->>D: c\n  D->>L: d\n  L->>Q: e\n  Q->>P: f"
        let s = seq(src)
        #expect(s.participants.map { $0.kind } == [.boundary, .control, .entity, .database, .collections, .queue, .box])
        #expect(sequence.draw(s, DiagramStyle.neutral(false)) != nil)
    }

    @Test func createDestroyAndNumbering() {
        let s = seq(
            "sequenceDiagram\n  autonumber 10 5\n  A->>B: hello\n  create participant C\n  B->>C: make\n  destroy C\n  C-->>B: bye\n  autonumber off\n  A->>B: quiet"
        )
        #expect(s.events.contains { if case .number(let n) = $0 { return n?.0 == 10 && n?.1 == 5 }; return false })
        #expect(s.events.contains { if case .number(nil) = $0 { return true }; return false })
        #expect(s.events.contains { if case .create(2) = $0 { return true }; return false })
        #expect(s.events.contains { if case .destroy(2) = $0 { return true }; return false })
        let paint = DiagramStyle.neutral(false)
        let sc = sequence.draw(s, paint)!
        let both = buildScene("sequenceDiagram\n  A->>B: hello\n  B->>C: make\n  C-->>B: bye\n  A->>B: quiet", paint, nil)!
        #expect(sc.size[1] > both.size[1])
        #expect(RuneMermaid.parse("sequenceDiagram\n  autonumber many\n  A->>B: hi") != nil)
    }

    @Test func nestingPastTheBoundStillRejects() {
        let deep = String(repeating: "loop x\n", count: MAX_DEPTH + 1)
        #expect(RuneMermaid.parse("sequenceDiagram\n\(deep)A->>B: hi") == nil)
    }

    @Test func everyPrefixDrawsOrFallsBackWithoutPanicking() {
        assertPrefixesNeverPanic(
            "sequenceDiagram\n  autonumber\n  actor U as User\n  U->>+A: hi\n  loop retry\n    A->>B: call\n    B--xA: fail\n  end\n  Note left of U: waits\n  A-->>-U: done",
            true
        )
    }

    @Test func longMessagesWidenTheirGap() {
        let paint = DiagramStyle.neutral(false)
        let narrow = buildScene("sequenceDiagram\nA->>B: hi", paint, nil)!
        let wide = buildScene("sequenceDiagram\nA->>B: a much longer message that needs room", paint, nil)!
        #expect(wide.size[0] > narrow.size[0] + 100.0)
    }
}
