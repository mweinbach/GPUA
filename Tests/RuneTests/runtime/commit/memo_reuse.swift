// Tests ported from: crates/rune/src/runtime/commit/memo_reuse.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("CommitMemoReuseUnitTests")
struct CommitMemoReuseUnitTests {
    @Test("expandMemoSubtree expands cached MemoShared children and reports reuse")
    func expandMemoSubtreeExpandsChildren() {
        var plain = col().key("plain").child(el().key("a").size(10.0, 10.0))
        #expect(!expandMemoSubtree(&plain))
        #expect(plain.children.count == 1)

        var memoEl = col().key("memo")
        memoEl.memoChildren = MemoShared(children: [
            el().key("c0").size(20.0, 10.0),
            el().key("c1").size(20.0, 10.0),
        ])
        #expect(expandMemoSubtree(&memoEl))
        #expect(memoEl.children.count == 2)
        #expect(memoEl.memoChildren == nil)
    }
}
