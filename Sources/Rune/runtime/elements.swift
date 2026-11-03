// Ported from: crates/rune/src/runtime/elements.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Element inspection (`Runtime.elements`, `presented`, `presentedPose`) and point picking (`Runtime.elementAt`).

import RuneMotion

/// What tools see of one element.
public struct ElementInfo: Sendable, Equatable {
    public var traceName: String?
    public var traceNamespace: (String, String)?
    public var loopPhase: Double?
    public var focusable: Bool
    public var focused: Bool
    public var focusVisible: Bool
    public var inert: Bool
    public var exiting: Bool
    public var path: String
    public var key: String?
    public var role: String
    public var label: String?
    public var text: String?
    public var rect: [Float]
    public var target: [Float]
    public var opacity: Float
    public var scale: Float
    public var blur: Float
    public var radius: Float
    public var fill: Color
    public var textColor: Color?
    public var hover: Float
    public var press: Float
    public var moving: Bool
    public var parent: Int?
    public var visible: [Float]
    public var revealing: Bool
    public var inGrowingRow: Bool
    public var scrolling: Bool
    public var scrolled: [Float]
    public var virtualExtent: Bool
    public var liveIntent: UInt32
    public var caret: [Float]?
    public var dragOut: Bool
    public var help: String?
    public var selected: String?
    public var level: UInt32?
    public var expanded: Bool?
    public var itemSelected: Bool
    public var stuck: Float

    public init(
        path: String,
        key: String? = nil,
        role: String = "group",
        label: String? = nil,
        text: String? = nil,
        rect: [Float] = [0, 0, 0, 0],
        target: [Float] = [0, 0, 0, 0],
        opacity: Float = 1.0,
        scale: Float = 1.0,
        blur: Float = 0.0,
        radius: Float = 0.0,
        fill: Color = .TRANSPARENT,
        textColor: Color? = nil,
        parent: Int? = nil
    ) {
        self.traceName = nil
        self.traceNamespace = nil
        self.loopPhase = nil
        self.focusable = false
        self.focused = false
        self.focusVisible = false
        self.inert = false
        self.exiting = false
        self.path = path
        self.key = key
        self.role = role
        self.label = label
        self.text = text
        self.rect = rect
        self.target = target
        self.opacity = opacity
        self.scale = scale
        self.blur = blur
        self.radius = radius
        self.fill = fill
        self.textColor = textColor
        self.hover = 0
        self.press = 0
        self.moving = false
        self.parent = parent
        self.visible = rect
        self.revealing = false
        self.inGrowingRow = false
        self.scrolling = false
        self.scrolled = [0, 0]
        self.virtualExtent = false
        self.liveIntent = 0
        self.caret = nil
        self.dragOut = false
        self.help = nil
        self.selected = nil
        self.level = nil
        self.expanded = nil
        self.itemSelected = false
        self.stuck = 0
    }

    public static func == (lhs: ElementInfo, rhs: ElementInfo) -> Bool {
        lhs.path == rhs.path && lhs.key == rhs.key && lhs.role == rhs.role
            && lhs.label == rhs.label && lhs.text == rhs.text && lhs.rect == rhs.rect
            && lhs.target == rhs.target && lhs.opacity == rhs.opacity && lhs.scale == rhs.scale
            && lhs.fill == rhs.fill && lhs.focused == rhs.focused && lhs.exiting == rhs.exiting
    }
}

/// An element `Runtime.elementAt` found.
public struct Picked: Sendable, Equatable {
    var pathValue: String
    var keyValue: String?

    public init(path: String, key: String? = nil) {
        self.pathValue = path
        self.keyValue = key
    }

    public func path() -> String { pathValue }
    public func key() -> String? { keyValue }
}

/// Options for `Runtime.elementAtWith` and siblings.
public struct Pick: Sendable, Equatable {
    var includeTransparent: Bool = false

    public init() {}

    public static func new() -> Pick { Pick() }

    public func transparent(_ on: Bool) -> Pick {
        var copy = self
        copy.includeTransparent = on
        return copy
    }
}

/// What an element presents beyond its rect and opacity, as of the last frame.
public struct Pose: Sendable, Equatable {
    var rotationValue: Float
    var scaleValue: Float
    var shadowsList: [Shadow]
    var movingFlag: Bool

    public init(
        rotation: Float = 0,
        scale: Float = 1,
        shadows: [Shadow] = [],
        moving: Bool = false
    ) {
        self.rotationValue = rotation
        self.scaleValue = scale
        self.shadowsList = shadows
        self.movingFlag = moving
    }

