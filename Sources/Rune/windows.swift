// Ported from: crates/rune/src/windows.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Window descriptions shared by the native shell and deterministic headless selection (`crates/rune/src/windows.rs`).

let defaultWindowMinSize: (Float, Float) = (420.0, 400.0)

struct PlaceRequest: Sendable, Equatable {
    var display: DisplayTarget
    var placement: OverlayPlacement
    var pointer: (Int32, Int32)?
    /// The caller's target, before sampling the pointer; headless runs resolve this.
    var requested: DisplayTarget

    init(display: DisplayTarget, placement: OverlayPlacement) {
        self.requested = display
        self.display = display
        self.placement = placement
        self.pointer = nil
        if self.display == .underPointer {
            #if os(macOS)
            if let id = macPointerDisplay() {
                self.display = .native(.macOS(id))
            } else {
                self.display = .primary
            }
            #elseif os(Windows)
            self.pointer = win32PointerPosition()
            #elseif os(Linux)
            self.pointer = x11PointerPosition()
            #endif
        }
    }

    static func new(_ display: DisplayTarget, _ placement: OverlayPlacement) -> PlaceRequest {
        PlaceRequest(display: display, placement: placement)
    }

    static func at(_ size: (Float, Float)) -> OverlayPlacementSpec {
        OverlayPlacementSpec(size: size, edge: .top, margin: 0.0, align: .center, inset: 0.0)
    }

    static func == (lhs: PlaceRequest, rhs: PlaceRequest) -> Bool {
        let ptrEq: Bool
        switch (lhs.pointer, rhs.pointer) {
        case (nil, nil): ptrEq = true
        case (let a?, let b?): ptrEq = a.0 == b.0 && a.1 == b.1
        default: ptrEq = false
        }
        return lhs.display == rhs.display
            && lhs.placement == rhs.placement
            && ptrEq
            && lhs.requested == rhs.requested
    }
}

/// Process-level settings applied once, before constructing the native event loop.
public struct RunOptions: Sendable, Equatable {
    /// macOS: no Dock icon/default menu and no activation at launch. Ignored elsewhere.
    public var accessory: Bool

    public init(accessory: Bool = false) {
        self.accessory = accessory
    }
}

/// A display in desktop physical-pixel coordinates (origins may be negative).
/// Headless runs provide one deterministic virtual display.
public struct Display: Sendable, Equatable {
    /// Native identity for overlay targeting; absent for the headless virtual display.
    public var id: DisplayId?
    public var name: String?
    public var position: (Int32, Int32)
    public var size: (UInt32, UInt32)
    public var scale: Double
    public var primary: Bool

    public init(
        id: DisplayId? = nil,
        name: String? = nil,
        position: (Int32, Int32) = (0, 0),
        size: (UInt32, UInt32) = (1920, 1080),
        scale: Double = 1.0,
        primary: Bool = true
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.size = size
        self.scale = scale
        self.primary = primary
    }

    public func nativeId() -> NativeDisplayId? {
        id?.nativeId()
    }

    /// `(x, y, width, height)` in the native global, top-left coordinate space.
    public func nativeBounds() -> [Double] {
        #if os(macOS)
        if case .macOS(let cgId) = nativeId() {
            return macDisplayBounds(cgId)
        }
        #endif
        let divisor: Double
        if case .wayland = nativeId() {
            divisor = scale
        } else {
            divisor = 1.0
        }
        return [
            Double(position.0),
            Double(position.1),
            Double(size.0) / divisor,
            Double(size.1) / divisor,
        ]
    }

    public static func == (lhs: Display, rhs: Display) -> Bool {
        lhs.id == rhs.id
            && lhs.name == rhs.name
            && lhs.position.0 == rhs.position.0
            && lhs.position.1 == rhs.position.1
            && lhs.size.0 == rhs.size.0
            && lhs.size.1 == rhs.size.1
            && lhs.scale == rhs.scale
            && lhs.primary == rhs.primary
    }
}

