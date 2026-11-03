// Ported from: crates/rune/src/runtime/input/hover.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Ancestor-chain hover tracking, `onHoverHandler` enter/leave callbacks, `P_HOVER` track updates, and cursor resolution.

extension Runtime {
    func updateHoverAt(_ x: Float, _ y: Float, commitIfChanged: Bool) {
        let hitIdx = hitTestNode(x, y, includeTransparent: false, requireInteractive: false)
        var newChain: Set<String> = []
        var orderedChain: [Int] = []
        var cur = hitIdx
        while let idx = cur {
            if !nodes[idx].inert {
                newChain.insert(nodes[idx].path)
                orderedChain.append(idx)
            }
            cur = nodes[idx].parent
        }

        // Update cursor based on deepest hit
        currentCursor = resolveCursorForChain(orderedChain, x: x, y: y)

        // Update tooltip help candidate
        updateHelpHover(orderedChain, x: x, y: y)

        guard newChain != hoveredPaths else { return }
        let leftPaths = hoveredPaths.subtracting(newChain)
        let enteredPaths = newChain.subtracting(hoveredPaths)
        hoveredPaths = newChain

        // Update P_HOVER tracks in scene immediately without requiring a full commit if no handler mutates state
        for i in nodes.indices where nodes[i].vis.hover.a > 0.0 {
            let p = nodes[i].path
            if leftPaths.contains(p) {
                if readyFromRest(scene, nodes[i].nodeId, P_HOVER, 0.0, 0.0) {
                    let outOfView = nodes[i].visibleRect[2] <= 0.01 || nodes[i].visibleRect[3] <= 0.01
                    if reducedMotion || outOfView {
                        scene.set(nodes[i].nodeId, P_HOVER, 0.0)
                    } else {
                        scene.animate(nodes[i].nodeId, P_HOVER, 0.0, tok.motion.INSTANT)
                    }
                }
            } else if enteredPaths.contains(p) {
                if readyFromRest(scene, nodes[i].nodeId, P_HOVER, 0.0, 1.0) {
                    scene.set(nodes[i].nodeId, P_HOVER, 1.0)
                }
            }
        }

        // Fire `onHoverHandler` on left then entered nodes
        var anyHandlerFired = false
        for i in nodes.indices where leftPaths.contains(nodes[i].path) {
            if let handler = nodes[i].onHoverHandler {
                anyHandlerFired = true
                var tx = newTx()
                let states = makeStates()
                handler(states, false, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.HOVER)
            }
        }
        for i in nodes.indices where enteredPaths.contains(nodes[i].path) {
            if let handler = nodes[i].onHoverHandler {
                anyHandlerFired = true
                var tx = newTx()
                let states = makeStates()
                handler(states, true, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.HOVER)
            }
        }

        if anyHandlerFired && commitIfChanged && dirty {
            performCommit()
        }
    }

    private func resolveCursorForChain(_ chain: [Int], x: Float, y: Float) -> Cursor {
        if activeDragNodePath != nil {
            return .grabbing
        }
        for idx in chain {
            let n = nodes[idx]
            if n.input != nil {
                return .text
            }
            if hitLinkInNode(nodeIdx: idx, windowX: x, windowY: y) != nil {
                return .pointer
            }
            if n.onPressHandler != nil || n.role == "button" || n.role == "link" {
                return .pointer
            }
            if n.textSpec?.selectable == true {
                return .text
            }
        }
        return .default
    }

    public func pointerLeave() {
        lastPointer = nil
        clearHelpHover()
        guard !hoveredPaths.isEmpty else { return }
        let left = hoveredPaths
        hoveredPaths.removeAll()
        for i in nodes.indices where left.contains(nodes[i].path) {
            if nodes[i].vis.hover.a > 0.0 && readyFromRest(scene, nodes[i].nodeId, P_HOVER, 0.0, 0.0) {
                if reducedMotion {
                    scene.set(nodes[i].nodeId, P_HOVER, 0.0)
                } else {
                    scene.animate(nodes[i].nodeId, P_HOVER, 0.0, tok.motion.INSTANT)
                }
            }
            if let handler = nodes[i].onHoverHandler {
                var tx = newTx()
                let states = makeStates()
                handler(states, false, &tx)
                commitStates(states)
                applyTx(&tx, why: CommitWhy.HOVER)
            }
        }
        currentCursor = .default
    }
}
