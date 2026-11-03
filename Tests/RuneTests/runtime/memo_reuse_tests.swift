// Tests ported from: crates/rune/src/runtime/memo_reuse_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import RuneMotion
import Testing
@testable import Rune

@Suite("MemoReuseTests")
struct MemoReuseTests {
    private struct CardsState {
        var useMemo: Bool
        var bannerH: Float = 24.0
        var tick: UInt32 = 0
        var cardVer: [UInt32] = [0, 0, 0, 0]
        var showCard: [Bool] = [true, true, true, true]
        var swapOrder: Bool = false
        var dimFirst: Bool = false
    }

    private static func maybeMemo<V: Hashable>(_ useMemo: Bool, _ id: String, _ ver: V, _ build: () -> El) -> El {
        if useMemo {
            return memo(id, ver, build)
        }
        return build().key(id)
    }

    private static func buildCard(_ i: Int, _ ver: UInt32, _ useMemo: Bool) -> El {
        let head = row().key("head").wFull().gap(8.0).itemsCenter().children([
            rtGroupOpacity(el().key("badge").size(10.0, 10.0).rounded(5.0).bg(Color(r: 0.3, g: 0.7, b: 0.9, a: 1.0)), 0.6),
            text("Card \(i) v\(ver)").key("title").font(TextStyle.new(14.0, 600.0)).color(.WHITE).grow(1.0).shrink().truncate(),
            maybeMemo(useMemo, "nested-pill", ver) {
                row().pad(4.0).rounded(4.0).bg(Color.WHITE.alpha(0.08))
                    .child(text("#\(ver)").key("v").font(TextStyle.new(11.0, 500.0)))
            },
        ])
        var card = rtHoverGroup(
            col().wFull().pad(10.0).gap(6.0).rounded(8.0)
                .bg(Color(r: 0.12, g: 0.14, b: 0.18, a: 1.0))
                .border(1.0, Color.WHITE.alpha(0.15))
                .hover(Color.WHITE.alpha(0.06))
                .press(Color.WHITE.alpha(0.12))
                .focusable(true)
                .onPress { (s: inout CardsState, _) in s.tick += UInt32(i + 1) }
                .transition(Transition.opacity())
        )
        .child(head)
        .child(rtSelectable(text("Body copy for card \(i) v\(ver)").key("desc").wFull()))

        if ver % 2 == 0 {
            card = card.child(
                text("Optional footer note").key("footer")
                    .font(TextStyle.new(11.0, 400.0))
                    .color(Color.WHITE.alpha(0.6))
                    .transition(Transition.opacity())
            )
        }
        return card
    }

    private static func cardsView(_ s: CardsState, _ cx: Cx<CardsState>) -> El {
        let indices = s.swapOrder ? [2, 1, 0, 3] : [0, 1, 2, 3]
        var kids: [El] = []
        for i in indices where s.showCard[i] {
            let ver = s.cardVer[i]
            var c = maybeMemo(s.useMemo, "card-\(i)", ver) { buildCard(i, ver, s.useMemo) }
            if i == 0 && s.dimFirst {
                c = c.opacity(0.45)
            }
            kids.append(c)
        }
        return rtSelectionGroup(col().wFull().hFull().pad(12.0).gap(8.0)).children([
            el().key("banner").wFull().h(s.bannerH).rounded(6.0).bg(cx.accent()),
            text("tick \(s.tick)").key("tick").font(TextStyle.new(12.0, 400.0)),
            col().key("list").wFull().grow(1.0).minH(0.0).gap(8.0).children(kids),
        ])
    }

    private func assertSameState(_ a: Runtime<CardsState>, _ b: Runtime<CardsState>, step: String) {
        #expect(a.nodes.count == b.nodes.count, "\(step): node count")
        for (na, nb) in zip(a.nodes, b.nodes) {
            #expect(na.nodeId == nb.nodeId, "\(step): nodeId \(na.path)")
            #expect(na.path == nb.path, "\(step): path")
            #expect(na.localRect == nb.localRect, "\(step): localRect \(na.path)")
            #expect(na.layoutRect == nb.layoutRect, "\(step): layoutRect \(na.path)")
            #expect(na.vis.opacity == nb.vis.opacity, "\(step): opacity \(na.path)")
            #expect(na.textSpec?.content == nb.textSpec?.content, "\(step): text \(na.path)")
        }
        let ea = a.elements()
        let eb = b.elements()
        #expect(ea.count == eb.count, "\(step): elements count")
        for (ia, ib) in zip(ea, eb) {
            #expect(ia.path == ib.path)
            #expect(ia.rect == ib.rect)
            #expect(ia.focused == ib.focused)
            #expect(ia.exiting == ib.exiting)
        }
        #expect(a.instances == b.instances, "\(step): instances")
    }

    @Test("Memo-reusing builds match fresh un-memoized builds across steady commits, ancestor moves, reorder, exits, and env updates")
    func memoBuildsMatchFreshBuilds() {
        let rtM = Runtime.new(CardsState(useMemo: true), Self.cardsView, (560.0, 520.0), Env.new(true, 2.0))
        let rtF = Runtime.new(CardsState(useMemo: false), Self.cardsView, (560.0, 520.0), Env.new(true, 2.0))

        func stepBoth(_ dt: Double, _ label: String, _ op: (Runtime<CardsState>) -> Void = { _ in }) {
            op(rtM)
            op(rtF)
            _ = rtM.frame(dt)
            _ = rtF.frame(dt)
            #expect(rtM.animating == rtF.animating, "\(label): animating mismatch")
            assertSameState(rtM, rtF, step: label)
        }

        stepBoth(0.0, "initial")

        // Steady ticks reuse memoized cards cleanly
        for k in 0..<4 {
            stepBoth(1.0 / 120.0, "steady-\(k)") { rt in rt.update { s, _ in s.tick += 1 } }
        }

        // Ancestor move + reorder + caller root modifier
        stepBoth(1.0 / 120.0, "banner-grow") { rt in rt.update { s, _ in s.bannerH = 68.0 } }
        for f in 0..<15 {
            stepBoth(1.0 / 120.0, "banner-spring-\(f)")
        }
        stepBoth(1.0 / 120.0, "reorder") { rt in rt.update { s, _ in s.swapOrder = true; s.dimFirst = true } }

        // Child exit + card exit + revive
        stepBoth(1.0 / 60.0, "exits-begin") { rt in
            rt.update { s, _ in
                s.cardVer[2] += 1
                s.showCard[1] = false
            }
        }
        for f in 0..<20 {
            stepBoth(1.0 / 60.0, "exits-step-\(f)")
        }
        stepBoth(1.0 / 60.0, "revive") { rt in rt.update { s, _ in s.showCard[1] = true } }

        // Hover, press, Tab focus, selection, and env changes
        let (cx, cy) = rtM.find("card-0")!
        stepBoth(1.0 / 120.0, "hover") { rt in rt.pointerMove(cx, cy) }
        stepBoth(1.0 / 120.0, "press-down") { rt in rt.pointerDown(cx, cy) }
        stepBoth(1.0 / 120.0, "press-up") { rt in rt.pointerUp(cx, cy) }
        stepBoth(1.0 / 120.0, "tab") { rt in _ = rt.key(.tab) }
        stepBoth(1.0 / 60.0, "dark-false") { rt in rt.setSystemDark(false) }
        stepBoth(1.0 / 60.0, "reduced-motion") { rt in rt.setSystemReducedMotion(true) }
    }
}
