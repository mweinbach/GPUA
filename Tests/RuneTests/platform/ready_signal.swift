// Tests ported from: crates/rune/src/platform/ready_signal.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Upstream `ready_signal.rs` delegates its `#[cfg(test)] mod tests;` to `ready_signal_tests.rs`.
// Behavioral tests live in `Tests/RuneTests/platform/ready_signal_tests.swift`.
