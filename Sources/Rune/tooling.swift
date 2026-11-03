// Ported from: crates/rune/src/tooling.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Agent tooling: headless deterministic rendering, synthetic input scripts, element-tree dumps,
//! motion-lint traces and frame strips. Same renderer as the window, fixed virtual clock.

#if !os(WASI)
import Foundation
#endif
import Taffy

extension RuneInstant {
    @inline(__always)
    func saturatingDurationSince(_ earlier: RuneInstant) -> Double {
        let d = durationSince(earlier)
        return Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }

    @inline(__always)
    func adding(_ seconds: Double) -> RuneInstant {
        RuneInstant(raw.advanced(by: .nanoseconds(Int64((seconds * 1_000_000_000.0).rounded()))))
    }
}

public struct AppSpec<S> {
    public var title: String
    public var size: (Float, Float)
    public var minSize: (Float, Float)?
    public var `init`: () -> S
    public var view: (S, Cx<S>) -> El
    public var scenes: [(String, (inout S) -> Void)]
    public var fonts: [[UInt8]]
    public var families: (String, String)
    public var setup: ((inout S, @escaping Waker) -> Void)?
    public var poll: ((inout S, Double, inout Tx) -> Bool)?
    public var onKey: ((inout S, KeyEvent, inout Tx) -> Bool)?

    public init(
        title: String,
        size: (Float, Float),
        minSize: (Float, Float)? = nil,
        init initFn: @escaping () -> S,
        view: @escaping (S, Cx<S>) -> El,
        scenes: [(String, (inout S) -> Void)] = [],
        fonts: [[UInt8]] = [],
        families: (String, String) = ("Inter", "Inter"),
        setup: ((inout S, @escaping Waker) -> Void)? = nil,
        poll: ((inout S, Double, inout Tx) -> Bool)? = nil,
        onKey: ((inout S, KeyEvent, inout Tx) -> Bool)? = nil
    ) {
        self.title = title
        self.size = size
        self.minSize = minSize
        self.`init` = initFn
        self.view = view
        self.scenes = scenes
        self.fonts = fonts
        self.families = families
        self.setup = setup
        self.poll = poll
        self.onKey = onKey
    }

    public init(
        _ title: String,
        _ size: (Float, Float),
        _ initFn: @escaping () -> S,
        _ view: @escaping (S, Cx<S>) -> El
    ) {
        self.init(title: title, size: size, init: initFn, view: view)
    }

    public static func new(
        _ title: String,
        _ size: (Float, Float),
        _ initFn: @escaping () -> S,
        _ view: @escaping (S, Cx<S>) -> El
    ) -> AppSpec<S> {
        AppSpec(title: title, size: size, init: initFn, view: view)
    }
}

/// Window frame options.
public struct Chrome: Sendable, Equatable {
    public var fullSizeContent: Bool
    public var trafficLights: (Float, Float)?
    public var dragRegions: Bool

    public static let DEFAULT = Chrome(fullSizeContent: true, trafficLights: nil, dragRegions: false)
    public static let TRAFFIC_LIGHT: Float = 14.0
    public static let TRAFFIC_PITCH: Float = 23.0

    public init(
        fullSizeContent: Bool = true,
        trafficLights: (Float, Float)? = nil,
        dragRegions: Bool = false
    ) {
        self.fullSizeContent = fullSizeContent
        self.trafficLights = trafficLights
        self.dragRegions = dragRegions
    }

    public static func == (lhs: Chrome, rhs: Chrome) -> Bool {
        guard lhs.fullSizeContent == rhs.fullSizeContent,
              lhs.dragRegions == rhs.dragRegions
        else { return false }
        switch (lhs.trafficLights, rhs.trafficLights) {
        case (nil, nil): return true
        case (let l?, let r?): return l.0 == r.0 && l.1 == r.1
        default: return false
        }
    }

    public func trafficLightRects() -> [[Float]]? {
        if !fullSizeContent && trafficLights == nil {
            return nil
        }
        let (x, y) = trafficLights ?? (7.0, 6.0)
        return (0..<3).map { i in
            [x + Float(i) * Self.TRAFFIC_PITCH, y, Self.TRAFFIC_LIGHT, Self.TRAFFIC_LIGHT]
        }
    }

