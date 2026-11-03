// Tests ported from: crates/rune/src/tooling/parser_tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

#if !os(WASI)
import Foundation
#endif
import Testing
@testable import Rune

@Suite("ToolingParserTests")
struct ToolingParserTests {
    private func parseJson(_ raw: String) -> [ToolingEv] {
        guard let val = try? ToolingJson.parse(raw) else {
            Issue.record("Invalid JSON in test: \(raw)")
            return []
        }
        return toolingParseScript(val)
    }

    @Test func aFileDropHoversThenDropsAtItsPoint() {
        let steps = parseJson(#"""
        [
            {"drag_files": {"paths": ["a.png"], "key": "zone"}},
            {"t": 0.5, "drop_files": {"paths": ["a.png", "b.png"], "at": [10, 20], "hover": 0.25}},
            {"t": 1.0, "drag_files": "leave"}
        ]
        """#)
        #expect(steps.count == 4)
        #expect(steps[0].t == 0.0 && steps[0].kind == .files(.hover(["a.png"])) && steps[0].pos == .key("zone"))
        #expect(steps[1].t == 0.5 && steps[1].kind == .files(.hover(["a.png", "b.png"])) && steps[1].pos == .xy(10.0, 20.0))
        #expect(steps[2].t == 0.75 && steps[2].kind == .files(.drop(["a.png", "b.png"])) && steps[2].pos == .xy(10.0, 20.0))
        #expect(steps[3].t == 1.0 && steps[3].kind == .files(.leave) && steps[3].pos == .rel(0.0, 0.0))
    }

    @Test func aPhysicalChordReleasesItsModifiersAfterTheKey() throws {
        let steps = parseJson(#"[{"physical": "alt+super+space"}, {"t": 0.1, "physical": "f5"}]"#)
        let kinds: [ScriptPhysicalInput] = steps.compactMap {
            if case .physical(let input) = $0.kind { return input }
            return nil
        }
        let mods = try Shortcut.parse("alt+super+space").get().modifiers()
        let expected: [ScriptPhysicalInput] = [
            .key(key: .space, mods: mods, pressed: true, repeat: false),
            .key(key: .space, mods: mods, pressed: false, repeat: false),
            .modifiers(Mods()),
            .key(key: .f5, mods: Mods(), pressed: true, repeat: false),
            .key(key: .f5, mods: Mods(), pressed: false, repeat: false),
        ]
        #expect(kinds == expected)
    }

    @Test func scriptEventsAnswerAFileDialog() {
        let steps = parseJson(#"[{"t": 0.1, "type": "file-dialog", "path": "/exports/a.json"}, {"t": 0.2, "type": "file-dialog-cancel"}]"#)
        let kinds: [String?] = steps.map { e in
            guard case .fileDialog(let pub) = e.publicEvent().event,
                  case .fileDialog(let path) = e.kind
            else {
                Issue.record("Unexpected event kind")
                return nil
            }
            #expect(pub == path)
            return path
        }
        #expect(kinds == ["/exports/a.json", nil])
    }

    @Test func scriptEventsAnswerAPopUpMenu() {
        let steps = parseJson(#"[{"t": 0.2, "type": "menu-cancel"}, {"t": 0.1, "type": "menu-pick", "id": "dark"}]"#)
        let kinds: [String?] = steps.map { e in
            guard case .popupMenu(let pub) = e.publicEvent().event,
                  case .popupMenu(let picked) = e.kind
            else {
                Issue.record("Unexpected event kind")
                return nil
            }
            #expect(pub == picked)
            return picked
        }
        #expect(kinds == ["dark", nil])
    }

    #if !os(WASI)
    @Test func aScriptPasteCanCarryHtmlRtfAndAnImage() throws {
        let pngURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rune-script-paste-\(UUID().uuidString).png")
        let pngBytes = encodePng(1, 2, [UInt8](repeating: 9, count: 8))!
        try Data(pngBytes).write(to: pngURL)
        defer { try? FileManager.default.removeItem(at: pngURL) }

        let script = parseJson("""
        [
            {"type": "paste", "text": "plain"},
            {"paste": "short"},
            {"paste": {"text": "Hi", "html": "<b>Hi</b><img src=x onerror=y>", "rtf": "{\\\\rtf1 Hi}"}},
            {"paste": {"png": \(toolingEscapeJsonString(pngURL.path))}}
        ]
        """)
        #expect(script.count == 4)
        #expect(script[0].publicEvent().event == .paste("plain"))
        #expect(script[1].publicEvent().event == .paste("short"))
        if case .pasteContent(let rich) = script[2].publicEvent().event {
            #expect(rich.text() == "Hi")
            #expect(rich.html() == #"<b>Hi</b><img src="x">"#)
            #expect(rich.rtf() == #"{\rtf1 Hi}"#)
        } else {
            Issue.record("Expected .pasteContent for rich paste")
        }
        if case .paste(let imgContent) = script[3].kind {
            #expect(imgContent.text() == "")
            #expect(imgContent.image()?.size().0 == 1 && imgContent.image()?.size().1 == 2)
        } else {
            Issue.record("Expected .paste for PNG paste")
        }
    }
    #endif

    @Test func aScriptKeyWithACodeReachesHandlersWithItsPhysicalKey() {
        let script = parseJson(#"""
        [
            {"type": "key", "name": "&", "cmd": true, "shift": true, "code": "7"},
            {"t": 0.1, "type": "key", "name": "&", "cmd": true, "shift": true}
        ]
        """#)
        #expect(script.count == 3)
        let rt = Runtime<[(Key, PhysicalKeyCode?)]>([], { _, _ in el() }, (100.0, 100.0), Env.new(false, 1.0))
        rt.onKey = { state, ev, tx in
            state.append((ev.key, tx.hostPhysicalKey()))
            return true
        }
        for event in script {
            switch event.kind {
            case .key(let k, _):
                _ = rt.hostKey(k)
            case .physical(let input):
                rt.toolingDeliverPhysical(input)
            default:
                #expect(toolingCanvasInput(rt: rt, kind: event.kind, at: (0.0, 0.0)))
            }
            _ = rt.hostFrame(0.0)
        }
        #expect(rt.state.count == 2)
        #expect(rt.state[0].0 == .command("&") && rt.state[0].1 == .digit7)
        #expect(rt.state[1].0 == .command("&") && rt.state[1].1 == nil)
    }

    @Test func aScriptKeyWithACodeReachesHandlersWithItsUnmodifiedCharacter() {
        let script = parseJson(#"""
        [
            {"type": "key", "name": "å", "alt": true, "code": "a", "base": "a"},
            {"t": 0.1, "type": "key", "name": "k", "cmd": true, "code": "k"},
            {"t": 0.2, "type": "key", "name": "&", "cmd": true, "shift": true, "code": "7"},
            {"t": 0.3, "type": "key", "name": "k", "cmd": true},
            {"t": 0.4, "type": "key-up", "name": "q", "code": "a"}
        ]
        """#)
        let rt = Runtime([(Key, Character?)](), { _, _ in el() }, (100.0, 100.0), Env())
        rt.onKey = { state, ev, tx in
            state.append((ev.key, tx.keyBase()))
            return true
        }
        for e in script {
            switch e.kind {
            case .key(let k, let rep):
                _ = rt.hostKey(k, isRepeat: rep)
            case .physicalKey(_, let k, let base):
                _ = rt.hostKey(k, base: base, isRepeat: false)
            case .keyUp(let k):
                rt.state.append((k.key, Character("q")))
            default:
                break
            }
        }
        #expect(rt.state.count == 5)
        #expect(rt.state[0].0 == .text("å") && rt.state[0].1 == "a")
        #expect(rt.state[1].0 == .command("k") && rt.state[1].1 == "k")
        #expect(rt.state[2].0 == .command("&") && rt.state[2].1 == nil)
        #expect(rt.state[3].0 == .command("k") && rt.state[3].1 == nil)
        #expect(rt.state[4].0 == .text("q") && rt.state[4].1 == "q")
    }

    @Test func aScriptKeyCanBeAHeldKeysRepeat() {
        let script = parseJson(#"""
        [
            {"type": "key", "name": "Enter"},
            {"t": 0.1, "type": "key", "name": "Enter", "repeat": true},
            {"t": 0.2, "physical": "f5", "repeat": true}
        ]
        """#)
        let rt = Runtime([Bool](), { _, _ in el() }, (100.0, 100.0), Env())
        rt.onKey = { state, _, tx in
            state.append(tx.keyRepeat())
            return true
        }
        var physical: [(Bool, Bool)] = []
        for event in script {
            switch event.kind {
            case .key(let k, let rep):
                _ = rt.hostKey(k, isRepeat: rep)
            case .physical(.key(_, _, let pressed, let rep)):
                physical.append((pressed, rep))
            default:
                Issue.record("Unexpected event \(event.kind)")
            }
        }
        #expect(rt.state == [false, true])
        #expect(physical.count == 2)
        #expect(physical[0] == (true, true))
        #expect(physical[1] == (false, false))
    }

    @Test func windowPanelHeadlessFocusStepsPreserveFalseAndEventOrder() {
        let script = parseJson(#"[{"focus":true}, {"t":0.1,"focus":false}, {"t":0.2,"focus":false}]"#)
        #expect(script.count == 3)
        var currentFocus = false
        var seen: [Bool] = []
        for e in script {
            guard case .focus(let focused) = e.kind else {
                Issue.record("Focus parsed as pointer action")
                continue
            }
            if focused != currentFocus {
                currentFocus = focused
                seen.append(focused)
            }
        }
        #expect(seen == [true, false])
    }

    @Test func scriptsDriveWheelsPinchesOtherButtonsAndKeyReleases() {
        let script = parseJson(#"""
        [
            {"type": "wheel", "x": 10, "y": 20, "dx": -4, "dy": 6, "cmd": true, "phase": "began"},
            {"t": 0.1, "type": "magnify", "delta": 0.2},
            {"t": 0.2, "type": "drag", "button": "middle", "key": "canvas", "dx": 30, "dur": 0.01},
            {"t": 0.3, "type": "key-up", "name": " "}
        ]
        """#)
        #expect(script[0].kind == .move)
        if case .wheelEvent(let w) = script[1].kind {
            #expect(w.dx == -4.0 && w.dy == 6.0 && w.mods.cmd && w.precise)
        } else {
            Issue.record("Expected wheelEvent")
        }
        if case .magnify(let m) = script[2].kind, case .rel = script[2].pos {
            #expect(m.delta == 0.2)
        } else {
            Issue.record("Expected magnify at pointer")
        }
        #expect(script[4].kind == .buttonDown(.middle))
        #expect(script.contains(where: { $0.kind == .buttonUp(.middle) }))
        let last = script.last!
        if case .keyUp(let k) = last.kind {
            #expect(k.key == .text(" "))
        } else {
            Issue.record("Expected keyUp")
        }
        if case .keyUp = last.publicEvent().event {} else {
            Issue.record("Expected public keyUp")
        }
        if case .pointer(let action, _) = script[1].publicEvent().event, case .wheel = action {} else {
            Issue.record("Expected public pointer wheel")
        }
    }
}
