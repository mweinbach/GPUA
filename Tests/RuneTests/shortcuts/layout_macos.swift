// Tests ported from: crates/rune/src/shortcuts/layout_macos.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import Testing
@testable import Rune

@Suite
struct ShortcutLayoutMacOSTests {
    @Test
    func forcedLayoutOverridesThreadLocalTranslation() {
        defer { forceMacKeyboardLayout(nil) }
        forceMacKeyboardLayout { key, _ in
            key == 40 ? "x" : nil
        }
        let s = Shortcut("cmd+k")!
        #expect(s.keycaps() == ["⌘", "X"])
        #expect(s.menuKeycaps() == ["⌘", "K"])
    }
}
#endif
