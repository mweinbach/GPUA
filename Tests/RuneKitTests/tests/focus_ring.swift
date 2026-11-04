// Tests ported from: crates/rune-kit/tests/focus_ring.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
import Rune
@testable import RuneKit

private func focusRingView(_ s: TextEdit, _ cx: Cx<TextEdit>) -> El {
    let k = Kit.neutral(cx.systemDark())
    var layers: [El] = []
    let body = col().gap(8.0).itemsStart()
        .child(Button.new("Button").onPress { (_: inout TextEdit) in }.build(k))
        .child(IconButton.new(k.glyph.copy).onPress { (_: inout TextEdit) in }.build(k))
        .child(Switch.new(true).label("Switch").build(k))
        .child(Checkbox.new(false).label("Checkbox").build(k))
        .child(RadioGroup.new().item(RadioItem.new("Radio", true)).build(k))
        .child(SegmentedControl.new(["One", "Two"], 0).build(k))
        .child(Select.new("select", ["One", "Two"]).current("One").build(k, &layers))
        .child(TextInput.new(s).onEdit(\TextEdit.self).build(k))
    return root(body, layers)
}

@Suite("FocusRingTests")
struct FocusRingTests {
    /// Each control draws its own ring, so none adds the default one in the system focus colour.
    // PORT NOTE: Blocked on Sources/Rune default focusRing suppression when control supplies custom ring.
    @Test(.disabled("Blocked on Sources/Rune default focusRing suppression when control supplies custom ring"))
    func kitControlsDrawOneRingTheirOwn() {
        let rt = Runtime.new(TextEdit.new(""), focusRingView, (400.0, 600.0), Env.new(true, 1.0))
        rt.setTabVisitsControls(true)
        let pink = Color(r: 1.0, g: 0.0, b: 0.5, a: 1.0)
        rt.setSystemAccent(SystemAccent.new(pink, pink))
        _ = rt.frame(0.0)
        let defaultRing = pink.alpha(0.5).premul(1.0)
        var stops: [String] = []
        for _ in 0..<12 {
            _ = rt.keyDown(KeyEvent(key: .tab))
            _ = rt.frame(0.0)
            guard let at = rt.elements().first(where: { $0.focused })?.path else { continue }
            #expect(!rt.instances.contains(where: { $0.border == defaultRing }), "\(at) drew the default ring")
            if !stops.contains(at) {
                stops.append(at)
            }
        }
        #expect(stops.count >= 8, "Tab visited \(stops)")
    }
}
