// Ported from: crates/rune/src/runtime/input/modifier_keys.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Standalone modifier key press/release state (`Modifier`, `KeySide`) and chord cancellation.

func updateHeldMods(_ mods: inout Mods, modifier: Modifier, pressed: Bool) {
    switch modifier {
    case .shiftLeft, .shiftRight:
        mods.shift = pressed
    case .controlLeft, .controlRight:
        mods.ctrl = pressed
        #if !os(macOS)
        mods.cmd = pressed
        #endif
    case .altLeft, .altRight:
        mods.alt = pressed
    case .superLeft, .superRight:
        mods.logo = pressed
        #if os(macOS)
        mods.cmd = pressed
        #endif
    case .fn:
        break
    }
}

extension Runtime {
    func handleModifierKeyEvent(_ mod: Modifier, pressed: Bool, mods: Mods) -> Bool {
        if pressed {
            heldModifierKeys.insert(mod)
        } else {
            heldModifierKeys.remove(mod)
        }
        heldMods = mods
        updateHeldMods(&heldMods, modifier: mod, pressed: pressed)

        let ev = KeyEvent(key: .modifier(modifier: mod, pressed: pressed), mods: heldMods)

        // Dispatch to focused node chain and app `onKey` when opted into modifier events
        if let fPath = focusedPath, let startIdx = keyIndex.nodeByPath(fPath) {
            var cur: Int? = startIdx
            while let idx = cur {
                if !nodes[idx].inert, let handler = nodes[idx].onKeyHandler {
                    var tx = newTx()
                    let states = makeStates()
                    let handled = handler(states, ev, &tx)
                    commitStates(states)
                    applyTx(&tx, why: CommitWhy.MODIFIERS)
                    if handled { return true }
                }
                cur = nodes[idx].parent
            }
        }

        if let appKeyHandler = onKey {
            var tx = newTx()
            let handled = appKeyHandler(&state, ev, &tx)
            applyTx(&tx, why: CommitWhy.MODIFIERS)
            return handled
        }

        return false
    }

    public func heldModifiers() -> Set<Modifier> {
        heldModifierKeys
    }

    public func clearModifiers() {
        heldModifierKeys.removeAll()
        heldMods = Mods()
    }
}
