// Tests ported from: crates/rune/src/recorder/mod.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("RecorderCoreTests")
struct RecorderCoreTests {
    @Test func levelsPackIntoOneWord() {
        for level in [Level.SILENT, Level.new(-6.0, -9.0), Level.new(0.0, -160.0)] {
            #expect(unpackRecorderLevel(packRecorderLevel(level)) == level)
        }
    }
}
