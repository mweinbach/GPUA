// Tests ported from: crates/rune/src/runtime/tests/app_ime.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Taffy
import Testing
@testable import Rune

private struct RtAppImeEditor {
    /// What `onIme` and `onKey` heard, in order.
    var log: [String] = []
    var field: TextEdit = TextEdit()
    /// The app's editor draws its caret (and so has the input method).
    var caret: Bool = false
}

private func rtAppImeAbsolute(_ base: El, _ left: Float, _ top: Float) -> El {
    var copy = base
    copy.style.position = .absolute
    copy.style.inset = Taffy.Rect(left: .length(left), right: .auto(), top: .length(top), bottom: .auto())
    return copy
}

private func rtAppImeCursor(_ base: El) -> El {
    var copy = base
    copy.imeCursorFlag = true
    return copy
}

private func rtDescribeIme(_ ev: Ime) -> String {
    switch ev {
    case .enabled:
        return "Enabled"
    case .disabled:
        return "Disabled"
    case .preedit(let s, let cur):
        if let (a, b) = cur {
            return "Preedit(\"\(s)\", Some((\(a), \(b))))"
        } else {
            return "Preedit(\"\(s)\", None)"
        }
    case .commit(let s):
        return "Commit(\"\(s)\")"
    }
}

private func rtDescribeKey(_ key: Key) -> String {
    switch key {
    case .text(let s):
        return "Text(\"\(s)\")"
    case .enter:
        return "Enter"
    case .escape:
        return "Escape"
    default:
        return "\(key)"
    }
}

private func rtAppImeView(_ s: RtAppImeEditor, _: Cx<RtAppImeEditor>) -> El {
    var page = el().key("page").size(300.0, 100.0)
    if s.caret {
        let caretEl = rtAppImeCursor(rtAppImeAbsolute(el().key("caret"), 40.0, 20.0).size(2.0, 18.0))
        page = page.child(caretEl)
    }
    return col().size(300.0, 200.0).children([
        textInput(s.field, TextStyle.new(14.0, 400.0)).key("field").size(200.0, 30.0),
        page,
    ])
}

private func rtMakeAppImeEditor() -> Runtime<RtAppImeEditor> {
    let rt = Runtime.new(
        RtAppImeEditor(caret: true),
        rtAppImeView,
        (300.0, 200.0),
        Env.new(true, 1.0)
    )
    rt.bindEdit("field", EditAccess(\.field))
    rt.onIme = { s, ev, _ in
        s.log.append(rtDescribeIme(ev))
        return true
    }
    rt.onKey = { s, ev, _ in
        s.log.append("key \(rtDescribeKey(ev.key))")
        return true
    }
    _ = rt.frame(0.0)
    return rt
}

private func rtPressAppImeKey(_ rt: Runtime<RtAppImeEditor>, _ key: Key) {
    _ = rt.keyDown(KeyEvent(key: key, mods: Mods()))
    _ = rt.frame(0.0)
}

@Suite
struct RtAppImeTests {
    @Test
    func anImeCursorTurnsTheInputMethodOnAtItsRectUnlessAFieldHasFocus() {
        let rt = rtMakeAppImeEditor()
        let initialArea = rt.imeArea
        #expect(initialArea == [40.0, 50.0, 2.0, 18.0])

        rt.update { s, _ in s.field.focused = true }
        _ = rt.frame(0.0)
        let fieldArea = rt.imeArea
        #expect(fieldArea != nil)
        if let f = fieldArea {
            #expect(f[1] < 30.0)
        }

        rt.update { s, _ in
            s.field.focused = false
            s.caret = false
        }
        _ = rt.frame(0.0)
        let clearedArea = rt.imeArea
        #expect(clearedArea == nil)
    }

    @Test
    func theAppHearsTheCompositionAndTypingArrivesOnce() {
        let rt = rtMakeAppImeEditor()
        rtPressAppImeKey(rt, .text("a"))
        _ = rt.ime(.enabled)
        _ = rt.ime(.preedit("か", (0, 3)))
        _ = rt.frame(0.0)
        rtPressAppImeKey(rt, .enter)
        rtPressAppImeKey(rt, .escape)
        _ = rt.ime(.commit("家"))
        _ = rt.frame(0.0)
        rtPressAppImeKey(rt, .enter)

        let log = rt.state.log
        #expect(log == [
            "key Text(\"a\")",
            "Enabled",
            "Preedit(\"か\", Some((0, 3)))",
            "Commit(\"家\")",
            "key Enter",
        ])
    }

    @Test
    func aFocusedFieldTakesTheInputMethodButTheAppsCompositionEndsInTheApp() {
        let rt = rtMakeAppImeEditor()
        _ = rt.ime(.preedit("か", nil))
        _ = rt.frame(0.0)
        rt.update { s, _ in s.field.focused = true }
        _ = rt.frame(0.0)

        // Turning the input method over to the field ends the app's composition.
        _ = rt.ime(.preedit("", nil))
        _ = rt.ime(.disabled)
        _ = rt.ime(.preedit("ね", nil))
        _ = rt.ime(.commit("猫"))
        _ = rt.frame(0.0)

        let log = rt.state.log
        let fieldText = rt.state.field.text
        #expect(log == ["Preedit(\"か\", None)", "Preedit(\"\", None)", "Disabled"])
        #expect(fieldText == "猫")
    }

    @Test
    func withoutOnImeAnImeCursorHearsNothing() {
        let rt = rtMakeAppImeEditor()
        rt.onIme = nil
        _ = rt.ime(.preedit("か", nil))
        _ = rt.frame(0.0)
        rtPressAppImeKey(rt, .enter)

        let log = rt.state.log
        #expect(log == ["key Enter"])
    }
}
