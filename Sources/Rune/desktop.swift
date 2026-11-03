// Ported from: crates/rune/src/desktop.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Headless multi-window virtual desktop (`Desk`, `runDesktop`, `--desktop` CLI runner) (`crates/rune/src/desktop.rs`).

#if !os(WASI)
import Foundation
#endif

/// Multi-window virtual desktop coordinator (`crates/rune/src/desktop.rs`).
final class Desk {
    var virtualDesktop: VirtualDesktop
    private(set) var members: [any DesktopMember]
    /// Z-ordered indices from bottom (0) to top (`count - 1`).
    private var zOrder: [Int]
    private(set) var keyMemberIndex: Int? = nil
    private(set) var pointer: (Int32, Int32)
    private var hoveredMemberIndex: Int? = nil
    private(set) var quitRequested: Bool = false

    init(windows: [AnyWindowSpec], virtualDesktop: VirtualDesktop = VirtualDesktop()) throws {
        let flat = flattenWindowSpecs(windows)
        try validateWindowSpecs(flat)
        self.virtualDesktop = virtualDesktop
        let built = flat.map { $0.buildDesktopMember(virtualDesktop) }
        self.members = built
        self.zOrder = Array(0..<built.count)
        let primary = virtualDesktop.primaryDisplay()
        self.pointer = (
            primary.position.0 + Int32(primary.size.0 / 2),
            primary.position.1 + Int32(primary.size.1 / 2)
        )

        for m in built {
            m.startMember(desktop: virtualDesktop)
        }
        sortZOrderByLevel()
        // Focus topmost visible window at startup
        if let topVisible = zOrder.reversed().first(where: { members[$0].isVisible }) {
            focusMember(topVisible)
        }
    }

    private func sortZOrderByLevel() {
        zOrder.sort { a, b in
            members[a].zLevel < members[b].zLevel
        }
    }

    func focusMember(_ index: Int?) {
        guard keyMemberIndex != index else { return }
        if let prev = keyMemberIndex, prev < members.count {
            members[prev].setKeyFocus(false)
        }
        keyMemberIndex = index
        if let idx = index, idx < members.count {
            // Raise within its z-level tier unless nonactivating panel
            zOrder.removeAll { $0 == idx }
            zOrder.append(idx)
            sortZOrderByLevel()
            members[idx].setKeyFocus(true)
        }
    }

    func keyWindowId() -> String? {
        guard let idx = keyMemberIndex, idx < members.count, members[idx].isVisible else {
            return nil
        }
        return members[idx].id
    }

    func visibleWindowIds() -> [String] {
        zOrder.filter { members[$0].isVisible }.map { members[$0].id }
    }

    func step(dt: Double = 1.0 / 60.0) {
        guard !quitRequested else { return }
        for idx in 0..<members.count {
            let changes = members[idx].stepMember(dt: dt, desktop: virtualDesktop)
            if changes.quit {
                quitRequested = true
                return
            }
            if changes.wantsFocus && members[idx].isVisible {
                focusMember(idx)
            }
        }
        if let keyIdx = keyMemberIndex, !members[keyIdx].isVisible {
            let fallback = zOrder.reversed().first { members[$0].isVisible }
            focusMember(fallback)
        }
    }

    func movePointer(_ x: Int32, _ y: Int32) {
        pointer = (x, y)
        let hitIdx = zOrder.reversed().first { members[$0].isVisible && members[$0].hitTestDesktop(px: x, py: y) }
        if hoveredMemberIndex != hitIdx {
            if let prev = hoveredMemberIndex {
                members[prev].pointerLeaveDesktop()
            }
            hoveredMemberIndex = hitIdx
        }
        if let hitIdx {
            members[hitIdx].pointerMoveDesktop(px: x, py: y)
        }
    }

    func pointerDown(_ x: Int32, _ y: Int32, button: PointerButton = .primary) {
        movePointer(x, y)
        guard let hitIdx = zOrder.reversed().first(where: {
            members[$0].isVisible && members[$0].hitTestDesktop(px: x, py: y)
        }) else {
            return
        }
        if keyMemberIndex != hitIdx {
            focusMember(hitIdx)
        }
        _ = members[hitIdx].pointerDownDesktop(px: x, py: y, button: button)
    }

    func pointerUp(_ x: Int32, _ y: Int32, button: PointerButton = .primary) {
        pointer = (x, y)
        if let hitIdx = hoveredMemberIndex ?? keyMemberIndex, hitIdx < members.count {
            members[hitIdx].pointerUpDesktop(px: x, py: y, button: button)
        }
    }

    func click(_ x: Int32, _ y: Int32, button: PointerButton = .primary) {
        pointerDown(x, y, button: button)
        pointerUp(x, y, button: button)
        step(dt: 1.0 / 60.0)
    }

    func sendKey(_ event: KeyEvent, base: Character? = nil) {
        guard let keyIdx = keyMemberIndex, keyIdx < members.count, members[keyIdx].isVisible else {
            return
        }
        members[keyIdx].keyDownDesktop(event: event, base: base)
    }

