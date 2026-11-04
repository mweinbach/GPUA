// Tests ported from: crates/rune-mermaid/src/git_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneMermaid

@Suite struct GitTests {
    private struct CommitShape: Equatable {
        var id: String?
        var kind: git.Kind
        var branch: Int
        var parents: [Int]
        init(_ id: String?, _ kind: git.Kind, _ branch: Int, _ parents: [Int]) {
            self.id = id
            self.kind = kind
            self.branch = branch
            self.parents = parents
        }
    }

    private func parseGit(_ src: String) -> git.GitGraph {
        guard let parsed = RuneMermaid.parse(src), case .git(let g) = parsed.diagram else {
            fatalError("not a git graph: \(src)")
        }
        return g
    }

    @Test func branchesMergesAndCherryPicks() {
        let g = parseGit(
            "gitGraph\n    commit id: \"Alpha\"\n    commit tag: \"v1.0\" type: HIGHLIGHT\n    branch develop order: 2\n    checkout develop\n    commit id:\"Beta\" type: REVERSE\n    commit\n    switch main\n    merge develop id: \"M\" tag: \"v2\"\n    branch \"feature/x\"\n    commit id: \"F\"\n    cherry-pick id: \"Beta\"\n    checkout nowhere\n    merge main\n    merge feature/x\n    bogus line"
        )
        #expect(g.flow == .right)
        #expect(g.branches.map { $0.name } == ["main", "develop", "feature/x"])
        #expect(g.branches[1].order == 2.0)
        #expect(g.commits.map { CommitShape($0.id, $0.kind, $0.branch, $0.parents) } == [
            CommitShape("Alpha", .normal, 0, []),
            CommitShape(nil, .highlight, 0, [0]),
            CommitShape("Beta", .reverse, 1, [1]),
            CommitShape(nil, .normal, 1, [2]),
            CommitShape("M", .merge, 0, [1, 3]),
            CommitShape("F", .normal, 2, [4]),
            CommitShape(nil, .cherryPick, 2, [5]),
        ])
        #expect(g.commits[1].tag == "v1.0")
        #expect(g.commits[4].tag == "v2")
        #expect(g.commits[6].picked == 2)
    }

    @Test func flowsAndBounds() {
        #expect(parseGit("gitGraph TB:\ncommit").flow == .down)
        #expect(parseGit("gitGraph BT:\ncommit").flow == .up)
        #expect(RuneMermaid.parse("gitGraph\nbranch x") == nil)
        let budget = "gitGraph\n\(String(repeating: "commit\n", count: MAX_ITEMS + 1))"
        #expect(RuneMermaid.parse(budget) == nil)
    }

    @Test func drawsLanesIdsAndTags() {
        for src in [
            "gitGraph\ncommit id: \"A\" tag: \"v1\"\nbranch dev\ncommit id: \"B\"\ncheckout main\nmerge dev",
            "gitGraph TB:\ncommit id: \"A\"\nbranch dev\ncommit id: \"B\" tag: \"t\"",
        ] {
            let s = buildScene(src, DiagramStyle.neutral(false), nil)!
            let texts = s.labels.map { $0.text }
            for t in ["main", "dev", "A", "B"] {
                #expect(texts.contains(t))
            }
        }
    }
}
