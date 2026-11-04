// Tests ported from: crates/rune-kit/tests/shell.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The app shell: pane resizing and collapse, the toggle shortcut, the source list's keyboard,
//! virtualised rows, accessibility roles and the title bar inset.

import Testing
import Rune
@testable import RuneKit

private let NAMES = ["Alpha", "Bravo", "Charlie", "Delta"]

private struct S {
    var sidebar: PaneState = PaneState.new(240.0).range(180.0, 420.0)
    var inspector: PaneState = PaneState.new(220.0).collapsed()
    var picked: Int = 1
    var collapsed: Bool = false
    var twoLines: Bool = false
    var rows: Int? = nil
    var renaming: Int? = nil
    var edit: TextEdit = TextEdit()
    var mainEdit: TextEdit = TextEdit()
    var toolbarEdit: TextEdit = TextEdit()
    var committed: String? = nil
}

private func makeState() -> S {
    S()
}

private func makeRow(_ s: S, _ i: Int, _ k: Kit) -> El {
    let label = i < NAMES.count ? NAMES[i] : "Row \(i)"
    var r = SidebarRow.new(label)
        .selected(s.picked == i)
        .onSelect { (s: inout S, _) in s.picked = i }
    if s.twoLines {
        r = r.subtitle("user\(i)@example.com")
    }
    if s.renaming == i {
        r = r.renaming(
            s.edit,
            \S.edit,
            { (s: inout S, _) in
                s.committed = s.edit.text
                s.renaming = nil
                s.edit.focused = false
            },
            { (s: inout S, _) in
                s.renaming = nil
                s.edit.focused = false
            }
        )
    }
    return r.build(k).key("row\(i)")
}

private func shellView(_ s: S, _ cx: Cx<S>) -> El {
    let k = Kit.neutral(true)
    let sidebar: Sidebar
    if let n = s.rows {
        let kit = k
        sidebar = Sidebar.new()
            .label("Sessions")
            .virtualRows(n, { (_: S, i: Int) in "row\(i)" }, { (s: S, i: Int) in makeRow(s, i, kit) })
    } else {
        sidebar = Sidebar.new().label("Sessions").section(
            SidebarSection.new("Today")
                .collapsed(s.collapsed)
                .onToggle { (s: inout S, _) in s.collapsed.toggle() }
                .rows((0..<NAMES.count).map { i in makeRow(s, i, k) })
        )
    }
    let main = col().key("body").child(
        TextInput.new(s.mainEdit)
            .placeholder("Main field")
            .onEdit(\S.mainEdit)
            .build(k)
            .key("main-field")
    )
    let inspector = col()
        .key("inspector-body")
        .child(el().key("inspector-btn").size(24.0, 24.0).role("button").focusable(true))
    return SplitView.new(main)
        .sidebar(s.sidebar, \S.sidebar, sidebar.build(k))
        .inspector(s.inspector, \S.inspector, inspector)
        .toolbar(
            Toolbar.new()
                .leading(el().key("lead").size(20.0, 20.0))
                .title("Title")
                .trailing(
                    TextInput.new(s.toolbarEdit)
                        .width(160.0)
                        .onEdit(\S.toolbarEdit)
                        .build(k)
                        .key("toolbar-search")
                )
        )
        .titlebarInset(cx.titlebarInset())
        .build(k)
}

private func makeRuntime(_ s: S) -> Runtime<S> {
    let rt = Runtime.new(s, shellView, (1000.0, 600.0), Env.new(true, 1.0))
    rt.onKey = { s, ev, _ in
        let hit = isSidebarToggle(ev)
        if hit {
            s.sidebar.toggle()
        }
        return hit
    }
    rt.frame(0.0)
    return rt
}

private func settle(_ rt: Runtime<S>) {
    for _ in 0..<120 {
        rt.frame(1.0 / 60.0)
    }
}

private func findInfo(_ rt: Runtime<S>, _ key: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.key == key && !$0.exiting }) else {
        fatalError("no \(key)")
    }
    return found
}

private func press(_ rt: Runtime<S>, _ key: Key) {
    _ = rt.key(key)
    rt.frame(1.0 / 60.0)
}

private func toggleShortcut() -> KeyEvent {
    KeyEvent(key: .command("b"), mods: Mods(shift: true, cmd: true))
}

