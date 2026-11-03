// Ported from: crates/rune/src/overlay/options.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Placement and input policy for native overlays. Coordinates inside a display are points.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Android)
import Android
#elseif canImport(Musl)
import Musl
#elseif os(Windows)
import ucrt
#elseif os(WASI)
import WASILibc
#endif

/// An opaque display identity, valid for this event-loop session. Obtain it from `Display.id`.
public struct DisplayId: Sendable, Equatable, Hashable {
    let monitorToken: UInt64
    let native: NativeDisplayId?

    init(monitorToken: UInt64, native: NativeDisplayId?) {
        self.monitorToken = monitorToken
        self.native = native
    }

    public func nativeId() -> NativeDisplayId? {
        native
    }
}

/// Native display identity. Windows handles retain their full pointer width.
public enum NativeDisplayId: Sendable, Equatable, Hashable {
    case macOS(UInt32)
    case windows(Int)
    /// X11 monitors identified by RandR CRTC. Output IDs can also be targeted below.
    case x11Crtc(UInt32)
    case x11Output(UInt32)
    /// Registry-global `wl_output` name, not a client-local protocol object ID.
    case wayland(UInt32)

    public static func MacOS(_ id: UInt32) -> NativeDisplayId { .macOS(id) }
    public static func Windows(_ id: Int) -> NativeDisplayId { .windows(id) }
    public static func X11Crtc(_ id: UInt32) -> NativeDisplayId { .x11Crtc(id) }
    public static func X11Output(_ id: UInt32) -> NativeDisplayId { .x11Output(id) }
    public static func Wayland(_ id: UInt32) -> NativeDisplayId { .wayland(id) }
}

public enum DisplayTarget: Sendable, Equatable, Hashable {
    case primary
    case underPointer
    case id(DisplayId)
    /// Resolve a native capture/display ID; disconnected IDs fall back to primary.
    case native(NativeDisplayId)

    public init() {
        self = .primary
    }

    public static let Primary: DisplayTarget = .primary
    public static let UnderPointer: DisplayTarget = .underPointer
    public static func Id(_ id: DisplayId) -> DisplayTarget { .id(id) }
    public static func Native(_ id: NativeDisplayId) -> DisplayTarget { .native(id) }
}

public enum OverlayPlacement: Sendable, Equatable {
    case edge(edge: ScreenEdge, margin: Float, align: Align, inset: Float)
    /// Points from the selected display's top-left, not desktop pixels. The rect isn't kept
    /// on that display, so on `DisplayTarget.primary` it's a global rect that may sit on
    /// any display: the space `El.onScreenLayout` reports in, so an overlay can open
    /// exactly over an element of a window. On macOS one point space spans displays of any
    /// scale, and the overlay draws at the backing scale of the display it lands on.
    /// Elsewhere a rect off the primary display is exact only where displays share a scale.
    case rect(x: Float, y: Float, width: Float, height: Float)
    case fullScreen

    public static let FullScreen: OverlayPlacement = .fullScreen
}

public enum OverlayLevel: Sendable, Equatable, Hashable {
    case status
    case aboveStatus
    /// Above Rune's status and picker overlays (macOS level 27).
    case aboveOverlays

    public init() {
        self = .status
    }

    public static let Status: OverlayLevel = .status
    public static let AboveStatus: OverlayLevel = .aboveStatus
    public static let AboveOverlays: OverlayLevel = .aboveOverlays
}

public enum KeyPolicy: Sendable, Equatable, Hashable {
    case none
    /// Permit `OverlayHandle.requestKeys`; showing alone never requests focus.
    case onDemand

    public init() {
        self = .none
    }

    public static let None: KeyPolicy = .none
    public static let OnDemand: KeyPolicy = .onDemand
}

