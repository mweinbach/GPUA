// Tests ported from: crates/rune-kit/src/tree/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

private func makeSampleModel() -> TreeModel<String> {
    var m = TreeModel<String>.new()
    m.insert(nil, "a", "alpha")
    m.insert("a", "a/1", "one")
    m.insert("a", "a/2", "two")
    m.insert(nil, "b", "beta")
    m.insert(nil, "c", "bravo")
    return m
}

@Suite struct TreeUnitTests {
    @Test func typingJumpsByPrefixAndARepeatedLetterCycles() {
        var m = makeSampleModel()
        let label: (String) -> String = { $0 }

        let r = m.typeSelect("b", true, label)
        #expect(r == 1, "beta: rows are alpha, beta, bravo")
        m.select("b")
        #expect(m.typeSelect("b", false, label) == 2, "b again cycles to bravo")
        m.select("c")
        #expect(m.typeSelect("r", false, label) == nil, "\"bbr\" is no name")
        #expect(m.typeSelect("b", true, label) == 1, "after a pause, a new prefix from the next row")
        m.select("a")
        #expect(m.typeSelect("b", true, label) == 1)
        #expect(m.typeSelect("r", false, label) == 2, "\"br\" keeps looking past beta to bravo")
    }

    @Test func naturalOrderCountsDigitsAndIgnoresCase() {
        var v = ["file10", "File2", "file1", "a", "B"]
        v.sort { a, b in naturalCmp(a, b) == .less }
        #expect(v == ["a", "B", "file1", "File2", "file10"])
    }
}
