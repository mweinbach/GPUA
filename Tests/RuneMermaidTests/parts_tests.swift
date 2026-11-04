// Tests ported from: crates/rune-mermaid/src/parts_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite(.serialized)
struct PartsTests {
    private static let one = "graph TD\n  A[Start] --> B[Check]\n"
    private static let two = "graph TD\n  A[Start] --> B[Check]\n  B --> C[Done]\n"

    private func keys(_ src: String) -> [String] {
        let paint = DiagramStyle.neutral(true)
        let s = buildScene(src, paint, (.edges, paint.text))!
        return s.pieces.map { $0.key } + s.labelKeys.map { $0.0 }
    }

    private func has(_ keys: [String], _ want: [String]) -> Bool {
        want.allSatisfy { keys.contains($0) }
    }

    @Test func flowchartPiecesAreKeyedByMermaidIdAcrossRebuilds() {
        let a = keys("graph TD\n  A[Start] --> B{Ok?}\n")
        #expect(has(a, ["n:A", "n:B", "e:A>B", "n:A.t0", "n:B.t0"]))
        let b = keys("graph TD\n  A[Start] --> B{Ok?}\n  B -->|yes| C[Done]\n  B --> C\n")
        #expect(a.allSatisfy { b.contains($0) })
        #expect(has(b, ["n:C", "e:B>C", "e:B>C~1", "e:B>C.t0"]))
        let c = keys("graph TD\n  subgraph core [Core]\n    A --> B\n  end\n  B --> C\n")
        #expect(has(c, ["g:core", "g:core.t0", "n:A", "n:B", "n:C", "e:A>B", "e:B>C"]))
    }

    @Test func sequenceAndStatePiecesKeepTheirKeysAsLinesArrive() {
        let a = keys("sequenceDiagram\n  participant A\n  participant B\n  A->>B: hi\n")
        #expect(has(a, ["n:p0", "n:p1", "n:p0.end", "g:life0", "e:m0", "e:m0.t0"]))
        let b = keys("sequenceDiagram\n  participant A\n  participant B\n  A->>B: hi\n  B-->>A: hello\n  Note over A,B: done\n")
        #expect(a.allSatisfy { b.contains($0) })
        #expect(has(b, ["e:m1", "n:note2"]))

        let s = keys("stateDiagram-v2\n  [*] --> Idle\n  Idle --> Busy : go\n")
        #expect(has(s, ["n:Idle", "n:Busy", "e:Idle>Busy", "e:Idle>Busy.t0"]))
    }

    private func find(_ rt: Runtime<(String, Bool)>, _ key: String) -> ElementInfo? {
        rt.elements().first(where: { $0.key == key })
    }

    private func partsView(_ s: (String, Bool), _: Cx<(String, Bool)>) -> El {
        let paint = DiagramStyle.neutral(true)
        let el = s.1
            ? renderStreaming(s.0, paint, .edges, paint.text)
            : renderWithHover(s.0, paint, .edges, paint.text)
        return col().wFull().children(el.map { [$0] } ?? [])
    }

    @Test func aFinishedDiagramShowsWholeTheFrameItMounts() {
        scenes.resetCache()
        let rt1 = Runtime.new(("", false), partsView, (600.0, 600.0), Env.new(true, 1.0))
        _ = rt1.frame(0.0)
        rt1.update { s, _ in s.0 = Self.two }
        _ = rt1.frame(0.0)
        let shown = rt1.elements().filter { e in
            guard let k = e.key else { return true }
            return !k.hasPrefix("hover:") && k != "lit"
        }
        #expect(find(rt1, "n:C") != nil && find(rt1, "e:B>C") != nil)
        for e in shown where !e.path.contains("/hover:") {
            #expect(e.opacity == 1.0 && e.scale == 1.0, "\(String(describing: e.key)) fades or grows in")
        }

        let rt2 = Runtime.new((Self.one, false), partsView, (600.0, 600.0), Env.new(true, 1.0))
        _ = rt2.frame(0.0)
        rt2.update { s, _ in s.0 = Self.two }
        _ = rt2.frame(0.0)
        #expect(find(rt2, "n:C")?.opacity == 1.0)
    }

    @Test func aStreamingDiagramBringsNewNodesInAndGlidesTheRest() {
        scenes.resetCache()
        let rt = Runtime.new((Self.one, true), partsView, (600.0, 600.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        for _ in 0..<90 {
            _ = rt.frame(1.0 / 60.0)
        }
        let a = find(rt, "n:A")!
        rt.update { s, _ in s.0 = Self.two }
        _ = rt.frame(1.0 / 60.0)
        let c = find(rt, "n:C")!
        #expect(c.opacity < 0.5 && c.scale < 1.0)
        #expect(find(rt, "n:A")?.opacity == 1.0)
        for _ in 0..<90 {
            _ = rt.frame(1.0 / 60.0)
        }
        let c2 = find(rt, "n:C")!
        let a2 = find(rt, "n:A")!
        #expect(c2.opacity == 1.0 && c2.scale == 1.0)
        #expect(a.path == a2.path)
    }

    @Test func aStreamingDiagramGlidesInsideAGrowthRow() {
        scenes.resetCache()
        let growthView: (String, Cx<String>) -> El = { s, _ in
            let paint = DiagramStyle.neutral(true)
            return col().key("stack").wFull().growth(GrowthSpec())
                .child(col().key("row").wFull().children(renderStreaming(s, paint, .edges, paint.text).map { [$0] } ?? []))
        }
        let findKey: (Runtime<String>, String) -> ElementInfo = { rt, key in
            rt.elements().first(where: { $0.key == key })!
        }
        let rt1 = Runtime.new(Self.two, growthView, (600.0, 600.0), Env.new(true, 1.0))
        _ = rt1.frame(0.0)
        let before = findKey(rt1, "n:B").rect
        rt1.update { s, _ in s += "  Z[First] --> A\n" }
        for _ in 0..<90 {
            _ = rt1.frame(1.0 / 60.0)
        }
        let after = findKey(rt1, "n:B").rect
        #expect(abs(after[1] - before[1]) > 10.0)

        scenes.resetCache()
        let rt2 = Runtime.new(Self.two, growthView, (600.0, 600.0), Env.new(true, 1.0))
        _ = rt2.frame(0.0)
        rt2.update { s, _ in s += "  Z[First] --> A\n" }
        _ = rt2.frame(1.0 / 60.0)
        let mid = findKey(rt2, "n:B").rect
        #expect(abs(mid[1] - before[1]) < abs(after[1] - before[1]) - 1.0)
    }
}
