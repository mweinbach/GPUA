// Ported from: crates/rune/src/runtime/commit/apply.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Synchronize laid-out `[Node]` geometries, transitions, matched geometry, exiting subtrees,
//! and custom paint/scale/growth tracks into `RuneMotion.Scene`.

import RuneMotion
import Taffy

extension Runtime {
    func extractTaffyLayouts(
        _ taffy: inout TaffyTree<NodeMeasureContext>,
        diagnostics: inout [LayoutDiagnostic]
    ) {
        guard !nodes.isEmpty else { return }
        extractNodeLayoutRecursive(
            nodeIdx: 0,
            parentWorldX: 0.0,
            parentWorldY: 0.0,
            taffy: &taffy
        )

        // Build key index before anchored overlay resolution so triggers can be found by key
        keyIndex.rebuild(nodes)

        // Post-pass 2: resolve anchored overlays (`El.above`, `El.anchored`, `El.anchoredFit`, `El.anchoredUnscaled`)
        for i in nodes.indices {
            guard let anchor = nodes[i].aboveAnchor else { continue }
            guard let triggerIdx = keyIndex.findMatching(anchor.key, in: nodes) else {
                diagnostics.append(
                    LayoutDiagnostic(
                        kind: .missingAnchorTarget,
                        path: nodes[i].path,
                        message: "Anchor target '\(anchor.key)' not found for '\(nodes[i].path)'"
                    )
                )
                continue
            }
            let trigRect = nodes[triggerIdx].layoutRect
            let trigScale = nodes[triggerIdx].cumulativeScale
            // Scaled visual bounds `[x0, y0, x1, y1]` around trigger center
            let tcx = trigRect[0] + trigRect[2] * 0.5
            let tcy = trigRect[1] + trigRect[3] * 0.5
            let tsw = trigRect[2] * trigScale
            let tsh = trigRect[3] * trigScale
            let triggerBounds: [Float] = [
                tcx - tsw * 0.5,
                tcy - tsh * 0.5,
                tcx + tsw * 0.5,
                tcy + tsh * 0.5,
            ]

            let resolved = resolveAnchoredOverlay(
                anchor,
                triggerBounds: triggerBounds,
                triggerScale: trigScale,
                measuredSize: (nodes[i].localRect[2], nodes[i].localRect[3]),
                viewport: viewport
            )
            nodes[i].resolvedAnchorSide = resolved.side
            nodes[i].scale = resolved.scale / max(nodes[i].parent.map { nodes[$0].cumulativeScale } ?? 1.0, 0.001)
            nodes[i].cumulativeScale = resolved.scale

            // If `anchor.fit` shrunk the overlay, re-run Taffy layout on the overlay subtree at `(resolved.w, resolved.h)`
            let sizeChanged = abs(resolved.w - nodes[i].localRect[2]) > 0.5 || abs(resolved.h - nodes[i].localRect[3]) > 0.5
            if anchor.fit && sizeChanged, let tid = nodes[i].taffyId {
                var fixedStyle = nodes[i].style
                fixedStyle.size = Size(width: .length(resolved.w), height: .length(resolved.h))
                _ = taffy.setStyle(tid, fixedStyle)
                _ = taffy.computeLayoutWithMeasure(
                    tid,
                    Size(width: .definite(resolved.w), height: .definite(resolved.h)),
                    makeTaffyMeasureClosure()
                )
                let px = nodes[i].parent.map { nodes[$0].layoutRect[0] } ?? 0.0
                let py = nodes[i].parent.map { nodes[$0].layoutRect[1] } ?? 0.0
                extractNodeLayoutRecursive(nodeIdx: i, parentWorldX: px, parentWorldY: py, taffy: &taffy)
                nodes[i].localRect = [resolved.x - px, resolved.y - py, resolved.w, resolved.h]
                repositionSubtree(nodeIdx: i, newWorldX: resolved.x, newWorldY: resolved.y)
            } else {
                let px = nodes[i].parent.map { nodes[$0].layoutRect[0] } ?? 0.0
                let py = nodes[i].parent.map { nodes[$0].layoutRect[1] } ?? 0.0
                nodes[i].localRect = [resolved.x - px, resolved.y - py, resolved.w, resolved.h]
                nodes[i].layoutRect[2] = resolved.w
                nodes[i].layoutRect[3] = resolved.h
                repositionSubtree(nodeIdx: i, newWorldX: resolved.x, newWorldY: resolved.y)
            }
        }
    }

