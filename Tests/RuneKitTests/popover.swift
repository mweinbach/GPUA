// Tests ported from: crates/rune-kit/src/popover.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `popover.rs` declares `#[cfg(test)] #[path = "popover_tests.rs"] mod tests;`,
// whose unit tests live in `Tests/RuneKitTests/popover_tests.swift`. This file additionally verifies
// the `popover::anchor_rect` doc-test from `popover.rs`.

import Testing
@testable import RuneKit

@Suite("PopoverDocTests")
struct PopoverDocTests {
    @Test("anchor_rect doc example flips above near the bottom edge")
    func anchorRectDocExample() {
        let r = popover.anchorRect([20.0, 250.0, 60.0, 270.0], (100.0, 80.0), .bottomStart, 4.0, (400.0, 300.0))
        #expect(r == [20.0, 166.0, 120.0, 246.0])
    }
}
