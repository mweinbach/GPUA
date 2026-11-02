// Ported from: crates/rune/src/input/canvas_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: in-progress

public enum PointerButton: Sendable, Equatable, Hashable {
    case primary
    case secondary
    case middle
    case back
    case forward
    case other(UInt16)

    public static let Primary: PointerButton = .primary
    public static let Secondary: PointerButton = .secondary
    public static let Middle: PointerButton = .middle
}

public enum GesturePhase: Sendable, Equatable, Hashable {
    case started
    case moved
    case ended
    case cancelled
}

public struct WheelEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var dx: Float
    public var dy: Float
    public var precise: Bool
    public var mods: Mods

    public init(x: Float = 0, y: Float = 0, dx: Float = 0, dy: Float = 0, precise: Bool = false, mods: Mods = Mods()) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        self.precise = precise
        self.mods = mods
    }
}

public struct MagnifyEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var delta: Float
    public var phase: GesturePhase
    public var mods: Mods

    public init(x: Float = 0, y: Float = 0, delta: Float = 0, phase: GesturePhase = .moved, mods: Mods = Mods()) {
        self.x = x
        self.y = y
        self.delta = delta
        self.phase = phase
        self.mods = mods
    }
}

public struct RotateEvent: Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var delta: Float
    public var phase: GesturePhase
    public var mods: Mods

    public init(x: Float = 0, y: Float = 0, delta: Float = 0, phase: GesturePhase = .moved, mods: Mods = Mods()) {
        self.x = x
        self.y = y
        self.delta = delta
        self.phase = phase
        self.mods = mods
    }
}