    public func titlebarInset() -> Float {
        guard let rects = trafficLightRects() else { return 0.0 }
        return rects[2][0] + rects[2][2]
    }
}

private let toolingGlobalsLock = LiveLock()
// PORT NOTE: Guarded by `toolingGlobalsLock` for process-wide app ID (`APP_ID` OnceLock in Rust).
nonisolated(unsafe) private var globalAppIdValue: String? = nil
// PORT NOTE: Guarded by `toolingGlobalsLock` for process-wide unrecognized CLI args (`EXTRA` OnceLock in Rust).
nonisolated(unsafe) private var globalExtraArgsValue: [String]? = nil

public func setAppId(_ id: String) {
    toolingGlobalsLock.withLock {
        if globalAppIdValue == nil {
            globalAppIdValue = id
        }
    }
}

func currentAppId() -> String? {
    toolingGlobalsLock.withLock { globalAppIdValue }
}

func setExtraArgsOnce(_ extra: [String]) {
    toolingGlobalsLock.withLock {
        if globalExtraArgsValue == nil {
            globalExtraArgsValue = extra
        }
    }
}

func resetExtraArgsForTests() {
    toolingGlobalsLock.withLock {
        globalExtraArgsValue = nil
    }
}

public func extraArgs() -> [String] {
    let existing = toolingGlobalsLock.withLock { globalExtraArgsValue }
    if let existing {
        return existing
    }
    _ = Args.parse()
    return toolingGlobalsLock.withLock { globalExtraArgsValue ?? [] }
}

func toolingRuntimeFor<S>(
    spec: AppSpec<S>,
    state: S,
    size: (Float, Float),
    env: Env,
    waker: @escaping Waker
) -> Runtime<S> {
    hostRecorderHeadlessReset()
    let text = TextSystem.forWindow(spec.fonts, spec.families)
    let rt = Runtime.withText(state, spec.view, size, env, text)
    rt.poll = spec.poll
    rt.onKey = spec.onKey
    hostAttachment(for: rt).startWindowTitle(spec.title)
    rt.hostSetLiveWaker(waker)
    if let setup = spec.setup {
        setup(&rt.state, waker)
    }
    return rt
}

/// Opens the app's window and quits when it closes (`App` for other lifetimes), or renders
/// headless for the tooling arguments.
public func run<S>(_ spec: AppSpec<S>) {
    App.new(spec).run()
}

/// Spine compatibility overload configuring `App<S>` before running.
public func runWith<S>(_ spec: AppSpec<S>, _ configure: (App<S>) -> App<S>) {
    configure(App.new(spec)).run()
}

/// `run` with a compositor drawing every frame (`crates/rune/src/tooling.rs:run_with`).
public func runWith<S>(_ spec: AppSpec<S>, _ compositor: any HostCompositorProtocol) {
    App.new(spec).compositor(compositor).run()
}

// MARK: - Multi-Window Factory Runners (`run_windows*`)

public func runWindows(_ factory: @escaping ([Display]) -> [AnyWindowSpec]) {
    runWindowsWith(RunOptions(), factory)
}

public func runWindowsWith(_ options: RunOptions, _ factory: @escaping ([Display]) -> [AnyWindowSpec]) {
    toolingStarted(tryRunWindowsWith(options, factory))
}

public func tryRunWindowsWith(
    _ options: RunOptions,
    _ factory: @escaping ([Display]) -> [AnyWindowSpec]
) -> Result<Void, ToolingCliError> {
    toolingRunWindowFactory(options: options, args: toolingWindowArgs(nil, Args.parse), factory: factory)
}

public func runWindowsWithArgs(
    _ options: RunOptions,
    _ args: [String],
    _ factory: @escaping ([Display]) -> [AnyWindowSpec]
) {
    toolingStarted(tryRunWindowsWithArgs(options, args, factory))
}

public func tryRunWindowsWithArgs(
    _ options: RunOptions,
    _ args: [String],
    _ factory: @escaping ([Display]) -> [AnyWindowSpec]
) -> Result<Void, ToolingCliError> {
    toolingRunWindowFactory(options: options, args: toolingWindowArgs(args, Args.parse), factory: factory)
}

func toolingStarted(_ result: Result<Void, ToolingCliError>) {
    if case .failure(let err) = result {
        fatalError(err.message)
    }
}

