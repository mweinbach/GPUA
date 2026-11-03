// Ported from: crates/rune/src/runtime/commit/flatten.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Flatten an `El` view tree into `[Node]` + `TaffyTree<NodeMeasureContext>`, deduplicating sibling keys.

import RuneMotion
import Taffy

/// First-pass room style for an `aspectFit` element: fills free space along its parent's main axis
/// and stretches across the cross axis within `own.maxSize`, ignoring child intrinsic content.
func fitRoomStyle(_ own: Taffy.Style<String>, parentRow: Bool) -> Taffy.Style<String> {
    func zeroAuto(_ d: Dimension) -> Dimension {
        d == .auto() ? .length(0.0) : d
    }
    let mainMax = parentRow ? own.maxSize.width : own.maxSize.height
    var s = own
    s.size = Size(width: own.maxSize.width, height: own.maxSize.height)
    s.minSize = Size(width: zeroAuto(own.minSize.width), height: zeroAuto(own.minSize.height))
    s.flexGrow = 1.0
    s.flexShrink = 1.0
    s.flexBasis = (mainMax == .auto()) ? .length(0.0) : .auto()
    s.alignSelf = .stretch
    s.aspectRatio = nil
    return s
}

/// Second-pass fixed style for an `aspectFit` element at the largest box of `ratio` inside `room`.
func fittedAspectStyle(_ ratio: Float, _ own: Taffy.Style<String>, room: Size<Float>) -> Taffy.Style<String> {
    let safeRatio = max(ratio, 1e-4)
    let w = max(min(room.width, room.height * safeRatio), 0.0)
    var s = own
    s.size = Size(width: .length(w), height: .length(w / safeRatio))
    s.flexGrow = 0.0
    s.flexShrink = 0.0
    s.flexBasis = .auto()
    s.aspectRatio = nil
    return s
}

extension Runtime {
    func flattenViewTree(
        _ rootEl: inout El,
        taffy: inout TaffyTree<NodeMeasureContext>,
        diagnostics: inout [LayoutDiagnostic],
        memoReuses: inout Int
    ) -> Taffy.NodeId? {
        nodes.removeAll(keepingCapacity: true)
        var rootStyleAdjusted = rootEl
        rootFillsViewportWidth = (rootStyleAdjusted.style.size.width == .auto() || rootStyleAdjusted.style.size.width == .percent(1.0))
        rootFillsViewportHeight = (rootStyleAdjusted.style.size.height == .auto() || rootStyleAdjusted.style.size.height == .percent(1.0))
        // Root element fills the window viewport unless explicitly sized otherwise (or `fitHeight` measures natural height).
        if rootStyleAdjusted.style.size.width == .auto() {
            rootStyleAdjusted.style.size.width = .length(viewport.0)
        }
        if fitHeight {
            rootStyleAdjusted.style.size.height = .auto()
        } else if rootStyleAdjusted.style.size.height == .auto() {
            rootStyleAdjusted.style.size.height = .length(viewport.1)
        }
        return flattenElement(
            &rootStyleAdjusted,
            path: "root",
            rawKey: rootStyleAdjusted.key,
            dedupKey: rootStyleAdjusted.key,
            parentIdx: nil,
            parentScale: 1.0,
            parentTimeScale: 1.0,
            parentGroupOpacity: 1.0,
            parentInert: false,
            scrollAncestor: nil,
            inGrowingRow: false,
            taffy: &taffy,
            diagnostics: &diagnostics,
            memoReuses: &memoReuses
        )
    }

