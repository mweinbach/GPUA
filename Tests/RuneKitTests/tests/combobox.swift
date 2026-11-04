// Tests ported from: crates/rune-kit/tests/combobox.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct ComboTestState {
    var combo: ComboboxState = ComboboxState()
    var chosen: String? = nil
    var chooses: Int = 0
    var other: TextEdit = TextEdit()
    var appKeys: Int = 0
    var animate: Bool = false
}

private func modelLabel(_ i: Int) -> String {
    let digits = "\(i)"
    let pad = String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    return "Model \(pad)"
}

private func comboTestView(_ s: ComboTestState, _: Cx<ComboTestState>) -> El {
    let options: [ComboboxOption] = (0..<200).map { i in
        var o = ComboboxOption.new("item-\(i)", modelLabel(i))
        o.disabled = i == 1
        return o
    }
    var layer: [El] = []
    let body = Combobox.new("models", s.combo, options, \ComboTestState.combo)
        .current(s.chosen)
        .animateFiltering(s.animate)
        .onChoose { s, id, _ in
            s.chosen = id
            s.chooses += 1
        }
        .build(Kit.neutral(true), &layer)
    let page = Rune.col()
        .child(
            TextInput.new(s.other)
                .onEdit(\ComboTestState.other)
                .build(Kit.neutral(true))
                .key("other")
        )
        .child(body)
    return RuneKit.root(page, layer)
}

private func makeOpenRuntime(_ s: ComboTestState) -> Runtime<ComboTestState> {
    var state = s
    state.combo.open = true
    state.combo.search.focused = true
    let rt = Runtime.new(state, comboTestView, (400.0, 400.0), Env.new(true, 1.0))
    _ = rt.frame(0.0)
    return rt
}

private func makeRuntime() -> Runtime<ComboTestState> {
    makeOpenRuntime(ComboTestState())
}

private func makeAnimatedRuntime() -> Runtime<ComboTestState> {
    makeOpenRuntime(ComboTestState(animate: true))
}

private func sendKey(_ rt: Runtime<ComboTestState>, _ key: Key, _ mods: Mods = Mods()) {
    _ = rt.keyDown(KeyEvent(key: key, mods: mods))
    _ = rt.frame(0.0)
}

private func comboTallView(_ s: ComboTestState, _: Cx<ComboTestState>) -> El {
    let options: [ComboboxOption] = (0..<200).map { i in
        ComboboxOption.new("item-\(i)", modelLabel(i))
    }
    var layer: [El] = []
    let trigger = Rune.row().key("custom").size(120.0, 28.0).child(Rune.text("Pick"))
    let body = Combobox.new("models", s.combo, options, \ComboTestState.combo)
        .trigger(trigger)
        .maxHeight(2000.0)
        .build(Kit.neutral(true), &layer)
    return RuneKit.root(Rune.col().pt(40.0).child(Rune.row().child(body)), layer)
}

