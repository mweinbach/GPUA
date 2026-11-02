// Tests ported from: crates/rune-motion/src/snap.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import RuneMotion

@Test func stationary_bottom_edge_never_moves() {
    // Top edge animates continuously; bottom stays at 200.3. Two-edge snapping keeps the bottom
    // exactly fixed, where snapping (y, h) separately would wobble it.
    let bottom: Float = 200.3
    let fixed = snap.grid(bottom, 2.0)
    var separate = Set<UInt32>()
    for i in 0..<1000 {
        let top: Float = 10.0 + Float(i) * 0.0137
        let r = snap.snapRect(Rect.fromEdges(0.0, top, 10.0, bottom), 2.0)
        #expect(r.y + r.h == fixed)
        let y = snap.grid(top, 2.0)
        let h = snap.grid(bottom - top, 2.0)
        separate.insert((y + h).bitPattern)
    }
    #expect(separate.count > 1, "the naive way should wobble, proving the test bites")
}
