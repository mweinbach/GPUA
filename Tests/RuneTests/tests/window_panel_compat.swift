// Tests ported from: crates/rune/tests/window_panel_compat.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowPanelCompatIntegrationTests")
struct WindowPanelCompatIntegrationTests {
    @Test func windowPanelBuildersPreserveExhaustiveLiteralsAndDefaultInference() {
        func view(_: Void, _: Cx<Void>) -> El { el() }

        let spec = AppSpec<Void>(
            title: "compat",
            size: (300.0, 100.0),
            minSize: nil,
            init: { () },
            view: view,
            scenes: [("scene", { _ in })],
            fonts: [],
            families: ("Inter", "Inter"),
            setup: nil,
            poll: { _, _, _ in false },
            onKey: { _, _, _ in false }
        )
        let options = WindowOptions(
            transparent: true,
            borderless: true,
            clickThrough: false,
            alwaysOnTop: false,
            visible: false,
            position: nil,
            physicalSize: nil,
            minSize: nil,
            maxSize: nil,
            resizable: false
        )
        let app = App.new(spec)
            .onFocus { _, _, _ in }
            .macosWindow(MacWindowOptions().nonactivatingPanel(true))
        let handle = app.handle()

        let window = WindowSpec(key: "quick", app: app, options: options, onCreated: nil)
            .onFocus { _, _, _ in }
            .options(WindowOptions())
        _ = window.configuredOptions(
            WindowOptions().macos(
                MacWindowOptions()
                    .nonactivatingPanel(true)
                    .cornerRadius(16.0)
                    .cornerCurveCircular()
            )
        )
        handle.place(.Primary, .FullScreen)

        let overlay = OverlaySpec<Void>(
            name: "compat",
            size: (50.0, 50.0),
            edge: .Top,
            margin: 0.0,
            align: .center,
            inset: 0.0,
            interactive: true,
            view: view
        )
        _ = overlay.options(OverlayOptions()).onFocus { _, _, _ in }

        _ = WindowSpec.new("launcher", AppSpec.new("launcher", (300.0, 100.0), { () }, view))
            .configuredOptions(WindowOptions.launcherPanel())
            .onReady { w in #expect(w.isReady()) }

        _ = App.new(AppSpec.new("launcher", (300.0, 100.0), { () }, view))
            .configuredOptions(WindowOptions.launcherPanel())
            .onReady { _ in }
            .windowOptions(WindowOptions())
    }
}
