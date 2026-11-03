// Tests ported from: crates/rune/src/shortcuts/wayland.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite
struct ShortcutWaylandTests {
    @Test
    func portalCancellationIsNotAConflict() {
        #expect(voidErr(waylandShortcutResponseStatus(1)) == .permissionDenied)
        if case .failure(.backend) = waylandShortcutResponseStatus(2) {
            // expected
        } else {
            Issue.record("Expected backend error for status 2")
        }
    }

    @Test
    func missingPortalIsUnsupported() {
        #expect(waylandShortcutMapDbusError(.fdoServiceUnknown("portal")) == .unsupported)
        #expect(waylandShortcutMapDbusError(.fdoUnknownMethod("BindShortcuts")) == .unsupported)
        if case .backend = waylandShortcutMapDbusError(.fdoFailed("x")) {
            // expected
        } else {
            Issue.record("Expected backend error for fdoFailed")
        }
    }
}