    func snapshotRgba(includeCaptureExcluded: Bool = true) -> (UInt32, UInt32, [UInt8]) {
        sortZOrderByLevel()
        var allSlots: [DesktopSlot] = []
        for idx in zOrder where members[idx].isVisible {
            allSlots.append(contentsOf: members[idx].renderSlots(isKeyWindow: idx == keyMemberIndex))
        }
        let b = virtualDesktop.bounds
        let pixels = desktopPixels(
            origin: (b.x, b.y),
            desktopSize: (b.width, b.height),
            slots: allSlots,
            includeCaptureExcluded: includeCaptureExcluded
        )
        return (b.width, b.height, pixels)
    }
}

func runDesktop(windows: [AnyWindowSpec], displaysSpec: String? = nil) throws -> Desk {
    let vd: VirtualDesktop
    if let spec = displaysSpec {
        vd = try VirtualDesktop.parse(spec)
    } else {
        vd = VirtualDesktop()
    }
    let desk = try Desk(windows: windows, virtualDesktop: vd)
    desk.step(dt: 1.0 / 60.0)
    return desk
}

// MARK: - `--desktop` CLI Multi-Window Runner (`crates/rune/src/desktop.rs:234-504`)

struct DesktopCliChanges {
    var front: Bool = false
    var keys: Bool = false
}

protocol DesktopCliMember: AnyObject {
    var key: String { get }
    var frame: [Float] { get }
    var visible: Bool { get }
    var clickThrough: Bool { get }
    var onTop: Bool { get }
    var radius: Float { get }
    var shadow: Bool { get }
    var srgbBlend: Bool { get }
    var dark: Bool { get }

    func start(desktop: VirtualDesktop)
    func traceOn()
    func drain(desktop: VirtualDesktop, t: Double) -> DesktopCliChanges
    func pending() -> Bool
    func stale() -> Bool
    func advance(dt: Double)
    func focus(_ focused: Bool)
    func input(kind: ToolingKind, at: (Float, Float))
    func leave()
    func find(_ key: String) -> (Float, Float)?
    func pointer() -> (Float, Float)?
    func shortcut(_ chord: Shortcut) throws
    func reopenCandidate() -> ReopenCandidate
    func reopenHook(hasVisibleWindows: Bool) -> Bool
    func reopen() -> DesktopCliChanges
    func menu(_ item: String) throws
    func popupOpen() -> Bool
    func resolvePopup(_ picked: String?) -> Result<Void, PopupMenuError>
    func fileDialogOpen() -> Bool
    func resolveFileDialog(_ path: String?) -> Result<Void, FileDialogError>
    func renderRgba(width: UInt32, height: UInt32) -> [UInt8]
    func backdropDark() -> Bool?
    func tree(_ t: Double) -> ToolingJson
    func trace(_ tr: ToolingTrace, _ tMs: Double, _ cpuMs: Double)
}

final class DesktopCliWindow<S>: DesktopCliMember {
    let key: String
    private var rt: Runtime<S>
    private let shared: AppHandle<S>
    private let shortcutsGuard: ShortcutGuard
    private let menusGuard: MenuGuard<S>
    private let windowHandle: WindowHandle?
    private let onFocus: ((inout S, Bool, inout Tx) -> Void)?
    private let onClose: ((inout S, inout Tx) -> Bool)?
    private let onReopen: ((inout S, Bool, inout Tx) -> Bool)?
    private let keepRunning: Bool
    private let launcher: Bool
    private let panel: Bool
    private let main: Bool
    private var hiddenAt: UInt64? = nil
    let shadow: Bool
    let clickThrough: Bool
    private(set) var onTop: Bool
    let radius: Float
    private var position: (Int32, Int32)?
    private let physical: (UInt32, UInt32)?
    private(set) var frame: [Float]
    private(set) var visible: Bool
    private var finished: Bool = false
    private var placedRecord: ToolingJson? = nil
    private var lastInstances: [Instance] = []
    let dark: Bool

    var srgbBlend: Bool { rt.srgbBlend }