public struct WindowOptions: Sendable, Equatable {
    public var transparent: Bool
    public var borderless: Bool
    /// Clicks, and so hover, pass to whatever is below.
    public var clickThrough: Bool
    public var alwaysOnTop: Bool
    public var visible: Bool
    /// Physical desktop coordinates, not points. Use a display's position unchanged.
    public var position: (Int32, Int32)?
    /// Physical content size; overrides `AppSpec`'s logical size when set.
    public var physicalSize: (UInt32, UInt32)?
    /// Logical minimum; `nil` inherits `AppSpec`'s minimum, `(0, 0)` removes the floor.
    public var minSize: (Float, Float)?
    /// Logical maximum content size. `nil` leaves it unconstrained.
    public var maxSize: (Float, Float)?
    /// Whether the user can resize the window. Programmatic sizing is unaffected.
    public var resizable: Bool

    public init(
        transparent: Bool = false,
        borderless: Bool = false,
        clickThrough: Bool = false,
        alwaysOnTop: Bool = false,
        visible: Bool = true,
        position: (Int32, Int32)? = nil,
        physicalSize: (UInt32, UInt32)? = nil,
        minSize: (Float, Float)? = nil,
        maxSize: (Float, Float)? = nil,
        resizable: Bool = true
    ) {
        self.transparent = transparent
        self.borderless = borderless
        self.clickThrough = clickThrough
        self.alwaysOnTop = alwaysOnTop
        self.visible = visible
        self.position = position
        self.physicalSize = physicalSize
        self.minSize = minSize
        self.maxSize = maxSize
        self.resizable = resizable
    }

    /// A hidden, retained launcher. On macOS, prepares its first frame at alpha zero;
    /// show/open takes keys without activating the app.
    public static func launcherPanel() -> ConfiguredWindowOptions {
        var native = MacWindowOptions().nonactivatingPanel(true)
        native.launcher = true
        return WindowOptions(
            transparent: true,
            borderless: true,
            visible: false,
            minSize: (0.0, 0.0),
            resizable: false
        ).macos(native)
    }

    public func macos(_ native: MacWindowOptions) -> ConfiguredWindowOptions {
        ConfiguredWindowOptions(options: self, native: native)
    }

    /// One transparent, borderless, topmost, click-through overlay covering this display.
    public static func overlay(_ display: Display) -> WindowOptions {
        WindowOptions(
            transparent: true,
            borderless: true,
            clickThrough: true,
            alwaysOnTop: true,
            visible: true,
            position: display.position,
            physicalSize: display.size,
            minSize: (0.0, 0.0),
            maxSize: nil,
            resizable: true
        )
    }

    func sizeLimits(_ appMin: (Float, Float)?) -> ((Float, Float), (Float, Float)?) {
        var minVal = minSize ?? appMin ?? defaultWindowMinSize
        if let maxVal = maxSize {
            minVal = (min(minVal.0, maxVal.0), min(minVal.1, maxVal.1))
        }
        return (minVal, maxSize)
    }

    func fitMinSize(_ appMin: (Float, Float)?) -> (Float, Float)? {
        if appMin == nil && minSize == nil {
            return (defaultWindowMinSize.0, 0.0)
        }
        return appMin
    }

    public static func == (lhs: WindowOptions, rhs: WindowOptions) -> Bool {
        func eqTuple<A: Equatable, B: Equatable>(_ a: (A, B)?, _ b: (A, B)?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case (let x?, let y?): return x.0 == y.0 && x.1 == y.1
            default: return false
            }
        }
        return lhs.transparent == rhs.transparent
            && lhs.borderless == rhs.borderless
            && lhs.clickThrough == rhs.clickThrough
            && lhs.alwaysOnTop == rhs.alwaysOnTop
            && lhs.visible == rhs.visible
            && eqTuple(lhs.position, rhs.position)
            && eqTuple(lhs.physicalSize, rhs.physicalSize)
            && eqTuple(lhs.minSize, rhs.minSize)
            && eqTuple(lhs.maxSize, rhs.maxSize)
            && lhs.resizable == rhs.resizable
    }
}