public enum OverlayInput: Sendable, Equatable, Hashable {
    /// Preserve `OverlaySpec.interactive` (whole surface or complete pass-through).
    case legacy
    /// Pass every click through, and hear no hover. Following remains available when enabled;
    /// use `.regions` without `.hit()` elements for a hover-only canvas.
    case none
    /// Only elements marked `El.hit()` intercept the pointer.
    case regions
    case all

    public init() {
        self = .legacy
    }

    func resolved(_ interactive: Bool) -> OverlayInput {
        switch self {
        case .legacy:
            return interactive ? .all : .none
        default:
            return self
        }
    }

    public static let Legacy: OverlayInput = .legacy
    public static let None: OverlayInput = .none
    public static let Regions: OverlayInput = .regions
    public static let All: OverlayInput = .all
}

/// An overlay shows its elements' `Cursor`s while the pointer is over a hit
/// area (with `OverlayInput.regions`, a hit region). On macOS that works for a non-key
/// overlay only while its app is frontmost, unless built with background-cursor support.
public struct OverlayOptions: Sendable, Equatable {
    /// `nil` preserves the spec's edge, margin, alignment and inset.
    public var placement: OverlayPlacement?
    public var display: DisplayTarget
    /// Re-resolve `.underPointer` while visible. Unsupported on Wayland.
    public var followPointer: Bool
    public var level: OverlayLevel
    /// Native best effort, not a security boundary. Use the window number in capture filters.
    /// Applies only while the overlay is shown.
    /// `OverlayHandle.setExcludeFromCapture` changes it later.
    public var excludeFromCapture: Bool
    public var keys: KeyPolicy
    public var input: OverlayInput
    /// Create and warm a hidden native host on the event thread at startup.
    public var prewarm: Bool

    public init(
        placement: OverlayPlacement? = nil,
        display: DisplayTarget = .primary,
        followPointer: Bool = false,
        level: OverlayLevel = .status,
        excludeFromCapture: Bool = false,
        keys: KeyPolicy = .none,
        input: OverlayInput = .legacy,
        prewarm: Bool = false
    ) {
        self.placement = placement
        self.display = display
        self.followPointer = followPointer
        self.level = level
        self.excludeFromCapture = excludeFromCapture
        self.keys = keys
        self.input = input
        self.prewarm = prewarm
    }
}

/// Keeps existing exhaustive `OverlaySpec` literals source compatible.
public struct ConfiguredOverlay<T> {
    public var spec: OverlaySpec<T>
    public var options: OverlayOptions
    public var onKey: ((inout T, KeyEvent, inout Tx) -> Bool)?
    public var onCreated: ((OverlayCreated) -> Void)?
    var poll: ((inout T, Double, inout Tx) -> Bool)?
    var onFocus: ((inout T, Bool, inout Tx) -> Void)?
    var compositorRender: ((Runtime<T>, Renderer) -> Void)?
    var compositorAnimating: (() -> Bool)?
    var setup: ((inout T, @escaping Waker) -> Void)?
    var srgbBlend: Bool
    var macosLevel: Int?
    var modifierKeysFlag: Bool
    var animateRevealFlag: Bool

    public init(spec: OverlaySpec<T>, options: OverlayOptions = OverlayOptions()) {
        self.spec = spec
        self.options = options
        self.onKey = nil
        self.onCreated = nil
        self.poll = nil
        self.onFocus = nil
        self.compositorRender = nil
        self.compositorAnimating = nil
        self.setup = nil
        self.srgbBlend = true
        self.macosLevel = nil
        self.modifierKeysFlag = false
        self.animateRevealFlag = false
    }

    public func onFocus(_ f: @escaping (inout T, Bool, inout Tx) -> Void) -> ConfiguredOverlay<T> {
        var copy = self
        copy.onFocus = f
        return copy
    }

    /// Composite this overlay's translucent fills, blurs, shadows, images, video and text in
    /// sRGB (gamma) space instead of linear light, matching CSS and Core Animation (on by default).
    public func srgbBlend(_ enabled: Bool) -> ConfiguredOverlay<T> {
        var copy = self
        copy.srgbBlend = enabled
        return copy
    }

