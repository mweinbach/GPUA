// Tests ported from: crates/rune/tests/default_menu_macos.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Main-thread AppKit menu assertions, without opening a window or running an event loop.

#if os(macOS)
import AppKit
import Foundation
#endif
import Testing
@testable import Rune

@Suite("DefaultMenuMacosIntegrationTests", .serialized)
struct DefaultMenuMacosIntegrationTests {
    #if os(macOS)
    @Test @MainActor
    func defaultTitlesSelectorsStandardMenusAndCustomEquivalents() async {
        let app = NSApplication.shared
        let savedPolicy = app.activationPolicy()
        let savedMenu = app.mainMenu
        defer {
            app.mainMenu = savedMenu
            _ = app.setActivationPolicy(savedPolicy)
        }
        _ = app.setActivationPolicy(.accessory)
        app.mainMenu = nil

        let root = ensureDefaultMenu(app)
        guard let menu = root.item(at: 0)?.submenu else {
            Issue.record("expected app submenu")
            return
        }
        let name = ProcessInfo.processInfo.processName
        let titles = (0..<menu.numberOfItems).compactMap { menu.item(at: $0)?.title }
        #expect(titles == [
            "About \(name)", "", "Services", "Hide \(name)",
            "Hide Others", "Show All", "", "Quit \(name)",
        ])
        let command: NSEvent.ModifierFlags = [.command]
        let expected: [(Int, Selector, String, NSEvent.ModifierFlags)] = [
            (0, #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", command),
            (3, #selector(NSApplication.hide(_:)), "h", command),
            (4, #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            (5, #selector(NSApplication.unhideAllApplications(_:)), "", command),
            (7, #selector(NSApplication.terminate(_:)), "q", command),
        ]
        for (index, selector, key, modifiers) in expected {
            let item = menu.item(at: index)
            #expect(item?.action == selector)
            #expect(item?.keyEquivalent == key)
            #expect(item?.keyEquivalentModifierMask == modifiers)
        }
        let services = app.servicesMenu
        #expect(services != nil && services === menu.item(at: 2)?.submenu)
        #expect(root.numberOfItems == 1, "no Edit menu intercepts Rune text commands")

        // Repeated promotion preserves the root and any custom items added after it.
        let custom = NSMenuItem()
        custom.title = "Custom action"
        menu.insertItem(custom, at: 0)
        for _ in 0..<2 {
            let current = ensureDefaultMenu(app)
            #expect(current === root)
            #expect(menu.numberOfItems == 9)
            #expect(menu.item(at: 0) === custom)
        }

        // An app's preexisting menu always wins, including an intentionally empty one.
        let supplied = NSMenu()
        app.mainMenu = supplied
        #expect(ensureDefaultMenu(app) === supplied)
        #expect(supplied.numberOfItems == 0)
        let top = NSMenuItem()
        top.title = "App-owned menu"
        supplied.addItem(top)
        #expect(ensureDefaultMenu(app) === supplied)
        #expect(supplied.numberOfItems == 1)
        #expect(!isWinitDefaultMenu(app), "an app-owned menu bar gets no standard items")

        // A regular app's default menu bar takes the standard Edit and Window items.
        app.mainMenu = nil
        let root2 = ensureDefaultMenu(app)
        #expect(isWinitDefaultMenu(app))
        addStandardMenus(app)
        func tops(_ r: NSMenu) -> [String] {
            (0..<r.numberOfItems).compactMap { r.item(at: $0)?.title }
        }
        func plan(_ m: NSMenu) -> [(String, String?, String, NSEvent.ModifierFlags, Bool)] {
            (0..<m.numberOfItems).compactMap { m.item(at: $0) }.map { item in
                if item.isSeparatorItem {
                    return ("-", nil, "", command, true)
                }
                return (
                    item.title,
                    item.action.map { NSStringFromSelector($0) },
                    item.keyEquivalent,
                    item.keyEquivalentModifierMask,
                    item.target == nil
                )
            }
        }
        #expect(Array(tops(root2).dropFirst()) == ["Edit", "Window"])
        let shift: NSEvent.ModifierFlags = [.command, .shift]
        let editPlan = plan(root2.item(at: 1)!.submenu!)
        #expect(editPlan.map(\.0) == ["Undo", "Redo", "-", "Cut", "Copy", "Paste", "Select All"])
        #expect(editPlan[0].1 == "undo:" && editPlan[0].2 == "z" && editPlan[0].3 == command && editPlan[0].4)
        #expect(editPlan[1].1 == "redo:" && editPlan[1].2 == "z" && editPlan[1].3 == shift && editPlan[1].4)
        let winPlan = plan(root2.item(at: 2)!.submenu!)
        #expect(winPlan.map(\.0) == ["Minimize", "Close"])
        #expect(winPlan[0].1 == "performMiniaturize:" && winPlan[0].2 == "m")
        #expect(winPlan[1].1 == "performClose:" && winPlan[1].2 == "w")
        #expect(root2.item(at: 0)?.submenu?.numberOfItems == 8)
        addStandardMenus(app)
        #expect(tops(root2).count == 3, "adding twice changes nothing")

        // Custom menus take the Mac order around the standard ones, and custom equivalents win.
        func keyOf(_ r: NSMenu, _ menuTitle: String, _ itemTitle: String) -> String {
            let sub = (0..<r.numberOfItems).compactMap { r.item(at: $0) }.first { $0.title == menuTitle }!.submenu!
            return (0..<sub.numberOfItems).compactMap { sub.item(at: $0) }.first { $0.title == itemTitle }!.keyEquivalent
        }
        let (fileTop, file) = addTopMenu(root2, "File")
        let (viewTop, _) = addTopMenu(root2, "View")
        let (helpTop, _) = addTopMenu(root2, "Help")
        #expect(Array(tops(root2).dropFirst()) == ["File", "Edit", "View", "Window", "Help"])
        let closeTab = NSMenuItem(title: "Close Tab", action: NSSelectorFromString("runeMenuAction:"), keyEquivalent: "w")
        addingCustomMenus(app) { file.addItem(closeTab) }
        #expect(closeTab.keyEquivalent == "w")
        #expect(keyOf(root2, "Window", "Close") == "", "Close Tab ⌘W wins")
        #expect(keyOf(root2, "Window", "Minimize") == "m")
        let pastePlain = NSMenuItem(title: "Paste Plain", action: NSSelectorFromString("runeMenuAction:"), keyEquivalent: "V")
        pastePlain.keyEquivalentModifierMask = [.command, .option]
        addingCustomMenus(app) { file.addItem(pastePlain) }
        #expect(keyOf(root2, "Edit", "Paste") == "v", "⌥⇧⌘V isn't ⌘V")
        file.removeItem(closeTab)
        file.removeItem(pastePlain)
        for t in [fileTop, viewTop, helpTop] {
            removeTopMenuIfEmpty(root2, t)
        }
        syncStandardMenus(app)
        #expect(Array(tops(root2).dropFirst()) == ["Edit", "Window"])
        #expect(keyOf(root2, "Window", "Close") == "w", "Close gets ⌘W back")

        // Set before standard items: custom item still wins, shared menu outlives it.
        app.mainMenu = nil
        let root3 = ensureDefaultMenu(app)
        let (windowTop, windowMenu) = addTopMenu(root3, "Window")
        let closeAll = NSMenuItem(title: "Close All", action: NSSelectorFromString("runeMenuAction:"), keyEquivalent: "w")
        addingCustomMenus(app) { windowMenu.addItem(closeAll) }
        addStandardMenus(app)
        #expect(Array(tops(root3).dropFirst()) == ["Edit", "Window"])
        #expect(closeAll.keyEquivalent == "w")
        #expect(keyOf(root3, "Window", "Close") == "")
        windowMenu.removeItem(closeAll)
        removeTopMenuIfEmpty(root3, windowTop)
        syncStandardMenus(app)
        #expect(Array(tops(root3).dropFirst()) == ["Edit", "Window"])
        #expect(plan(windowMenu).map { ($0.0, $0.2) }.map { "\($0.0):\($0.1)" } == ["Minimize:m", "Close:w"])

        // An app's own Edit menu keeps its items; only missing actions join it.
        app.mainMenu = nil
        let supplied2 = NSMenu()
        let editTop = NSMenuItem()
        editTop.title = "Edit"
        let edit = NSMenu()
        let ownCopy = NSMenuItem(title: "Copy Link", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(ownCopy)
        editTop.submenu = edit
        supplied2.addItem(editTop)
        app.mainMenu = supplied2
        addStandardMenus(app)
        #expect(tops(supplied2) == ["Edit", "Window"])
        #expect(plan(edit).map(\.0) == ["Copy Link", "Undo", "Redo", "-", "Cut", "Paste", "Select All"])

        // An accessory app's standard items wait without Quit until its Dock icon shows.
        app.mainMenu = nil
        addStandardMenus(app)
        let root4 = app.mainMenu!
        let appMenu = root4.item(at: 0)!.submenu!
        #expect(appMenu.numberOfItems == 0, "no Quit or terminate: for an accessory app")
        #expect(!isWinitDefaultMenu(app))
        func hasTerminate(_ r: NSMenu) -> Bool {
            (0..<r.numberOfItems).compactMap { r.item(at: $0)?.submenu }.contains { m in
                (0..<m.numberOfItems).compactMap { m.item(at: $0) }.contains {
                    $0.action == #selector(NSApplication.terminate(_:))
                }
            }
        }
        #expect(!hasTerminate(root4))
        for _ in 0..<2 {
            promoteDefaultMenu(app)
            #expect(app.mainMenu === root4)
            #expect(appMenu.numberOfItems == 8, "showing the Dock icon adds winit's app menu, once")
        }
        #expect(hasTerminate(root4))
    }
    #else
    @Test func nonMacosNoop() {}
    #endif
}