/// AppKit properties for an ordinary window, reapplied on native recreation.
public struct MacWindowOptions: Sendable, Equatable {
    var shadowFlag: Bool?
    var levelValue: Int?
    var collectionBehaviorBits: UInt?
    var excludeFromCaptureFlag: Bool?
    var nonactivatingPanelFlag: Bool
    var launcher: Bool
    var cornerRadiusValue: Float?
    var cornerCurveCircularFlag: Bool

    public init() {
        self.shadowFlag = nil
        self.levelValue = nil
        self.collectionBehaviorBits = nil
        self.excludeFromCaptureFlag = nil
        self.nonactivatingPanelFlag = false
        self.launcher = false
        self.cornerRadiusValue = nil
        self.cornerCurveCircularFlag = false
    }

    /// Use a key-taking `NSPanel`. Open/focus never activates the app or its other windows.
    public func nonactivatingPanel(_ enabled: Bool) -> MacWindowOptions {
        var copy = self
        copy.nonactivatingPanelFlag = enabled
        if !enabled {
            copy.launcher = false
        }
        return copy
    }

    public func shadow(_ enabled: Bool) -> MacWindowOptions {
        var copy = self
        copy.shadowFlag = enabled
        return copy
    }

    /// AppKit `NSWindow.Level` value (normal 0, floating 3, status 25).
    public func level(_ level: Int) -> MacWindowOptions {
        var copy = self
        copy.levelValue = level
        return copy
    }

    /// AppKit `NSWindow.CollectionBehavior` bit mask. Replaces the existing mask.
    public func collectionBehavior(_ bits: UInt) -> MacWindowOptions {
        var copy = self
        copy.collectionBehaviorBits = bits
        return copy
    }

    /// Requests `NSWindowSharingNone`; `false` restores `NSWindowSharingReadOnly`.
    public func excludeFromCapture(_ exclude: Bool) -> MacWindowOptions {
        var copy = self
        copy.excludeFromCaptureFlag = exclude
        return copy
    }

    /// Rounds a transparent, borderless window or panel to `radius` points with a continuous
    /// (squircle) curve.
    public func cornerRadius(_ radius: Float) -> MacWindowOptions {
        var copy = self
        copy.cornerRadiusValue = max(radius, 0.0)
        return copy
    }

    /// Use a circular corner arc instead of the continuous curve for `cornerRadius`.
    public func cornerCurveCircular() -> MacWindowOptions {
        var copy = self
        copy.cornerCurveCircularFlag = true
        return copy
    }
}

/// Ordinary options plus native builders, accepted by `WindowSpec.configuredOptions`.
public struct ConfiguredWindowOptions: Sendable, Equatable {
    var options: WindowOptions
    var native: MacWindowOptions

    public init(options: WindowOptions = WindowOptions(), native: MacWindowOptions = MacWindowOptions()) {
        self.options = options
        self.native = native
    }

    /// Amends the AppKit settings in place, keeping what a preset already set.
    public func macos(_ amend: (MacWindowOptions) -> MacWindowOptions) -> ConfiguredWindowOptions {
        var copy = self
        copy.native = amend(copy.native)
        return copy
    }
}

/// Specification for one typed window in a multi-window Rune process (`crates/rune/src/windows.rs`).
public struct WindowSpec<S> {
    public var id: String
    public var key: String {
        get { id }
        set { id = newValue }
    }
    public var spec: AppSpec<S>
    var chromeVal: Chrome
    var optionsVal: WindowOptions
    var macosVal: MacWindowOptions
    var handleVal: AppHandle<S>?
    var openOnStart: Bool
    var keepRunningFlag: Bool
    var releaseGpuFlag: Bool
    var srgbBlendFlag: Bool
    var fontSmoothingMode: FontSmoothing
    var fitContentHeightFlag: Bool
    var modifierKeysFlag: Bool
    var tabVisitsControlsFlag: Bool
    var floatOnOpenFlag: Bool

