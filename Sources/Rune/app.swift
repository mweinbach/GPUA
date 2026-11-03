// Ported from: crates/rune/src/app.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! The app's lifetime beside its window (`App`, `AppHandle`) (`crates/rune/src/app.rs`).

enum AppWindowRequest: Sendable, Equatable {
    case open(String?)
    case show
    case hide
    case close
}

struct AppRequestsSnapshot<S> {
    var window: AppWindowRequest? = nil
    var dock: Bool? = nil
    var focus: Bool = false
    var minimize: Bool = false
    var position: (Int32, Int32)? = nil
    var place: PlaceRequest? = nil
    var quit: Bool = false
    var woken: Bool = false
    var updates: [(inout S, inout Tx) -> Bool] = []

    func onlyUpdates() -> Bool {
        !woken && window == nil && !focus && !minimize && position == nil && place == nil
    }
}

/// Thread-safe handle to open, focus, close, update, or quit a running `App<S>`.
// PORT NOTE: Synchronized via `lock` (`LiveLock`), mirroring `Arc<Shared<S>>` in `crates/rune/src/app.rs`.
public final class AppHandle<S>: @unchecked Sendable {
    private let lock = LiveLock()
    private var openRequested: Bool = false
    private var quitRequested: Bool = false
    private var wokenFlag: Bool = false
    private var focusRequested: Bool = false
    private var minimizeRequested: Bool = false
    private var visibleSnapshot: Bool = false
    private var windowErrorSnapshot: String? = nil
    private var windowRequest: AppWindowRequest? = nil
    private var positionRequest: (Int32, Int32)? = nil
    private var placeRequest: PlaceRequest? = nil
    private var dockIconVisibleRequest: Bool? = nil
    private var updates: [(inout S, inout Tx) -> Bool] = []
    private var wakerFn: Waker? = nil
    let shortcutHub = ShortcutHub<S>()
    let menuHub = MenuHub<S>()

    public init() {}

    /// Installs the event loop's wake-up and wakes it once for requests made before it existed.
    func connect(_ waker: @escaping Waker) {
        lock.withLock { wakerFn = waker }
        waker()
    }

    public func wake() {
        let w = lock.withLock { () -> Waker? in
            wokenFlag = true
            return wakerFn
        }
        w?()
    }

    public func open() {
        let w = lock.withLock { () -> Waker? in
            openRequested = true
            windowRequest = .open(nil)
            minimizeRequested = false
            return wakerFn
        }
        w?()
    }

    public func show() {
        let w = lock.withLock { () -> Waker? in
            openRequested = true
            windowRequest = .show
            return wakerFn
        }
        w?()
    }

    public func hide() {
        let w = lock.withLock { () -> Waker? in
            openRequested = false
            windowRequest = .hide
            minimizeRequested = false
            return wakerFn
        }
        w?()
    }

    public func focus() {
        let w = lock.withLock { () -> Waker? in
            focusRequested = true
            minimizeRequested = false
            return wakerFn
        }
        w?()
    }

    public func minimize() {
        let w = lock.withLock { () -> Waker? in
            minimizeRequested = true
            focusRequested = false
            return wakerFn
        }
        w?()
    }

    public func setPosition(_ position: (Int32, Int32)) {
        let w = lock.withLock { () -> Waker? in
            positionRequest = position
            placeRequest = nil
            return wakerFn
        }
        w?()
    }

    public func setPosition(_ x: Int32, _ y: Int32) {
        setPosition((x, y))
    }

    public func place(_ display: DisplayTarget, _ placement: OverlayPlacement) {
        let req = PlaceRequest(display: display, placement: placement)
        let w = lock.withLock { () -> Waker? in
            placeRequest = req
            positionRequest = nil
            return wakerFn
        }
        w?()
    }

    /// macOS: show or hide the app's Dock icon (and app menu) while it runs, switching between
    /// the regular and accessory activation policies. Does nothing elsewhere.
    public func setDockIcon(_ visible: Bool) {
        let w = lock.withLock { () -> Waker? in
            dockIconVisibleRequest = visible
            return wakerFn
        }
        w?()
    }