    private func extractNodeLayoutRecursive(
        nodeIdx: Int,
        parentWorldX: Float,
        parentWorldY: Float,
        taffy: inout TaffyTree<NodeMeasureContext>
    ) {
        guard let tid = nodes[nodeIdx].taffyId,
              case .success(let layout) = taffy.layout(tid)
        else { return }

        let lx = layout.location.x
        let ly = layout.location.y
        let lw = layout.size.width
        let lh = layout.size.height
        let wx = parentWorldX + lx
        let wy = parentWorldY + ly

        nodes[nodeIdx].localRect = [lx, ly, lw, lh]
        nodes[nodeIdx].layoutRect = [wx, wy, lw, lh]
        nodes[nodeIdx].presentedRect = [wx, wy, lw, lh]
        nodes[nodeIdx].visibleRect = [wx, wy, lw, lh]

        // Re-wrap / align text at the final resolved inner width if needed
        if let spec = nodes[nodeIdx].textSpec {
            let padX = layout.padding.left + layout.padding.right + layout.border.left + layout.border.right
            let innerW = max(lw - padX, 0.0)
            if (spec.wrap || spec.truncate || spec.maxLines > 0) && innerW > 0.0 {
                let key = makeTextLayoutCacheKey(spec, maxWidth: innerW)
                if let cached = textLayoutCache[key] {
                    nodes[nodeIdx].textLayout = cached
                } else if nodes[nodeIdx].textLayout == nil || abs((nodes[nodeIdx].textLayout?.width ?? 0.0) - innerW) > 0.5 {
                    let prevText = previousShapedByPath[nodes[nodeIdx].path]
                    let relaid = layoutTextSpec(spec, maxWidth: innerW, textSys: text, previouslyShapedText: prevText)
                    previousShapedByPath[nodes[nodeIdx].path] = spec.content
                    textLayoutCache[key] = relaid
                    nodes[nodeIdx].textLayout = relaid
                }
            } else if nodes[nodeIdx].textLayout == nil {
                let key = makeTextLayoutCacheKey(spec, maxWidth: nil)
                let built = textLayoutCache[key] ?? layoutTextSpec(spec, maxWidth: nil, textSys: text, previouslyShapedText: previousShapedByPath[nodes[nodeIdx].path])
                previousShapedByPath[nodes[nodeIdx].path] = spec.content
                textLayoutCache[key] = built
                nodes[nodeIdx].textLayout = built
            }
            if nodes[nodeIdx].textLayout != nil {
                alignTextLayout(&nodes[nodeIdx].textLayout!, containerWidth: innerW, align: spec.align)
            }
        }

        for childIdx in nodes[nodeIdx].children {
            extractNodeLayoutRecursive(nodeIdx: childIdx, parentWorldX: wx, parentWorldY: wy, taffy: &taffy)
        }
    }

    private func repositionSubtree(nodeIdx: Int, newWorldX: Float, newWorldY: Float) {
        let dx = newWorldX - nodes[nodeIdx].layoutRect[0]
        let dy = newWorldY - nodes[nodeIdx].layoutRect[1]
        guard abs(dx) > 1e-5 || abs(dy) > 1e-5 else { return }
        shiftSubtreeWorld(nodeIdx: nodeIdx, dx: dx, dy: dy)
    }

    private func shiftSubtreeWorld(nodeIdx: Int, dx: Float, dy: Float) {
        nodes[nodeIdx].layoutRect[0] += dx
        nodes[nodeIdx].layoutRect[1] += dy
        nodes[nodeIdx].presentedRect[0] += dx
        nodes[nodeIdx].presentedRect[1] += dy
        for c in nodes[nodeIdx].children {
            shiftSubtreeWorld(nodeIdx: c, dx: dx, dy: dy)
        }
    }

