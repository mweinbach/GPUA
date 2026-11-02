// Ported from: crates/rune-motion/src/transition.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// A side of a node.
public enum Edge: String, Sendable, Equatable, Hashable, Codable {
    case leading = "Leading"
    case trailing = "Trailing"
    case top = "Top"
    case bottom = "Bottom"

    /// Unit direction pointing out of the node through this edge (LTR).
    public func direction() -> Vec2 {
        switch self {
        case .leading: return Vec2(-1.0, 0.0)
        case .trailing: return Vec2(1.0, 0.0)
        case .top: return Vec2(0.0, -1.0)
        case .bottom: return Vec2(0.0, 1.0)
        }
    }

    public func opposite() -> Edge {
        switch self {
        case .leading: return .trailing
        case .trailing: return .leading
        case .top: return .bottom
        case .bottom: return .top
        }
    }
}

/// A soft-edged wipe: the mask's `edge` side is inset by `(1 − p) ×` the node's size, with a
/// `feather`-point gradient ramp (Kit rule 11: no hard edges).
public struct Reveal: Sendable, Equatable, Hashable, Codable {
    /// The side the content is hidden behind when absent (it grows away from the opposite side).
    public var edge: Edge
    public var feather: Float

    public init(edge: Edge, feather: Float) {
        self.edge = edge
        self.feather = feather
    }
}

/// The smallest scale a transition with ``Transition/allowSmallScale()`` starts or ends at.
/// Below it a glyph reads as appearing from a point, which the scale rule exists to avoid.
public let smallScaleFloor: Float = 0.5

/// What an absent node looks like. Every field's identity value means "no change".
public struct Effect: Sendable, Equatable, Hashable, Codable {
    /// Opacity multiplier when absent (identity 1).
    public var opacity: Float
    /// Uniform scale when absent (identity 1). Kept within [0.9, 1.1], or
    /// [``smallScaleFloor``, 1.1] with `smallScale`: never scale to or from 0.
    public var scale: Float
    /// Scale anchor in unit coordinates of the node (0.5, 0.5 = centre).
    public var anchor: Vec2
    /// Offset in points when absent.
    public var offset: Vec2
    /// Offset in fractions of the node's own size when absent (`.move(edge)`, `.push`).
    public var offsetFraction: Vec2
    /// Gaussian blur sigma in points when absent (identity 0). At most 4; in-place replacement only.
    public var blur: Float
    public var reveal: Reveal?
    /// Lets `scale` go down to ``smallScaleFloor`` instead of 0.9, for small glyphs
    /// (``Transition/allowSmallScale()``).
    public var smallScale: Bool
    /// How much of the node's own shape is drawn when absent (identity 1): its strokes trace on
    /// along their length in order, and each fill fades in as the drawing reaches it
    /// (``Transition/draw()``). Under Reduce Motion it is drawn whole.
    public var draw: Float

    enum CodingKeys: String, CodingKey {
        case opacity
        case scale
        case anchor
        case offset
        case offsetFraction = "offset_fraction"
        case blur
        case reveal
        case smallScale = "small_scale"
        case draw
    }

    public static let identity = Effect(
        opacity: 1.0,
        scale: 1.0,
        anchor: Vec2(0.5, 0.5),
        offset: .zero,
        offsetFraction: .zero,
        blur: 0.0,
        reveal: nil,
        smallScale: false,
        draw: 1.0
    )

    public init() {
        self = .identity
    }

    public init(
        opacity: Float = 1.0,
        scale: Float = 1.0,
        anchor: Vec2 = Vec2(0.5, 0.5),
        offset: Vec2 = .zero,
        offsetFraction: Vec2 = .zero,
        blur: Float = 0.0,
        reveal: Reveal? = nil,
        smallScale: Bool = false,
        draw: Float = 1.0
    ) {
        self.opacity = opacity
        self.scale = scale
        self.anchor = anchor
        self.offset = offset
        self.offsetFraction = offsetFraction
        self.blur = blur
        self.reveal = reveal
        self.smallScale = smallScale
        self.draw = draw
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.opacity = try c.decode(Float.self, forKey: .opacity)
        self.scale = try c.decode(Float.self, forKey: .scale)
        self.anchor = try c.decode(Vec2.self, forKey: .anchor)
        self.offset = try c.decode(Vec2.self, forKey: .offset)
        self.offsetFraction = try c.decode(Vec2.self, forKey: .offsetFraction)
        self.blur = try c.decode(Float.self, forKey: .blur)
        self.reveal = try c.decodeIfPresent(Reveal.self, forKey: .reveal)
        self.smallScale = try c.decodeIfPresent(Bool.self, forKey: .smallScale) ?? false
        self.draw = try c.decodeIfPresent(Float.self, forKey: .draw) ?? 1.0
    }