    init(
        spec windowSpec: WindowSpec<S>,
        handle: WindowHandle?,
        args: Args,
        selected: Bool,
        main: Bool,
        scale: Float
    ) {
        let app = windowSpec.toApp()
        var inherited = args
        inherited.size = nil
        if !selected {
            inherited.scene = nil
            inherited.playground = nil
            inherited.variant = nil
        }
        let own = app.resolveToolingArgs(inherited)
        let options = windowSpec.optionsVal
        let native = windowSpec.macosVal
        let open = app.openOnStart
        let keepRunning = app.keepRunningFlag
        let onFocus = app.onFocusHook
        let onClose = app.onCloseHook
        let onReopen = app.onReopenHook
        let tabVisitsControls = app.tabVisitsControlsFlag
        let srgbBlend = app.srgbBlendFlag
        let fontSmoothing = app.fontSmoothingMode
        let titlebarInset: Float = options.borderless ? 0.0 : app.chromeSpec.titlebarInset()
        let playground = app.attachedPlayground
        app.attachedPlayground = nil

        let (appSpec, state, shared) = withSceneClock(SceneClock(now: 0.0, dt: 0.0)) {
            app.intoParts(scene: own.scene)
        }
        let shortcutsGuard = ShortcutGuard.attach(shared, wake: {}, headless: true, wayland: false)
        let menusGuard = MenuGuard.attach(shared, headless: true)
        let size = own.size ?? appSpec.size
        let dark = own.theme != "light"

        var rt = toolingRuntimeFor(spec: appSpec, state: state, size: size, env: Env.new(dark, scale), waker: {})
        playgroundAttachHeadless(
            rt: &rt,
            playground: playground,
            spec: appSpec,
            cliPlayground: own.playground,
            cliVariant: own.variant,
            windowed: false
        )
        rt.hostSetTitlebarInset(titlebarInset)
        rt.transparent = options.transparent
        rt.srgbBlend = srgbBlend
        windowHostState(for: rt).fontSmoothing = fontSmoothing
        windowHostState(for: rt).tabVisitsControls = tabVisitsControls
        if selected && args.tree != nil {
            toolingTraceState(for: rt).keyWarnings = []
        }

        let vis = options.visible && open
        rt.hostSetLiveVisible(vis)
        shared.setVisibleSnapshot(vis)
        let decorated = !options.borderless && !options.transparent

        self.key = windowSpec.id
        self.rt = rt
        self.shared = shared
        self.shortcutsGuard = shortcutsGuard
        self.menusGuard = menusGuard
        self.windowHandle = handle
        self.onFocus = onFocus
        self.onClose = onClose
        self.onReopen = onReopen
        self.keepRunning = keepRunning
        self.launcher = native.launcher
        self.panel = native.nonactivatingPanelFlag
        self.main = main
        self.shadow = native.shadowFlag != false && (!options.borderless || native.shadowFlag == true)
        self.clickThrough = options.clickThrough
        self.onTop = options.alwaysOnTop
        self.radius = decorated ? 10.0 : (native.cornerRadiusValue ?? 0.0)
        self.position = options.position
        self.physical = options.physicalSize
        self.frame = [0.0, 0.0, size.0, size.1]
        self.visible = vis
        self.dark = dark
    }

    private func setVisible(_ v: Bool) {
        visible = v
        rt.hostSetLiveVisible(v)
        shared.setVisibleSnapshot(v)
    }

    private func show() {
        guard !visible else { return }
        if !launcher {
            rt.hostSettleAll()
        }
        setVisible(true)
    }

    private func hide() {
        guard visible else { return }
        hiddenAt = reopenStamp()
        rt.hostCancelPopups()
        rt.hostCancelFileDialogs()
        _ = rt.hostPointerLeave()
        setVisible(false)
    }

    private func close() {
        guard visible || !keepRunning else { return }
        if let onClose {
            _ = rt.hostUpdateIf { s, tx in onClose(&s, &tx) }
        }
        hide()
        if !keepRunning {
            rt.hostCancelPopups()
            rt.hostCancelFileDialogs()
            finished = true
        }
    }

    private func applyWindowRequest(_ req: AppWindowRequest, changes: inout DesktopCliChanges) {
        switch req {
        case .open where finished, .show where finished:
            break
        case .open:
            show()
            changes.front = true
            changes.keys = true
        case .show:
            show()
            changes.front = true
            if launcher { changes.keys = true }
        case .hide:
            hide()
        case .close:
            close()
        }
    }

    private func moveTo(_ pt: (Float, Float)) {
        frame[0] = pt.0
        frame[1] = pt.1
        rt.hostSetWindowOrigin(pt.0, pt.1)
    }

    private func resize(_ newFrame: [Float]) {
        frame = newFrame
        let scale = rt.env.scale
        rt.hostSetScale(scale)
        rt.hostSetViewport(newFrame[2], newFrame[3])
        rt.hostSetWindowOrigin(newFrame[0], newFrame[1])
    }

    private func applyPlace(_ desktop: VirtualDesktop, _ req: PlaceRequest, _ t: Double) {
        let size = (frame[2], frame[3])
        let (dispId, placedFrame) = desktop.place(req, size)
        let record: ToolingJson = .object([
            ("t", .number(t)),
            ("window", .string(key)),
            ("display", .int(Int64(dispId))),
            ("frame", .array(placedFrame.map { .number(Double($0)) })),
        ])
        print("rune-placed \(record.serialized())")
        placedRecord = record
        position = nil
        resize(placedFrame)
    }

    func start(desktop: VirtualDesktop) {
        let disp = position.map { desktop.displayAt(px: $0.0, py: $0.1) } ?? desktop.primaryDisplay()
        let size: (Float, Float)
        if let (pw, ph) = physical {
            size = (Float(Double(pw) / disp.scale), Float(Double(ph) / disp.scale))
        } else {
            size = (frame[2], frame[3])
        }
        resize(desktop.openAt(position, size))
    }