    var cliArgsOverride: [String]? = nil
    var initialStateFn: (() -> S)? = nil
    var onFocusHook: ((inout S, Bool, inout Tx) -> Void)? = nil
    var onImeHook: ((inout S, Ime, inout Tx) -> Bool)? = nil
    var onCloseHook: ((inout S, inout Tx) -> Bool)? = nil
    var onReopenHook: ((inout S, Bool, inout Tx) -> Bool)? = nil
    var onOpenUrlHook: OnOpenUrl<S>? = nil
    var onWindowHook: ((WindowHandle) -> Void)? = nil
    var onReadyHook: ((WindowHandle) -> Void)? = nil
    var onCreatedCallback: ((WindowHandle) -> Void)? = nil
    var frameReports = WindowFrameReports<S>()
    var pendingOverlays: [PendingOverlay] = []
    var secondaryWindows: [AnyWindowSpec] = []
    var attachedPlayground: Any? = nil

    public init(_ id: String, _ spec: AppSpec<S>) {
        self.id = id
        self.spec = spec
        self.chromeVal = .DEFAULT
        self.optionsVal = WindowOptions()
        self.macosVal = MacWindowOptions()
        self.handleVal = nil
        self.openOnStart = true
        self.keepRunningFlag = false
        self.releaseGpuFlag = false
        self.srgbBlendFlag = true
        self.fontSmoothingMode = .default
        self.fitContentHeightFlag = false
        self.modifierKeysFlag = false
        self.tabVisitsControlsFlag = false
        self.floatOnOpenFlag = false
    }

    public static func new(_ id: String, _ spec: AppSpec<S>) -> WindowSpec<S> {
        WindowSpec(id, spec)
    }

    public init(
        key: String,
        app: App<S>,
        options: WindowOptions = WindowOptions(),
        onCreated: ((WindowHandle) -> Void)? = nil
    ) {
        var ws = Self.fromApp(key, app)
        ws.optionsVal = options
        ws.onCreatedCallback = onCreated
        self = ws
    }

    public static func fromApp(_ key: String, _ app: App<S>) -> WindowSpec<S> {
        var ws = WindowSpec(key, app.spec)
        ws.chromeVal = app.chromeSpec
        ws.optionsVal = app.winOptions
        ws.macosVal = app.macWinOptions
        ws.handleVal = app.sharedHandle
        ws.openOnStart = app.openOnStart
        ws.keepRunningFlag = app.keepRunningFlag
        ws.releaseGpuFlag = app.releaseGpuFlag
        ws.srgbBlendFlag = app.srgbBlendFlag
        ws.fontSmoothingMode = app.fontSmoothingMode
        ws.fitContentHeightFlag = app.fitContentHeightFlag
        ws.modifierKeysFlag = app.modifierKeysFlag
        ws.tabVisitsControlsFlag = app.tabVisitsControlsFlag
        ws.floatOnOpenFlag = app.floatOnOpenFlag
        ws.cliArgsOverride = app.cliArgsOverride
        ws.initialStateFn = app.initialStateOverride
        ws.onFocusHook = app.onFocusHook
        ws.onImeHook = app.onImeHook
        ws.onCloseHook = app.onCloseHook
        ws.onReopenHook = app.onReopenHook
        ws.onOpenUrlHook = app.onOpenUrlHook
        ws.onWindowHook = app.onWindowHook
        ws.onReadyHook = app.onReadyHook
        ws.frameReports = app.frameReports
        ws.pendingOverlays = app.pendingOverlays
        ws.secondaryWindows = app.secondaryWindows
        ws.attachedPlayground = app.attachedPlayground
        return ws
    }