    public func activate(_ token: String) {
        let nonEmpty = token.isEmpty ? nil : token
        let w = lock.withLock { () -> Waker? in
            openRequested = true
            windowRequest = .open(nonEmpty)
            minimizeRequested = false
            return wakerFn
        }
        w?()
    }

    public func close() {
        let w = lock.withLock { () -> Waker? in
            openRequested = false
            windowRequest = .close
            minimizeRequested = false
            return wakerFn
        }
        w?()
    }

    public func quit() {
        let w = lock.withLock { () -> Waker? in
            quitRequested = true
            return wakerFn
        }
        w?()
    }

    public func isVisible() -> Bool {
        lock.withLock { visibleSnapshot }
    }

    public func windowError() -> String? {
        lock.withLock { windowErrorSnapshot }
    }

    func setVisibleSnapshot(_ visible: Bool) {
        lock.withLock { visibleSnapshot = visible }
    }

    func setWindowError(_ error: String?) {
        lock.withLock { windowErrorSnapshot = error }
    }

    func isQuitRequested() -> Bool {
        lock.withLock { quitRequested }
    }

    func takeWoken() -> Bool {
        lock.withLock {
            let w = wokenFlag
            wokenFlag = false
            return w
        }
    }

    func takeFocusRequest() -> Bool {
        lock.withLock {
            let f = focusRequested
            focusRequested = false
            return f
        }
    }

    func takeMinimizeRequest() -> Bool {
        lock.withLock {
            let m = minimizeRequested
            minimizeRequested = false
            return m
        }
    }

    func takePositionRequest() -> (Int32, Int32)? {
        lock.withLock {
            let p = positionRequest
            positionRequest = nil
            return p
        }
    }

    func takePlaceRequest() -> PlaceRequest? {
        lock.withLock {
            let r = placeRequest
            placeRequest = nil
            return r
        }
    }

    func takeDockIconRequest() -> Bool? {
        lock.withLock {
            let d = dockIconVisibleRequest
            dockIconVisibleRequest = nil
            return d
        }
    }

    func takeWindowRequest() -> AppWindowRequest? {
        lock.withLock {
            let r = windowRequest
            windowRequest = nil
            return r
        }
    }

    func windowPending() -> Bool {
        lock.withLock {
            windowRequest != nil
                || focusRequested
                || minimizeRequested
                || positionRequest != nil
                || placeRequest != nil
                || !updates.isEmpty
        }
    }

    func takeAllRequests() -> AppRequestsSnapshot<S> {
        lock.withLock {
            let snap = AppRequestsSnapshot<S>(
                window: windowRequest,
                dock: dockIconVisibleRequest,
                focus: focusRequested,
                minimize: minimizeRequested,
                position: positionRequest,
                place: placeRequest,
                quit: quitRequested,
                woken: wokenFlag,
                updates: updates
            )
            windowRequest = nil
            dockIconVisibleRequest = nil
            focusRequested = false
            minimizeRequested = false
            positionRequest = nil
            placeRequest = nil
            quitRequested = false
            wokenFlag = false
            updates.removeAll()
            return snap
        }
    }

    func drainRequests(_ runUpdate: ((inout S, inout Tx) -> Bool) -> Void) -> AppRequestsSnapshot<S> {
        for fn in takeUpdates() {
            runUpdate(fn)
        }
        return lock.withLock {
            let later = updates
            let snap = AppRequestsSnapshot<S>(
                window: windowRequest,
                dock: dockIconVisibleRequest,
                focus: focusRequested,
                minimize: minimizeRequested,
                position: positionRequest,
                place: placeRequest,
                quit: quitRequested,
                woken: wokenFlag,
                updates: []
            )
            windowRequest = nil
            dockIconVisibleRequest = nil
            focusRequested = false
            minimizeRequested = false
            positionRequest = nil
            placeRequest = nil
            quitRequested = false
            wokenFlag = false
            updates = later
            return snap
        }
    }

    public func update(_ f: @escaping @Sendable (inout S, inout Tx) -> Void) {
        updateIf { state, tx in
            f(&state, &tx)
            return true
        }
    }

    public func updateIf(_ f: @escaping @Sendable (inout S, inout Tx) -> Bool) {
        let w = lock.withLock { () -> Waker? in
            updates.append(f)
            return wakerFn
        }
        w?()
    }

