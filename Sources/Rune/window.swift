// Ported from: crates/rune/src/window.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Native window host (`Host<S>`, `AnyHost`, `startAll`, `runWindows`) (`crates/rune/src/window.rs`).

#if !os(WASI)
import Foundation
#endif

/// Type-erased window/app host driven by `ShellEventLoop` (`crates/rune/src/window.rs`).
protocol AnyHost: AnyObject {
    var hostWindowId: UInt64? { get }
    var isPrimaryHost: Bool { get }
    var isAlive: Bool { get }
    func attachHost(
        hostIndex: Int,
        wakeHost: @escaping @Sendable () -> Void,
        wakeSink: @escaping @Sendable (WakeEvent) -> Void
    )
    func resumeHost(hostIndex: Int, displays: [Display])
    func startHost(
        hostIndex: Int,
        wakeHost: @escaping @Sendable () -> Void,
        wakeSink: @escaping @Sendable (WakeEvent) -> Void,
        displays: [Display]
    )
    @discardableResult
    func stepHost(now: RuneInstant, displays: [Display]) -> Bool
    func handleHostWakeEvent(_ event: WakeEvent, displays: [Display]) -> Bool
    func nextWakeDeadline(now: RuneInstant) -> RuneInstant?
    func handleReopen(hasVisibleWindows: Bool) -> Bool
    func hasVisibleReopenableWindow() -> Bool
    func handleIncomingUrls(_ urls: [String])
    func shutdownHost()
}

/// Concrete typed host for one `App<S>` or `WindowSpec<S>` (`crates/rune/src/window.rs`).
final class Host<S> {
    var spec: AppSpec<S>
    let rt: Runtime<S>
    var win: Win? = nil
    var clock = HostFrameClock()
    var windowlessHiddenPace = HiddenPace()

    var chrome: Chrome
    var options: WindowOptions
    var macOptions: MacWindowOptions
    let handle: AppHandle<S>
    let windowHandle: WindowHandle

    var openOnStart: Bool
    var keepRunning: Bool
    var secondary: Bool
    var releaseGpuWhenClosed: Bool
    var accessory: Bool
    var standardMenus: Bool
    var floatOnOpen: Bool
    var fitContentHeight: Bool
    var modifierKeys: Bool
    var tabVisitsControls: Bool
    var headlessGuards: Bool = false
    var gpuBackend: HostGpuBackend = .auto

    var shortcutGuard: ShortcutGuard? = nil
    var menuGuard: MenuGuard<S>? = nil
    let popupPresenter = PopupPresenter()

    var reports = WindowFrameReports<S>()
    var compositor: (any HostCompositorProtocol)? = nil

    var onFocusHook: ((inout S, Bool, inout Tx) -> Void)? = nil {
        didSet {
            rt.hostSetAppOnFocus(onFocusHook)
        }
    }
    var onImeHook: ((inout S, Ime, inout Tx) -> Bool)? = nil {
        didSet {
            rt.hostSetAppOnIme(onImeHook)
        }
    }
    var onCloseHook: ((inout S, inout Tx) -> Bool)? = nil
    var onReopenHook: ((inout S, Bool, inout Tx) -> Bool)? = nil
    var onOpenUrlHook: OnOpenUrl<S>? = nil
    var onWindowHook: ((WindowHandle) -> Void)? = nil
    var onReadyHook: ((WindowHandle) -> Void)? = nil
    var onCreatedCallback: ((WindowHandle) -> Void)? = nil
    var readyFired: Bool = false

    var overlays: [any AnyOverlayHost] = []
    var pendingOverlays: [PendingOverlay] = []

    init(
        spec: AppSpec<S>,
        state: S? = nil,
        chrome: Chrome = .DEFAULT,
        options: WindowOptions = WindowOptions(),
        macOptions: MacWindowOptions = MacWindowOptions(),
        handle: AppHandle<S> = AppHandle<S>(),
        windowHandle: WindowHandle = WindowHandle("main"),
        openOnStart: Bool = true,
        keepRunning: Bool = false,
        secondary: Bool = false,
        releaseGpuWhenClosed: Bool = false,
        accessory: Bool = false,
        standardMenus: Bool = false,
        srgbBlend: Bool = true,
        fontSmoothing: FontSmoothing = .default,
        fitContentHeight: Bool = false,
        modifierKeys: Bool = false,
        tabVisitsControls: Bool = false,
        floatOnOpen: Bool = false,
        playground: Any? = nil
    ) {
        self.spec = spec
        let initialState = state ?? spec.`init`()
        let env = Env(systemDark: true, scale: 1.0)
        let runtime = Runtime(initialState, spec.view, spec.size, env)
        runtime.transparent = options.transparent
        runtime.srgbBlend = srgbBlend
        runtime.poll = spec.poll
        runtime.onKey = spec.onKey
        let hs = windowHostState(for: runtime)
        hs.fontSmoothing = fontSmoothing
        hs.fontFamilies = spec.families
        hs.modifierKeys = modifierKeys
        hs.tabVisitsControls = tabVisitsControls
        #if os(macOS)
        hs.titlebarInset = macTitlebarInset(chrome: chrome, borderless: options.borderless, fullscreen: false)
        #endif
        hs.systemAccent = systemAccent()
        if let pg = playground as? Playground<S> {
            playgroundAttach(
                rt: runtime,
                playground: pg,
                spec: spec,
                open: nil,
                variant: nil,
                windowed: true,
                inUnitTest: true
            )
        }
        self.rt = runtime

        self.chrome = chrome
        self.options = options
        self.macOptions = macOptions
        self.handle = handle
        self.windowHandle = windowHandle
        self.openOnStart = openOnStart
        self.keepRunning = keepRunning
        self.secondary = secondary
        self.releaseGpuWhenClosed = releaseGpuWhenClosed
        self.accessory = accessory
        self.standardMenus = standardMenus
        self.floatOnOpen = floatOnOpen
        self.fitContentHeight = fitContentHeight
        self.modifierKeys = modifierKeys
        self.tabVisitsControls = tabVisitsControls
    }

    func mountPendingOverlays(hostIndex: Int, displays: [Display]) {
        guard !pendingOverlays.isEmpty else { return }
        let pending = pendingOverlays
        pendingOverlays.removeAll()
        for p in pending {
            let mounted = p.mount(hostIndex: hostIndex, displays: displays)
            overlays.append(mounted)
        }
    }
}

/// Starts all hosts in `specs` inside a `ShellEventLoop` (`crates/rune/src/window.rs`).
func startAll(_ hosts: [any AnyHost], displays: [Display] = [Display()]) -> ShellEventLoop {
    let loop = ShellEventLoop(hosts: hosts, displays: displays)
    loop.start()
    return loop
}

/// Runs a set of `AnyWindowSpec` windows (`crates/rune/src/window.rs`).
func runWindowsInternal(_ windows: [AnyWindowSpec], options: RunOptions) throws {
    let flat = flattenWindowSpecs(windows)
    try validateWindowSpecs(flat)
    #if os(macOS)
    if options.accessory {
        macSetDockIconVisible(false)
    }
    #endif
    let hosts = flat.map { $0.buildHost() }
    let loop = startAll(hosts)
    _ = loop.pump()
    loop.shutdown()
}
