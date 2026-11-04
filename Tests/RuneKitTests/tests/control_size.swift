// Tests ported from: crates/rune-kit/tests/control_size.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct ControlSizeEmpty {}

private let ALL_CONTROL_SIZES: [ControlSize] = [.mini, .small, .regular, .large, .extraLarge]

@available(*, deprecated)
private func controlSizeButtonsView(_: ControlSizeEmpty, _ cx: Cx<ControlSizeEmpty>) -> El {
    let k = Kit.neutral(cx.systemDark())
    var c = col().itemsStart()
    for (i, s) in ALL_CONTROL_SIZES.enumerated() {
        c = c.child(Button.new("Button").controlSize(s).build(k).key("button-\(i)"))
        c = c.child(IconButton.new(k.glyph.copy).controlSize(s).build(k).key("icon-\(i)"))
    }
    let legacySizes: [ButtonSize] = [.small, .normal, .large]
    return c.child(Button.new("Button").build(k).key("default"))
        .child(IconButton.new(k.glyph.copy).build(k).key("icon-default"))
        .children(legacySizes.enumerated().map { (i, s) in
            col()
                .child(Button.new("Button").size(s).build(k).key("legacy-\(i)"))
                .child(IconButton.new(k.glyph.copy).size(s).build(k).key("legacy-icon-\(i)"))
        })
}

private func controlSizeSwitchesView(_: ControlSizeEmpty, _ cx: Cx<ControlSizeEmpty>) -> El {
    let k = Kit.neutral(cx.systemDark())
    var c = col().itemsStart()
    let variants: [(Bool, State)] = [(false, .rest), (true, .rest), (false, .pressed)]
    for (i, s) in ALL_CONTROL_SIZES.enumerated() {
        for (j, (on, st)) in variants.enumerated() {
            c = c.child(Switch.new(on).controlSize(s).state(st).build(k).key("switch-\(i)-\(j)"))
        }
    }
    return c
}

@Suite("ControlSizeTests")
struct ControlSizeTests {
    @Test
    @available(*, deprecated)
    func controlSizesMatchAppkitPushButtonsAndOldSizesKeepTheirMetrics() {
        let rt = Runtime.new(
            ControlSizeEmpty(),
            controlSizeButtonsView,
            (400.0, 900.0),
            Env(systemDark: false, scale: 2.0)
        )
        _ = rt.frame(0.0)
        let els = rt.elements()
        func size(_ key: String) -> (Float, Float) {
            guard let e = els.first(where: { $0.key == key }) else {
                preconditionFailure("\(key)")
            }
            return (e.rect[2], e.rect[3])
        }
        let expectedHeights: [Float] = [16.0, 20.0, 24.0, 28.0, 36.0]
        for (i, h) in expectedHeights.enumerated() {
            #expect(size("button-\(i)").1 == h, "push button \(i)")
            #expect(size("icon-\(i)") == (h, h), "icon button \(i)")
        }
        #expect(size("default").1 == 24.0, "a button is Regular unless sized")
        #expect(size("icon-default") == (24.0, 24.0))
        let legacyMetrics: [(Float, Float)] = [(24.0, 20.0), (28.0, 24.0), (32.0, 28.0)]
        for (i, (h, side)) in legacyMetrics.enumerated() {
            #expect(size("legacy-\(i)").1 == h, "ButtonSize keeps its height")
            #expect(size("legacy-icon-\(i)") == (side, side))
        }
        // Wider padding as the size grows, as AppKit's: 8, 10, 12, 14 and 18 points a side.
        let widths: [Float] = (0..<5).map { i in size("button-\(i)").0 }
        for i in 0..<(widths.count - 1) {
            #expect(widths[i] < widths[i + 1], "\(widths)")
        }
    }

    @Test
    func switchesHaveAppkitCapsuleTracksAndPillKnobs() {
        let rt = Runtime.new(
            ControlSizeEmpty(),
            controlSizeSwitchesView,
            (400.0, 900.0),
            Env(systemDark: false, scale: 2.0)
        )
        _ = rt.frame(0.0)
        rt.settleAll()
        _ = rt.frame(0.0)
        let els = rt.elements()
        func parts(_ key: String) -> (ElementInfo, ElementInfo) {
            let rootEl = els.first(where: { $0.key == key })!
            func under(_ k: String) -> ElementInfo {
                els.first(where: { $0.key == k && $0.path.hasPrefix(rootEl.path) })!
            }
            return (under("control"), under("thumb"))
        }
        let measured: [(Float, Float, Float, Float, Float)] = [
            (36.0, 16.0, 21.0, 14.0, 1.0),
            (44.0, 20.0, 26.0, 16.0, 2.0),
            (54.0, 24.0, 32.0, 20.0, 2.0),
            (64.0, 28.0, 38.0, 24.0, 2.0),
            (80.0, 36.0, 48.0, 30.0, 3.0),
        ]
        for (i, (tw, th, kw, kh, inset)) in measured.enumerated() {
            let (track, off) = parts("switch-\(i)-0")
            #expect((track.rect[2], track.rect[3], track.radius) == (tw, th, th / 2.0), "track \(i)")
            #expect((off.rect[2], off.rect[3], off.radius) == (kw, kh, kh / 2.0), "knob \(i)")
            #expect((off.rect[0] - track.rect[0], off.rect[1] - track.rect[1]) == (inset, inset), "inset \(i)")
            let (trackOn, on) = parts("switch-\(i)-1")
            #expect(trackOn.rect[0] + tw - (on.rect[0] + on.rect[2]) == inset, "on sits at the far end \(i)")
            let (_, pressed) = parts("switch-\(i)-2")
            #expect(pressed.rect[2] > kw && pressed.rect[3] == kh, "a pressed knob stretches \(i)")
        }
    }
}
