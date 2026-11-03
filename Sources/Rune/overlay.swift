// Ported from: crates/rune/src/overlay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Overlays: surfaces beside the app's window (a recording HUD, meeting capsules) (`crates/rune/src/overlay.rs`).

#if !os(WASI)
import Foundation
#endif

/// The screen edge an overlay sits on.
public enum ScreenEdge: Sendable, Equatable, Hashable {
    case top
    case bottom

    public init() {
        self = .top
    }

    public static let Top: ScreenEdge = .top
    public static let Bottom: ScreenEdge = .bottom
}

/// Specification for a native overlay surface.
public struct OverlaySpec<T> {
    /// The window title, or the layer-shell namespace on Wayland.
    public var name: String
    /// In points.
    public var size: (Float, Float)
    public var edge: ScreenEdge
    /// Distance from the edge, in points.
    public var margin: Float
    /// Along the edge: centred, or at the start (left) or end (right) `inset` points in.
    public var align: Align
    public var inset: Float
    /// Clicks reach the view (meeting capsule buttons); otherwise they pass through.
    public var interactive: Bool
    /// The overlay's view. Its root should have no fill: whatever it leaves clear stays
    /// transparent.
    public var view: (T, Cx<T>) -> El

    public init(
        name: String,
        size: (Float, Float),
        edge: ScreenEdge = .top,
        margin: Float = 0.0,
        align: Align = .center,
        inset: Float = 0.0,
        interactive: Bool = false,
        view: @escaping (T, Cx<T>) -> El
    ) {
        self.name = name
        self.size = size
        self.edge = edge
        self.margin = margin
        self.align = align
        self.inset = inset
        self.interactive = interactive
        self.view = view
    }

    public func poll(_ f: @escaping (inout T, Double, inout Tx) -> Bool) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).poll(f)
    }

    public func onKey(_ f: @escaping (inout T, KeyEvent, inout Tx) -> Bool) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).onKey(f)
    }

    public func onFocus(_ f: @escaping (inout T, Bool, inout Tx) -> Void) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).onFocus(f)
    }

    public func setup(_ f: @escaping (inout T, @escaping Waker) -> Void) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).setup(f)
    }

    public func modifierKeys() -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).modifierKeys()
    }

    public func animateReveal() -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).animateReveal()
    }

    public func srgbBlend(_ enabled: Bool) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).srgbBlend(enabled)
    }

    public func macosLevel(_ level: Int) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).macosLevel(level)
    }

    public func onCreated(_ f: @escaping (OverlayCreated) -> Void) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self).onCreated(f)
    }
}

/// Whether the platform could show the overlay, known after its first `show`.
public enum Availability: Sendable, Equatable, Hashable {
    case unknown
    case available
    /// Wayland without layer-shell, or its window, surface or show failed (`OverlayHandle.failure`).
    case unavailable

    public static let Unknown: Availability = .unknown
    public static let Available: Availability = .available
    public static let Unavailable: Availability = .unavailable
}

/// Where an overlay sits and how big it is, in points.
struct OverlayPlacementSpec: Sendable, Equatable {
    var size: (Float, Float)
    var edge: ScreenEdge
    var margin: Float
    var align: Align
    var inset: Float

    init(
        size: (Float, Float),
        edge: ScreenEdge = .top,
        margin: Float = 0.0,
        align: Align = .center,
        inset: Float = 0.0
    ) {
        self.size = size
        self.edge = edge
        self.margin = margin
        self.align = align
        self.inset = inset
    }

    static func == (lhs: OverlayPlacementSpec, rhs: OverlayPlacementSpec) -> Bool {
        lhs.size.0 == rhs.size.0
            && lhs.size.1 == rhs.size.1
            && lhs.edge == rhs.edge
            && lhs.margin == rhs.margin
            && lhs.align == rhs.align
            && lhs.inset == rhs.inset
    }
}

/// Thread-safe handle returned by `App.overlay` (`crates/rune/src/overlay.rs`).
// PORT NOTE: Synchronized via `OverlaySharedState` (`LiveLock`), matching `Arc<Shared<T>>` in `crates/rune/src/overlay.rs`.
public final class OverlayHandle<T>: @unchecked Sendable {
    let shared = OverlaySharedState<T>()

    public init() {}

    func connect(_ waker: @escaping Waker) {
        shared.lock.withLock {
            shared.waker = waker
        }
    }

    public func wake() {
        let w = shared.lock.withLock { () -> Waker? in
            shared.woken = true
            return shared.waker
        }
        w?()
    }

    public func show() {
        enqueue(.show)
    }

    public func hide() {
        enqueue(.hide)
    }

    /// Destroys the native overlay surface and releases its GPU resources. A subsequent `show()` recreates it.
    public func close() {
        enqueue(.close)
    }

    public func isVisible() -> Bool {
        shared.lock.withLock { shared.visibleSnapshot }
    }

    public func availability() -> Availability {
        shared.lock.withLock { shared.availabilitySnapshot }
    }

    public func failure() -> String? {
        shared.lock.withLock { shared.failureSnapshot }
    }

    public func capabilities() -> OverlayCapabilities {
        shared.lock.withLock { shared.capabilitiesSnapshot }
    }

    public func windowNumber() -> UInt32? {
        shared.lock.withLock { shared.windowNumberSnapshot }
    }

    public func setSize(_ width: Float, _ height: Float) {
        enqueue(.setSize(max(width, 1.0), max(height, 1.0)))
    }

