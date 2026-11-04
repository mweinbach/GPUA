// Tests ported from: crates/rune-mermaid/src/flowchart_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct FlowchartTests {
    private struct NodeTriple: Equatable {
        var id: String
        var label: String
        var shape: NodeShape
        init(_ id: String, _ label: String, _ shape: NodeShape) {
            self.id = id
            self.label = label
            self.shape = shape
        }
    }

    private func flow(_ src: String) -> flowchart.Flowchart {
        guard let parsed = RuneMermaid.parse(src), case .flowchart(let f) = parsed.diagram else {
            fatalError("not a flowchart: \(src)")
        }
        return f
    }

    private func edges(_ f: flowchart.Flowchart) -> [[String]] {
        f.edges.map { [f.nodes[$0.from].id, f.nodes[$0.to].id] }
    }

    @Test func directionsShapesAndLabels() {
        let f = flow(
            "flowchart LR\n  A[Start] --> B(Round)\n  B --> C([Stadium]) --> D[[Sub]]\n  D --> E[(Database)] & F((Circle))\n  F --> G>Flag] --> H{Decide?} --> I{{Hex}}\n  I --> J[/Lean/] --> K[/Trap\\]\n  K --> L[\\Back\\] --> M[\\Top/] --> N(((Stop)))"
        )
        #expect(f.dir == .right)
        let shapes = f.nodes.map { NodeTriple($0.id, $0.label, $0.shape) }
        #expect(shapes == [
            NodeTriple("A", "Start", .rect),
            NodeTriple("B", "Round", .round),
            NodeTriple("C", "Stadium", .stadium),
            NodeTriple("D", "Sub", .subroutine),
            NodeTriple("E", "Database", .cylinder),
            NodeTriple("F", "Circle", .circle),
            NodeTriple("G", "Flag", .asymmetric),
            NodeTriple("H", "Decide?", .diamond),
            NodeTriple("I", "Hex", .hexagon),
            NodeTriple("J", "Lean", .leanRight),
            NodeTriple("K", "Trap", .trapBottom),
            NodeTriple("L", "Back", .leanLeft),
            NodeTriple("M", "Top", .trapTop),
            NodeTriple("N", "Stop", .doubleCircle),
        ])
        #expect(Array(edges(f)[3..<5]) == [["D", "E"], ["D", "F"]])
    }

    @Test func v11AtShapesSubgraphEndpointsAndLinkStyles() {
        let f = flow(
            "flowchart TD\nApp[Viewer] --> core\nsubgraph core [Rune Core]\n  El[El tree] --> Store@{ shape: cyl, label: \"AnimationStore\" }\nend\ncore --> GPU@{ shape: hex, label: \"wgpu\" }\nlinkStyle 0 stroke:#22c55e,stroke-width:2px"
        )
        #expect(f.nodes.count == 4)
        #expect(edges(f) == [["App", "El"], ["El", "Store"], ["Store", "GPU"]])
        let store = f.nodes.first(where: { $0.id == "Store" })!
        #expect(store.shape == .cylinder && store.label == "AnimationStore")
        #expect(f.edges[0].style.stroke != nil)
        #expect(f.edges[0].style.width == 2.0)
    }

    @Test func everyV11ShapeNameReadsAndDraws() {
        let names: [(String, NodeShape)] = [
            ("rect", .rect), ("event", .round), ("pill", .stadium), ("subproc", .subroutine),
            ("db", .cylinder), ("circ", .circle), ("dbl-circ", .doubleCircle), ("odd", .asymmetric),
            ("question", .diamond), ("prepare", .hexagon), ("in-out", .leanRight), ("out-in", .leanLeft),
            ("priority", .trapBottom), ("manual", .trapTop), ("start", .smallCircle), ("junction", .filledCircle),
            ("stop", .framedCircle), ("summary", .crossedCircle), ("bang", .bang), ("cloud", .cloud),
            ("card", .card), ("collate", .hourglass), ("com-link", .bolt), ("comment", .braceLeft),
            ("brace-r", .braceRight), ("braces", .braces), ("delay", .delay), ("das", .hCylinder),
            ("disk", .linedCylinder), ("display", .curvedTrapezoid), ("div-proc", .dividedRect), ("document", .document),
            ("lin-doc", .linedDocument), ("docs", .documents), ("tag-doc", .taggedDocument), ("extract", .triangle),
            ("manual-file", .flippedTriangle), ("join", .fork), ("internal-storage", .windowPane), ("shaded-process", .linedRect),
            ("loop-limit", .notchedPentagon), ("manual-input", .slopedRect), ("processes", .stackedRect), ("paper-tape", .flag),
            ("stored-data", .bowRect), ("tag-rect", .taggedRect), ("text", .text),
        ]
        var src = "flowchart TD\n"
        for (i, (name, _)) in names.enumerated() {
            src += "  n\(i)@{ shape: \(name), label: \"Step \(i)\" }\n"
            if i > 0 {
                src += "  n\(i - 1) --> n\(i)\n"
            }
        }
        let f = flow(src)
        #expect(f.nodes.map { $0.shape } == names.map { $0.1 })
        #expect(f.nodes.allSatisfy { $0.label.hasPrefix("Step ") })
        #expect(buildScene(src, DiagramStyle.neutral(false), nil) != nil)
    }

    @Test func iconsAndImagesDrawAsTheirFrame() {
        let f = flow("flowchart TD\n  A@{ icon: \"fa:user\", form: \"circle\", label: \"User\" }\n  B@{ img: \"https://example.com/a.png\", label: \"Pic\" }\n  A --> B")
        #expect(f.nodes.map { NodeTriple($0.id, $0.label, $0.shape) } == [
            NodeTriple("A", "User", .circle),
            NodeTriple("B", "Pic", .rect),
        ])
    }

    @Test func namedEdgesAndTheirSettingsAddNoNodes() {
        let f = flow("flowchart LR\n  A e1@--> B\n  B e2@-.-> C\n  e1@{ animate: true }\n  e2@{ animation: fast }")
        #expect(edges(f) == [["A", "B"], ["B", "C"]])
        #expect(f.edges[1].line == .dotted)
        #expect(f.nodes.count == 3)
    }

    @Test func linkStylesHeadsLengthsAndLabels() {
        let f = flow(
            "graph TD\nA --> B\nA --- C\nA -.-> D\nA ==> E\nA -- yes --> F\nA -->|no| G\nA <--> H\nA --o I\nA --x J\nA ---> K\nA -. maybe .-> L\nA == sure ==> M\nA ~~~ N\nA-->O;O-->P"
        )
        let e: (String) -> RuneMermaid.Edge = { to in
            f.edges.first(where: { f.nodes[$0.to].id == to })!
        }
        #expect(e("B").line == .solid && e("B").end == .arrow && e("B").minlen == 1)
        #expect(e("C").line == .solid && e("C").end == .none)
        #expect(e("D").line == .dotted && e("D").end == .arrow)
        #expect(e("E").line == .thick && e("E").end == .arrow)
        #expect(e("F").label == "yes")
        #expect(e("G").label == "no")
        #expect(e("H").start == .arrow && e("H").end == .arrow)
        #expect(e("I").end == .circle)
        #expect(e("J").end == .cross)
        #expect(e("K").minlen == 2)
        #expect(e("L").line == .dotted && e("L").label == "maybe")
        #expect(e("M").line == .thick && e("M").label == "sure")
        #expect(e("N").line == .invisible)
        #expect(e("P").from == f.nodes.firstIndex(where: { $0.id == "O" }))
    }

    @Test func quotedEdgeLabelsNestedBracketsAndStyles() {
        let f = flow(
            "flowchart LR\nA[Audio] --> B[Parakeet writes text<br/>'went to the capuchin']\nB --> C{Any word that looks<br/>or sounds like a term?}\nC -- no --> F[Paste as is]\nC -- \"capuchin ≈ Cappuccino\" --> D[Score the same audio twice:<br/>as 'capuchin' and as 'Cappuccino']\nD --> E(Call fn(x)) --> G[items[0]]\nG -->|\"a | b\"| F\nstyle D fill:#dcf5dc"
        )
        let toD = f.edges.first(where: { f.nodes[$0.to].id == "D" })!
        #expect(toD.label == "capuchin ≈ Cappuccino")
        let toF = f.edges.last(where: { f.nodes[$0.to].id == "F" })!
        #expect(toF.label == "a | b")
        #expect(f.nodes.first(where: { $0.id == "E" })?.label == "Call fn(x)")
        #expect(f.nodes.first(where: { $0.id == "G" })?.label == "items[0]")
        #expect(f.nodes.first(where: { $0.id == "D" })?.style.fill != nil)
    }

    @Test func subgraphsNestAndClaimNodes() {
        let f = flow(
            "graph TB\n  c1-->a2\n  subgraph one [The first]\n    a1-->a2\n    subgraph inner\n      x1\n    end\n  end\n  subgraph \"two\"\n    b1-->b2\n  end\n  classDef hot fill:#f00\n  class a1 hot\n  style b1 fill:#0f0\n  click b2 callback\n  a1:::hot --> b1"
        )
        #expect(f.subgraphs.map { $0.title } == ["The first", "inner", "two"])
        #expect(f.subgraphs[1].parent == 0)
        let cluster: (String) -> Int? = { id in f.nodes.first(where: { $0.id == id })!.cluster }
        #expect(cluster("c1") == nil)
        #expect(cluster("a2") == 0)
        #expect(cluster("x1") == 1)
        #expect(cluster("b2") == 2)
        #expect(f.nodes.first(where: { $0.id == "a1" })?.style.fill != nil)
        #expect(f.nodes.first(where: { $0.id == "b1" })?.style.fill != nil)
    }

    @Test func quotedLabelsBreaksAndDashedIds() {
        let f = flow("graph TD\n  web-server[\"Web (edge) server\"] --> db[(\"Postgres<br/>primary\")]")
        #expect(f.nodes[0].id == "web-server")
        #expect(f.nodes[0].label == "Web (edge) server")
        #expect(f.nodes[1].label == "Postgres\nprimary")
    }

    @Test func onlySourcesWhereNothingReadsAreRejected() {
        for src in ["graph TD", "graph TD\nend", "graph TD\n-->", "graph LR\n  this is not valid", "graph TD\n%% just a comment", "notADiagram\nA --> B"] {
            #expect(RuneMermaid.parse(src) == nil, "\(src)")
        }
    }

    @Test func anUnclosedShapeIsARectangleWithItsTextAsWritten() {
        let src = "flowchart LR\n  A[List + count] --> B[/items split view]\n  B --> C[Details]\n  C --> D[Pause / Resume / Delete]"
        let f = flow(src)
        #expect(f.nodes.map { NodeTriple($0.id, $0.label, $0.shape) } == [
            NodeTriple("A", "List + count", .rect),
            NodeTriple("B", "/items split view", .rect),
            NodeTriple("C", "Details", .rect),
            NodeTriple("D", "Pause / Resume / Delete", .rect),
        ])
        #expect(edges(f) == [["A", "B"], ["B", "C"], ["C", "D"]])
        #expect(buildScene(src, DiagramStyle.neutral(true), nil) != nil)
        #expect(flow("graph TD\nA[\\back slash]").nodes[0].label == "\\back slash")
        #expect(flow("graph TD\nA(open round").nodes[0].label == "open round")
        #expect(flow("graph TD\nA[unclosed --> B").nodes[0].label == "unclosed --> B")
        #expect(flow("flowchart TD\n  A{\"quote never closes} --> B").nodes[0].label == "\"quote never closes} --> B")
        #expect(flow("graph TD\nA@{ shape: not_a_shape } --> B").nodes[0].shape == .rect)
        #expect(flow("graph TD\nA@{ unclosed --> B").nodes[0].label == "A")
    }

    @Test func punctuationInLabelsIsPlainText() {
        let src = "flowchart LR\n  a[setting.some_name] --> b[run_* + /go]\n  c[(store -> row)] --> d[Item.Worker]\n  d --> e[/api/v2/item]"
        let f = flow(src)
        #expect(f.nodes.map { NodeTriple($0.id, $0.label, $0.shape) } == [
            NodeTriple("a", "setting.some_name", .rect),
            NodeTriple("b", "run_* + /go", .rect),
            NodeTriple("c", "store -> row", .cylinder),
            NodeTriple("d", "Item.Worker", .rect),
            NodeTriple("e", "/api/v2/item", .rect),
        ])
        #expect(edges(f) == [["a", "b"], ["c", "d"], ["d", "e"]])
        #expect(buildScene(src, DiagramStyle.neutral(false), nil) != nil)
    }

    @Test func aStatementThatDoesNotReadIsSkipped() {
        let cases: [(String, [[String]])] = [
            ("graph XY\nA-->B", [["A", "B"]]),
            ("graph TD\nA -- --> B\nC --> D", [["C", "D"]]),
            ("graph TD\nA -->|unclosed B\nC --> D", [["C", "D"]]),
            ("graph TD\nA - B\nC --> D", [["C", "D"]]),
            ("graph TD\nsubgraph open\n  A --> B", [["A", "B"]]),
            ("graph TD\nend\nA --> B\nend", [["A", "B"]]),
            ("graph TD\nA --> \nC --> D", [["C", "D"]]),
        ]
        for (src, want) in cases {
            let f = flow(src)
            #expect(edges(f) == want, "\(src)")
            let ids = f.nodes.map { $0.id }
            var used: [String] = []
            for pair in want {
                for id in pair where used.last != id {
                    used.append(id)
                }
            }
            if !want.isEmpty {
                #expect(ids == used, "\(src)")
            }
        }
    }

    @Test func goingPastTheBoundsStillRejects() {
        let deep = (0...MAX_DEPTH).map { "subgraph s\($0)\nA\($0)" }.joined(separator: "\n")
        #expect(RuneMermaid.parse("graph TD\n\(deep)") == nil)
        let wide = (0..<MAX_ITEMS).map { "N\($0) --> M\($0)" }.joined(separator: "\n")
        #expect(RuneMermaid.parse("graph TD\n\(wide)") == nil)
    }

    @Test func everyPrefixOfASourceParsesOrFallsBackWithoutPanicking() {
        assertPrefixesNeverPanic(
            "flowchart TD\n  A[Start] -->|go| B{Ok?}\n  B -- yes --> C([Done])\n  B -.->|no| A\n  subgraph s [Group]\n    C --> D[(Store)]\n  end",
            false
        )
    }

    @Test func boundaryPointsSitOnTheOutline() {
        let c: [Float] = [0.0, 0.0]
        #expect(boundary(.rect, c, [100.0, 40.0], [0.0, 100.0]) == [0.0, 20.0])
        #expect(boundary(.rect, c, [100.0, 40.0], [100.0, 0.0]) == [50.0, 0.0])
        let d = boundary(.diamond, c, [100.0, 40.0], [100.0, 40.0])
        #expect(abs(abs(d[0]) / 50.0 + abs(d[1]) / 20.0 - 1.0) < 1e-4)
        let e = boundary(.circle, c, [40.0, 40.0], [30.0, 40.0])
        #expect(abs(dist(c, e) - 20.0) < 1e-4)
    }
}
