// Tests ported from: crates/rune/src/window.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowHostRootTests")
struct WindowHostRootTests {
    @Test("Host initializes runtime and mounts pending overlays on start")
    func hostInitializesRuntimeAndMountsPendingOverlaysOnStart() {
        let spec = AppSpec<Int>("main", (400.0, 300.0), { 42 }, { _, _ in el().size(400.0, 300.0) })
        let app = App.new(spec)
        let ovSpec = OverlaySpec<Int>(name: "hud", size: (120.0, 40.0), view: { _, _ in el() })
        let ovHandle = app.overlay(ovSpec, 7)

        let host = app.buildHost()
        #expect(host.rt.state == 42)
        #expect(host.pendingOverlays.count == 1)

        let loop = startAll([host])
        #expect(host.overlays.count == 1)
        #expect(host.win != nil)
        #expect(!ovHandle.isVisible())
        loop.shutdown()
    }
}