    func queueUpdateWithoutWake(_ f: @escaping (inout S, inout Tx) -> Bool) {
        lock.withLock {
            updates.append(f)
        }
    }

    func takeUpdates() -> [(inout S, inout Tx) -> Bool] {
        lock.withLock {
            let out = updates
            updates.removeAll()
            return out
        }
    }

    func drainUpdates(into state: inout S, tx: inout Tx) -> Bool {
        let pending = takeUpdates()
        var changed = false
        for u in pending {
            if u(&state, &tx) {
                changed = true
            }
        }
        return changed
    }
}

/// An `AppSpec` with its lifetime and window policy.
public final class App<S> {
    var spec: AppSpec<S>
    var chromeSpec: Chrome = .DEFAULT
    var winOptions = WindowOptions()
    var macWinOptions = MacWindowOptions()
    var openOnStart: Bool = true
    var keepRunningFlag: Bool = false
    var releaseGpuFlag: Bool = false
    var accessoryFlag: Bool = false
    var standardMenusFlag: Bool = false
    var srgbBlendFlag: Bool = true
    var fontSmoothingMode: FontSmoothing = .default
    var fitContentHeightFlag: Bool = false
    var canvasIdValue: String? = nil
    var fullViewportFlag: Bool = false
    var modifierKeysFlag: Bool = false
    var tabVisitsControlsFlag: Bool = false
    var floatOnOpenFlag: Bool = false
    var gpuBackendChoice: HostGpuBackend = .auto

    var initialStateOverride: (() -> S)? = nil
    var cliArgsOverride: [String]? = nil

    var onOpenUrlHook: OnOpenUrl<S>? = nil
    var sameTabRouterHook: ((String) -> Bool)? = nil
    var onFocusHook: ((inout S, Bool, inout Tx) -> Void)? = nil
    var onImeHook: ((inout S, Ime, inout Tx) -> Bool)? = nil
    var onCloseHook: ((inout S, inout Tx) -> Bool)? = nil
    var onReopenHook: ((inout S, Bool, inout Tx) -> Bool)? = nil
    var onWindowHook: ((WindowHandle) -> Void)? = nil
    var onReadyHook: ((WindowHandle) -> Void)? = nil
    var frameReports = WindowFrameReports<S>()
    var compositorHook: (any HostCompositorProtocol)? = nil
    var devStatsHook: (() -> String)? = nil
    var pendingOverlays: [PendingOverlay] = []
    var secondaryWindows: [AnyWindowSpec] = []
    var attachedPlayground: Any? = nil

    var sharedHandle = AppHandle<S>()

    public init(_ spec: AppSpec<S>) {
        self.spec = spec
        self.sharedHandle.shortcutHub.named(spec.title)
    }

    public static func new(_ spec: AppSpec<S>) -> App<S> {
        App(spec)
    }

    public func handle() -> AppHandle<S> {
        sharedHandle
    }

    public func srgbBlend(_ enabled: Bool) -> App<S> {
        srgbBlendFlag = enabled
        return self
    }

    public func fontSmoothing(_ mode: FontSmoothing) -> App<S> {
        fontSmoothingMode = mode
        return self
    }

    public func chrome(_ chrome: Chrome) -> App<S> {
        chromeSpec = chrome
        return self
    }

    public func windowOptions(_ options: WindowOptions) -> App<S> {
        winOptions = options
        if !options.visible {
            sharedHandle.setVisibleSnapshot(false)
        }
        return self
    }

    public func configuredOptions(_ configured: ConfiguredWindowOptions) -> App<S> {
        winOptions = configured.options
        macWinOptions = configured.native
        if macWinOptions.launcher {
            keepRunningFlag = true
        }
        return self
    }

    public func macosWindow(_ native: MacWindowOptions) -> App<S> {
        macWinOptions = native
        if native.launcher {
            keepRunningFlag = true
        }
        return self
    }

    public func floatOnOpen() -> App<S> {
        floatOnOpenFlag = true
        return self
    }

    public func fitContentHeight() -> App<S> {
        fitContentHeightFlag = true
        return self
    }

    public func canvasId(_ id: String) -> App<S> {
        canvasIdValue = id
        return self
    }

    public func fullViewport() -> App<S> {
        fullViewportFlag = true
        return self
    }