    func toApp() -> App<S> {
        let app = App<S>(spec)
        app.chromeSpec = chromeVal
        app.winOptions = optionsVal
        app.macWinOptions = macosVal
        if let h = handleVal {
            app.sharedHandle = h
        }
        app.openOnStart = openOnStart
        app.keepRunningFlag = keepRunningFlag
        app.releaseGpuFlag = releaseGpuFlag
        app.srgbBlendFlag = srgbBlendFlag
        app.fontSmoothingMode = fontSmoothingMode
        app.fitContentHeightFlag = fitContentHeightFlag
        app.modifierKeysFlag = modifierKeysFlag
        app.tabVisitsControlsFlag = tabVisitsControlsFlag
        app.floatOnOpenFlag = floatOnOpenFlag
        app.cliArgsOverride = cliArgsOverride
        app.initialStateOverride = initialStateFn
        app.onFocusHook = onFocusHook
        app.onImeHook = onImeHook
        app.onCloseHook = onCloseHook
        app.onReopenHook = onReopenHook
        app.onOpenUrlHook = onOpenUrlHook
        app.onWindowHook = onWindowHook
        app.onReadyHook = onReadyHook
        app.frameReports = frameReports
        app.pendingOverlays = pendingOverlays
        app.secondaryWindows = secondaryWindows
        app.attachedPlayground = attachedPlayground
        return app
    }

    public func chrome(_ chrome: Chrome) -> WindowSpec<S> {
        var copy = self
        copy.chromeVal = chrome
        return copy
    }

    public func options(_ options: WindowOptions) -> WindowSpec<S> {
        var copy = self
        copy.optionsVal = options
        copy.macosVal = MacWindowOptions()
        return copy
    }

    public func configuredOptions(_ configured: ConfiguredWindowOptions) -> WindowSpec<S> {
        var copy = self
        copy.optionsVal = configured.options
        copy.macosVal = configured.native
        return copy
    }

    public func macos(_ native: MacWindowOptions) -> WindowSpec<S> {
        var copy = self
        copy.macosVal = native
        return copy
    }

    public func handle(_ handle: AppHandle<S>) -> WindowSpec<S> {
        var copy = self
        copy.handleVal = handle
        return copy
    }

    public func windowless() -> WindowSpec<S> {
        var copy = self
        copy.openOnStart = false
        copy.keepRunningFlag = true
        return copy
    }

    public func keepRunning() -> WindowSpec<S> {
        var copy = self
        copy.keepRunningFlag = true
        return copy
    }

    public func releaseGpuWhenClosed() -> WindowSpec<S> {
        var copy = self
        copy.releaseGpuFlag = true
        return copy
    }

    public func srgbBlend(_ enabled: Bool) -> WindowSpec<S> {
        var copy = self
        copy.srgbBlendFlag = enabled
        return copy
    }

    public func fontSmoothing(_ mode: FontSmoothing) -> WindowSpec<S> {
        var copy = self
        copy.fontSmoothingMode = mode
        return copy
    }

    public func fitContentHeight() -> WindowSpec<S> {
        var copy = self
        copy.fitContentHeightFlag = true
        return copy
    }

    public func modifierKeys() -> WindowSpec<S> {
        var copy = self
        copy.modifierKeysFlag = true
        return copy
    }

    public func tabVisitsControls(_ on: Bool) -> WindowSpec<S> {
        var copy = self
        copy.tabVisitsControlsFlag = on
        return copy
    }

    public func floatOnOpen() -> WindowSpec<S> {
        var copy = self
        copy.floatOnOpenFlag = true
        return copy
    }

    public func state(_ state: S) -> WindowSpec<S> {
        var copy = self
        copy.initialStateFn = { state }
        return copy
    }

    public func initState(_ f: @escaping () -> S) -> WindowSpec<S> {
        var copy = self
        copy.initialStateFn = f
        return copy
    }

    public func onFocus(_ f: @escaping (inout S, Bool, inout Tx) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onFocusHook = f
        return copy
    }

