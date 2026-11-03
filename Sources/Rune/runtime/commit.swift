// Ported from: crates/rune/src/runtime/commit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Top-level commit orchestration: evaluate `view(state, cx)`, expand/reuse `memo`, flatten to
//! Taffy, resolve anchored overlays, iterate layout-read fixpoints (up to 3 passes), and apply to `Scene`.

import RuneMotion
import Taffy

extension Runtime {
    func markDirty(_ why: UInt16) {
        dirty = true
        pendingCommitWhy |= why
    }

    func ensureClean() {
        if dirty {
            performCommit()
        }
    }

    func performCommit() {
        let why = pendingCommitWhy == 0 ? CommitWhy.UPDATE : pendingCommitWhy
        commitWhy |= why
        pendingCommitWhy = 0
        dirty = false
        commitsThisFrame += 1
        totalCommits &+= 1

        pushEventMarker(
            kind: "commit",
            detail: CommitWhy.names(why).joined(separator: ",")
        )

        let previousNodes = nodes
        let isFirstCommit = !hasCommittedOnce
        var diagnostics: [LayoutDiagnostic] = []
        var totalMemoBuilds = 0
        var totalMemoReuses = 0

        // Capture pre-commit text flight sources if `tx.flyText` was requested
        capturePreCommitTextFlights(from: previousNodes)

        if !tryRelayoutWithoutView(why: why, previousNodes: previousNodes, diagnostics: &diagnostics) {
            let maxPasses = 3
            var pass = 0
            while pass < maxPasses {
                pass += 1
                bumpCommitGeneration()

                let buildsBefore = memo.builds
                let finishMemo = enterMemoScope(
                    memo,
                    env: env,
                    reducedMotion: reducedMotion,
                    srgbBlend: srgbBlend
                )
                let cx = Cx<S>(
                    env: env,
                    titlebarInset: titlebarInset,
                    systemAccent: systemAccent,
                    systemReducedMotion: systemReducedMotion,
                    reducedMotion: reducedMotion,
                    timeScale: timeScale,
                    caret: lastLayoutSnapshot.caret,
                    layoutRects: lastLayoutSnapshot.layoutRects,
                    windowRects: lastLayoutSnapshot.windowRects
                )

                var rootEl = withSceneClock(SceneClock(now: t, dt: lastDt)) {
                    withBlend(srgbBlend) {
                        view(state, cx)
                    }
                }
                let (memoKeys, memoCaret) = finishMemo()
                cx.caretRead = cx.caretRead || memoCaret
                for mk in memoKeys where !cx.layoutReadKeys.contains("@size:\(mk)") {
                    cx.layoutReadKeys.insert(mk)
                }
                totalMemoBuilds += (memo.builds - buildsBefore)

                // Absorb any view-declared `reducedMotion` / `timeScale` updates on `cx`
                if cx.reducedMotionValue != reducedMotion {
                    reducedMotion = cx.reducedMotionValue
                    scene.setReducedMotion(reducedMotion)
                }
                if cx.timeScaleValue != timeScale {
                    timeScale = cx.timeScaleValue
                }

                diagnostics.removeAll(keepingCapacity: true)
                var memoReusesThisPass = 0
                var taffy = TaffyTree<NodeMeasureContext>()
                taffy.disableRounding()
                if let rootTid = flattenViewTree(
                    &rootEl,
                    taffy: &taffy,
                    diagnostics: &diagnostics,
                    memoReuses: &memoReusesThisPass
                ) {
                    totalMemoReuses += memoReusesThisPass
                    let viewportRoom = Size<AvailableSpace>(
                        width: .definite(viewport.0),
                        height: fitHeight ? .maxContent : .definite(viewport.1)
                    )
                    _ = taffy.computeLayoutWithMeasure(
                        rootTid,
                        viewportRoom,
                        makeTaffyMeasureClosure()
                    )
                    var refitAspect = false
                    for i in nodes.indices where nodes[i].aspectFit > 0.0 {
                        if let tid = nodes[i].taffyId,
                           case .success(let layout) = taffy.layout(tid)
                        {
                            let fitted = fittedAspectStyle(nodes[i].aspectFit, nodes[i].style, room: layout.size)
                            _ = taffy.setStyle(tid, fitted)
                            refitAspect = true
                        }
                    }
                    if refitAspect {
                        _ = taffy.computeLayoutWithMeasure(
                            rootTid,
                            viewportRoom,
                            makeTaffyMeasureClosure()
                        )
                    }
                    extractTaffyLayouts(&taffy, diagnostics: &diagnostics)
                }

                reconcileFocusAfterCommit()
                let newSnapshot = buildLayoutReadSnapshot()
                let readChanged = ((!cx.layoutReadKeys.isEmpty || cx.caretRead)
                    && newSnapshot.differs(for: cx.layoutReadKeys, caretRead: cx.caretRead, from: lastLayoutSnapshot))
                    || newSnapshot.differsPredicates(cx.layoutPredicates)
                syncMemoLayoutSnapshot(from: lastLayoutSnapshot, to: newSnapshot)
                lastLayoutSnapshot = newSnapshot
                lastCommittedLayoutReadKeys = cx.layoutReadKeys
                lastCommittedCaretRead = cx.caretRead
                lastCommittedLayoutPredicates = cx.layoutPredicates

                if !readChanged {
                    break
                }
                if pass == maxPasses {
                    diagnostics.append(
                        LayoutDiagnostic(
                            kind: .layoutReadCycle,
                            path: "root",
                            message: "Layout reads did not stabilize within \(maxPasses) passes"
                        )
                    )
                }
            }
            lastCommittedScale = env.scale
            lastCommittedSrgbBlend = srgbBlend
        }

        if fitHeight, let root = nodes.first {
            fitWindow(height: root.localRect[3], first: isFirstCommit, why: why)
        }

        lastLayoutDiagnostics = diagnostics
        lastMemoStats = MemoStats(builds: totalMemoBuilds, reuses: totalMemoReuses)

        applyNodesToScene(previousNodes: previousNodes)
        hasCommittedOnce = true

        // Snapshot initial/instant scene poses so post-commit focus, scroll reveals, and loop culling
        // observe the newly committed rects immediately.
        _ = scene.frameAt(t)

        // Resolve post-commit text flights, scroll reveals, focus validity, and pruning
        resolvePostCommitTextFlights()
        reconcileFocusAfterCommit()
        syncSingleLineInputScrollOffsets()
        drainPostCommitScrollRequests()
        collectVirtualSelectableTexts()
        refreshPresentedGeometries()

        var mountedKeys: Set<String> = []
        var mountedPaths: Set<String> = []
        for n in nodes {
            mountedPaths.insert(n.path)
            if let k = n.key { mountedKeys.insert(k) }
        }
        pruneStaleState(
            mountedIds: applyScratch.mountedIds,
            mountedKeys: mountedKeys,
            mountedPaths: mountedPaths
        )

        if pendingSettleCommit {
            settleAll()
        }

        // Clear one-shot commit motion overrides
        pendingInstantCommit = false
        pendingSettleCommit = false
        pendingMotionSpring = nil
        pendingMotionCurve = nil
        pendingColorSpring = nil
    }
}
