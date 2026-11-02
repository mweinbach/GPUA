// Ported from: crates/rune-motion/src/props.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// A stable node key from the app side (a hash of the keyed path, a row id, …).
public struct NodeId: Sendable, Equatable, Hashable, Comparable, Codable, RawRepresentable {
    public var rawValue: UInt64

    public var value: UInt64 {
        get { rawValue }
        set { rawValue = newValue }
    }

    public init(_ rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static func < (lhs: NodeId, rhs: NodeId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// An untyped property id, as it appears in events and traces.
public struct PropId: Sendable, Equatable, Hashable, Comparable, Codable, RawRepresentable {
    public var rawValue: UInt16

    public var value: UInt16 {
        get { rawValue }
        set { rawValue = newValue }
    }

    public init(_ rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static func < (lhs: PropId, rhs: PropId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kind of quantity a property is. The runtime picks settle thresholds and reduced-motion
/// behaviour from this, so authors can't forget either.
public enum PropClass: Sendable, Equatable, Hashable {
    /// Positions, edges, offsets, sizes (points).
    case spatial
    case scale
    /// Radians.
    case rotation
    case opacity
    /// Blur radius (points).
    case blur
    /// Colours (premultiplied OKLab lanes).
    case color
    /// Corner radii, borders, feathers (points).
    case shape
    /// A 0…1 presence progress that fades content in and out.
    case presence
    /// Values the user's own hand drives (scroll offset, drag position). Never reduced.
    case gesture
    case other
}

/// The fade that replaces travel under Reduce Motion (OpenCode `reducedFade` .20, 75 ms in a native
/// app; Kit: ≈ .15–.2 s).
public let reducedFade: Curve = .tween(duration: 0.18, easing: .easeInOut)

extension PropClass {
    /// Settle thresholds, set below the 1/64 px snap quantum so the final snap is invisible
    /// (research 06 §2.3). `pixelScale` is device pixels per point.
    public func eps(_ pixelScale: Float) -> Eps {
        let px: Float = 1.0 / (128.0 * max(pixelScale, 1.0))
        let pos: Float
        switch self {
        case .spatial, .shape, .gesture, .blur:
            pos = px
        case .scale, .rotation, .presence:
            pos = 1e-5
        case .opacity, .color:
            pos = 1.0 / 1024.0
        case .other:
            pos = 1e-4
        }
        return Eps(pos: pos, vel: pos * 10.0)
    }

    /// What Reduce Motion turns `curve` into for this class (research 06 §2.12): travel, scale,
    /// rotation, shape and blur jump; opacity, colour and presence take a short fade; the user's
    /// own gestures are untouched.
    public func reduce(_ curve: Curve) -> Curve {
        switch curve {
        case .instant, .decay:
            return curve
        default:
            break
        }
        switch self {
        case .spatial, .scale, .rotation, .shape, .blur:
            return .instant
        case .opacity, .color, .presence:
            return reducedFade
        case .gesture, .other:
            return curve
        }
    }
}

/// A typed property key: `prop.opacity` is a `Prop<Float>`, `prop.frame` a `Prop<Rect>`.
public struct Prop<T: Animatable>: Sendable, Equatable, Hashable, CustomDebugStringConvertible {
    public let id: PropId
    public let `class`: PropClass

    /// A custom property. Ids below 64 are reserved for the built-ins.
    public static func custom(_ id: UInt16, _ propClass: PropClass) -> Prop<T> {
        precondition(id >= 64, "custom property ids start at 64")
        return Prop(id: PropId(id), class: propClass)
    }

    fileprivate static func builtin(_ id: UInt16, _ propClass: PropClass) -> Prop<T> {
        Prop(id: PropId(id), class: propClass)
    }

    public var debugDescription: String {
        "Prop(\(id.rawValue), \(`class`))"
    }
}

/// Built-in properties the scene and renderer understand.
public enum prop {
    public static let opacity = Prop<Float>.builtin(0, .opacity)
    /// The layout frame in parent space, animated as four edges.
    public static let frame = Prop<Rect>.builtin(1, .spatial)
    public static let offset = Prop<Vec2>.builtin(2, .spatial)
    public static let scale = Prop<Float>.builtin(3, .scale)
    public static let rotation = Prop<Float>.builtin(4, .rotation)
    public static let blur = Prop<Float>.builtin(5, .blur)
    public static let radius = Prop<Corners>.builtin(6, .shape)
    public static let fill = Prop<Color>.builtin(7, .color)
    /// Soft-mask insets (left, top, right, bottom) in points.
    public static let mask = Prop<Sides>.builtin(8, .shape)
    /// Scroll or drag offset owned by the render thread.
    public static let scroll = Prop<Vec2>.builtin(9, .gesture)
    /// Presence progress: 0 absent, 1 present. Driven by the scene.
    public static let presence = Prop<Float>.builtin(10, .presence)
    /// Screen-space travel progress (x, y) for matched geometry and `Travel.screen`. A
    /// fraction of the path, so it settles like a scale: a point-sized threshold would end a
    /// long flight a few points short and snap.
    public static let travel = Prop<Vec2>.builtin(11, .scale)

    /// Number of built-in property ids (the scene caches these per node).
    public static let builtinCount: Int = 12
}
