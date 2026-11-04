// Tests ported from: crates/rune-mermaid/src/layered_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMermaid

@Suite struct LayeredTests {
    private static let sp = Spacing(node: 30.0, rank: 40.0, cluster: 10.0)

    private func makeGraph(_ n: Int, _ edges: [(Int, Int)]) -> Graph {
        Graph(
            sizes: Array(repeating: [60.0, 30.0], count: n),
            edges: edges.map { GEdge(from: $0.0, to: $0.1, label: nil, minlen: 1) },
            nodeCluster: Array(repeating: nil, count: n),
            clusters: [],
            ids: []
        )
    }

    @Test func aChainGoesDownInAStraightLine() {
        let p = layered.layout(makeGraph(3, [(0, 1), (1, 2)]), Self.sp)!
        #expect(p.centers[0][1] < p.centers[1][1] && p.centers[1][1] < p.centers[2][1])
        #expect(abs(p.centers[0][0] - p.centers[2][0]) < 0.5)
        #expect(p.centers[1][1] - p.centers[0][1] == 30.0 + 40.0)
    }

    @Test func aForkSpreadsChildrenWithoutOverlapAndCentresTheParent() {
        let p = layered.layout(makeGraph(3, [(0, 1), (0, 2)]), Self.sp)!
        let a = p.centers[1]
        let b = p.centers[2]
        #expect(a[1] == b[1])
        #expect(abs(a[0] - b[0]) >= 90.0 - 0.01)
        #expect(abs(p.centers[0][0] - (a[0] + b[0]) / 2.0) < 1.0)
    }

    @Test func cyclesAndSelfLoopsLayOut() {
        let p = layered.layout(makeGraph(3, [(0, 1), (1, 2), (2, 0), (1, 1)]), Self.sp)!
        #expect(p.paths.count == 4)
        let back = p.paths[2]
        #expect(back.first == p.centers[2])
        #expect(back.last == p.centers[0])
        #expect(p.centers.allSatisfy { $0[0].isFinite && $0[1].isFinite })
    }

    @Test func siblingClustersNeverOverlapAcrossLayers() {
        var g = makeGraph(7, [(0, 1), (2, 3), (2, 4), (0, 2), (3, 5), (4, 5), (4, 6)])
        g.clusters = [
            GCluster(parent: nil, lead: [0.0, 16.0], minSpan: [0.0, 0.0]),
            GCluster(parent: nil, lead: [0.0, 16.0], minSpan: [0.0, 0.0]),
        ]
        g.nodeCluster = [0, 0, 1, 1, 1, nil, nil]
        let p = layered.layout(g, Self.sp)!
        let a = p.clusters[0]
        let b = p.clusters[1]
        let apart = a[2] <= b[0] || b[2] <= a[0] || a[3] <= b[1] || b[3] <= a[1]
        #expect(apart)
        for v in [5, 6] {
            let c = p.centers[v]
            for bx in [a, b] {
                let inside = c[0] > bx[0] && c[0] < bx[2] && c[1] > bx[1] && c[1] < bx[3]
                #expect(!inside)
            }
        }
    }

    @Test func isotonicKeepsSeparationAndHitsFreeTargets() {
        #expect(layered.isotonic([0.0, 100.0], [1.0, 1.0], [10.0]) == [0.0, 100.0])
        #expect(layered.isotonic([50.0, 50.0], [1.0, 1.0], [20.0]) == [40.0, 60.0])
    }

    @Test func clustersStayContiguousAndContainTheirMembers() {
        var g = makeGraph(4, [(0, 1), (0, 2), (0, 3)])
        g.clusters.append(GCluster(parent: nil, lead: [0.0, 16.0], minSpan: [0.0, 0.0]))
        g.nodeCluster[1] = 0
        g.nodeCluster[3] = 0
        let p = layered.layout(g, Self.sp)!
        let b = p.clusters[0]
        for v in [1, 3] {
            let c = p.centers[v]
            #expect(c[0] - 30.0 >= b[0] && c[0] + 30.0 <= b[2] && c[1] - 15.0 >= b[1] + 16.0)
        }
        let c2 = p.centers[2]
        #expect(c2[0] + 30.0 <= b[0] || c2[0] - 30.0 >= b[2])
    }
}
