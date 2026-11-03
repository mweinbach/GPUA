// Tests ported from: crates/rune/src/runtime/input/modifier_keys.rs (#[cfg(test)] items)
// Upstream commit: 5f6d53ddae78
// Port status: ported

import Testing
@testable import Rune

@Suite("ModifierKeysTests")
struct ModifierKeysTests {
    @Test("Modifier press and release update heldModifiers, Mods flags, and dispatch Key.modifier events")
    func modifierPressReleaseUpdatesHeldStateAndDispatches() {
        var seen: [(Modifier, Bool, Bool)] = []
        let rt = Runtime.new(0, { _, _ in
            el().key("box").size(80.0, 40.0).focusable(true).onKey { (count: inout Int, ev, _) in
                if case .modifier(let m, let pressed) = ev.key {
                    seen.append((m, pressed, ev.mods.shift))
                    count += 1
                    return true
                }
                return false
            }
        }, (200.0, 200.0), Env.new(true, 1.0))
        _ = rt.frame(0.0)
        rt.focus("box")
        _ = rt.frame(0.0)

        #expect(rt.handleModifierKeyEvent(.shiftLeft, pressed: true, mods: Mods(shift: true)))
        #expect(rt.heldModifiers().contains(.shiftLeft))
        #expect(seen.count == 1)
        #expect(seen[0].0 == .shiftLeft && seen[0].1 == true && seen[0].2 == true)

        #expect(rt.handleModifierKeyEvent(.shiftLeft, pressed: false, mods: Mods()))
        #expect(rt.heldModifiers().isEmpty)
        #expect(seen.count == 2)
        #expect(seen[1].1 == false && seen[1].2 == false)

        _ = rt.handleModifierKeyEvent(.altRight, pressed: true, mods: Mods(alt: true))
        #expect(rt.heldModifiers().contains(.altRight))
        rt.clearModifiers()
        #expect(rt.heldModifiers().isEmpty)
    }
}
