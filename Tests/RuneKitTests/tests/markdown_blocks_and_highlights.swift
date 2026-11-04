// Tests ported from: crates/rune-kit/tests/markdown_blocks_and_highlights.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune
@testable import RuneKit

private func byKey<S>(_ rt: Runtime<S>, _ key: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.key == key }) else {
        preconditionFailure("no \(key)")
    }
    return found
}

private func utf8ByteOffset(_ haystack: String, _ needle: String) -> Int? {
    let h = Array(haystack.utf8)
    let n = Array(needle.utf8)
    if n.isEmpty { return 0 }
    if n.count > h.count { return nil }
    let limit = h.count - n.count
    for i in 0...limit {
        if h[i..<(i + n.count)].elementsEqual(n) {
            return i
        }
    }
    return nil
}

private func utf8MatchIndices(_ haystack: String, _ needle: String) -> [Int] {
    let h = Array(haystack.utf8)
    let n = Array(needle.utf8)
    guard !n.isEmpty, n.count <= h.count else { return [] }
    var out: [Int] = []
    var i = 0
    let limit = h.count - n.count
    while i <= limit {
        if h[i..<(i + n.count)].elementsEqual(n) {
            out.append(i)
            i += n.count
        } else {
            i += 1
        }
    }
    return out
}

// These fixtures intentionally have only blank-line-separated top-level blocks.
private func fixtureKeys(_ src: String, _ keys: [String]) -> [(Int, String)] {
    let starts = [0] + utf8MatchIndices(src, "\n\n").map { $0 + 2 }
    return Array(zip(starts, keys))
}

private struct TaskToggleRecord: Equatable {
    var blockKey: String
    var markerOffset: Int
    var checked: Bool
}

private struct TaskDoc {
    var src: String = ""
    var keys: [String] = []
    var handled: Bool = false
    var readOnly: Bool = false
    var toggled: [TaskToggleRecord] = []
}

private func taskView(_ s: TaskDoc, _: Cx<TaskDoc>) -> El {
    var md = Markdown.new(s.src)
    if !s.keys.isEmpty {
        md = md.blockKeys(fixtureKeys(s.src, s.keys))
    }
    if s.handled {
        md = md.onTaskTx { (st: inout TaskDoc, key: String, item: Int, checked: Bool, tx: inout Tx) in
            st.toggled.append(TaskToggleRecord(blockKey: key, markerOffset: item, checked: checked))
            tx.copy("\(key):\(item):\(checked)")
        }
    }
    if s.readOnly {
        md = md.tasksReadOnly()
    }
    return col().w(320.0).child(md.build(Kit.neutral(true)))
}