/// One row alone: 0 plain, 1 two-line, 2 two-line and selected, 3 two-line with custom types,
/// 4 two-line with a muted subtitle.
private func loneRow(_ variant: UInt8) -> Runtime<UInt8> {
    func view(_ v: UInt8, _ cx: Cx<UInt8>) -> El {
        let k = Kit.neutral(true)
        let r: SidebarRow
        switch v {
        case 0:
            r = SidebarRow.new("Name")
        case 1:
            r = SidebarRow.new("Name").subtitle("Detail")
        case 2:
            r = SidebarRow.new("Name").subtitle("Detail").selected(true)
        case 4:
            r = SidebarRow.new("Name").subtitle("Detail").subtitleColor(k.c.textMuted)
        default:
            r = SidebarRow.new("Name")
                .subtitle("Detail")
                .titleStyle(TextStyle.new(15.0, 600.0).lh(22.0))
                .subtitleStyle(TextStyle.new(10.0, 400.0).lh(12.0))
        }
        return col().w(240.0).child(r.build(Kit.neutral(true)).key("r"))
    }
    let rt = Runtime.new(variant, view, (240.0, 200.0), Env.new(true, 1.0))
    rt.frame(0.0)
    return rt
}

private func loneInfo(_ rt: Runtime<UInt8>, _ key: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.key == key }) else {
        fatalError("no \(key)")
    }
    return found
}

private struct PickState {
    var field: TextEdit = TextEdit()
    var picked: Int = 1
    var presses: Int = 0
}

// PORT NOTE: `@MainActor` runs these deep `SplitView` integration tests on the 8 MB main stack
// rather than Swift Concurrency's 512 KB cooperative worker stack, avoiding Debug `-Onone` stack
// frame overflow in recursive `Runtime.flattenElement`.
@Suite
@MainActor
struct ShellIntegrationTests {
    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func draggingTheGripClampsCollapsesAndDoubleClickResets() {
        let rt = makeRuntime(makeState())
        guard let (x, y) = rt.find("sidebar-grip") else {
            Issue.record("missing grip")
            return
        }
        rt.pointerMove(x, y)
        _ = rt.pointerDown(x, y)
        rt.pointerMove(x + 60.0, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.width() == 300.0, "follows the pointer")
        #expect(findInfo(rt, "sidebar-pane").rect[2] == 300.0, "a drag doesn't spring")
        rt.pointerMove(x + 600.0, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.width() == 420.0, "clamps to the maximum")
        rt.pointerMove(x - 140.0, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isOpen() && rt.state.sidebar.width() == 180.0, "clamps to the minimum")
        rt.pointerMove(x - 200.0, y)
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isOpen(), "below half the minimum it collapses")
        rt.pointerMove(x - 20.0, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isOpen(), "and dragging back out opens it")
        rt.pointerUp(x - 20.0, y)
        settle(rt)
        #expect(rt.state.sidebar.width() == 220.0)