func toolingWindowArgs(_ args: [String]?, _ process: () -> Args) -> Args {
    if let args {
        return Args.parseFrom(args)
    }
    return process()
}

private func toolingRunWindowFactory(
    options: RunOptions,
    args: Args,
    factory: @escaping ([Display]) -> [AnyWindowSpec]
) -> Result<Void, ToolingCliError> {
    if args.headless() {
        let displays = toolingDesktop(args, toolingReadScript(args)).publicDisplays()
        return toolingHeadlessWindow(factory(displays), displays: displays, args: args, options: options)
    } else {
        return windowRunWindows(factory: factory, args: args, options: options)
    }
}

func windowRunWindows(
    factory: @escaping ([Display]) -> [AnyWindowSpec],
    args: Args,
    options: RunOptions
) -> Result<Void, ToolingCliError> {
    _ = args
    let displays = VirtualDesktop().publicDisplays()
    let flat = flattenWindowSpecs(factory(displays))
    do {
        try validateWindowSpecs(flat)
    } catch {
        return .failure(ToolingCliError("\(error)"))
    }
    #if !os(WASI)
    readySignalRunStarts()
    defer { readySignalClear() }
    #endif
    #if os(macOS)
    if options.accessory {
        macSetDockIconVisible(false)
    }
    #endif
    let hosts = flat.map { $0.buildHost() }
    let loop = startAll(hosts)
    _ = loop.pump()
    loop.shutdown()
    return .success(())
}

func toolingHeadlessWindow(
    _ rawWindows: [AnyWindowSpec],
    displays: [Display],
    args: Args,
    options: RunOptions
) -> Result<Void, ToolingCliError> {
    var windows = flattenWindowSpecs(rawWindows)
    do {
        try validateWindowSpecs(windows)
    } catch {
        toolingDie("\(error)")
    }
    if args.listWindows {
        for w in windows {
            print(w.id)
        }
        return .success(())
    }
    let index: Int
    if let key = args.window {
        guard let idx = windows.firstIndex(where: { $0.id == key }) else {
            toolingDie("no window \(toolingEscapeJsonString(key)); use --list-windows")
        }
        index = idx
    } else if !windows.isEmpty {
        index = 0
    } else {
        toolingDie("the app created no windows")
    }

    if args.desktop != nil {
        interactionGateHeadless()
        toolingRunDesktopCli(windows: windows, selectedIndex: index, args: args, accessory: options.accessory)
        return .success(())
    }

    let chosen = windows.remove(at: index)
    let resolved = chosen.resolveToolingArgs(args)
    if !resolved.headless() {
        return windowRunWindows(factory: { _ in [chosen] }, args: resolved, options: options)
    }
    let primary = displays.first(where: \.primary) ?? displays[0]
    chosen.runHeadless(args: resolved, defaultScale: Float(primary.scale))
    return .success(())
}

public func initialState<S>(_ spec: AppSpec<S>, _ scene: String? = nil) -> S {
    toolingWithScene(spec, spec.`init`(), scene)
}

func toolingWithScene<S>(_ spec: AppSpec<S>, _ initial: S, _ scene: String?) -> S {
    var s = initial
    if let name = scene {
        guard let entry = spec.scenes.first(where: { $0.0 == name }) else {
            let names = spec.scenes.map(\.0).joined(separator: ", ")
            toolingDie("no scene \(toolingEscapeJsonString(name)); scenes: \(names)")
        }
        entry.1(&s)
    }
    return s
}

// MARK: - Internal Script Event IR (`Pos`, `Kind`, `FileStep`, `Ev`)

enum ToolingPos: Sendable, Equatable {
    case xy(Float, Float)
    case key(String)
    /// Relative to the last pointer-down position.
    case rel(Float, Float)
}

enum ToolingFileStep: Sendable, Equatable {
    case hover([String])
    case drop([String])
    case leave
}