@Suite("MarkdownBlocksAndHighlightsTests")
struct MarkdownBlocksAndHighlightsTests {
    @Test func callerBlockKeysInsertRemoveEditAndRetargetMidFlight() {
        struct DocState {
            var src: String
            var keys: [String]
        }
        func view(_ d: DocState, _: Cx<DocState>) -> El {
            col().w(320.0).child(Markdown.new(d.src).blockKeys(fixtureKeys(d.src, d.keys)).build(Kit.neutral(true)))
        }

        let rt = Runtime.new(
            DocState(src: "Alpha\n\nBeta", keys: ["p-a", "p-b"]),
            view,
            (320.0, 400.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let yA0 = byKey(rt, "p-a").rect[1]
        let yB0 = byKey(rt, "p-b").rect[1]
        #expect(yA0 == 0.0)
        #expect(yB0 > 20.0)

        // 1. Insert a block at the top: old blocks keep their keys and spring down; new block fades in.
        rt.state = DocState(src: "Intro\n\nAlpha\n\nBeta", keys: ["p-intro", "p-a", "p-b"])
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        let intro = byKey(rt, "p-intro")
        let aMid = byKey(rt, "p-a")
        let bMid = byKey(rt, "p-b")
        #expect(intro.opacity > 0.0 && intro.opacity < 1.0, "inserted block enters on its fade: \(intro.opacity)")
        #expect(aMid.moving && aMid.rect[1] > yA0 && aMid.rect[1] < yB0, "p-a springs from old y to new y: \(aMid)")
        #expect(bMid.moving && bMid.rect[1] > yB0, "p-b springs down with p-a: \(bMid)")
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        let yALanded = byKey(rt, "p-a").rect[1]
        let yBLanded = byKey(rt, "p-b").rect[1]
        #expect(abs(byKey(rt, "p-intro").opacity - 1.0) < 1e-3)
        #expect(abs(yALanded - yB0) < 0.5 && yBLanded > yALanded)

        // 2. Remove the middle block: it stays mounted while exiting and the trailing sibling springs up.
        rt.state = DocState(src: "Intro\n\nBeta", keys: ["p-intro", "p-b"])
        rt.invalidate()
        _ = rt.frame(0.0)
        _ = rt.frame(1.0 / 60.0)
        let aExit = byKey(rt, "p-a")
        let bReflow = byKey(rt, "p-b")
        #expect(aExit.exiting && aExit.opacity > 0.0 && aExit.opacity < 1.0, "removed block stays mounted while exiting: \(aExit)")
        #expect(bReflow.moving && bReflow.rect[1] < yBLanded && bReflow.rect[1] > yALanded, "p-b springs up: \(bReflow)")
        for _ in 0..<60 {
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(rt.elements().allSatisfy { $0.key != "p-a" }, "exited block unmounts after transition")
        #expect(abs(byKey(rt, "p-b").rect[1] - yALanded) < 0.5)

        // 3. Edit a block in place and retarget mid-flight: height and sibling y continue smoothly without jumping.
        let h0 = byKey(rt, "p-intro").rect[3]
        let y0 = byKey(rt, "p-b").rect[1]
        rt.state = DocState(src: "Intro line one  \nline two  \nline three\n\nBeta", keys: ["p-intro", "p-b"])
        rt.invalidate()
        _ = rt.frame(0.0)
        for _ in 0..<3 {
            _ = rt.frame(1.0 / 60.0)
        }
        let hMid = byKey(rt, "p-intro").rect[3]
        let yMid = byKey(rt, "p-b").rect[1]
        #expect(hMid > h0 && yMid > y0, "height and sibling y are mid-spring: \(hMid) > \(h0), \(yMid) > \(y0)")
        #expect(
            hMid < byKey(rt, "p-intro").target[3] && yMid < byKey(rt, "p-b").target[1],
            "editing animates toward the larger height and sibling position, not straight to them"
        )

        rt.state = DocState(src: "Intro line one  \nline two  \nline three  \nline four  \nline five\n\nBeta", keys: ["p-intro", "p-b"])
        rt.invalidate()
        _ = rt.frame(0.0)
        let hRetarget = byKey(rt, "p-intro").rect[3]
        let yRetarget = byKey(rt, "p-b").rect[1]
        #expect(abs(hRetarget - hMid) < 0.5 && abs(yRetarget - yMid) < 0.5, "retarget commit does not jump: \(hRetarget) vs \(hMid), \(yRetarget) vs \(yMid)")
        _ = rt.frame(1.0 / 60.0)
        #expect(byKey(rt, "p-intro").rect[3] > hRetarget && byKey(rt, "p-b").rect[1] > yRetarget)
    }

    @Test func blockKeysFallbackNestedAndSelectable() {
        func view(_ keys: [String], _: Cx<[String]>) -> El {
            let src = "# Heading\n\n> Quoted one\n>\n> Quoted two\n\nParagraph three"
            return col()
                .w(320.0)
                .child(Markdown.new(src).blockKeys(fixtureKeys(src, keys)).selectable(true).reveal(0.15).build(Kit.neutral(true)))
        }

        // Fewer keys, empty key and duplicate key fall back to unused b{i} keys without trapping;
        // nested blocks inside the quote keep their own b0, b1 keys under the quote's caller key.
        let rt = Runtime.new(["sec-head", "sec-quote"], view, (320.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let paths = rt.elements().map(\.path)
        #expect(paths.contains(where: { $0.hasSuffix("/sec-head") }), "\(paths)")
        #expect(
            paths.contains(where: { $0.contains("/sec-quote/") && $0.hasSuffix("/b0") })
                && paths.contains(where: { $0.contains("/sec-quote/") && $0.hasSuffix("/b1") }),
            "\(paths)"
        )
        #expect(paths.contains(where: { $0.hasSuffix("/b2") }), "missing 3rd key falls back to b2: \(paths)")

        // Extra keys, empty keys and duplicates never collide or panic.
        rt.state = ["", "dup", "dup", "extra-1", "extra-2"]
        rt.invalidate()
        _ = rt.frame(1.0 / 60.0)
        let topKeys = rt.elements()
            .filter { !$0.exiting && $0.path.filter({ $0 == "/" }).count == 2 }
            .compactMap(\.key)
        #expect(topKeys == ["b0", "dup", "b2"])

        // Selection across caller-keyed blocks copies the whole document in order.
        rt.pointerMove(4.0, 6.0)
        _ = rt.pointerDown(4.0, 6.0)
        rt.pointerUp(4.0, 6.0)
        _ = rt.frame(1.0 / 60.0)
        let cmd = Mods(cmd: true)
        _ = rt.keyDown(KeyEvent(key: .command("a"), mods: cmd))
        _ = rt.frame(1.0 / 60.0)
        _ = rt.keyDown(KeyEvent(key: .command("c"), mods: cmd))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.takeClipboardWrite()?.content().text() == "Heading\nQuoted one\nQuoted two\nParagraph three")
    }

    @Test func sourceKeysDoNotShiftWhenParsersDisagree() {
        func view(_ src: String, _: Cx<String>) -> El {
            // The caller splits a loose list into two blocks and keeps an HTML block that the
            // renderer omits. Neither boundary must steal the later paragraph's durable ID.
            let keys: [(Int, String)] = [
                (0, "list"),
                (utf8ByteOffset(src, "- second")!, "second-item"),
                (utf8ByteOffset(src, "<div>")!, "html"),
                (utf8ByteOffset(src, "After")!, "after"),
            ]
            return col()
                .w(320.0)
                .child(Markdown.new(src).blockKeys(keys).reveal(0.15).selectable(true).streaming(true).build(Kit.neutral(true)))
        }

        let rt = Runtime.new("- first\n\n- second\n\n<div>ignored</div>\n\nAfter", view, (320.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(byKey(rt, "after").text == "After")
        #expect(rt.elements().allSatisfy { $0.key != "second-item" && $0.key != "html" })
        // Appending a partial block takes the incremental parse path; absolute offsets stay valid.
        rt.state += " grows\n\npartial"
        rt.invalidate()
        _ = rt.frame(1.0 / 60.0)
        #expect(byKey(rt, "after").text == "After grows")
        #expect(byKey(rt, "after").revealing, "appended words reveal under the retained key")
        #expect(byKey(rt, "b2").text == "partial")
    }

    @Test func nestedTasksReportExactSourceMarkerOffsetsAndReadOnlyDisablesFocus() {
        let src = "Préface\n\n- plain\n  - [ ] nested\n- [x] outer\n\nTail\n\n- [ ] last\n"
        let rt = Runtime.new(TaskDoc(src: src, handled: true), taskView, (320.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)

        let boxes = rt.elements().filter { $0.role == "checkbox" }
        #expect(boxes.count == 3)
        #expect(boxes.allSatisfy({ $0.focusable }) == true)

        func click(_ r: [Float]) {
            let (x, y) = (r[0] + 12.0, r[1] + r[3] * 0.5)
            rt.pointerMove(x, y)
            _ = rt.pointerDown(x, y)
            rt.pointerUp(x, y)
            _ = rt.frame(1.0 / 60.0)
        }

        for (n, (marker, key, checked)) in [("[ ] nested", "b1", true), ("[x] outer", "b1", false), ("[ ] last", "b3", true)].enumerated() {
            click(boxes[n].rect)
            #expect(rt.state.toggled.count == n + 1)
            #expect(rt.state.toggled[n] == TaskToggleRecord(blockKey: key, markerOffset: utf8ByteOffset(src, marker)!, checked: checked))
        }

        rt.state.readOnly = true
        rt.state.toggled.removeAll()
        rt.invalidate()
        _ = rt.frame(1.0 / 60.0)
        for _ in 0..<4 {
            _ = rt.keyDown(KeyEvent(key: .tab, mods: Mods()))
            _ = rt.keyDown(KeyEvent(key: .text(" "), mods: Mods()))
            _ = rt.frame(1.0 / 60.0)
        }
        #expect(rt.state.toggled.isEmpty)
        #expect(rt.elements().filter({ $0.role == "checkbox" }).allSatisfy({ !$0.focusable }))
    }

    @Test(.disabled("Requires Rune runtime input_keys.swift to activate focused role == \"checkbox\" on Space instead of Enter"))
    func nestedTasksWalkTabOrderAndToggleWithSpace() {
        let src = "Préface\n\n- plain\n  - [ ] nested\n- [x] outer\n\nTail\n\n- [ ] last\n"
        let rt = Runtime.new(TaskDoc(src: src, handled: true), taskView, (320.0, 400.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        // Space without focus does nothing. Tab walks document order, including nested tasks.
        _ = rt.keyDown(KeyEvent(key: .text(" "), mods: Mods()))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.toggled.isEmpty)
        for (n, (marker, key, checked)) in [("[ ] nested", "b1", true), ("[x] outer", "b1", false), ("[ ] last", "b3", true)].enumerated() {
            _ = rt.keyDown(KeyEvent(key: .tab, mods: Mods()))
            _ = rt.frame(1.0 / 60.0)
            _ = rt.keyDown(KeyEvent(key: .text(" "), mods: Mods()))
            _ = rt.frame(1.0 / 60.0)
            #expect(rt.state.toggled.count == n + 1)
            #expect(rt.state.toggled[n] == TaskToggleRecord(blockKey: key, markerOffset: utf8ByteOffset(src, marker)!, checked: checked))
        }
    }

    @Test func taskControlsMatchCheckboxPaintInBothThemes() {
        struct ThemeCheckState {
            var dark: Bool
            var checked: Bool
        }
        func view(_ st: ThemeCheckState, _: Cx<ThemeCheckState>) -> El {
            let kit = Kit.neutral(st.dark)
            return col()
                .w(320.0)
                .child(Checkbox.new(st.checked).label("Task").build(kit).key("standard"))
                .child(Markdown.new(st.checked ? "- [x] Task" : "- [ ] Task").build(kit).key("markdown"))
        }
        for dark in [false, true] {
            for checked in [false, true] {
                let rt = Runtime.new(ThemeCheckState(dark: dark, checked: checked), view, (320.0, 160.0), Env.new(dark, 1.0))
                _ = rt.frame(0.0)
                let controls = rt.elements().filter { $0.key == "control" }
                #expect(controls.count == 2)
                #expect(controls[0].fill == controls[1].fill)
                #expect(controls[0].radius == controls[1].radius)
                #expect(Array(controls[0].rect[2...]) == Array(controls[1].rect[2...]))
                let marks = rt.elements().filter { $0.key == "mark" }
                #expect(marks.count == 2)
                #expect(marks[0].opacity == marks[1].opacity)
                #expect(marks[0].textColor == marks[1].textColor)
                #expect(Array(marks[0].rect[2...]) == Array(marks[1].rect[2...]))
            }
        }
    }

    @Test func taskListsRenderCheckboxesClickAndRespectReadOnly() {
        let k = Kit.neutral(true)
        let rt = Runtime.new(
            TaskDoc(
                src: "Notes\n\n- [ ] a\n- [x] b\n",
                keys: ["intro", "checklist"],
                handled: true,
                readOnly: false,
                toggled: []
            ),
            taskView,
            (320.0, 300.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        let boxes = rt.elements().filter { $0.role == "checkbox" }
        #expect(boxes.count == 2, "two checkbox elements: \(boxes)")
        #expect(boxes[0].label == "a" && !boxes[0].itemSelected && boxes[0].focusable)
        #expect(boxes[1].label == "b" && boxes[1].itemSelected && boxes[1].focusable)

        let marks = rt.elements().filter { $0.key == "mark" }
        #expect(marks[0].opacity == 0.0 && marks[1].opacity == 1.0)
        let controls = rt.elements().filter { $0.key == "control" }
        #expect(controls[0].fill == Color.TRANSPARENT && controls[1].fill == k.c.surfaceWeak)

        func click(_ r: [Float]) {
            let (x, y) = (r[0] + 12.0, r[1] + r[3] * 0.5)
            rt.pointerMove(x, y)
            _ = rt.pointerDown(x, y)
            rt.pointerUp(x, y)
            _ = rt.frame(1.0 / 60.0)
        }

        // Each callback identifies the source marker, not an index among tasks or list items.
        click(boxes[0].rect)
        #expect(rt.state.toggled == [TaskToggleRecord(blockKey: "checklist", markerOffset: 9, checked: true)])
        #expect(rt.takeClipboardWrite()?.content().text() == "checklist:9:true")

        click(boxes[1].rect)
        #expect(
            rt.state.toggled == [
                TaskToggleRecord(blockKey: "checklist", markerOffset: 9, checked: true),
                TaskToggleRecord(blockKey: "checklist", markerOffset: 17, checked: false),
            ]
        )
        #expect(rt.takeClipboardWrite()?.content().text() == "checklist:17:false")

        // Without caller blockKeys, onTask receives the default b{index} key.
        rt.state.keys.removeAll()
        rt.state.toggled.removeAll()
        rt.invalidate()
        _ = rt.frame(1.0 / 60.0)
        click(boxes[0].rect)
        #expect(rt.state.toggled == [TaskToggleRecord(blockKey: "b1", markerOffset: 9, checked: true)])

        // `.tasksReadOnly()` and missing `onTask` keep role/label/checked state but ignore presses and Space.
        for (handled, readOnly) in [(true, true), (false, false)] {
            rt.state.handled = handled
            rt.state.readOnly = readOnly
            rt.state.toggled.removeAll()
            rt.invalidate()
            _ = rt.frame(1.0 / 60.0)
            let roBoxes = rt.elements().filter { !$0.exiting && $0.role == "checkbox" }
            #expect(roBoxes.count == 2)
            #expect(!roBoxes[0].focusable && !roBoxes[1].focusable)
            #expect(!roBoxes[0].itemSelected && roBoxes[1].itemSelected)
            click(roBoxes[0].rect)
            _ = rt.keyDown(KeyEvent(key: .text(" "), mods: Mods()))
            _ = rt.frame(1.0 / 60.0)
            #expect(rt.state.toggled.isEmpty, "read-only tasks must not fire: handled=\(handled) readOnly=\(readOnly)")
        }
    }

    @Test(.disabled("Requires Rune runtime input_keys.swift to activate focused role == \"checkbox\" on Space instead of Enter"))
    func taskListsToggleWithSpaceAndIgnoreEnter() {
        let rt = Runtime.new(
            TaskDoc(
                src: "Notes\n\n- [ ] a\n- [x] b\n",
                keys: ["intro", "checklist"],
                handled: true,
                readOnly: false,
                toggled: []
            ),
            taskView,
            (320.0, 300.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)
        let boxes = rt.elements().filter { $0.role == "checkbox" }
        let (x, y) = (boxes[1].rect[0] + 12.0, boxes[1].rect[1] + boxes[1].rect[3] * 0.5)
        rt.pointerMove(x, y)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.toggled.count == 1)

        // Space on the focused task checkbox toggles it through the same handler; Enter does not.
        _ = rt.keyDown(KeyEvent(key: .text(" "), mods: Mods()))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.toggled.last == TaskToggleRecord(blockKey: "checklist", markerOffset: 17, checked: false))
        #expect(rt.state.toggled.count == 2, "Space fires once on the focused checkbox")
        _ = rt.keyDown(KeyEvent(key: .enter, mods: Mods()))
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.toggled.count == 2, "checkboxes toggle with Space, not Enter")
    }

    @Test func strikethroughParsesInParagraphListAndTable() {
        let src = "Keep ~~struck~~ and ~~**bold** `code`~~ in\n\n- ~~item~~\n\n| Col |\n|---|\n| ~~cell~~ |\n"
        let b = markdown.parse(src)
        guard case .para(let p) = b[0] else {
            Issue.record("expected paragraph: \(b)")
            return
        }
        #expect(p.text == "Keep struck and bold \u{202f}\u{202f}code\u{202f}\u{202f} in")
        let pBytes = Array(p.text.utf8)
        let struck = p.spans
            .filter { $0.2 == .strike }
            .map { String(decoding: pBytes[$0.0..<$0.1], as: UTF8.self) }
        #expect(struck == ["struck", "bold \u{202f}\u{202f}code\u{202f}\u{202f}"])
    }

    @Test(.disabled("Requires Rune runtime paint_content.swift to call strikeDecorations for TextSpec.strikes"))
    func strikethroughPaintsInLightAndDarkThemes() {
        struct StrikeState {
            var dark: Bool
            var strike: Bool
        }
        func view(_ st: StrikeState, _: Cx<StrikeState>) -> El {
            let k = Kit.neutral(st.dark)
            let doc = st.strike
                ? "Keep ~~struck~~ and ~~**bold** `code`~~\n\n- ~~item~~\n\n| Col |\n|---|\n| ~~cell~~ |\n"
                : "Keep struck and **bold** `code`\n\n- item\n\n| Col |\n|---|\n| cell |\n"
            return col().w(360.0).child(Markdown.new(doc).build(k))
        }

        for dark in [false, true] {
            let plain = Runtime.new(StrikeState(dark: dark, strike: false), view, (360.0, 300.0), Env.new(dark, 1.0))
            _ = plain.frame(0.0)
            let struckRt = Runtime.new(StrikeState(dark: dark, strike: true), view, (360.0, 300.0), Env.new(dark, 1.0))
            _ = struckRt.frame(0.0)

            func thinRects(_ rt: Runtime<StrikeState>) -> [[Float]] {
                rt.instances
                    .filter { $0.params[1] == KIND_RECT && $0.rect[3] >= 0.9 && $0.rect[3] <= 2.5 && $0.rect[2] > 12.0 }
                    .map(\.rect)
            }
            let extra = max(thinRects(struckRt).count - thinRects(plain).count, 0)
            #expect(extra >= 4, "dark=\(dark): strike lines drawn for paragraph, list item and table cell (\(extra) new lines)")
        }
    }

    @Test func bareUrlsAutolinkWithGfmPunctuationRulesAndRespectOptOut() {
        let src =
            "Visit https://example.org/docs?x=1#top, http://example.org:8080/a; "
            + "and www.example.org/path/to_file! "
            + "Also (see https://en.wikipedia.org/wiki/Rust_(programming_language)) "
            + "and https://example.org/entity&nbsp; "
            + "but not `https://in.code` or [explicit](https://explicit.example/x).\n\n"
            + "```\nhttps://in.fence.example\n```\n"
        let b = markdown.parse(src)
        guard case .para(let p) = b[0] else {
            Issue.record("expected paragraph: \(b)")
            return
        }
        let pBytes = Array(p.text.utf8)
        let links = p.links.map { (a, z, u) in
            "\(String(decoding: pBytes[a..<z], as: UTF8.self))->\(u)"
        }
        #expect(
            links == [
                "https://example.org/docs?x=1#top->https://example.org/docs?x=1#top",
                "http://example.org:8080/a->http://example.org:8080/a",
                "www.example.org/path/to_file->http://www.example.org/path/to_file",
                "https://en.wikipedia.org/wiki/Rust_(programming_language)->https://en.wikipedia.org/wiki/Rust_(programming_language)",
                "https://example.org/entity->https://example.org/entity",
                "explicit->https://explicit.example/x",
            ]
        )

        // Verify `autolink: false` leaves bare URLs plain while keeping explicit links.
        let disabled = parseDoc("Try www.example.org/hello, or [named](https://named.example).", false).blocks
        guard case .para(let plainPara) = disabled[0] else {
            Issue.record("expected paragraph")
            return
        }
        #expect(plainPara.links.map(\.2) == ["https://named.example"])
    }

    @Test(.disabled("Requires Rune runtime synthetic #link- ElementInfo and TextSpec.onLink dispatch"))
    func bareUrlsAutolinkClickAndOptOutInRuntime() {
        struct AutoState {
            var autolink: Bool
            var opened: [String]
        }
        func autoView(_ s: AutoState, _: Cx<AutoState>) -> El {
            col().w(480.0).child(
                Markdown.new("Try www.example.org/hello, or [named](https://named.example).")
                    .autolink(s.autolink)
                    .onLink { (st: inout AutoState, url: String) in st.opened.append(url) }
                    .build(Kit.neutral(true))
            )
        }
        let rt = Runtime.new(AutoState(autolink: true, opened: []), autoView, (480.0, 120.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let (x, y) = rt.find("http://www.example.org/hello")!
        rt.pointerMove(x, y)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.state.opened == ["http://www.example.org/hello"])

        rt.state.autolink = false
        rt.invalidate()
        _ = rt.frame(1.0 / 60.0)
        #expect(rt.find("http://www.example.org/hello") == nil, "autolink(false) disables bare URL links")
        #expect(rt.find("https://named.example") != nil, "explicit links remain active")
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo and highlight ring painting"))
    func highlightsMapSourceBytesAcrossFormattingBlocksAndSyntaxWithoutReshaping() {
        let src =
            "# Heading Alpha\n\n"
            + "Plain **bold token** and `inline_code` plus ~~struck_word~~ and [linked text](https://example.org/hidden).\n\n"
            + "Second paragraph continues here.\n\n"
            + "- list item one\n"
            + "- [x] task needle done\n\n"
            + "> quoted thoughts\n\n"
            + "| Col A | Col B |\n"
            + "|---|---|\n"
            + "| cell_alpha | cell_beta |\n\n"
            + "```rust\nfn compute(value: i32) -> i32 {\n    value + 1\n}\n```\n"

        func rangeOf(_ needle: String) -> Range<Int> {
            let start = utf8ByteOffset(src, needle)!
            return start..<(start + needle.utf8.count)
        }

        let boldStars = utf8ByteOffset(src, "**bold")!
        let linkDest = utf8ByteOffset(src, "(https://example.org/hidden)")!
        let highlights: [(Range<Int>, Highlight)] = [
            (rangeOf("Alpha"), Highlight.new()),
            (rangeOf("Plain **bold"), Highlight.new()),
            (rangeOf("inline_code"), Highlight.new()),
            (rangeOf("struck"), Highlight.new()),
            (rangeOf("linked text](https://example.org/hidden).\n\nSecond"), Highlight.new()),
            (rangeOf("item one"), Highlight.new()),
            (rangeOf("needle"), Highlight.new()),
            (rangeOf("thoughts"), Highlight.new()),
            (rangeOf("cell_beta"), Highlight.new()),
            (rangeOf("compute(value"), Highlight.current().key("active-match")),
            (boldStars..<(boldStars + 2), Highlight.new().key("syntax-only-stars")),
            (linkDest..<(linkDest + "(https://example.org/hidden)".utf8.count), Highlight.new().key("syntax-only-url")),
        ]

        struct HlState {
            var src: String
            var hls: [(Range<Int>, Highlight)]
        }
        func hlView(_ st: HlState, _: Cx<HlState>) -> El {
            let k = Kit.neutral(true)
            let style = MarkdownStyle.fromKit(k)
                .highlightBg(Rune.hex("#eab30838")!)
                .highlightCurrentBg(Rune.hex("#f59e0b66")!)
                .highlightCurrentRing((Rune.hex("#f59e0b")!, 1.5))
            return col().w(520.0).child(Markdown.new(st.src).style(style).highlights(st.hls).build(k))
        }
        func renderWith(_ s: String, _ hls: [(Range<Int>, Highlight)]) -> Runtime<HlState> {
            let rt = Runtime.new(HlState(src: s, hls: hls), hlView, (520.0, 900.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            return rt
        }

        let plainRt = renderWith(src, [])
        let hlRt = renderWith(src, highlights)

        func glyphs(_ rt: Runtime<HlState>) -> [[UInt32]] {
            rt.instances
                .filter { $0.params[1] == KIND_GLYPH }
                .map { $0.rect.map(\.bitPattern) + $0.uv.map(\.bitPattern) }
        }
        #expect(glyphs(plainRt) == glyphs(hlRt), "highlights must never reshape text or move glyphs")

        let marks = hlRt.elements()
            .filter { $0.role == "mark" }
            .map { "\($0.key ?? ""):\($0.label ?? "")" }
        #expect(marks.contains("md-mark-0:Alpha"), "\(marks)")
        #expect(marks.contains("md-mark-1:Plain bold"), "\(marks)")
        #expect(marks.contains("md-mark-2:inline_code"), "\(marks)")
        #expect(marks.contains("md-mark-3:struck"), "\(marks)")
        let cross = hlRt.elements().filter { $0.role == "mark" && $0.key == "md-mark-4" }.compactMap(\.label)
        #expect(cross == ["linked text.", "Second"])
        #expect(marks.contains("md-mark-5:item one"), "\(marks)")
        #expect(marks.contains("md-mark-6:needle"), "\(marks)")
        #expect(marks.contains("md-mark-7:thoughts"), "\(marks)")
        #expect(marks.contains("md-mark-8:cell_beta"), "\(marks)")
        #expect(marks.contains("active-match:compute(value"), "\(marks)")
        #expect(!marks.contains(where: { $0.hasPrefix("syntax-only") }), "syntax-only ranges must not highlight: \(marks)")

        let wantRing = Rune.hex("#f59e0b")!.premul(1.0)
        let ringed = hlRt.instances.filter {
            $0.params[1] == KIND_RECT && abs($0.params[0] - 1.5) < 1e-3 && $0.border == wantRing
        }
        #expect(ringed.count == 1, "current match gets its 1.5pt ring: \(ringed)")
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo and scrollIntoView wiring"))
    func scrollIntoViewScrollsToHighlightedMatchInTallDocumentAndCodeBlock() {
        var doc = "# Searchable Document\n\n"
        for i in 0..<25 {
            doc += "Paragraph \(i) with filler words to push later content below the fold.\n\n"
        }
        doc += "Paragraph with the first_target_match in body text.\n\n"
        doc += "```rust\n"
        for i in 0..<30 {
            doc += "let line_\(i) = \(i);\n"
        }
        doc += "let deep_code_target = 42;\n```\n"

        let s1 = utf8ByteOffset(doc, "first_target_match")!
        let firstRange = s1..<(s1 + "first_target_match".utf8.count)
        let s2 = utf8ByteOffset(doc, "deep_code_target")!
        let codeRange = s2..<(s2 + "deep_code_target".utf8.count)

        struct SearchApp {
            var doc: String
            var r1: Range<Int>
            var r2: Range<Int>
        }

        func searchView(_ s: SearchApp, _: Cx<SearchApp>) -> El {
            let hls: [(Range<Int>, Highlight)] = [
                (s.r1, Highlight.new()),
                (s.r2, Highlight.current().key("code-hit")),
            ]
            return col()
                .key("doc-scroll")
                .wFull()
                .h(200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(Markdown.new(s.doc).highlights(hls).build(Kit.neutral(true)))
        }

        let rt = Runtime.new(
            SearchApp(doc: doc, r1: firstRange, r2: codeRange),
            searchView,
            (480.0, 200.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        let y1Initial = byKey(rt, Markdown.highlightKey(0)).rect[1]
        let y2Initial = byKey(rt, "code-hit").rect[1]
        #expect(y1Initial > 400.0 && y2Initial > y1Initial + 300.0, "initially below fold: \(y1Initial), \(y2Initial)")

        rt.update { _, tx in tx.scrollIntoView(Markdown.highlightKey(0)) }
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        let m1 = byKey(rt, Markdown.highlightKey(0)).rect
        #expect(m1[1] >= 0.0 && m1[1] + m1[3] <= 200.5, "first highlight scrolled into viewport: \(m1)")

        rt.update { _, tx in tx.scrollIntoView("code-hit") }
        for _ in 0..<30 {
            _ = rt.frame(1.0 / 60.0)
        }
        let m2 = byKey(rt, "code-hit").rect
        #expect(m2[1] >= 0.0 && m2[1] + m2[3] <= 200.5, "deep code-block highlight scrolled into viewport: \(m2)")
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo wiring"))
    func reviewHighlightMappingEdgesAndStreaming() {
        struct HlEdgeState {
            var src: String
            var marks: [(Range<Int>, Highlight)]
        }
        func view(_ st: HlEdgeState, _: Cx<HlEdgeState>) -> El {
            col().w(480.0).child(Markdown.new(st.src).highlights(st.marks).build(Kit.neutral(true)))
        }
        for (src, needle, expected) in [
            ("before &amp; after", "amp", "&"),
            ("before \\* after", "*", "*"),
            ("before <b>after</b>", "after", "after"),
            ("one\r\ntwo", "two", "two"),
            ("one  \r\ntwo", "two", "two"),
            ("> - nested **needle**", "needle", "needle"),
            ("left שלום world right", "שלום world", "שלום world"),
            ("| a | b |\n|---|---|\n| a\\|needle | end |", "needle", "needle"),
            ("| a |\n|---|\n| `a\\|needle` |", "needle", "needle"),
            ("`a\r\nb needle`", "needle", "needle"),
            ("`a\r\nbb cc dd ee ff gg hh`", "bb", "bb"),
            ("` a\r\nbb cc dd ee ff gg hh `", "bb", "bb"),
            ("`a bb cc dd ee ff gg\r\nhh ii`", "bb", "bb"),
            ("`a\r\nbb cc dd ee ff gg hh`", "gg", "gg"),
            ("> `one\n> two three four five`", "three", "three"),
            ("- `one\n  two three four five`", "three", "three"),
            ("https://example.org/needle", "needle", "needle"),
            ("reference [^needle]\n\n[^needle]: text", "needle", "needle"),
        ] {
            let start = utf8ByteOffset(src, needle)!
            let rt = Runtime.new(
                HlEdgeState(src: src, marks: [(start..<(start + needle.utf8.count), Highlight.new())]),
                view,
                (480.0, 200.0),
                Env.new(true, 1.0)
            )
            _ = rt.frame(0.0)
            let labels = rt.elements().filter { $0.role == "mark" }.compactMap(\.label)
            #expect(labels == [expected], "source=\(src)")
        }

        let src = "αβ **needle**\n\nsecond https://example.org/path"
        let srcBytes = Array(src.utf8)
        let start = utf8ByteOffset(src, "needle")!
        let marks: [(Range<Int>, Highlight)] = [
            (start..<(start + 6), Highlight.new()),
            (1..<3, Highlight.current()),
            ((Int.max - 1)..<Int.max, Highlight.new()),
        ]
        let rt = Runtime.new(HlEdgeState(src: "", marks: marks), view, (480.0, 200.0), Env.new(true, 1.0))
        for end in 0...srcBytes.count where isUtf8Boundary(srcBytes, end) {
            rt.state.src = String(decoding: srcBytes[0..<end], as: UTF8.self)
            rt.invalidate()
            _ = rt.frame(0.0)
            for e in rt.elements().filter({ $0.role == "mark" }) {
                #expect(e.key != "md-mark-2")
            }
        }
        rt.state.marks = [(start..<(start + 6), Highlight.current().fg(Color.WHITE))]
        rt.invalidate()
        _ = rt.frame(0.0)
        #expect(rt.stats.shaped == 0, "changing highlights including foreground must reuse the shape cache")
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo and synthetic #link- wiring"))
    func reviewMarksDoNotWrapLargeOffsetsOrInterceptLinks() {
        struct State {
            var opened: [String]
        }
        func view(_: State, _: Cx<State>) -> El {
            let src = "~~https://example.org/path~~ and שלום world"
            let big = Int(UInt32.max) + 1
            return col()
                .w(220.0)
                .child(
                    Markdown.new(src)
                        .selectable(true)
                        .highlights([(10..<24, Highlight.new()), (2..<26, Highlight.current().key("hit"))])
                        .onLink { (s: inout State, url: String) in s.opened.append(url) }
                        .build(Kit.neutral(true))
                )
                .child(
                    Rune.text("plain").textHighlight(
                        TextHighlight.new(big..<(big + 4), Color.WHITE).key("outside")
                    )
                )
        }
        let rt = Runtime.new(State(opened: []), view, (220.0, 180.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(rt.find("outside") == nil, "large offsets must not wrap to the beginning of text")
        #expect(!rt.elements().contains(where: { $0.key == "outside" }))
        let (x, y) = rt.find("hit")!
        rt.pointerMove(x, y)
        _ = rt.pointerDown(x, y)
        rt.pointerUp(x, y)
        _ = rt.frame(0.0)
        #expect(rt.state.opened == ["https://example.org/path"])
    }

    @Test func reviewAutolinksSkipImagesEmailsAndUnsafeSchemes() {
        let src = "HTTP://example.org/a, ![https://image.example/alt](image.png) [https://label.example](https://dest.example) <https://angle.example> `https://code.example` foo@bar.com javascript:alert(1) data:text/plain,test"
        let blocks = markdown.parse(src)
        guard case .para(let p) = blocks[0] else {
            Issue.record("expected paragraph: \(blocks)")
            return
        }
        #expect(p.links.map(\.2) == ["HTTP://example.org/a", "https://dest.example", "https://angle.example"])
    }

    @Test(.disabled("Requires Rune runtime TextHighlight synthetic mark ElementInfo wiring"))
    func reviewTwoThousandMatchesAddNoLayoutNodesOrShapes() {
        struct ManyMarksState {
            var src: String
            var marked: Bool
        }
        func view(_ st: ManyMarksState, _: Cx<ManyMarksState>) -> El {
            let ranges: [(Range<Int>, Highlight)] = st.marked
                ? utf8MatchIndices(st.src, "needle").map { ($0..<($0 + 6), Highlight.new()) }
                : []
            return col()
                .w(480.0)
                .h(200.0)
                .scroll(ScrollSpec(stickBottom: false))
                .child(Markdown.new(st.src).highlights(ranges).build(Kit.neutral(true)))
        }
        let src = String(repeating: "needle needle needle needle with some fictional filler words.\n\n", count: 500)
        let rt = Runtime.new(ManyMarksState(src: src, marked: false), view, (480.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let baseNodes = rt.elements().filter { $0.role != "mark" }.count
        rt.state.marked = true
        rt.invalidate()
        _ = rt.frame(0.0)
        #expect(rt.stats.shaped == 0)
        #expect(rt.elements().filter({ $0.role != "mark" }).count == baseNodes)
        #expect(rt.elements().filter({ $0.role == "mark" }).count == 2000)
        #expect(rt.find("md-mark-1999") != nil)
    }
}
