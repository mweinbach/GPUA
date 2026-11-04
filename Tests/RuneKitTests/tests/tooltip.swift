// Tests ported from: crates/rune-kit/tests/tooltip.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private let longTooltipLabel = "PR #123 · Open · CI passing · Move the sidebar search into the toolbar and keep its results"

private func tooltipByKey(_ rt: Runtime<UInt8>, _ key: String) -> ElementInfo {
    guard let found = rt.elements().first(where: { $0.key == key }) else {
        Issue.record("no \(key)")
        return ElementInfo(path: "")
    }
    return found
}

private func tooltipWords(_ rt: Runtime<UInt8>, _ s: String) -> ElementInfo {
    rt.elements().first(where: { $0.text == s })!
}

private func tooltipTestView(_ which: UInt8, _: Cx<UInt8>) -> El {
    var layer: [El] = []
    let tip = Tooltip.new("t").trigger(Rune.text("?")).open(true)
    let built: El
    switch which {
    case 0:
        built = tip
            .label(longTooltipLabel)
            .render(TooltipStyle.neutral(true).maxWidth(160.0).padding(8.0, 5.0), &layer)
    case 1:
        let k = Kit.neutral(true)
        let long = "\(longTooltipLabel) \(longTooltipLabel)"
        built = tip
            .appearance(.standard)
            .text(k, long)
            .build(k, &layer)
    case 3:
        built = tip
            .child(Rune.text(longTooltipLabel).wrap())
            .child(Rune.text("⌘K").key("chip"))
            .render(TooltipStyle.neutral(true).maxWidth(160.0).padding(8.0, 5.0), &layer)
    default:
        built = tip
            .label("Help")
            .render(TooltipStyle.neutral(true).maxWidth(160.0).padding(8.0, 5.0), &layer)
    }
    return RuneKit.root(
        Rune.col().wFull().pt(200.0).itemsCenter().child(built),
        layer
    )
}

@Suite("TooltipTests")
struct TooltipTests {
    /// A long label wraps at the style's max width, inside the box: 0 by `label`, 1 by a kit's
    /// Standard tooltip (`text`, max 320), 2 a short label that stays one line.
    @Test
    func aTooltipLabelWrapsInsideItsMaxWidth() {
        let laidOut = { (which: UInt8) -> Runtime<UInt8> in
            let rt = Runtime.new(which, tooltipTestView, (800.0, 400.0), Env.new(true, 1.0))
            _ = rt.frame(0.0)
            for _ in 0..<60 {
                _ = rt.frame(1.0)
            }
            return rt
        }

        let rt0 = laidOut(0)
        let tip0 = tooltipByKey(rt0, "t-tooltip").target
        let w0 = tooltipWords(rt0, longTooltipLabel).target
        #expect(tip0[2] == 160.0)
        #expect(w0[0] >= tip0[0] + 8.0 && w0[0] + w0[2] <= tip0[0] + tip0[2] - 8.0, "\(w0) inside \(tip0)")
        #expect(w0[3] > 30.0 && tip0[3] >= w0[3] + 10.0, "several lines, and the box holds them: \(w0) \(tip0)")

        let rt1 = laidOut(1)
        let doubled = "\(longTooltipLabel) \(longTooltipLabel)"
        let tip1 = tooltipByKey(rt1, "t-tooltip").target
        let w1 = tooltipWords(rt1, doubled).target
        #expect(tip1[2] == 320.0)
        #expect(w1[0] + w1[2] <= tip1[0] + tip1[2] && w1[3] > 20.0, "\(w1) inside \(tip1)")

        // A wrapping child wraps inside the box without `.shrink()`, and a chip beside it keeps its width.
        let rt3 = laidOut(3)
        let tip3 = tooltipByKey(rt3, "t-tooltip").target
        let w3 = tooltipWords(rt3, longTooltipLabel).target
        let chip = tooltipByKey(rt3, "chip").target
        #expect(tip3[2] == 160.0)
        #expect(w3[2] <= tip3[2] - 16.0 && w3[0] + w3[2] <= chip[0], "\(w3) inside \(tip3), before \(chip)")
        #expect(chip[0] + chip[2] <= tip3[0] + tip3[2] - 8.0 + 0.01 && chip[2] > 10.0, "\(chip) inside \(tip3)")
        #expect(w3[3] > 30.0, "several lines: \(w3)")

        let rt2 = laidOut(2)
        let tip2 = tooltipByKey(rt2, "t-tooltip").target
        let w2 = tooltipWords(rt2, "Help").target
        #expect(tip2[2] < 60.0 && tip2[2] == w2[2] + 16.0, "a short label keeps its own width: \(w2) \(tip2)")
    }
}