    func traceOn() {
        toolingTraceState(for: rt).enabled = true
        rt.scene.storeMut().auditRetargets(true)
    }

    func drain(desktop: VirtualDesktop, t: Double) -> DesktopCliChanges {
        var changes = DesktopCliChanges()
        shortcutsGuard.drain()
        menusGuard.drain()
        let requests = shared.drainRequests { fn in
            _ = rt.hostUpdateIf(fn)
            menusGuard.drain()
        }
        if let pos = requests.position {
            moveTo(desktop.toPoints(pos))
        }
        if let place = requests.place {
            applyPlace(desktop, place, t)
        }
        if let winReq = requests.window {
            applyWindowRequest(winReq, changes: &changes)
        }
        if requests.focus && visible {
            changes.front = true
            changes.keys = true
        }
        if let wh = windowHandle {
            for ev in wh.takeHeadless() {
                switch ev {
                case .window(_, let winReq):
                    applyWindowRequest(winReq, changes: &changes)
                case .place(_, let place):
                    applyPlace(desktop, place, t)
                case .position(_, let pos):
                    moveTo(desktop.toPoints(pos))
                case .focus where visible:
                    changes.front = true
                    changes.keys = true
                case .level(_, let top):
                    onTop = top
                case .frame(_, let fReq):
                    if let sz = fReq.size {
                        resize([frame[0], frame[1], sz.0, sz.1])
                    }
                default:
                    break
                }
            }
        }
        let att = hostAttachment(for: rt)
        for _ in 0..<8 {
            att.minimizeRequest = false
            if let shell = att.shellRequest {
                att.shellRequest = nil
                if shell == .close {
                    close()
                }
            }
            if visible {
                rt.hostOpenPopupHeadless()
            } else {
                rt.hostCancelPopups()
                rt.hostRefuseFileDialog("cannot open a file dialog while the window is hidden")
            }
            if att.shellRequest == nil { break }
        }
        return changes
    }

    func pending() -> Bool {
        shared.windowPending()
            || hostAttachment(for: rt).shellRequest != nil
            || (windowHandle?.headlessPending() == true)
    }

    func stale() -> Bool {
        rt.hostStale()
    }

    func advance(dt: Double) {
        let (insts, _, _) = withBlend(rt.srgbBlend) {
            rt.hostFrame(dt)
        }
        lastInstances = insts
    }

    func focus(_ focused: Bool) {
        rt.hostWindowFocus(focused)
        if let onFocus {
            var tx = Tx()
            onFocus(&rt.state, focused, &tx)
            rt.hostLatchTx(&tx)
        }
    }

    func input(kind: ToolingKind, at xy: (Float, Float)) {
        switch kind {
        case .focus(let focused):
            focus(focused)
        case .move:
            _ = rt.hostPointerMove(xy.0, xy.1)
        case .down:
            _ = rt.hostPointerDown(xy.0, xy.1, button: .primary)
        case .up:
            _ = rt.hostPointerUp(xy.0, xy.1, button: .primary)
        case .secondaryDown:
            _ = rt.hostPointerDown(xy.0, xy.1, button: .secondary)
        case .secondaryUp:
            _ = rt.hostPointerUp(xy.0, xy.1, button: .secondary)
        case .key(let kev, let rep):
            _ = rt.hostKey(kev, isRepeat: rep)
        case .physical(let phys):
            rt.toolingDeliverPhysical(phys)
        case .paste(let content):
            rt.toolingDeliverPaste(content)
        case .wheel(let dx, let dy):
            toolingWheel(rt: rt, at: xy, dx: dx, dy: dy)
        case .fling(let vx, let vy):
            toolingFling(rt: rt, at: xy, vx: vx, vy: vy)
        case .files(let step):
            toolingFileInput(rt: rt, step: step, at: xy)
        case .mark, .reopen, .menu, .popupMenu, .fileDialog, .shortcut:
            break
        default:
            _ = toolingCanvasInput(rt: rt, kind: kind, at: xy)
        }
    }

    func leave() {
        _ = rt.hostPointerLeave()
    }

    func find(_ key: String) -> (Float, Float)? {
        rt.toolingFindElementCenter(key)
    }

    func pointer() -> (Float, Float)? {
        rt.hostPointer()
    }

    func shortcut(_ chord: Shortcut) throws {
        try shared.shortcutHub.fire(chord).get()
        shortcutsGuard.drain()
        rt.hostInvalidate()
    }

    func reopenCandidate() -> ReopenCandidate {
        ReopenCandidate(
            reopenable: !finished && !panel,
            visible: visible,
            minimized: false,
            hiddenAt: hiddenAt,
            main: main
        )
    }

    func reopenHook(hasVisibleWindows: Bool) -> Bool {
        guard !finished, let onReopen else { return false }
        var handled = false
        _ = rt.hostUpdateIf { s, tx in
            handled = onReopen(&s, hasVisibleWindows, &tx)
            return true
        }
        return handled
    }