    private func flattenElement(
        _ el: inout El,
        path: String,
        rawKey: String?,
        dedupKey: String?,
        parentIdx: Int?,
        parentScale: Float,
        parentTimeScale: Float,
        parentGroupOpacity: Float,
        parentInert: Bool,
        scrollAncestor: Int?,
        inGrowingRow: Bool,
        taffy: inout TaffyTree<NodeMeasureContext>,
        diagnostics: inout [LayoutDiagnostic],
        memoReuses: inout Int
    ) -> Taffy.NodeId? {
        if expandMemoSubtree(&el) {
            memoReuses += 1
        }

        let nodeIdx = nodes.count
        let nodeId = fnvNodeId(path)
        let cumScale = parentScale * el.scaleValue
        let cumTimeScale = parentTimeScale * el.timeScaleValue
        let groupOp = parentGroupOpacity * (el.vis.groupOpacity ?? 1.0)
        let inert = parentInert || el.inertFlag
        let parentIsGrowthStack = parentIdx.map { nodes[$0].growthSpec != nil } ?? false
        let growingHere = inGrowingRow || parentIsGrowthStack || el.glideSpec != nil

        var nodeStyle = el.style
        // Match upstream `El::grow`: `flex_grow > 0` uses `flex_basis: 0` and `flex_shrink: 1`.
        if nodeStyle.flexGrow > 0.0 && nodeStyle.flexBasis == .auto() {
            nodeStyle.flexBasis = .length(0.0)
            nodeStyle.flexShrink = 1.0
        }
        // Match upstream `El::scroll`: set Taffy overflow so scroll viewports do not stretch to content size.
        if el.scrollSpec != nil {
            if el.style.flexDirection == .row {
                if nodeStyle.overflow.x == .visible { nodeStyle.overflow.x = .scroll }
                if nodeStyle.overflow.y == .visible { nodeStyle.overflow.y = .hidden }
            } else {
                if nodeStyle.overflow.x == .visible { nodeStyle.overflow.x = .hidden }
                if nodeStyle.overflow.y == .visible { nodeStyle.overflow.y = .scroll }
            }
        }
        // Anchored overlays are taken out of normal flex flow so they size to their content.
        if el.aboveAnchor != nil {
            nodeStyle.position = .absolute
        }

        // Sync live text if bound
        var textSpecVal = el.textSpec?.value
        if let liveText = textSpecVal?.live {
            textSpecVal?.content = liveText.get()
        }
        if el.input == nil, let tc = textSpecVal?.textCase, let raw = textSpecVal?.content {
            let (cased, _) = TextCaseSource.new(tc, raw)
            textSpecVal?.content = cased
        }
        // Sync focused/edited InputSpec if runtime holds an active edit override for this path/key
        var inputVal = el.input
        if inputVal != nil {
            let isFocusedHere = (focusedPath == path) || (dedupKey != nil && focusedPath?.split(separator: "/").last.map(String.init) == dedupKey)
            if (commitWhy & CommitWhy.FOCUS) != 0 {
                inputVal?.edit.focused = isFocusedHere
            } else if inputVal?.edit.focused != true && isFocusedHere {
                let hasBoundEdit = (dedupKey.flatMap { editAccessors[$0] } != nil)
                    || (editAccessors[path] != nil)
                    || (state is TextEdit)
                if !hasBoundEdit {
                    inputVal?.edit.focused = true
                }
            }
            if let rev = inputVal?.revealedOverride {
                inputVal?.edit.setRevealed(rev)
                textSpecVal?.secureRevealed = rev
            } else if let ed = inputVal?.edit {
                textSpecVal?.secureRevealed = ed.isRevealed()
            }
            if let ed = inputVal?.edit {
                let (disp, _) = ed.display()
                textSpecVal?.content = disp
            }
        }

        let focusSpecVal = el.focusSpec.valueOrEmpty
        let nextScrollAncestor: Int? = (el.scrollSpec != nil) ? nodeIdx : scrollAncestor

        let node = Node(
            index: nodeIdx,
            nodeId: nodeId,
            taffyId: nil,
            path: path,
            key: dedupKey,
            rawKey: rawKey,
            parent: parentIdx,
            children: [],
            traceName: el.traceNameValue,
            traceNamespace: el.traceNamespaceValue,
            role: el.roleName,
            label: el.labelText,
            helpText: el.helpCutFlag ? nil : el.helpText,
            helpCut: el.helpCutFlag,
            style: nodeStyle,
            vis: el.vis,
            focusSpec: focusSpecVal,
            loopingSpec: el.loopingSpec,
            liveBindings: el.liveBindings,
            textSpec: textSpecVal,
            textLayout: nil,
            aboveAnchor: el.aboveAnchor,
            resolvedAnchorSide: nil,
            motionSpring: el.motionSpring,
            opacityMotionAnim: el.opacityMotionAnim,
            animateLayout: el.animateLayoutFlag || (inputVal?.animateLayout ?? false),
            instantChanges: el.instantChangesFlag,
            transitionSpec: el.transitionSpec,
            matchedId: el.matchedId,
            scrollSpec: el.scrollSpec,
            scrollXEnabled: el.scrollSpec != nil && (el.style.flexDirection == .row || nodeStyle.overflow.x == .scroll),
            growthSpec: el.growthSpec,
            streaming: el.streamingFlag,
            whole: el.wholeFlag,
            glideSpec: el.glideSpec,
            input: inputVal,
            windowDrag: el.windowDragFlag,
            imeCursor: el.imeCursorFlag,
            scale: el.scaleValue,
            cumulativeScale: cumScale,
            timeScale: el.timeScaleValue,
            cumulativeTimeScale: cumTimeScale,
            materialSpec: el.materialSpec,
            aspectFit: el.aspectFitValue,
            selectionGroup: el.selectionGroupFlag,
            a11yLevel: el.a11yLevel,
            a11yExpanded: el.a11yExpanded,
            a11ySecure: el.a11ySecure,
            inert: inert,
            virtualExtent: el.hasVirtual,
            stickyTop: el.style.gridTemplateRowNames.first(where: { $0.count == 2 && $0[0] == "__rt_sticky_top__" }).flatMap { Float($0[1]) },
            stuckAmount: 0.0,
            rotate: el.style.gridTemplateRowNames.first(where: { $0.count == 2 && $0[0] == "__rt_rotate__" }).flatMap { Float($0[1]) } ?? 0.0,
            onPressHandler: el.onPressHandler,
            onSecondaryPressHandler: el.onSecondaryPressHandler,
            onKeyHandler: el.onKeyHandler,
            onDragHandler: el.onDragHandler,
            onHoverHandler: el.onHoverHandler,
            scrollAncestor: scrollAncestor,
            inGrowingRow: growingHere,
            groupOpacityAccum: groupOp
        )
        nodes.append(node)

        if let p = parentIdx {
            nodes[p].children.append(nodeIdx)
        }

        // Flatten children, deduplicating duplicate sibling keys
        var seenSiblingKeys: [String: Int] = [:]
        var childTaffyIds: [Taffy.NodeId] = []
        childTaffyIds.reserveCapacity(el.children.count)

        for i in el.children.indices {
            let childRawKey = el.children[i].key
            let childSeg: String
            let childDedupKey: String?
            if let k = childRawKey {
                let count = seenSiblingKeys[k, default: 0]
                seenSiblingKeys[k] = count + 1
                if count == 0 {
                    childSeg = k
                    childDedupKey = k
                } else {
                    let dup = "\(k)#dup\(count)"
                    childSeg = dup
                    childDedupKey = dup
                    diagnostics.append(
                        LayoutDiagnostic(
                            kind: .duplicateSiblingKey,
                            path: "\(path)/\(dup)",
                            message: "Duplicate sibling key '\(k)' under '\(path)'"
                        )
                    )
                }
            } else {
                childSeg = "\(i)"
                childDedupKey = nil
            }

            if let cid = flattenElement(
                &el.children[i],
                path: "\(path)/\(childSeg)",
                rawKey: childRawKey,
                dedupKey: childDedupKey,
                parentIdx: nodeIdx,
                parentScale: cumScale,
                parentTimeScale: cumTimeScale,
                parentGroupOpacity: groupOp,
                parentInert: inert,
                scrollAncestor: nextScrollAncestor,
                inGrowingRow: growingHere,
                taffy: &taffy,
                diagnostics: &diagnostics,
                memoReuses: &memoReuses
            ) {
                childTaffyIds.append(cid)
            }
        }

        // Create Taffy node (leaf with measure context or container with children)
        let parentIsRow: Bool = {
            guard let p = parentIdx else { return false }
            let dir = nodes[p].style.flexDirection
            return dir == .row || dir == .rowReverse
        }()
        let taffyStyle = (nodes[nodeIdx].aspectFit > 0.0 && nodes[nodeIdx].aboveAnchor == nil)
            ? fitRoomStyle(nodeStyle, parentRow: parentIsRow)
            : nodeStyle

        let taffyResult: Result<Taffy.NodeId, TaffyError>
        if childTaffyIds.isEmpty {
            if nodes[nodeIdx].aspectFit > 0.0 {
                taffyResult = taffy.newLeaf(taffyStyle)
            } else if nodes[nodeIdx].textSpec != nil {
                taffyResult = taffy.newLeafWithContext(taffyStyle, .text(nodeIdx))
            } else if let px = nodes[nodeIdx].vis.cold.getIfSome?.pixels {
                let (pw, ph) = px.size()
                taffyResult = taffy.newLeafWithContext(taffyStyle, .pixels(pw, ph))
            } else {
                taffyResult = taffy.newLeaf(taffyStyle)
            }
        } else {
            taffyResult = taffy.newWithChildren(taffyStyle, childTaffyIds)
        }

        if case .success(let tid) = taffyResult {
            nodes[nodeIdx].taffyId = tid
            return tid
        }
        return nil
    }
}
