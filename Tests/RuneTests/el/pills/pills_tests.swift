// Tests ported from: crates/rune/src/el/pills/tests.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

private let INK = Color(1.0, 0.0, 0.0, 1.0)
private let CHIP = Color(0.0, 0.0, 1.0, 0.2)

private func utf8Find(_ haystack: String, _ needle: String) -> Int {
    guard let r = haystack.range(of: needle) else {
        preconditionFailure("substring \(needle) not found")
    }
    return haystack.utf8.distance(from: haystack.utf8.startIndex, to: r.lowerBound.samePosition(in: haystack.utf8)!)
}

@Suite("PillsTests")
struct PillsTests {
    @Test("pills record sorted chips and skip bad ranges")
    func pillsRecordSortedChipsAndSkipBadRanges() {
        let body = "ask @code-reviewer about @src/main.rs — é"
        let bodyLen = body.utf8.count
        let agentStart = utf8Find(body, "@code-reviewer")
        let agent = agentStart..<(agentStart + 14)
        let fileStart = utf8Find(body, "@src/main.rs")
        let file = fileStart..<(fileStart + 12)

        let e = text(body).pills([
            (file, PillStyle.new().bg(CHIP)),
            (agent, PillStyle.new().fg(INK)),
            ((agent.lowerBound + 1)..<(agent.upperBound + 2), PillStyle.new()),
            (5..<5, PillStyle.new()),
            ((bodyLen - 1)..<bodyLen, PillStyle.new()),
            (0..<(bodyLen + 1), PillStyle.new()),
        ])
        guard let t = e.textSpec?.value else {
            Issue.record("expected textSpec on text element")
            return
        }
        #expect(t.pills.count == 2)
        #expect(t.pills[0] == PillChip(start: UInt32(agent.lowerBound), end: UInt32(agent.upperBound), icon: nil, bg: nil, fg: INK))
        #expect(t.pills[1] == PillChip(start: UInt32(file.lowerBound), end: UInt32(file.upperBound), icon: nil, bg: CHIP, fg: nil))
    }

    @Test("a pill colours its label and keeps it through later spans")
    func aPillColoursItsLabelAndKeepsItThroughLaterSpans() {
        let body = "ask @reviewer to look"
        let e = rich(body, [Span.new(0, 3).bold()])
            .pill(4..<13, PillStyle.new().fg(INK))
            .spans([Span.new(14, 16).italic()])
        guard let t = e.textSpec?.value else {
            Issue.record("expected textSpec on rich element")
            return
        }
        let inkRanges = t.spans.filter { $0.color == INK }.map { ($0.start, $0.end) }
        #expect(inkRanges.count == 1)
        #expect(inkRanges[0] == (4, 13))
        #expect(t.spans.contains { $0.italic && ($0.start, $0.end) == (14, 16) })
    }

    @Test("a field ignores static pills")
    func aFieldIgnoresStaticPills() {
        let e = textInput(TextEdit.new("ask @reviewer"), TextStyle.new(14.0, 400.0))
            .pill(4..<13, PillStyle.new().fg(INK))
        #expect(e.textSpec?.value.pills.isEmpty == true)
    }

    @Test("pills survive streaming appends and bad ranges are ignored")
    func pillsSurviveStreamingAppendsAndBadRangesAreIgnored() {
        // PORT NOTE: Parley line-shaping (`TextSystem.layoutForSpec`) and pointer-drag selectable copy
        // (`Runtime.pointerDown` / `Runtime.selectedText`) live in `text/` and `runtime/` (not yet ported).
        // Here we verify `El.pills` streaming append survival and invalid-UTF8/out-of-bounds rejection across commits.
        struct StreamState {
            var body: String
            var pills: [Range<Int>]
            var width: Float
        }

        func streamView(_ s: StreamState, _ cx: Cx<StreamState>) -> El {
            _ = cx
            let t = text(s.body)
                .key("t")
                .font(TextStyle.new(14.0, 400.0).lh(20.0))
                .w(s.width)
                .wrap()
                .selectable(true)
            return col().key("root").padding(10.0).child(
                t.pills(s.pills.map { ($0, PillStyle.new()) })
            )
        }

        let rt = Runtime(
            StreamState(body: "ask @reviewer", pills: [4..<13], width: 400.0),
            streamView,
            (600.0, 400.0),
            Env.new(true, 1.0)
        )
        _ = rt.frame(0.0)

        func currentPills() -> [Range<UInt32>] {
            let built = streamView(rt.state, Cx(env: rt.env, reducedMotion: false, timeScale: 1.0))
            return built.children[0].textSpec?.value.pills.map { $0.start..<$0.end } ?? []
        }

        for more in [" to", " look at", " the é diff"] {
            rt.update { s, _ in s.body += more }
            _ = rt.frame(1.0 / 60.0)
            #expect(currentPills() == [4..<13])
        }

        // Past the end, inside "é", or empty: skipped, and the frame still commits cleanly.
        let eByte = utf8Find(rt.state.body, "é")
        rt.update { s, _ in
            s.pills = [4..<13, (eByte + 1)..<(eByte + 2), 30..<400, 20..<20]
        }
        _ = rt.frame(2.0 / 60.0)
        #expect(currentPills() == [4..<13])

        rt.update { s, _ in
            s.body = String(s.body.prefix(8))
        }
        _ = rt.frame(3.0 / 60.0)
        #expect(currentPills().isEmpty)
    }
}
