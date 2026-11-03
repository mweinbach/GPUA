// Tests ported from: crates/rune/tests/app_spec_compat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

// Exactly the public field set at 32a1715. Deliberately exhaustive: adding a required field
// must fail compilation here rather than first in a downstream Hex or Rooms checkout.
private func legacySpec() -> AppSpec<Void> {
    AppSpec<Void>(
        title: "Legacy consumer",
        size: (640.0, 480.0),
        minSize: nil,
        init: { () },
        view: { _, _ in el() },
        scenes: [],
        fonts: [],
        families: ("Inter", "Inter"),
        setup: nil,
        poll: nil,
        onKey: nil
    )
}

@Suite("AppSpecCompatIntegrationTests")
struct AppSpecCompatIntegrationTests {
    @Test func legacyExhaustiveLiteralAndChromeBuildersCompile() {
        let app = App.new(legacySpec()).chrome(Chrome.DEFAULT)
        let win = WindowSpec.new("legacy", legacySpec()).chrome(Chrome.DEFAULT)
        #expect(app.spec.title == "Legacy consumer")
        #expect(win.id == "legacy")
    }
}
