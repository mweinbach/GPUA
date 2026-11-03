// Ported from: crates/rune/src/runtime/input/action.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Execute resolved press / secondary-press / link actions on committed nodes.

extension Runtime {
    func dispatchPress(nodeIdx: Int) -> Bool {
        guard nodes.indices.contains(nodeIdx), !nodes[nodeIdx].inert else { return false }
        guard let handler = nodes[nodeIdx].onPressHandler else { return false }
        pushEventMarker(kind: "press", detail: nodes[nodeIdx].key ?? nodes[nodeIdx].path)
        var tx = newTx()
        tx.shortcutActivationToken = pressActivationToken(currentAppId())
        let states = makeStates()
        handler(states, &tx)
        commitStates(states)
        applyTx(&tx, why: CommitWhy.PRESS)
        return true
    }

    func dispatchSecondaryPress(nodeIdx: Int, windowX: Float, windowY: Float) -> Bool {
        // Bubble up to nearest ancestor with `onSecondaryPressHandler`
        var cur: Int? = nodeIdx
        while let idx = cur {
            if !nodes[idx].inert, let handler = nodes[idx].onSecondaryPressHandler {
                let r = nodes[idx].presentedRect
                let ev = PointerEvent(
                    x: windowX - r[0],
                    y: windowY - r[1],
                    windowX: windowX,
                    windowY: windowY
                )
                var tx = newTx()
                tx.buttonPressed = .secondary
                let states = makeStates()
                handler(states, ev, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.SECONDARY)
                return true
            }
            cur = nodes[idx].parent
        }
        return false
    }
}