    public func modifierKeys() -> App<S> {
        modifierKeysFlag = true
        return self
    }

    public func tabVisitsControls(_ on: Bool) -> App<S> {
        tabVisitsControlsFlag = on
        return self
    }

    public func windowless() -> App<S> {
        openOnStart = false
        keepRunningFlag = true
        return self
    }

    public func keepRunning() -> App<S> {
        keepRunningFlag = true
        return self
    }

    public func releaseGpuWhenClosed() -> App<S> {
        releaseGpuFlag = true
        return self
    }

    public func accessory() -> App<S> {
        accessoryFlag = true
        return self
    }

    public func standardMenus() -> App<S> {
        standardMenusFlag = true
        return self
    }

    public func onOpenUrl(_ f: @escaping @Sendable (inout S, String, inout Tx) -> Void) -> App<S> {
        onOpenUrlHook = f
        return self
    }

    public func sameTabRouter(_ f: @escaping (String) -> Bool) -> App<S> {
        sameTabRouterHook = f
        return self
    }

    public func onFocus(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> App<S> {
        onFocusHook = f
        return self
    }

    public func onIme(_ f: @escaping (inout S, Ime, inout Tx) -> Bool) -> App<S> {
        onImeHook = f
        return self
    }

    public func onClose(_ f: @escaping (inout S, inout Tx) -> Void) -> App<S> {
        onCloseHook = { state, tx in
            f(&state, &tx)
            return true
        }
        return self
    }

    public func onClose(_ f: @escaping (inout S, inout Tx) -> Bool) -> App<S> {
        onCloseHook = f
        return self
    }

    public func onReopen(_ f: @escaping (inout S, Bool, inout Tx) -> Bool) -> App<S> {
        onReopenHook = f
        return self
    }

    public func onWindow(_ f: @escaping (WindowHandle) -> Void) -> App<S> {
        onWindowHook = f
        return self
    }

    public func onReady(_ f: @escaping (WindowHandle) -> Void) -> App<S> {
        onReadyHook = f
        return self
    }

    public func onFrameEncoded(_ f: @escaping (WindowFrameEncoded) -> Void) -> App<S> {
        frameReports.encoded = { _, enc in f(enc) }
        return self
    }

    public func onFrameEncoded(_ f: @escaping (inout S, WindowFrameEncoded) -> Void) -> App<S> {
        frameReports.encoded = f
        return self
    }

    public func onFrameDrawn(_ f: @escaping (Runtime<S>) -> Void) -> App<S> {
        frameReports.drawnRuntime = f
        return self
    }

    public func onFrameDrawn(_ f: @escaping (inout S, WindowFrameOutcome) -> Void) -> App<S> {
        frameReports.drawn = f
        return self
    }

    public func compositor(_ compositor: any HostCompositorProtocol) -> App<S> {
        compositorHook = compositor
        return self
    }

    public func gpuBackend(_ backend: HostGpuBackend) -> App<S> {
        gpuBackendChoice = backend
        return self
    }

    public func devStats(_ stats: @escaping () -> String) -> App<S> {
        devStatsHook = stats
        frameReports.devStats = true
        return self
    }

    public func devStats() -> App<S> {
        frameReports.devStats = true
        return self
    }

    public func `init`(_ f: @escaping () -> S) -> App<S> {
        initialStateOverride = f
        return self
    }

    public func initState(_ f: @escaping () -> S) -> App<S> {
        initialStateOverride = f
        return self
    }

    public func args(_ argv: [String]) -> App<S> {
        cliArgsOverride = argv
        return self
    }

    public func overlay<T>(_ spec: OverlaySpec<T>, _ state: T) -> OverlayHandle<T> {
        overlay(ConfiguredOverlay(spec: spec), { state })
    }

    public func overlay<T>(_ configured: ConfiguredOverlay<T>, _ state: T) -> OverlayHandle<T> {
        overlay(configured, { state })
    }

    public func overlay<T>(_ spec: OverlaySpec<T>, _ initState: @escaping () -> T) -> OverlayHandle<T> {
        overlay(ConfiguredOverlay(spec: spec), initState)
    }

    public func overlay<T>(_ configured: ConfiguredOverlay<T>, _ initState: @escaping () -> T) -> OverlayHandle<T> {
        let h = OverlayHandle<T>()
        pendingOverlays.append(PendingOverlay(configured: configured, initState: initState, handle: h))
        return h
    }

    public func retainOverlaySurface<T>(
        _ configured: ConfiguredOverlay<T>,
        _ initState: @escaping () -> T
    ) -> OverlayHandle<T> {
        let h = OverlayHandle<T>()
        pendingOverlays.append(
            PendingOverlay(configured: configured, initState: initState, handle: h, retainSurface: true)
        )
        return h
    }

    @discardableResult
    public func window(_ secondary: AnyWindowSpec) -> App<S> {
        secondaryWindows.append(secondary)
        return self
    }

    @discardableResult
    public func window<W>(_ secondary: WindowSpec<W>) -> (AppHandle<W>, WindowHandle) {
        let appHandle = secondary.handleVal ?? AppHandle<W>()
        let winHandle = WindowHandle(secondary.id)
        var copy = secondary
        copy.handleVal = appHandle
        copy.keepRunningFlag = true
        secondaryWindows.append(AnyWindowSpec.secondary(copy, handle: winHandle))
        return (appHandle, winHandle)
    }

    func webInline() -> Bool {
        canvasIdValue != nil && (fitContentHeightFlag || !fullViewportFlag)
    }

    func intoParts(scene: String? = nil) -> (AppSpec<S>, S, AppHandle<S>) {
        let state = perfLaunchInit {
            if let initFn = initialStateOverride {
                return toolingWithScene(spec, initFn(), scene)
            } else {
                return initialState(spec, scene)
            }
        }
        return (spec, state, sharedHandle)
    }

    func resolveToolingArgs(_ inherited: Args) -> Args {
        if let argv = cliArgsOverride {
            cliArgsOverride = nil
            return Args.parseFrom(argv)
        }
        return inherited
    }

    func buildHost(windowHandle: WindowHandle? = nil, secondary: Bool = false) -> Host<S> {
        let (_, state, _) = intoParts(scene: nil)
        let host = Host<S>(
            spec: spec,
            state: state,
            chrome: chromeSpec,
            options: winOptions,
            macOptions: macWinOptions,
            handle: sharedHandle,
            windowHandle: windowHandle ?? WindowHandle("main"),
            openOnStart: openOnStart,
            keepRunning: keepRunningFlag || secondary,
            secondary: secondary,
            releaseGpuWhenClosed: releaseGpuFlag,
            accessory: accessoryFlag,
            standardMenus: standardMenusFlag,
            srgbBlend: srgbBlendFlag,
            fontSmoothing: fontSmoothingMode,
            fitContentHeight: fitContentHeightFlag,
            modifierKeys: modifierKeysFlag,
            tabVisitsControls: tabVisitsControlsFlag,
            floatOnOpen: floatOnOpenFlag,
            playground: attachedPlayground
        )
        host.gpuBackend = gpuBackendChoice
        host.reports = frameReports
        host.compositor = compositorHook
        host.onFocusHook = onFocusHook
        host.onImeHook = onImeHook
        host.onCloseHook = onCloseHook
        host.onReopenHook = onReopenHook
        host.onOpenUrlHook = onOpenUrlHook
        host.onWindowHook = onWindowHook
        host.onReadyHook = onReadyHook
        host.pendingOverlays = pendingOverlays
        return host
    }

    public func intoWindowSpec(_ id: String = "main") -> WindowSpec<S> {
        WindowSpec.fromApp(id, self)
    }

    public func tryRun() -> Result<Void, ToolingCliError> {
        let args: Args
        if let argv = cliArgsOverride {
            cliArgsOverride = nil
            args = Args.parseFrom(argv)
        } else {
            args = Args.parse()
        }
        if args.headless() {
            return tryHeadless(self, args)
        }
        perfLaunchRunStarts()
        let primarySpec = WindowSpec.fromApp("main", self).boxed()
        let flat = flattenWindowSpecs([primarySpec])
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
        if accessoryFlag {
            macSetDockIconVisible(false)
        }
        #endif

        let hosts = flat.map { $0.buildHost() }
        let loop = startAll(hosts)
        _ = loop.pump()
        loop.shutdown()
        return .success(())
    }

    public func run() {
        toolingStarted(tryRun())
    }
}