enum ToolingKind: Sendable, Equatable {
    case mark(String)
    case focus(Bool)
    case reopen
    case menu(String)
    case popupMenu(String?)
    case fileDialog(String?)
    case physical(ScriptPhysicalInput)
    case shortcut(Shortcut)
    case move
    case down
    case up
    case secondaryDown
    case secondaryUp
    case key(KeyEvent, Bool)
    case physicalKey(ScriptPhysicalInput, KeyEvent, Character?)
    case paste(ClipboardContent)
    case wheel(Float, Float)
    case fling(Float, Float)
    case files(ToolingFileStep)
    case wheelEvent(WheelEvent)
    case magnify(MagnifyEvent)
    case rotate(RotateEvent)
    case smartMagnify
    case buttonDown(PointerButton)
    case buttonUp(PointerButton)
    case keyUp(KeyEvent)
    case resize(Float, Float)

    var isMark: Bool {
        if case .mark = self { return true }
        return false
    }

    var isDown: Bool {
        switch self {
        case .down, .secondaryDown, .buttonDown: return true
        default: return false
        }
    }

    var isUp: Bool {
        switch self {
        case .up, .secondaryUp, .buttonUp: return true
        default: return false
        }
    }

    var atPointer: Bool {
        switch self {
        case .wheel, .fling, .wheelEvent, .magnify, .rotate, .smartMagnify:
            return true
        default:
            return false
        }
    }
}

struct ToolingEv: Sendable, Equatable {
    var t: Double
    var kind: ToolingKind
    var pos: ToolingPos

    func publicEvent() -> TimedEvent {
        let point: ScriptPoint
        switch pos {
        case .xy(let x, let y): point = .at(x, y)
        case .key(let k): point = .element(k)
        case .rel(let dx, let dy): point = .fromDown(dx, dy)
        }
        func ptr(_ action: PointerAction) -> ScriptEvent {
            .pointer(action: action, at: point)
        }
        let ev: ScriptEvent
        switch kind {
        case .mark(let name): ev = .mark(name)
        case .focus(let focused): ev = .focus(focused)
        case .reopen: ev = .reopen
        case .menu(let item): ev = .menu(item)
        case .popupMenu(let picked): ev = .popupMenu(picked)
        case .fileDialog(let path): ev = .fileDialog(path)
        case .physical(let input): ev = .physical(input)
        case .shortcut(let chord): ev = .shortcut(chord)
        case .move: ev = ptr(.move)
        case .down: ev = ptr(.down)
        case .up: ev = ptr(.up)
        case .secondaryDown: ev = ptr(.secondaryDown)
        case .secondaryUp: ev = ptr(.secondaryUp)
        case .key(let k, let rep): ev = .key(key: k, repeat: rep)
        case .physicalKey(let input, let k, _):
            let rep: Bool
            if case .key(_, _, _, let r) = input { rep = r } else { rep = false }
            ev = .key(key: k, repeat: rep)
        case .paste(let content):
            ev = content.isRich() ? .pasteContent(content) : .paste(content.text())
        case .wheel(0.0, let dy): ev = ptr(.scroll(dy))
        case .wheel(let dx, let dy): ev = ptr(.scrollXy(dx, dy))
        case .fling(0.0, let vy): ev = ptr(.fling(vy))
        case .fling(let vx, let vy): ev = ptr(.flingXy(vx, vy))
        case .files(.hover(let paths)): ev = .dragFiles(paths: paths, at: point)
        case .files(.drop(let paths)): ev = .dropFiles(paths: paths, at: point)
        case .files(.leave): ev = .dragFilesLeave
        case .wheelEvent(let w):
            var positioned = w
            if case .xy(let x, let y) = pos { positioned.x = x; positioned.y = y }
            ev = ptr(.wheel(positioned))
        case .magnify(let m):
            var positioned = m
            if case .xy(let x, let y) = pos { positioned.x = x; positioned.y = y }
            ev = ptr(.magnify(positioned))
        case .rotate(let r):
            var positioned = r
            if case .xy(let x, let y) = pos { positioned.x = x; positioned.y = y }
            ev = ptr(.rotate(positioned))
        case .smartMagnify: ev = ptr(.smartMagnify)
        case .buttonDown(let b): ev = ptr(.buttonDown(b))
        case .buttonUp(let b): ev = ptr(.buttonUp(b))
        case .keyUp(let k): ev = .keyUp(k)
        case .resize(let dw, let dh): ev = .resize(dw: dw, dh: dh)
        }
        return TimedEvent(t: t, event: ev)
    }
}

