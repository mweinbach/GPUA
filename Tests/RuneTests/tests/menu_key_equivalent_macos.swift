// Tests ported from: crates/rune/tests/menu_key_equivalent_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if os(macOS)
import AppKit
import CoreGraphics
#endif
import Testing
@testable import Rune

#if os(macOS)
@MainActor
private final class MenuKeyEquivalentHitTarget: NSObject {
    var hits: [String] = []

    @objc func hit(_ sender: NSMenuItem) {
        hits.append(sender.title)
    }
}
#endif

@Suite("MenuKeyEquivalentMacosIntegrationTests", .serialized)
struct MenuKeyEquivalentMacosIntegrationTests {
    #if os(macOS)
    @Test @MainActor
    func keyEquivalentsHoldAcceleratorsCharactersAndFireOnCurrentLayout() async {
        let app = NSApplication.shared
        let target = MenuKeyEquivalentHitTarget()

        let makeEvent = { (code: UInt16, flags: UInt) -> NSEvent? in
            guard let cg = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true) else {
                return nil
            }
            cg.flags = CGEventFlags(rawValue: UInt64(flags))
            return NSEvent(cgEvent: cg)
        }

        let codeTyping = { (c: String) -> UInt16? in
            for code in UInt16(0)..<128 {
                if let ev = makeEvent(code, MENU_COMMAND),
                   ev.charactersIgnoringModifiers == c
                {
                    return code
                }
            }
            return nil
        }

        let cases: [(String, String, UInt)] = [
            ("cmd+b", "b", MENU_COMMAND),
            ("cmd+=", "=", MENU_COMMAND),
            ("ctrl+cmd+f", "f", MENU_CONTROL | MENU_COMMAND),
            ("cmd+shift+z", "z", MENU_SHIFT | MENU_COMMAND),
            ("alt+cmd+k", "k", MENU_OPTION | MENU_COMMAND),
            ("cmd+left", "\u{f702}", MENU_COMMAND),
            ("f5", "\u{f708}", 0),
            ("cmd+backspace", "\u{08}", MENU_COMMAND),
        ]

        let root = NSMenu()
        let viewMenu = NSMenu(title: "View")
        let top = NSMenuItem()
        top.title = "View"
        top.submenu = viewMenu
        root.addItem(top)

        var items: [NSMenuItem] = []
        for (accelerator, _, _) in cases {
            let item = NSMenuItem(title: accelerator, action: #selector(MenuKeyEquivalentHitTarget.hit(_:)), keyEquivalent: "")
            item.target = target
            let parsed = try? Shortcut.parse(accelerator).get()
            setMenuKeyEquivalent(item, parsed)
            viewMenu.addItem(item)
            items.append(item)
        }
        let previousMenu = app.mainMenu
        app.mainMenu = root
        defer { app.mainMenu = previousMenu }

        for ((accelerator, expectedKey, expectedMask), item) in zip(cases, items) {
            let shortcut = try? Shortcut.parse(accelerator).get()
            #expect(shortcut != nil)
            if let shortcut {
                #expect(KeyEquivalent.new(shortcut) == KeyEquivalent(key: expectedKey, mask: expectedMask))
            }
            #expect(item.keyEquivalent == expectedKey)
            #expect(item.keyEquivalentModifierMask.rawValue == expectedMask)
        }

        let fires = { (code: UInt16, flags: UInt) -> String? in
            target.hits.removeAll()
            guard let ev = makeEvent(code, flags) else { return nil }
            let handled = root.performKeyEquivalent(with: ev)
            return handled ? target.hits.joined(separator: ",") : nil
        }

        for (accelerator, key, mask) in [
            ("cmd+b", "b", MENU_COMMAND),
            ("cmd+=", "=", MENU_COMMAND),
            ("ctrl+cmd+f", "f", MENU_CONTROL | MENU_COMMAND),
            ("cmd+shift+z", "z", MENU_SHIFT | MENU_COMMAND),
        ] {
            guard let code = codeTyping(key) else { continue }
            #expect(fires(code, mask) == accelerator)
        }

        let qwertyB: UInt16 = 11
        let bHere = (codeTyping("b") == qwertyB)
        #expect((fires(qwertyB, MENU_COMMAND) != nil) == bHere)
    }
    #endif
}