    func reopen() -> DesktopCliChanges {
        var changes = DesktopCliChanges()
        applyWindowRequest(.open(nil), changes: &changes)
        return changes
    }

    func menu(_ item: String) throws {
        try fireMenuItem(shared, item).get()
        menusGuard.drain()
    }

    func popupOpen() -> Bool {
        rt.hostPopupJson() != nil
    }

    func resolvePopup(_ picked: String?) -> Result<Void, PopupMenuError> {
        rt.hostResolvePopup(picked)
    }

    func fileDialogOpen() -> Bool {
        rt.hostFileDialog() != nil
    }

    func resolveFileDialog(_ path: String?) -> Result<Void, FileDialogError> {
        rt.hostResolveFileDialog(path)
    }

    func renderRgba(width: UInt32, height: UInt32) -> [UInt8] {
        var rgba = toolingRasterizeInstances(
            instances: lastInstances,
            atlas: rt.images,
            width: width,
            height: height,
            dark: dark,
            transparent: rt.transparent,
            srgbBlend: rt.srgbBlend
        )
        if rt.transparent {
            straightAlpha(&rgba)
        }
        return rgba
    }

    func backdropDark() -> Bool? {
        rt.hostBackdropDark()
    }

    func tree(_ t: Double) -> ToolingJson {
        var json = toolingTreeJson(rt, t)
        if let placed = placedRecord {
            json["placed"] = placed
        }
        return json
    }

    func trace(_ tr: ToolingTrace, _ tMs: Double, _ cpuMs: Double) {
        tr.frame(rt, tMs, cpuMs)
    }
}

