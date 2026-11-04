// Tests ported from: crates/rune-kit/tests/button_label.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private struct ButtonLabelState {
    var label: String
    var rolling: Bool
}

private struct EmptyState {}

private func buttonLabelView(_ s: ButtonLabelState, _: Cx<ButtonLabelState>) -> El {
    let k = Kit.neutral(true)
    let b = Button.new(s.label)
    let configured = s.rolling ? b.rolling("import-label") : b
    return Rune.row().padding(20.0).child(configured.build(k).key("button"))
}

private func makeRuntime(_ label: String, _ rolling: Bool) -> Runtime<ButtonLabelState> {
    let rt = Runtime.new(
        ButtonLabelState(label: label, rolling: rolling),
        buttonLabelView,
        (400.0, 100.0),
        Env.new(true, 2.0)
    )
    _ = rt.frame(0.0)
    return rt
}

private func buttonRect<T>(_ rt: Runtime<T>, _ key: String) -> [Float] {
    guard let p = rt.presented(key) else {
        preconditionFailure("no \(key)")
    }
    return p.0
}

@Suite("ButtonLabelTests", .serialized)
struct ButtonLabelTests {
    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aRollingLabelSizesTheButtonAsPlainTextDoes() {
        for label in ["Import 3 items", "Importing\u{2026}"] {
            let rolling = buttonRect(makeRuntime(label, true), "button")
            let plain = buttonRect(makeRuntime(label, false), "button")
            #expect(abs(rolling[2] - plain[2]) < 0.5, "\(label): \(rolling) vs \(plain)")
            #expect(rolling[3] == plain[3])
        }
    }

    @Test
    func aCustomLabelGetsTheButtonsFontAndInk() {
        func custom(_: EmptyState, _: Cx<EmptyState>) -> El {
            let k = Kit.neutral(true)
            return Rune.row()
                .child(Button.new("Save").build(k).key("plain"))
                .child(
                    Button.new("Save")
                        .labelWith { font, ink in
                            Rune.text("Save").key("custom").font(font).color(ink)
                        }
                        .build(k)
                        .key("rich")
                )
        }
        let rt = Runtime.new(EmptyState(), custom, (400.0, 100.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        let els = rt.elements()
        func find(_ path: String) -> ElementInfo {
            guard let e = els.first(where: { $0.path.hasSuffix(path) }) else {
                preconditionFailure("no \(path)")
            }
            return e
        }
        #expect(find("rich").label == "Save")
        #expect(find("rich/custom").textColor == find("plain/label").textColor)
        #expect(find("rich").rect[2] == find("plain").rect[2])
    }

    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func theButtonSpringsWithItsRollingLabelAndKeepsItsAccessibleLabel() {
        let rt = makeRuntime("Import 3 items", true)
        func info(_ rt: Runtime<ButtonLabelState>) -> ElementInfo {
            rt.elements().first(where: { $0.key == "button" })!
        }
        #expect(info(rt).role == "button")
        #expect(info(rt).label == "Import 3 items")
        let from = buttonRect(rt, "button")
        // The label's right edge sits this far inside the button's at rest.
        let labelFrom = buttonRect(rt, "import-label")
        let inset = from[0] + from[2] - (labelFrom[0] + labelFrom[2])
        let to = buttonRect(makeRuntime("Importing\u{2026}", false), "button")
        #expect(from[2] - to[2] > 10.0, "the label shrinks: \(from) -> \(to)")

        rt.state.label = "Importing\u{2026}"
        rt.invalidate()
        _ = rt.frame(0.0)
        #expect(info(rt).label == "Importing\u{2026}")
        var widths: [Float] = [buttonRect(rt, "button")[2]]
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            let b = buttonRect(rt, "button")
            let l = buttonRect(rt, "import-label")
            widths.append(b[2])
            let gap = b[0] + b[2] - (l[0] + l[2])
            #expect(abs(gap - inset) < 0.5, "the padding holds as both spring: \(gap) vs \(inset)")
        }
        #expect(abs(widths[0] - from[2]) < 1.0, "no snap: starts at the old width \(widths[0]) vs \(from[2])")
        for i in 0..<(widths.count - 1) {
            #expect(abs(widths[i + 1] - widths[i]) < 4.0, "no jumps: \(widths)")
        }
        #expect(widths[12] < from[2] - 1.0 && widths[12] > to[2] + 1.0, "springs between: \(widths[12])")
        #expect(abs(widths.last! - to[2]) < 0.5, "lands on the new width: \(widths)")
    }

    // PORT NOTE: Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs.
    @Test(.disabled("Blocked on Sources/Rune El.advanceIn / Run glyph-advance measurement & animateLayout springs"))
    func aRollingButtonWithAnIconAndNeighbourSpringsWithoutJumps() {
        func rowView(_ label: String, _: Cx<String>) -> El {
            let k = Kit.neutral(true)
            return Rune.row()
                .padding(20.0)
                .gap(8.0)
                .child(Button.new(label).icon(k.glyph.lock).rolling("import-row-label").build(k).key("button"))
                .child(Button.new("Cancel").build(k).key("cancel"))
                .child(Button.new(label).icon(k.glyph.lock).rolling("fixed-row-label").build(k).key("fixed").w(180.0))
        }
        let rt = Runtime.new("Import 3 items", rowView, (500.0, 100.0), Env.new(true, 2.0))
        _ = rt.frame(0.0)
        func iconGap(_ rt: Runtime<String>) -> Float {
            let els = rt.elements()
            let ic = els.first(where: { $0.path.hasSuffix("fixed/icon") })!.rect
            let lb = els.first(where: { $0.key == "fixed-row-label" })!.rect
            return lb[0] - (ic[0] + ic[2])
        }
        let restIconGap = iconGap(rt)
        let cancelFrom = buttonRect(rt, "cancel")[0]

        rt.state = "Importing\u{2026}"
        rt.invalidate()
        _ = rt.frame(0.0)
        var cancelXs: [Float] = [buttonRect(rt, "cancel")[0]]
        for _ in 0..<120 {
            _ = rt.frame(1.0 / 120.0)
            cancelXs.append(buttonRect(rt, "cancel")[0])
            let g = iconGap(rt)
            #expect(abs(g - restIconGap) < 0.6, "icon and rolling label move on the same curve: \(g) vs \(restIconGap)")
        }
        #expect(abs(cancelXs[0] - cancelFrom) < 1.0, "neighbour starts at its old x: \(cancelXs[0]) vs \(cancelFrom)")
        for i in 0..<(cancelXs.count - 1) {
            #expect(abs(cancelXs[i + 1] - cancelXs[i]) < 4.0, "neighbour slides with no jump: \(cancelXs)")
        }
    }
}
