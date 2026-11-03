// Tests ported from: crates/rune/src/tray.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("TrayTests")
struct TrayTests {
    @Test func enabledLeavesSeparatorsAlone() {
        #expect(TrayItem.separator.enabled(false) == .separator)
        #expect(
            TrayItem.action("q", "Quit").enabled(false)
                == .action(id: "q", label: "Quit", enabled: false)
        )
    }

    @Test func aShortIconIsRefused() {
        let spec = TraySpec.new("t", "T", TrayIcon.rgba(2, 2, [0, 0, 0]))
        if case .failure(.backend) = Tray.new(spec, { _ in }) {
            // expected
        } else {
            Issue.record("Expected TrayError.backend for short icon")
        }
    }
}
