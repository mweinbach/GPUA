// Ported from: crates/rune/src/runtime/motion/tracks.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Synchronize node opacity, scale, corner radii, blur, fill, border, text color, shadows, outline,
//! icon turn, hover, press, and group-opacity tracks in `RuneMotion.Scene`, plus `settleAll`.

import RuneMotion

extension Runtime {
    func syncNodeMotionTracks(nodeIdx: Int, prevNode: Node?, wasPresent: Bool, forceInstant: Bool) {
        let node = nodes[nodeIdx]
        let id = node.nodeId
        let instant = forceInstant || node.instantChanges || !wasPresent

        let baseSpring = pendingMotionSpring ?? node.motionSpring
        let layoutSpring = baseSpring ?? tok.motion.REFLOW
        let colorSpring = pendingColorSpring ?? baseSpring ?? tok.motion.SNAP

        // Opacity (`NodeSpec` sets initial opacity on mount without allocating a track)
        let opAnim: Anim? = {
            if instant { return nil }
            if let oa = node.opacityMotionAnim { return oa }
            if let mc = pendingMotionCurve { return mc }
            return Anim(layoutSpring)
        }()
        if wasPresent && !node.liveBindings.contains(where: { $0.property == .opacity }) {
            let opacityChanged = prevNode.map { abs($0.vis.opacity - node.vis.opacity) > 1e-6 } ?? false
            if opacityChanged || scene.store().has(id, RuneMotion.prop.opacity) {
                if let anim = opAnim, anim != .instant, !reducedMotion {
                    let curTarget = scene.store().target(id, RuneMotion.prop.opacity) ?? scene.get(id, RuneMotion.prop.opacity)
                    if curTarget.map({ abs($0 - node.vis.opacity) > 1e-6 }) ?? true {
                        scene.animate(id, RuneMotion.prop.opacity, node.vis.opacity, anim)
                    }
                } else {
                    scene.set(id, RuneMotion.prop.opacity, node.vis.opacity)
                }
            }
        }

        // Group opacity rest track
        if node.vis.groupOpacity != nil || groupFading.contains(id) || scene.store().has(id, P_GROUP_REST) {
            setGroupRest(
                scene,
                id,
                node.vis.groupOpacity,
                node.opacityMotionAnim ?? pendingMotionCurve,
                layoutSpring,
                instant || reducedMotion,
                &groupFading
            )
        }

        // Node scale (`El.scale`, rest = 1.0)
        if readyFromRest(scene, id, P_SCALE, 1.0, node.scale) {
            if !instant && !reducedMotion {
                scene.animate(id, P_SCALE, node.scale, layoutSpring)
            } else {
                scene.set(id, P_SCALE, node.scale)
            }
        }

        // Corner radii (`NodeSpec` sets initial corners on mount without allocating a track)
        if wasPresent {
            let cornersChanged = prevNode.map { $0.vis.corners != node.vis.corners } ?? false
            if cornersChanged || scene.store().has(id, RuneMotion.prop.radius) {
                if !instant && !reducedMotion {
                    scene.animate(id, RuneMotion.prop.radius, node.vis.corners, layoutSpring)
                } else {
                    scene.set(id, RuneMotion.prop.radius, node.vis.corners)
                }
            }
        }

        // Layer blur (rest = 0.0)
        let layerBlur = node.vis.cold.getIfSome?.layerBlur ?? 0.0
        if readyFromRest(scene, id, RuneMotion.prop.blur, 0.0, layerBlur) {
            if !instant && !reducedMotion {
                scene.animate(id, RuneMotion.prop.blur, layerBlur, layoutSpring)
            } else {
                scene.set(id, RuneMotion.prop.blur, layerBlur)
            }
        }

        // Lazy paint tracks (`P_FILL`, `P_BORDER`, `P_BORDER_BOTTOM`, `P_TEXT`, `P_HOVER_C`, `P_PRESS_C`)
        commitPaintTrack(
            id,
            P_FILL,
            from: prevNode?.vis.fill,
            to: node.vis.fill,
            spring: colorSpring,
            instant: instant
        )
        if node.vis.borderWidth > 0.0 || (prevNode?.vis.borderWidth ?? 0.0) > 0.0 {
            commitPaintTrack(
                id,
                P_BORDER,
                from: prevNode?.vis.border,
                to: node.vis.border,
                spring: colorSpring,
                instant: instant
            )
        }
        if let bb = node.vis.borderBottom {
            commitPaintTrack(
                id,
                P_BORDER_BOTTOM,
                from: prevNode?.vis.borderBottom ?? prevNode?.vis.border,
                to: bb,
                spring: colorSpring,
                instant: instant
            )
        }
        if let tc = nodeTextColor(node) {
            let prevTc = prevNode.flatMap { nodeTextColor($0) }
            let textSpring = Spring.new(max(colorSpring.duration * 0.5, 0.1), colorSpring.bounce)
            commitPaintTrack(
                id,
                P_TEXT,
                from: prevTc,
                to: tc,
                spring: textSpring,
                instant: instant
            )
        }
        if node.vis.hover.a > 0.0 {
            commitPaintTrack(
                id,
                P_HOVER_C,
                from: prevNode?.vis.hover,
                to: node.vis.hover,
                spring: colorSpring,
                instant: instant
            )
        }
        if node.vis.press.a > 0.0 {
            commitPaintTrack(
                id,
                P_PRESS_C,
                from: prevNode?.vis.press,
                to: node.vis.press,
                spring: colorSpring,
                instant: instant
            )
        }

        // Icon rotation (`iconTurn`, rest = 0.0)
        let iconTurn = node.vis.cold.getIfSome?.iconTurn ?? 0.0
        if readyFromRest(scene, id, P_ICON_TURN, 0.0, iconTurn) {
            if !instant && !reducedMotion, let sp = baseSpring {
                scene.animate(id, P_ICON_TURN, iconTurn, sp)
            } else {
                scene.set(id, P_ICON_TURN, iconTurn)
            }
        }

        // Hover & press 0..1 progress tracks (rest = 0.0)
        if node.vis.hover.a > 0.0 {
            let isHovered = hoveredPaths.contains(node.path) && !node.inert
            let hoverTarget: Float = isHovered ? 1.0 : 0.0
            if readyFromRest(scene, id, P_HOVER, 0.0, hoverTarget) {
                if instant || reducedMotion || hoverTarget >= 1.0 {
                    scene.set(id, P_HOVER, hoverTarget)
                } else {
                    scene.animate(id, P_HOVER, hoverTarget, tok.motion.INSTANT)
                }
            }
        }
        if node.vis.press.a > 0.0 {
            let isPressed = (pressedPath == node.path) && !node.inert
            let pressTarget: Float = isPressed ? 1.0 : 0.0
            if readyFromRest(scene, id, P_PRESS, 0.0, pressTarget) {
                if instant || reducedMotion {
                    scene.set(id, P_PRESS, pressTarget)
                } else {
                    scene.animate(id, P_PRESS, pressTarget, tok.motion.INSTANT)
                }
            }
        }
    }

