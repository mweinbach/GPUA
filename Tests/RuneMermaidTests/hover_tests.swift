// Tests ported from: crates/rune-mermaid/src/hover_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite(.serialized)
struct HoverTests {
    private static let litColor = Color(r: 0.9, g: 0.2, b: 0.5, a: 1.0)

    private func litScene(_ src: String) -> RuneMermaid.Scene {
        buildScene(src, DiagramStyle.neutral(false), (.edges, Self.litColor))!
    }

    private func label(_ s: RuneMermaid.Scene, _ text: String) -> Int {
        s.labels.firstIndex(where: { $0.text == text })!
    }

    private func spots(_ s: RuneMermaid.Scene, _ prefix: String) -> [Spot] {
        s.hovers.filter { $0.key.hasPrefix(prefix) }
    }

    private func inside(_ r: [Float], _ p: [Float]) -> Bool {
        p[0] >= r[0] && p[0] <= r[0] + r[2] && p[1] >= r[1] && p[1] <= r[1] + r[3]
    }

    private func centre(_ s: RuneMermaid.Scene, _ i: Int) -> [Float] {
        let l = s.labels[i]
        return [l.at[0] + l.size[0] / 2.0, l.at[1] + l.size[1] / 2.0]
    }

    @Test func aNodeLightsItsEdgesLabels() {
        let s = litScene("flowchart TD\n  A -->|go| B")
        let go = label(s, "go")
        for node in ["hover:n:A", "hover:n:B"] {
            let spot = spots(s, node).first!
            #expect(spot.labels == [go])
        }
        let st = litScene("stateDiagram-v2\n  Idle --> Busy : start")
        let start = label(st, "start")
        #expect(spots(st, "hover:n:").allSatisfy { $0.labels == [start] })
    }

    @Test func anEdgeLightsItselfAndItsLabelAndNodesWin() {
        let s = litScene("stateDiagram-v2\n  Idle --> Busy : start\n  Busy --> Done")
        let start = label(s, "start")
        let first = spots(s, "hover:e:Idle>Busy.")
        #expect(first.count >= 2)
        #expect(first.allSatisfy { $0.labels == [start] })
        let nodes = spots(s, "hover:n:").map { $0.rect }
        let overlap: ([Float], [Float]) -> Bool = { a, b in
            a[0] < b[0] + b[2] && b[0] < a[0] + a[2] && a[1] < b[1] + b[3] && b[1] < a[1] + a[3]
        }
        for h in spots(s, "hover:e:") {
            #expect(h.rect[2] >= 4.0 && h.rect[3] >= 4.0, "\(h.key) is big enough to aim at: \(h.rect)")
            #expect(!nodes.contains { overlap($0, h.rect) }, "\(h.key) stays off every node: \(h.rect)")
            #expect(h.rect.allSatisfy { $0.isFinite })
        }
        let thin = first.map { min($0.rect[2], $0.rect[3]) }.min() ?? .greatestFiniteMagnitude
        #expect(thin >= 2.0 * EDGE_SLOP - 0.5)
        let second = spots(s, "hover:e:Busy>Done.")
        #expect(!second.isEmpty && second.allSatisfy { $0.labels.isEmpty })
    }

    @Test func aLabelLightsItselfAndItsEdge() {
        let s = litScene("flowchart LR\n  A -->|go on| B\n  B --> C")
        let go = label(s, "go on")
        let over = s.hovers.filter { inside($0.rect, centre(s, go)) }
        #expect(!over.isEmpty)
        #expect(over.allSatisfy { $0.key.hasPrefix("hover:e:A>B.") && $0.labels == [go] })
    }

    @Test func anUnlitEdgesLabelStaysUnlit() {
        let s = litScene("flowchart TD\n  A -->|go| B\n  C -->|stay| D")
        let go = label(s, "go")
        let stay = label(s, "stay")
        for h in spots(s, "hover:n:A") + spots(s, "hover:n:B") + spots(s, "hover:e:A>B.") {
            #expect(h.labels == [go])
            #expect(!h.labels.contains(stay))
        }
        #expect(!s.hovers.contains { $0.labels.contains(go) && $0.labels.contains(stay) })
    }

    @Test func offDrawsNoHoverGroups() {
        let s = buildScene("flowchart TD\n  A -->|go| B", DiagramStyle.neutral(false), nil)!
        #expect(s.hovers.isEmpty)
    }