    /// Called before each frame; true means state changed, not that another frame is due.
    public func poll(_ f: @escaping (inout T, Double, inout Tx) -> Bool) -> ConfiguredOverlay<T> {
        var copy = self
        copy.poll = f
        return copy
    }

    /// Draw every rendered overlay frame, including hidden prewarm frames, through this
    /// compositor callback.
    // PORT NOTE: Accepts closure callbacks rather than `any Compositor<T>` while `compose.swift` is owned by a sibling worker.
    public func compositor(
        _ render: @escaping (Runtime<T>, Renderer) -> Void,
        animating: @escaping () -> Bool = { false }
    ) -> ConfiguredOverlay<T> {
        var copy = self
        copy.compositorRender = render
        copy.compositorAnimating = animating
        return copy
    }

    public func onKey(_ f: @escaping (inout T, KeyEvent, inout Tx) -> Bool) -> ConfiguredOverlay<T> {
        var copy = self
        copy.onKey = f
        return copy
    }

    /// Like `App.modifierKeys`: send modifier keys pressed and released on their own
    /// (`Key.modifier`) to `onKey` and the focused input. Off by default.
    public func modifierKeys() -> ConfiguredOverlay<T> {
        var copy = self
        copy.modifierKeysFlag = true
        return copy
    }

    /// Like `AppSpec.setup`: called once with a waker other threads use when new data arrives.
    public func setup(_ f: @escaping (inout T, @escaping Waker) -> Void) -> ConfiguredOverlay<T> {
        var copy = self
        copy.setup = f
        return copy
    }

    /// Called once on the event thread after native creation, before the first show.
    public func onCreated(_ f: @escaping (OverlayCreated) -> Void) -> ConfiguredOverlay<T> {
        var copy = self
        copy.onCreated = f
        return copy
    }

    /// Showing doesn't settle motion: what the state started while hidden plays from the
    /// first visible frame. By default an unretained overlay shows settled, at its target.
    public func animateReveal() -> ConfiguredOverlay<T> {
        var copy = self
        copy.animateRevealFlag = true
        return copy
    }

    /// The macOS window level (`NSWindow.Level`, e.g. 3 for `.floating`), in place of
    /// `OverlayOptions.level`; `OverlayHandle.setMacosLevel` changes it later.
    public func macosLevel(_ level: Int) -> ConfiguredOverlay<T> {
        var copy = self
        copy.macosLevel = level
        return copy
    }
}

public struct OverlayCreated: Sendable, Equatable {
    /// The actual macOS panel `CGWindowID`, available before its first show.
    public var windowNumber: UInt32?
    public var capabilities: OverlayCapabilities

    public init(windowNumber: UInt32? = nil, capabilities: OverlayCapabilities = OverlayCapabilities()) {
        self.windowNumber = windowNumber
        self.capabilities = capabilities
    }
}

extension OverlaySpec {
    public static func new(
        _ name: String,
        _ size: (Float, Float),
        _ view: @escaping (T, Cx<T>) -> El
    ) -> OverlaySpec<T> {
        OverlaySpec(
            name: name,
            size: size,
            edge: .top,
            margin: 0.0,
            align: .center,
            inset: 0.0,
            interactive: false,
            view: view
        )
    }

    public func options(_ options: OverlayOptions) -> ConfiguredOverlay<T> {
        ConfiguredOverlay(spec: self, options: options)
    }
}

/// Native capability, distinct from whether an overlay could be created.
public enum OverlaySupport: Sendable, Equatable, Hashable {
    case unknown
    case supported
    /// The OS accepted a capture-exclusion request; capture clients may still need a filter.
    case requested
    case unsupported
    case failed

    public init() {
        self = .unknown
    }

