// Ported from: crates/rune/src/window/stepping.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Runtime stepping for visible and covered windows/overlays (`crates/rune/src/window/stepping.rs`).

#if !os(WASI)
import Foundation
#endif
import RuneMotion
import Taffy

private let windowHostStateKey = "gpua.rune.window.hostState"

struct HostElExtras {
    var cursor: Cursor? = nil
    var onDoublePress: ((States, inout Tx) -> Void)? = nil
    var onPaste: ((States, String, inout Tx) -> Void)? = nil
    var onDropFiles: ((States, [String], inout Tx) -> Void)? = nil
    var onDropHover: ((States, Bool, inout Tx) -> Void)? = nil
    var onWindowFocus: ((States, Bool, inout Tx) -> Void)? = nil
    var onSubmit: ((States, inout Tx) -> Void)? = nil
    var editAccess: ((States, (inout TextEdit) -> Void) -> Bool)? = nil
}

// PORT NOTE: Only checks atomic ARC weak liveness (`target != nil`) without reading or mutating `Runtime<S>`, matching Rust `Weak<live::Wake>` drop semantics when a `Runtime` is deinitialized.
private final class HostRuntimeLivenessProbe: @unchecked Sendable {
    private weak var target: AnyObject?
    init(_ target: AnyObject) { self.target = target }
    var isAlive: Bool { target != nil }
}

func hostAttachExtras(_ el: El, _ modify: (inout HostElExtras) -> Void) -> El {
    var copy = el
    var extras = copy.handlers.getIfSome?.hostExtras ?? HostElExtras()
    modify(&extras)
    copy.handlers.value.hostExtras = extras
    return copy
}

struct HostNodeEntry {
    var nodeId: NodeId
    var parentId: NodeId?
    var parentElemIndex: Int?
    var key: String?
    var path: String
    var identity: String
    var localRect: RuneMotion.Rect
    var worldRect: RuneMotion.Rect
    var scrollShift: (Float, Float)
    var clipRect: [Float]?
    var fill: Color
    var hoverFill: Color
    var pressFill: Color
    var border: Color
    var borderWidth: Float
    var corners: Corners
    var opacity: Float
    var transition: Transition
    var motionSpring: Spring?
    var opacityAnim: Anim?
    var animateLayout: Bool
    var instantChanges: Bool
    var hasGrowth: Bool
    var textSpec: TextSpec?
    var pixels: Pixels?
    var effectMark: UInt32?
    var windowDrag: Bool
    var helpText: String?
    var helpCut: Bool
    var focusable: Bool
    var focusHighlight: Color?
    var focusFollows: Bool
    var defaultButton: Bool
    var isInput: Bool
    var singleLineInput: Bool
    var inputEditFocused: Bool
    var scrollSpec: ScrollSpec?
    var role: String
    var label: String?
    var inert: Bool
    var hasPressHandler: Bool
    var hasRealOnKey: Bool
    var onPress: ((States, inout Tx) -> Void)?
    var onSecondaryPress: ((States, PointerEvent, inout Tx) -> Void)?
    var onKey: ((States, KeyEvent, inout Tx) -> Bool)?
    var onDrag: ((States, inout Drag, inout Tx) -> Void)?
    var onHover: ((States, Bool, inout Tx) -> Void)?
    var extras: HostElExtras
    var liveBindings: [LiveBound]
}

// PORT NOTE: Per-`Runtime` host layout/motion/live/input/playground state stored in `RuntimeHostAttachment` so `window`, `overlay`, `desktop`, `playground`, and `app` run full Taffy + `RuneMotion.Scene` + `LiveWake` + `TimerWake` pipelines without modifying Spine `Sources/Rune/runtime.swift`.
final class RuntimeWindowHostState: @unchecked Sendable {
    var firstCommit: Bool = true
    var needsCommit: Bool = true
    var pendingInstant: Bool = false
    var pendingSpring: Spring? = nil
    var pendingCurve: Anim? = nil
    var pendingSettle: Bool = false
    var pendingRelayout: Bool = false

    // Focus tracking (path + optional key)
    var focusedPath: String? = nil
    var focusedKey: String? = nil
    var keyboardFocus: Bool = false
    var hoverFocus: Bool = false

    var windowFocused: Bool = true
    var titlebarInset: Float = 0.0
    var windowOrigin: (Float, Float) = (0.0, 0.0)
    var systemAccent: SystemAccent = .DEFAULT
    var fontSmoothing: FontSmoothing = .default
    var fontFamilies: (String, String) = ("Inter", "Inter")
    var modifierKeys: Bool = false
    var tabVisitsControls: Bool = false

    // Playground & Spine `Runtime.frame` bridge hooks
    var playground: AnyObject? = nil
    var appPoll: ((inout Any, Double, inout Tx) -> Bool)? = nil
    var hasHostPollBridge: Bool = false
    var insideHostCommit: Bool = false
    var activeSpineStatePtr: UnsafeMutableRawPointer? = nil
    var appOnFocus: ((inout Any, Bool, inout Tx) -> Void)? = nil
    var appOnIme: ((inout Any, Ime, inout Tx) -> Bool)? = nil

    // Timer & live wake state
    var timerDeadlines: [Double] = []
    var pendingWakeDurations: [Double] = []
    var timerFrameArmed: Bool = false
    var lastPolledClock: Double? = nil
    var liveVisible: Bool = true
    var liveWake: LiveWake = LiveWake {}
    var liveDirty: Bool = false
    var liveSubscriptions: [LiveSubscription] = []
    let liveClockToken = LiveClockToken()

    // Retained scene node tracking
    var mountedNodeIds: [String: NodeId] = [:]
    var exitingNodes: [String: (NodeId, ElementInfo)] = [:]
    var lastNodes: [HostNodeEntry] = []
    var lastElements: [ElementInfo] = []
    var layoutRects: [String: [Float]] = [:]
    var windowRects: [String: [Float]] = [:]
    var dragRegions: [[Float]] = []
    var effectSlots: [(UInt32, [Float])] = []
    var nextSyntheticNodeRaw: UInt64 = 1_000_000

    // Scroll state
    var scrollOffsets: [String: Float] = [:]
    var scrollMaxByPath: [String: Float] = [:]
    var pendingScrollReveals: [ScrollReveal] = []
    var pendingScrollRequests: [ScrollRequest] = []
    var pendingScrollBottoms: [(String, Bool)] = []

    // Pointer & interaction state
    var pointerPos: (Float, Float)? = nil
    var pointerDownPos: (Float, Float)? = nil
    var pointerButtonHeld: PointerButton? = nil
    var activeDragNodePath: String? = nil
    var activeDragData: Float = 0.0
    var activeDragClicks: UInt32 = 1
    var lastClickTime: Double = -.infinity
    var lastClickPos: (Float, Float) = (0.0, 0.0)
    var lastClickCount: UInt32 = 0
    var activePressClicks: UInt32 = 1
    var clickMovedPastSlop: Bool = false
    var hoveredPaths: Set<String> = []
    var currentCursor: Cursor = .default
    var currentHelp: (String, [Float])? = nil
    var imeActive: Bool = false
    var imeSpot: ((Float, Float), (Float, Float))? = nil
    var lastStats = FrameStats()

    // File drop callbacks
    var lastHoveredFiles: [String] = []
    var lastDroppedFiles: [String] = []

    // Window frame & fit-content-height state
    var pendingWindowFrameRequest: WindowFrameRequest? = nil
    var fitContentHeight: Bool = false
    var fitHeld: Bool = false
    var fitTargetHeight: Float? = nil
    var fitLimits: ((Float, Float), (Float, Float)?) = ((0.0, 0.0), nil)

    // Physical key state & trace anim sources
    var lastPhysicalKey: PhysicalKeyCode? = nil
    var animSources: UInt16 = 0
    var dragCancelledSuppressNextUp: Bool = false

    // Debug performance meters
    let perfIdle = PerfIdleMeter()
    let perfWatch = PerfWatch()
    var hadInputSinceLastFrame: Bool = false
    var commitsCount: UInt64 = 0
    var systemReducedMotion: Bool = false

    init() {}

    func allocNodeId(for identity: String) -> NodeId {
        if let existing = mountedNodeIds[identity] {
            return existing
        }
        if let (exitingId, _) = exitingNodes.removeValue(forKey: identity) {
            mountedNodeIds[identity] = exitingId
            return exitingId
        }
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in identity.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        if h == 0 {
            nextSyntheticNodeRaw &+= 1
            h = nextSyntheticNodeRaw
        }
        while mountedNodeIds.values.contains(NodeId(h)) {
            h &+= 1
            if h == 0 { h = 1 }
        }
        let nid = NodeId(h)
        mountedNodeIds[identity] = nid
        return nid
    }
}

func windowHostState(for runtime: AnyObject) -> RuntimeWindowHostState {
    let att = hostAttachment(for: runtime)
    if let existing = att.customData[windowHostStateKey] as? RuntimeWindowHostState {
        return existing
    }
    let created = RuntimeWindowHostState()
    att.customData[windowHostStateKey] = created
    return created
}

// PORT NOTE: `TaffyNodePayload` holds transient `El` subtrees during single-threaded `hostCommitTree` layout and never escapes `TaffyTree`.
private final class TaffyNodePayload: @unchecked Sendable {
    var el: El
    var path: String
    var identity: String

    init(el: El, path: String, identity: String) {
        self.el = el
        self.path = path
        self.identity = identity
    }
}

@inline(__always)
private func motionColor(_ c: Color) -> RuneMotion.Color {
    RuneMotion.Color(r: c.r, g: c.g, b: c.b, a: c.a)
}

private func intersectClip(_ a: [Float]?, _ b: [Float]) -> [Float] {
    guard let a, a.count == 4, b.count == 4 else { return b }
    let x0 = max(a[0], b[0])
    let y0 = max(a[1], b[1])
    let x1 = min(a[2], b[2])
    let y1 = min(a[3], b[3])
    return [x0, y0, max(x0, x1), max(y0, y1)]
}

private func visibleWithinClip(_ rect: RuneMotion.Rect, _ clip: [Float]?) -> [Float] {
    guard let clip, clip.count == 4 else {
        return [rect.x, rect.y, rect.w, rect.h]
    }
    let x0 = max(rect.x, clip[0])
    let y0 = max(rect.y, clip[1])
    let x1 = min(rect.x + rect.w, clip[2])
    let y1 = min(rect.y + rect.h, clip[3])
    return [x0, y0, max(0.0, x1 - x0), max(0.0, y1 - y0)]
}

@inline(__always)
private func hostDrawnRect(_ pres: RuneMotion.Presented, scrollShift: (Float, Float)) -> RuneMotion.Rect {
    let sx = pres.transform.scale.x
    let sy = pres.transform.scale.y
    var x = pres.rect.x
    var y = pres.rect.y
    var w = pres.rect.w
    var h = pres.rect.h
    if abs(sx - 1.0) > 1e-5 || abs(sy - 1.0) > 1e-5 {
        x = pres.anchor.x + (x - pres.anchor.x) * sx
        y = pres.anchor.y + (y - pres.anchor.y) * sy
        w *= sx
        h *= sy
    }
    x -= scrollShift.0
    y -= scrollShift.1
    return RuneMotion.Rect(x: x, y: y, w: w, h: h)
}

extension Runtime {
    // MARK: - Playground & State Routing

    func hostPlayground() -> PlaygroundLive<S>? {
        windowHostState(for: self).playground as? PlaygroundLive<S>
    }

    func hostInstallPlayground(_ live: PlaygroundLive<S>, appPoll: ((inout S, Double, inout Tx) -> Bool)?) {
        let hs = windowHostState(for: self)
        hs.playground = live
        hs.needsCommit = true
        hostInstallSpineFrameBridge(appPoll: appPoll)
    }

    func hostInstallSpineFrameBridge(appPoll: ((inout S, Double, inout Tx) -> Bool)?) {
        let hs = windowHostState(for: self)
        hs.appPoll = appPoll.map { fn in
            { anyState, clockVal, tx in
                guard var typed = anyState as? S else { return false }
                let changed = fn(&typed, clockVal, &tx)
                anyState = typed
                return changed
            }
        }
        hs.hasHostPollBridge = true
        self.poll = { [weak self] stateRef, _, _ in
            guard let self else { return false }
            let hs = windowHostState(for: self)
            withUnsafeMutablePointer(to: &stateRef) { ptr in
                hs.activeSpineStatePtr = UnsafeMutableRawPointer(ptr)
                defer { hs.activeSpineStatePtr = nil }
                self.hostStepFromSpineFrame()
            }
            return false
        }
    }

    private func hostReadState(_ hs: RuntimeWindowHostState) -> S {
        if let raw = hs.activeSpineStatePtr {
            return raw.assumingMemoryBound(to: S.self).pointee
        }
        return state
    }

    private func hostMutateAppState<R>(_ hs: RuntimeWindowHostState, _ body: (inout S) -> R) -> R {
        if let raw = hs.activeSpineStatePtr {
            let ptr = raw.assumingMemoryBound(to: S.self)
            return body(&ptr.pointee)
        }
        return body(&state)
    }

    func hostSetAppOnFocus(_ f: ((inout S, Bool, inout Tx) -> Void)?) {
        let hs = windowHostState(for: self)
        hs.appOnFocus = f.map { fn in
            { anyState, focused, tx in
                guard var typed = anyState as? S else { return }
                fn(&typed, focused, &tx)
                anyState = typed
            }
        }
    }

    func hostSetAppOnIme(_ f: ((inout S, Ime, inout Tx) -> Bool)?) {
        let hs = windowHostState(for: self)
        hs.appOnIme = f.map { fn in
            { anyState, ime, tx in
                guard var typed = anyState as? S else { return false }
                let handled = fn(&typed, ime, &tx)
                anyState = typed
                return handled
            }
        }
    }

    func hostWithStates<R>(_ body: (States) -> R) -> R {
        let hs = windowHostState(for: self)
        if let live = hostPlayground() {
            return hostMutateAppState(hs) { appRef in
                live.withStates(&appRef, body)
            }
        }
        return hostMutateAppState(hs) { appRef in
            let s = States.one(appRef)
            let r = body(s)
            if let updated = s.app as? S {
                appRef = updated
            }
            return r
        }
    }

    func hostStatesRef() -> StatesRef {
        let hs = windowHostState(for: self)
        let current = hostReadState(hs)
        if let live = hostPlayground() {
            return live.statesRef(current)
        }
        return StatesRef.one(current)
    }

    private func hostAppRootIndex(_ hs: RuntimeWindowHostState) -> Int {
        hostPlayground()?.root ?? 0
    }

    private func hostFindAppRoot(_ hs: RuntimeWindowHostState) {
        guard let live = hostPlayground() else { return }
        func isMargin(_ k: String?) -> Bool { k == "playground-margin" }
        func wraps(_ k: String) -> Bool {
            k == "playground-closed" || isMargin(k) || playgroundIsStage(k)
        }
        live.root = hs.lastNodes.indices.first(where: { idx in
            !isMargin(hs.lastNodes[idx].key)
                && hs.lastNodes[idx].parentElemIndex.flatMap { hs.lastNodes[$0].key }.map(wraps) == true
        }) ?? 0
    }

    private func hostNodeUnder(_ hs: RuntimeWindowHostState, _ idx: Int, _ predicate: (String) -> Bool) -> Bool {
        var cur: Int? = idx
        while let j = cur, j >= 0 && j < hs.lastNodes.count {
            if let k = hs.lastNodes[j].key, predicate(k) {
                return true
            }
            cur = hs.lastNodes[j].parentElemIndex
        }
        return false
    }

    private func hostFocusedIndex(_ hs: RuntimeWindowHostState) -> Int? {
        if let fp = hs.focusedPath,
           let idx = hs.lastNodes.firstIndex(where: { $0.path == fp && !$0.inert })
        {
            return idx
        }
        if let fk = hs.focusedKey,
           let idx = hs.lastNodes.firstIndex(where: { $0.key == fk && !$0.inert })
        {
            return idx
        }
        return nil
    }

