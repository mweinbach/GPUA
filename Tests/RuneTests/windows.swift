// Tests ported from: crates/rune/src/windows.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowsTests")
struct WindowsTests {
    @Test("launcher panel preset configures hidden borderless transparent window")
    func launcherPanelPresetConfiguresHiddenBorderlessTransparentWindow() {
        let preset = WindowOptions.launcherPanel()
        #expect(!preset.options.visible && preset.options.borderless && preset.options.transparent)
        #expect(!MacWindowOptions().nonactivatingPanel(true).launcher)
        #expect(!preset.native.nonactivatingPanel(false).launcher)
        #expect(WindowOptions().visible)

        let spec = AppSpec<Void>("launcher", (300.0, 100.0), { () }, { _, _ in el() })
        let app = App.new(spec).configuredOptions(WindowOptions.launcherPanel())
        #expect(app.macWinOptions.launcher)
        #expect(!app.winOptions.visible)
        let window = WindowSpec.fromApp("launcher", app)
        #expect(!window.optionsVal.visible && window.optionsVal.transparent)
    }

    @Test("amending a preset keeps its launcher behaviour")
    func amendingAPresetKeepsItsLauncherBehaviour() {
        let preset = WindowOptions.launcherPanel().macos { native in
            native.cornerRadius(16.0).shadow(true)
        }
        #expect(preset.native.launcher && preset.native.nonactivatingPanelFlag)
        #expect(preset.native.cornerRadiusValue == 16.0 && preset.native.shadowFlag == true)
        #expect(!preset.options.visible && preset.options.transparent)

        let spec = AppSpec<Void>("launcher", (300.0, 100.0), { () }, { _, _ in el() })
        let app = App.new(spec).configuredOptions(preset)
        #expect(app.macWinOptions.launcher)
        #expect(app.macWinOptions.cornerRadiusValue == 16.0)
    }

    @Test("app windows follow their app and share its key space")
    func appWindowsFollowTheirAppAndShareItsKeySpace() throws {
        let main = App.new(AppSpec<UInt32>("main", (100.0, 100.0), { 0 }, { _, _ in el() }))
        func settings() -> WindowSpec<String> {
            WindowSpec.new("settings", AppSpec("settings", (100.0, 100.0), { "" }, { _, _ in el() }))
        }
        let (_, handle) = main.window(settings())
        #expect(handle.key() == "settings")

        let other = WindowSpec.new("other", AppSpec<Void>("other", (100.0, 100.0), { () }, { _, _ in el() }))
        let flat = flattenWindowSpecs([WindowSpec.fromApp("main", main).boxed(), other.intoAny()])
        #expect(flat.map { $0.key() } == ["main", "settings", "other"])
        try validateWindowSpecs(flat)

        let clash = App.new(AppSpec<UInt32>("main", (100.0, 100.0), { 0 }, { _, _ in el() }))
        _ = clash.window(settings())
        #expect(throws: WindowValidationError.duplicateId("settings")) {
            try validateWindowSpecs(flattenWindowSpecs([WindowSpec.fromApp("settings", clash).boxed()]))
        }
    }

    @Test("default window options remain inferable at existing call sites")
    func defaultWindowOptionsRemainInferableAtExistingCallSites() {
        let configure: (WindowSpec<Void>) -> WindowSpec<Void> = { spec in
            spec.options(WindowOptions())
        }
        let s = configure(WindowSpec.new("main", AppSpec("main", (100.0, 100.0), { () }, { _, _ in el() })))
        #expect(s.optionsVal.visible)
    }

    @Test("compact window overrides the legacy minimum without changing defaults")
    func compactWindowOverridesTheLegacyMinimumWithoutChangingDefaults() {
        let defaults = WindowOptions().sizeLimits(nil)
        #expect(defaults.0 == (420.0, 400.0))
        #expect(defaults.1 == nil)

        var compactOpts = WindowOptions()
        compactOpts.minSize = (280.0, 80.0)
        compactOpts.maxSize = (320.0, 120.0)
        compactOpts.resizable = false
        compactOpts.borderless = true
        let limits = compactOpts.sizeLimits((860.0, 560.0))
        #expect(limits.0 == (280.0, 80.0))
        #expect(limits.1?.0 == 320.0 && limits.1?.1 == 120.0)
    }

    @Test("maximum alone caps the inherited minimum per axis")
    func maximumAloneCapsTheInheritedMinimumPerAxis() {
        var options = WindowOptions()
        options.maxSize = (320.0, 120.0)
        let cases: [((Float, Float)?, (Float, Float))] = [
            (nil, (320.0, 120.0)),
            ((860.0, 80.0), (320.0, 80.0)),
        ]
        for (appMin, expected) in cases {
            let limits = options.sizeLimits(appMin)
            #expect(limits.0 == expected)
            #expect(limits.1?.0 == 320.0 && limits.1?.1 == 120.0)
        }
    }

    @Test("default options inherit the app minimum")
    func defaultOptionsInheritTheAppMinimum() {
        let limits = WindowOptions().sizeLimits((860.0, 560.0))
        #expect(limits.0 == (860.0, 560.0))
    }

    @Test("a window that fits its content has no default minimum height")
    func aWindowThatFitsItsContentHasNoDefaultMinimumHeight() {
        let fit = WindowOptions().fitMinSize(nil)
        let limits = WindowOptions().sizeLimits(fit)
        #expect(limits.0 == (420.0, 0.0) && limits.1 == nil)
        let fitExplicit = WindowOptions().fitMinSize((300.0, 200.0))
        #expect(fitExplicit?.0 == 300.0 && fitExplicit?.1 == 200.0)

        var custom = WindowOptions()
        custom.minSize = (300.0, 500.0)
        let customLimits = custom.sizeLimits(custom.fitMinSize(nil))
        #expect(customLimits.0 == (300.0, 500.0) && customLimits.1 == nil)
    }
}