    public static func opacity(_ opacity: Float) -> Effect {
        Effect(opacity: opacity)
    }

    public static func scale(_ scale: Float) -> Effect {
        Effect(scale: scale)
    }

    public static func blur(_ sigma: Float) -> Effect {
        Effect(blur: sigma)
    }

    /// Both effects at once: opacities and scales multiply, offsets add, blur takes the max.
    public func combined(_ o: Effect) -> Effect {
        Effect(
            opacity: opacity * o.opacity,
            scale: scale * o.scale,
            anchor: scale != 1.0 ? anchor : o.anchor,
            offset: Vec2(offset.x + o.offset.x, offset.y + o.offset.y),
            offsetFraction: Vec2(
                offsetFraction.x + o.offsetFraction.x,
                offsetFraction.y + o.offsetFraction.y
            ),
            blur: max(blur, o.blur),
            reveal: reveal ?? o.reveal,
            smallScale: smallScale || o.smallScale,
            draw: draw * o.draw
        )
    }

    public func travels() -> Bool {
        offset != .zero || offsetFraction != .zero
    }

    /// Kit's rules, enforced: scale in [0.9, 1.1] (never to or from 0; down to
    /// ``smallScaleFloor`` with `smallScale`), blur sigma ≤ 4 pt, no blur on anything that
    /// travels (sliding content stays sharp), and nothing leaves at full opacity.
    public func kitRules(_ removal: Bool) -> Effect {
        var copy = self
        let floor: Float = copy.smallScale ? smallScaleFloor : 0.9
        copy.scale = min(max(copy.scale, floor), 1.1)
        copy.blur = copy.travels() ? 0.0 : min(max(copy.blur, 0.0), 4.0)
        copy.opacity = min(max(copy.opacity, 0.0), 1.0)
        copy.draw = min(max(copy.draw, 0.0), 1.0)
        if removal {
            copy.opacity = 0.0
        }
        return copy
    }
}

/// Insertion and removal effects plus how the node behaves while it leaves.
public struct Transition: Sendable, Equatable, Hashable, Codable {
    public var insertion: Effect
    public var removal: Effect
    /// Motion's `AnimatePresence mode="popLayout"`: an exiting node leaves layout flow at once
    /// (siblings reflow while it fades in place). The default.
    public var popLayout: Bool
    /// Enter and exit springs. Exits run 10–25 % shorter.
    public var springs: SpringPair

    enum CodingKeys: String, CodingKey {
        case insertion
        case removal
        case popLayout = "pop_layout"
        case springs
    }

    public init() {
        self = .opacity()
    }

    public init(
        insertion: Effect,
        removal: Effect,
        popLayout: Bool = true,
        springs: SpringPair = tokens.pair.settle
    ) {
        self.insertion = insertion
        self.removal = removal
        self.popLayout = popLayout
        self.springs = springs
    }

    private static func symmetric(_ e: Effect) -> Transition {
        Transition(insertion: e, removal: e, popLayout: true, springs: tokens.pair.settle)
    }

    /// No visual change (presence still holds removal until its fade settles).
    public static func identity() -> Transition {
        symmetric(.identity)
    }

    /// No motion at all: a node shows whole the frame it mounts and is gone the frame it's
    /// removed, through the usual presence lifecycle (it exits invisible and inert, then
    /// unmounts, and focus returns as for any transition). Unlike `Tx::instant`, the rest of
    /// the change still animates; unlike a very short spring, Reduce Motion doesn't stretch it
    /// into a fade that keeps the node on screen.
    public static func none() -> Transition {
        identity().springs(.none)
    }

