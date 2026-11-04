// Tests ported from: crates/rune-kit/tests/dialog_select.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct DialogSelectState {
    var dialog: Bool
    var select: Bool
    var value: String
}

private func dialogSelectView(_ s: DialogSelectState, _: Cx<DialogSelectState>) -> El {
    let k = Kit.neutral(true)
    var layer: [El] = []
    // Build the portal before its modal, as nested component builders naturally do.
    let select = Select.new("choice", ["First", "Second"])
        .current(s.value)
        .appearance(.field)
        .width(100.0)
        .placement(.rightStart)
        .open(s.select)
        .onToggle { (s: inout DialogSelectState) in s.select.toggle() }
        .onClose { (s: inout DialogSelectState) in s.select = false }
        .onChoose { (s: inout DialogSelectState, v, _) in
            s.value = v
            s.select = false
        }
        .build(k, &layer)
    Dialog.new("dialog", "Choose")
        .open(s.dialog)
        .onClose { (s: inout DialogSelectState) in s.dialog = false }
        .child(row().wFull().justifyEnd().child(select))
        .build(k, &layer)
    return root(el().wFull().hFull(), layer)
}

@Suite("DialogSelectTests")
struct DialogSelectTests {
    @Test
    func selectPortalInsideDialogAcceptsAnOptionOutsideThePanel() {
        let rt = Runtime.new(
            DialogSelectState(dialog: true, select: false, value: "First"),
            dialogSelectView,
            (1400.0, 800.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let (tx, ty) = rt.find("choice-trigger")!
        _ = rt.pointerDown(tx, ty)
        rt.pointerUp(tx, ty)
        _ = rt.frame(0.0)
        #expect(rt.state.select && rt.state.dialog)
        for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
        let elements = rt.elements()
        let panel = elements.first(where: { $0.key == "dialog-dialog" })!
        let option = elements.first(where: { $0.key == "option1" })!
        #expect(!option.inert)
        let (ox, oy) = rt.find("option1")!
        #expect(
            ox < panel.rect[0] || ox > panel.rect[0] + panel.rect[2]
                || oy < panel.rect[1] || oy > panel.rect[1] + panel.rect[3],
            "option (\(ox), \(oy)) must be outside panel \(panel.rect)"
        )
        _ = rt.pointerDown(ox, oy)
        rt.pointerUp(ox, oy)
        _ = rt.frame(0.0)
        #expect(rt.state.value == "Second")
        #expect(rt.state.dialog && !rt.state.select)
    }

    @Test
    func aFitDialogIsAsTallAsItsContent() {
        func view(_ fit: Bool, _: Cx<Bool>) -> El {
            let k = Kit.neutral(true)
            var layer: [El] = []
            let buttons = row().key("buttons").wFull().padding(16.0).justifyEnd().child(el().size(80.0, 28.0))
            let d = Dialog.new("delete", "Delete session")
                .description("Delete session \"x\"?")
                .width(400.0)
                .open(true)
                .onClose { (_: inout Bool) in }
                .child(buttons)
            let configured = fit ? d.fit() : d
            configured.build(k, &layer)
            return root(el().wFull().hFull(), layer)
        }
        func rect(_ fit: Bool, _ key: String) -> [Float] {
            let rt = Runtime.new(fit, view, (1000.0, 800.0), Env.new(true, 1.0))
            for _ in 0..<60 { _ = rt.frame(1.0 / 60.0) }
            return rt.elements().first(where: { $0.key == key })!.rect
        }
        #expect(rect(false, "delete-dialog")[3] == 368.0, "the standard height")
        let panel = rect(true, "delete-dialog")
        let buttons = rect(true, "buttons")
        // 16 + title 20 + 4 + description 20 + 16, then the 60 point button row.
        #expect(panel[3] == 76.0 + 60.0)
        #expect((panel[0], panel[1]) == ((1000.0 - 400.0) / 2.0, (800.0 - panel[3]) / 2.0), "centred in the layer")
        #expect(buttons[1] + buttons[3] == panel[1] + panel[3], "the buttons sit at the bottom edge")
    }
}
