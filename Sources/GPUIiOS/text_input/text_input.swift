// Ported from: crates/gpui_ios/src/text_input/mod.rs
// Upstream commit: 650aab59d54f
// Port status: ported

import Foundation

// MARK: - iOS Text Input Module Overview

// PORT NOTE: Mirrors `crates/gpui_ios/src/text_input/mod.rs`, which groups `backed_view`,
// `events` (`text_input_events.swift`), `session`, and `traits` into a cohesive subsystem.
// Because Swift shares module scope across target files, types from those sibling files are
// directly visible throughout `GPUIiOS`.
enum IosTextInputModule {}