    @Test func lineHitsCoverABendAndStayBounded() {
        let hits = lineHits([[0.0, 0.0], [0.0, 100.0], [100.0, 100.0]], EDGE_SLOP)
        #expect(hits.count == 2)
        let wiggle: [[Float]] = (0..<400).map { i in [Float(i) * 3.0, i % 2 == 0 ? 0.0 : 30.0] }
        #expect(lineHits(wiggle, EDGE_SLOP).count <= 16)
        #expect(cutAway([[0.0, 0.0, 16.0, 100.0]], [[-10.0, 80.0, 40.0, 40.0]]) == [[0.0, 0.0, 16.0, 80.0]])
        #expect(cutAway([[0.0, 0.0, 16.0, 16.0]], [[-10.0, -10.0, 40.0, 40.0]]).isEmpty)
    }

    @Test func hoveringAnEdgeLightsItInstantlyAndLeavingDropsIt() {
        let view: (UInt32, Cx<UInt32>) -> El = { _, _ in
            let paint = DiagramStyle.neutral(false)
            let s = buildScene("stateDiagram-v2\n  Idle --> Busy : start", paint, (.edges, Self.litColor))!
            return col().wFull().child(s.el(paint, false))
        }
        let rt = Runtime.new(0 as UInt32, view, (400.0, 400.0), Env.new(false, 1.0))
        _ = rt.frame(0.0)
        let find: (Runtime<UInt32>, String) -> ElementInfo = { rt, key in
            rt.elements().first(where: { $0.key == key })!
        }
        let labelSpot = find(rt, "hover:e:Idle>Busy.t")
        let key = labelSpot.key!
        let r = labelSpot.rect
        rt.pointerMove(r[0] + r[2] / 2.0, r[1] + r[3] / 2.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(find(rt, key).hover == 1.0)
        #expect(find(rt, "hover:n:Idle").hover == 0.0)
        rt.pointerMove(1.0, 399.0)
        for _ in 0..<12 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(find(rt, key).hover == 0.0)
    }

    @Test func hoverGroupsAreKeyedByThePieceTheyLight() {
        let s = litScene("flowchart TD\n  A -->|go| B\n  B --> C\n")
        let pieces = s.pieces.map { $0.key }
        for h in s.hovers {
            let stripped = String(h.key.stripPrefix("hover:")!)
            let piece: String
            if stripped.hasPrefix("e:"), let (p, _) = stripped.rsplitOnce(".") {
                piece = String(p)
            } else {
                piece = stripped
            }
            #expect(pieces.contains(piece), "\(h.key) lights \(piece)")
            if piece.hasPrefix("e:") && !h.labels.isEmpty {
                #expect(s.labelKeys[h.labels[0]].0 == "\(piece).t0")
            }
        }
        #expect(s.hovers.contains { $0.key == "hover:e:A>B.t" })
    }

    @Test func aStillPointerKeepsWhatItHoversOrLetsGoAsAStreamingDiagramMoves() {
        scenes.resetCache()
        let view: (String, Cx<String>) -> El = { s, _ in
            let paint = DiagramStyle.neutral(false)
            return col().wFull().children(renderStreaming(s, paint, .edges, Self.litColor).map { [$0] } ?? [])
        }
        let litLabels: (Runtime<String>) -> [[String]] = { rt in
            let all = rt.elements()
            // PORT NOTE: `Sources/Rune` sets `ElementInfo.hover = 1.0` on non-hover-group ancestors via
            // `hoveredPaths`, so scope inspection to `hover:*` group elements.
            return all.filter { $0.hover > 0.0 && ($0.key?.hasPrefix("hover:") == true) }.map { g in
                let insidePrefix = "\(g.path)/"
                return all.filter { $0.path.hasPrefix(insidePrefix) }.compactMap { $0.text }.sorted()
            }
        }
        let src = "graph TD\n  X -->|in| S\n  S --> W\n  W -->|out| Y\n"
        let grown = "\(src)  subgraph S\n    D\n  end\n"
        let rect: (Runtime<String>, String) -> [Float]? = { rt, key in
            rt.elements().first(where: { $0.key == key && !$0.exiting })?.rect
        }
        for (over, before) in [("hover:e:W>Y.t", ["out"]), ("hover:n:S", ["in"])] {
            scenes.resetCache()
            let rt = Runtime.new(src, view, (600.0, 600.0), Env.new(false, 1.0))
            _ = rt.frame(0.0)
            let at = rect(rt, over)!
            let y = rect(rt, "n:Y")!
            rt.pointerMove(at[0] + at[2] / 2.0, at[1] + at[3] / 2.0)
            _ = rt.frame(1.0 / 60.0)
            let now = litLabels(rt)
            #expect(!now.isEmpty && now.allSatisfy { $0 == before })
            rt.update { s, _ in s = grown }
            for _ in 0..<240 {
                _ = rt.frame(1.0 / 60.0)
                if !rt.elements().contains(where: { $0.moving }) {
                    break
                }
                for l in litLabels(rt) {
                    #expect(l == before)
                }
            }
            let y2 = rect(rt, "n:Y")!
            #expect(abs(y2[1] - y[1]) > 8.0)
        }
    }
}