    public func onIme(_ f: @escaping (inout S, Ime, inout Tx) -> Bool) -> WindowSpec<S> {
        var copy = self
        copy.onImeHook = f
        return copy
    }

    public func onClose(_ f: @escaping (inout S, inout Tx) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onCloseHook = { state, tx in
            f(&state, &tx)
            return true
        }
        return copy
    }

    public func onClose(_ f: @escaping (inout S, inout Tx) -> Bool) -> WindowSpec<S> {
        var copy = self
        copy.onCloseHook = f
        return copy
    }

    public func onReopen(_ f: @escaping (inout S, Bool, inout Tx) -> Bool) -> WindowSpec<S> {
        var copy = self
        copy.onReopenHook = f
        return copy
    }

    public func onOpenUrl(_ f: @escaping @Sendable (inout S, String, inout Tx) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onOpenUrlHook = f
        return copy
    }

    public func onFrameEncoded(_ f: @escaping (WindowFrameEncoded) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.frameReports.encoded = { _, enc in f(enc) }
        return copy
    }

    public func onWindow(_ f: @escaping (WindowHandle) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onWindowHook = f
        return copy
    }

    public func onReady(_ f: @escaping (WindowHandle) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onReadyHook = f
        return copy
    }

    public func onCreated(_ callback: @escaping (WindowHandle) -> Void) -> WindowSpec<S> {
        var copy = self
        copy.onCreatedCallback = callback
        return copy
    }

    public func overlay<T>(_ spec: OverlaySpec<T>, _ initState: @escaping () -> T) -> (WindowSpec<S>, OverlayHandle<T>) {
        overlay(ConfiguredOverlay(spec: spec), initState)
    }

    public func overlay<T>(_ configured: ConfiguredOverlay<T>, _ initState: @escaping () -> T) -> (WindowSpec<S>, OverlayHandle<T>) {
        var copy = self
        let h = OverlayHandle<T>()
        copy.pendingOverlays.append(PendingOverlay(configured: configured, initState: initState, handle: h))
        return (copy, h)
    }

    func buildHost(windowHandle: WindowHandle? = nil, secondary: Bool = false) -> Host<S> {
        let h = handleVal ?? AppHandle<S>()
        h.shortcutHub.named(spec.title)
        let wh = windowHandle ?? WindowHandle(id)
        let host = Host<S>(
            spec: spec,
            state: initialStateFn?(),
            chrome: chromeVal,
            options: optionsVal,
            macOptions: macosVal,
            handle: h,
            windowHandle: wh,
            openOnStart: openOnStart,
            keepRunning: keepRunningFlag || secondary,
            secondary: secondary,
            releaseGpuWhenClosed: releaseGpuFlag,
            accessory: false,
            standardMenus: false,
            srgbBlend: srgbBlendFlag,
            fontSmoothing: fontSmoothingMode,
            fitContentHeight: fitContentHeightFlag,
            modifierKeys: modifierKeysFlag,
            tabVisitsControls: tabVisitsControlsFlag,
            floatOnOpen: floatOnOpenFlag,
            playground: attachedPlayground
        )
        host.reports = frameReports
        host.onFocusHook = onFocusHook
        host.onImeHook = onImeHook
        host.onCloseHook = onCloseHook
        host.onReopenHook = onReopenHook
        host.onOpenUrlHook = onOpenUrlHook
        host.onWindowHook = onWindowHook
        host.onReadyHook = onReadyHook
        host.onCreatedCallback = onCreatedCallback
        host.pendingOverlays = pendingOverlays
        return host
    }

    public func boxed() -> AnyWindowSpec {
        AnyWindowSpec.single(self)
    }

    public func intoAny() -> AnyWindowSpec {
        AnyWindowSpec.single(self)
    }
}