    public func rotation() -> Float { rotationValue }
    public func scale() -> Float { scaleValue }
    public func shadows() -> [Shadow] { shadowsList }
    public func moving() -> Bool { movingFlag }
}

extension Runtime {
    func isNodeSecure(_ n: Node) -> Bool {
        n.a11ySecure
            || (n.textSpec?.redacted ?? false)
            || (n.input?.edit.isSecure() ?? false)
    }

    private func nodeLiveIntentBits(_ n: Node) -> UInt32 {
        var bits: UInt32 = 0
        for b in n.liveBindings where b.spring == nil {
            switch b.property {
            case .offset:
                bits |= 1
            case .scale, .rect:
                bits |= 1 | 2
            case .opacity:
                bits |= 4
            case .fill, .blur:
                break
            }
        }
        return bits
    }

    func isNodeExiting(_ id: RuneMotion.NodeId) -> Bool {
        if case .exiting = scene.phase(id) { return true }
        return false
    }

    public func isExiting(_ id: RuneMotion.NodeId) -> Bool {
        isNodeExiting(id)
    }

    private func isNodeMoving(_ id: RuneMotion.NodeId) -> Bool {
        let store = scene.store()
        return store.isAnimating(id, RuneMotion.prop.frame)
            || store.isAnimating(id, RuneMotion.prop.travel)
            || store.isAnimating(id, RuneMotion.prop.presence)
            || store.isAnimating(id, RuneMotion.prop.offset)
            || store.isAnimating(id, RuneMotion.prop.scale)
            || store.isAnimating(id, P_PRESS_SCALE)
            || store.isAnimating(id, P_SCALE)
            || store.isAnimating(id, RuneMotion.prop.rotation)
            || paintPoseSpringing(scene, id)
            || (!reducedMotion && (loops[id].map { !$0.sleeping } ?? false))
    }

    /// Tracks sampled during the latest tick: `(path, propName, active)`.
    func touchedTracks() -> [(String, String, Bool)] {
        let store = scene.store()
        var out: [(String, String, Bool)] = []
        for (track, nodeId, p) in store.touchedTracks() {
            let path = nodes.first(where: { $0.nodeId == nodeId })?.path ?? "node:\(nodeId.rawValue)"
            out.append((path, propName(p), store.isActive(track)))
        }
        out.sort { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return !lhs.2 && rhs.2
        }
        var deduped: [(String, String, Bool)] = []
        for item in out {
            if let last = deduped.last, last.0 == item.0 && last.1 == item.1 && last.2 == item.2 {
                continue
            }
            deduped.append(item)
        }
        return deduped
    }

    /// Leaf elements that draw nothing and hold nothing (spacers, invisible hit zones).
    func blankLeaves() -> Set<String> {
        var out: Set<String> = []
        for n in nodes where n.children.isEmpty {
            let v = n.vis
            let cold = v.cold.getIfSome
            let blankBorder = v.borderWidth == 0.0 || (v.border.a == 0.0 && (v.borderBottom?.a ?? 0.0) == 0.0)
            if n.textSpec == nil
                && n.input == nil
                && !n.focusSpec.enabled
                && n.materialSpec == nil
                && v.fill.a == 0.0
                && blankBorder
                && (cold?.shadows.isEmpty ?? true)
                && cold?.surface == nil
                && cold?.icon == nil
                && cold?.outline == nil
                && cold?.shape == nil
                && cold?.pixels == nil
                && cold?.effectMark == nil
                && v.hover.a == 0.0
                && v.press.a == 0.0
            {
                out.insert(n.path)
            }
        }
        return out
    }

    /// Whether an element path contains secure/redacted text.
    public func elementIsSecure(_ path: String) -> Bool {
        ensureClean()
        guard let idx = keyIndex.nodeByPath(path) else { return false }
        return isNodeSecure(nodes[idx])
    }