    private func hostKeyPath(_ hs: RuntimeWindowHostState, _ key: String) -> String? {
        hs.lastNodes.first(where: { $0.key == key && !$0.inert })?.path
    }

    private func hostCanFocus(_ hs: RuntimeWindowHostState, _ idx: Int) -> Bool {
        guard idx >= 0 && idx < hs.lastNodes.count else { return false }
        let n = hs.lastNodes[idx]
        return n.focusable && !n.inert
    }

    private func hostOnSideKeys(_ hs: RuntimeWindowHostState) -> Bool {
        guard !hs.hoverFocus, let idx = hostFocusedIndex(hs) else { return false }
        guard let k = hs.lastNodes[idx].key else { return false }
        return k.hasPrefix("playground-slot-")
    }

    private func hostSyncSideFocus(_ hs: RuntimeWindowHostState) {
        let active = hostOnSideKeys(hs)
        if let live = hostPlayground(), live.setSideActive(active) {
            hs.needsCommit = true
        }
    }

    func hostSetFocus(_ target: String?, visible: Bool = false) {
        let hs = windowHostState(for: self)
        let prevIdx = hostFocusedIndex(hs)
        hs.hoverFocus = false
        hs.keyboardFocus = visible
        guard let target else {
            if let prevIdx, let editAccess = hs.lastNodes[prevIdx].extras.editAccess {
                hostWithStates { states in
                    _ = editAccess(states) { $0.focused = false }
                }
            }
            if hs.focusedPath != nil || hs.focusedKey != nil {
                hs.focusedPath = nil
                hs.focusedKey = nil
                hs.needsCommit = true
            }
            hostSyncSideFocus(hs)
            return
        }
        if let entry = hs.lastNodes.first(where: { !$0.inert && ($0.path == target || $0.key == target) }) {
            hs.focusedPath = entry.path
            hs.focusedKey = entry.key
        } else {
            hs.focusedPath = target
            hs.focusedKey = target
        }
        let nextIdx = hostFocusedIndex(hs)
        if prevIdx != nextIdx {
            if let prevIdx, let editAccess = hs.lastNodes[prevIdx].extras.editAccess {
                hostWithStates { states in
                    _ = editAccess(states) { $0.focused = false }
                }
            }
            if let nextIdx, let editAccess = hs.lastNodes[nextIdx].extras.editAccess {
                hostWithStates { states in
                    _ = editAccess(states) { $0.focused = true }
                }
            }
        }
        hs.needsCommit = true
        hostSyncSideFocus(hs)
    }

    func hostFocused() -> String? {
        let hs = windowHostState(for: self)
        return hs.focusedPath ?? hs.focusedKey
    }

    private func hostSyncRegion(_ hs: RuntimeWindowHostState) {
        let focused = hs.focusedPath ?? hs.focusedKey
        let hover = hs.hoverFocus
        guard let live = hostPlayground() else { return }
        if !live.seeFocus(focused) || hover { return }
        guard let idx = hostFocusedIndex(hs) else { return }
        let region: PlaygroundRegion
        if hostNodeUnder(hs, idx, { $0 == "playground-side" }) {
            region = .side
        } else if hostNodeUnder(hs, idx, playgroundIsStage) {
            region = .stage
        } else {
            region = .list
        }
        if live.setRegion(region) {
            hs.needsCommit = true
        }
    }

    private func hostGiveRegion(_ hs: RuntimeWindowHostState, _ region: PlaygroundRegion) {
        let focused = hs.focusedPath ?? hs.focusedKey
        guard let live = hostPlayground() else { return }
        _ = live.seeFocus(focused)
        if live.setRegion(region) {
            hs.needsCommit = true
        }
    }

    private func hostToList(_ hs: RuntimeWindowHostState) {
        hostSetFocus(nil, visible: true)
        hostGiveRegion(hs, .list)
    }

    private func hostPlaygroundPointerDown(_ hs: RuntimeWindowHostState, _ x: Float) {
        guard let live = hostPlayground(), live.isOpen() else { return }
        let region = live.regionAt(x, viewport.0)
        hostGiveRegion(hs, region)
    }

    private func hostPlaygroundSidePaths(_ hs: RuntimeWindowHostState) -> [String] {
        var out: [String] = []
        for idx in hs.lastNodes.indices {
            if hostCanFocus(hs, idx) && hostNodeUnder(hs, idx, { $0 == "playground-side" }) {
                out.append(hs.lastNodes[idx].path)
            }
        }
        return out
    }

    private func hostDrainUnlatchedPlayground(_ hs: RuntimeWindowHostState) {
        let unlatched = pgDrainUnlatchedRequests()
        guard !unlatched.isEmpty else { return }
        hs.pendingInstant = true
        if let live = hostPlayground() {
            live.request(unlatched)
            hs.needsCommit = true
        }
    }

    private func hostLatchPlayground(_ tx: inout Tx, _ hs: RuntimeWindowHostState) {
        let boxes = tx.drainSidecar(as: PlaygroundRequestBox.self)
        let requests = pgMarkBoxesLatched(boxes)
        guard !requests.isEmpty else { return }
        tx.instantFlag = true
        hs.pendingInstant = true
        if let live = hostPlayground() {
            live.request(requests)
            hs.needsCommit = true
        }
    }

    private func hostApplyPlayground(_ hs: RuntimeWindowHostState) {
        hostDrainUnlatchedPlayground(hs)
        hostSyncRegion(hs)
        guard let live = hostPlayground(), live.hasPending() else { return }
        let swaps = live.pendingSwapsStage()
        let keepSideFocus = live.pendingReplaysOnly()
            && (hostFocusedIndex(hs).map { hostNodeUnder(hs, $0, { $0 == "playground-side" }) } ?? false)
        let wasOpen = live.isOpen()
        if swaps && !keepSideFocus && (hs.focusedPath != nil || hs.focusedKey != nil) {
            hostSetFocus(nil, visible: false)
        }
        let applied = hostMutateAppState(hs) { appRef in
            live.apply(clock, &appRef)
        }
        guard applied else { return }
        memo.clear()
        if swaps {
            hostLeaveStage(hs, wasOpen: wasOpen)
        }
        if live.polls() {
            hs.pendingWakeDurations.append(0.0)
            hs.timerDeadlines.append(clock)
            hs.timerDeadlines.sort()
        }
    }

    private func hostLeaveStage(_ hs: RuntimeWindowHostState, wasOpen: Bool) {
        for (_, (nid, _)) in hs.exitingNodes {
            scene.unmount(nid)
        }
        hs.exitingNodes.removeAll()
        hs.pointerButtonHeld = nil
        hs.pointerDownPos = nil
        hs.activeDragNodePath = nil
        hs.activeDragData = 0.0
        hs.activeDragClicks = 1
        hs.lastClickTime = -.infinity
        hs.lastClickCount = 0
        hs.activePressClicks = 1
        hs.clickMovedPastSlop = false
        hs.hoveredPaths.removeAll()
        hs.lastHoveredFiles.removeAll()
        if let live = hostPlayground() {
            if wasOpen {
                timeScale = live.appTimeScale
            } else {
                live.appTimeScale = timeScale
            }
        }
    }

    private func hostFlushPendingBeforeInput(_ hs: RuntimeWindowHostState) {
        hostDrainUnlatchedPlayground(hs)
        let att = hostAttachment(for: self)
        let pendingPg = hostPlayground()?.hasPending() ?? false
        if hs.firstCommit || pendingPg || ((hs.needsCommit || att.dirtyFromHost) && hs.focusedKey != nil && hostFocusedIndex(hs) == nil) {
            hostCommitTree(hs)
            hs.needsCommit = false
            att.dirtyFromHost = false
        }
    }

    private func hostAppKey(
        _ hs: RuntimeWindowHostState,
        _ fn: (inout S, KeyEvent, inout Tx) -> Bool,
        _ ev: KeyEvent,
        _ tx: inout Tx
    ) -> Bool {
        if let live = hostPlayground() {
            return live.withKeyState(&state) { keyState in
                fn(&keyState, ev, &tx)
            } ?? false
        }
        return fn(&state, ev, &tx)
    }

    private func hostFilterKey(_ hs: RuntimeWindowHostState, _ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        let plain = !ev.mods.alt && !ev.mods.ctrl && !ev.mods.cmd && !ev.mods.shift
        guard plain,
              let idx = hostFocusedIndex(hs),
              hs.lastNodes[idx].key == PLAYGROUND_FILTER,
              let live = hostPlayground()
        else {
            return false
        }
        let targetIndex: Int?
        switch ev.key {
        case .escape where live.clearFilter():
            hs.needsCommit = true
            return true
        case .down:
            targetIndex = live.firstShown()
        case .enter:
            targetIndex = live.firstMatch()
        case .escape:
            targetIndex = nil
        default:
            return false
        }
        if let i = targetIndex {
            tx.pgPush(.select(i))
        }
        hostSetFocus(nil, visible: true)
        return true
    }

    private func hostPlaygroundNav(_ hs: RuntimeWindowHostState, _ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        guard let live = hostPlayground() else { return false }
        if live.isShortcut(ev) {
            if !tx.keyRepeatFlag {
                tx.togglePlayground()
            }
            return true
        }
        if live.isTyping(state), let rootOnKey = onKey {
            if hostAppKey(hs, rootOnKey, ev, &tx) {
                return true
            }
        }
        guard live.isOpen() else { return false }
        hostSyncRegion(hs)
        if let idx = hostFocusedIndex(hs), hs.lastNodes[idx].isInput {
            return hostFilterKey(hs, ev, &tx)
        }
        if hostOnSideKeys(hs) {
            switch ev.key {
            case .escape, .tab:
                hostToList(hs)
                return true
            default:
                if live.sideKey(ev, &tx) {
                    return true
                }
            }
        }
        let side = hostPlaygroundSidePaths(hs)
        let focusedCurrent = hs.hoverFocus ? nil : hs.focusedPath
        let at = focusedCurrent.flatMap { fp in side.firstIndex(of: fp) }
        switch live.nav(ev, live.region()) {
        case .pass:
            return false
        case .stay:
            return true
        case .request(let req):
            let isTrigger: Bool
            switch req {
            case .trigger, .replay: isTrigger = true
            default: isTrigger = false
            }
            if !(isTrigger && tx.keyRepeatFlag) {
                tx.pgPush(req)
            }
            return true
        case .intoSide:
            if let first = side.first {
                hostSetFocus(first, visible: true)
            }
            hostGiveRegion(hs, .side)
            return true
        case .intoStage:
            hostSetFocus(nil, visible: true)
            hostGiveRegion(hs, .stage)
            return true
        case .filter:
            guard let path = hostKeyPath(hs, PLAYGROUND_FILTER) else { return false }
            hostSetFocus(path, visible: true)
            return true
        case .outOfSide:
            hostToList(hs)
            return true
        case .sideStep where side.isEmpty:
            return true
        case .sideStep(let by):
            let n = side.count
            let nextIndex: Int
            if let at {
                let raw = (at + by) % n
                nextIndex = raw < 0 ? raw + n : raw
            } else if by > 0 {
                nextIndex = 0
            } else {
                nextIndex = n - 1
            }
            let path = side[nextIndex]
            hostSetFocus(path, visible: true)
            tx.scrollToRequests.append(ScrollReveal(key: path, center: false, animated: false))
            return true
        }
    }

    private func hostPlaygroundKey(_ hs: RuntimeWindowHostState, _ ev: KeyEvent, _ tx: inout Tx) -> Bool {
        let plain = !ev.mods.cmd && !ev.mods.alt && !ev.mods.ctrl && !ev.mods.shift
        guard ev.key == .escape, plain, let live = hostPlayground(), live.isOpen() else {
            return false
        }
        hostSyncRegion(hs)
        if live.region() != .list {
            hostToList(hs)
        } else {
            tx.closePlayground()
        }
        return true
    }

    // MARK: - Tx Latching & Poll Execution

    func hostLatchWindowTx(_ tx: inout Tx) {
        let hs = windowHostState(for: self)
        hostRecordTraceCalls(tx)
        hostLatchPlayground(&tx, hs)

        let frameBoxes = tx.drainSidecar(as: WindowFrameRequestBox.self)
        for box in frameBoxes {
            if var req = box.take() {
                if req.animate && !tx.instantFlag && !reducedMotion {
                    req.spring = tx.motionSpring ?? .smooth
                } else {
                    req.animate = false
                    req.spring = nil
                }
                hs.pendingWindowFrameRequest = (hs.pendingWindowFrameRequest ?? WindowFrameRequest()).merge(req)
            }
        }
        if !tx.wakes.isEmpty {
            hs.pendingWakeDurations.append(contentsOf: tx.wakes)
            for sec in tx.wakes {
                let target = clock + max(sec, 0.0)
                hs.timerDeadlines.append(target)
            }
            hs.timerDeadlines.sort()
            tx.wakes.removeAll()
        }
        if !tx.scrollToRequests.isEmpty {
            hs.pendingScrollReveals.append(contentsOf: tx.scrollToRequests)
            tx.scrollToRequests.removeAll()
            hs.needsCommit = true
        }
        if !tx.scrollOffsetRequests.isEmpty {
            hs.pendingScrollRequests.append(contentsOf: tx.scrollOffsetRequests)
            tx.scrollOffsetRequests.removeAll()
            hs.needsCommit = true
        }
        if !tx.scrollBottomRequests.isEmpty {
            hs.pendingScrollBottoms.append(contentsOf: tx.scrollBottomRequests)
            tx.scrollBottomRequests.removeAll()
            hs.needsCommit = true
        }
        if tx.instantFlag {
            hs.pendingInstant = true
        }
        if let curve = tx.motionCurveAnim {
            hs.pendingCurve = curve
        } else if let sp = tx.motionSpring {
            hs.pendingSpring = sp
        }
        if tx.settleFlag {
            hs.pendingSettle = true
            toolingTraceState(for: self).settledThisFrame = true
            tx.settleFlag = false
        }
        if tx.relayoutFlag {
            hs.pendingRelayout = true
            hs.needsCommit = true
            tx.relayoutFlag = false
        }
        let initialFocusBoxes = tx.drainSidecar(as: HostInitialFocusBox.self)
        let hadInitialFocus = !initialFocusBoxes.isEmpty
        let initialFocus = initialFocusBoxes.first?.key
        if tx.blurFlag {
            hostSetFocus(nil, visible: hs.keyboardFocus)
            tx.blurFlag = false
            if let fk = tx.focusedKey, (!hadInitialFocus || fk != initialFocus) {
                hostSetFocus(fk, visible: hs.keyboardFocus)
            }
        } else if let fk = tx.focusedKey, (!hadInitialFocus || fk != initialFocus) {
            if fk != hs.focusedKey && fk != hs.focusedPath {
                hostSetFocus(fk, visible: hs.keyboardFocus)
            }
        }
        if let srgb = tx.srgbBlendRequest {
            self.srgbBlend = srgb
            hs.needsCommit = true
            tx.srgbBlendRequest = nil
        }
        if let smooth = tx.fontSmoothingRequest {
            hs.fontSmoothing = smooth
            hs.needsCommit = true
            tx.fontSmoothingRequest = nil
        }
        if let fams = tx.fontFamiliesRequest {
            hs.fontFamilies = fams
            hs.needsCommit = true
            tx.fontFamiliesRequest = nil
        }
        if !tx.liveOnlyFlag {
            hs.needsCommit = true
        }
    }

