// Ported from: crates/rune/src/input/canvas_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// A mouse button. Only ``primary`` reaches `onPress` and `onDrag` unless an element opts in to
/// others with ``El/pointerButtons(_:)``; ``secondary`` always goes to `onSecondaryPress`.
public enum PointerButton: Sendable, Equatable, Hashable {
    case primary
    case secondary
    case middle
    case back
    case forward
    case other(UInt16)

    public init() {
        self = .primary
    }

    public static let Primary: PointerButton = .primary
    public static let Secondary: PointerButton = .secondary
    public static let Middle: PointerButton = .middle
    public static let Back: PointerButton = .back
    public static let Forward: PointerButton = .forward

    /// Its bit in ``CanvasInput/buttons``; zero for the primary and secondary buttons.
    internal var bit: UInt8 {
        switch self {
        case .primary, .secondary:
            return 0
        case .middle:
            return 1
        case .back:
            return 2
        case .forward:
            return 4
        case .other:
            return 8
        }
    }
}

/// Where a wheel or trackpad gesture is. A mouse wheel, which reports no phases, is always ``moved``.
public enum GesturePhase: Sendable, Equatable, Hashable {
    /// The fingers touched down (or momentum began).
    case began
    /// Legacy Spine alias for ``began``.
    case started
    case moved
    /// The fingers lifted or the system cancelled the gesture.
    case ended
    /// Legacy Spine alias for ``ended``.
    case cancelled

    public init() {
        self = .moved
    }

    public static let Began: GesturePhase = .began
    public static let Moved: GesturePhase = .moved
    public static let Ended: GesturePhase = .ended
}

/// A wheel or trackpad scroll an ``El/onWheel(_:)`` handler sees.
public struct WheelEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var dx: Float
    public var dy: Float
    public var precise: Bool
    public var mods: Mods
    public var phase: GesturePhase
    public var momentum: Bool

    public init(
        x: Float = 0,
        y: Float = 0,
        dx: Float = 0,
        dy: Float = 0,
        precise: Bool = false,
        mods: Mods = Mods(),
        phase: GesturePhase = .moved,
        momentum: Bool = false
    ) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.precise = precise
        self.mods = mods
        self.phase = phase
        self.momentum = momentum
    }

    public static func new(_ dx: Float, _ dy: Float) -> WheelEvent {
        WheelEvent(dx: dx, dy: dy)
    }

    public func at(_ x: Float, _ y: Float) -> WheelEvent {
        var copy = self
        copy.x = x
        copy.y = y
        return copy
    }

    public func mods(_ mods: Mods) -> WheelEvent {
        var copy = self
        copy.mods = mods
        return copy
    }

    public func phase(_ phase: GesturePhase) -> WheelEvent {
        var copy = self
        copy.phase = phase
        return copy
    }

    public func precise(_ precise: Bool) -> WheelEvent {
        var copy = self
        copy.precise = precise
        return copy
    }
}

/// A pinch an ``El/onMagnify(_:)`` handler sees.
public struct MagnifyEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    /// The change in magnification: scale by `1.0 + delta`. Positive zooms in.
    public var delta: Float
    public var phase: GesturePhase
    public var mods: Mods

    public init(
        x: Float = 0,
        y: Float = 0,
        delta: Float = 0,
        phase: GesturePhase = .moved,
        mods: Mods = Mods()
    ) {
        self.x = x
        self.y = y
        self.delta = delta
        self.phase = phase
        self.mods = mods
    }

    public static func new(_ delta: Float) -> MagnifyEvent {
        MagnifyEvent(delta: delta)
    }

    public func at(_ x: Float, _ y: Float) -> MagnifyEvent {
        var copy = self
        copy.x = x
        copy.y = y
        return copy
    }

    public func phase(_ phase: GesturePhase) -> MagnifyEvent {
        var copy = self
        copy.phase = phase
        return copy
    }
}

/// A two-finger rotation an ``El/onRotate(_:)`` handler sees.
public struct RotateEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    /// Degrees turned since the last event, positive counterclockwise (aliased with ``degrees``).
    public var delta: Float
    public var phase: GesturePhase
    public var mods: Mods

    /// Degrees turned since the last event, positive counterclockwise.
    public var degrees: Float {
        get { delta }
        set { delta = newValue }
    }

    public init(
        x: Float = 0,
        y: Float = 0,
        delta: Float = 0,
        phase: GesturePhase = .moved,
        mods: Mods = Mods()
    ) {
        self.x = x
        self.y = y
        self.delta = delta
        self.phase = phase
        self.mods = mods
    }

    public init(
        degrees: Float,
        x: Float = 0,
        y: Float = 0,
        phase: GesturePhase = .moved,
        mods: Mods = Mods()
    ) {
        self.init(x: x, y: y, delta: degrees, phase: phase, mods: mods)
    }

    public static func new(_ degrees: Float) -> RotateEvent {
        RotateEvent(degrees: degrees)
    }

    public func at(_ x: Float, _ y: Float) -> RotateEvent {
        var copy = self
        copy.x = x
        copy.y = y
        return copy
    }

    public func phase(_ phase: GesturePhase) -> RotateEvent {
        var copy = self
        copy.phase = phase
        return copy
    }
}

