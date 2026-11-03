// Tests ported from: crates/rune/src/popup_menu/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private struct PopupTestState {
    var theme: String = "system"
    var picks: [String?] = []
    var anchor: PopupAnchor? = nil
    var extra: Bool = false
}

private func makeThemeMenu(_ selected: String) -> PopupMenu {
    PopupMenu.picker([("system", "System"), ("light", "Light"), ("dark", "Dark")], selected)
}

private func recordPick(_ s: inout PopupTestState, _ picked: String?, _ tx: inout Tx) {
    _ = tx
    s.picks.append(picked)
    if let id = picked {
        s.theme = id
    }
}

private func popupView(_ s: PopupTestState, _ cx: Cx<PopupTestState>) -> El {
    _ = cx
    var root = el()
        .child(el().key("theme").size(80.0, 20.0))
        .child(el().key("canvas").size(100.0, 40.0))
    if s.extra {
        root = root.child(el().key("extra").size(30.0, 10.0))
    }
    return root
}

private func makePopupRuntime() -> Runtime<PopupTestState> {
    let rt = Runtime(PopupTestState(), popupView, (200.0, 120.0), Env.new(true, 1.0))
    let ps = popupState(for: rt)
    ps.anchorRectOverrides["theme"] = [40.0, 30.0, 80.0, 20.0]
    ps.anchorRectOverrides["canvas"] = [0.0, 60.0, 100.0, 40.0]
    _ = rt.frame(0.0)
    return rt
}

@Suite("PopupMenuTests")
struct PopupMenuTests {
    @Test func aPressHandlerAsksForAMenuThatOpensOverItsAnchor() {
        let rt = makePopupRuntime()
        rt.hostUpdate { s, tx in
            let anchor = s.anchor ?? .key("theme")
            tx.popupMenu(makeThemeMenu(s.theme), anchor, recordPick)
        }
        #expect(rt.hostPopupMenu() == makeThemeMenu("system"))
        guard let maybeShow = rt.hostTakePopup(), let show = maybeShow else {
            Issue.record("Expected PopupShow")
            return
        }
        #expect(show.positioned == "system")
        #expect(show.at.0 == 40.0 && show.at.1 == 30.0)
        #expect(show.minWidth == 80.0)
        #expect(rt.hostTakePopup() == nil)

        #expect(voidOk(rt.hostResolvePopup("dark")))
        #expect(rt.state.picks == [Optional("dark")])
        #expect(rt.hostPopupMenu() == nil)
        #expect(rt.state.theme == "dark")
    }

