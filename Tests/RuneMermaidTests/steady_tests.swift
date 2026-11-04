// Tests ported from: crates/rune-mermaid/src/steady_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite(.serialized)
struct SteadyTests {
    private static let retries = """
    flowchart LR
      Drop[Socket drops] --> R1[Retry at once]
      R1 -->|ok| On[Online]
      R1 -->|fails| R2[Back off 1 s]
      R2 -->|ok| On
      R2 -->|fails| Off[Offline]
      Off -->|retry| R2

    """

    private static let deploy = """
    flowchart TD
      A[Push] --> B{Tests pass?}
      B -->|no| C[Fix]
      C --> A
      B -->|yes| D[Build image]
      subgraph Ship
        D --> E[Canary]
        E --> F[Roll out]
      end
      E -->|errors| G[Roll back]
      G --> C
      F --> H([Done])

    """

    private static let connection = """
    stateDiagram-v2
      [*] --> Idle
      Idle --> Connecting: open
      Connecting --> Open: ok
      Connecting --> Backoff: fail
      Backoff --> Connecting: timer
      Open --> Closing: close
      Open --> Backoff: drop
      Closing --> [*]

    """

    private func centres(_ s: RuneMermaid.Scene) -> [String: [Float]] {
        var out: [String: [Float]] = [:]
        for p in s.pieces where p.key.hasPrefix("n:") && !p.key.contains(".") {
            out[p.key] = [p.at[0] + p.size[0] / 2.0, p.at[1] + p.size[1] / 2.0]
        }
        return out
    }

    private func stream(_ src: String) -> [RuneMermaid.Scene] {
        scenes.resetCache()
        let lines = src.rustLines().map { String($0) }
        guard lines.count >= 2 else { return [] }
        return (2...lines.count).compactMap { k in
            scenes.growing(lines[..<k].joined(separator: "\n") + "\n", DiagramStyle.neutral(true), nil)
        }
    }

    private func worstReversal(_ sceneList: [RuneMermaid.Scene]) -> (Float, String) {
        var paths: [String: [[Float]]] = [:]
        for s in sceneList {
            for (k, c) in centres(s) {
                paths[k, default: []].append(c)
            }
        }
        var worst: (Float, String) = (0.0, "")
        for (k, path) in paths {
            for axis in 0..<2 {
                var lo = Float.greatestFiniteMagnitude
                var hi = -Float.greatestFiniteMagnitude
                var up: Float = 0.0
                var down: Float = 0.0
                for p in path {
                    let v = p[axis]
                    up = max(up, hi - v)
                    down = max(down, v - lo)
                    lo = min(lo, v)
                    hi = max(hi, v)
                }
                let back = min(up, down)
                if back > worst.0 {
                    worst = (back, "\(k) axis \(axis): \(path)")
                }
            }
        }
        return worst
    }

    @Test func aStreamingDiagramOnlyGrows() {
        for src in [Self.retries, Self.deploy, Self.connection] {
            let built = stream(src)
            let sizes = built.map { $0.size }
            if sizes.count >= 2 {
                for i in 0..<(sizes.count - 1) {
                    #expect(sizes[i + 1][0] >= sizes[i][0] - 0.01 && sizes[i + 1][1] >= sizes[i][1] - 0.01, "it never shrinks: \(sizes)")
                }
            }
            let (back, which) = worstReversal(built)
            #expect(back <= 1.0, "no node doubles back more than a point: \(back) at \(which)")
        }
    }

    @Test func aFinishedStreamLaysOutAsIfItNeverStreamed() {
        let paint = DiagramStyle.neutral(true)
        let before = buildScene(Self.retries, paint, nil)!
        let streamed = stream(Self.retries)
        let after = buildScene(Self.retries, paint, nil)!
        #expect(centres(before) == centres(after))
        #expect(before.size == after.size)
        #expect(!streamed.isEmpty)
    }

    @Test func aGrowingBuildIsTheSameHoweverManyLinesArrivedAtOnce() {
        let paint = DiagramStyle.neutral(true)
        let byLine = stream(Self.retries).last!
        scenes.resetCache()
        let atOnce = scenes.growing(Self.retries, paint, nil)!
        #expect(centres(byLine) == centres(atOnce))
        #expect(byLine.size == atOnce.size)
    }

    @Test func nodesKeepTheirPlacesByNameWhenOneBeforeThemBecomesASubgraph() {
        let built = stream("graph TD\n  X -->|in| S\n  S --> W\n  W -->|out| Y\n  subgraph S\n    D\n  end\n")
        let (back, which) = worstReversal(built)
        #expect(back <= 1.0, "no node doubles back more than a point: \(back) at \(which)")
    }
}