    @discardableResult
    func hostRunPollHooks() -> Bool {
        let hs = windowHostState(for: self)
        let att = hostAttachment(for: self)
        var anyChanged = false

        if hs.hasHostPollBridge {
            if let appPoll = hs.appPoll {
                var tx = hostNewTx()
                let changed = hostMutateAppState(hs) { appRef -> Bool in
                    var erased: Any = appRef
                    let c = hs.perfIdle.polled(perfTimed("poll") { appPoll(&erased, clock, &tx) })
                    if let updated = erased as? S {
                        appRef = updated
                    }
                    return c
                }
                hs.lastPolledClock = clock
                if !changed {
                    tx.liveOnly()
                } else {
                    hs.perfWatch.cause |= ToolingCommitWhy.POLL
                    hs.perfWatch.meter.poll()
                    anyChanged = true
                }
                hostLatchTx(&tx)
                if changed && !tx.liveOnlyFlag {
                    hs.needsCommit = true
                    att.dirtyFromHost = true
                }
            }
        } else if let pollFn = poll {
            var tx = hostNewTx()
            let changed = hs.perfIdle.polled(perfTimed("poll") { pollFn(&state, clock, &tx) })
            hs.lastPolledClock = clock
            if !changed {
                tx.liveOnly()
            } else {
                hs.perfWatch.cause |= ToolingCommitWhy.POLL
                hs.perfWatch.meter.poll()
                anyChanged = true
            }
            hostLatchTx(&tx)
            if changed && !tx.liveOnlyFlag {
                hs.needsCommit = true
                att.dirtyFromHost = true
            }
        }

        if let live = hostPlayground(), live.polls() {
            var tx = hostNewTx()
            let stageChanged = live.pollStage(clock, &tx)
            if !stageChanged {
                tx.liveOnly()
            } else {
                hs.perfWatch.cause |= ToolingCommitWhy.POLL
                anyChanged = true
            }
            hostLatchTx(&tx)
            if stageChanged && !tx.liveOnlyFlag {
                hs.needsCommit = true
                att.dirtyFromHost = true
            }
        }

        return anyChanged
    }

    func hostWindowNeedsCommit() -> Bool {
        let hs = windowHostState(for: self)
        return hs.needsCommit || (hostPlayground()?.hasPending() ?? false)
    }

    func hostRecordPolledAt() {
        windowHostState(for: self).lastPolledClock = clock
    }

    func hostInvalidate() {
        let hs = windowHostState(for: self)
        hs.needsCommit = true
        hostAttachment(for: self).dirtyFromHost = true
    }

    func hostSetLiveWaker(_ waker: @escaping Waker) {
        let hs = windowHostState(for: self)
        for sub in hs.liveSubscriptions {
            sub.active = false
        }
        hs.liveSubscriptions.removeAll(keepingCapacity: true)
        let probe = HostRuntimeLivenessProbe(self)
        let lw = LiveWake {
            guard probe.isAlive else { return }
            waker()
        }
        lw.setVisible(hs.liveVisible)
        hs.liveWake = lw
        hostSubscribeLive(hs)
    }

    func hostSetLiveVisible(_ visible: Bool) {
        let hs = windowHostState(for: self)
        hs.liveWake.setVisible(visible)
        hs.liveVisible = visible
    }

    func hostLiveVisible() -> Bool {
        windowHostState(for: self).liveVisible
    }

    func hostLivePending() -> Bool {
        let hs = windowHostState(for: self)
        return hs.liveVisible && (hs.liveDirty || hs.liveWake.pending)
    }

    func hostSetSrgbBlend(_ enabled: Bool) {
        if srgbBlend != enabled {
            srgbBlend = enabled
            hostInvalidate()
        }
    }

    func hostSrgbBlend() -> Bool {
        srgbBlend
    }

    func hostCommits() -> UInt64 {
        windowHostState(for: self).commitsCount
    }

    private func hostSubscribeLive(_ hs: RuntimeWindowHostState) {
        for idx in hs.lastNodes.indices {
            for bIdx in hs.lastNodes[idx].liveBindings.indices {
                hs.lastNodes[idx].liveBindings[bIdx].attach(hs.liveClockToken, clock)
            }
        }
        for sub in hs.liveSubscriptions {
            sub.active = false
        }
        var sampled = false
        for entry in hs.lastNodes {
            let liveTextSource = entry.textSpec?.live?.source
            let pixelsSource = entry.pixels?.source
            let hasLive = !entry.liveBindings.isEmpty
            if !hasLive && liveTextSource == nil && pixelsSource == nil {
                continue
            }
            if !scene.contains(entry.nodeId) {
                continue
            }
            if liveTextSource != nil || hasLive {
                sampled = true
            }
            var sources = entry.liveBindings.map(\.source)
            if let ts = liveTextSource { sources.append(ts) }
            if let ps = pixelsSource { sources.append(ps) }
            for src in sources {
                if let existing = hs.liveSubscriptions.first(where: { $0.sourceId == src.id }) {
                    existing.active = true
                } else {
                    hs.liveSubscriptions.append(src.subscribe(hs.liveWake))
                }
            }
        }
        hs.liveSubscriptions.removeAll { !$0.active }
        hs.liveDirty = sampled
    }

    func hostWakeDeadline() -> Double? {
        windowHostState(for: self).timerDeadlines.first
    }

    func hostPolledAt() -> Double? {
        windowHostState(for: self).lastPolledClock
    }

    func hostSchedulePendingWakes() -> [Double] {
        let hs = windowHostState(for: self)
        let out = hs.pendingWakeDurations
        hs.pendingWakeDurations.removeAll()
        return out
    }

    func hostArmTimerFrame() {
        windowHostState(for: self).timerFrameArmed = true
    }

    func hostCancelTimerFrame() -> Bool {
        let hs = windowHostState(for: self)
        let was = hs.timerFrameArmed
        hs.timerFrameArmed = false
        return was
    }

    func hostRests() -> Bool {
        let hs = windowHostState(for: self)
        return !hs.lastStats.animating && !hostNeedsCommit() && !hostLivePending()
    }

    func hostStale() -> Bool {
        hostNeedsCommit() || hostLivePending()
    }

    func hostSetViewport(_ width: Float, _ height: Float) {
        let w = max(width, 0.0)
        let h = max(height, 0.0)
        if viewport.0 != w || viewport.1 != h {
            viewport = (w, h)
            hostInvalidate()
        }
    }

    func hostSetScale(_ scale: Float) {
        let s = max(scale, 0.25)
        if env.scale != s {
            env.scale = s
            scene.setPixelScale(s)
            hostInvalidate()
        }
    }

    func hostSetSystemDark(_ dark: Bool) {
        if env.systemDark != dark {
            env.systemDark = dark
            hostInvalidate()
        }
    }

    func hostSetSystemAccent(_ accent: SystemAccent) {
        let hs = windowHostState(for: self)
        if hs.systemAccent != accent {
            hs.systemAccent = accent
            hostInvalidate()
        }
    }

    func hostSystemAccent() -> SystemAccent {
        windowHostState(for: self).systemAccent
    }

    func hostSetSystemReducedMotion(_ on: Bool) {
        let hs = windowHostState(for: self)
        if hs.systemReducedMotion != on {
            hs.systemReducedMotion = on
            hostInvalidate()
        }
    }

    func hostSystemReducedMotion() -> Bool {
        windowHostState(for: self).systemReducedMotion
    }

    func hostSetTitlebarInset(_ inset: Float) {
        let hs = windowHostState(for: self)
        if hs.titlebarInset != inset {
            hs.titlebarInset = inset
            hostInvalidate()
        }
    }

    func hostTitlebarInset() -> Float {
        windowHostState(for: self).titlebarInset
    }

    func hostSetWindowOrigin(_ x: Float, _ y: Float) {
        let hs = windowHostState(for: self)
        if hs.windowOrigin.0 != x || hs.windowOrigin.1 != y {
            hs.windowOrigin = (x, y)
            hs.windowRects.removeAll(keepingCapacity: true)
            for (k, r) in hs.layoutRects where r.count == 4 {
                hs.windowRects[k] = [r[0] + x, r[1] + y, r[2], r[3]]
            }
        }
    }

    func hostWindowFocus(_ focused: Bool) {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        if !focused {
            _ = hostCancelActiveDrag(hs)
        }
        if hs.windowFocused != focused {
            hs.windowFocused = focused
            hostInvalidate()
        }
        if let appFocus = hs.appOnFocus {
            var tx = hostNewTx()
            if let live = hostPlayground() {
                if live.stageHears(state) {
                    _ = live.withKeyState(&state) { keyState in
                        var erased: Any = keyState
                        appFocus(&erased, focused, &tx)
                        if let updated = erased as? S {
                            keyState = updated
                        }
                    }
                }
            } else {
                var erased: Any = state
                appFocus(&erased, focused, &tx)
                if let updated = erased as? S {
                    state = updated
                }
            }
            hostLatchTx(&tx)
        }
        let rootIdx = hostAppRootIndex(hs)
        if rootIdx < hs.lastNodes.count, let onWinFocus = hs.lastNodes[rootIdx].extras.onWindowFocus {
            var tx = hostNewTx()
            hostWithStates { states in
                onWinFocus(states, focused, &tx)
            }
            hostLatchTx(&tx)
            hs.needsCommit = true
        }
    }

    func hostPresented(_ key: String) -> RuneMotion.Presented? {
        let hs = windowHostState(for: self)
        if let entry = hs.lastNodes.first(where: { $0.key == key || $0.path == key }) {
            return scene.presented(entry.nodeId)
        }
        return nil
    }

    func hostElements() -> [ElementInfo] {
        let hs = windowHostState(for: self)
        let att = hostAttachment(for: self)
        hostDrainUnlatchedPlayground(hs)
        if hs.firstCommit || hs.needsCommit || att.dirtyFromHost || (hostPlayground()?.hasPending() ?? false) {
            hostCommitTree(hs)
            hs.needsCommit = false
            att.dirtyFromHost = false
            hostRefreshPresentedElements(hs)
        }
        return hs.lastElements
    }

    func hostFind(_ keyOrPath: String) -> ElementInfo? {
        let all = hostElements()
        return all.first(where: { info in
            !info.exiting && (info.key == keyOrPath || info.path == keyOrPath || info.path.hasSuffix("/\(keyOrPath)"))
        })
    }

    @discardableResult
    func hostClick(_ keyOrPath: String) -> Bool {
        guard let info = hostFind(keyOrPath), info.rect.count >= 4 else { return false }
        let cx = info.rect[0] + info.rect[2] * 0.5
        let cy = info.rect[1] + info.rect[3] * 0.5
        return hostClickAt(cx, cy)
    }

    @discardableResult
    func hostClickAt(_ x: Float, _ y: Float, button: PointerButton = .primary) -> Bool {
        _ = hostPointerDown(x, y, button: button)
        return hostPointerUp(x, y, button: button)
    }

    @discardableResult
    func hostDoubleClick(_ keyOrPath: String) -> Bool {
        guard let info = hostFind(keyOrPath), info.rect.count >= 4 else { return false }
        let cx = info.rect[0] + info.rect[2] * 0.5
        let cy = info.rect[1] + info.rect[3] * 0.5
        return hostDoubleClickAt(cx, cy)
    }

