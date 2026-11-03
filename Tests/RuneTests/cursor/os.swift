// Tests ported from: crates/rune/src/cursor/os.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("OsCursorTests")
struct OsCursorTests {
    @Test("a host sets its cursor while active and the arrow once when it stops")
    func hostSetsCursorWhileActiveAndArrowOnceWhenStopped() {
        var applied: (Bool, Cursor) = (false, .default)
        #expect(nextOsCursor(&applied, .crosshair, false) == nil)
        #expect(nextOsCursor(&applied, .crosshair, true) == .crosshair)
        #expect(nextOsCursor(&applied, .hidden, true) == .hidden)
        #expect(nextOsCursor(&applied, .hidden, true) == nil)
        #expect(nextOsCursor(&applied, .hidden, false) == .default)
        #expect(nextOsCursor(&applied, .hidden, false) == nil)
        #expect(nextOsCursor(&applied, .pointer, false) == nil)
        #expect(nextOsCursor(&applied, .default, true) == .default)
        #expect(nextOsCursor(&applied, .default, true) == nil)
    }

    @Test("only an image holding the pointer is set again")
    func onlyImageHoldingPointerIsSetAgain() {
        let png: [UInt8] = [1, 2, 3, 4]
        let image = Cursor.Image(CursorImage.png(png, [0.0, 0.0]))
        var applied: (Bool, Cursor) = (false, .default)
        _ = nextOsCursor(&applied, image, true)
        #expect(holdsImageCursor(applied))
        _ = nextOsCursor(&applied, image, false)
        #expect(!holdsImageCursor(applied))
        _ = nextOsCursor(&applied, .crosshair, true)
        #expect(!holdsImageCursor(applied))
    }
}
