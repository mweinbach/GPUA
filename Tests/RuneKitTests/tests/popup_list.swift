// Tests ported from: crates/rune-kit/tests/popup_list.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private typealias PopupItem = RuneKit.PopupItem

private struct PopupListState {
    var composer: TextEdit = TextEdit()
    var open: Bool = false
    var count: Int = 0
    var active: Int? = nil
    var hovered: [Int] = []
    var chosen: [String] = []
    var animate: Bool = false
}

private func cmdLabel(_ i: Int) -> String {
    let digits = "\(i)"
    let pad = String(repeating: "0", count: max(0, 2 - digits.count)) + digits
    return "/command-\(pad)"
}

private func popupItemFor(_ k: Kit, _ i: Int) -> PopupItem {
    PopupItem.new("cmd-\(i)", cmdLabel(i))
        .description("Action \(i)")
        .leading(icon(glyphs.SPARKLE, 14.0).color(k.c.iconMuted))
        .trailing(text("⏎").font(k.ty.smallMedium).color(k.c.textFaint))
        .disabled(i == 1)
}

private func popupListView(_ s: PopupListState, _: Cx<PopupListState>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    let field = TextInput.new(s.composer)
        .placeholder("Type a command\u{2026}")
        .animateEditLayout()
        .onEdit(\PopupListState.composer)
        .onKey { (s: inout PopupListState, ev, _) in
            switch ev.key {
            case .down:
                if s.count > 0 {
                    s.active = ((s.active ?? 0) + 1) % s.count
                }
                return true
            case .up:
                if s.count > 0 {
                    let cur = s.active ?? 0
                    s.active = cur > 0 ? (cur - 1) : (s.count - 1)
                }
                return true
            default:
                return false
            }
        }
        .build(k)
        .key("composer")
    let items: [PopupItem] = (0..<s.count).map { i in popupItemFor(k, i) }
    PopupList<PopupListState>.new("commands", "composer")
        .anchored("composer", .bottom, .start, 4.0)
        .open(s.open)
        .animateFiltering(s.animate)
        .items(items)
        .active(s.active)
        .emptyMessage("No matching commands")
        .label("Commands")
        .onActive { s, i in
            s.active = i
            s.hovered.append(i)
        }
        .onChoose { s, id, _ in
            s.chosen.append(id)
        }
        .build(k, &layer)
    return root(col().padding(16.0).child(field), layer)
}

