// Tests ported from: crates/rune-kit/src/shell/reorder.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneKit

@Suite
struct ShellReorderTests {
    @Test
    func rowsBetweenThePlaceAndTheTargetStepAside() {
        var r = Reorder.new().gap(4.0)
        r.follow(1, 5, 3.0, 45.0)
        #expect(r.dragging() == nil, "inside the slop it's still a press")
        r.follow(1, 5, 100.0, 45.0)
        #expect(r.dragging() == 1 && r.target() == 3)
        let shifts = (0..<5).map { i in r.shift(i) }
        #expect(shifts == [0.0, 100.0, -49.0, -49.0, 0.0])
        r.follow(1, 5, -500.0, 45.0)
        #expect(r.target() == 0, "clamped to the list")
        #expect(r.shift(0) == 49.0)
        let ended = r.end(false)
        #expect(ended?.0 == 1 && ended?.1 == 0)
        #expect(r.shift(0) == 0.0)
        r.follow(2, 5, 60.0, 45.0)
        #expect(r.end(true) == nil, "a cancel moves nothing")
    }
}