/// Type-erased window or group of windows for `runWindows` and `App.window` (`crates/rune/src/windows.rs`).
public struct AnyWindowSpec {
    public let id: String
    public let title: String
    let isGroup: Bool
    let secondary: Bool
    let cliArgsOverride: [String]?
    let children: [AnyWindowSpec]
    private let hostBuilder: (() -> any AnyHost)?
    private let desktopBuilder: ((VirtualDesktop) -> any DesktopMember)?
    private let headlessRunner: ((Args, Float) -> Void)?
    private let desktopCliBuilder: ((Args, Bool, Float) -> any DesktopCliMember)?

    private init(
        id: String,
        title: String,
        isGroup: Bool,
        secondary: Bool,
        cliArgsOverride: [String]?,
        children: [AnyWindowSpec],
        hostBuilder: (() -> any AnyHost)?,
        desktopBuilder: ((VirtualDesktop) -> any DesktopMember)?,
        headlessRunner: ((Args, Float) -> Void)? = nil,
        desktopCliBuilder: ((Args, Bool, Float) -> any DesktopCliMember)? = nil
    ) {
        self.id = id
        self.title = title
        self.isGroup = isGroup
        self.secondary = secondary
        self.cliArgsOverride = cliArgsOverride
        self.children = children
        self.hostBuilder = hostBuilder
        self.desktopBuilder = desktopBuilder
        self.headlessRunner = headlessRunner
        self.desktopCliBuilder = desktopCliBuilder
    }

    public func key() -> String {
        id
    }

    public static func single<S>(_ windowSpec: WindowSpec<S>) -> AnyWindowSpec {
        AnyWindowSpec(
            id: windowSpec.id,
            title: windowSpec.spec.title,
            isGroup: false,
            secondary: false,
            cliArgsOverride: windowSpec.cliArgsOverride,
            children: windowSpec.secondaryWindows,
            hostBuilder: { windowSpec.buildHost(windowHandle: WindowHandle(windowSpec.id), secondary: false) },
            desktopBuilder: { desktop in
                DesktopWindow(
                    id: windowSpec.id,
                    host: windowSpec.buildHost(windowHandle: WindowHandle(windowSpec.id), secondary: false),
                    desktop: desktop
                )
            },
            headlessRunner: { args, defaultScale in
                let app = windowSpec.toApp()
                let scale = args.scale ?? defaultScale
                if let (pw, ph) = windowSpec.optionsVal.physicalSize {
                    app.spec.size = (Float(pw) / scale, Float(ph) / scale)
                }
                headlessConfigured(app, args, transparent: windowSpec.optionsVal.transparent)
            },
            desktopCliBuilder: { args, selected, scale in
                DesktopCliWindow(
                    spec: windowSpec,
                    handle: nil,
                    args: args,
                    selected: selected,
                    main: true,
                    scale: scale
                )
            }
        )
    }

    static func secondary<S>(_ windowSpec: WindowSpec<S>, handle: WindowHandle) -> AnyWindowSpec {
        AnyWindowSpec(
            id: windowSpec.id,
            title: windowSpec.spec.title,
            isGroup: false,
            secondary: true,
            cliArgsOverride: windowSpec.cliArgsOverride,
            children: windowSpec.secondaryWindows,
            hostBuilder: { windowSpec.buildHost(windowHandle: handle, secondary: true) },
            desktopBuilder: { desktop in
                DesktopWindow(
                    id: windowSpec.id,
                    host: windowSpec.buildHost(windowHandle: handle, secondary: true),
                    desktop: desktop
                )
            },
            headlessRunner: { args, defaultScale in
                let app = windowSpec.toApp()
                let scale = args.scale ?? defaultScale
                if let (pw, ph) = windowSpec.optionsVal.physicalSize {
                    app.spec.size = (Float(pw) / scale, Float(ph) / scale)
                }
                headlessConfigured(app, args, transparent: windowSpec.optionsVal.transparent)
            },
            desktopCliBuilder: { args, selected, scale in
                DesktopCliWindow(
                    spec: windowSpec,
                    handle: handle,
                    args: args,
                    selected: selected,
                    main: false,
                    scale: scale
                )
            }
        )
    }

