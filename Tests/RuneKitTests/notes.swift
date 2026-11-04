// Tests ported from: crates/rune-kit/src/notes.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Upstream `crates/rune-kit/src/notes.rs` declares `#[cfg(test)] #[path = "notes_tests.rs"] mod tests;`,
// whose tests live in `Tests/RuneKitTests/notes_tests.swift`.

import Testing
@testable import RuneKit

@Suite("NotesModuleSmokeTests")
struct NotesModuleSmokeTests {
    @Test func emptyNoteCutsToEmptyPieces() {
        #expect(cut("   \n  ").isEmpty)
    }
}
