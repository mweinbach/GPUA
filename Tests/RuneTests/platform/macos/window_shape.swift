// Tests ported from: crates/rune/src/platform/macos/window_shape.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Upstream `window_shape.rs` delegates its `#[cfg(test)] mod tests;` to `window_shape_tests.rs`.
// Behavioral tests live in `Tests/RuneTests/platform/macos/window_shape_tests.swift`.