    public static let Unknown: OverlaySupport = .unknown
    public static let Supported: OverlaySupport = .supported
    public static let Requested: OverlaySupport = .requested
    public static let Unsupported: OverlaySupport = .unsupported
    public static let Failed: OverlaySupport = .failed
}

public struct OverlayCapabilities: Sendable, Equatable, Hashable {
    public var captureExclusion: OverlaySupport
    public var nonactivatingKeys: OverlaySupport
    public var globalPointer: OverlaySupport

    public init(
        captureExclusion: OverlaySupport = .unknown,
        nonactivatingKeys: OverlaySupport = .unknown,
        globalPointer: OverlaySupport = .unknown
    ) {
        self.captureExclusion = captureExclusion
        self.nonactivatingKeys = nonactivatingKeys
        self.globalPointer = globalPointer
    }
}

/// Bounds in logical points, local to a display. Also shared by native placement tests.
func overlayLocalRect(
    _ at: OverlayPlacementSpec,
    _ placement: OverlayPlacement?,
    _ area: (Float, Float)
) -> [Float] {
    let edge: ScreenEdge
    let margin: Float
    let align: Align
    let inset: Float
    switch placement {
    case .fullScreen:
        return [0.0, 0.0, area.0, area.1]
    case .rect(let x, let y, let width, let height):
        return [x, y, max(width, 1.0), max(height, 1.0)]
    case .edge(let e, let m, let a, let i):
        edge = e
        margin = m
        align = a
        inset = i
    case nil:
        edge = at.edge
        margin = at.margin
        align = at.align
        inset = at.inset
    }
    let w = max(at.size.0, 1.0)
    let h = max(at.size.1, 1.0)
    let x: Float
    switch align {
    case .start:
        x = inset
    case .center:
        x = (area.0 - w) / 2.0
    case .end:
        x = area.0 - w - inset
    }
    let y: Float
    switch edge {
    case .top:
        y = margin
    case .bottom:
        y = area.1 - h - margin
    }
    return [x, y, w, h]
}

func overlayContains(_ rect: [Float], _ x: Float, _ y: Float) -> Bool {
    guard rect.count >= 4 else { return false }
    return x >= rect[0] && y >= rect[1] && x < rect[2] && y < rect[3]
}

/// Bounds and pointer share one native coordinate space. Never rescale desktop origins.
func overlayChooseDisplay(
    _ bounds: [[Double]],
    _ primary: Int?,
    _ requested: Int?,
    _ pointer: (Double, Double)?
) -> Int? {
    if let r = requested, r >= 0 && r < bounds.count {
        return r
    }
    if let (x, y) = pointer {
        if let idx = bounds.firstIndex(where: { r in
            r.count >= 4 && x >= r[0] && y >= r[1] && x < r[2] && y < r[3]
        }) {
            return idx
        }
    }
    if let p = primary, p >= 0 && p < bounds.count {
        return p
    }
    return bounds.isEmpty ? nil : 0
}

/// The scale of the display holding most of `frame` (`[x, y, w, h]`), as AppKit picks a
/// window's backing scale; `nil` when it's on none. `displays` are `(frame, scale)` in the
/// same space.
func overlayScaleUnder(_ frame: [Double], _ displays: [([Double], Double)]) -> Double? {
    guard frame.count >= 4 else { return nil }
    func overlap(_ d: [Double]) -> Double {
        guard d.count >= 4 else { return 0.0 }
        let w = min(frame[0] + frame[2], d[0] + d[2]) - max(frame[0], d[0])
        let h = min(frame[1] + frame[3], d[1] + d[3]) - max(frame[1], d[1])
        return max(w, 0.0) * max(h, 0.0)
    }
    var bestArea: Double = 0.0
    var bestScale: Double? = nil
    for (d, scale) in displays {
        let area = overlap(d)
        if area > 0.0 && (bestScale == nil || area >= bestArea) {
            bestArea = area
            bestScale = scale
        }
    }
    return bestScale
}