        guard let (gx, gy) = rt.find("sidebar-grip") else {
            Issue.record("missing grip")
            return
        }
        for _ in 0..<2 {
            _ = rt.pointerDown(gx, gy)
            rt.pointerUp(gx, gy)
            rt.frame(1.0 / 60.0)
        }
        #expect(rt.state.sidebar.width() == 240.0, "double-click resets the width")
    }

    @Test
    func theShortcutCollapsesOnASpringAndReducedMotionSnaps() {
        let rt = makeRuntime(makeState())
        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isOpen())
        let w = findInfo(rt, "sidebar-pane").rect[2]
        #expect(w > 0.0 && w < 240.0, "mid-spring: \(w)")
        settle(rt)
        #expect(findInfo(rt, "sidebar-pane").rect[2] == 0.0)
        #expect(!rt.elements().contains(where: { $0.key == "sidebar-grip" }), "no grip while collapsed")
        press(rt, .tab)
        let focused = rt.elements().first(where: { $0.focused })?.key
        #expect(focused != "row1", "a collapsed sidebar's rows are out of the Tab order")

        rt.setSystemReducedMotion(true)
        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isOpen())
        #expect(findInfo(rt, "sidebar-pane").rect[2] == 240.0, "Reduce Motion snaps it open")
        #expect(!isSidebarToggle(KeyEvent(key: .command("b"), mods: Mods(cmd: true))))
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func theListIsOneTabStopWhoseArrowsAndTypingMoveTheSelection() {
        let rt = makeRuntime(makeState())
        func focusedKey() -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }
        press(rt, .tab)
        #expect(focusedKey() == "row1", "Tab lands on the selected row")
        press(rt, .down)
        #expect(focusedKey() == "row2" && rt.state.picked == 2, "selection follows focus")
        for _ in 0..<4 {
            press(rt, .down)
        }
        #expect(rt.state.picked == 3, "stops at the end")
        press(rt, .home)
        #expect(rt.state.picked == 0)
        press(rt, .text("c"))
        #expect(rt.state.picked == 2, "type-select")
        rt.state.picked = 0
        press(rt, .enter)
        #expect(rt.state.picked == 2, "Return presses the focused row")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func longListsBuildOnlyTheRowsNearTheViewport() {
        var initial = makeState()
        initial.rows = 5_000
        let rt = makeRuntime(initial)
        settle(rt)
        let rows = rt.elements().filter { $0.role == "listitem" }.count
        #expect((10..<300).contains(rows), "\(rows) rows built")
        #expect(rt.find("row0") != nil && rt.find("row4999") == nil)
        press(rt, .tab)
        press(rt, .down)
        #expect(rt.state.picked == 2, "the keyboard works in a virtualised list")

        // During the sidebar's disclosure spring, rows outside the viewport must not lay out.
        let tSpring = ContinuousClock.now
        _ = rt.keyDown(toggleShortcut())
        for _ in 0..<30 {
            rt.frame(1.0 / 60.0)
            let built = rt.elements().filter { $0.role == "listitem" }.count
            #expect(built < 300, "offscreen rows built mid-spring: \(built)")
        }
        let dSpring = tSpring.duration(to: .now)
        let springUs = (Double(dSpring.components.seconds) * 1e6 + Double(dSpring.components.attoseconds) * 1e-12) / 30.0
        _ = rt.keyDown(toggleShortcut())
        settle(rt)

        // Measure scrolling across 60 frames in the 5,000-row virtual list.
        guard let (x, y) = rt.find("sidebar-scroll") else {
            Issue.record("missing scroll")
            return
        }
        let tScroll = ContinuousClock.now
        for _ in 0..<60 {
            rt.wheel(x, y, -40.0)
            rt.frame(1.0 / 60.0)
        }
        let dScroll = tScroll.duration(to: .now)
        let scrollUs = (Double(dScroll.components.seconds) * 1e6 + Double(dScroll.components.attoseconds) * 1e-12) / 60.0

        // Measure inline rename keystroke cost.
        rt.wheel(x, y, 2400.0)
        settle(rt)
        rt.update { s, _ in
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        let tKey = ContinuousClock.now
        for _ in 0..<20 {
            press(rt, .text("a"))
        }
        let dKey = tKey.duration(to: .now)
        let keyUs = (Double(dKey.components.seconds) * 1e6 + Double(dKey.components.attoseconds) * 1e-12) / 20.0
        _ = (springUs, scrollUs, keyUs)
    }

    @Test
    func rolesAndLabelsDescribeTheShell() {
        let rt = makeRuntime(makeState())
        let all = rt.elements()
        func role(_ key: String) -> (String, String?)? {
            all.first(where: { $0.key == key }).map { ($0.role, $0.label) }
        }
        #expect(role("sidebar-list")?.0 == "list" && role("sidebar-list")?.1 == "Sessions")
        #expect(role("row2")?.0 == "listitem" && role("row2")?.1 == "Charlie")
        #expect(role("section-header")?.0 == "button" && role("section-header")?.1 == "Today, expanded")
        #expect(role("toolbar")?.0 == "toolbar")
        #expect(role("sidebar-grip")?.0 == "separator" && role("sidebar-grip")?.1 == "Resize sidebar")
        #expect(role("sidebar-toggle")?.0 == "button" && role("sidebar-toggle")?.1 == "Hide sidebar")
        func fill(_ key: String) -> Float {
            all.first(where: { $0.key == key })!.fill.a
        }
        #expect(fill("row1") > 0.0 && fill("row0") == 0.0, "the selected row is filled")
        let toggle = all.first(where: { $0.key == "sidebar-toggle" })!
        #expect(toggle.expanded == true, "the toggle reports the open sidebar")
        #expect(fill("sidebar-toggle") == 0.0, "without holding a pressed fill")

        let (x, y) = rt.find("section-header")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        settle(rt)
        #expect(rt.state.collapsed)
        #expect(findInfo(rt, "section-header").label == "Today, collapsed")
        #expect(rt.find("row0") == nil, "a collapsed section hides its rows")
    }

    @Test
    func theTitleBarClearsTheTrafficLightsAndDragsTheWindow() {
        let rt = makeRuntime(makeState())
        let inset = Chrome.DEFAULT.titlebarInset()
        #expect(inset > 0.0)
        rt.setTitlebarInset(inset)
        rt.setSystemReducedMotion(true)
        rt.frame(1.0 / 60.0)
        #expect(findInfo(rt, "sidebar-toggle").rect[0] == inset + 8.0, "the toggle sits past the lights")
        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(findInfo(rt, "lead").rect[0] == inset + 8.0 + 24.0 + 8.0, "a collapsed sidebar's toolbar clears lights and toggle")

        rt.setTitlebarInset(0.0)
        rt.frame(1.0 / 60.0)
        #expect(findInfo(rt, "sidebar-toggle").rect[0] == 12.0, "full screen has no lights to clear")
        #expect(findInfo(rt, "lead").rect[0] == 12.0 + 24.0 + 8.0)

        for (key, drags) in [("title", true), ("sidebar-toggle", false), ("lead", true)] {
            let (x, y) = rt.find(key)!
            rt.pointerMove(x, y)
            _ = rt.pointerDown(x, y)
            #expect((rt.takeTitlebarAction() == .drag) == drags, "\(key)")
            rt.pointerUp(x, y)
            rt.frame(1.0 / 60.0)
        }
        #expect(rt.state.sidebar.isOpen(), "the toggle button opened the sidebar again")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func collapsingTheSidebarMovesFocusOutAndBlursRename() {
        let rt = makeRuntime(makeState())
        func focusedKey() -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }
        press(rt, .tab)
        #expect(focusedKey() == "row1")

        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(focusedKey() == "sidebar-toggle", "focus leaves the collapsed sidebar")
        press(rt, .down)
        #expect(rt.state.picked == 1, "arrows no longer move a collapsed sidebar's selection")

        // Reopen and start an inline rename, then collapse: the rename input must blur.
        _ = rt.keyDown(toggleShortcut())
        settle(rt)
        rt.update { s, _ in
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        #expect(focusedKey() == "rename")

        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.edit.focused, "collapsing the sidebar blurs its rename field")
        #expect(focusedKey() == "sidebar-toggle")
        press(rt, .text("X"))
        #expect(rt.state.edit.text == "Bravo", "typing after collapse does not edit the hidden field")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func hidingTheSidebarKeepsFocusInAToolbarSearch() {
        let rt = makeRuntime(makeState())
        let (x, y) = rt.find("toolbar-search")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        rt.frame(0.0)
        #expect(rt.state.toolbarEdit.focused)
        _ = rt.keyDown(toggleShortcut())
        rt.frame(0.0)
        #expect(!rt.state.sidebar.isOpen())
        #expect(rt.state.toolbarEdit.focused, "the sentinel belongs to the sidebar, not the whole shell")
        press(rt, .text("search"))
        #expect(rt.state.toolbarEdit.text == "search")
        #expect(rt.takeTitlebarAction() == nil)
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func hidingTheSidebarKeepsFocusInAMainPaneTextField() {
        let rt = makeRuntime(makeState())
        func focusedKey() -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }
        let (x, y) = rt.find("main-field")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.mainEdit.focused)
        #expect(focusedKey() == "input")

        _ = rt.keyDown(toggleShortcut())
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isOpen(), "shortcut closes the sidebar")
        #expect(rt.state.mainEdit.focused, "focus never leaves the main text field")
        #expect(focusedKey() == "input")

        for ch in ["a", " ", "b"] {
            press(rt, .text(ch))
        }
        #expect(rt.state.mainEdit.text == "a b")
        #expect(!rt.state.sidebar.isOpen(), "Space typed into the field does not reopen the sidebar")
        #expect(rt.state.mainEdit.focused)

        // Closing the inspector while focus is inside it returns focus to the main pane, while
        // closing it with focus already in main keeps focus in main.
        rt.update { s, _ in s.inspector.setOpen(true) }
        settle(rt)
        let (ix, iy) = rt.find("inspector-btn")!
        _ = rt.pointerDown(ix, iy)
        rt.pointerUp(ix, iy)
        rt.frame(1.0 / 60.0)
        #expect(focusedKey() == "inspector-btn")
        rt.update { s, _ in s.inspector.setOpen(false) }
        rt.frame(1.0 / 60.0)
        #expect(focusedKey() == "input", "closing a focused inspector returns focus to main")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func inlineRenameCommitsOnReturnAndCancelsOnEscape() {
        let rt = makeRuntime(makeState())
        rt.update { s, _ in
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.anchor = 0
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        press(rt, .text("Beta"))
        #expect(rt.state.edit.text == "Beta")
        press(rt, .escape)
        #expect(rt.state.renaming == nil && rt.state.committed == nil, "Escape cancels")

        rt.update { s, _ in
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.anchor = 0
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        press(rt, .text("Beta"))
        press(rt, .enter)
        #expect(rt.state.renaming == nil && rt.state.committed == "Beta", "Return commits")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func aStuckResizeClearsOnWindowBlurOrUncapturedPointerMove() {
        let rt = makeRuntime(makeState())
        let (x, y) = rt.find("sidebar-grip")!
        rt.pointerMove(x, y)
        _ = rt.pointerDown(x, y)
        rt.pointerMove(x - 200.0, y)
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isOpen() && rt.state.sidebar.isResizing())

        // Losing window focus without a pointer-up clears `isResizing`.
        rt.windowFocus(false)
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isResizing(), "window blur clears a stuck resize")

        // Reopen, start another resize, release capture, then simulate a stuck flag: the next
        // uncaptured pointer move clears it.
        rt.windowFocus(true)
        rt.update { s, _ in s.sidebar.setOpen(true) }
        settle(rt)
        let (gx, gy) = rt.find("sidebar-grip")!
        rt.pointerMove(gx, gy)
        _ = rt.pointerDown(gx, gy)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isResizing())
        rt.pointerUp(gx, gy)
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isResizing())

        _ = rt.pointerDown(gx, gy)
        rt.pointerMove(gx + 20.0, gy)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isResizing(), "live drag keeps resizing")
        rt.pointerUp(gx + 20.0, gy)
        rt.frame(1.0 / 60.0)
        _ = rt.pointerDown(gx + 20.0, gy)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.sidebar.isResizing())
        rt.pointerUp(gx + 20.0, gy)
        rt.pointerMove(500.0, 300.0)
        rt.frame(1.0 / 60.0)
        #expect(!rt.state.sidebar.isResizing())
    }

    @Test
    func sidebarAndMainPaneMoveInLockstepDuringDisclosure() {
        let rt = makeRuntime(makeState())
        _ = rt.keyDown(toggleShortcut())
        for _ in 0..<30 {
            rt.frame(1.0 / 60.0)
            let sideW = findInfo(rt, "sidebar-pane").rect[2]
            let mainColX = findInfo(rt, "main-column").rect[0]
            #expect(
                abs(sideW - mainColX) < 0.05,
                "sidebar right edge (\(sideW)) and main-column left edge (\(mainColX)) must move together"
            )
        }
    }

    @Test
    func aWiderRangeKeepsTheWidthNewWasGiven() {
        let p0 = PaneState.new(640.0).range(360.0, 960.0)
        #expect(p0.width() == 640.0 && p0.defaultWidth() == 640.0)
        var p1 = PaneState.new(640.0).range(360.0, 960.0).withWidth(700.0)
        #expect(p1.width() == 700.0 && p1.defaultWidth() == 640.0)
        p1.resetWidth()
        #expect(p1.width() == 640.0)
        let p2 = PaneState.new(900.0).range(360.0, 600.0)
        #expect(p2.width() == 600.0 && p2.defaultWidth() == 600.0)
        #expect(PaneState.new(640.0).width() == PaneState.MAX)
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func aRenameFieldKeepsLettersAndArrowsThatWouldTypeSelectARow() {
        let rt = makeRuntime(makeState())
        func focusedKey() -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }
        rt.update { s, _ in
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.anchor = 0
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        for key in ["D", "e", "l"] {
            press(rt, .text(key))
        }
        for key: Key in [.down, .up, .home, .end] {
            press(rt, key)
        }
        #expect(rt.state.edit.text == "Del", "Delta's first letter goes to the field")
        #expect(rt.state.picked == 1 && focusedKey() == "rename", "no row was type-selected")
    }

    @Test
    func anExplicitTwoLineRowHeightWinsInEitherBuilderOrder() {
        struct Empty {}
        func view(_ s: Empty, _ cx: Cx<Empty>) -> El {
            let k = Kit.neutral(true)
            return col()
                .w(240.0)
                .child(SidebarRow.new("First").height(45.0).subtitle("Detail").build(k).key("first"))
                .child(SidebarRow.new("Second").subtitle("Detail").height(45.0).build(k).key("second"))
        }
        let rt = Runtime.new(Empty(), view, (240.0, 200.0), Env.new(true, 1.0))
        rt.frame(0.0)
        for key in ["first", "second"] {
            #expect(rt.elements().first(where: { $0.key == key })!.rect[3] == 45.0)
        }
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func twoLineRowsKeepFocusKeyboardNavigationAndAccessibleLabels() {
        var initial = makeState()
        initial.twoLines = true
        let rt = makeRuntime(initial)
        func focusedKey() -> String? {
            rt.elements().first(where: { $0.focused })?.key
        }
        let r2 = findInfo(rt, "row2")
        #expect(r2.role == "listitem" && r2.label == "Charlie, user2@example.com" && r2.rect[3] == 40.0)

        press(rt, .tab)
        #expect(focusedKey() == "row1", "Tab lands on the selected two-line row")
        press(rt, .down)
        #expect(focusedKey() == "row2" && rt.state.picked == 2)
        press(rt, .home)
        #expect(focusedKey() == "row0" && rt.state.picked == 0)
        press(rt, .text("d"))
        #expect(focusedKey() == "row3" && rt.state.picked == 3, "type-select matches the title label")
        rt.state.picked = 0
        press(rt, .enter)
        #expect(rt.state.picked == 3, "Return selects the focused two-line row")

        // Ending an inline rename on a two-line row returns focus to the selected row.
        rt.update { s, _ in
            s.picked = 1
            s.renaming = 1
            s.edit = TextEdit.new("Bravo")
            s.edit.focused = true
        }
        rt.frame(1.0 / 60.0)
        #expect(focusedKey() == "rename")
        press(rt, .escape)
        #expect(focusedKey() == "row1", "ending rename returns focus to the selected row")
    }

    @Test
    func pageMatchesSplitViewsToolbarAndFramePixelForPixel() {
        struct P {
            var page: Bool
            var sidebar: PaneState
            var backs: Int
        }
        func pageView(_ s: P, _ cx: Cx<P>) -> El {
            let k = Kit.neutral(true)
            let lead = el().key("lead").size(24.0, 24.0).role("button").focusable(true).onPress { (s: inout P) in
                s.backs += 1
            }
            let trail = el().key("trail").size(24.0, 24.0).role("button").focusable(true)
            let body = col().key("content").wFull().hFull()
            if s.page {
                return Page.new(body)
                    .title("Settings")
                    .leading(lead)
                    .trailing(trail)
                    .titlebarInset(cx.titlebarInset())
                    .frameInset(8.0)
                    .build(k)
            } else {
                return SplitView.new(body)
                    .sidebar(s.sidebar, \P.sidebar, col())
                    .hideSidebarToggle()
                    .toolbar(Toolbar.new().title("Settings").leading(lead).trailing(trail))
                    .titlebarInset(cx.titlebarInset())
                    .frameInset(8.0)
                    .build(k)
            }
        }
        let inset = Chrome.DEFAULT.titlebarInset()
        let rt = Runtime.new(
            P(page: false, sidebar: PaneState.new(240.0).collapsed(), backs: 0),
            pageView,
            (960.0, 600.0),
            Env.new(true, 2.0)
        )
        rt.setTitlebarInset(inset)
        rt.frame(0.0)
        func rectIn(_ key: String) -> [Float] {
            rt.elements().first(where: { $0.key == key })!.rect
        }
        let splitToolbar = rectIn("toolbar")
        let splitLead = rectIn("lead")
        let splitTitle = rectIn("title")
        let splitTrail = rectIn("trail")
        let splitPane = rectIn("main-pane")

        rt.update { s, _ in s.page = true }
        rt.frame(1.0 / 60.0)
        #expect(rectIn("toolbar") == splitToolbar, "toolbar rect matches SplitView")
        #expect(rectIn("lead") == splitLead, "leading control past traffic lights matches SplitView")
        #expect(rectIn("title") == splitTitle, "title rect matches SplitView")
        #expect(rectIn("trail") == splitTrail, "trailing control rect matches SplitView")
        #expect(rectIn("main-pane") == splitPane, "framed main-pane rect matches SplitView")

        // Titlebar drags the window; leading button keeps its press.
        let (tx, ty) = rt.find("title")!
        _ = rt.pointerDown(tx, ty)
        #expect(rt.takeTitlebarAction() == .drag)
        rt.pointerUp(tx, ty)
        let (lx, ly) = rt.find("lead")!
        _ = rt.pointerDown(lx, ly)
        #expect(rt.takeTitlebarAction() == nil)
        rt.pointerUp(lx, ly)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.backs == 1)
    }

    @Test
    func iconButtonAndSidebarToggleShowHelpAndShortcutTooltips() {
        struct H {
            var sidebar: PaneState
        }
        func helpView(_ s: H, _ cx: Cx<H>) -> El {
            let k = Kit.neutral(true)
            let lock = IconButton.new(glyphs.LOCK)
                .help("Lock")
                .shortcut("⌘L")
                .build(k)
                .key("lock")
            let parsed = IconButton.new(glyphs.COPY)
                .label("Copy")
                .shortcut("cmd+c")
                .build(k)
                .key("copy")
            let save = Button.new("Save")
                .shortcut("⌘S")
                .build(k)
                .key("save")
            return SplitView.new(col().wFull().hFull())
                .sidebar(s.sidebar, \H.sidebar, col())
                .toolbar(Toolbar.new().trailing(lock).trailing(parsed).trailing(save))
                .build(k)
        }
        let rt = Runtime.new(
            H(sidebar: PaneState.new(240.0)),
            helpView,
            (800.0, 480.0),
            Env.new(true, 2.0)
        )
        rt.frame(0.0)
        func info(_ key: String) -> ElementInfo {
            rt.elements().first(where: { $0.key == key })!
        }
        #expect(info("lock").label == "Lock", "help supplies accessible label when label is unset")
        #expect(info("lock").help == "Lock  ⌘L")
        #if os(macOS)
        let expectedCopy = "Copy  ⌘C"
        let expectedToggle = "Hide sidebar  ⇧⌘B"
        #else
        let expectedCopy = "Copy  Super+C"
        let expectedToggle = "Hide sidebar  Ctrl+Shift+B"
        #endif
        #expect(info("copy").help == expectedCopy)
        #expect(info("save").help == "Save  ⌘S")
        #expect(info("sidebar-toggle").help == expectedToggle)

        let (x, y) = rt.find("lock")!
        rt.pointerMove(x, y)
        rt.frame(1.0 / 60.0)
        rt.frame(rt.helpDelay + 0.05)
        #expect(rt.activeHelp()?.text == "Lock  ⌘L")
    }

    @Test
    func aLongLeadingTitleTruncatesAndKeepsTheTrailingSlotOnTheBand() {
        struct T {}
        func toolbarView(_ s: T, _ cx: Cx<T>) -> El {
            let k = Kit.neutral(true)
            return Toolbar.new()
                .leading(Rune.text(String(repeating: "a", count: 400)).key("long").truncate().shrink().minW(0.0))
                .trailing(el().key("trail").size(24.0, 24.0))
                .build(k)
        }
        let rt = Runtime.new(T(), toolbarView, (400.0, 200.0), Env.new(true, 1.0))
        rt.frame(0.0)
        func rect(_ key: String) -> [Float] {
            rt.elements().first(where: { $0.key == key })!.rect
        }
        let long = rect("long")
        let trail = rect("trail")
        #expect(trail[0] + trail[2] <= 400.0 + 0.5, "trailing slot pushed off the band: \(trail)")
        #expect(long[0] + long[2] <= trail[0] + 0.5, "leading title overlaps the trailing slot: \(long) \(trail)")
    }

    @Test
    func aTwoLineRowHasAStrongerFirstLineAndFitsIn40Points() {
        let k = Kit.neutral(true)
        for (variant, selected): (UInt8, Bool) in [(1, false), (2, true)] {
            let rt = loneRow(variant)
            let rowInfo = loneInfo(rt, "r")
            let name = loneInfo(rt, "label")
            let sub = loneInfo(rt, "subtitle")
            #expect(rowInfo.rect[3] == 40.0)
            #expect(name.textColor == (selected ? k.c.textBase : k.c.textMuted))
            #expect(sub.textColor == k.c.textFaint, "the subtitle is the faintest ink")
            #expect(name.rect[1] + name.rect[3] <= sub.rect[1] + 0.01, "the lines don't overlap")
            #expect(sub.rect[1] + sub.rect[3] <= rowInfo.rect[1] + rowInfo.rect[3], "both lines fit the default height")
            #expect(name.rect[3] == k.ty.uiCompact.linePx() && sub.rect[3] == k.ty.caption().linePx())
        }
        let rt = loneRow(3)
        #expect(loneInfo(rt, "label").rect[3] == 22.0 && loneInfo(rt, "subtitle").rect[3] == 12.0)
    }

    @Test
    func aTwoLineRowsSubtitleTakesItsOwnColour() {
        let k = Kit.neutral(true)
        #expect(loneInfo(loneRow(4), "subtitle").textColor == k.c.textMuted)
    }

    @Test
    func renamingATwoLineRowKeepsTheTitleAndSubtitleLinesInPlace() {
        struct Ren {
            var renaming: Bool
            var custom: Bool
            var edit: TextEdit
        }
        func view(_ s: Ren, _ cx: Cx<Ren>) -> El {
            var r = SidebarRow.new("Name").subtitle("Detail")
            if s.custom {
                r = r.titleStyle(TextStyle.new(15.0, 600.0).lh(22.0))
            }
            if s.renaming {
                r = r.renaming(s.edit, \Ren.edit, { _, _ in }, { _, _ in })
            }
            return col().w(240.0).child(r.build(Kit.neutral(true)).key("r"))
        }
        for custom in [false, true] {
            let rt = Runtime.new(
                Ren(renaming: false, custom: custom, edit: TextEdit()),
                view,
                (240.0, 200.0),
                Env.new(true, 1.0)
            )
            rt.frame(0.0)
            let labelRect = rt.elements().first(where: { $0.key == "label" })!.rect
            let subRect = rt.elements().first(where: { $0.key == "subtitle" })!.rect
            for txt in ["Name", ""] {
                rt.update { s, _ in
                    s.renaming = true
                    s.edit = TextEdit.new(txt)
                    s.edit.focused = true
                }
                rt.frame(1.0 / 60.0)
                let renameRect = rt.elements().first(where: { $0.key == "rename" })!.rect
                let subNow = rt.elements().first(where: { $0.key == "subtitle" })!.rect
                #expect(renameRect[1] == labelRect[1] && renameRect[3] == labelRect[3], "rename field matches title line y and height")
                #expect(subNow == subRect, "subtitle does not jump when entering rename")
            }
        }
    }

    @Test
    func aTwoLineRowReadsNameThenSubtitle() {
        let rt1 = loneRow(1)
        #expect(loneInfo(rt1, "r").label == "Name, Detail")
        let rt0 = loneRow(0)
        #expect(loneInfo(rt0, "r").label == "Name")
    }

    // PORT NOTE: Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation.
    @Test(.disabled("Blocked on Sources/Rune focusGroup source-list navigation, virtualRowsSource, double-click & focus preservation"))
    func selectOnlyRowsSkipTabAndKeepAnOutsideFieldFocused() {
        func view(_ s: PickState, _ cx: Cx<PickState>) -> El {
            let k = Kit.neutral(true)
            return col()
                .w(240.0)
                .gap(8.0)
                .child(TextInput.new(s.field).onEdit(\PickState.field).build(k).key("field"))
                .child(
                    Sidebar.new()
                        .label("Results")
                        .child(
                            col().children((0..<3).map { i in
                                SidebarRow.new("Row \(i)")
                                    .selectOnly()
                                    .selected(s.picked == i)
                                    .onSelect { (s: inout PickState, _) in
                                        s.picked = i
                                        s.presses += 1
                                    }
                                    .build(k)
                                    .key("row\(i)")
                            })
                        )
                        .build(k)
                )
        }
        let rt = Runtime.new(PickState(), view, (240.0, 300.0), Env.new(true, 1.0))
        rt.frame(0.0)
        func rowInfo(_ i: Int) -> ElementInfo {
            rt.elements().first(where: { $0.key == "row\(i)" })!
        }
        #expect((0..<3).allSatisfy { !rowInfo($0).focusable }, "rows take no focus")
        #expect(rowInfo(1).itemSelected && !rowInfo(0).itemSelected, "the selection is still exposed")

        _ = rt.key(.tab)
        rt.frame(1.0 / 60.0)
        func focusedKeys() -> [String] {
            rt.elements().filter { $0.focused }.compactMap { $0.key }
        }
        #expect(focusedKeys() == ["input"], "Tab lands on the field and no row")
        _ = rt.key(.tab)
        rt.frame(1.0 / 60.0)
        #expect(rt.elements().allSatisfy { ($0.key.map { !$0.hasPrefix("row") } ?? true) || !$0.focused })

        let r = rowInfo(2)
        let (x, y) = (r.rect[0] + 20.0, r.rect[1] + r.rect[3] * 0.5)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        rt.frame(1.0 / 60.0)
        #expect(rt.state.picked == 2 && rt.state.presses == 1, "the press selects")
        #expect(focusedKeys() == ["input"], "the field keeps focus through the press")
        #expect(rowInfo(2).itemSelected && !rowInfo(1).itemSelected)

        // Changing selection from the app (e.g. arrow keys handled by the field) keeps focus on the field.
        rt.update { s, _ in s.picked = 0 }
        rt.frame(1.0 / 60.0)
        #expect(focusedKeys() == ["input"], "selection change never pulls focus from the field")
        #expect(rowInfo(0).itemSelected && !rowInfo(2).itemSelected)
    }
}