/// An element's canvas handlers, stored optionally since few elements register any.
internal struct CanvasInput {
    internal var wheel: ((States, WheelEvent, inout Tx) -> Bool)? = nil
    internal var magnify: ((States, MagnifyEvent, inout Tx) -> Bool)? = nil
    internal var rotate: ((States, RotateEvent, inout Tx) -> Bool)? = nil
    internal var smartMagnify: ((States, Float, Float, inout Tx) -> Bool)? = nil
    /// ``PointerButton/bit``s of the buttons besides the primary that press and drag it.
    internal var buttons: UInt8 = 0

    internal init() {}

    /// It takes a gesture, so it hit-tests like an element with a press handler.
    internal var takesGestures: Bool {
        wheel != nil || magnify != nil || rotate != nil || smartMagnify != nil
    }
}

extension El {
    /// Wheel and trackpad scrolls over this element, before any scroll view around or under the pointer moves.
    public func onWheel<S>(_ f: @escaping (inout S, WheelEvent, inout Tx) -> Bool) -> El {
        var copy = self
        var spec = copy.canvasInputSpec ?? CanvasInput()
        spec.wheel = { states, event, tx in
            states.withMutable { (state: inout S) in
                f(&state, event, &tx)
            } ?? false
        }
        copy.canvasInputSpec = spec
        return copy
    }

    /// Trackpad pinches over this element: return `true` to take one.
    public func onMagnify<S>(_ f: @escaping (inout S, MagnifyEvent, inout Tx) -> Bool) -> El {
        var copy = self
        var spec = copy.canvasInputSpec ?? CanvasInput()
        spec.magnify = { states, event, tx in
            states.withMutable { (state: inout S) in
                f(&state, event, &tx)
            } ?? false
        }
        copy.canvasInputSpec = spec
        return copy
    }

    /// Two-finger trackpad rotation over this element (macOS): return `true` to take it.
    public func onRotate<S>(_ f: @escaping (inout S, RotateEvent, inout Tx) -> Bool) -> El {
        var copy = self
        var spec = copy.canvasInputSpec ?? CanvasInput()
        spec.rotate = { states, event, tx in
            states.withMutable { (state: inout S) in
                f(&state, event, &tx)
            } ?? false
        }
        copy.canvasInputSpec = spec
        return copy
    }

    /// A two-finger double tap over this element (macOS smart magnify), with the pointer in its own layout points.
    public func onSmartMagnify<S>(_ f: @escaping (inout S, Float, Float, inout Tx) -> Bool) -> El {
        var copy = self
        var spec = copy.canvasInputSpec ?? CanvasInput()
        spec.smartMagnify = { states, x, y, tx in
            states.withMutable { (state: inout S) in
                f(&state, x, y, &tx)
            } ?? false
        }
        copy.canvasInputSpec = spec
        return copy
    }

    /// Mouse buttons besides the primary that press and drag this element.
    public func pointerButtons<S: Swift.Sequence>(_ buttons: S) -> El where S.Element == PointerButton {
        var copy = self
        var spec = copy.canvasInputSpec ?? CanvasInput()
        for b in buttons {
            spec.buttons |= b.bit
        }
        copy.canvasInputSpec = spec
        return copy
    }

    /// Key releases routed to the focused element's handler, then each ancestor's up to the root.
    public func onKeyUp<S>(_ f: @escaping (inout S, KeyEvent, inout Tx) -> Bool) -> El {
        var copy = self
        copy.onKeyUpHandler = { states, event, tx in
            states.withMutable { (state: inout S) in
                f(&state, event, &tx)
            } ?? false
        }
        return copy
    }
}

extension Tx {
    /// In `onPress` and `onDrag`, the button that drove it, which is ``PointerButton/primary``
    /// unless the element opted in to others with ``El/pointerButtons(_:)``.
    public func button() -> PointerButton {
        buttonPressed
    }
}
