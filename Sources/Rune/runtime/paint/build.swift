// Ported from: crates/rune/src/runtime/paint/build.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Frame paint pass: `Scene` presented poses, scroll/growth/sticky offsets, clips, layers,
//! pixel snapping, shadows, fills, borders, text, exiting nodes, and flights -> GPU `[Instance]`.

import RuneMotion

extension Runtime {
    /// Update every node's `presentedRect`, `visibleRect`, `clipBounds`, `clipRadii`, `scrollOffsetApplied`,
    /// `inGrowingRow`, `groupOpacityAccum`, and `stuckAmount` from the current `Scene`, scroll, and growth states.
    func refreshPresentedGeometries() {
        guard !nodes.isEmpty else { return }

        // Track vertical growth lift propagated to following siblings inside the same parent
        var siblingGrowthDeltaByParent: [Int: Float] = [:]
        var groupHoverByNode = [Float](repeating: 0.0, count: nodes.count)

        for i in nodes.indices {
            let n = nodes[i]
            let id = n.nodeId
            let parentIdx = n.parent

            let parentWorldX: Float
            let parentWorldY: Float
            let parentScale: Float
            var inheritedClip: [Float]
            var inheritedClipRadii: Corners
            var scrollAnc: Int?
            var scrollApplied: [Float]
            var inGrow: Bool
            var groupAccum: Float

            if let p = parentIdx {
                let pn = nodes[p]
                parentWorldX = pn.presentedRect[0]
                parentWorldY = pn.presentedRect[1]
                parentScale = pn.cumulativeScale
                inheritedClip = pn.clipBounds
                inheritedClipRadii = pn.clipRadii
                scrollAnc = pn.scrollSpec != nil ? p : pn.scrollAncestor
                scrollApplied = pn.scrollOffsetApplied
                inGrow = pn.inGrowingRow || (growthTracks[pn.nodeId]?.moving() == true)
                groupAccum = pn.groupOpacityAccum

                if pn.scrollSpec != nil {
                    let sKey = pn.key ?? pn.path
                    let sy = scrolls[sKey]?.offset ?? 0.0
                    let sx = scrollsX[sKey]?.offset ?? 0.0
                    let (sinA, cosA) = RuneMotion.math.sinCos(pn.turn.angle)
                    let dx = (sx * cosA - sy * sinA) * parentScale
                    let dy = (sx * sinA + sy * cosA) * parentScale
                    scrollApplied = [scrollApplied[0] + dx, scrollApplied[1] + dy]
                    let pr = pn.presentedRect
                    inheritedClip = intersectClips(inheritedClip, [pr[0], pr[1], pr[0] + pr[2], pr[1] + pr[3]])
                } else if pn.vis.clip {
                    let pr = pn.presentedRect
                    inheritedClip = intersectClips(inheritedClip, [pr[0], pr[1], pr[0] + pr[2], pr[1] + pr[3]])
                    if pn.vis.corners != .zero {
                        inheritedClipRadii = pn.vis.corners
                    }
                }
            } else {
                parentWorldX = 0.0
                parentWorldY = 0.0
                parentScale = 1.0
                inheritedClip = [0.0, 0.0, viewport.0, viewport.1]
                inheritedClipRadii = .zero
                scrollAnc = nil
                scrollApplied = [0.0, 0.0]
                inGrow = false
                groupAccum = 1.0
            }

            let pres = scene.presented(id)
            let ownScale = (scene.get(id, P_SCALE) ?? n.scale) * (pres?.transform.scale.x ?? 1.0)
            let effScale = parentScale * ownScale
            nodes[i].cumulativeScale = effScale

            let parentSceneOrigin: (Float, Float) = parentIdx
                .flatMap { scene.presented(nodes[$0].nodeId) }
                .map { ($0.rect.x, $0.rect.y) } ?? (0.0, 0.0)
            var lx = pres.map { $0.rect.x - parentSceneOrigin.0 } ?? n.localRect[0]
            var ly = pres.map { $0.rect.y - parentSceneOrigin.1 } ?? n.localRect[1]
            let lw = pres?.rect.w ?? n.localRect[2]
            var lh = pres?.rect.h ?? n.localRect[3]

            // Apply scroll offset from immediate scroll parent
            if let p = parentIdx, nodes[p].scrollSpec != nil {
                let sKey = nodes[p].key ?? nodes[p].path
                lx -= scrollsX[sKey]?.offset ?? 0.0
                ly -= scrolls[sKey]?.offset ?? 0.0
            }

            // Apply sibling growth row delta from earlier siblings in the same parent
            if let p = parentIdx, let dyGrow = siblingGrowthDeltaByParent[p] {
                ly += dyGrow
            }

            // Apply vertical row reorder slide (`P_ROW_SLIDE`) inside `GrowthSpec` stacks
            if scene.store().isAnimating(id, P_ROW_SLIDE), let slideY = scene.get(id, P_ROW_SLIDE) {
                ly += slideY
            }

            // Apply this node's own `GrowTrack` height override and accumulate delta for later siblings
            if let gt = growthTracks[id] {
                let targetH = n.layoutRect[3]
                if gt.moving() {
                    let curH = max(0.0, gt.h)
                    let delta = curH - targetH
                    lh = curH
                    inGrow = true
                    if let p = parentIdx {
                        siblingGrowthDeltaByParent[p, default: 0.0] += delta
                    }
                }
            }

            let bx = parentWorldX + lx * parentScale
            let by = parentWorldY + ly * parentScale
            let bw = lw * parentScale
            let bh = lh * parentScale

            // Scale around node center when `ownScale != 1`, compounded with ancestor scale
            let sw = lw * effScale
            let sh = lh * effScale
            var wx = bx
            var wy = by
            if abs(ownScale - 1.0) > 1e-5 {
                wx += (bw - sw) * 0.5
                wy += (bh - sh) * 0.5
            }

            // Sticky top offset inside vertical scroll viewport
            var stuckShift: Float = 0.0
            if let stickyInset = n.stickyTop, let sAnc = scrollAnc {
                let vpTop = nodes[sAnc].presentedRect[1] + stickyInset
                if wy < vpTop {
                    let parentMaxBottom: Float = parentIdx.map { p in
                        let pr = nodes[p].presentedRect
                        return pr[1] + pr[3]
                    } ?? .infinity
                    let clampedY = min(vpTop, max(wy, parentMaxBottom - sh))
                    stuckShift = clampedY - wy
                    wy = clampedY
                }
            }

            // Group hover factor accumulation (inherited down from `hoverGroup` / `.hover(...)` ancestors)
            let parentGroupHover = parentIdx.map { groupHoverByNode[$0] } ?? 0.0
            let nodeGroupHover: Float
            if n.vis.hover.a > 0.0 {
                let curHover = scene.store().has(id, P_HOVER)
                    ? (scene.get(id, P_HOVER) ?? 0.0)
                    : (hoveredPaths.contains(n.path) ? 1.0 : 0.0)
                nodeGroupHover = min(max(curHover, 0.0), 1.0)
            } else {
                nodeGroupHover = parentGroupHover
            }
            groupHoverByNode[i] = nodeGroupHover
            let ownGroupFactor: Float = {
                if let rest = n.vis.groupOpacity {
                    let curRest = groupFactor(scene, id, rest)
                    return min(max(curRest + (1.0 - curRest) * nodeGroupHover, 0.0), 1.0)
                } else if groupFading.contains(id) {
                    let curRest = groupFactor(scene, id, 1.0)
                    return min(max(curRest + (1.0 - curRest) * nodeGroupHover, 0.0), 1.0)
                } else {
                    return 1.0
                }
            }()
            groupAccum *= ownGroupFactor

            let presRect: [Float] = [wx, wy, sw, sh]
            let vx0 = max(wx, inheritedClip[0])
            let vy0 = max(wy, inheritedClip[1])
            let vx1 = min(wx + sw, inheritedClip[2])
            let vy1 = min(wy + sh, inheritedClip[3])
            let visRect: [Float] = [vx0, vy0, max(0.0, vx1 - vx0), max(0.0, vy1 - vy0)]

            let parentTurn = parentIdx.map { nodes[$0].turn } ?? .none
            let ownTurn = parentTurn.combined(n.rotate, [wx + sw * 0.5, wy + sh * 0.5])

            nodes[i].presentedRect = presRect
            nodes[i].visibleRect = visRect
            nodes[i].clipBounds = inheritedClip
            nodes[i].clipRadii = inheritedClipRadii
            nodes[i].scrollAncestor = scrollAnc
            nodes[i].scrollOffsetApplied = scrollApplied
            nodes[i].inGrowingRow = inGrow
            nodes[i].groupOpacityAccum = groupAccum
            nodes[i].stuckAmount = stuckShift
            nodes[i].turn = ownTurn
        }

        // Adjust growth stack containers' presented & visible heights by their children's live growth delta
        for (stackIdx, dyGrow) in siblingGrowthDeltaByParent where abs(dyGrow) > 1e-4 {
            let effScale = nodes[stackIdx].cumulativeScale
            nodes[stackIdx].presentedRect[3] = max(0.0, nodes[stackIdx].presentedRect[3] + dyGrow * effScale)
            let wx = nodes[stackIdx].presentedRect[0]
            let wy = nodes[stackIdx].presentedRect[1]
            let sw = nodes[stackIdx].presentedRect[2]
            let sh = nodes[stackIdx].presentedRect[3]
            let clip = nodes[stackIdx].clipBounds
            let vx0 = max(wx, clip[0])
            let vy0 = max(wy, clip[1])
            let vx1 = min(wx + sw, clip[2])
            let vy1 = min(wy + sh, clip[3])
            nodes[stackIdx].visibleRect = [vx0, vy0, max(0.0, vx1 - vx0), max(0.0, vy1 - vy0)]
        }

        // Refresh `lastLayoutSnapshot` window/caret rects when focused input moved
        if let caretEntry = computeFocusedCaretEntry() {
            lastLayoutSnapshot.caret = caretEntry
        } else {
            lastLayoutSnapshot.caret = nil
        }
    }

