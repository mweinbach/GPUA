// Tests ported from: crates/rune/src/platform/macos/presence.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Upstream `presence.rs` delegates its `#[cfg(test)] mod tests;` to `presence_tests.rs`.
// Behavioral tests live in `Tests/RuneTests/platform/macos/presence_tests.swift`.
