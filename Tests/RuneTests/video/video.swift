// Tests ported from: crates/rune/src/video/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("Video Signature Fold Tests")
struct VideoModuleTests {
    @Test("videoFold is order-free and distinguishes generation and surface key")
    func videoFoldOrderFreeAndDistinct() {
        let base: UInt64 = 0x1234_5678_9abc_def0
        let aFirst = videoFold(videoFold(base, 1, 100), 2, 200)
        let bFirst = videoFold(videoFold(base, 2, 200), 1, 100)
        #expect(aFirst == bFirst)
        #expect(videoFold(base, 1, 100) != videoFold(base, 2, 100))
        #expect(videoFold(base, 1, 100) != videoFold(base, 1, 101))
    }
}
