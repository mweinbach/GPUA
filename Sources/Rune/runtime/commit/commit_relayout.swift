// Ported from: crates/rune/src/runtime/commit/relayout.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Explicit `Tx.relayout()` handling and resize-only tree relayout without re-running `view`.

import Taffy

extension Runtime {
    public func relayout() {
        textLayoutCache.removeAll()
        markDirty(CommitWhy.RELAYOUT)
        ensureClean()
    }

    /// Re-lay out the last committed `nodes` at the new `viewport` without running `view(state, cx)`.
    /// Returns `true` when the fast path succeeded and no layout/caret read changed; returns `false`
    /// (restoring `previousNodes` untouched) when `view` needs to run.
    func tryRelayoutWithoutView(why: UInt16, previousNodes: [Node], diagnostics: inout [LayoutDiagnostic]) -> Bool {
        guard why == CommitWhy.RELAYOUT,
              hasCommittedOnce,
              !pendingSettleCommit,
              exitingNodes.isEmpty,
              lastCommittedScale == env.scale,
              lastCommittedSrgbBlend == srgbBlend,
              !nodes.isEmpty
        else { return false }

        // Nodes with live bindings, fitted anchored overlays, or virtual list extents require a full commit
        for n in nodes {
            if !n.liveBindings.isEmpty { return false }
            if n.aboveAnchor?.fit == true { return false }
            if n.virtualExtent { return false }
        }

        // Work on fresh node copies so `previousNodes` retains its old rects & `textLayout`s
        var candidate = previousNodes
        for i in candidate.indices {
            candidate[i].textLayout = nil
            candidate[i].taffyId = nil
        }
        if rootFillsViewportWidth {
            candidate[0].style.size.width = .length(viewport.0)
        }
        if fitHeight {
            candidate[0].style.size.height = .auto()
        } else if rootFillsViewportHeight {
            candidate[0].style.size.height = .length(viewport.1)
        }

        nodes = candidate
        var taffy = TaffyTree<NodeMeasureContext>()
        taffy.disableRounding()

        func buildTaffySubtree(_ idx: Int) -> Taffy.NodeId? {
            var childIds: [Taffy.NodeId] = []
            childIds.reserveCapacity(nodes[idx].children.count)
            for cIdx in nodes[idx].children {
                if let cid = buildTaffySubtree(cIdx) {
                    childIds.append(cid)
                }
            }
            let parentIsRow: Bool = {
                guard let p = nodes[idx].parent else { return false }
                let dir = nodes[p].style.flexDirection
                return dir == .row || dir == .rowReverse
            }()
            let taffyStyle = (nodes[idx].aspectFit > 0.0 && nodes[idx].aboveAnchor == nil)
                ? fitRoomStyle(nodes[idx].style, parentRow: parentIsRow)
                : nodes[idx].style
            let res: Result<Taffy.NodeId, TaffyError>
            if childIds.isEmpty {
                if nodes[idx].aspectFit > 0.0 {
                    res = taffy.newLeaf(taffyStyle)
                } else if nodes[idx].textSpec != nil {
                    res = taffy.newLeafWithContext(taffyStyle, .text(idx))
                } else if let px = nodes[idx].vis.cold.getIfSome?.pixels {
                    let (pw, ph) = px.size()
                    res = taffy.newLeafWithContext(taffyStyle, .pixels(pw, ph))
                } else {
                    res = taffy.newLeaf(taffyStyle)
                }
            } else {
                res = taffy.newWithChildren(taffyStyle, childIds)
            }
            if case .success(let tid) = res {
                nodes[idx].taffyId = tid
                return tid
            }
            return nil
        }

        guard let rootTid = buildTaffySubtree(0) else {
            nodes = previousNodes
            return false
        }

        let viewportRoom = Size<AvailableSpace>(
            width: .definite(viewport.0),
            height: fitHeight ? .maxContent : .definite(viewport.1)
        )
        _ = taffy.computeLayoutWithMeasure(rootTid, viewportRoom, makeTaffyMeasureClosure())
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
            _ = taffy.computeLayoutWithMeasure(rootTid, viewportRoom, makeTaffyMeasureClosure())
        }
        extractTaffyLayouts(&taffy, diagnostics: &diagnostics)
        reconcileFocusAfterCommit()

        let newSnapshot = buildLayoutReadSnapshot()
        let readChanged = ((!lastCommittedLayoutReadKeys.isEmpty || lastCommittedCaretRead)
            && newSnapshot.differs(for: lastCommittedLayoutReadKeys, caretRead: lastCommittedCaretRead, from: lastLayoutSnapshot))
            || newSnapshot.differsPredicates(lastCommittedLayoutPredicates)

        if readChanged {
            nodes = previousNodes
            return false
        }

        syncMemoLayoutSnapshot(from: lastLayoutSnapshot, to: newSnapshot)
        lastLayoutSnapshot = newSnapshot
        return true
    }
}
