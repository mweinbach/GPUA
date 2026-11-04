// Tests ported from: crates/rune-kit/tests/segmented.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private func segmentedRect(_ rt: Runtime<Int>, _ key: String) -> [Float] {
    guard let found = rt.elements().first(where: { $0.key == key }) else {
        Issue.record("no \(key)")
        return [0, 0, 0, 0]
    }
    return found.rect
}

private func fittedSegmentedView(_ selected: Int, _: Cx<Int>) -> El {
    Rune.row().child(
        SegmentedControl.new(["A", "Much longer label", "日本語"], selected)
            .fit()
            .build(Kit.neutral(true))
            .key("seg")
    )
}

private func pickableSegmentedView(_ selected: Int, _: Cx<Int>) -> El {
    Rune.row().child(
        SegmentedControl.new(["Left", "Either", "Right"], selected)
            .fit()
            .onPick { (s: inout Int, i: Int, _: inout Tx) in
                s = i
            }
            .build(Kit.neutral(true))
            .key("seg")
    )
}

private func segmentedHover(_ rt: Runtime<Int>, _ key: String) -> Float {
    rt.elements().first(where: { $0.key == key })!.hover
}

private func selectTriggerFieldView(_: Int, _: Cx<Int>) -> El {
    Rune.row().child(
        Select.new("model", [] as [String])
            .appearance(.field)
            .width(200.0)
            .current("Parakeet")
            .open(true)
            .trigger(Kit.neutral(true))
    )
}

@Suite("SegmentedTests")
struct SegmentedTests {
    // PORT NOTE: Blocked on Sources/Rune equalColumns CSS Grid track sizing & resting hover state on pressable segments.
    @Test(.disabled("Blocked on Sources/Rune equalColumns CSS Grid track sizing & resting hover state on pressable segments"))
    func fittedSegmentsShareTheWidestLabelsWidthAndTheIndicatorSlidesBetweenThem() {
        let rt = Runtime.new(0, fittedSegmentedView, (600.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let widths: [Float] = (0..<3).map { i in segmentedRect(rt, "segment\(i)")[2] }
        #expect(widths.allSatisfy { abs($0 - widths[0]) < 0.01 }, "equal segments: \(widths)")
        let label = rt.elements()
            .first(where: { $0.text == "Much longer label" })!
            .rect[2]
        #expect(widths[1] >= label + 24.0 - 0.01, "the widest label fits with its padding: \(widths) vs \(label)")
        let sumWidths = widths.reduce(Float(0.0), +)
        #expect(abs(segmentedRect(rt, "seg")[2] - sumWidths) < 0.01)
        #expect(segmentedRect(rt, "indicator")[0] == segmentedRect(rt, "segment0")[0])

        rt.state = 2
        rt.invalidate()
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 60.0)
        }
        let indicator = segmentedRect(rt, "indicator")
        let target = segmentedRect(rt, "segment2")
        #expect(abs(indicator[0] - target[0]) < 0.01 && abs(indicator[2] - target[2]) < 0.01)
    }

    // PORT NOTE: Blocked on Sources/Rune equalColumns CSS Grid track sizing & resting hover state on pressable segments.
    @Test(.disabled("Blocked on Sources/Rune equalColumns CSS Grid track sizing & resting hover state on pressable segments"))
    func anUnselectedSegmentHoversOnTheFirstFrameAndFadesAsThePointerLeaves() {
        let rt = Runtime.new(1, pickableSegmentedView, (600.0, 100.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        let (x0, y0) = rt.find("segment0")!
        rt.pointerMove(x0, y0)
        _ = rt.frame(1.0 / 120.0)
        #expect(segmentedHover(rt, "segment0") == 1.0, "the first frame under the pointer is fully hovered")

        let (x1, y1) = rt.find("segment1")!
        rt.pointerMove(x1, y1)
        _ = rt.frame(1.0 / 120.0)
        let leaving = segmentedHover(rt, "segment0")
        #expect(leaving > 0.0 && leaving < 1.0, "leaving fades: \(leaving)")
        #expect(segmentedHover(rt, "segment1") == 0.0, "the selected segment stays as it is")

        _ = rt.frame(0.5)
        #expect(segmentedHover(rt, "segment0") == 0.0)
    }

    @Test
    func aSelectTriggerIsTheClosedFieldWithoutAListbox() {
        let rt = Runtime.new(0, selectTriggerFieldView, (400.0, 300.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        #expect(segmentedRect(rt, "model-trigger")[2] == 200.0)
        #expect(
            rt.elements().allSatisfy { $0.role != "listbox" },
            "open turns the chevron but builds no listbox"
        )
    }
}