    /// Build the GPU `[Instance]` painter stream and `[LayerSpec]` metadata for the current frame.
    func buildFramePaint() -> ([Instance], [LayerSpec], Int) {
        let s = max(env.scale, 0.001)
        let srgb = srgbBlend
        let vpPx: [Float] = [0.0, 0.0, viewport.0 * s, viewport.1 * s]

        var out: [Instance] = []
        out.reserveCapacity(max(instances.count, nodes.count * 2))
        var layerSpecs: [LayerSpec] = []
        surfaces.removeAll(keepingCapacity: true)
        marks.removeAll(keepingCapacity: true)
        imeArea = nil

        beginExitMask()
        pixelSnap.beginFrame(t, [vpPx[2], vpPx[3]])

        // Map selected byte ranges by node path once per frame
        var selectedByPath: [String: Range<Int>] = [:]
        if let sel = currentTextSelection() {
            for item in sel.items {
                selectedByPath[item.path] = item.range
            }
        }

        var glyphCount = 0
        var backdropBlurCount = 0
        // Stack of open layers: `(ancestorNodeIdx, beginInstanceIdx)`
        var openLayers: [(Int, Int)] = []
        var unisolatedOpacity = [Float](repeating: 1.0, count: nodes.count)

        func closeTopLayer() {
            guard let (_, startIdx) = openLayers.popLast() else { return }
            out.append(Instance.endLayer())
            _ = startIdx
        }

        // Paint normal nodes first, then overlay/anchored subtrees on top so popovers/tooltips cover siblings
        var normalOrder: [Int] = []
        var overlayRoots: [Int] = []
        for i in nodes.indices {
            if nodes[i].aboveAnchor != nil {
                overlayRoots.append(i)
            }
        }
        let overlaySet = Set(overlayRoots)
        func appendSubtree(_ idx: Int, into list: inout [Int], skippingOverlays: Bool) {
            if skippingOverlays && overlaySet.contains(idx) {
                return
            }
            list.append(idx)
            for c in nodes[idx].children {
                appendSubtree(c, into: &list, skippingOverlays: skippingOverlays)
            }
        }
        if !nodes.isEmpty {
            appendSubtree(0, into: &normalOrder, skippingOverlays: true)
            for ov in overlayRoots {
                appendSubtree(ov, into: &normalOrder, skippingOverlays: false)
            }
        }

        for i in normalOrder {
            let n = nodes[i]
            let nodeId = n.nodeId

            // Close any open layers whose subtree we have exited
            while let (ancIdx, _) = openLayers.last {
                var cur = n.parent
                var isDescendant = false
                while let p = cur {
                    if p == ancIdx {
                        isDescendant = true
                        break
                    }
                    cur = nodes[p].parent
                }
                if isDescendant { break }
                closeTopLayer()
            }

            let pres = scene.presented(nodeId)
            let inheritedOpacity = n.parent.map { unisolatedOpacity[$0] } ?? 1.0
            let ownOpacity = (pres?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
            let effectiveOpacity = min(max(inheritedOpacity * ownOpacity, 0.0), 1.0)

            let sc = max(n.cumulativeScale, 0.001)
            let kPx = sc * s
            let pr = n.presentedRect
            let rExact: [Float] = [
                RuneMotion.snap.grid(pr[0], s) * s,
                RuneMotion.snap.grid(pr[1], s) * s,
                RuneMotion.snap.grid(pr[0] + pr[2], s) * s,
                RuneMotion.snap.grid(pr[1] + pr[3], s) * s,
            ]
            let isAnimatingPose = (scene.rest(nodeId) != nil)
                || scene.store().isAnimating(nodeId, P_ROW_SLIDE)
                || (growthTracks[nodeId]?.moving() == true)
            let snappedPt = pixelSnapRect(pr, scale: s, moving: isAnimatingPose)
            let r: [Float] = [
                snappedPt[0] * s,
                snappedPt[1] * s,
                (snappedPt[0] + snappedPt[2]) * s,
                (snappedPt[1] + snappedPt[3]) * s,
            ]
            let w = max(r[2] - r[0], 0.0)
            let h = max(r[3] - r[1], 0.0)

            var clip: [Float] = n.clipBounds.map { $0 * s }
            var fade: [Float] = [0.0, 0.0, 0.0, 0.0]
            var fadeOrigin: [Float] = clip
            if let mask = pres?.mask, !mask.isNone() {
                applyPresentedMask(mask, rectEdges: r, scalePx: kPx, clip: &clip, fade: &fade, fadeOrigin: &fadeOrigin)
            }
            // Apply growth row bottom feather when streaming/folding
            if let gt = growthTracks[nodeId], gt.moving() {
                let featherPt = gt.mask
                clip[3] = min(clip[3], r[3])
                if featherPt > 0.0 {
                    inheritFade(&fade, &fadeOrigin, r, [0.0, 0.0, 0.0, featherPt * s])
                }
            }

            let cold = n.vis.cold.getIfSome
            let layerBlurPt = pres?.blur ?? (cold?.layerBlur ?? 0.0)
            let filterMargin = layerBlurPt * sc * s * 3.0 + 2.0
            let visible = r[2] >= max(clip[0], vpPx[0]) - filterMargin
                && r[0] <= min(clip[2], vpPx[2]) + filterMargin
                && r[3] >= max(clip[1], vpPx[1]) - filterMargin
                && r[1] <= min(clip[3], vpPx[3]) + filterMargin

            let rawRadii = (pres?.radius ?? n.vis.corners).values
            let radii = rawRadii.map { $0 * kPx }

            // Backdrop blur goes ahead of any layer this element opens
            var blurHole: Float? = nil
            if let bdBlur = cold?.backdropBlur, bdBlur > 0.0,
               visible, backdropBlurCount < MAX_BACKDROP_BLURS, effectiveOpacity > 0.001
            {
                blurHole = pushBackdropBlur(
                    &out,
                    sigma: bdBlur,
                    rect: [r[0], r[1], w, h],
                    radii: radii,
                    continuous: false,
                    clip: clip,
                    fade: fade,
                    fadeOrigin: fadeOrigin,
                    rounded: nil,
                    kPx: kPx,
                    opacity: effectiveOpacity
                )
                backdropBlurCount += 1
            }

            // Open group layer when node has blur, group opacity with children, or overlapping shape
            let hasChildren = !n.children.isEmpty
            let overlapsShape = cold?.shape?.overlaps() ?? false
            let isolate = effectiveOpacity > 0.001 && (
                layerBlurPt > 0.0
                || (effectiveOpacity < 0.999 && (hasChildren || overlapsShape))
            )
            unisolatedOpacity[i] = isolate ? 1.0 : effectiveOpacity

            var paintOpacity = effectiveOpacity
            if isolate {
                let spec = LayerSpec(
                    opacity: effectiveOpacity,
                    blend: .sourceOver,
                    blur: layerBlurPt * kPx,
                    clipRadius: n.vis.clip ? clampCornerRadius(radii, w, h) : 0.0
                )
                layerSpecs.append(spec)
                var marker = Instance.beginLayer([r[0], r[1], w, h], clip, spec)
                marker.fade = packFade(fade, fadeOrigin, clip)
                openLayers.append((i, out.count))
                out.append(marker)
                clip = NO_CLIP
                fade = [0.0, 0.0, 0.0, 0.0]
                fadeOrigin = NO_CLIP
                paintOpacity = 1.0
            }

            // Focused text input / IME cursor area tracking
            var inputCaretPx: [Float]? = nil
            if let inp = n.input, inp.edit.focused, focusedPath == n.path {
                let (dispText, _) = inp.edit.display()
                let dispByte = caretIndex(inp.edit, dispText)
                let localC = n.textLayout.map { caretRectInTextLayout($0, byteOffset: dispByte) } ?? [0.0, 0.0, 1.5, 16.0]
                let scrollOff = inp.singleLine ? (inputScrollOffsets[n.path] ?? 0.0) : 0.0
                let cxPx = r[0] + (localC[0] - scrollOff) * kPx
                let cyPx = r[1] + localC[1] * kPx
                let cwPx = max(localC[2] * kPx, s)
                let chPx = localC[3] * kPx
                inputCaretPx = [cxPx, cyPx, cwPx, chPx]
                if !inp.edit.isSecure() {
                    imeArea = [cxPx / s, cyPx / s, cwPx / s, chPx / s]
                }
            } else if n.imeCursor && imeArea == nil && !n.inert && !subtreeExiting(i) {
                imeArea = pr
            }

            let firstInstance = out.count
            var fadedSlotIdx: Int? = nil

            if visible && paintOpacity > 0.001 {
                let fillCol = sampledColor(nodeId, P_FILL, n.vis.fill)
                let shadows = cold?.shadows ?? []

                // 1. Outer shadows
                if !shadows.isEmpty {
                    let solid = blurHole == nil && n.materialSpec == nil && fillCol.a >= 1.0
                    let opaqueBox = solid && paintOpacity >= 1.0 && cold?.surface == nil
                    let dimHole: Float? = (solid && paintOpacity < 1.0) ? clampCornerRadius(radii, w, h) : nil
                    let caster = ShadowCaster(
                        rect: [r[0], r[1], w, h],
                        radii: radii,
                        shape: radii,
                        kPx: kPx,
                        scale: s,
                        opacity: paintOpacity,
                        srgb: srgb,
                        clip: clip,
                        fade: fade,
                        hole: blurHole ?? dimHole,
                        opaque: opaqueBox
                    )
                    for (si, sh) in shadows.enumerated() where !sh.inset {
                        let sampled = sampledShadow(nodeId, si, sh)
                        if sampled.color.a > 0.0 {
                            pushOuterShadow(&out, sampled, sampled.color, caster)
                        }
                    }
                }

                // 2. Hover / press / focus highlight overlays + fill + border
                var overlay: [Float] = [0.0, 0.0, 0.0, 0.0]
                if let hl = n.focusSpec.highlight, focusedPath == n.path {
                    overlay = over(premul(hl, 1.0, srgb), overlay)
                }
                if n.vis.hover.a > 0.0 {
                    let hv = min(max(scene.get(nodeId, P_HOVER) ?? (hoveredPaths.contains(n.path) ? 1.0 : 0.0), 0.0), 1.0)
                    if hv > 0.0 {
                        overlay = over(premul(sampledColor(nodeId, P_HOVER_C, n.vis.hover), hv, srgb), overlay)
                    }
                }
                if n.vis.press.a > 0.0 {
                    let pv = min(max(scene.get(nodeId, P_PRESS) ?? (pressedPath == n.path ? 1.0 : 0.0), 0.0), 1.0)
                    if pv > 0.0 {
                        overlay = over(premul(sampledColor(nodeId, P_PRESS_C, n.vis.press), pv, srgb), overlay)
                    }
                }

                let basePremul = premul(fillCol, 1.0, srgb)
                let combinedFill = over(overlay, basePremul).map { $0 * paintOpacity }
                let bw = n.vis.borderWidth * kPx
                let borderPremul = bw > 0.0
                    ? premul(sampledColor(nodeId, P_BORDER, n.vis.border), paintOpacity, srgb)
                    : [0.0, 0.0, 0.0, 0.0]
                let borderBottomPremul: [Float]? = (bw > 0.0 && n.vis.borderBottom != nil)
                    ? premul(sampledColor(nodeId, P_BORDER_BOTTOM, n.vis.borderBottom ?? n.vis.border), paintOpacity, srgb)
                    : nil
                let borderKind = borderBottomPremul != nil ? KIND_GRADIENT : KIND_RECT
                let borderUv = borderBottomPremul ?? [0.0, 0.0, 0.0, 0.0]
                let borderAlpha = max(borderPremul[3], borderUv[3])

                if let (surf, fit) = cold?.surface {
                    if combinedFill[3] > 0.0005 {
                        out.append(
                            Instance(
                                rect: [r[0], r[1], w, h],
                                radii: radii,
                                fill: combinedFill,
                                border: [0.0, 0.0, 0.0, 0.0],
                                params: [0.0, KIND_RECT, 0.0, 1.0],
                                uv: [0.0, 0.0, 0.0, 0.0],
                                clip: clip,
                                fade: packFade(fade, clip, clip)
                            )
                        )
                    }
                    surfaces.append(
                        SurfaceDraw(
                            surface: surf,
                            fit: fit,
                            beforeInstance: UInt32(out.count),
                            rect: [r[0], r[1], w, h],
                            radii: radii,
                            clip: clip,
                            fade: packFade(fade, fadeOrigin, clip),
                            opacity: paintOpacity
                        )
                    )
                    if borderAlpha > 0.0005 {
                        out.append(
                            Instance(
                                rect: [r[0], r[1], w, h],
                                radii: radii,
                                fill: [0.0, 0.0, 0.0, 0.0],
                                border: borderPremul,
                                params: [bw, borderKind, 0.0, 1.0],
                                uv: borderUv,
                                clip: clip,
                                fade: packFade(fade, clip, clip)
                            )
                        )
                    }
                } else if combinedFill[3] > 0.0005 || borderAlpha > 0.0005 {
                    let inst = Instance(
                        rect: [r[0], r[1], w, h],
                        radii: radii,
                        fill: combinedFill,
                        border: borderPremul,
                        params: [bw, borderKind, 0.0, 1.0],
                        uv: borderUv,
                        clip: clip,
                        fade: packFade(fade, clip, clip)
                    )
                    if combinedFill == [0.0, 0.0, 0.0, 0.0] && borderKind == KIND_RECT && bw > 0.0 {
                        pushRingBands(&out, inst)
                    } else {
                        out.append(inst)
                    }
                }

                // 3. Inset shadows
                for (si, sh) in shadows.enumerated() where sh.inset {
                    let sampled = sampledShadow(nodeId, si, sh)
                    if sampled.color.a > 0.0 {
                        pushInsetShadow(
                            &out,
                            sampled,
                            sampled.color,
                            rect: [r[0], r[1], w, h],
                            radii: radii,
                            kPx: kPx,
                            scale: s,
                            opacity: paintOpacity,
                            srgb: srgb,
                            clip: clip,
                            fade: fade
                        )
                    }
                }

                // 4. Effect slot (`effectMark`)
                if let effMark = cold?.effectMark, effMark != 0 {
                    fadedSlotIdx = pushEffectSlot(
                        &out,
                        mark: effMark,
                        rect: [r[0], r[1], w, h],
                        radii: radii,
                        clip: clip,
                        fade: packFade(fade, clip, clip),
                        kPx: kPx,
                        opacity: paintOpacity
                    )
                }

                // 5. Focus ring & outline
                let showFocusRing = focusVisible && focusedPath == n.path && !n.focusSpec.ringOff
                let defaultRing = Outline(width: 2.0, offset: 2.0, color: systemAccent.focus(env.systemDark))
                let ringOutline: Outline? = showFocusRing ? (n.focusSpec.ring ?? defaultRing) : nil
                if let ol = ringOutline ?? cold?.outline {
                    let olColor: Color = {
                        if ringOutline != nil { return ol.color }
                        if scene.store().has(nodeId, P_OUTLINE), let oLanes = scene.get(nodeId, P_OUTLINE) {
                            return Color(
                                r: oLanes.lanesValue[2],
                                g: oLanes.lanesValue[3],
                                b: oLanes.lanesValue[4],
                                a: oLanes.lanesValue[5]
                            )
                        }
                        return ol.color
                    }()
                    let g = (ol.offset + ol.width) * kPx
                    if olColor.a > 0.0 && ol.width > 0.0 {
                        out.append(
                            Instance(
                                rect: [r[0] - g, r[1] - g, w + 2.0 * g, h + 2.0 * g],
                                radii: radii.map { v in v != 0.0 ? (v + (v < 0.0 ? -g : g)) : 0.0 },
                                fill: [0.0, 0.0, 0.0, 0.0],
                                border: premul(olColor, paintOpacity, srgb),
                                params: [ol.width * kPx, KIND_RECT, 0.0, 1.0],
                                uv: [0.0, 0.0, 0.0, 0.0],
                                clip: clip,
                                fade: packFade(fade, clip, clip)
                            )
                        )
                    }
                }

                // 6. Leaf content (shapes, pixels, icons, text)
                paintLeafContent(
                    nodeIdx: i,
                    box: LeafBox(
                        r: r,
                        rExact: rExact,
                        rawSize: [pr[2], pr[3]],
                        radii: radii,
                        sc: sc,
                        o: paintOpacity,
                        draw: pres?.draw ?? 1.0,
                        clip: clip,
                        fade: fade,
                        gliding: isAnimatingPose,
                        caret: inputCaretPx
                    ),
                    selectedByPath: selectedByPath,
                    into: &out,
                    glyphCount: &glyphCount
                )
            }

            let packedFade = packFade(fade, fadeOrigin, clip)
            if firstInstance < out.count {
                for idx in firstInstance..<out.count {
                    out[idx].fade = packedFade
                }
            }
            clipTextInstances(
                nodeIdx: i,
                firstInstance: firstInstance,
                into: &out,
                r: r,
                sc: sc,
                clip: clip,
                fade: fade,
                fadeOrigin: fadeOrigin
            )
            if let at = fadedSlotIdx, at + 1 < out.count {
                out[at].fade = [0, 0, 0, 0]
                out[at + 1].fade = [0, 0, 0, 0]
            }

            if trackMarks {
                let markVal = cold?.effectMark ?? 0
                while marks.count < out.count {
                    marks.append(markVal)
                }
            }
        }

        while !openLayers.isEmpty {
            closeTopLayer()
        }

        // Paint snapshots of removed nodes still playing exit transitions in `Scene`
        if !exitingNodes.isEmpty {
            var exitingById: [RuneMotion.NodeId: ExitingNode] = [:]
            exitingById.reserveCapacity(exitingNodes.count)
            for ex in exitingNodes {
                exitingById[ex.nodeId] = ex
            }
            for ex in exitingNodes {
                guard let geo = presentedExitingGeometry(ex, byId: exitingById),
                      let pres = scene.presented(ex.nodeId),
                      geo.opacity > 0.001
                else { continue }
                let exSc = max(geo.scale, 0.001)
                let kPx = exSc * s
                let wx = geo.rect[0]
                let wy = geo.rect[1]
                let ww = geo.rect[2]
                let wh = geo.rect[3]
                let rx = wx * s, ry = wy * s, rw = max(ww * s, 0.0), rh = max(wh * s, 0.0)
                let exClip = ex.clipRect.map { $0 * s }
                let exRadii = pres.radius.values.map { $0 * kPx }
                let exFill = premul(ex.vis.fill, geo.opacity, srgb)
                let exBw = ex.vis.borderWidth * kPx
                let exBorder = exBw > 0.0 ? premul(ex.vis.border, geo.opacity, srgb) : [0.0, 0.0, 0.0, 0.0]
                if exFill[3] > 0.0005 || exBorder[3] > 0.0005 {
                    out.append(
                        Instance(
                            rect: [rx, ry, rw, rh],
                            radii: exRadii,
                            fill: exFill,
                            border: exBorder,
                            params: [exBw, KIND_RECT, pres.blur * kPx, 1.0],
                            uv: [0.0, 0.0, 0.0, 0.0],
                            clip: exClip,
                            fade: [0, 0, 0, 0]
                        )
                    )
                }
                if let spec = ex.textSpec, let layout = ex.textLayout {
                    for line in layout.lines {
                        for g in line.glyphs where g.advance > 0.0 {
                            let q = GlyphQuad(
                                rect: [rx + g.x * kPx, ry + g.y * kPx, g.advance * kPx, g.height * kPx],
                                uv: [0.0, 0.0],
                                ink: 0,
                                byte: UInt32(g.byteOffset)
                            )
                            out.append(glyphInst(q, premul(g.color == spec.color ? spec.color : g.color, geo.opacity * g.alpha, srgb), exClip, [0, 0, 0, 0]))
                            glyphCount += 1
                        }
                    }
                }
            }
        }

        endExitMask()
        _ = drawTextFlights(into: &out, glyphCount: &glyphCount)
        images.endFrame()

        if trackMarks {
            while marks.count < out.count {
                marks.append(0)
            }
        }

        instances = out
        layers = layerSpecs
        return (out, layerSpecs, glyphCount)
    }
}
