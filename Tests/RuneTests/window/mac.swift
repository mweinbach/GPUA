// Tests ported from: crates/rune/src/window/mac.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("WindowMacHelpersTests")
struct WindowMacHelpersTests {
    @Test("macSystemTitlebarAction maps AppleActionOnDoubleClick preference")
    func macSystemTitlebarActionMapsAppleActionOnDoubleClickPreference() {
        #expect(macSystemTitlebarAction("Minimize") == .minimize)
        #expect(macSystemTitlebarAction("None") == .none)
        #expect(macSystemTitlebarAction("Maximize") == .zoom)
        #expect(macSystemTitlebarAction(nil) == .zoom)
    }

    @Test("macTitlebarInset and macNativeTitlebarBand respect borderless and fullscreen")
    func macTitlebarInsetAndBandRespectBorderlessAndFullscreen() {
        let chrome = Chrome.DEFAULT
        #expect(macTitlebarInset(chrome: chrome, borderless: false, fullscreen: false) == 67.0)
        #expect(macTitlebarInset(chrome: chrome, borderless: true, fullscreen: false) == 0.0)
        #expect(macTitlebarInset(chrome: chrome, borderless: false, fullscreen: true) == 0.0)

        #expect(macNativeTitlebarBand(chrome: chrome, borderless: false, fullscreen: false) > 0.0)
        #expect(macNativeTitlebarBand(chrome: chrome, borderless: true, fullscreen: false) == 0.0)
        #expect(macNativeTitlebarBand(chrome: chrome, borderless: false, fullscreen: true) == 0.0)
    }
}