    /// `.opacity`.
    public static func opacity() -> Transition {
        symmetric(.opacity(0.0))
    }

    /// `.scale(s)` about the centre, plus a fade.
    public static func scale(_ scale: Float) -> Transition {
        symmetric(Effect(opacity: 0.0, scale: scale))
    }

    /// `.scale(s, anchor:)`.
    public static func scaleAnchor(_ scale: Float, _ anchor: Vec2) -> Transition {
        symmetric(Effect(opacity: 0.0, scale: scale, anchor: anchor))
    }

    /// `.offset(x:y:)`.
    public static func offset(_ x: Float, _ y: Float) -> Transition {
        symmetric(Effect(offset: Vec2(x, y)))
    }

    /// `.move(edge:)`: in from and out to `edge`, by the node's full size.
    public static func moveEdge(_ edge: Edge) -> Transition {
        symmetric(Effect(offsetFraction: edge.direction()))
    }

    /// `.push(from:)`: in from `edge`, out through the opposite edge, fading.
    public static func push(_ edge: Edge) -> Transition {
        let make = { (d: Edge) -> Effect in
            Effect(opacity: 0.0, offsetFraction: d.direction())
        }
        return Transition(insertion: make(edge), removal: make(edge.opposite()))
    }

    /// `.slide`: in from the leading edge, out through the trailing edge.
    public static func slide() -> Transition {
        let make = { (d: Edge) -> Effect in
            Effect(offsetFraction: d.direction())
        }
        return Transition(insertion: make(.leading), removal: make(.trailing))
    }

    /// `.blurReplace`: whole-element in-place replacement: sigma 1.5 pt, scale .96, fade.
    /// The old 4 pt shape-edge ramp left glyphs sharp; it is not equivalent to sigma 4.
    /// This preset stays within the two-pass Gaussian path at 1×/2×. Explicit `blur(sigma)`
    /// remains available for stronger effects.
    public static func blurReplace() -> Transition {
        symmetric(Effect(opacity: 0.0, scale: 0.96, blur: 1.5))
    }

    /// Gaussian blur (sigma in points) and fade only.
    public static func blur(_ sigma: Float) -> Transition {
        symmetric(Effect(opacity: 0.0, blur: sigma))
    }

    /// A shape that draws itself on, as a connector draws from its source to its target: its
    /// strokes trace from their first point to their last, one after another, and each fill (an
    /// arrowhead) fades in as the line reaches it. Applies to the node's own shape (`canvas`)
    /// only; children enter by their own transitions.
    public static func draw() -> Transition {
        symmetric(Effect(draw: 0.0))
    }

    /// A soft-edged wipe from `edge` (mask reveal), 24 pt feather.
    public static func reveal(_ edge: Edge) -> Transition {
        symmetric(Effect(reveal: Reveal(edge: edge, feather: 24.0)))
    }

    /// `.asymmetric(insertion:removal:)`.
    public static func asymmetric(_ insertion: Transition, _ removal: Transition) -> Transition {
        var copy = insertion
        copy.removal = removal.removal
        return copy
    }

    /// `.combined(with:)`.
    public func combined(_ other: Transition) -> Transition {
        var copy = self
        copy.insertion = insertion.combined(other.insertion)
        copy.removal = removal.combined(other.removal)
        return copy
    }

    public func springs(_ springs: SpringPair) -> Transition {
        var copy = self
        copy.springs = springs
        return copy
    }

    /// Lets this transition's scale go below 0.9, down to ``smallScaleFloor`` (0.5), for a
    /// small glyph such as an icon in a button, which barely seems to move at 0.9:
    /// `Transition.scale(0.6).allowSmallScale()`. Larger elements keep the default range, and
    /// nothing scales to or from 0.
    public func allowSmallScale() -> Transition {
        var copy = self
        copy.insertion.smallScale = true
        copy.removal.smallScale = true
        return copy
    }

    /// Keep the exiting node in flow (its slot collapses as it leaves) instead of popping it out.
    public func holdLayout() -> Transition {
        var copy = self
        copy.popLayout = false
        return copy
    }
}