    /// Immediately settle all scene animations, scroll springs, growth tracks, and flights to their targets.
    public func settleAll() {
        if dirty {
            pendingSettleCommit = true
        }
        exitingNodes.removeAll()
        activeTextFlights.removeAll()

        for i in nodes.indices {
            let n = nodes[i]
            let id = n.nodeId
            if !scene.contains(id) { continue }
            scene.enterNow(id)
            scene.landWaiting(id)
            scene.landPath(id)
            let r = RuneMotion.Rect(n.localRect[0], n.localRect[1], n.localRect[2], n.localRect[3])
            scene.setFrame(id, r, LayoutAnim.instant)
            scene.set(id, RuneMotion.prop.opacity, n.vis.opacity)
            scene.set(id, RuneMotion.prop.radius, n.vis.corners)
            scene.set(id, RuneMotion.prop.blur, n.vis.cold.getIfSome?.layerBlur ?? 0.0)
            let rmFill = RuneMotion.Color(r: n.vis.fill.r, g: n.vis.fill.g, b: n.vis.fill.b, a: n.vis.fill.a)
            scene.set(id, RuneMotion.prop.fill, rmFill)
            scene.set(id, P_FILL, n.vis.fill)
            scene.set(id, P_BORDER, n.vis.border)
            scene.set(id, P_SCALE, n.scale)
            scene.set(id, P_HOVER, hoveredPaths.contains(n.path) ? 1.0 : 0.0)
            scene.set(id, P_PRESS, pressedPath == n.path ? 1.0 : 0.0)
            if let grp = n.vis.groupOpacity {
                scene.set(id, P_GROUP_REST, grp)
            }
            if let tc = n.textSpec?.color {
                scene.set(id, P_TEXT, tc)
            }
            if scene.store().has(id, P_ROW_SLIDE) {
                scene.set(id, P_ROW_SLIDE, 0.0)
            }
            if var loopEntry = loops[id], case .sequence = loopEntry.spec.kind {
                loopEntry.startTime = t - loopEntry.spec.delay - Double(loopEntry.spec.period) - 1.0
                loopEntry.phase = 1.0
                loopEntry.sleeping = true
                loops[id] = loopEntry
                let track = LoopTrack(loopEntry.spec, loopEntry.startTime)
                if let beat = track.pose(t, true) {
                    scene.set(id, RuneMotion.prop.opacity, beat.opacity)
                    scene.set(id, RuneMotion.prop.scale, beat.scale)
                }
            }
        }
        groupFading.removeAll()

        for k in Array(scrolls.keys) {
            if var entry = scrolls[k] {
                entry.offset = entry.target
                entry.vel = 0.0
                entry.overscroll = 0.0
                scrolls[k] = entry
            }
        }
        for k in Array(scrollsX.keys) {
            if var entry = scrollsX[k] {
                entry.offset = entry.target
                entry.vel = 0.0
                entry.overscroll = 0.0
                scrollsX[k] = entry
            }
        }
        for id in Array(growthTracks.keys) {
            if let target = growthTracks[id]?.target {
                growthTracks[id] = GrowTrack.settled(target)
            }
        }
        for path in Array(reveals.keys) {
            if var entry = reveals[path] {
                entry.progress = entry.target
                reveals[path] = entry
            }
        }

        _ = scene.frameAt(t)
        scene.present()
        refreshPresentedGeometries()
    }
}