    public func setPlacement(_ placement: OverlayPlacement?) {
        enqueue(.setPlacement(placement))
    }

    public func setDisplay(_ display: DisplayTarget) {
        enqueue(.setDisplay(display))
    }

    public func setFollowPointer(_ follow: Bool) {
        enqueue(.setFollowPointer(follow))
    }

    public func setLevel(_ level: OverlayLevel) {
        enqueue(.setLevel(level))
    }

    public func setMacosLevel(_ level: Int?) {
        enqueue(.setMacosLevel(level))
    }

    public func setExcludeFromCapture(_ exclude: Bool) {
        enqueue(.setExcludeFromCapture(exclude))
    }

    public func setInput(_ input: OverlayInput) {
        enqueue(.setInput(input))
    }

    public func requestKeys() {
        enqueue(.requestKeys)
    }

    public func releaseKeys() {
        enqueue(.releaseKeys)
    }

    public func update(_ f: @escaping @Sendable (inout T, inout Tx) -> Void) {
        let w = shared.lock.withLock { () -> Waker? in
            shared.updates.append { state, tx in
                f(&state, &tx)
                return true
            }
            return shared.waker
        }
        w?()
    }

    public func updateIf(_ f: @escaping @Sendable (inout T, inout Tx) -> Bool) {
        let w = shared.lock.withLock { () -> Waker? in
            shared.updates.append(f)
            return shared.waker
        }
        w?()
    }

    private func enqueue(_ cmd: OverlayCommand) {
        let w = shared.lock.withLock { () -> Waker? in
            switch cmd {
            case .show:
                shared.visibleSnapshot = true
            case .hide, .close:
                shared.visibleSnapshot = false
            default:
                break
            }
            shared.commands.append(cmd)
            return shared.waker
        }
        w?()
    }
}

/// Concrete runtime and surface state for one overlay (`crates/rune/src/overlay.rs`).
final class Overlay<T> {
    var name: String
    var at: OverlayPlacementSpec
    var interactive: Bool
    var options: OverlayOptions
    let rt: Runtime<T>
    let handle: OverlayHandle<T>

    var window: NativeWindow? = nil
    var config = WindowSurfaceConfig(transparent: true)
    var surfaceMeter = WindowSurfaceMeter()
    var presented = WindowPresented()
    var clock = HostFrameClock()
    var hiddenPace = HiddenPace()

    var macosLevelOverride: Int?
    var retainSurface: Bool
    var animateReveal: Bool
    var modifierKeys: Bool
    var onFocus: ((inout T, Bool, inout Tx) -> Void)?
    var onCreated: ((OverlayCreated) -> Void)?
    var setupFn: ((inout T, @escaping Waker) -> Void)?
    var compositorRender: ((Runtime<T>, Renderer) -> Void)?
    var compositorAnimating: (() -> Bool)?

    var visible: Bool = false
    var keysActive: Bool = false
    var passthrough: Bool = true
    var pendingInput: OverlayInput? = nil
    var hitRects: [[Float]] = []
    var createdNotified: Bool = false
    var simulatedUnavailableError: String? = nil
    var simulatedPointer: (Int32, Int32)? = nil
    var drawCount: Int = 0

    init(
        configured: ConfiguredOverlay<T>,
        initialState: T,
        handle: OverlayHandle<T> = OverlayHandle<T>(),
        retainSurface: Bool = false
    ) {
        let spec = configured.spec
        self.name = spec.name
        self.at = OverlayPlacementSpec(
            size: (max(spec.size.0, 1.0), max(spec.size.1, 1.0)),
            edge: spec.edge,
            margin: spec.margin,
            align: spec.align,
            inset: spec.inset
        )
        self.interactive = spec.interactive
        self.options = configured.options
        self.handle = handle
        self.macosLevelOverride = configured.macosLevel
        self.retainSurface = retainSurface || configured.options.prewarm
        self.animateReveal = configured.animateRevealFlag
        self.modifierKeys = configured.modifierKeysFlag
        self.onFocus = configured.onFocus
        self.onCreated = configured.onCreated
        self.setupFn = configured.setup
        self.compositorRender = configured.compositorRender
        self.compositorAnimating = configured.compositorAnimating

        let env = Env(systemDark: true, scale: 1.0)
        let runtime = Runtime(initialState, spec.view, (self.at.size.0, self.at.size.1), env)
        runtime.transparent = true
        runtime.srgbBlend = configured.srgbBlend
        runtime.poll = configured.poll
        runtime.onKey = configured.onKey
        runtime.hostSetLiveVisible(false)
        self.rt = runtime
    }
}

/// Type-erased pending overlay registration queued on `App<S>` before startup (`crates/rune/src/overlay.rs`).
struct PendingOverlay {
    private let mountFn: (Int, [Display]) -> any AnyOverlayHost

    init<T>(
        configured: ConfiguredOverlay<T>,
        initState: @escaping () -> T,
        handle: OverlayHandle<T>,
        retainSurface: Bool = false
    ) {
        self.mountFn = { _, displays in
            let ov = Overlay(
                configured: configured,
                initialState: initState(),
                handle: handle,
                retainSurface: retainSurface
            )
            ov.startOverlay(displays: displays)
            return ov
        }
    }

    func mount(hostIndex: Int, displays: [Display]) -> any AnyOverlayHost {
        mountFn(hostIndex, displays)
    }
}