func toolingReadScript(_ args: Args) -> ToolingJson? {
    guard let path = args.script else { return nil }
    #if os(WASI)
    toolingDie("\(path): filesystem unavailable on WASI")
    #else
    let text: String
    do {
        text = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        toolingDie("\(path): \(error)")
    }
    do {
        return try ToolingJson.parse(text)
    } catch {
        toolingDie("\(path): \(error)")
    }
    #endif
}

func toolingLoadScript(_ script: ToolingJson) -> [ToolingEv] {
    let list: ToolingJson
    if case .object = script {
        list = script.get("events") ?? .array([])
    } else {
        list = script
    }
    return toolingParseScript(list)
}

func toolingDesktop(_ args: Args, _ script: ToolingJson?) -> VirtualDesktop {
    let scale = Double(args.scale ?? 2.0)
    var fallbackSize: (Double, Double)? = nil
    if let deskPath = args.desktop {
        if let (w, h) = args.size {
            fallbackSize = (Double(w), Double(h))
        } else {
            #if !os(WASI)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: deskPath)),
               let (pw, ph) = decodePngHeaderSize([UInt8](data))
            {
                fallbackSize = (Double(pw) / scale, Double(ph) / scale)
            } else {
                toolingDie("\(deskPath): unable to read backdrop dimensions")
            }
            #endif
        }
    }
    do {
        return try VirtualDesktop.fromScriptJson(script, scale: scale, defaultSize: fallbackSize)
    } catch {
        toolingDie("\(error)")
    }
}

func toolingCanvasInput<S>(rt: Runtime<S>, kind: ToolingKind, at xy: (Float, Float)) -> Bool {
    switch kind {
    case .wheelEvent(var ev):
        ev.x = xy.0
        ev.y = xy.1
        rt.toolingDeliverWheelEvent(ev)
    case .magnify(var ev):
        ev.x = xy.0
        ev.y = xy.1
        rt.toolingDeliverMagnifyEvent(ev)
    case .rotate(var ev):
        ev.x = xy.0
        ev.y = xy.1
        rt.toolingDeliverRotateEvent(ev)
    case .smartMagnify:
        rt.toolingDeliverSmartMagnify(xy.0, xy.1)
    case .buttonDown(let b):
        _ = rt.hostPointerDown(xy.0, xy.1, button: b)
    case .buttonUp(let b):
        _ = rt.hostPointerUp(xy.0, xy.1, button: b)
    case .keyUp(let kev):
        rt.toolingDeliverKeyUp(kev)
    case .physicalKey(let phys, let kev, let base):
        rt.toolingDeliverPhysical(phys)
        _ = rt.hostKey(kev, base: base, isRepeat: {
            if case .key(_, _, _, let r) = phys { return r }
            return false
        }())
    default:
        return false
    }
    return true
}

func toolingWheel<S>(rt: Runtime<S>, at xy: (Float, Float), dx: Float, dy: Float) {
    rt.toolingDeliverWheelEvent(WheelEvent(x: xy.0, y: xy.1, dx: dx, dy: dy, precise: true, mods: Mods()))
}

func toolingFling<S>(rt: Runtime<S>, at xy: (Float, Float), vx: Float, vy: Float) {
    _ = rt
    _ = xy
    _ = vx
    _ = vy
}

func toolingFileInput<S>(rt: Runtime<S>, step: ToolingFileStep, at xy: (Float, Float)) {
    _ = xy
    switch step {
    case .hover(let paths): _ = rt.hostDragHover(paths)
    case .drop(let paths): _ = rt.hostFileDrop(paths)
    case .leave: _ = rt.hostDragLeave()
    }
}

// MARK: - Runtime Tooling Extensions

// PORT NOTE: Carries the last physical key code on `Tx` via `sidecar` without modifying `Sources/Rune/el/el_tx.swift`.
final class HostPhysicalKeyBox: Sendable {
    let code: PhysicalKeyCode
    init(_ code: PhysicalKeyCode) { self.code = code }
}

extension Tx {
    func hostPhysicalKey() -> PhysicalKeyCode? {
        peekSidecar(as: HostPhysicalKeyBox.self)?.code
    }
}

final class HostInitialFocusBox: Sendable {
    let key: String?
    init(_ key: String?) {
        self.key = key
    }
}

