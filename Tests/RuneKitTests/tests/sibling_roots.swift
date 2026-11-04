// Tests ported from: crates/rune-kit/tests/sibling_roots.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
@testable import RuneKit

private struct SiblingPage {}

private func siblingCards(_: SiblingPage, _: Cx<SiblingPage>) -> El {
    let k = Kit.neutral(true)
    return col()
        .wFull()
        .child(Card.new().title("One", nil).description("a").build(k))
        .child(Card.new().title("Two", nil).description("b").build(k))
}

private func siblingBlocks(_: SiblingPage, _: Cx<SiblingPage>) -> El {
    let style = MarkdownStyle.neutral(true)
    return col()
        .wFull()
        .child(Markdown.new("# One\n\nbody").render(style))
        .child(Markdown.new("# Two\n\nbody").render(style))
}

private func repaired(_ view: @escaping (SiblingPage, Cx<SiblingPage>) -> El) -> [String] {
    let rt = Runtime.new(SiblingPage(), view, (600.0, 600.0), Env.new(true, 2.0))
    _ = rt.frame(0.0)
    let all = rt.elements()
    let uniquePaths = Set(all.map(\.path))
    #expect(uniquePaths.count == all.count, "element paths are unique")
    return all.compactMap(\.key).filter { $0.contains("#dup") }
}

@Suite("SiblingRootsTests")
struct SiblingRootsTests {
    @Test func siblingCardsHaveNoDuplicateKeys() {
        #expect(repaired(siblingCards).isEmpty)
    }

    @Test func siblingMarkdownBlocksHaveNoDuplicateKeys() {
        #expect(repaired(siblingBlocks).isEmpty)
    }
}