    func applyNodesToScene(previousNodes: [Node]) {
        applyScratch.resetForCommit(previousNodes: previousNodes)
        scene.setTime(t)
        scene.setPixelScale(max(env.scale, 0.001))
        if scene.store().reducedMotion() != reducedMotion {
            scene.setReducedMotion(reducedMotion)
        }

        let isFirstCommit = !hasCommittedOnce
        let userRelayout = (commitWhy & CommitWhy.RELAYOUT) != 0 && !viewportStepped
        let forceInstant = isFirstCommit || pendingInstantCommit || pendingSettleCommit
        let keepFlightsActive = ((pendingInstantCommit || viewportStepped) && !pendingSettleCommit && !isFirstCommit && !userRelayout)
        scene.keepFlights(keepFlightsActive)
        defer {
            scene.keepFlights(false)
            viewportStepped = false
        }

        matched.removeAll(keepingCapacity: true)
        for idx in nodes.indices {
            if let mid = nodes[idx].matchedId {
                if applyScratch.currentMatched[mid] != nil {
                    keyWarnings?.append("duplicate matched id \"\(mid)\"")
                    matched.removeAll { $0.0 == mid }
                }
                applyScratch.currentMatched[mid] = idx
                matched.append((mid, nodes[idx].nodeId))
            }
        }

        var lastBuild = LastBuild()

        for i in nodes.indices {
            let node = nodes[i]
            let id = node.nodeId
            let prevNode = lastBuild.find(previousNodes, id).map { previousNodes[$0] }
            applyScratch.mountedIds.insert(id)

            let frameRect = RuneMotion.Rect(
                node.localRect[0],
                node.localRect[1],
                node.localRect[2],
                node.localRect[3]
            )
            let parentId = node.parent.map { nodes[$0].nodeId }
            let rmFill = RuneMotion.Color(r: node.vis.fill.r, g: node.vis.fill.g, b: node.vis.fill.b, a: node.vis.fill.a)

            var spec = NodeSpec(frameRect)
                .opacity(node.vis.opacity)
                .radius(node.vis.corners)
                .fill(rmFill)
                .transition(node.transitionSpec ?? .opacity())
            if let pid = parentId {
                spec = spec.parent(pid)
            }

            let wasPresent = scene.contains(id)
            let inGrowthStack = node.parent.map { nodes[$0].growthSpec != nil } ?? false
            let parentInstant = node.parent.map { nodes[$0].instantChanges } ?? false
            let suppressUnseen = isOffscreenUnseenEntrance(nodeIdx: i)
            if !wasPresent {
                let ridesRow = inGrowthStack || (node.inGrowingRow && !node.animateLayout)
                let quietRow = ridesRow
                    && (node.transitionSpec == nil || node.transitionSpec?.insertion == .identity)
                    && !reducedMotion
                let mountMode: Mount = (forceInstant || node.instantChanges || parentInstant || suppressUnseen || quietRow)
                    ? .initial
                    : .animated
                scene.insert(id, spec, mountMode)
            } else {
                let wasExiting = isNodeExiting(id)
                if wasExiting {
                    exitingNodes.removeAll { $0.nodeId == id }
                    let reviveMode: Mount = (forceInstant || node.instantChanges || parentInstant || suppressUnseen)
                        ? .initial
                        : .animated
                    scene.insert(id, spec, reviveMode)
                } else {
                    scene.setTransition(id, node.transitionSpec ?? .opacity())
                }
                let rawAnim = resolveNodeLayoutAnim(node)
                let stackRow = inGrowthStack || node.growthSpec != nil || node.virtualExtent
                let snapsInGrowthRow = node.inGrowingRow && !inGrowthStack && !node.animateLayout
                let layoutAnim: LayoutAnim
                if forceInstant || node.instantChanges || parentInstant || suppressUnseen || (commitWhy & CommitWhy.RELAYOUT) != 0 || snapsInGrowthRow {
                    layoutAnim = .instant
                } else if stackRow {
                    layoutAnim = LayoutAnim.axes(rawAnim.x, Anim.instant)
                } else {
                    layoutAnim = rawAnim
                }
                let keepTravel = scene.store().isAnimating(id, RuneMotion.prop.travel)
                    && !pendingSettleCommit
                    && !userRelayout
                    && prevNode?.localRect == node.localRect
                if !keepTravel {
                    scene.setFrame(id, frameRect, layoutAnim)
                }
            }

            if abs(scene.store().nodeTimeScale(id) - node.cumulativeTimeScale) > 1e-6 {
                scene.setTimeScale(id, node.cumulativeTimeScale)
            }
            scene.traceName(id, node.traceName)
            scene.traceNamespace(id, node.traceNamespace)

            // Matched geometry transfer when the winning `matchedId` moves from a different `NodeId`
            if !wasPresent,
               let mid = node.matchedId,
               applyScratch.currentMatched[mid] == i,
               let (oldId, _) = applyScratch.previousMatched[mid],
               oldId != id
            {
                let anim = resolveNodeLayoutAnim(node)
                if anim != .instant {
                    scene.matchGeometry(oldId, id, anim)
                }
            }

            // Launch flights queued via `tx.launch(src, dst)`
            if let srcRect = pendingLaunchRects[node.key ?? ""] ?? pendingLaunchRects[node.path] {
                let anim = resolveNodeLayoutAnim(node)
                if anim != .instant {
                    scene.launch(id, srcRect, anim)
                }
            }

            // Sync opacity / scale / paint / hover / press / groupRest tracks
            syncNodeMotionTracks(nodeIdx: i, prevNode: prevNode, wasPresent: wasPresent, forceInstant: forceInstant || suppressUnseen)

            // Sync loop clock registration
            syncNodeLoop(nodeIdx: i)

            // Sync live bindings
            attachNodeLiveBindings(nodeIdx: i)

            // Sync growth / fold-glide tracks
            syncNodeGrowthTrack(nodeIdx: i, prevNode: prevNode, isFirstCommit: isFirstCommit, forceInstant: forceInstant || reducedMotion)
        }
        pendingLaunchRects.removeAll(keepingCapacity: true)

        // Start vertical reorder slides (`P_ROW_SLIDE`) for rows inside `GrowthSpec` stacks
        if !isFirstCommit {
            syncGrowthStackRowSlides(previousNodes: previousNodes, forceInstant: forceInstant || reducedMotion)
        }

        // Handle nodes from `previousNodes` that were removed in this commit
        var newIdxById: [RuneMotion.NodeId: Int] = [:]
        newIdxById.reserveCapacity(nodes.count)
        for i in nodes.indices {
            newIdxById[nodes[i].nodeId] = i
        }
        func mountedAncestorDrawsNothing(_ startNewIdx: Int?) -> Bool {
            var cur = startNewIdx
            while let idx = cur {
                let n = nodes[idx]
                if n.vis.opacity <= 0.0 && !scene.store().isAnimating(n.nodeId, RuneMotion.prop.opacity) {
                    return true
                }
                cur = n.parent
            }
            return false
        }

        // Sync mounted ancestor `cumulativeTimeScale` & visibility onto already-exiting nodes
        if !exitingNodes.isEmpty {
            var exitingParentById: [RuneMotion.NodeId: RuneMotion.NodeId?] = [:]
            for ex in exitingNodes {
                exitingParentById[ex.nodeId] = ex.parentNodeId
            }
            func nearestMountedAncestorIdx(for ex: ExitingNode) -> Int? {
                var pid = ex.parentNodeId
                while let p = pid {
                    if let mIdx = newIdxById[p] { return mIdx }
                    pid = exitingParentById[p] ?? nil
                }
                return nil
            }
            exitingNodes.removeAll { ex in
                guard scene.contains(ex.nodeId) else { return true }
                let mIdx = nearestMountedAncestorIdx(for: ex)
                if mountedAncestorDrawsNothing(mIdx) {
                    scene.setTimeScale(ex.nodeId, 1.0)
                    scene.unmount(ex.nodeId)
                    return true
                }
                let inheritedTs = mIdx.map { nodes[$0].cumulativeTimeScale } ?? 1.0
                if abs(scene.store().nodeTimeScale(ex.nodeId) - inheritedTs) > 1e-6 {
                    scene.setTimeScale(ex.nodeId, inheritedTs)
                }
                return false
            }
        }

        for prev in previousNodes where !applyScratch.mountedIds.contains(prev.nodeId) {
            growthTracks.removeValue(forKey: prev.nodeId)
            guard scene.contains(prev.nodeId) else { continue }
            let oldParentId = prev.parent.map { previousNodes[$0].nodeId }
            let parentNewIdx = oldParentId.flatMap { newIdxById[$0] }
            let parentRemainedPresent = oldParentId == nil || parentNewIdx != nil
            if parentRemainedPresent {
                let parentInstant = parentNewIdx.map { nodes[$0].instantChanges } ?? false
                var ancestorHidden = prev.vis.opacity <= 0.0 || mountedAncestorDrawsNothing(parentNewIdx)
                var ancCur = prev.parent
                while let pIdx = ancCur, !ancestorHidden {
                    if previousNodes[pIdx].vis.opacity <= 0.0 {
                        ancestorHidden = true
                    }
                    ancCur = previousNodes[pIdx].parent
                }
                let prevUnseen = prev.visibleRect[2] <= 0.01 || prev.visibleRect[3] <= 0.01 || ancestorHidden
                let nodeInstant = forceInstant || prev.instantChanges || parentInstant || prevUnseen
                if pendingSettleCommit || (nodeInstant && !isNodeExiting(prev.nodeId)) || ancestorHidden {
                    scene.setTimeScale(prev.nodeId, 1.0)
                    scene.unmount(prev.nodeId)
                } else {
                    let inheritedTs = parentNewIdx.map { nodes[$0].cumulativeTimeScale } ?? 1.0
                    scene.setTimeScale(prev.nodeId, inheritedTs)
                    scene.remove(prev.nodeId)
                }
            }
            if scene.contains(prev.nodeId) {
                let wasSecure = isNodeSecure(prev)
                var exitSpec = prev.textSpec
                var exitLayout = prev.textLayout
                if wasSecure, var ts = exitSpec {
                    let masked = String(repeating: "•", count: ts.content.count)
                    ts.content = masked
                    ts.secureRevealed = false
                    exitSpec = ts
                    let innerW = max(prev.localRect[2], 0.0)
                    var tl = layoutTextSpec(ts, maxWidth: innerW > 0.0 ? innerW : nil, textSys: text)
                    alignTextLayout(&tl, containerWidth: innerW, align: ts.align)
                    exitLayout = tl
                }
                let ownScale = scene.get(prev.nodeId, P_SCALE) ?? prev.scale
                exitingNodes.append(
                    ExitingNode(
                        nodeId: prev.nodeId,
                        path: prev.path,
                        key: prev.key,
                        parentPath: prev.parent.map { previousNodes[$0].path },
                        parentNodeId: oldParentId,
                        role: prev.role,
                        label: wasSecure ? nil : prev.label,
                        vis: prev.vis,
                        textSpec: exitSpec,
                        textLayout: exitLayout,
                        scale: ownScale,
                        localRect: prev.localRect,
                        worldRect: prev.presentedRect,
                        clipRect: prev.clipBounds,
                        clipRadii: prev.clipRadii,
                        children: []
                    )
                )
            }
        }

        // Evict stale layouts for incrementally edited strings no longer shown by any mounted or exiting node
        var editedOldTexts: Set<String> = []
        for prev in previousNodes {
            guard let oldContent = prev.textSpec?.content,
                  let curIdx = newIdxById[prev.nodeId],
                  let newContent = nodes[curIdx].textSpec?.content,
                  edited(oldContent, newContent)
            else { continue }
            editedOldTexts.insert(oldContent)
        }
        if !editedOldTexts.isEmpty {
            for n in nodes {
                if let c = n.textSpec?.content { editedOldTexts.remove(c) }
            }
            for ex in exitingNodes {
                if let c = ex.textSpec?.content { editedOldTexts.remove(c) }
            }
            if !editedOldTexts.isEmpty {
                for key in Array(textLayoutCache.keys) where editedOldTexts.contains(key.content) {
                    textLayoutCache.removeValue(forKey: key)
                }
            }
        }

        // Update scroll containers' viewport & content extents
        syncScrollContainersAfterLayout(diagnostics: &lastLayoutDiagnostics)
    }