    @Test func aMenuWithoutASelectionDropsDownBelowItsElement() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            tx.popupMenu(PopupMenu.new().item(PopupItem.new("a", "A")), "theme", recordPick)
        }
        guard let maybeShow = rt.hostTakePopup(), let show = maybeShow else {
            Issue.record("Expected PopupShow")
            return
        }
        #expect(show.at.0 == 40.0 && show.at.1 == 50.0)
        #expect(show.positioned == nil)
        #expect(show.minWidth == 80.0)
    }

    @Test func aContextMenuOpensAtThePress() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            let menu = PopupMenu.new()
                .item(PopupItem.new("copy", "Copy"))
                .separator()
                .item(PopupItem.new("paste", "Paste").enabled(false))
                .submenu("More", PopupMenu.new().item(PopupItem.new("share", "Share")))
            tx.popupMenu(menu, PointerPress(x: 30.0, y: 70.0), recordPick)
        }
        guard let maybeShow = rt.hostTakePopup(), let show = maybeShow else {
            Issue.record("Expected PopupShow")
            return
        }
        #expect(show.at.0 == 30.0 && show.at.1 == 70.0)
        #expect(show.positioned == nil)
        #expect(show.minWidth == 0.0)
        #expect(voidErr(rt.hostResolvePopup("paste")) == .disabled("paste"))
        #expect(voidErr(rt.hostResolvePopup("nope")) == .unknownItem("nope"))
        #expect(rt.hostPopupMenu() != nil)
        #expect(voidOk(rt.hostResolvePopup("share")))
        #expect(rt.state.picks == [Optional("share")])
        #expect(voidErr(rt.hostResolvePopup(nil)) == .notOpen)
    }

    @Test func aPointAnchorWithASelectionPutsThatItemUnderThePoint() {
        let rt = makePopupRuntime()
        rt.state.anchor = PopupAnchor((5.0, 6.0))
        rt.hostUpdate { s, tx in
            tx.popupMenu(makeThemeMenu(s.theme), s.anchor ?? "theme", recordPick)
        }
        guard let maybeShow = rt.hostTakePopup(), let show = maybeShow else {
            Issue.record("Expected PopupShow")
            return
        }
        #expect(show.at.0 == 5.0 && show.at.1 == 6.0)
        #expect(show.positioned == "system")
        #expect(show.minWidth == 0.0)
    }

    @Test func aMenuThatCannotOpenAnswersNone() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in tx.popupMenu(makeThemeMenu("system"), "missing", recordPick) }
        rt.hostUpdate { _, tx in
            tx.popupMenu(PopupMenu.new().item(PopupItem.new("a", "A")).item(PopupItem.new("a", "B")), "theme", recordPick)
        }
        rt.hostUpdate { _, tx in
            tx.popupMenu(PopupMenu.new().item(PopupItem.new("", "Blank")), "theme", recordPick)
        }
        rt.hostUpdate { _, tx in tx.popupMenu(makeThemeMenu("light"), "theme", recordPick) }
        rt.hostOpenPopupHeadless()
        #expect(rt.state.picks == [nil, nil, nil])
        #expect(rt.hostPopupMenu() == makeThemeMenu("light"))
        #expect(rt.hostPopupOpen)
    }

    @Test func menusAskedForTogetherOpenOneAfterAnother() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme", recordPick)
            tx.popupMenu(makeThemeMenu("dark"), "theme", recordPick)
        }
        rt.hostOpenPopupHeadless()
        #expect(voidOk(rt.hostResolvePopup(nil)))
        #expect(rt.hostPopupMenu() == makeThemeMenu("dark"))
        #expect(!rt.hostPopupOpen)
        rt.hostOpenPopupHeadless()
        #expect(voidOk(rt.hostResolvePopup("light")))
        #expect(rt.state.picks == [nil, Optional("light")])
    }

    @Test func aPickCanAskForTheNextMenu() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme") { (s: inout PopupTestState, picked: String?, tx: inout Tx) in
                recordPick(&s, picked, &tx)
                tx.popupMenu(makeThemeMenu("dark"), "theme", recordPick)
            }
        }
        rt.hostOpenPopupHeadless()
        #expect(voidOk(rt.hostResolvePopup("dark")))
        #expect(rt.hostPopupMenu() == makeThemeMenu("dark"))
    }

    @Test func clonesOfATxShareOneRequest() {
        var tx = Tx()
        tx.popupMenu(makeThemeMenu("system"), "theme", recordPick)
        var clone = tx
        let first = clone.drainSidecar(as: PopupMenuCallBox.self)
        #expect(first.count == 1)
        #expect(first[0].take() != nil)
        let second = tx.drainSidecar(as: PopupMenuCallBox.self)
        #expect(second.isEmpty)
    }

    @Test func theTreeJsonShowsTheOpenMenu() {
        let rt = makePopupRuntime()
        #expect(rt.hostPopupJson() == nil)
        guard case .success(let sc) = Shortcut.parse("super+c") else {
            Issue.record("parse failed")
            return
        }
        rt.hostUpdate { _, tx in
            let m = PopupMenu.new()
                .item(PopupItem.new("copy", "Copy").checked(true).symbol("doc.on.doc").keyEquivalent(sc))
                .separator()
            tx.popupMenu(m, (3.0, 4.0), recordPick)
        }
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme", recordPick)
        }
        rt.hostOpenPopupHeadless()
        guard let menuJson = rt.hostPopupJson() else {
            Issue.record("Expected popup json")
            return
        }
        #expect(menuJson["open"] as? Bool == true)
        #expect(menuJson["queued"] as? Int == 1)
        let anchor = menuJson["anchor"] as? [String: Float]
        #expect(anchor?["x"] == 3.0 && anchor?["y"] == 4.0)
        let items = menuJson["items"] as? [[String: Any]]
        #expect(items?[0]["id"] as? String == "copy")
        #expect(items?[0]["checked"] as? Bool == true)
        #expect(items?[0]["symbol"] as? String == "doc.on.doc")
        #expect(items?[0]["keyEquivalent"] is String)
        #expect(items?[1]["separator"] as? Bool == true)
    }

    @Test func aWindowGoingAwayAnswersEveryWaitingMenuNoneOnce() {
        let rt = makePopupRuntime()
        let presenter = PopupPresenter()
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme", recordPick)
            tx.popupMenu(makeThemeMenu("dark"), "theme") { (s: inout PopupTestState, picked: String?, tx: inout Tx) in
                recordPick(&s, picked, &tx)
                tx.popupMenu(makeThemeMenu("light"), "theme", recordPick)
            }
        }
        rt.hostOpenPopupHeadless()
        let showing = PopupSession()
        presenter.session = showing
        presenter.cancel(rt)
        #expect(rt.state.picks == [nil, nil, nil])
        #expect(rt.hostPopupMenu() == nil)
        #expect(!rt.hostPopupOpen)
        #expect(showing.cancelled)

        showing.answer = .some("dark")
        #expect(!presenter.answer(rt))
        presenter.cancel(rt)
        #expect(rt.state.picks == [nil, nil, nil])
    }

    @Test func aCallbackThatAlwaysAsksAgainCannotHoldAClosingWindow() {
        func askAgain(_ s: inout PopupTestState, _ picked: String?, _ tx: inout Tx) {
            recordPick(&s, picked, &tx)
            tx.popupMenu(makeThemeMenu("system"), "theme", askAgain)
        }
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme", askAgain)
        }
        rt.hostCancelPopups()
        #expect(rt.state.picks.count == 64)
        #expect(rt.hostPopupMenu() == nil)
    }

    @Test func aMenuAPickAsksForWaitsForTheElementThePickMounts() {
        let rt = makePopupRuntime()
        rt.hostUpdate { _, tx in
            tx.popupMenu(makeThemeMenu("system"), "theme") { (s: inout PopupTestState, picked: String?, tx: inout Tx) in
                recordPick(&s, picked, &tx)
                s.extra = true
                tx.popupMenu(makeThemeMenu("dark"), "extra", recordPick)
            }
        }
        hostAttachment(for: rt).dirtyFromHost = false
        #expect(!rt.hostPopupWaitsForLayout())
        rt.hostOpenPopupHeadless()
        #expect(voidOk(rt.hostResolvePopup("dark")))
        #expect(rt.hostPopupWaitsForLayout())
        // Simulate next commit mounting "extra"
        popupState(for: rt).anchorRectOverrides["extra"] = [150.0, 5.0, 30.0, 10.0]
        _ = rt.frame(0.0)
        hostAttachment(for: rt).dirtyFromHost = false
        #expect(!rt.hostPopupWaitsForLayout())
        guard let maybeShow = rt.hostTakePopup(), let show = maybeShow else {
            Issue.record("Expected PopupShow for mounted extra")
            return
        }
        #expect(show.at.0 == 150.0 && show.at.1 == 5.0 && show.minWidth == 30.0)
        #expect(rt.state.picks == [Optional("dark")])
    }

    @Test func supportIsMacosOnly() {
        #if os(macOS)
        #expect(popupMenuSupported() == true)
        #else
        #expect(popupMenuSupported() == false)
        #endif
    }
}
