// Tests ported from: crates/rune/src/shortcuts/x11.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ShortcutX11Tests {
    @Test
    func badAccessIsAConflict() {
        #expect(x11ShortcutReplyError(errorCode: 10) == .conflict)
        #expect(x11ShortcutReplyError(errorCode: 2, message: "BadValue") == .backend("BadValue"))
    }
}