    func syncGrowthStackRowSlides(previousNodes: [Node], forceInstant: Bool) {
        var prevById: [RuneMotion.NodeId: Node] = [:]
        prevById.reserveCapacity(previousNodes.count)
        for pn in previousNodes {
            prevById[pn.nodeId] = pn
        }

        for stackIdx in nodes.indices where nodes[stackIdx].growthSpec != nil {
            let stackNode = nodes[stackIdx]
            guard let prevStack = prevById[stackNode.nodeId] else { continue }
            let prevStackScale = max(prevStack.cumulativeScale, 0.001)
            let sKey = stackNode.key ?? stackNode.path
            let prevStackScrollY: Float = prevStack.scrollSpec != nil ? (scrolls[sKey]?.offset ?? 0.0) : 0.0

            var cumulativeGrowthDelta: Float = 0.0
            for childIdx in stackNode.children {
                let child = nodes[childIdx]
                let cid = child.nodeId
                let newBaseLocalY = child.localRect[1] + cumulativeGrowthDelta

                if let gt = growthTracks[cid], gt.moving() {
                    cumulativeGrowthDelta += max(0.0, gt.h) - child.layoutRect[3]
                }

                let rowAnim = resolveNodeLayoutAnim(child)
                if forceInstant || child.instantChanges || rowAnim == .instant {
                    if scene.store().has(cid, P_ROW_SLIDE) {
                        scene.set(cid, P_ROW_SLIDE, 0.0)
                    }
                    continue
                }

                guard let prevChild = prevById[cid], prevChild.parent != nil else { continue }
                let oldDrawnLocalY = (prevChild.presentedRect[1] - prevStack.presentedRect[1]) / prevStackScale + prevStackScrollY
                let curSlide: Float = scene.store().isAnimating(cid, P_ROW_SLIDE)
                    ? (scene.get(cid, P_ROW_SLIDE) ?? 0.0)
                    : 0.0
                let slotJump = (oldDrawnLocalY - curSlide) - newBaseLocalY
                if abs(slotJump) > (1.0 / 64.0) {
                    let nextSlide = curSlide + slotJump
                    if abs(nextSlide) > (1.0 / 64.0) {
                        scene.set(cid, P_ROW_SLIDE, nextSlide)
                        scene.animate(cid, P_ROW_SLIDE, 0.0, rowAnim.y)
                    } else if scene.store().has(cid, P_ROW_SLIDE) {
                        scene.set(cid, P_ROW_SLIDE, 0.0)
                    }
                }
            }
        }
    }

    func resolveNodeLayoutAnim(_ node: Node) -> LayoutAnim {
        if pendingInstantCommit || node.instantChanges || !hasCommittedOnce || (commitWhy & CommitWhy.RELAYOUT) != 0 {
            return .instant
        }
        if let txCurve = pendingMotionCurve {
            return LayoutAnim(txCurve)
        }
        if let txSpring = pendingMotionSpring {
            return LayoutAnim(txSpring)
        }
        if let nodeSpring = node.motionSpring {
            return LayoutAnim(nodeSpring)
        }
        return LayoutAnim(tok.motion.REFLOW)
    }
}
