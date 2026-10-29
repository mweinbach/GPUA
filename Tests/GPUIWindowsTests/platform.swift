// Tests ported from: crates/gpui_windows/src/platform.rs (#[cfg(test)] items)
// Upstream commit: 650aab59d54f
// Port status: ported

#if os(Windows)
import Foundation
import Testing
import GPUI
@testable import GPUIWindows

@Suite("WindowsPlatformTests")
struct WindowsPlatformTests {
    @Test
    func testClipboard() {
        let platform = WindowsPlatform(headless: true)

        let item1 = ClipboardItem(text: "你好，我是张小白")
        platform.writeToClipboard(item1)
        #expect(platform.readFromClipboard() == item1)

        let item2 = ClipboardItem(text: "12345")
        platform.writeToClipboard(item2)
        #expect(platform.readFromClipboard() == item2)

        let item3 = ClipboardItem(text: "abcdef")
        platform.writeToClipboard(item3)
        #expect(platform.readFromClipboard() == item3)
    }

    @Test
    func testPlatformInitializationAndProperties() {
        let platform = WindowsPlatform(headless: true)
        #expect(platform.headless == true)
        #expect(platform.buttonLayout() == WindowButtonLayout(left: false))
        #expect(platform.thermalState() == .nominal)
        #expect(platform.canSelectMixedFilesAndDirs() == false)
        _ = platform.shouldAutoHideScrollbars()
        #expect(platform.displays().count >= 1)
        #expect(platform.primaryDisplay() != nil)
    }
}

#endif
