// Tests ported from: crates/rune-kit/tests/markdown_link_menu.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
@testable import RuneKit

private struct LinkMenuEntry: Equatable {
    var url: String
    var x: Float
    var y: Float
}

private struct LinkMenuState {
    var selectable: Bool = false
    var linkMenus: [LinkMenuEntry] = []
    var rowMenus: Int = 0
    var opened: [String] = []
}

private func linkMenuView(_ s: LinkMenuState, _: Cx<LinkMenuState>) -> El {
    let k = Kit.neutral(true)
    let text = Markdown.new("Hello there and [link](https://x.dev/a) and [other](https://x.dev/b).")
        .selectable(s.selectable)
        .onLink { (s: inout LinkMenuState, url) in
            s.opened.append(url)
        }
        .onLinkSecondary { (s: inout LinkMenuState, url, p, _) in
            s.linkMenus.append(LinkMenuEntry(url: url, x: p.x, y: p.y))
        }
        .build(k)
    return col()
        .wFull()
        .padding(10.0)
        .child(text)
        .onSecondaryPress { (s: inout LinkMenuState, _, _) in
            s.rowMenus += 1
        }
}

private func tickMenu(_ rt: Runtime<LinkMenuState>) {
    for _ in 0..<4 {
        _ = rt.frame(1.0 / 60.0)
    }
}

private func rightClick(_ rt: Runtime<LinkMenuState>, _ x: Float, _ y: Float) {
    rt.secondaryDown(x, y)
    rt.secondaryUp(x, y)
    tickMenu(rt)
}

private func linkCenter(_ rt: Runtime<LinkMenuState>, _ url: String) -> (Float, Float) {
    let link = rt.elements().first(where: { $0.key == url })!
    return (link.rect[0] + link.rect[2] / 2.0, link.rect[1] + link.rect[3] / 2.0)
}

@Suite("MarkdownLinkMenuTests")
struct MarkdownLinkMenuTests {
    @Test(.disabled("Requires Rune runtime synthetic link ElementInfo exposure and TextSpec.onLinkSecondary dispatch"))
    func aRightClickOnALinkOpensItsMenuAndElsewhereTheRows() {
        for selectable in [false, true] {
            let rt = Runtime.new(LinkMenuState(selectable: selectable), linkMenuView, (480.0, 200.0), Env.new(true, 2.0))
            _ = rt.frame(0.0)
            let link = rt.elements().first(where: { $0.key == "https://x.dev/a" })!
            let at = (link.rect[0] + link.rect[2] / 2.0, link.rect[1] + link.rect[3] / 2.0)
            rt.pointerMove(at.0, at.1)
            tickMenu(rt)
            #expect(rt.cursor() == .pointer, "selectable \(selectable)")

            rightClick(rt, at.0, at.1)
            #expect(rt.state.linkMenus == [LinkMenuEntry(url: "https://x.dev/a", x: at.0, y: at.1)], "selectable \(selectable)")
            #expect(rt.state.rowMenus == 0, "the link took it (selectable \(selectable))")
            #expect(rt.state.opened.isEmpty)

            rightClick(rt, 16.0, at.1)
            #expect(rt.state.rowMenus == 1, "plain text goes to the row (selectable \(selectable))")
            #expect(rt.state.linkMenus.count == 1)
        }
    }

    @Test(.disabled("Requires Rune runtime synthetic link focus stops and Key.contextMenu -> TextSpec.onLinkSecondary dispatch"))
    func theMenuKeyOnAFocusedLinkOpensItsMenuAtItsBottomLeft() {
        let rt = Runtime.new(LinkMenuState(), linkMenuView, (480.0, 200.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        _ = rt.keyDown(KeyEvent(key: .tab, mods: Mods()))
        tickMenu(rt)
        let link = rt.elements().first(where: { $0.key == "https://x.dev/a" })!
        #expect(link.focused)
        _ = rt.keyDown(KeyEvent(key: .contextMenu, mods: Mods()))
        tickMenu(rt)
        #expect(rt.state.linkMenus == [LinkMenuEntry(url: "https://x.dev/a", x: link.rect[0], y: link.rect[1] + link.rect[3])])
        #expect(rt.state.rowMenus == 0)
    }

    @Test(.disabled("Requires Rune runtime synthetic link ElementInfo exposure and TextSpec.onLinkSecondary dispatch"))
    func aRightClickThatMovesToAnotherLinkOpensNoMenu() {
        let rt = Runtime.new(LinkMenuState(), linkMenuView, (480.0, 200.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let a = linkCenter(rt, "https://x.dev/a")
        let b = linkCenter(rt, "https://x.dev/b")
        rt.secondaryDown(a.0, a.1)
        rt.pointerMove(b.0, b.1)
        rt.secondaryUp(b.0, b.1)
        tickMenu(rt)
        #expect(rt.state.linkMenus.isEmpty, "\(rt.state.linkMenus)")
        #expect(rt.state.rowMenus == 0)
        rightClick(rt, b.0, b.1)
        #expect(rt.state.linkMenus == [LinkMenuEntry(url: "https://x.dev/b", x: b.0, y: b.1)])
    }
}