    @discardableResult
    func hostDoubleClickAt(_ x: Float, _ y: Float) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        _ = hostPointerDown(x, y, button: .primary, clicks: 1)
        _ = hostPointerUp(x, y, button: .primary)
        hostFlushPendingBeforeInput(hs)
        _ = hostPointerDown(x, y, button: .primary, clicks: 2)
        return hostPointerUp(x, y, button: .primary)
    }

    func hostDragRegions() -> [[Float]] {
        windowHostState(for: self).dragRegions
    }

    func hostEffectSlots() -> [(UInt32, [Float])] {
        windowHostState(for: self).effectSlots
    }

    func hostCursor() -> Cursor {
        windowHostState(for: self).currentCursor
    }

    func hostHelpTooltip() -> (String, [Float])? {
        windowHostState(for: self).currentHelp
    }

    func hostPointer() -> (Float, Float)? {
        windowHostState(for: self).pointerPos
    }

    func hostPointerCaptured() -> Bool {
        windowHostState(for: self).pointerButtonHeld != nil
    }

    func hostElementAt(_ x: Float, _ y: Float) -> ElementInfo? {
        let hs = windowHostState(for: self)
        _ = hostElements()
        for idx in hs.lastNodes.indices.reversed() {
            let entry = hs.lastNodes[idx]
            guard !entry.inert else { continue }
            if hostHitContains(entry, x, y), idx < hs.lastElements.count {
                return hs.lastElements[idx]
            }
        }
        return nil
    }

    func hostDropHovered() -> String? {
        let hs = windowHostState(for: self)
        guard !hs.lastHoveredFiles.isEmpty else { return nil }
        let rootIdx = hostAppRootIndex(hs)
        guard rootIdx < hs.lastNodes.count else { return nil }
        return hs.lastNodes[rootIdx].path
    }

    private func hostPresentedRect(_ entry: HostNodeEntry) -> RuneMotion.Rect {
        if let pres = scene.presented(entry.nodeId) {
            return hostDrawnRect(pres, scrollShift: entry.scrollShift)
        }
        return entry.worldRect
    }

    private func hostHitContains(_ entry: HostNodeEntry, _ x: Float, _ y: Float) -> Bool {
        let rect = hostPresentedRect(entry)
        guard x >= rect.x && x <= rect.x + rect.w && y >= rect.y && y <= rect.y + rect.h else {
            return false
        }
        if let clip = entry.clipRect, clip.count == 4 {
            guard x >= clip[0] && x <= clip[2] && y >= clip[1] && y <= clip[3] else {
                return false
            }
        }
        return true
    }

    func hostHitInteractive(_ x: Float, _ y: Float) -> Bool {
        let hs = windowHostState(for: self)
        for entry in hs.lastNodes.reversed() where !entry.inert {
            if hostHitContains(entry, x, y) {
                if entry.hasPressHandler
                    || entry.onDrag != nil
                    || entry.onHover != nil
                    || entry.windowDrag
                    || entry.focusable
                    || entry.fill.a > 0.0
                    || entry.border.a > 0.0
                    || entry.textSpec != nil
                    || entry.pixels != nil
                {
                    return true
                }
            }
        }
        return false
    }

    func hostTitlebarDoubleClick(_ x: Float, _ y: Float, bandHeight: Float) -> TitlebarAction {
        guard y >= 0.0 && y <= bandHeight else { return .none }
        let hs = windowHostState(for: self)
        for entry in hs.lastNodes.reversed() where !entry.inert {
            if hostHitContains(entry, x, y) {
                if entry.hasPressHandler || entry.onDrag != nil || entry.focusable {
                    return .none
                }
            }
        }
        return .zoom
    }

    // MARK: - Pointer, Wheel, Paste & Key Dispatch

    @discardableResult
    private func hostSyncHoverAtPoint(_ hs: RuntimeWindowHostState, _ x: Float, _ y: Float, fromPointerMove: Bool) -> Bool {
        var newHovered = Set<String>()
        var topCursor: Cursor? = nil
        var topHelp: (String, [Float])? = nil
        var helpCutSeen = false
        var hoverFollowPath: (String, String?)? = nil

        for entry in hs.lastNodes.reversed() where !entry.inert {
            if hostHitContains(entry, x, y) {
                newHovered.insert(entry.path)
                if topCursor == nil {
                    if let explicit = entry.extras.cursor {
                        topCursor = explicit
                    } else if entry.isInput {
                        topCursor = .text
                    } else if entry.hasPressHandler || entry.role == "button" || entry.role == "link" {
                        topCursor = .pointer
                    }
                }
                if fromPointerMove && hoverFollowPath == nil && entry.focusable && entry.focusFollows {
                    hoverFollowPath = (entry.path, entry.key)
                }
                if !helpCutSeen {
                    if entry.helpCut {
                        helpCutSeen = true
                    } else if topHelp == nil, let h = entry.helpText {
                        let rect = hostPresentedRect(entry)
                        topHelp = (h, [rect.x, rect.y, rect.w, rect.h])
                    }
                }
            }
        }
        hs.currentCursor = topCursor ?? .default
        hs.currentHelp = topHelp

        var changed = false
        if let (fp, fk) = hoverFollowPath {
            if hs.focusedPath != fp {
                hs.focusedPath = fp
                hs.focusedKey = fk
                hs.hoverFocus = true
                hs.needsCommit = true
                hostSyncSideFocus(hs)
                changed = true
            }
        }

        let prevHovered = hs.hoveredPaths
        hs.hoveredPaths = newHovered

        if prevHovered != newHovered {
            var tx = hostNewTx()
            var handlerRan = false
            hostWithStates { states in
                for entry in hs.lastNodes {
                    let wasIn = prevHovered.contains(entry.path)
                    let isIn = newHovered.contains(entry.path)
                    if wasIn != isIn, let onHover = entry.onHover {
                        onHover(states, isIn, &tx)
                        handlerRan = true
                    }
                }
            }
            if handlerRan {
                hostLatchTx(&tx)
                changed = true
            }
        }
        return changed
    }

    @discardableResult
    func hostPointerMove(_ x: Float, _ y: Float) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        hs.pointerPos = (x, y)
        if let down = hs.pointerDownPos {
            let dx = x - down.0
            let dy = y - down.1
            if dx * dx + dy * dy > 36.0 {
                hs.clickMovedPastSlop = true
            }
        }

        var changed = hostSyncHoverAtPoint(hs, x, y, fromPointerMove: true)

        if let dragPath = hs.activeDragNodePath,
           let down = hs.pointerDownPos,
           let entry = hs.lastNodes.first(where: { $0.path == dragPath }),
           let onDrag = entry.onDrag
        {
            let rect = hostPresentedRect(entry)
            var drag = Drag(
                phase: .move,
                x: x - rect.x,
                y: y - rect.y,
                w: rect.w,
                h: rect.h,
                startX: down.0 - rect.x,
                startY: down.1 - rect.y,
                dx: x - down.0,
                dy: y - down.1,
                data: hs.activeDragData,
                clicks: hs.activeDragClicks,
                cancelled: false
            )
            var tx = hostNewTx()
            hostWithStates { states in
                onDrag(states, &drag, &tx)
            }
            hs.activeDragData = drag.data
            hostLatchTx(&tx)
            changed = true
        }

        return changed
    }

    @discardableResult
    func hostPointerLeave() -> Bool {
        let hs = windowHostState(for: self)
        hs.pointerPos = nil
        hs.currentCursor = .default
        hs.currentHelp = nil
        let prev = hs.hoveredPaths
        hs.hoveredPaths.removeAll()
        guard !prev.isEmpty else { return false }
        var changed = false
        var tx = hostNewTx()
        hostWithStates { states in
            for entry in hs.lastNodes where prev.contains(entry.path) {
                if let onHover = entry.onHover {
                    onHover(states, false, &tx)
                    changed = true
                }
            }
        }
        if changed {
            hostLatchTx(&tx)
        }
        return changed
    }

    /// Returns `(changed, hitWindowDragRegion)`.
    @discardableResult
    func hostPointerDown(_ x: Float, _ y: Float, button: PointerButton = .primary, clicks: UInt32? = nil) -> (Bool, Bool) {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        hs.dragCancelledSuppressNextUp = false
        hs.pointerPos = (x, y)
        hs.pointerDownPos = (x, y)
        hs.pointerButtonHeld = button
        let resolvedClicks: UInt32
        if button == .primary {
            if let explicit = clicks {
                resolvedClicks = explicit
            } else {
                let dtClick = t - hs.lastClickTime
                let dx = x - hs.lastClickPos.0
                let dy = y - hs.lastClickPos.1
                if !hs.clickMovedPastSlop && dtClick >= 0.0 && dtClick <= 0.5 && (dx * dx + dy * dy) <= 36.0 {
                    resolvedClicks = hs.lastClickCount &+ 1
                } else {
                    resolvedClicks = 1
                }
            }
            hs.lastClickTime = t
            hs.lastClickPos = (x, y)
            hs.lastClickCount = resolvedClicks
            hs.activePressClicks = resolvedClicks
            hs.clickMovedPastSlop = false
            hostPlaygroundPointerDown(hs, x)
        } else {
            resolvedClicks = clicks ?? 1
            hs.activePressClicks = resolvedClicks
        }

        for entry in hs.lastNodes.reversed() where !entry.inert {
            guard hostHitContains(entry, x, y) else {
                continue
            }
            let rect = hostPresentedRect(entry)
            if button == .secondary, let onSec = entry.onSecondaryPress {
                var tx = hostNewTx()
                tx.buttonPressed = .secondary
                let ev = PointerEvent(x: x - rect.x, y: y - rect.y, windowX: x, windowY: y)
                hostWithStates { states in
                    onSec(states, ev, &tx)
                }
                hostLatchTx(&tx)
                return (true, false)
            }
            if button == .primary {
                if let onDrag = entry.onDrag {
                    hs.activeDragNodePath = entry.path
                    hs.activeDragData = 0.0
                    hs.activeDragClicks = resolvedClicks
                    var drag = Drag(
                        phase: .down,
                        x: x - rect.x,
                        y: y - rect.y,
                        w: rect.w,
                        h: rect.h,
                        startX: x - rect.x,
                        startY: y - rect.y,
                        dx: 0,
                        dy: 0,
                        data: 0,
                        clicks: resolvedClicks,
                        cancelled: false
                    )
                    var tx = hostNewTx()
                    hostWithStates { states in
                        onDrag(states, &drag, &tx)
                    }
                    hs.activeDragData = drag.data
                    hostLatchTx(&tx)
                    return (true, false)
                }
                if entry.hasPressHandler {
                    if entry.focusable {
                        hostSetFocus(entry.path, visible: false)
                    }
                    return (true, false)
                }
                if entry.focusable {
                    hostSetFocus(entry.path, visible: entry.isInput)
                    return (true, false)
                }
                if entry.windowDrag {
                    hs.pointerButtonHeld = nil
                    return (false, true)
                }
            }
        }
        if button == .primary, let idx = hostFocusedIndex(hs), hs.lastNodes[idx].isInput {
            hostSetFocus(nil, visible: false)
            return (true, false)
        }
        return (hs.needsCommit, false)
    }

    @discardableResult
    func hostCancelActiveDrag(_ hs: RuntimeWindowHostState) -> Bool {
        guard let dragPath = hs.activeDragNodePath,
              let down = hs.pointerDownPos,
              let entry = hs.lastNodes.first(where: { $0.path == dragPath }),
              let onDrag = entry.onDrag
        else {
            return false
        }
        let (x, y) = hs.pointerPos ?? down
        let rect = hostPresentedRect(entry)
        var drag = Drag(
            phase: .up,
            x: x - rect.x,
            y: y - rect.y,
            w: rect.w,
            h: rect.h,
            startX: down.0 - rect.x,
            startY: down.1 - rect.y,
            dx: x - down.0,
            dy: y - down.1,
            data: hs.activeDragData,
            clicks: hs.activeDragClicks,
            cancelled: true
        )
        var tx = hostNewTx()
        hostWithStates { states in
            onDrag(states, &drag, &tx)
        }
        hs.activeDragNodePath = nil
        hs.pointerDownPos = nil
        hs.pointerButtonHeld = nil
        hs.activeDragData = 0.0
        hs.activeDragClicks = 1
        hs.dragCancelledSuppressNextUp = true
        hs.hadInputSinceLastFrame = true
        hostLatchTx(&tx)
        return true
    }

    @discardableResult
    func hostPointerUp(_ x: Float, _ y: Float, button: PointerButton = .primary) -> Bool {
        let hs = windowHostState(for: self)
        let prevPos = hs.pointerPos
        hs.pointerPos = (x, y)
        defer {
            hs.pointerButtonHeld = nil
            hs.pointerDownPos = nil
            hs.activeDragNodePath = nil
            hs.activeDragData = 0.0
            hs.activeDragClicks = 1
        }
        if hs.dragCancelledSuppressNextUp {
            hs.dragCancelledSuppressNextUp = false
            return false
        }

        if let dragPath = hs.activeDragNodePath,
           let down = hs.pointerDownPos,
           let entry = hs.lastNodes.first(where: { $0.path == dragPath }),
           let onDrag = entry.onDrag
        {
            let rect = hostPresentedRect(entry)
            if let prevPos, (x != prevPos.0 || y != prevPos.1) {
                let ddx = x - down.0
                let ddy = y - down.1
                if ddx * ddx + ddy * ddy > 36.0 {
                    hs.clickMovedPastSlop = true
                }
                var moveDrag = Drag(
                    phase: .move,
                    x: x - rect.x,
                    y: y - rect.y,
                    w: rect.w,
                    h: rect.h,
                    startX: down.0 - rect.x,
                    startY: down.1 - rect.y,
                    dx: ddx,
                    dy: ddy,
                    data: hs.activeDragData,
                    clicks: hs.activeDragClicks,
                    cancelled: false
                )
                var moveTx = hostNewTx()
                hostWithStates { states in
                    onDrag(states, &moveDrag, &moveTx)
                }
                hs.activeDragData = moveDrag.data
                hostLatchTx(&moveTx)
            }
            var drag = Drag(
                phase: .up,
                x: x - rect.x,
                y: y - rect.y,
                w: rect.w,
                h: rect.h,
                startX: down.0 - rect.x,
                startY: down.1 - rect.y,
                dx: x - down.0,
                dy: y - down.1,
                data: hs.activeDragData,
                clicks: hs.activeDragClicks,
                cancelled: false
            )
            var tx = hostNewTx()
            let fireDouble = button == .primary && hs.activePressClicks == 2 && !hs.clickMovedPastSlop
            hostWithStates { states in
                onDrag(states, &drag, &tx)
                if fireDouble, let onDouble = entry.extras.onDoublePress {
                    onDouble(states, &tx)
                }
            }
            hs.hadInputSinceLastFrame = true
            hostLatchTx(&tx)
            return true
        }

        guard button == .primary else { return false }
        let pressClicks = hs.activePressClicks
        let movedPastSlop = hs.clickMovedPastSlop
        for entry in hs.lastNodes.reversed() where !entry.inert {
            if hostHitContains(entry, x, y) {
                if entry.focusable {
                    hostSetFocus(entry.path, visible: entry.isInput)
                }
                if pressClicks == 2 && !movedPastSlop, let onDouble = entry.extras.onDoublePress {
                    var tx = hostNewTx()
                    hostWithStates { states in
                        onDouble(states, &tx)
                    }
                    hs.hadInputSinceLastFrame = true
                    hostLatchTx(&tx)
                    return true
                }
                if let onPress = entry.onPress {
                    let note = hostInteractionNote(action: "on_press", rank: 3, path: entry.path)
                    let t0 = RuneInstant.now()
                    var tx = hostNewTx()
                    hostWithStates { states in
                        onPress(states, &tx)
                    }
                    if let note {
                        hostInteractionRan(note: note, started: t0)
                    }
                    hs.hadInputSinceLastFrame = true
                    hostLatchTx(&tx)
                    return true
                }
                if entry.focusable {
                    hs.hadInputSinceLastFrame = true
                    hs.needsCommit = true
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    func hostCancelDrag() -> Bool {
        let hs = windowHostState(for: self)
        guard let dragPath = hs.activeDragNodePath,
              let down = hs.pointerDownPos,
              let entry = hs.lastNodes.first(where: { $0.path == dragPath }),
              let onDrag = entry.onDrag
        else {
            hs.pointerButtonHeld = nil
            hs.pointerDownPos = nil
            hs.activeDragNodePath = nil
            hs.activeDragData = 0.0
            hs.activeDragClicks = 1
            return false
        }
        let pos = hs.pointerPos ?? down
        let rect = hostPresentedRect(entry)
        var drag = Drag(
            phase: .up,
            x: pos.0 - rect.x,
            y: pos.1 - rect.y,
            w: rect.w,
            h: rect.h,
            startX: down.0 - rect.x,
            startY: down.1 - rect.y,
            dx: pos.0 - down.0,
            dy: pos.1 - down.1,
            data: hs.activeDragData,
            clicks: hs.activeDragClicks,
            cancelled: true
        )
        hs.pointerButtonHeld = nil
        hs.pointerDownPos = nil
        hs.activeDragNodePath = nil
        hs.activeDragData = 0.0
        hs.activeDragClicks = 1
        var tx = hostNewTx()
        hostWithStates { states in
            onDrag(states, &drag, &tx)
        }
        hostLatchTx(&tx)
        return true
    }

    @discardableResult
    func hostWheel(_ x: Float, _ y: Float, _ dy: Float) -> Bool {
        guard dy != 0.0 else { return false }
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        hs.currentHelp = nil
        for entry in hs.lastNodes.reversed() where !entry.inert && entry.scrollSpec != nil {
            guard hostHitContains(entry, x, y) else { continue }
            let maxOff = hs.scrollMaxByPath[entry.path] ?? 0.0
            guard maxOff > 0.0 else { continue }
            let cur = hs.scrollOffsets[entry.path] ?? 0.0
            let next = min(max(cur - dy, 0.0), maxOff)
            if abs(next - cur) > 1e-4 {
                hs.scrollOffsets[entry.path] = next
                hs.needsCommit = true
                return true
            }
            return false
        }
        return false
    }

    @discardableResult
    func hostPasteText(_ text: String) -> Bool {
        hostPaste(ClipboardContent.new(text))
    }

    @discardableResult
    func hostPaste(_ content: ClipboardContent) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        let plain = content.text()
        if let idx = hostFocusedIndex(hs) {
            let entry = hs.lastNodes[idx]
            if let onPaste = entry.extras.onPaste {
                var tx = hostNewTx()
                hostWithStates { states in
                    onPaste(states, plain, &tx)
                }
                hs.hadInputSinceLastFrame = true
                hostLatchTx(&tx)
                hs.needsCommit = true
                return true
            }
            if let editAccess = entry.extras.editAccess {
                let inserted = entry.singleLineInput
                    ? plain.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
                    : plain
                var edited = false
                hostWithStates { states in
                    edited = editAccess(states) { edit in
                        edit.insert(inserted)
                    }
                }
                if edited {
                    hs.hadInputSinceLastFrame = true
                    hs.pendingInstant = true
                    hs.needsCommit = true
                    return true
                }
            }
        }
        let rootIdx = hostAppRootIndex(hs)
        if rootIdx < hs.lastNodes.count, let rootPaste = hs.lastNodes[rootIdx].extras.onPaste {
            var tx = hostNewTx()
            hostWithStates { states in
                rootPaste(states, plain, &tx)
            }
            hs.hadInputSinceLastFrame = true
            hostLatchTx(&tx)
            hs.needsCommit = true
            return true
        }
        return false
    }

    @discardableResult
    func hostKeyUp(_ event: KeyEvent) -> Bool {
        _ = event
        return false
    }

    @discardableResult
    func hostKey(_ event: KeyEvent, base: Character? = nil, isRepeat: Bool = false) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        if case .modifier = event.key, !hs.modifierKeys {
            return false
        }
        var tx = hostNewTx()
        hs.lastPhysicalKey = nil
        tx.keyRepeatFlag = isRepeat
        tx.heldMods = event.mods
        tx.keyBaseChar = base

        if event.key == .tab || event.key == .up || event.key == .down || event.key == .left || event.key == .right {
            hs.keyboardFocus = true
        }
        if (event.key == .enter || event.key == .escape) && hs.imeActive {
            return true
        }
        if event.key == .escape && !event.mods.cmd && !event.mods.ctrl && !event.mods.alt && hostCancelActiveDrag(hs) {
            return true
        }

        let focusedIdx = hostFocusedIndex(hs)
        let appFirst = (focusedIdx == nil)
        let isFocusedInput = focusedIdx.map { hs.lastNodes[$0].isInput } ?? false

        func finishHandled() -> Bool {
            hs.hadInputSinceLastFrame = true
            hostLatchTx(&tx)
            return true
        }

        // 1. `element_key`: non-input focused element and its ancestors (`keys.rs:20, 224`)
        if let startIdx = focusedIdx, !isFocusedInput {
            var cur: Int? = startIdx
            while let j = cur, j >= 0 && j < hs.lastNodes.count {
                let entry = hs.lastNodes[j]
                if entry.inert { break }
                if let handler = entry.onKey {
                    let note = hostInteractionNote(action: "key", rank: 3, path: entry.path)
                    let t0 = RuneInstant.now()
                    let handled = hostWithStates { states in
                        handler(states, event, &tx)
                    }
                    if handled {
                        if let note {
                            hostInteractionRan(note: note, started: t0)
                        }
                        return finishHandled()
                    }
                }
                cur = entry.parentElemIndex
            }
        }

        // 2. Default button on plain Enter when not in a non-submitting multi-line editor
        if event.key == .enter && !event.mods.cmd && !event.mods.ctrl && !event.mods.alt && !event.mods.shift && !isFocusedInput {
            if let defBtn = hs.lastNodes.first(where: { !$0.inert && $0.defaultButton && $0.onPress != nil }),
               let onPress = defBtn.onPress
            {
                hostWithStates { states in
                    onPress(states, &tx)
                }
                return finishHandled()
            }
        }

        // 3. `playground_nav` (`keys.rs:24`)
        if hostPlaygroundNav(hs, event, &tx) {
            return finishHandled()
        }

        let pgTyping = hostPlayground().map { $0.isTyping(state) } ?? false

        // 4. App `onKey` when `app_first && !playground_typing()` (`keys.rs:25`)
        if appFirst && !pgTyping, let rootOnKey = onKey {
            let note = hostInteractionNote(action: "key", rank: 3, path: hs.focusedKey)
            let t0 = RuneInstant.now()
            if hostAppKey(hs, rootOnKey, event, &tx) {
                if let note {
                    hostInteractionRan(note: note, started: t0)
                }
                return finishHandled()
            }
        }

        // 5. Focused input handler (`pgOnEdit` / `onSubmit` / custom input `onKey`)
        if let idx = focusedIdx, isFocusedInput {
            let entry = hs.lastNodes[idx]
            if event.key == .enter
                && !event.mods.cmd
                && !event.mods.ctrl
                && !event.mods.alt
                && !event.mods.shift,
               let onSubmit = entry.extras.onSubmit
            {
                let note = hostInteractionNote(action: "key_edit", rank: 3, path: entry.path)
                let t0 = RuneInstant.now()
                hostWithStates { states in
                    onSubmit(states, &tx)
                }
                if let note {
                    hostInteractionRan(note: note, started: t0)
                }
                return finishHandled()
            }
            if let handler = entry.onKey {
                let note = hostInteractionNote(action: "key_edit", rank: 3, path: entry.path)
                let t0 = RuneInstant.now()
                let handled = hostWithStates { states in
                    handler(states, event, &tx)
                }
                if handled {
                    if let note {
                        hostInteractionRan(note: note, started: t0)
                    }
                    return finishHandled()
                }
            }
        }

        // 6. Focus key: Enter/Space presses focused button, Tab traverses focusable controls
        if let idx = focusedIdx, !isFocusedInput {
            let entry = hs.lastNodes[idx]
            let plainActivate = (event.key == .enter || event.key == .text(" "))
                && !event.mods.cmd && !event.mods.ctrl && !event.mods.alt
            if plainActivate, let onPress = entry.onPress {
                hostWithStates { states in
                    onPress(states, &tx)
                }
                return finishHandled()
            }
        }

        if event.key == .tab && !event.mods.cmd && !event.mods.ctrl && !event.mods.alt {
            let candidates = hs.lastNodes.filter { elem in
                guard elem.focusable && !elem.inert else { return false }
                if !hs.tabVisitsControls && !elem.isInput { return false }
                if let live = hostPlayground(), live.isOpen() {
                    if let elemIdx = hs.lastNodes.firstIndex(where: { $0.path == elem.path }) {
                        return hostNodeUnder(hs, elemIdx, playgroundIsStage)
                    }
                    return false
                }
                return true
            }
            if let first = candidates.first {
                let curPath = hs.focusedPath
                if let curPath, let curIdx = candidates.firstIndex(where: { $0.path == curPath }) {
                    let step = event.mods.shift ? -1 : 1
                    let nextIdx = (curIdx + step + candidates.count) % candidates.count
                    hostSetFocus(candidates[nextIdx].path, visible: true)
                } else {
                    let chosen = event.mods.shift ? candidates.last! : first
                    hostSetFocus(chosen.path, visible: true)
                }
                return true
            }
        }

        // 7. App `onKey` when `!app_first && !playground_typing()` (`keys.rs:79`)
        if !appFirst && !pgTyping, let rootOnKey = onKey {
            let note = hostInteractionNote(action: "key", rank: 3, path: hs.focusedKey)
            let t0 = RuneInstant.now()
            if hostAppKey(hs, rootOnKey, event, &tx) {
                if let note {
                    hostInteractionRan(note: note, started: t0)
                }
                return finishHandled()
            }
        }

        // 8. `playground_key` (`keys.rs:88`)
        if hostPlaygroundKey(hs, event, &tx) {
            return finishHandled()
        }

        return false
    }

    @discardableResult
    func hostDragHover(_ paths: [String]) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        let wasEmpty = hs.lastHoveredFiles.isEmpty
        hs.lastHoveredFiles = paths
        let rootIdx = hostAppRootIndex(hs)
        if wasEmpty, rootIdx < hs.lastNodes.count, let onDropHover = hs.lastNodes[rootIdx].extras.onDropHover {
            var tx = hostNewTx()
            hostWithStates { states in
                onDropHover(states, true, &tx)
            }
            hostLatchTx(&tx)
            hs.needsCommit = true
            return true
        }
        return false
    }

    @discardableResult
    func hostDragLeave() -> Bool {
        let hs = windowHostState(for: self)
        let had = !hs.lastHoveredFiles.isEmpty
        hs.lastHoveredFiles.removeAll()
        let rootIdx = hostAppRootIndex(hs)
        if had, rootIdx < hs.lastNodes.count, let onDropHover = hs.lastNodes[rootIdx].extras.onDropHover {
            var tx = hostNewTx()
            hostWithStates { states in
                onDropHover(states, false, &tx)
            }
            hostLatchTx(&tx)
            hs.needsCommit = true
        }
        return had
    }

    @discardableResult
    func hostFileDrop(_ paths: [String]) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        let hadHover = !hs.lastHoveredFiles.isEmpty
        hs.lastHoveredFiles.removeAll()
        hs.lastDroppedFiles = paths
        let rootIdx = hostAppRootIndex(hs)
        if rootIdx < hs.lastNodes.count {
            var tx = hostNewTx()
            var invoked = false
            hostWithStates { states in
                if hadHover, let onDropHover = hs.lastNodes[rootIdx].extras.onDropHover {
                    onDropHover(states, false, &tx)
                    invoked = true
                }
                if !paths.isEmpty, let onDropFiles = hs.lastNodes[rootIdx].extras.onDropFiles {
                    onDropFiles(states, paths, &tx)
                    invoked = true
                }
            }
            if invoked {
                hostLatchTx(&tx)
                hs.needsCommit = true
            }
        }
        return !paths.isEmpty
    }

    @discardableResult
    func hostIme(_ ime: Ime) -> Bool {
        let hs = windowHostState(for: self)
        hostFlushPendingBeforeInput(hs)
        let focusedIdx = hostFocusedIndex(hs)
        let focusedPath = focusedIdx.map { hs.lastNodes[$0].path } ?? hs.focusedPath ?? hs.focusedKey
        let note = hostInteractionNote(action: "key_edit", rank: 3, path: focusedPath)
        let t0 = RuneInstant.now()

        if focusedIdx == nil || hs.lastNodes[focusedIdx!].isInput == false {
            if let appIme = hs.appOnIme {
                var tx = hostNewTx()
                var handled = false
                if let live = hostPlayground() {
                    if live.stageHears(state) {
                        handled = live.withKeyState(&state) { keyState in
                            var erased: Any = keyState
                            let r = appIme(&erased, ime, &tx)
                            if let updated = erased as? S {
                                keyState = updated
                            }
                            return r
                        } ?? false
                    }
                } else {
                    var erased: Any = state
                    handled = appIme(&erased, ime, &tx)
                    if let updated = erased as? S {
                        state = updated
                    }
                }
                switch ime {
                case .preedit(let text, _): hs.imeActive = !text.isEmpty
                case .commit, .disabled: hs.imeActive = false
                case .enabled: hs.imeActive = true
                }
                if handled {
                    hostLatchTx(&tx)
                    hs.needsCommit = true
                }
                return handled
            }
        }

        switch ime {
        case .commit(let text):
            hs.imeActive = false
            if let idx = focusedIdx, let editAccess = hs.lastNodes[idx].extras.editAccess {
                hostWithStates { states in
                    _ = editAccess(states) { edit in
                        edit.insert(text)
                    }
                }
            }
            if let note {
                hostInteractionRan(note: note, started: t0)
            }
            hs.hadInputSinceLastFrame = true
            hs.pendingInstant = true
            hs.needsCommit = true
            return true
        case .preedit(let text, _):
            hs.imeActive = !text.isEmpty
            if let note {
                hostInteractionRan(note: note, started: t0)
            }
            hs.hadInputSinceLastFrame = true
            hs.needsCommit = true
            return true
        case .enabled:
            hs.imeActive = true
            return false
        case .disabled:
            hs.imeActive = false
            return false
        }
    }

    // MARK: - Full Frame & Settle Pipeline

    func hostSettleAll() {
        let hs = windowHostState(for: self)
        hs.pendingSettle = true
        hs.needsCommit = true
    }

    /// Invoked via `self.poll` when Spine's `Runtime.frame(_:)` is called directly in tests (`clock` and `t` were already advanced by `dt`).
    private func hostStepFromSpineFrame() {
        let hs = windowHostState(for: self)
        let att = hostAttachment(for: self)
        hs.hadInputSinceLastFrame = false

        hostRecorderHeadlessFrame(clock)
        _ = hostFlushFileDialogAnswers()
        flushMemoryClipboard(self)
        hostDrainUnlatchedPlayground(hs)
        scene.setPixelScale(env.scale)
        scene.setReducedMotion(reducedMotion)

        while let earliest = hs.timerDeadlines.first, earliest <= clock + 1e-9 {
            hs.timerDeadlines.removeFirst()
            hs.needsCommit = true
        }

        _ = hostRunPollHooks()
        let tookSpineLiveWake: Bool
        if hs.liveVisible {
            tookSpineLiveWake = hs.liveWake.pending
            hs.liveWake.pending = false
        } else {
            tookSpineLiveWake = false
        }

        // Always commit in Spine `Runtime.frame` so direct `rt.update` state mutations are reflected in `hostElements()`, while unchanged tracks stay untouched.
        hostCommitTree(hs)
        hs.needsCommit = false
        att.dirtyFromHost = false
        hs.perfWatch.cause = 0

        scene.setTime(t)
        if hs.pendingSettle {
            hs.pendingSettle = false
            for _ in 0..<240 {
                t += (1.0 / 60.0) * Double(max(timeScale, 1.0))
                scene.setTime(t)
                let out = scene.frame()
                if !out.animating { break }
            }
            if scene.frameAt(t).animating {
                t += 10.0 * Double(max(timeScale, 1.0))
                scene.setTime(t)
            }
        }
        let liveAnimating = hostSampleLiveBindings(hs, pending: tookSpineLiveWake)
        let sceneOut = scene.frameAt(t)
        hostRefreshPresentedElements(hs)
        let (instances, layers) = hs.liveVisible ? hostEmitInstances(hs) : ([], [])
        hs.lastStats = FrameStats(
            instances: instances.count,
            layers: layers.count,
            animating: hs.liveVisible && (sceneOut.animating || liveAnimating)
        )
        if hs.liveVisible {
            images.endFrame()
        }
    }

    @discardableResult
    func hostFrame(_ dt: Double) -> ([Instance], [LayerSpec], FrameStats) {
        let hs = windowHostState(for: self)
        let att = hostAttachment(for: self)
        let hadInput = hs.hadInputSinceLastFrame
        hs.hadInputSinceLastFrame = false
        let liveWoke = hs.liveVisible && hs.liveWake.pending

        hostInteractionFrameBegins(queued: hadInput)

        // 1. Advance logical clock and sync scene configuration at current `t` before commit
        clock += dt
        hostRecorderHeadlessFrame(clock)
        _ = hostFlushFileDialogAnswers()
        flushMemoryClipboard(self)
        hostDrainUnlatchedPlayground(hs)
        scene.setPixelScale(env.scale)
        scene.setReducedMotion(reducedMotion)
        scene.setTime(t)

        // 2. Drain expired `wakeAfter` timers on `clock`
        var timerFired = false
        while let earliest = hs.timerDeadlines.first, earliest <= clock + 1e-9 {
            hs.timerDeadlines.removeFirst()
            timerFired = true
        }
        if timerFired {
            hs.needsCommit = true
            hs.perfWatch.cause |= ToolingCommitWhy.POLL
        }

        hs.perfIdle.begins(quiet: !hadInput, timer: timerFired, live: liveWoke)

        // 3. Poll app hook & playground stage poll
        _ = hostRunPollHooks()

        // Clear coalesced live-wake pending flag before sampling (hidden hosts keep the wake for show)
        let tookLiveWake: Bool
        if hs.liveVisible {
            tookLiveWake = hs.liveWake.pending
            hs.liveWake.pending = false
        } else {
            tookLiveWake = false
        }

        // 4. Commit view -> Taffy layout -> `RuneMotion.Scene` if dirty (before stepping `dt`)
        let didCommit = hs.firstCommit || hs.needsCommit || att.dirtyFromHost || (hostPlayground()?.hasPending() ?? false)
        if didCommit {
            if hs.firstCommit {
                hs.perfWatch.cause |= ToolingCommitWhy.LAYOUT
            }
            hostCommitTree(hs)
            hs.needsCommit = false
            att.dirtyFromHost = false
        }
        hs.perfWatch.cause = 0

        if !hs.liveVisible && !didCommit {
            t += dt * Double(timeScale)
            scene.setTime(t)
            let hiddenStats = FrameStats(instances: 0, layers: 0, animating: false)
            hs.lastStats = hiddenStats
            hs.animSources = 0
            hs.perfIdle.ends(
                clock: clock,
                animating: false,
                drawn: PerfDrawn(instances: [], key: 0, opaque: false),
                name: { att.windowTitle }
            )
            hostInteractionBuilt()
            return ([], [], hiddenStats)
        }

        // 5. Sample `Live` / `Tween` / `LiveText` / `Pixels` bindings at start-of-frame `t` before stepping `dt`
        let liveAnimating = hostSampleLiveBindings(hs, pending: tookLiveWake)

        // 6. Advance animation time `t` by this frame's `dt`
        t += dt * Double(timeScale)
        scene.setTime(t)

        // 7. Settle if requested by `tx.settle()` or `hostSettleAll()`
        if hs.pendingSettle {
            hs.pendingSettle = false
            for _ in 0..<240 {
                t += (1.0 / 60.0) * Double(max(timeScale, 1.0))
                scene.setTime(t)
                let out = scene.frame()
                if !out.animating { break }
            }
            if scene.frameAt(t).animating {
                t += 10.0 * Double(max(timeScale, 1.0))
                scene.setTime(t)
            }
        }

        // 8. Step `RuneMotion.Scene` and refresh `lastElements` presented rects
        if scene.tracing() {
            for i in 0..<min(hs.lastElements.count, hs.lastNodes.count) {
                let nid = hs.lastNodes[i].nodeId
                scene.traceName(nid, hs.lastElements[i].traceName)
                scene.traceNamespace(nid, hs.lastElements[i].traceNamespace)
            }
        }
        let sceneOut = scene.frameAt(t)
        hostRefreshPresentedElements(hs)
        if let (px, py) = hs.pointerPos, hs.activeDragNodePath == nil {
            _ = hostSyncHoverAtPoint(hs, px, py, fromPointerMove: false)
        }

        // 9. Emit `Instance`s and `LayerSpec`s
        let (instances, layers) = hs.liveVisible ? hostEmitInstances(hs) : ([], [])
        var sources: UInt16 = 0
        if hs.liveVisible {
            if sceneOut.animating { sources |= 1 } // AnimSource.TRACKS
            if liveAnimating { sources |= 256 } // AnimSource.LIVE
        }
        hs.animSources = sources
        let stats = FrameStats(
            instances: instances.count,
            layers: layers.count,
            animating: hs.liveVisible && (sceneOut.animating || liveAnimating)
        )
        hs.lastStats = stats
        var instHash: UInt64 = 0xcbf2_9ce4_8422_2325
        for inst in instances {
            for v in inst.rect + inst.fill + inst.uv {
                instHash ^= UInt64(v.bitPattern)
                instHash = instHash &* 0x0000_0100_0000_01b3
            }
        }
        let instBytes = withUnsafeBytes(of: instHash) { Array($0) }
        hs.perfIdle.ends(
            clock: clock,
            animating: stats.animating,
            drawn: PerfDrawn(instances: instBytes, key: UInt64(instances.count), opaque: false),
            name: { att.windowTitle }
        )
        hostInteractionBuilt()
        if hs.liveVisible {
            images.endFrame()
        }
        return (instances, layers, stats)
    }

    private func hostRefreshPresentedElements(_ hs: RuntimeWindowHostState) {
        let mountedCount = hs.lastNodes.count
        for i in 0..<min(hs.lastElements.count, mountedCount) {
            if let pres = scene.presented(hs.lastNodes[i].nodeId) {
                let r = hostDrawnRect(pres, scrollShift: hs.lastNodes[i].scrollShift)
                hs.lastElements[i].rect = [r.x, r.y, r.w, r.h]
                hs.lastElements[i].visible = visibleWithinClip(r, hs.lastNodes[i].clipRect)
                hs.lastElements[i].opacity = pres.opacity
                hs.lastElements[i].radius = pres.radius.c0
                let nodeFill = hs.lastNodes[i].fill
                let pf = Color(pres.fill.r, pres.fill.g, pres.fill.b, pres.fill.a)
                if abs(pf.r - nodeFill.r) < 1e-5
                    && abs(pf.g - nodeFill.g) < 1e-5
                    && abs(pf.b - nodeFill.b) < 1e-5
                    && abs(pf.a - nodeFill.a) < 1e-5
                {
                    hs.lastElements[i].fill = nodeFill
                } else {
                    hs.lastElements[i].fill = pf
                }
                hs.lastElements[i].scale = pres.transform.scale.x
                hs.lastElements[i].blur = pres.blur
                let tgt = hs.lastElements[i].target
                if tgt.count >= 4 {
                    let moving = zip([r.x, r.y, r.w, r.h], tgt).contains { abs($0 - $1) > 0.25 }
                    hs.lastElements[i].moving = moving
                    if moving {
                        var intent: UInt32 = 0
                        if abs(r.x - tgt[0]) > 0.25 || abs(r.y - tgt[1]) > 0.25 {
                            intent |= Intent.position
                        }
                        if abs(r.w - tgt[2]) > 0.25 || abs(r.h - tgt[3]) > 0.25 {
                            intent |= Intent.size
                        }
                        hs.lastElements[i].liveIntent = intent
                    } else {
                        hs.lastElements[i].liveIntent = 0
                    }
                }
            }
        }

        // Update or prune exiting nodes at tail of `lastElements`
        if hs.lastElements.count > mountedCount {
            hs.lastElements.removeSubrange(mountedCount..<hs.lastElements.count)
        }
        for (ident, (nid, baseInfo)) in Array(hs.exitingNodes) {
            if let pres = scene.presented(nid), scene.contains(nid) {
                var ex = baseInfo
                let r = pres.rect
                ex.exiting = true
                ex.parent = nil
                ex.rect = [r.x, r.y, r.w, r.h]
                ex.visible = [r.x, r.y, r.w, r.h]
                ex.opacity = pres.opacity
                ex.scale = pres.transform.scale.x
                ex.blur = pres.blur
                hs.lastElements.append(ex)
            } else {
                hs.exitingNodes.removeValue(forKey: ident)
            }
        }
    }

    private func hostCommitTree(_ hs: RuntimeWindowHostState, settleDepth: Int = 0) {
        hs.insideHostCommit = true
        defer { hs.insideHostCommit = false }
        let wasFirstCommit = hs.firstCommit
        let savedPendingInstant = hs.pendingInstant
        let savedPendingSpring = hs.pendingSpring
        let savedPendingCurve = hs.pendingCurve
        let prevLayoutRects = hs.layoutRects
        let prevWindowRects = hs.windowRects
        if settleDepth == 0 {
            hostApplyPlayground(hs)
            bumpCommitGeneration()
            hs.commitsCount &+= 1
            hs.perfWatch.interaction.committed(hs.perfWatch.cause != 0 ? hs.perfWatch.cause : ToolingCommitWhy.DIRTY)
        }
        let firstViewTimer = PerfFirstView.start(hs.firstCommit && settleDepth == 0)
        memo.layoutRects = hs.layoutRects
        memo.windowRects = hs.windowRects
        let finishMemo = enterMemoScope(memo, env: env, reducedMotion: reducedMotion, srgbBlend: srgbBlend)
        let cx = Cx<S>(
            env: env,
            titlebarInset: hs.titlebarInset,
            systemAccent: hs.systemAccent,
            systemReducedMotion: hs.systemReducedMotion,
            reducedMotion: hs.systemReducedMotion,
            timeScale: timeScale,
            caret: nil,
            layoutRects: hs.layoutRects,
            windowRects: hs.windowRects
        )
        let viewT0 = interactionActive() ? RuneInstant.now() : nil
        let livePg = hostPlayground()
        let appSnapshot = hostReadState(hs)
        var root = withBlend(srgbBlend) {
            perfTimed("view") {
                if let livePg {
                    return livePg.view(appSnapshot, self.view, cx, viewport)
                } else {
                    return playgroundCall(self.view, appSnapshot, cx)
                }
            }
        }
        if let vt0 = viewT0 {
            interactionAddPhase(.view, max(vt0.elapsedSeconds() * 1000.0, 0.001))
        }
        _ = finishMemo()
        firstViewTimer.end()

        reducedMotion = cx.isReducedMotion()
        timeScale = cx.timeScaleValue
        scene.setReducedMotion(reducedMotion)

        // Build Taffy tree
        var taffy = TaffyTree<TaffyNodePayload>()
        taffy.disableRounding()
        let rootNodeId = buildTaffySubtree(&root, parentPath: "", parentIdentity: "", indexInParent: 0, tree: &taffy)
        if let rootNodeId {
            var rootStyle: Style<String>
            if case .success(let s) = taffy.style(rootNodeId) {
                rootStyle = s
            } else {
                rootStyle = Style<String>()
            }
            if rootStyle.size.width == .auto() {
                rootStyle.size.width = Dimension.length(viewport.0)
            }
            if !hs.fitContentHeight && rootStyle.size.height == .auto() {
                rootStyle.size.height = Dimension.length(viewport.1)
            }
            _ = taffy.setStyle(rootNodeId, rootStyle)
            let avail = Size<AvailableSpace>(
                width: .definite(viewport.0),
                height: hs.fitContentHeight ? .maxContent : .definite(viewport.1)
            )
            _ = taffy.computeLayoutWithMeasure(rootNodeId, avail) { knownDims, availSpace, _, payload, _ in
                guard let payload else {
                    return Size(width: knownDims.width ?? 0.0, height: knownDims.height ?? 0.0)
                }
                if let inputSpec = payload.el.input {
                    let displayStr = inputSpec.edit.text.isEmpty ? inputSpec.placeholder : inputSpec.edit.text
                    let style = payload.el.textSpec?.value.style ?? tok.type_.BODY
                    let wrapW: Float?
                    if inputSpec.singleLine {
                        wrapW = nil
                    } else if let kw = knownDims.width {
                        wrapW = kw
                    } else if case .definite(let aw) = availSpace.width {
                        wrapW = aw
                    } else {
                        wrapW = nil
                    }
                    let (mw, mh) = Rune.measure(displayStr, [], style, wrapW)
                    return Size(
                        width: knownDims.width ?? mw,
                        height: knownDims.height ?? max(mh, style.linePx())
                    )
                }
                guard let textSpec = payload.el.textSpec?.value else {
                    return Size(
                        width: knownDims.width ?? 0.0,
                        height: knownDims.height ?? 0.0
                    )
                }
                let rawContent = textSpec.live?.get() ?? textSpec.content
                let wrapW: Float?
                if !textSpec.wrap || textSpec.truncate {
                    wrapW = nil
                } else if let kw = knownDims.width {
                    wrapW = kw
                } else if case .definite(let maxW) = availSpace.width {
                    wrapW = maxW
                } else {
                    wrapW = nil
                }
                let (mw, mh) = Rune.measure(rawContent, textSpec.spans, textSpec.style, wrapW)
                return Size(
                    width: knownDims.width ?? mw,
                    height: knownDims.height ?? mh
                )
            }
        }

        var prevByNodeId: [NodeId: HostNodeEntry] = [:]
        var prevInfoByIdentity: [String: ElementInfo] = [:]
        prevByNodeId.reserveCapacity(hs.lastNodes.count)
        for (i, existing) in hs.lastNodes.enumerated() {
            prevByNodeId[existing.nodeId] = existing
            if i < hs.lastElements.count {
                prevInfoByIdentity[existing.identity] = hs.lastElements[i]
            }
        }

        var newEntries: [HostNodeEntry] = []
        var newElements: [ElementInfo] = []
        var seenIdentities = Set<String>()
        var newLayoutRects: [String: [Float]] = [:]
        var newDragRegions: [[Float]] = []
        var newEffectSlots: [(UInt32, [Float])] = []

        if let rootNodeId {
            collectLaidOutNodes(
                rootTaffyId: rootNodeId,
                tree: &taffy,
                hs: hs,
                prevByNodeId: prevByNodeId,
                seenIdentities: &seenIdentities,
                entries: &newEntries,
                elements: &newElements,
                layoutRects: &newLayoutRects,
                dragRegions: &newDragRegions,
                effectSlots: &newEffectSlots
            )
        }

        // Apply queued scroll requests (`scrollTo`, `scrollBottom`, `scrollOffset`)
        applyQueuedScrollOperations(
            hs: hs,
            entries: &newEntries,
            elements: &newElements,
            layoutRects: &newLayoutRects
        )

        // Sync requested focus if `focusedKey` or `focusedPath` resolved to a newly mounted node
        if let fk = hs.focusedKey, hs.focusedPath == nil || !newEntries.contains(where: { $0.path == hs.focusedPath }) {
            if let found = newEntries.first(where: { !$0.inert && ($0.key == fk || $0.path == fk) }) {
                hs.focusedPath = found.path
                hs.focusedKey = found.key
            } else {
                hs.focusedPath = nil
                hs.focusedKey = nil
            }
        } else if let fp = hs.focusedPath, !newEntries.contains(where: { $0.path == fp && !$0.inert }) {
            if let fk = hs.focusedKey, let found = newEntries.first(where: { !$0.inert && $0.key == fk }) {
                hs.focusedPath = found.path
            } else {
                hs.focusedPath = nil
                hs.focusedKey = nil
            }
        }
        for i in newElements.indices {
            newElements[i].focused = (newEntries[i].path == hs.focusedPath)
                || (newEntries[i].key != nil && newEntries[i].key == hs.focusedKey)
        }

        // Remove unmounted scene nodes (tracking animated exits when non-instant)
        let txInstant = hs.pendingInstant || reducedMotion
        for (ident, nid) in Array(hs.mountedNodeIds) where !seenIdentities.contains(ident) {
            if txInstant {
                scene.unmount(nid)
                hs.exitingNodes.removeValue(forKey: ident)
            } else {
                scene.remove(nid)
                if scene.contains(nid), let prevInfo = prevInfoByIdentity[ident] {
                    var ex = prevInfo
                    ex.exiting = true
                    ex.parent = nil
                    hs.exitingNodes[ident] = (nid, ex)
                }
            }
            hs.mountedNodeIds.removeValue(forKey: ident)
        }

        if hs.fitContentHeight, let rootElem = newElements.first, rootElem.target.count >= 4 {
            let naturalH = rootElem.target[3]
            let clamped = clampWindowSize((viewport.0, naturalH), hs.fitLimits.0, hs.fitLimits.1)
            if hs.firstCommit {
                viewport = (viewport.0, clamped.1)
                hs.fitTargetHeight = clamped.1
            } else if abs(clamped.1 - (hs.fitTargetHeight ?? viewport.1)) > 0.25 {
                hs.fitTargetHeight = clamped.1
                let req = WindowFrameRequest(
                    size: (viewport.0, clamped.1),
                    animate: !txInstant,
                    spring: txInstant ? nil : (hs.pendingSpring ?? .smooth),
                    center: false
                )
                hs.pendingWindowFrameRequest = (hs.pendingWindowFrameRequest ?? WindowFrameRequest()).merge(req)
                hs.fitHeld = true
            }
        }

        hs.lastNodes = newEntries
        hs.lastElements = newElements
        hostSubscribeLive(hs)
        hostFindAppRoot(hs)
        hostSyncRegion(hs)
        hostSyncSideFocus(hs)

        // Append currently exiting nodes to `lastElements`
        for (ident, (nid, baseInfo)) in Array(hs.exitingNodes) {
            if scene.contains(nid) {
                var ex = baseInfo
                if let pres = scene.presented(nid) {
                    let r = pres.rect
                    ex.rect = [r.x, r.y, r.w, r.h]
                    ex.visible = [r.x, r.y, r.w, r.h]
                    ex.opacity = pres.opacity
                }
                hs.lastElements.append(ex)
            } else {
                hs.exitingNodes.removeValue(forKey: ident)
            }
        }

        hs.layoutRects = newLayoutRects
        hs.windowRects.removeAll(keepingCapacity: true)
        for (k, r) in newLayoutRects where r.count == 4 {
            hs.windowRects[k] = [r[0] + hs.windowOrigin.0, r[1] + hs.windowOrigin.1, r[2], r[3]]
        }
        hs.dragRegions = newDragRegions
        hs.effectSlots = newEffectSlots

        if settleDepth < 4 && !cx.layoutReadKeys.isEmpty {
            let layoutMoved = cx.layoutReadKeys.contains { key in
                if key.hasPrefix("@win:") {
                    let sub = String(key.dropFirst(5))
                    return (prevWindowRects[sub] ?? prevLayoutRects[sub]) != (hs.windowRects[sub] ?? hs.layoutRects[sub])
                }
                return prevLayoutRects[key] != hs.layoutRects[key]
            }
            if layoutMoved {
                hs.firstCommit = wasFirstCommit
                hs.pendingInstant = savedPendingInstant
                hs.pendingSpring = savedPendingSpring
                hs.pendingCurve = savedPendingCurve
                hostCommitTree(hs, settleDepth: settleDepth + 1)
                return
            }
        }

        hs.firstCommit = false
        hs.pendingInstant = false
        hs.pendingSpring = nil
        hs.pendingCurve = nil
        hs.pendingRelayout = false
    }

    private func buildTaffySubtree(
        _ rootEl: inout El,
        parentPath: String,
        parentIdentity: String,
        indexInParent: Int,
        tree: inout TaffyTree<TaffyNodePayload>
    ) -> Taffy.NodeId? {
        func makeFrame(
            _ el: inout El,
            pPath: String,
            pIdentity: String,
            idx: Int
        ) -> (el: El, path: String, identity: String, nodeStyle: Style<String>, nextChild: Int, childIds: [Taffy.NodeId]) {
            el.expandMemo()
            let seg = el.key ?? "#\(idx)"
            let path = pPath.isEmpty ? seg : "\(pPath)/\(seg)"
            let identity = pIdentity.isEmpty ? (el.key ?? "root") : "\(pIdentity)/\(seg)"
            var nodeStyle = el.style
            if el.scrollSpec != nil {
                nodeStyle.overflow.y = .scroll
            }
            var childIds: [Taffy.NodeId] = []
            childIds.reserveCapacity(el.children.count)
            return (el: el, path: path, identity: identity, nodeStyle: nodeStyle, nextChild: 0, childIds: childIds)
        }

        var stack = [makeFrame(&rootEl, pPath: parentPath, pIdentity: parentIdentity, idx: indexInParent)]
        while !stack.isEmpty {
            let top = stack.count - 1
            if stack[top].nextChild < stack[top].el.children.count {
                let ci = stack[top].nextChild
                stack[top].nextChild += 1
                let pPath = stack[top].path
                let pIdentity = stack[top].identity
                var childEl = stack[top].el.children[ci]
                if stack[top].el.inertFlag {
                    childEl.inertFlag = true
                }
                let childFrame = makeFrame(&childEl, pPath: pPath, pIdentity: pIdentity, idx: ci)
                stack[top].el.children[ci] = childEl
                stack.append(childFrame)
            } else {
                var finished = stack.removeLast()
                finished.el.children.removeAll()
                let payload = TaffyNodePayload(el: finished.el, path: finished.path, identity: finished.identity)
                let builtId: Taffy.NodeId?
                if finished.childIds.isEmpty {
                    if case .success(let nid) = tree.newLeafWithContext(finished.nodeStyle, payload) {
                        builtId = nid
                    } else {
                        builtId = nil
                    }
                } else {
                    if case .success(let nid) = tree.newWithChildren(finished.nodeStyle, finished.childIds) {
                        _ = tree.setNodeContext(nid, payload)
                        builtId = nid
                    } else {
                        builtId = nil
                    }
                }
                if stack.isEmpty {
                    return builtId
                }
                if let cid = builtId {
                    stack[stack.count - 1].childIds.append(cid)
                }
            }
        }
        return nil
    }

    private func collectLaidOutNodes(
        rootTaffyId: Taffy.NodeId,
        tree: inout TaffyTree<TaffyNodePayload>,
        hs: RuntimeWindowHostState,
        prevByNodeId: [NodeId: HostNodeEntry],
        seenIdentities: inout Set<String>,
        entries: inout [HostNodeEntry],
        elements: inout [ElementInfo],
        layoutRects: inout [String: [Float]],
        dragRegions: inout [[Float]],
        effectSlots: inout [(UInt32, [Float])]
    ) {
        var workStack: [(Taffy.NodeId, NodeId?, (Float, Float), (Float, Float), [Float]?, Int?)] = [
            (rootTaffyId, nil, (0.0, 0.0), (0.0, 0.0), nil, nil)
        ]
        while let (taffyId, parentSceneId, parentWorldOrigin, ancestorScrollShift, parentClipRect, parentElemIndex) = workStack.popLast() {
            guard let payload = tree.getNodeContext(taffyId) else { continue }
        let layout: Layout
        if case .success(let l) = tree.layout(taffyId) {
            layout = l
        } else {
            layout = Layout()
        }
        let el = payload.el
        var localRect = RuneMotion.Rect(
            x: layout.location.x,
            y: layout.location.y,
            w: layout.size.width,
            h: layout.size.height
        )
        if let anc = el.aboveAnchor, let tRect = layoutRects[anc.key], tRect.count == 4 {
            let trigger: [Float] = [tRect[0], tRect[1], tRect[0] + tRect[2], tRect[1] + tRect[3]]
            let (ax, ay) = anchorPosition(anc, trigger, (localRect.w, localRect.h), viewport)
            localRect.x = ax - parentWorldOrigin.0
            localRect.y = ay - parentWorldOrigin.1
        }
        let worldRect = RuneMotion.Rect(
            x: parentWorldOrigin.0 + localRect.x,
            y: parentWorldOrigin.1 + localRect.y,
            w: localRect.w,
            h: localRect.h
        )

        let wasMounted = hs.mountedNodeIds[payload.identity] != nil
        let sceneId = hs.allocNodeId(for: payload.identity)
        seenIdentities.insert(payload.identity)

        let inheritedMotionSpring = el.motionSpring ?? parentElemIndex.flatMap { entries[$0].motionSpring }
        let inheritedInstantChanges = el.instantChangesFlag || (parentElemIndex.map { entries[$0].instantChanges } ?? false)
        let parentHasGrowth = parentElemIndex.map { entries[$0].hasGrowth } ?? false
        let txInstant = hs.pendingInstant || inheritedInstantChanges || reducedMotion
        let transition = el.transitionSpec ?? .opacity()

        let prev = prevByNodeId[sceneId]
        let nowHasLiveRect = el.liveBindings.contains(where: { $0.property == .rect })
        let prevHadLiveRect = prev?.liveBindings.contains(where: { $0.property == .rect }) == true
        let nowHasLiveOpacity = el.liveBindings.contains(where: { $0.property == .opacity })
        let prevHadLiveOpacity = prev?.liveBindings.contains(where: { $0.property == .opacity }) == true
        let nowHasLiveFill = el.liveBindings.contains(where: { $0.property == .fill })
        let prevHadLiveFill = prev?.liveBindings.contains(where: { $0.property == .fill }) == true
        let nowHasLiveScale = el.liveBindings.contains(where: { $0.property == .scale })
        let prevHadLiveScale = prev?.liveBindings.contains(where: { $0.property == .scale }) == true
        let nowHasLiveOffset = el.liveBindings.contains(where: { $0.property == .offset })
        let prevHadLiveOffset = prev?.liveBindings.contains(where: { $0.property == .offset }) == true
        let nowHasLiveBlur = el.liveBindings.contains(where: { $0.property == .blur })
        let prevHadLiveBlur = prev?.liveBindings.contains(where: { $0.property == .blur }) == true

        if !wasMounted || !scene.contains(sceneId) {
            var spec = NodeSpec(localRect)
                .opacity(el.vis.opacity)
                .radius(el.vis.corners)
                .fill(motionColor(el.vis.fill))
                .transition(transition)
            if let pid = parentSceneId {
                spec = spec.parent(pid)
            }
            let mountMode: Mount = (hs.firstCommit || txInstant) ? .initial : .animated
            scene.insert(sceneId, spec, mountMode)
        } else {
            let rectChanged = !nowHasLiveRect && (prev == nil || prev?.localRect != localRect || prevHadLiveRect)
            let opacityChanged = !nowHasLiveOpacity && (prev == nil || prev?.opacity != el.vis.opacity || prevHadLiveOpacity)
            let fillNeedsSync = !nowHasLiveFill && (prev == nil || prev?.fill != el.vis.fill || prevHadLiveFill)
            let radiusChanged = prev == nil || prev?.corners != el.vis.corners

            if rectChanged {
                let layoutAnim: LayoutAnim
                if txInstant || parentHasGrowth || hs.pendingRelayout {
                    layoutAnim = .instant
                } else if let curve = hs.pendingCurve {
                    layoutAnim = LayoutAnim(curve)
                } else if let sp = hs.pendingSpring {
                    layoutAnim = LayoutAnim(sp)
                } else if let elSp = inheritedMotionSpring {
                    layoutAnim = LayoutAnim(elSp)
                } else if el.animateLayoutFlag || el.key != nil {
                    layoutAnim = LayoutAnim(tok.motion.DEFAULT)
                } else {
                    layoutAnim = .instant
                }
                scene.setFrame(sceneId, localRect, layoutAnim)
            }

            if prevHadLiveScale && !nowHasLiveScale {
                scene.set(sceneId, prop.scale, el.scaleValue)
            }
            if prevHadLiveOffset && !nowHasLiveOffset {
                scene.set(sceneId, prop.offset, Vec2.zero)
            }
            if prevHadLiveBlur && !nowHasLiveBlur {
                scene.set(sceneId, prop.blur, el.vis.cold.getIfSome?.layerBlur ?? 0.0)
            }

            if txInstant {
                if opacityChanged {
                    scene.set(sceneId, prop.opacity, el.vis.opacity)
                }
                if fillNeedsSync {
                    scene.set(sceneId, prop.fill, motionColor(el.vis.fill))
                }
                if radiusChanged {
                    scene.set(sceneId, prop.radius, el.vis.corners)
                }
            } else {
                if opacityChanged {
                    if let opAnim = el.opacityMotionAnim {
                        scene.animate(sceneId, prop.opacity, el.vis.opacity, opAnim)
                    } else {
                        scene.set(sceneId, prop.opacity, el.vis.opacity)
                    }
                }
                if fillNeedsSync {
                    scene.set(sceneId, prop.fill, motionColor(el.vis.fill))
                }
                if radiusChanged {
                    scene.set(sceneId, prop.radius, el.vis.corners)
                }
            }
        }

        if el.timeScaleValue != 1.0 {
            scene.setTimeScale(sceneId, el.timeScaleValue)
        }
        if let tn = el.traceNameValue {
            scene.traceName(sceneId, tn)
        }
        if let tns = el.traceNamespaceValue {
            scene.traceNamespace(sceneId, tns)
        }

        var extras = el.handlers.getIfSome?.hostExtras ?? HostElExtras()
        if extras.cursor == nil {
            extras.cursor = el.handlers.getIfSome?.cursor
        }
        let hasRealOnKey = (el.onKeyHandler != nil)

        var mergedLiveBindings = el.liveBindings
        if let prevBindings = prev?.liveBindings {
            for i in mergedLiveBindings.indices {
                if let old = prevBindings.first(where: {
                    $0.property == mergedLiveBindings[i].property && $0.source.id == mergedLiveBindings[i].source.id
                }) {
                    mergedLiveBindings[i].seen = old.seen
                }
            }
        }
        let effectiveFill: Color = (nowHasLiveFill && prevHadLiveFill) ? (prev?.fill ?? el.vis.fill) : el.vis.fill
        let inputAskedFocus = el.input?.edit.focused ?? false
        if inputAskedFocus && (hs.firstCommit || prev?.inputEditFocused != true) && !el.inertFlag {
            hs.focusedPath = payload.path
            hs.focusedKey = el.key
        }

        if let key = el.key {
            layoutRects[key] = [worldRect.x, worldRect.y, worldRect.w, worldRect.h]
        }
        if el.windowDragFlag {
            dragRegions.append([worldRect.x, worldRect.y, worldRect.w, worldRect.h])
        }
        if let mark = el.vis.cold.getIfSome?.effectMark {
            effectSlots.append((mark, [worldRect.x, worldRect.y, worldRect.w, worldRect.h]))
        }

        let elemIdx = elements.count
        let shownRect: RuneMotion.Rect
        if let pres = scene.presented(sceneId) {
            shownRect = hostDrawnRect(pres, scrollShift: ancestorScrollShift)
        } else {
            shownRect = worldRect
        }
        let displayedText: String?
        if let inp = el.input {
            displayedText = inp.edit.text
        } else {
            displayedText = el.textSpec?.value.live?.get() ?? el.textSpec?.value.content
        }
        var elemInfo = ElementInfo(
            path: payload.path,
            key: el.key,
            role: el.input != nil ? "textbox" : el.roleName,
            label: el.labelText,
            text: displayedText,
            rect: [shownRect.x, shownRect.y, shownRect.w, shownRect.h],
            target: [worldRect.x, worldRect.y, worldRect.w, worldRect.h],
            opacity: el.vis.opacity,
            radius: el.vis.corners.c0,
            fill: effectiveFill,
            textColor: el.textSpec?.value.color,
            parent: parentElemIndex
        )
        elemInfo.focused = (payload.path == hs.focusedPath) || (el.key != nil && el.key == hs.focusedKey)
        elemInfo.focusable = (el.focusSpec.getIfSome?.enabled ?? false) || el.input != nil
        elemInfo.inert = el.inertFlag
        elemInfo.help = el.helpText
        let inheritedTraceNamespace = el.traceNamespaceValue ?? parentElemIndex.flatMap { elements[$0].traceNamespace }
        elemInfo.traceName = el.traceNameValue
        elemInfo.traceNamespace = inheritedTraceNamespace
        elemInfo.visible = visibleWithinClip(shownRect, parentClipRect)
        if let pres = scene.presented(sceneId) {
            elemInfo.scale = pres.transform.scale.x
            elemInfo.blur = pres.blur
        }
        elements.append(elemInfo)

        entries.append(
            HostNodeEntry(
                nodeId: sceneId,
                parentId: parentSceneId,
                parentElemIndex: parentElemIndex,
                key: el.key,
                path: payload.path,
                identity: payload.identity,
                localRect: localRect,
                worldRect: worldRect,
                scrollShift: ancestorScrollShift,
                clipRect: parentClipRect,
                fill: effectiveFill,
                hoverFill: el.vis.hover,
                pressFill: el.vis.press,
                border: el.vis.border,
                borderWidth: el.vis.borderWidth,
                corners: el.vis.corners,
                opacity: el.vis.opacity,
                transition: transition,
                motionSpring: inheritedMotionSpring,
                opacityAnim: el.opacityMotionAnim,
                animateLayout: el.animateLayoutFlag,
                instantChanges: inheritedInstantChanges,
                hasGrowth: el.growthSpec != nil,
                textSpec: el.textSpec?.value,
                pixels: el.vis.cold.getIfSome?.pixels,
                effectMark: el.vis.cold.getIfSome?.effectMark,
                windowDrag: el.windowDragFlag,
                helpText: el.helpText,
                helpCut: el.helpCutFlag,
                focusable: (el.focusSpec.getIfSome?.enabled ?? false) || el.input != nil,
                focusHighlight: el.focusSpec.getIfSome?.highlight,
                focusFollows: el.focusSpec.getIfSome?.follows ?? false,
                defaultButton: el.focusSpec.getIfSome?.defaultButton ?? false,
                isInput: el.input != nil,
                singleLineInput: el.input?.singleLine ?? false,
                inputEditFocused: inputAskedFocus,
                scrollSpec: el.scrollSpec,
                role: el.input != nil ? "textbox" : el.roleName,
                label: el.labelText,
                inert: el.inertFlag,
                hasPressHandler: el.onPressHandler != nil,
                hasRealOnKey: hasRealOnKey,
                onPress: el.onPressHandler,
                onSecondaryPress: el.onSecondaryPressHandler,
                onKey: el.onKeyHandler,
                onDrag: el.onDragHandler,
                onHover: el.onHoverHandler,
                extras: extras,
                liveBindings: mergedLiveBindings
            )
        )

        if case .success(let childIds) = tree.children(taffyId), !childIds.isEmpty {
            var childOrigin = (worldRect.x, worldRect.y)
            var childScrollShift = ancestorScrollShift
            if let scrollSpec = el.scrollSpec {
                var contentBottom: Float = 0.0
                for cid in childIds {
                    if case .success(let cl) = tree.layout(cid) {
                        contentBottom = max(contentBottom, cl.location.y + cl.size.height)
                    }
                }
                contentBottom += layout.padding.bottom
                let prevMax = hs.scrollMaxByPath[payload.path]
                let maxOff = max(0.0, contentBottom - localRect.h)
                hs.scrollMaxByPath[payload.path] = maxOff
                let existing = hs.scrollOffsets[payload.path]
                let clamped: Float
                if let existing {
                    if scrollSpec.stickBottom, let prevMax, existing >= prevMax - 1.0 {
                        clamped = maxOff
                    } else {
                        clamped = min(max(existing, 0.0), maxOff)
                    }
                } else if scrollSpec.stickBottom {
                    clamped = maxOff
                } else {
                    clamped = 0.0
                }
                hs.scrollOffsets[payload.path] = clamped
                scene.set(sceneId, prop.scroll, Vec2(0.0, clamped))
                childOrigin.1 -= clamped
                childScrollShift.1 += clamped
            }

            let nextClip: [Float]?
            if el.vis.clip || el.scrollSpec != nil {
                let ownBounds: [Float] = [
                    worldRect.x,
                    worldRect.y,
                    worldRect.x + worldRect.w,
                    worldRect.y + worldRect.h,
                ]
                nextClip = intersectClip(parentClipRect, ownBounds)
            } else {
                nextClip = parentClipRect
            }

            for cid in childIds.reversed() {
                workStack.append((cid, sceneId, childOrigin, childScrollShift, nextClip, elemIdx))
            }
        } else if el.scrollSpec != nil {
            hs.scrollMaxByPath[payload.path] = 0.0
            hs.scrollOffsets[payload.path] = 0.0
        }
        }
    }

    private func applyQueuedScrollOperations(
        hs: RuntimeWindowHostState,
        entries: inout [HostNodeEntry],
        elements: inout [ElementInfo],
        layoutRects: inout [String: [Float]]
    ) {
        guard !hs.pendingScrollReveals.isEmpty
            || !hs.pendingScrollRequests.isEmpty
            || !hs.pendingScrollBottoms.isEmpty
        else { return }

        func shiftSubtree(scrollIdx: Int, deltaY: Float) {
            guard abs(deltaY) > 1e-4 else { return }
            for i in (scrollIdx + 1)..<entries.count {
                var isDesc = false
                var cur = entries[i].parentElemIndex
                while let p = cur {
                    if p == scrollIdx {
                        isDesc = true
                        break
                    }
                    cur = entries[p].parentElemIndex
                }
                guard isDesc else { continue }
                entries[i].worldRect.y -= deltaY
                entries[i].scrollShift.1 += deltaY
                if entries[i].scrollSpec != nil || entries[i].clipRect != nil {
                    // Recompute clipRect if an inner clip container moved
                    if let pIdx = entries[i].parentElemIndex {
                        let parentClip = entries[pIdx].scrollSpec != nil
                            ? intersectClip(
                                entries[pIdx].clipRect,
                                [
                                    entries[pIdx].worldRect.x,
                                    entries[pIdx].worldRect.y,
                                    entries[pIdx].worldRect.x + entries[pIdx].worldRect.w,
                                    entries[pIdx].worldRect.y + entries[pIdx].worldRect.h,
                                ]
                            )
                            : entries[pIdx].clipRect
                        entries[i].clipRect = parentClip
                    }
                }
                let wr = entries[i].worldRect
                elements[i].rect = [wr.x, wr.y, wr.w, wr.h]
                elements[i].target = [wr.x, wr.y, wr.w, wr.h]
                elements[i].visible = visibleWithinClip(wr, entries[i].clipRect)
                if let k = entries[i].key {
                    layoutRects[k] = [wr.x, wr.y, wr.w, wr.h]
                }
            }
        }

        func resolveKeyPath(_ idx: Int) -> String {
            var parts: [String] = []
            var cur: Int? = idx
            while let i = cur {
                if let k = entries[i].key {
                    parts.append(k)
                }
                cur = entries[i].parentElemIndex
            }
            return parts.reversed().joined(separator: "/")
        }

        func findMatchingNode(_ query: String) -> Int? {
            if !query.contains("/") {
                return entries.firstIndex(where: { $0.key == query || $0.path == query })
            }
            return entries.indices.first(where: { idx in
                if entries[idx].path == query || entries[idx].path.hasSuffix("/\(query)") {
                    return true
                }
                let kp = resolveKeyPath(idx)
                return kp == query || kp.hasSuffix("/\(query)")
            })
        }

        func enclosingScrollNode(_ targetIdx: Int) -> Int? {
            if entries[targetIdx].scrollSpec != nil {
                return targetIdx
            }
            var cur = entries[targetIdx].parentElemIndex
            while let p = cur {
                if entries[p].scrollSpec != nil {
                    return p
                }
                cur = entries[p].parentElemIndex
            }
            return nil
        }

        for req in hs.pendingScrollRequests {
            if let mIdx = findMatchingNode(req.key),
               let sIdx = enclosingScrollNode(mIdx),
               let targetY = req.y
            {
                let path = entries[sIdx].path
                let maxOff = hs.scrollMaxByPath[path] ?? 0.0
                let oldOff = hs.scrollOffsets[path] ?? 0.0
                let newOff = min(max(targetY, 0.0), maxOff)
                hs.scrollOffsets[path] = newOff
                scene.set(entries[sIdx].nodeId, prop.scroll, Vec2(0.0, newOff))
                shiftSubtree(scrollIdx: sIdx, deltaY: newOff - oldOff)
            }
        }
        hs.pendingScrollRequests.removeAll()

        for (key, _) in hs.pendingScrollBottoms {
            if let mIdx = findMatchingNode(key),
               let sIdx = enclosingScrollNode(mIdx)
            {
                let path = entries[sIdx].path
                let maxOff = hs.scrollMaxByPath[path] ?? 0.0
                let oldOff = hs.scrollOffsets[path] ?? 0.0
                hs.scrollOffsets[path] = maxOff
                scene.set(entries[sIdx].nodeId, prop.scroll, Vec2(0.0, maxOff))
                shiftSubtree(scrollIdx: sIdx, deltaY: maxOff - oldOff)
            }
        }
        hs.pendingScrollBottoms.removeAll()

        for reveal in hs.pendingScrollReveals {
            guard let tIdx = findMatchingNode(reveal.key) else {
                continue
            }
            var cur = entries[tIdx].parentElemIndex
            var scrollIdx: Int? = nil
            while let p = cur {
                if entries[p].scrollSpec != nil {
                    scrollIdx = p
                    break
                }
                cur = entries[p].parentElemIndex
            }
            guard let sIdx = scrollIdx else { continue }
            let path = entries[sIdx].path
            let maxOff = hs.scrollMaxByPath[path] ?? 0.0
            guard maxOff > 0.0 else { continue }
            let oldOff = hs.scrollOffsets[path] ?? 0.0
            let viewTop = entries[sIdx].worldRect.y
            let viewH = entries[sIdx].worldRect.h
            let itemTopInContent = (entries[tIdx].worldRect.y - viewTop) + oldOff
            let itemH = entries[tIdx].worldRect.h

            var newOff = oldOff
            if reveal.center {
                newOff = itemTopInContent + itemH * 0.5 - viewH * 0.5
            } else if itemTopInContent < oldOff {
                newOff = itemTopInContent
            } else if itemTopInContent + itemH > oldOff + viewH {
                newOff = itemTopInContent + itemH - viewH
            }
            newOff = min(max(newOff, 0.0), maxOff)
            if abs(newOff - oldOff) > 1e-4 {
                hs.scrollOffsets[path] = newOff
                scene.set(entries[sIdx].nodeId, prop.scroll, Vec2(0.0, newOff))
                shiftSubtree(scrollIdx: sIdx, deltaY: newOff - oldOff)
            }
        }
        hs.pendingScrollReveals.removeAll()
    }

    private func hostSampleLiveBindings(_ hs: RuntimeWindowHostState, pending: Bool) -> Bool {
        if !hs.liveVisible || hs.liveSubscriptions.isEmpty {
            return false
        }
        if !pending && !hs.liveDirty {
            return false
        }
        hs.liveDirty = false
        for idx in 0..<hs.lastNodes.count {
            let nid = hs.lastNodes[idx].nodeId
            for bIdx in 0..<hs.lastNodes[idx].liveBindings.count {
                let initial = hs.lastNodes[idx].liveBindings[bIdx].seen == nil
                let (sampled, active) = hs.lastNodes[idx].liveBindings[bIdx].read(hs.liveClockToken, clock)
                if active {
                    hs.liveDirty = true
                }
                guard let bits = sampled else { continue }
                let sp: Spring? = initial ? nil : hs.lastNodes[idx].liveBindings[bIdx].spring
                switch hs.lastNodes[idx].liveBindings[bIdx].property {
                case .opacity:
                    let val = min(max(Float.decodeLive(bits), 0.0), 1.0)
                    if let sp {
                        scene.animate(nid, prop.opacity, val, sp)
                    } else {
                        scene.set(nid, prop.opacity, val)
                    }
                case .scale:
                    let val = max(Float.decodeLive(bits), 0.0)
                    if let sp {
                        scene.animate(nid, prop.scale, val, sp)
                    } else {
                        scene.set(nid, prop.scale, val)
                    }
                case .blur:
                    let val = max(Float.decodeLive(bits), 0.0)
                    if let sp {
                        scene.animate(nid, prop.blur, val, sp)
                    } else {
                        scene.set(nid, prop.blur, val)
                    }
                case .offset:
                    let arr = [Float].decodeLive(bits)
                    let vec = Vec2(arr[0], arr[1])
                    if let sp {
                        scene.animate(nid, prop.offset, vec, sp)
                    } else {
                        scene.set(nid, prop.offset, vec)
                    }
                case .fill:
                    let decoded = Color.decodeLive(bits)
                    hs.lastNodes[idx].fill = decoded
                    let col = motionColor(decoded)
                    if let sp {
                        scene.animate(nid, prop.fill, col, sp)
                    } else {
                        scene.set(nid, prop.fill, col)
                    }
                case .rect:
                    let arr = [Float].decodeLive(bits)
                    let r = RuneMotion.Rect(x: arr[0], y: arr[1], w: max(arr[2], 0.0), h: max(arr[3], 0.0))
                    if let sp {
                        scene.setFrame(nid, r, sp)
                    } else {
                        scene.setFrame(nid, r, LayoutAnim.instant)
                    }
                }
            }
        }
        return hs.liveDirty
    }

    private func hostEmitInstances(_ hs: RuntimeWindowHostState) -> ([Instance], [LayerSpec]) {
        var instances: [Instance] = []
        var layers: [LayerSpec] = []
        let scale = env.scale
        let useSrgb = srgbBlend

        @inline(__always)
        func premulColor(_ c: Color, _ opacity: Float) -> [Float] {
            useSrgb ? c.premulSrgb(opacity) : c.premul(opacity)
        }

        for i in 0..<hs.lastNodes.count {
            let entry = hs.lastNodes[i]
            guard let pres = scene.presented(entry.nodeId) else { continue }
            let r = hostDrawnRect(pres, scrollShift: entry.scrollShift)
            if i < hs.lastElements.count {
                hs.lastElements[i].rect = [r.x, r.y, r.w, r.h]
            }
            guard pres.opacity > 0.0 else { continue }
            let devRect = [r.x * scale, r.y * scale, r.w * scale, r.h * scale]
            let devClip: [Float]
            if let cr = entry.clipRect, cr.count == 4 {
                devClip = [cr[0] * scale, cr[1] * scale, cr[2] * scale, cr[3] * scale]
            } else {
                devClip = NO_CLIP
            }
            let radii = [
                pres.radius.c0 * scale,
                pres.radius.c1 * scale,
                pres.radius.c2 * scale,
                pres.radius.c3 * scale,
            ]

            var fill = Color(pres.fill.r, pres.fill.g, pres.fill.b, pres.fill.a)
            let isFocusedNode = (entry.path == hs.focusedPath) || (entry.key != nil && entry.key == hs.focusedKey)
            if isFocusedNode && (hs.keyboardFocus || hs.hoverFocus), let hl = entry.focusHighlight, hl.a > 0.0 {
                fill = hl
            }
            var fillPremul = premulColor(fill, pres.opacity)
            if hs.hoveredPaths.contains(entry.path) {
                if hs.pointerButtonHeld == .primary && entry.pressFill.a > 0.0 {
                    fillPremul = over(premulColor(entry.pressFill, pres.opacity), fillPremul)
                } else if entry.hoverFill.a > 0.0 {
                    fillPremul = over(premulColor(entry.hoverFill, pres.opacity), fillPremul)
                }
            }

            if pres.blur > 0.0 {
                let spec = LayerSpec(opacity: pres.opacity, blend: .sourceOver, blur: pres.blur * scale, clipRadius: 0.0)
                layers.append(spec)
                instances.append(.beginLayer(devRect, devClip, spec))
            }

            if fillPremul[3] > 0.0 || entry.borderWidth > 0.0 {
                instances.append(
                    Instance(
                        rect: devRect,
                        radii: radii,
                        fill: fillPremul,
                        border: premulColor(entry.border, pres.opacity),
                        params: [entry.borderWidth * scale, KIND_RECT, 0.0, 0.0],
                        uv: [0, 0, 0, 0],
                        clip: devClip,
                        fade: [0, 0, 0, 0]
                    )
                )
            }

            if let px = entry.pixels {
                if let placed = images.place(px, [devRect[2], devRect[3]]) {
                    instances.append(
                        Instance(
                            rect: devRect,
                            radii: radii,
                            fill: [1.0, 1.0, 1.0, pres.opacity],
                            border: [0, 0, 0, 0],
                            params: [Float(placed.page), KIND_IMAGE, placed.premultiplied ? 1.0 : 0.0, 0.0],
                            uv: [
                                Float(placed.rect[0]),
                                Float(placed.rect[1]),
                                Float(placed.rect[2]),
                                Float(placed.rect[3]),
                            ],
                            clip: devClip,
                            fade: [0, 0, 0, 0]
                        )
                    )
                }
            }

            if let textSpec = entry.textSpec {
                let str = (i < hs.lastElements.count ? hs.lastElements[i].text : nil)
                    ?? textSpec.live?.get()
                    ?? textSpec.content
                if !str.isEmpty {
                    var hashVal: UInt32 = 2_166_136_261
                    for b in str.utf8 {
                        hashVal ^= UInt32(b)
                        hashVal = hashVal &* 16_777_619
                    }
                    let tc = textSpec.color
                    instances.append(
                        Instance(
                            rect: devRect,
                            radii: [0, 0, 0, 0],
                            fill: [tc.r, tc.g, tc.b, tc.a * pres.opacity],
                            border: [0, 0, 0, 0],
                            params: [textSpec.style.size * scale, KIND_GLYPH, 0.0, 0.0],
                            uv: [Float(hashVal & 0xffff), Float((hashVal >> 16) & 0xffff), Float(str.utf8.count), 0.0],
                            clip: devClip,
                            fade: [0, 0, 0, 0]
                        )
                    )
                }
            }

            if let mark = entry.effectMark {
                instances.append(
                    Instance(
                        rect: devRect,
                        radii: radii,
                        fill: [0, 0, 0, pres.opacity],
                        border: [0, 0, 0, 0],
                        params: [Float(mark), KIND_EFFECT, 0.0, 0.0],
                        uv: [0, 0, 0, 0],
                        clip: devClip,
                        fade: [0, 0, 0, 0]
                    )
                )
            }

            if pres.blur > 0.0 {
                instances.append(.endLayer())
            }
        }
        return (instances, layers)
    }

    func hostInteractiveRegions() -> [[Float]] {
        let hs = windowHostState(for: self)
        if hs.firstCommit || hs.needsCommit {
            hostCommitTree(hs)
            hs.needsCommit = false
        }
        var rects: [[Float]] = []
        for entry in hs.lastNodes where !entry.inert {
            let interactive = entry.hasPressHandler
                || entry.focusable
                || entry.onDrag != nil
                || entry.onHover != nil
                || entry.onSecondaryPress != nil
                || entry.hasRealOnKey
            if interactive {
                let r = hostPresentedRect(entry)
                if r.w > 0 && r.h > 0 {
                    rects.append([
                        r.x,
                        r.y,
                        r.x + r.w,
                        r.y + r.h,
                    ])
                }
            }
        }
        return rects
    }
}

/// Steps a covered (occluded, hidden, or minimized) window without GPU encoding, view building, or swapchain acquisition (`crates/rune/src/window/stepping.rs`).
/// `poll` and due timers run now while the view and layout wait, dirty, for the frame that uncovers the window.
@discardableResult
func coveredStep<S>(
    rt: Runtime<S>,
    clock: inout HostFrameClock,
    firstFrame: inout FirstFrame,
    now: RuneInstant = .now()
) -> Bool {
    _ = now
    _ = rt.hostCancelTimerFrame()
    _ = firstFrame.markReady()
    clock.pause()
    _ = rt.hostPollHidden()
    return false
}