func toolingRunDesktopCli(
    windows: [AnyWindowSpec],
    selectedIndex: Int,
    args: Args,
    accessory: Bool
) {
    if args.listScenes {
        toolingDie("--list-scenes lists one window's scenes; drop --desktop")
    }
    guard let backdropPath = args.desktop else { return }

    let launched = RuneInstant.now()
    let source = toolingReadScript(args)
    let script = source.map(toolingLoadScript) ?? []
    let timeline: ToolingTimeline
    switch ToolingTimeline.of(args, script) {
    case .success(let tl): timeline = tl
    case .failure(let err): toolingDie(err.message)
    }

    let scale = args.scale ?? 2.0
    var vDesktop = toolingDesktop(args, source)
    let primary = vDesktop.primaryVirtualDisplay().frame.map { Float($0) }
    let size = args.size ?? (primary[2], primary[3])
    guard let (wp, hp) = compositeOutputPixels(size, scale, MAX_BACKDROP) else {
        toolingDie("--size \(size.0)x\(size.1) at scale \(scale): each side must be 1..\(MAX_BACKDROP) pixels")
    }

    let backdropRgba: [UInt8]
    #if canImport(Darwin)
    switch fitBackdropImageFile(backdropPath, (wp, hp)) {
    case .success(let px): backdropRgba = px
    case .failure(let err): toolingDie(err.message)
    }
    #elseif !os(WASI)
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: backdropPath))
        guard let (iw, ih, raw) = decodePng([UInt8](data)) else {
            toolingDie("\(backdropPath): unable to decode PNG backdrop")
        }
        switch fitBackdropBuffer(label: backdropPath, sourceSize: (iw, ih), sourceRgba: raw, targetSize: (wp, hp)) {
        case .success(let px): backdropRgba = px
        case .failure(let err): toolingDie(err.message)
        }
    } catch {
        toolingDie("\(backdropPath): \(error)")
    }
    #else
    toolingDie("\(backdropPath): filesystem unavailable on WASI")
    #endif

    let writer = ToolingWriter((wp, hp))
    if let videoPath = args.video {
        if case .failure(let err) = writer.video(videoPath, timeline.fps) {
            toolingDie(err.message)
        }
    }

    let windowsLog = HeadlessWindowsLog()
    publishHeadlessRun(
        HeadlessRun(
            script: args.script,
            events: script.map { $0.publicEvent() },
            scale: scale,
            fps: timeline.fps,
            size: size,
            start: Double(timeline.startFrame) * timeline.dt,
            frames: timeline.frames,
            end: Double(timeline.lastFrame) * timeline.dt,
            desktop: backdropPath,
            windows: windowsLog
        )
    )

    let members: [any DesktopCliMember] = windows.enumerated().map { idx, spec in
        spec.buildDesktopCliMember(args: args, selected: idx == selectedIndex, scale: scale)
    }
    let n = members.count
    for m in members {
        m.start(desktop: vDesktop)
    }

    var z = Array(0..<n)
    func sortZ() {
        z.sort { a, b in
            !members[a].onTop && members[b].onTop
        }
    }
    sortZ()

    var key: Int? = z.reversed().first { members[$0].visible && !members[$0].clickThrough }
    var active: Bool = (key != nil)
    if let k = key {
        members[k].focus(true)
    }
    var hovered: Int? = nil
    var captured: Int? = nil
    var pointer: (Float, Float) = (primary[0] + primary[2] * 0.5, primary[1] + primary[3] * 0.5)
    var lastDown: (Float, Float) = (0.0, 0.0)

    func snapshotWindow(_ i: Int, _ t: Double) -> WindowFrame {
        let m = members[i]
        return WindowFrame(
            t: t,
            key: m.key,
            frame: m.frame,
            visible: m.visible,
            focused: active && key == i
        )
    }
    var lastLogged: [WindowFrame?] = Array(repeating: nil, count: n)
    func recordWindowFrames(_ t: Double) {
        for i in 0..<n {
            let cur = snapshotWindow(i, t)
            let changed: Bool
            if let prev = lastLogged[i] {
                changed = prev.frame != cur.frame || prev.visible != cur.visible || prev.focused != cur.focused
            } else {
                changed = true
            }
            if changed {
                lastLogged[i] = cur
                windowsLog.append(cur)
            }
        }
    }

    func raise(_ idx: Int) {
        z.removeAll { $0 == idx }
        z.append(idx)
        sortZ()
    }

    func setKey(_ next: Int?, activate: Bool = true) {
        if key == next && (!activate || active) {
            return
        }
        if let prev = key, prev != next {
            members[prev].focus(false)
        }
        key = next
        if let idx = next {
            active = activate
            members[idx].focus(active)
        } else {
            active = false
        }
    }

    func applyChanges(_ idx: Int, _ changes: DesktopCliChanges) {
        if changes.front {
            raise(idx)
        }
        if changes.keys && members[idx].visible && !members[idx].clickThrough {
            setKey(idx, activate: true)
        } else if key == idx && !members[idx].visible {
            let fallback = z.reversed().first { members[$0].visible && !members[$0].clickThrough }
            setKey(fallback, activate: fallback != nil && active)
        }
    }

    func drainAll(_ t: Double) {
        for _ in 0..<8 {
            var anyPending = false
            for idx in 0..<n {
                let ch = members[idx].drain(desktop: vDesktop, t: t)
                applyChanges(idx, ch)
                if members[idx].pending() {
                    anyPending = true
                }
            }
            sortZ()
            if !anyPending { break }
        }
    }

    let t0 = RuneInstant.now()
    let readback = ToolingReadback<ToolingShot>(width: wp, height: hp, depth: TOOLING_READBACK_DEPTH)
    let dark = args.theme != "light"
    let keycapOverlay: ToolingKeycapOverlay? = (args.keys != nil || args.pointer)
        ? ToolingKeycapOverlay(size: size, scale: scale, keys: args.keys, theme: args.keysTheme, pointer: args.pointer)
        : nil
    let initMs = t0.elapsedSeconds() * 1000.0

    let trace: ToolingTrace? = args.trace.map { p in
        let tr = ToolingTrace.open(p, (members[selectedIndex].frame[2], members[selectedIndex].frame[3]), timeline.fps, scale)
        tr.all = args.traceAll
        return tr
    }
    if trace != nil {
        members[selectedIndex].traceOn()
    }

    var stripTiles: [[UInt8]] = []
    let cropsPx: [[UInt32]] = args.crops.map { c in
        c.map { UInt32(max(0.0, ($0 * scale).rounded())) }
    }
    let gap = UInt32((4.0 * scale).rounded())
    var framesWritten = 0
    let hasVideo = writer.hasVideo
    let startFrame = timeline.startFrame
    let frames = timeline.frames
    let snapFrame = timeline.snapFrame
    let lastFrame = timeline.lastFrame
    let dt = timeline.dt
    let fps = timeline.fps

    func deliver(_ shot: ToolingShot, _ px: [UInt8]) {
        if shot.dump {
            if args.strip != nil {
                stripTiles.append(toolingTile(px, wp, hp, cropsPx, gap))
            }
            if let dir = args.out {
                let frameNum = shot.k - startFrame
                let numStr = String(repeating: "0", count: max(0, 4 - "\(frameNum)".count)) + "\(frameNum)"
                if case .failure(let err) = writer.png("\(dir)/frame_\(numStr).png", px) {
                    toolingDie(err.message)
                }
            }
        }
        if shot.snap, let snapPath = args.snap {
            if case .failure(let err) = writer.png(snapPath, px) {
                toolingDie(err.message)
            }
        }
        if shot.video {
            framesWritten += 1
            if case .failure(let err) = writer.frame(px) {
                toolingDie(err.message)
            }
        }
    }

    func fireAcross(_ f: (any DesktopCliMember) throws -> Void) throws {
        var order: [Int] = []
        if let k = key { order.append(k) }
        for i in z.reversed() where i != key {
            order.append(i)
        }
        var firstErr: (any Error)? = nil
        for i in order {
            do {
                try f(members[i])
                return
            } catch {
                if firstErr == nil { firstErr = error }
            }
        }
        if let firstErr { throw firstErr }
    }

    func hitWindow(_ gx: Float, _ gy: Float) -> Int? {
        z.reversed().first { i in
            let m = members[i]
            guard m.visible && !m.clickThrough else { return false }
            let f = m.frame
            return gx >= f[0] && gx < f[0] + f[2] && gy >= f[1] && gy < f[1] + f[3]
        }
    }

    if let firstNonMark = script.first(where: { !$0.kind.isMark }), firstNonMark.t <= 1e-9 {
        drainAll(0.0)
        for m in members where m.visible {
            m.advance(dt: 0.0)
        }
        drainAll(0.0)
    }

    var nextEv = 0
    for k in 0...lastFrame {
        let realT = Double(k) * dt
        let frameStart = RuneInstant.now()

        while nextEv < script.count && script[nextEv].t <= realT + 1e-9 {
            let e = script[nextEv]
            nextEv += 1

            switch e.kind {
            case .mark:
                break
            case .focus(let focused):
                active = focused
                if let idx = key {
                    members[idx].focus(focused)
                }
            case .reopen:
                let cands = members.map { $0.reopenCandidate() }
                let hasVis = reopenHasVisible(cands)
                var handled = false
                for idx in 0..<n where members[idx].reopenHook(hasVisibleWindows: hasVis) {
                    handled = true
                    break
                }
                if !handled && !accessory, let target = reopenTarget(cands) {
                    let ch = members[target].reopen()
                    applyChanges(target, ch)
                    active = true
                }
            case .shortcut(let chord):
                do {
                    try fireAcross({ try $0.shortcut(chord) })
                } catch {
                    toolingDie("script shortcut: \(error)")
                }
                if let ov = keycapOverlay { ov.chord(e.t, chord) }
            case .menu(let item):
                do {
                    try fireAcross({ try $0.menu(item) })
                } catch {
                    toolingDie("script menu: \(error)")
                }
            case .popupMenu(let picked):
                guard let idx = z.reversed().first(where: { members[$0].popupOpen() }) else {
                    toolingDie("script pop-up menu: \(PopupMenuError.notOpen)")
                }
                if case .failure(let err) = members[idx].resolvePopup(picked) {
                    toolingDie("script pop-up menu: \(err)")
                }
            case .fileDialog(let path):
                guard let idx = z.reversed().first(where: { members[$0].fileDialogOpen() }) else {
                    toolingDie("script file dialog: no file dialog is open")
                }
                if case .failure(let err) = members[idx].resolveFileDialog(path) {
                    toolingDie("script file dialog: \(err)")
                }
            case .key(let kev, _), .keyUp(let kev):
                if active, let idx = key, members[idx].visible {
                    members[idx].input(kind: e.kind, at: (0.0, 0.0))
                }
                if case .key = e.kind, let ov = keycapOverlay {
                    ov.key(e.t, kev)
                }
            case .physical(let phys):
                if active, let idx = key, members[idx].visible {
                    members[idx].input(kind: e.kind, at: (0.0, 0.0))
                }
                if case .key(let kc, let mods, pressed: true, _) = phys,
                   case .success(let chord) = Shortcut.fromPhysicalKey(kc, mods),
                   let ov = keycapOverlay
                {
                    ov.chord(e.t, chord)
                }
            case .physicalKey(_, let kev, _):
                if active, let idx = key, members[idx].visible {
                    members[idx].input(kind: e.kind, at: (0.0, 0.0))
                }
                keycapOverlay?.key(e.t, kev)
            case .paste:
                if active, let idx = key, members[idx].visible {
                    members[idx].input(kind: e.kind, at: (0.0, 0.0))
                }
            default:
                // Global desktop pointer / file-drag events
                if case .files(.leave) = e.kind {
                    if let h = hovered {
                        members[h].input(kind: e.kind, at: (0.0, 0.0))
                    }
                    break
                }
                let gx: Float
                let gy: Float
                switch e.pos {
                case .xy(let x, let y):
                    gx = x
                    gy = y
                case .key(let elemKey):
                    var foundPt: (Float, Float)? = nil
                    for idx in z.reversed() where members[idx].visible {
                        if let local = members[idx].find(elemKey) {
                            let f = members[idx].frame
                            foundPt = (f[0] + local.0, f[1] + local.1)
                            break
                        }
                    }
                    guard let resolved = foundPt else {
                        toolingDie("script: no visible window has an element with key \(toolingEscapeJsonString(elemKey))")
                    }
                    gx = resolved.0
                    gy = resolved.1
                case .rel where e.kind.atPointer:
                    gx = pointer.0
                    gy = pointer.1
                case .rel(let dx, let dy):
                    gx = lastDown.0 + dx
                    gy = lastDown.1 + dy
                }
                pointer = (gx, gy)
                vDesktop.pointer = (Double(gx), Double(gy))

                let targetIdx = captured ?? hitWindow(gx, gy)
                if hovered != targetIdx {
                    if let prevH = hovered {
                        members[prevH].leave()
                    }
                    hovered = targetIdx
                }
                if e.kind.isDown {
                    lastDown = (gx, gy)
                    if let hit = targetIdx {
                        raise(hit)
                        setKey(hit, activate: true)
                        captured = hit
                    } else {
                        if let prevK = key {
                            members[prevK].focus(false)
                        }
                        active = false
                    }
                    if case .down = e.kind {
                        keycapOverlay?.press(e.t, gx - primary[0], gy - primary[1])
                    }
                }
                if let idx = targetIdx, members[idx].visible {
                    let f = members[idx].frame
                    members[idx].input(kind: e.kind, at: (gx - f[0], gy - f[1]))
                }
                if e.kind.isUp {
                    captured = nil
                }
            }
        }

        drainAll(realT)
        let step = (k == 0) ? 0.0 : dt
        for m in members where m.visible {
            m.advance(dt: step)
        }
        drainAll(realT)
        for m in members where m.visible && m.stale() {
            m.advance(dt: 0.0)
        }
        recordWindowFrames(realT)

        let inRange = k >= startFrame && k < startFrame + frames
        let shot = ToolingShot(
            k: k,
            dump: inRange && (args.out != nil || args.strip != nil) && ((k - startFrame) % max(args.every, 1) == 0),
            video: inRange && hasVideo,
            snap: k == snapFrame && args.snap != nil
        )
        let firstPixels = args.firstPixels && k == 0
        let wantPixels = shot.dump || shot.video || shot.snap || firstPixels

        if wantPixels {
            for (s, px) in readback.makeRoom() { deliver(s, px) }
            var slots: [DesktopSlot] = []
            for idx in z where members[idx].visible {
                let m = members[idx]
                let f = m.frame
                let sx = Int32(((f[0] - primary[0]) * scale).rounded())
                let sy = Int32(((f[1] - primary[1]) * scale).rounded())
                let sw = UInt32(max(1.0, (f[2] * scale).rounded()))
                let sh = UInt32(max(1.0, (f[3] * scale).rounded()))
                let winRgba = m.renderRgba(width: sw, height: sh)
                slots.append(
                    DesktopSlot(
                        rect: [sx, sy, Int32(sw), Int32(sh)],
                        rgba: winRgba,
                        shadow: m.shadow,
                        cornerRadius: m.radius,
                        backdropBlur: 0.0,
                        keyWindow: active && key == idx,
                        scale: scale,
                        excludeFromCapture: false
                    )
                )
            }
            var compPx = desktopPixels(
                origin: (0, 0),
                desktopSize: (wp, hp),
                backdropRgba: backdropRgba,
                slots: slots
            )
            if let ov = keycapOverlay {
                let appDark = key.flatMap { members[$0].backdropDark() } ?? dark
                let (ovInsts, ovAtlas) = ov.frame(realT, step, appDark)
                if !ovInsts.isEmpty {
                    toolingCompositeInstances(
                        into: &compPx,
                        instances: ovInsts,
                        atlas: ovAtlas,
                        width: wp,
                        height: hp,
                        srgbBlend: true
                    )
                }
            }
            readback.copy(compPx, shot)
            readback.submitted()
        }

        let ms = frameStart.elapsedSeconds() * 1000.0
        if let tr = trace {
            members[selectedIndex].trace(tr, realT * 1000.0, ms)
        }
        if firstPixels {
            let done = readback.finish()
            let marker: ToolingJson = .object([
                ("headless_ms", .number(launched.elapsedSeconds() * 1000.0)),
                ("gpu_init_ms", .number(initMs)),
                ("frame_cpu_ms", .number(ms)),
                ("pixel_bytes", .int(Int64(done.last?.1.count ?? 0))),
            ])
            print("rune-first-pixels \(marker.serialized())")
            for (s, px) in done { deliver(s, px) }
        } else if wantPixels {
            for (s, px) in readback.ready() { deliver(s, px) }
        }

        if k == snapFrame, let treePath = args.tree {
            var tree = members[selectedIndex].tree(realT)
            tree["windows"] = .array((0..<n).map { idx in
                let wf = snapshotWindow(idx, realT)
                return .object([
                    ("key", .string(wf.key)),
                    ("frame", .array(wf.frame.map { .number(Double($0)) })),
                    ("visible", .bool(wf.visible)),
                    ("focused", .bool(wf.focused)),
                ])
            })
            let text = tree.serialized(pretty: true)
            #if !os(WASI)
            do {
                let url = URL(fileURLWithPath: treePath)
                let dir = url.deletingLastPathComponent()
                if !dir.path.isEmpty {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                try text.write(to: url, atomically: false, encoding: .utf8)
            } catch {
                toolingDie("\(treePath): \(error)")
            }
            #endif
        }
    }

    for (s, px) in readback.finish() {
        deliver(s, px)
    }
    trace?.close()
    interactionFlush()

    switch writer.finish() {
    case .success(let maybeVideo):
        if let videoPath = maybeVideo {
            toolingStderr("rune: wrote \(videoPath) (\(framesWritten) frames at \(fps) fps)\n")
        }
    case .failure(let err):
        toolingDie(err.message)
    }

    if let stripPath = args.strip {
        toolingWriteStrip(stripPath, stripTiles, (wp, hp), cropsPx, gap, args.cols)
    }
}
