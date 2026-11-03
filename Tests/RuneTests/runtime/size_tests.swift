// Tests ported from: crates/rune/src/runtime/size_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Taffy
import Testing
@testable import Rune

@Suite("RuntimeSizeTests")
struct RuntimeSizeTests {
    @Test("Elements and retained Nodes stay compact via cold-path boxing")
    func elementsAndNodesStaySmall() {
        let elSize = MemoryLayout<El>.size
        let nodeSize = MemoryLayout<Node>.size
        let visualSize = MemoryLayout<Visual>.size
        let styleSize = MemoryLayout<Taffy.Style<String>>.size
        #expect(visualSize < 256)
        #expect(styleSize < 1024)
        #expect(elSize <= 1280)
        #expect(nodeSize <= 2048)
    }
}