@Suite("ComboboxTests")
struct ComboboxTests {
    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func openingTakesFocusAndRevealsTheOffscreenSelection() {
        var s = ComboTestState()
        s.other.focused = true
        s.chosen = "item-199"
        let rt = Runtime.new(s, comboTestView, (400.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        _ = rt.ime(.preedit("pending", nil))
        _ = rt.frame(0.0)
        let trigger = rt.elements().first(where: { $0.key == "models-value-trigger" })!
        let x = trigger.rect[0] + trigger.rect[2] / 2.0
        let y = trigger.rect[1] + trigger.rect[3] / 2.0
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(0.0)
        #expect(rt.state.combo.open && rt.state.combo.search.focused)
        #expect(!rt.state.other.focused)
        #expect(rt.state.other.preedit == nil)
        let last = rt.elements().first(where: { $0.key == "models-option-item-199" })!
        #expect(last.visible[3] > 0.0)
        sendKey(rt, .text("099"))
        #expect(rt.state.combo.search.text == "099")
        #expect(rt.state.other.text == "")
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func closingAScrolledVirtualPopupKeepsRowsInPlaceWhileFading() {
        let rt = makeRuntime()
        sendKey(rt, .up)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        let before = rt.elements().first(where: { $0.key == "models-option-item-199" })!
        sendKey(rt, .escape)
        _ = rt.frame(1.0 / 60.0)
        let after = rt.elements().first(where: { $0.key == before.key })!
        #expect(abs(after.rect[1] - before.rect[1]) < 5.0, "row jumped: \(before.rect) -> \(after.rect)")
        #expect(after.opacity > 0.0 && after.opacity < before.opacity)
        #expect(after.visible[3] > 0.0)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func comboboxLoopsSkipsDisabledAndScrollsVirtualRowsIntoView() {
        let rt = makeRuntime()
        #expect(rt.elements().filter { $0.role == "option" }.count < 50)
        sendKey(rt, .down)
        #expect(rt.state.combo.active == "item-2")
        sendKey(rt, .up)
        sendKey(rt, .up)
        #expect(rt.state.combo.active == "item-199")
        let last = rt.elements().first(where: { $0.key == "models-option-item-199" })!
        #expect(last.visible[3] > 0.0)
        sendKey(rt, .enter)
        #expect(rt.state.chosen == "item-199")
        #expect(!rt.state.combo.open)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func comboboxFiltersFromScrollEndPreservesEditorModifiersAndIme() {
        let rt = makeRuntime()
        sendKey(rt, .up)
        sendKey(rt, .text("099"))
        #expect(rt.elements().contains(where: { $0.key == "models-option-item-99" }))
        #expect(rt.state.combo.search.text == "099")
        sendKey(rt, .down, Mods(alt: true))
        #expect(rt.state.combo.active == nil)
        _ = rt.ime(.preedit("x", nil))
        _ = rt.frame(0.0)
        sendKey(rt, .enter)
        #expect(rt.state.combo.open && rt.state.chosen == nil)
        _ = rt.ime(.preedit("", nil))
        _ = rt.frame(0.0)
        sendKey(rt, .escape)
        #expect(!rt.state.combo.open)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func focusedComboboxHandlesKeysBeforeAppAndReturnsFocusOnClose() {
        let rt = makeRuntime()
        rt.onKey = { s, _, _ in
            s.appKeys += 1
            return true
        }
        sendKey(rt, .down)
        #expect(rt.state.combo.active == "item-2")
        sendKey(rt, .function(5))
        #expect(rt.state.appKeys == 1, "unhandled keys bubble to the app")
        sendKey(rt, .enter)
        #expect(rt.state.chosen == "item-2")
        let trigger = rt.elements().first(where: { $0.focused })!
        #expect(trigger.key == "models-value-trigger")
        #expect(trigger.focusVisible)
        sendKey(rt, .text(" "))
        #expect(rt.state.combo.open && rt.state.combo.search.focused)
        sendKey(rt, .escape)
        #expect(!rt.state.combo.open)
        #expect(rt.state.appKeys == 1, "Enter/Space/arrows/Escape belong to the control")
        #expect(rt.elements().first(where: { $0.focused })!.key == "models-value-trigger")
        sendKey(rt, .text(" "))
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        _ = rt.ime(.preedit("pending", nil))
        _ = rt.frame(0.0)
        _ = rt.pointerDown(390.0, 390.0)
        rt.pointerUp(390.0, 390.0)
        _ = rt.frame(0.0)
        #expect(!rt.state.combo.open && !rt.state.combo.search.focused)
        #expect(rt.state.combo.search.preedit == nil)
        let refocusedTrigger = rt.elements().first(where: { $0.focused })!
        #expect(refocusedTrigger.key == "models-value-trigger")
        #expect(!refocusedTrigger.focusVisible)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func heldEnterChoosesOnceAndDoesNotReopenFromTheTrigger() {
        let rt = makeRuntime()
        rt.onKey = { s, _, _ in
            s.appKeys += 1
            return false
        }
        sendKey(rt, .down)
        _ = rt.keyDown(KeyEvent(key: .enter))
        _ = rt.frame(0.0)
        for _ in 0..<2 {
            _ = rt.keyDown(KeyEvent(key: .enter), isRepeat: true)
            _ = rt.frame(0.0)
        }
        #expect(rt.state.chosen == "item-2" && rt.state.chooses == 1)
        #expect(!rt.state.combo.open, "the repeat must not reopen the popup from its trigger")
        #expect(rt.state.appKeys == 0)
    }

    /// A held key whose first press went to the IME: the repeats arrive after the composition ends,
    /// while the popup is still open, and must not choose or close it.
    @Test
    func repeatsAfterAnImeCompositionNeitherChooseNorClose() {
        for held: Key in [.enter, .escape] {
            let rt = makeRuntime()
            sendKey(rt, .down)
            _ = rt.ime(.preedit("ka", nil))
            _ = rt.frame(0.0)
            sendKey(rt, held)
            #expect(rt.state.combo.open, "\(held) during composition belongs to the IME")
            _ = rt.ime(.commit("か"))
            _ = rt.frame(0.0)
            for _ in 0..<2 {
                _ = rt.keyDown(KeyEvent(key: held), isRepeat: true)
                _ = rt.frame(0.0)
            }
            #expect(rt.state.combo.open, "a repeated \(held) keeps the popup open")
            #expect(rt.state.chooses == 0)
        }
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func aKeystrokeLandsItsRowsAndHeightInOneFrame() {
        let rt = makeRuntime()
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        sendKey(rt, .up)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        func find(_ rt: Runtime<ComboTestState>, _ key: String) -> ElementInfo? {
            rt.elements().first(where: { $0.key == key })
        }
        let open = find(rt, "models-content")!.rect
        func top(_ rt: Runtime<ComboTestState>, _ id: String) -> (Float, Float)? {
            let vp = find(rt, "viewport")!.rect
            guard let e = find(rt, "models-option-\(id)") else { return nil }
            return (e.rect[1] - vp[1], e.opacity)
        }
        sendKey(rt, .text("0"))
        _ = rt.frame(1.0 / 120.0)
        #expect(rt.elements().allSatisfy { !$0.exiting }, "nothing is left fading out")
        #expect(top(rt, "item-199") == nil, "the rows the filter drops are gone")
        let firstMatch = top(rt, "item-0")
        #expect(firstMatch?.0 == 0.0 && firstMatch?.1 == 1.0, "the first match is whole at the top")
        #expect(find(rt, "models-content")!.rect == open, "a full list keeps its size")

        sendKey(rt, .text("zz"))
        _ = rt.frame(1.0 / 120.0)
        let empty = find(rt, "models-content")!.rect
        #expect(empty[3] < open[3] - 100.0, "it takes the empty state's height: \(open) -> \(empty)")
        #expect(top(rt, "item-0") == nil)
        #expect(find(rt, "empty")!.opacity == 1.0)
        for _ in 0..<60 { _ = rt.frame(1.0 / 120.0) }
        #expect(find(rt, "models-content")!.rect == empty, "and holds it")

        sendKey(rt, .backspace)
        sendKey(rt, .backspace)
        _ = rt.frame(1.0 / 120.0)
        #expect(find(rt, "models-content")!.rect == open, "deleting lands back at once")
        let restored = top(rt, "item-0")
        #expect(restored?.0 == 0.0 && restored?.1 == 1.0)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func filteringSpringsThePopupHeightAndFadesRows() {
        let rt = makeAnimatedRuntime()
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        func find(_ rt: Runtime<ComboTestState>, _ key: String) -> ElementInfo? {
            rt.elements().first(where: { $0.key == key })
        }
        let open = find(rt, "models-content")!.rect[3]
        sendKey(rt, .text("199"))
        _ = rt.frame(1.0 / 60.0)
        guard let gone = find(rt, "models-option-item-0") else {
            Issue.record("a filtered-out row fades out")
            return
        }
        #expect(gone.opacity > 0.0 && gone.opacity < 1.0, "row opacity \(gone.opacity)")
        sendKey(rt, .text("zz"))
        var last = find(rt, "models-content")!.rect[3]
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            let h = find(rt, "models-content")!.rect[3]
            #expect(abs(h - last) < 20.0, "the popup's height jumped \(last) -> \(h)")
            last = h
        }
        #expect(last < open - 100.0, "it settles to the empty state: \(open) -> \(last)")
        #expect(find(rt, "empty")!.opacity == 1.0)
    }

    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func aCustomTriggerOpensAListThatFitsTheWindowUnderASearchHeader() {
        let rt = Runtime.new(ComboTestState(), comboTallView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        func find(_ rt: Runtime<ComboTestState>, _ key: String) -> ElementInfo {
            rt.elements().first(where: { $0.key == key })!
        }
        let trigger = find(rt, "custom").rect
        _ = rt.pointerDown(trigger[0] + 10.0, trigger[1] + 10.0)
        rt.pointerUp(trigger[0] + 10.0, trigger[1] + 10.0)
        rt.settleAll()
        _ = rt.frame(0.0)
        #expect(rt.state.combo.open && rt.state.combo.search.focused)
        let content = find(rt, "models-content").rect
        #expect(content[1] + content[3] <= 300.0, "the popup runs off the window: \(content)")
        let headerRect = find(rt, "header").rect
        let headerTop = headerRect[1]
        let headerHeight = headerRect[3]
        let viewport = find(rt, "viewport").rect
        #expect(viewport[1] >= headerTop + headerHeight, "rows start under the search header")
        #expect(viewport[3] > 100.0, "the list uses the room below: \(viewport)")
        sendKey(rt, .up)
        #expect(rt.state.combo.active == "item-199")
        let last = find(rt, "models-option-item-199")
        #expect(last.visible[3] > 0.0)
    }

    /// Typing while the list sits scrolled to its end: what the reader saw fades out where it stood,
    /// the matches fade in from the top, and matches that land out of view skip their fade.
    /// (`animateFiltering`)
    // PORT NOTE: Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec.
    @Test(.disabled("Blocked on Sources/Rune El.virtualRowsSource layout expansion, El.controls popup key routing & GrowthSpec"))
    func typingCrossfadesTheRowsInView() {
        let rt = makeAnimatedRuntime()
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        sendKey(rt, .up)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        // (top in the viewport, opacity, leaving)
        func row(_ rt: Runtime<ComboTestState>, _ id: String) -> (Float, Float, Bool)? {
            let vp = rt.elements().first(where: { $0.key == "viewport" })!.rect
            let key = "models-option-\(id)"
            guard let e = rt.elements().first(where: { $0.key == key }) else { return nil }
            return (e.rect[1] - vp[1], e.opacity, e.exiting)
        }
        sendKey(rt, .text("0"))
        let (top0, opacity0, _) = row(rt, "item-0")!
        #expect(abs(top0) < 0.5 && opacity0 < 0.05, "it fades in at the top: \(top0) at \(opacity0)")
        for _ in 0..<4 { _ = rt.frame(1.0 / 120.0) }
        let (top7, opacity7, _) = row(rt, "item-7")!
        #expect(top7 > 190.0 && opacity7 == 1.0, "nobody sees it, so it skips its fade: \(top7) at \(opacity7)")
        let (stood, _, _) = row(rt, "item-2")!
        sendKey(rt, .text("9"))
        let (topDrop, _, leaving) = row(rt, "item-2")!
        #expect(leaving && abs(topDrop - stood) < 0.5, "it fades where it stood: \(stood) -> \(topDrop)")
        let (top90, opacity90, _) = row(rt, "item-90")!
        #expect(abs(top90) < 0.5 && opacity90 < 0.05, "it fades in at the top over the leaving rows: \(top90) at \(opacity90)")
        for _ in 0..<4 { _ = rt.frame(1.0 / 120.0) }
        sendKey(rt, .text("9"))
        let (top99, opacity99, _) = row(rt, "item-99")!
        #expect(abs(top99) < 0.5 && opacity99 < 0.05, "it fades in rather than appearing whole: \(top99) at \(opacity99)")
    }
}