extension Runtime {
    func hostNewTx() -> Tx {
        var tx = Tx()
        let hs = windowHostState(for: self)
        tx.focusedKey = hs.focusedKey
        tx.appendSidecar(HostInitialFocusBox(hs.focusedKey))
        if scene.tracing() || toolingTraceState(for: self).enabled {
            tx.traceCalls = TraceCalls()
        }
        if let code = hs.lastPhysicalKey {
            tx.appendSidecar(HostPhysicalKeyBox(code))
        }
        return tx
    }

    func hostRecordTraceCalls(_ tx: Tx) {
        guard let calls = tx.traceCalls else { return }
        let ts = toolingTraceState(for: self)
        if ts.enabled {
            ts.events.append(contentsOf: calls.events)
            for (name, kind, val) in calls.channels {
                ts.channels[name] = (kind, val)
            }
        }
        if let tr = scene.traceMut() {
            for ev in calls.events {
                tr.event(ev)
            }
            for (name, kind, val) in calls.channels {
                tr.channel(name, kind, val)
            }
        }
    }

    func toolingFindElementCenter(_ key: String) -> (Float, Float)? {
        let els = hostElements()
        guard let found = els.first(where: { !$0.exiting && ($0.key == key || $0.path == key || $0.path.hasSuffix("/\(key)")) }),
              found.rect.count >= 4
        else { return nil }
        return (found.rect[0] + found.rect[2] * 0.5, found.rect[1] + found.rect[3] * 0.5)
    }

    func toolingDeliverPhysical(_ input: ScriptPhysicalInput) {
        let hs = windowHostState(for: self)
        switch input {
        case .key(let code, let mods, let pressed, _):
            hs.lastPhysicalKey = pressed ? code : nil
            if pressed && code == .escape && !mods.cmd && !mods.ctrl && !mods.alt {
                _ = hostCancelActiveDrag(hs)
            }
        case .modifiers:
            break
        case .focusLost:
            hs.lastPhysicalKey = nil
        }
    }

    func toolingDeliverPaste(_ content: ClipboardContent) {
        _ = hostPaste(content)
    }

    func toolingDeliverWheelEvent(_ ev: WheelEvent) {
        _ = hostWheel(ev.x, ev.y, ev.dy)
    }

    func toolingDeliverMagnifyEvent(_ ev: MagnifyEvent) {
        _ = ev
    }

    func toolingDeliverRotateEvent(_ ev: RotateEvent) {
        _ = ev
    }

    func toolingDeliverSmartMagnify(_ x: Float, _ y: Float) {
        _ = x
        _ = y
    }

    func toolingDeliverKeyUp(_ ev: KeyEvent) {
        _ = ev
    }

    /// Upstream `Runtime::backdrop_dark`: whether the app root's own fill is opaque and dark (`crates/rune/src/runtime/elements.rs:497`).
    func hostBackdropDark() -> Bool? {
        if transparent { return nil }
        let hs = windowHostState(for: self)
        guard let root = hs.lastNodes.first else { return nil }
        let c: Color
        if let pres = scene.presented(root.nodeId) {
            c = Color(pres.fill.r, pres.fill.g, pres.fill.b, pres.fill.a)
        } else {
            c = root.fill
        }
        guard c.a > 0.5 else { return nil }
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.25
    }

