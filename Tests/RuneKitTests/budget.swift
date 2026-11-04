// Tests ported from: crates/rune-kit/src/budget.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

@Test func whatTheLastTwoCommitsUsedOutlivesTheBudget() {
    let rt = Runtime.new((), { _, _ in Rune.el() }, (10.0, 10.0), Env())
    func commit() {
        rt.invalidate()
        _ = rt.frame(0.01)
    }
    commit()
    var b = Budget<String, Void>.new(100)
    for k in ["a", "b", "c"] {
        b.insert(k, (), 60)
    }
    #expect(b.map.count == 3, "all three are on screen")
    commit()
    #expect(b.get("c") != nil)
    commit()
    b.insert("d", (), 60)
    // a and b are two commits old; c was used last commit.
    let left1 = b.map.keys.sorted()
    #expect(left1 == ["c", "d"])
    #expect(b.bytes() == 120)
    commit()
    commit()
    b.insert("e", (), 10)
    let left2 = b.map.keys.sorted()
    #expect(left2 == ["d", "e"], "the least recently used go until under three quarters")
    #expect(b.bytes() == 70)
}