private func makePopupRuntime(_ count: Int) -> Runtime<PopupListState> {
    var composer = TextEdit.new("")
    composer.focused = true
    let s = PopupListState(
        composer: composer,
        open: true,
        count: count,
        active: 0
    )
    let rt = Runtime.new(s, popupListView, (480.0, 480.0), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    return rt
}

@Suite("PopupListTests")
struct PopupListTests {
    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func optionChanges5203SpringHeightFadeRowsAndToggleEmptyState() {
        let rt = makePopupRuntime(5)
        rt.update { s, _ in s.animate = true }
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        func find(_ rt: Runtime<PopupListState>, _ key: String) -> ElementInfo? {
            rt.elements().first(where: { $0.key == key })
        }
        let h5 = find(rt, "commands-content")!.rect[3]
        #expect(find(rt, "empty")!.opacity == 0.0)
        #expect(find(rt, "empty")!.rect[3] == 0.0)

        // 5 -> 2 items: height springs down and removed rows fade out.
        rt.update { s, _ in s.count = 2 }
        _ = rt.frame(1.0 / 60.0)
        guard let fading = find(rt, "commands-option-cmd-4") else {
            Issue.record("removed row stays mounted while fading out")
            return
        }
        #expect(fading.opacity > 0.0 && fading.opacity < 1.0, "row opacity \(fading.opacity)")
        let mid5To2 = find(rt, "commands-content")!.rect[3]
        #expect(mid5To2 < h5 && mid5To2 > 64.0, "height springs from \(h5), got \(mid5To2)")
        var last = mid5To2
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
            let h = find(rt, "commands-content")!.rect[3]
            #expect(abs(h - last) < 25.0, "popup height jumped \(last) -> \(h)")
            last = h
        }
        let h2 = last
        #expect(abs(h2 - 64.0) < 1.0, "settled 2-item height \(h2)")
        #expect(find(rt, "empty")!.opacity == 0.0)

        // 2 -> 0 items: height springs to empty state and empty message becomes visible.
        rt.update { s, _ in s.count = 0 }
        _ = rt.frame(1.0 / 60.0)
        #expect(find(rt, "empty")!.opacity > 0.0)
        let mid2To0 = find(rt, "commands-content")!.rect[3]
        #expect(mid2To0 < h2 && mid2To0 > 36.0, "height springs from \(h2) toward empty, got \(mid2To0)")
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        let h0 = find(rt, "commands-content")!.rect[3]
        #expect(abs(h0 - 36.0) < 1.0, "settled empty height \(h0)")
        #expect(find(rt, "empty")!.opacity == 1.0)
        #expect(abs(find(rt, "empty")!.rect[3] - 28.0) < 1.0)

        // 0 -> 3 items: height springs back up and empty state hides.
        rt.update { s, _ in
            s.count = 3
            s.active = 0
        }
        _ = rt.frame(1.0 / 60.0)
        #expect(find(rt, "empty")!.opacity < 1.0)
        let mid0To3 = find(rt, "commands-content")!.rect[3]
        #expect(mid0To3 > h0 && mid0To3 < 92.0, "height springs from \(h0) toward 3 items, got \(mid0To3)")
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        let h3 = find(rt, "commands-content")!.rect[3]
        #expect(abs(h3 - 92.0) < 1.0, "settled 3-item height \(h3)")
        #expect(find(rt, "empty")!.opacity == 0.0)
    }

    /// By default a change to the rows lands in its frame, though the composer's edits animate the
    /// layout, while opening, closing and the hover highlight keep their motion.
    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func optionChangesLandAtOnceByDefault() {
        func find(_ rt: Runtime<PopupListState>, _ key: String) -> ElementInfo? {
            rt.elements().first(where: { $0.key == key })
        }
        let rt = makePopupRuntime(5)
        rt.update { s, _ in s.open = false }
        _ = rt.frame(1.0 / 60.0)
        rt.update { s, _ in s.open = true }
        _ = rt.frame(1.0 / 60.0)
        let opening = find(rt, "commands-content")!
        #expect(opening.opacity < 1.0 || opening.scale < 1.0, "the popover enters: \(opening.opacity) at \(opening.scale)")
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }

        let steps: [(Int, Float)] = [(2, 64.0), (0, 36.0), (3, 92.0)]
        for (count, height) in steps {
            // The composer's text changes too, in a commit that animates its layout.
            _ = rt.keyDown(KeyEvent(key: .text("x")))
            rt.update { s, _ in
                s.count = count
                s.active = count > 0 ? 0 : nil
            }
            _ = rt.frame(1.0 / 60.0)
            let h = find(rt, "commands-content")!.rect[3]
            #expect(abs(h - height) < 0.05, "\(count) rows: \(h)")
            #expect(rt.elements().allSatisfy { !$0.exiting }, "\(count) rows: nothing is left fading out")
            for i in 0..<count {
                #expect(find(rt, "commands-option-cmd-\(i)")!.opacity == 1.0, "row \(i) is whole")
            }
            let empty = find(rt, "empty")!
            #expect(empty.opacity == (count == 0 ? 1.0 : 0.0))
        }

        let row = find(rt, "commands-option-cmd-2")!.rect
        func fill(_ rt: Runtime<PopupListState>) -> Float {
            find(rt, "commands-option-cmd-2")!.fill.a
        }
        rt.pointerMove(row[0] + 10.0, row[1] + 10.0)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.active == 2)
        let hovered = fill(rt)
        _ = rt.frame(1.0 / 60.0)
        #expect(fill(rt) > hovered, "the highlight still eases in: \(hovered) -> \(fill(rt))")

        rt.update { s, _ in s.open = false }
        _ = rt.frame(1.0 / 60.0)
        guard let closing = find(rt, "commands-content") else {
            Issue.record("the popover is still closing")
            return
        }
        #expect(
            closing.exiting && (closing.opacity < 1.0 || closing.scale < 1.0),
            "it leaves: \(closing.opacity) at \(closing.scale)"
        )
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func activeIndexScrollsIntoViewAndUpdatesListboxAccessibility() {
        let rt = makePopupRuntime(40)
        func find(_ rt: Runtime<PopupListState>, _ key: String) -> ElementInfo? {
            rt.elements().first(where: { $0.key == key })
        }
        let listbox = find(rt, "viewport")!
        #expect(listbox.role == "listbox")
        #expect(listbox.label == "Commands")
        let first = find(rt, "commands-option-cmd-0")!
        #expect(first.role == "option")
        #expect(first.itemSelected)

        // Moving active to the last item (via Up key in the outside field) reveals the offscreen row.
        _ = rt.keyDown(KeyEvent(key: .up))
        _ = rt.frame(0.0)
        #expect(rt.state.active == 39)
        guard let last = find(rt, "commands-option-cmd-39") else {
            Issue.record("active virtual row is mounted and revealed")
            return
        }
        #expect(last.visible[3] > 0.0, "last row visible rect \(last.visible)")
        #expect(last.itemSelected)
        let updatedListbox = find(rt, "viewport")!
        #expect(updatedListbox.label == "Commands")
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func hoverFiresOnActiveClickFiresOnChooseAndOutsideTextEditKeepsFocus() {
        let rt = makePopupRuntime(5)
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        // Typing while open goes straight to the outside TextEdit without moving focus into the popup.
        _ = rt.keyDown(KeyEvent(key: .text("/re")))
        _ = rt.frame(0.0)
        #expect(rt.state.composer.text == "/re")
        #expect(rt.state.composer.focused)
        #expect(rt.elements().filter { $0.role == "option" }.allSatisfy { !$0.focusable && !$0.focused })

        // Hovering option 2 fires onActive(s, 2).
        let (x2, y2) = rt.find("commands-option-cmd-2")!
        rt.pointerMove(x2, y2)
        _ = rt.frame(0.0)
        #expect(rt.state.hovered == [2])
        #expect(rt.state.active == 2)
        #expect(rt.elements().first(where: { $0.key == "viewport" })?.label == "Commands")

        // Clicking disabled option 1 neither chooses nor blurs the outside TextEdit.
        let (x1, y1) = rt.find("commands-option-cmd-1")!
        _ = rt.pointerDown(x1, y1)
        rt.pointerUp(x1, y1)
        _ = rt.frame(0.0)
        #expect(rt.state.chosen.isEmpty)
        #expect(rt.state.composer.focused)

        // Clicking enabled option 2 fires onChoose and leaves focus in the outside TextEdit so typing continues.
        _ = rt.pointerDown(x2, y2)
        rt.pointerUp(x2, y2)
        _ = rt.frame(0.0)
        #expect(rt.state.chosen == ["cmd-2"])
        #expect(rt.state.composer.focused)
        _ = rt.keyDown(KeyEvent(key: .text("view")))
        _ = rt.frame(0.0)
        #expect(rt.state.composer.text == "/review")
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func hoverChangesDoNotScrollNowOrOnTheNextFrame() {
        let rt = makePopupRuntime(40)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        let row = rt.elements().first(where: { $0.key == "commands-option-cmd-8" })!
        let (x, y) = (row.visible[0] + 10.0, row.visible[1] + 2.0)
        let before = row.rect
        rt.pointerMove(x, y)
        _ = rt.frame(0.0)
        #expect(rt.state.active == 8)
        for _ in 0..<3 { _ = rt.frame(1.0 / 60.0) }
        let after = rt.elements().first(where: { $0.key == "commands-option-cmd-8" })!.rect
        #expect(before == after, "hovering a partly clipped row must not reveal it")
        #expect(rt.state.hovered == [8])
    }

    @Test
    func pressingPopupPaddingOrEmptyStateKeepsTheComposerFocused() {
        for count in [0, 3] {
            let rt = makePopupRuntime(count)
            for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
            let popup = rt.elements().first(where: { $0.key == "commands-content" })!.rect
            let (x, y) = (popup[0] + 1.0, popup[1] + 1.0)
            _ = rt.pointerDown(x, y)
            rt.pointerUp(x, y)
            _ = rt.frame(0.0)
            #expect(rt.state.composer.focused, "padding, count \(count)")
            if count == 0 {
                let (ex, ey) = rt.find("empty")!
                _ = rt.pointerDown(ex, ey)
                rt.pointerUp(ex, ey)
                _ = rt.frame(0.0)
                #expect(rt.state.composer.focused, "empty state")
            }
        }
    }

    // PORT NOTE: Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal.
    @Test(.disabled("Blocked on Sources/Rune GrowthSpec height spring, El.controls focus preservation & virtual scroll reveal"))
    func ordinaryListboxSelectionDoesNotRevealAndPressStillBlurs() {
        func ordinary(_ s: PopupListState, _: Cx<PopupListState>) -> El {
            let k = Kit.neutral(true)
            return col()
                .child(TextInput.new(s.composer).onEdit(\PopupListState.composer).build(k))
                .child(
                    col()
                        .key("ordinary-list")
                        .role("listbox")
                        .h(100.0)
                        .scroll(ScrollSpec(stickBottom: false))
                        .child(
                            col()
                                .growth(GrowthSpec())
                                .virtualize(28.0)
                                .children((0..<40).map { (i: Int) -> El in
                                    el()
                                        .key("row-\(i)")
                                        .role("option")
                                        .h(28.0)
                                        .focusSelected(s.active == i)
                                        .onPress { (_: inout PopupListState) in }
                                })
                        )
                )
        }
        var s = PopupListState()
        s.composer.focused = true
        s.active = 39
        let rt = Runtime.new(s, ordinary, (480.0, 480.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        func first(_ rt: Runtime<PopupListState>) -> ElementInfo {
            rt.elements().first(where: { $0.key == "row-0" })!
        }
        #expect(first(rt).visible[3] > 0.0, "restoring selection must not scroll")
        rt.update { s, _ in s.active = 38 }
        _ = rt.frame(0.0)
        #expect(first(rt).visible[3] > 0.0, "programmatic selection must not scroll")
        let (x, y) = rt.find("row-0")!
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(0.0)
        #expect(!rt.state.composer.focused, "ordinary listbox presses still blur the field")
    }
}