    /// Upstream `Runtime::touched_tracks`: tracks sampled on the last tick by `(path, propName, active)` (`crates/rune/src/runtime/elements.rs:137`).
    func hostTouchedTracks() -> [(String, String, Bool)] {
        let store = scene.store()
        let hs = windowHostState(for: self)
        var pathByNode: [NodeId: String] = [:]
        pathByNode.reserveCapacity(hs.lastNodes.count)
        for n in hs.lastNodes {
            pathByNode[n.nodeId] = n.path
        }
        func propName(_ raw: UInt16) -> String {
            switch raw {
            case 0: return "opacity"
            case 1: return "frame"
            case 2: return "offset"
            case 3: return "scale"
            case 4: return "rotation"
            case 5: return "blur"
            case 6: return "radius"
            case 7: return "fill"
            case 8: return "mask"
            case 9: return "scroll"
            case 10: return "presence"
            case 11: return "travel"
            default: return "custom:\(raw)"
            }
        }
        var out: [(String, String, Bool)] = store.touchedTracks().map { track, node, pid in
            let path = pathByNode[node] ?? "node:\(node.rawValue)"
            return (path, propName(pid.rawValue), store.isActive(track))
        }
        out.sort { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            if a.1 != b.1 { return a.1 < b.1 }
            return !a.2 && b.2
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
}

// MARK: - `tooling` Module Namespace (`pub mod tooling`)

public enum tooling {
    public typealias AppSpec<S> = Rune.AppSpec<S>
    public typealias Chrome = Rune.Chrome
    public typealias Args = Rune.Args
    public typealias HeadlessRun = Rune.HeadlessRun
    public typealias WindowFrame = Rune.WindowFrame
    public typealias TimedEvent = Rune.TimedEvent
    public typealias ScriptEvent = Rune.ScriptEvent
    public typealias PointerAction = Rune.PointerAction
    public typealias ScriptPoint = Rune.ScriptPoint
    public typealias PhysicalInput = Rune.ScriptPhysicalInput

    public static func setAppId(_ id: String) { Rune.setAppId(id) }
    public static func extraArgs() -> [String] { Rune.extraArgs() }
    public static func isHeadless() -> Bool { Rune.isHeadless() }
    public static func headlessRun() -> HeadlessRun? { Rune.headlessRun() }
    public static func headless<S>(_ app: App<S>, _ args: Args) { Rune.headless(app, args) }
    public static func initialState<S>(_ spec: AppSpec<S>, _ scene: String? = nil) -> S { Rune.initialState(spec, scene) }
    public static func run<S>(_ spec: AppSpec<S>) { Rune.run(spec) }
    public static func runWith<S>(_ spec: AppSpec<S>, _ configure: (App<S>) -> App<S>) { Rune.runWith(spec, configure) }
    public static func runWith<S>(_ spec: AppSpec<S>, _ compositor: any HostCompositorProtocol) { Rune.runWith(spec, compositor) }
    public static func runWindows(_ factory: @escaping ([Display]) -> [AnyWindowSpec]) { Rune.runWindows(factory) }
    public static func runWindowsWith(_ options: RunOptions, _ factory: @escaping ([Display]) -> [AnyWindowSpec]) { Rune.runWindowsWith(options, factory) }
    public static func tryRunWindowsWith(_ options: RunOptions, _ factory: @escaping ([Display]) -> [AnyWindowSpec]) -> Result<Void, ToolingCliError> { Rune.tryRunWindowsWith(options, factory) }
    public static func runWindowsWithArgs(_ options: RunOptions, _ args: [String], _ factory: @escaping ([Display]) -> [AnyWindowSpec]) { Rune.runWindowsWithArgs(options, args, factory) }
    public static func tryRunWindowsWithArgs(_ options: RunOptions, _ args: [String], _ factory: @escaping ([Display]) -> [AnyWindowSpec]) -> Result<Void, ToolingCliError> { Rune.tryRunWindowsWithArgs(options, args, factory) }
}

// MARK: - Internal `El` Helpers for Tooling & Playground (Wave 2 collision-free)

extension El {
    func pgAbsolute(_ x: Float, _ y: Float) -> El {
        var copy = self
        copy.style.position = .absolute
        copy.style.inset = Taffy.Rect(
            left: .length(x),
            right: .auto(),
            top: .length(y),
            bottom: .auto()
        )
        return copy
    }

    func pgPin(_ left: Float?, _ top: Float?, _ right: Float?, _ bottom: Float?) -> El {
        var copy = self
        copy.style.position = .absolute
        copy.style.inset = Taffy.Rect(
            left: left.map(LengthPercentageAuto.length) ?? .auto(),
            right: right.map(LengthPercentageAuto.length) ?? .auto(),
            top: top.map(LengthPercentageAuto.length) ?? .auto(),
            bottom: bottom.map(LengthPercentageAuto.length) ?? .auto()
        )
        return copy
    }

    func pgAnimateLayout(_ enabled: Bool = true) -> El {
        var copy = self
        copy.animateLayoutFlag = enabled
        return copy
    }

    func pgTraceName(_ name: String) -> El {
        var copy = self
        copy.traceNameValue = name
        return copy
    }

    func pgTraceNamespace(_ cls: String, _ host: String) -> El {
        var copy = self
        copy.traceNamespaceValue = (cls, host)
        return copy
    }
}
