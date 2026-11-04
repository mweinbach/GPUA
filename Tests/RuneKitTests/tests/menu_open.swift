// Tests ported from: crates/rune-kit/tests/menu_open.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct MenuOpenState {
    var open: Bool = false
    var sub: Bool = false
}

private func menuOpenView(_ s: MenuOpenState, _: Cx<MenuOpenState>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    let body = Menu.new("file")
        .trigger(text("File"))
        .item(MenuItem.new("Copy"))
        .item(MenuItem.new("More").submenu([MenuEntry.item(MenuItem.new("Deeper"))], s.sub))
        .open(s.open)
        .build(k, &layer)
    return root(col().wFull().hFull().child(body), layer)
}

private func menuSurface<S>(_ rt: Runtime<S>, _ key: String) -> ElementInfo? {
    rt.elements().first(where: { $0.key == key })
}

@Suite("MenuOpenTests")
struct MenuOpenTests {
    @Test
    func menusAndSubmenusOpenOnTheNextFrameAndFadeOnlyOnClose() {
        let rt = Runtime.new(MenuOpenState(), menuOpenView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.update { s, _ in s.open = true }
        _ = rt.frame(1.0 / 120.0)
        let menu = menuSurface(rt, "file-menu")!
        #expect(menu.opacity == 1.0, "menu fades in")
        #expect(menu.rect == menu.target, "menu scales in")
        let (x, y) = rt.find("file-item0")!
        rt.pointerMove(x, y)
        _ = rt.frame(1.0 / 120.0)
        #expect(menuSurface(rt, "file-item0")!.hover == 1.0, "item highlight lands on arrival")

        rt.update { s, _ in s.sub = true }
        _ = rt.frame(1.0 / 120.0)
        let sub = menuSurface(rt, "file-item1-sub-menu")!
        #expect(sub.opacity == 1.0, "submenu fades in")
        #expect(sub.rect == sub.target, "submenu scales in")

        rt.update { s, _ in
            s.open = false
            s.sub = false
        }
        _ = rt.frame(1.0 / 120.0)
        _ = rt.frame(0.1)
        guard let closing = menuSurface(rt, "file-menu") else {
            Issue.record("menu fades out instead of vanishing")
            return
        }
        #expect(closing.opacity > 0.0 && closing.opacity < 1.0, "closing opacity \(closing.opacity)")
        #expect(closing.rect[2] == closing.target[2], "close fades without scaling")
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        #expect(menuSurface(rt, "file-menu") == nil)
    }
}