    /// Inspect all mounted and exiting elements as of the latest commit/frame.
    public func elements() -> [ElementInfo] {
        ensureClean()

        var selectedTextByPath: [String: String] = [:]
        if let sel = currentTextSelection() {
            for item in sel.items {
                selectedTextByPath[item.path] = item.text
            }
        }
        let focusedCaret = computeFocusedCaretEntry()

        var infos: [ElementInfo] = []
        infos.reserveCapacity(nodes.count + exitingNodes.count + activeTextFlights.count)

        for i in nodes.indices {
            let n = nodes[i]
            let id = n.nodeId
            let pres = scene.presented(id)
            let exiting = subtreeExiting(i)
            let landingFlight = activeTextFlights.first { $0.lands(n.path, n.key) }

            var moving = landingFlight != nil
                || isNodeMoving(id)
                || (growthTracks[id]?.moving() ?? false)
            var scrollingNow = false
            var liveIntent = nodeLiveIntentBits(n)

            var anc = n.parent
            while let pIdx = anc {
                let pn = nodes[pIdx]
                moving = moving || isNodeMoving(pn.nodeId) || (growthTracks[pn.nodeId]?.moving() ?? false)
                liveIntent |= nodeLiveIntentBits(pn)
                if pn.scrollSpec != nil {
                    let sKey = pn.key ?? pn.path
                    let sSpringing = (scrolls[sKey]?.isMoving ?? false) || (scrollsX[sKey]?.isMoving ?? false)
                    let sScrolling = (scrolls[sKey]?.isScrollingOrMoving ?? false) || (scrollsX[sKey]?.isMoving ?? false)
                    scrollingNow = scrollingNow || sScrolling
                    moving = moving || sSpringing
                }
                anc = pn.parent
            }

            let drawn = n.presentedRect
            let rect: [Float]
            if let f = landingFlight {
                let d = f.destination
                let c = f.presented
                let zx = c.w / max(d.w, 1e-3)
                let zy = c.h / max(d.h, 1e-3)
                rect = [c.x + (drawn[0] - d.x) * zx, c.y + (drawn[1] - d.y) * zy, drawn[2] * zx, drawn[3] * zy]
            } else {
                rect = n.turn.isActive ? n.turn.bbox(drawn) : drawn
            }

            let secure = isNodeSecure(n)
            let shownText: String? = {
                guard !secure else { return nil }
                if let ts = n.textSpec {
                    return ts.content
                }
                if n.role == "text" {
                    return n.label
                }
                return nil
            }()

            let effectiveOp: Float = {
                if let f = landingFlight {
                    return f.targetAlpha
                }
                var op = (pres?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
                var cur = n.parent
                while let pIdx = cur {
                    op *= (scene.presented(nodes[pIdx].nodeId)?.opacity ?? nodes[pIdx].vis.opacity)
                    cur = nodes[pIdx].parent
                }
                return min(max(op, 0.0), 1.0)
            }()

            let effectiveBlur: Float = {
                if landingFlight != nil { return 0.0 }
                var b = pres?.blur ?? (n.vis.cold.getIfSome?.layerBlur ?? 0.0)
                var cur = n.parent
                while let pIdx = cur {
                    b += scene.presented(nodes[pIdx].nodeId)?.blur ?? (nodes[pIdx].vis.cold.getIfSome?.layerBlur ?? 0.0)
                    cur = nodes[pIdx].parent
                }
                return b
            }()

            let isFocused = (focusedPath == n.path)
            var info = ElementInfo(
                path: n.path,
                key: n.key,
                role: n.role,
                label: n.label,
                text: shownText,
                rect: rect,
                target: n.layoutRect,
                opacity: effectiveOp,
                scale: landingFlight != nil ? 1.0 : n.cumulativeScale,
                blur: effectiveBlur,
                radius: (pres?.radius ?? n.vis.corners).values[0],
                fill: sampledColor(id, P_FILL, n.vis.fill),
                textColor: nodeTextColor(n).map { sampledColor(id, P_TEXT, $0) },
                parent: n.parent
            )
            info.traceName = n.traceName
            info.traceNamespace = n.traceNamespace
            info.loopPhase = loops[id].map { entry in
                if reducedMotion {
                    if case .sequence = entry.spec.kind { return 1.0 }
                    return 0.0
                }
                return entry.phase
            }
            info.focusable = isNodeFocusable(i)
            info.focused = isFocused
            info.focusVisible = focusVisible && isFocused
            info.inert = n.inert || exiting
            info.exiting = exiting
            info.hover = scene.get(id, P_HOVER) ?? (hoveredPaths.contains(n.path) ? 1.0 : 0.0)
            info.press = scene.get(id, P_PRESS) ?? (pressedPath == n.path ? 1.0 : 0.0)
            info.moving = moving
            info.visible = n.visibleRect
            info.revealing = landingFlight != nil || activeRevealProgress(for: i) < 0.999
            info.inGrowingRow = n.inGrowingRow
            info.scrolling = scrollingNow
            info.scrolled = n.scrollOffsetApplied
            info.virtualExtent = n.virtualExtent
            info.liveIntent = liveIntent
            info.caret = (focusedCaret?.0 == n.path) ? focusedCaret?.1 : nil
            info.dragOut = false
            info.help = n.helpText
            info.selected = (!secure && (n.textSpec?.selectable ?? false)) ? selectedTextByPath[n.path] : nil
            info.level = n.a11yLevel
            info.expanded = n.a11yExpanded
            info.itemSelected = n.focusSpec.selected
            info.stuck = n.stuckAmount
            infos.append(info)
        }

        // Include removed nodes still playing exit transitions
        if !exitingNodes.isEmpty {
            var exitingById: [RuneMotion.NodeId: ExitingNode] = [:]
            exitingById.reserveCapacity(exitingNodes.count)
            for ex in exitingNodes {
                exitingById[ex.nodeId] = ex
            }
            for ex in exitingNodes {
                guard let geo = presentedExitingGeometry(ex, byId: exitingById),
                      let pres = scene.presented(ex.nodeId)
                else { continue }
                let rect = geo.rect
                var info = ElementInfo(
                    path: ex.path,
                    key: ex.key,
                    role: ex.role,
                    label: ex.label,
                    text: ex.textSpec?.content,
                    rect: rect,
                    target: ex.worldRect,
                    opacity: geo.opacity,
                    scale: geo.scale,
                    blur: geo.blur,
                    radius: pres.radius.values[0],
                    fill: ex.vis.fill,
                    textColor: ex.textSpec?.color,
                    parent: nil
                )
                info.inert = true
                info.exiting = true
                info.moving = true
                info.visible = rect
                infos.append(info)
            }
        }

        // Synthetic flight-source elements while cross-fading in air
        for f in activeTextFlights {
            let r = reducedMotion ? f.source : f.presented
            let c = reducedMotion ? f.sourceClip : f.clip
            let tRect = f.destination
            let fPath = "flight-source/\(f.targetKey)"
            var info = ElementInfo(
                path: fPath,
                key: fPath,
                role: "text",
                label: nil,
                text: nil,
                rect: [r.x, r.y, r.w, r.h],
                target: [tRect.x, tRect.y, tRect.w, tRect.h],
                opacity: f.sourceAlpha,
                scale: 1.0,
                blur: 0.0,
                radius: 0.0,
                fill: .TRANSPARENT,
                textColor: nil,
                parent: nil
            )
            info.inert = true
            info.moving = true
            info.revealing = true
            let vx0 = max(r.x, c[0])
            let vy0 = max(r.y, c[1])
            let vx1 = min(r.x + r.w, c[2])
            let vy1 = min(r.y + r.h, c[3])
            info.visible = [vx0, vy0, max(0.0, vx1 - vx0), max(0.0, vy1 - vy0)]
            infos.append(info)
        }

        return infos
    }

    /// Drawn rect `[x, y, w, h]` in points and effective opacity of the element keyed `key` (exiting or mounted).
    public func presented(_ key: String) -> ([Float], Float)? {
        ensureClean()
        if let idx = nodes.firstIndex(where: { $0.key == key || selectsKeyPath(key, $0.path, $0.key) }) {
            let n = nodes[idx]
            var op = (scene.presented(n.nodeId)?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
            var cur = n.parent
            while let p = cur {
                op *= (scene.presented(nodes[p].nodeId)?.opacity ?? nodes[p].vis.opacity)
                cur = nodes[p].parent
            }
            return (n.presentedRect, min(max(op, 0.0), 1.0))
        }
        if !exitingNodes.isEmpty {
            var exitingById: [RuneMotion.NodeId: ExitingNode] = [:]
            exitingById.reserveCapacity(exitingNodes.count)
            for ex in exitingNodes {
                exitingById[ex.nodeId] = ex
            }
            if let ex = exitingNodes.first(where: { $0.key == key || selectsKeyPath(key, $0.path, $0.key) }),
               let geo = presentedExitingGeometry(ex, byId: exitingById)
            {
                return (geo.rect, geo.opacity)
            }
        }
        return nil
    }

    /// Presented rotation, scale, shadows, and moving state of the element keyed `key`.
    public func presentedPose(_ key: String) -> Pose? {
        ensureClean()
        if let idx = nodes.firstIndex(where: { selectsKeyPath(key, $0.path, $0.key) }) {
            let n = nodes[idx]
            let rawShadows = n.vis.cold.getIfSome?.shadows ?? []
            let shadows = rawShadows.enumerated().map { k, sh in
                sampledShadow(n.nodeId, k, sh)
            }
            var moving = isNodeMoving(n.nodeId) || (growthTracks[n.nodeId]?.moving() ?? false)
            var cur = n.parent
            while let p = cur {
                moving = moving || isNodeMoving(nodes[p].nodeId)
                cur = nodes[p].parent
            }
            let rot = scene.get(n.nodeId, RuneMotion.prop.rotation) ?? 0.0
            return Pose(
                rotation: rot,
                scale: n.cumulativeScale,
                shadows: shadows,
                moving: moving
            )
        }
        if let ex = exitingNodes.first(where: { selectsKeyPath(key, $0.path, $0.key) && isNodeExiting($0.nodeId) }),
           let pres = scene.presented(ex.nodeId)
        {
            return Pose(
                rotation: pres.transform.rotate,
                scale: ex.scale * pres.transform.scale.x,
                shadows: ex.vis.cold.getIfSome?.shadows ?? [],
                moving: true
            )
        }
        return nil
    }

    private func isNodePickable(_ idx: Int, x: Float, y: Float, pick: Pick) -> Bool {
        guard nodes.indices.contains(idx), !subtreeExiting(idx) else { return false }
        let n = nodes[idx]
        if !pick.includeTransparent {
            var op = (scene.presented(n.nodeId)?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
            var cur = n.parent
            while let p = cur {
                op *= (scene.presented(nodes[p].nodeId)?.opacity ?? nodes[p].vis.opacity)
                cur = nodes[p].parent
            }
            if op <= 0.0 {
                return false
            }
        }
        let c = n.clipBounds
        guard x >= c[0] && x < c[2] && y >= c[1] && y < c[3] else { return false }
        let r = n.presentedRect
        return x >= r[0] && x < r[0] + r[2] && y >= r[1] && y < r[1] + r[3]
    }

    private func elementAtWithin(_ within: String?, _ x: Float, _ y: Float, _ pick: Pick) -> Picked? {
        ensureClean()
        let scopeIdx: Int?
        if let wKey = within {
            guard let found = nodes.firstIndex(where: { selectsKeyPath(wKey, $0.path, $0.key) }) else {
                return nil
            }
            scopeIdx = found
        } else {
            scopeIdx = nil
        }

        // Build paint order (normal tree, then overlay subtrees on top)
        var order: [Int] = []
        let overlays = nodes.indices.filter { nodes[$0].aboveAnchor != nil }
        let overlaySet = Set(overlays)
        func walk(_ idx: Int, skipOv: Bool) {
            if skipOv && overlaySet.contains(idx) { return }
            order.append(idx)
            for c in nodes[idx].children {
                walk(c, skipOv: skipOv)
            }
        }
        if !nodes.isEmpty {
            walk(0, skipOv: true)
            for ov in overlays {
                walk(ov, skipOv: false)
            }
        }

        for idx in order.reversed() {
            if let sIdx = scopeIdx {
                var cur: Int? = idx
                var inside = false
                while let p = cur {
                    if p == sIdx {
                        inside = true
                        break
                    }
                    cur = nodes[p].parent
                }
                if !inside { continue }
            }
            if isNodePickable(idx, x: x, y: y, pick: pick) {
                return Picked(path: nodes[idx].path, key: nodes[idx].key)
            }
        }
        return nil
    }

    public func elementAt(_ x: Float, _ y: Float) -> Picked? {
        elementAtWithin(nil, x, y, Pick())
    }

    public func elementAtWith(_ x: Float, _ y: Float, _ pick: Pick) -> Picked? {
        elementAtWithin(nil, x, y, pick)
    }

    public func elementAtIn(_ within: String, _ x: Float, _ y: Float) -> Picked? {
        elementAtWithin(within, x, y, Pick())
    }

    public func elementAtInWith(_ within: String, _ x: Float, _ y: Float, _ pick: Pick) -> Picked? {
        elementAtWithin(within, x, y, pick)
    }

    public func contains(_ key: String, _ x: Float, _ y: Float) -> Bool {
        containsWith(key, x, y, Pick())
    }

    public func containsWith(_ key: String, _ x: Float, _ y: Float, _ pick: Pick) -> Bool {
        ensureClean()
        guard let idx = nodes.firstIndex(where: { selectsKeyPath(key, $0.path, $0.key) }) else {
            return false
        }
        return isNodePickable(idx, x: x, y: y, pick: pick)
    }

    /// Whether the root element's fill is dark (`luminance < 0.25`) when opaque.
    func backdropDark() -> Bool? {
        guard !transparent, let root = nodes.first else { return nil }
        let c = sampledColor(root.nodeId, P_FILL, root.vis.fill)
        guard c.a > 0.5 else { return nil }
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.25
    }
}