    public static func group(_ specs: [AnyWindowSpec]) -> AnyWindowSpec {
        AnyWindowSpec(
            id: "",
            title: "",
            isGroup: true,
            secondary: false,
            cliArgsOverride: nil,
            children: specs,
            hostBuilder: nil,
            desktopBuilder: nil
        )
    }

    func withoutChildren() -> AnyWindowSpec {
        AnyWindowSpec(
            id: id,
            title: title,
            isGroup: isGroup,
            secondary: secondary,
            cliArgsOverride: cliArgsOverride,
            children: [],
            hostBuilder: hostBuilder,
            desktopBuilder: desktopBuilder,
            headlessRunner: headlessRunner,
            desktopCliBuilder: desktopCliBuilder
        )
    }

    func resolveToolingArgs(_ inherited: Args) -> Args {
        if let argv = cliArgsOverride {
            return Args.parseFrom(argv)
        }
        return inherited
    }

    func runHeadless(args: Args, defaultScale: Float) {
        guard let headlessRunner else {
            preconditionFailure("AnyWindowSpec.group must be flattened before runHeadless()")
        }
        headlessRunner(args, defaultScale)
    }

    func buildDesktopCliMember(args: Args, selected: Bool, scale: Float) -> any DesktopCliMember {
        guard let desktopCliBuilder else {
            preconditionFailure("AnyWindowSpec.group must be flattened before buildDesktopCliMember()")
        }
        return desktopCliBuilder(args, selected, scale)
    }

    func buildHost() -> any AnyHost {
        guard let hostBuilder else {
            preconditionFailure("AnyWindowSpec.group must be flattened before buildHost()")
        }
        return hostBuilder()
    }

    func buildDesktopMember(_ desktop: VirtualDesktop) -> any DesktopMember {
        guard let desktopBuilder else {
            preconditionFailure("AnyWindowSpec.group must be flattened before buildDesktopMember()")
        }
        return desktopBuilder(desktop)
    }
}

public enum WindowValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyList
    case emptyId
    case duplicateId(String)

    public var description: String {
        switch self {
        case .emptyList:
            return "run_windows requires at least one window"
        case .emptyId:
            return "window id must not be empty"
        case .duplicateId(let id):
            return "duplicate window id '\(id)'"
        }
    }
}

/// Flattens groups and appends each window's secondary `App.window(...)` children depth-first.
func flattenWindowSpecs(_ specs: [AnyWindowSpec]) -> [AnyWindowSpec] {
    var out: [AnyWindowSpec] = []
    for item in specs {
        if item.isGroup {
            out.append(contentsOf: flattenWindowSpecs(item.children))
        } else {
            out.append(item.withoutChildren())
            if !item.children.isEmpty {
                out.append(contentsOf: flattenWindowSpecs(item.children))
            }
        }
    }
    return out
}

func validateWindowSpecs(_ flat: [AnyWindowSpec]) throws(WindowValidationError) {
    guard !flat.isEmpty else {
        throw .emptyList
    }
    var seen = Set<String>()
    for spec in flat {
        let trimmed = spec.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw .emptyId
        }
        if !seen.insert(spec.id).inserted {
            throw .duplicateId(spec.id)
        }
    }
}

/// Namespace mirroring `rune::windows` (`crates/rune/src/windows.rs`).
public enum windows {
    public typealias Display = Rune.Display
    public typealias RunOptions = Rune.RunOptions
    public typealias WindowOptions = Rune.WindowOptions
    public typealias MacWindowOptions = Rune.MacWindowOptions
    public typealias ConfiguredWindowOptions = Rune.ConfiguredWindowOptions
    public typealias WindowSpec = Rune.WindowSpec
    public typealias AnyWindowSpec = Rune.AnyWindowSpec
}
