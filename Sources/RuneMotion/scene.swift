// Ported from: crates/rune-motion/src/scene.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// Width-leads ratio for the X axis spring (native morph: `width_vd = 0.78 · vd`).
public let widthLead: Float = 0.78

/// Where a node is in its life.
public enum Phase: Sendable, Equatable, Hashable {
    case entering
    case present
    /// Removed by the app; still drawn until its exit settles. `generation` guards against stale exits.
    case exiting(generation: UInt32)
}

/// Whether an insert is part of the first build (no animation, Kit rule 6) or a later change.
public enum Mount: Sendable, Equatable, Hashable {
    case initial
    case animated
}

/// The coordinate space layout motion is tracked in.
public enum Travel: Sendable, Equatable, Hashable {
    /// Edges animate in parent space; an unchanged child rides its parent.
    case parent
    /// The node travels one straight screen-space path from where it was seen to where it lands,
    /// whatever its ancestors do (Kit rule 12). Interpolates start and end root-space rects with
    /// one progress per axis.
    case screen

    public init() {
        self = .parent
    }
}

/// Anything that converts into a ``LayoutAnim`` (Swift counterpart to `impl Into<LayoutAnim>`).
public protocol LayoutAnimConvertible: Sendable {
    func intoLayoutAnim() -> LayoutAnim
}

/// How a frame change animates: per-axis curves, directional edge lead, and travel space.
public struct LayoutAnim: Sendable, Equatable, LayoutAnimConvertible {
    public var x: Anim
    public var y: Anim
    public var lead: (Anim, Anim)?
    public var travel: Travel

    public init(_ anim: some AnimExt) {
        let a = anim.intoAnim()
        self.x = a
        self.y = a
        self.lead = nil
        self.travel = .parent
    }

    public init(x: Anim, y: Anim, lead: (Anim, Anim)? = nil, travel: Travel = .parent) {
        self.x = x
        self.y = y
        self.lead = lead
        self.travel = travel
    }

    public static func new(_ anim: some AnimExt) -> LayoutAnim {
        LayoutAnim(anim)
    }

    public static func axes(_ x: some AnimExt, _ y: some AnimExt) -> LayoutAnim {
        LayoutAnim(x: x.intoAnim(), y: y.intoAnim(), lead: nil, travel: .parent)
    }

    public static func == (lhs: LayoutAnim, rhs: LayoutAnim) -> Bool {
        guard lhs.x == rhs.x, lhs.y == rhs.y, lhs.travel == rhs.travel else {
            return false
        }
        switch (lhs.lead, rhs.lead) {
        case (nil, nil):
            return true
        case (let a?, let b?):
            return a.0 == b.0 && a.1 == b.1
        default:
            return false
        }
    }

    @inline(__always)
    public func intoLayoutAnim() -> LayoutAnim {
        self
    }

    /// The X axis springs faster (duration × 0.78), so a widening surface fits its content first
    /// (Kit rule 9: "the width should animate much faster").
    public func widthLeads() -> LayoutAnim {
        var copy = self
        if case .spring(let s) = copy.x.curve {
            copy.x.curve = .spring(s.withDuration(s.duration * widthLead))
        }
        return copy
    }

    /// When an axis travels, its leading edge in the direction of travel uses `lead` and its
    /// trailing edge uses `trail` (width leads along the travel direction).
    public func lead(_ lead: some AnimExt, _ trail: some AnimExt) -> LayoutAnim {
        var copy = self
        copy.lead = (lead.intoAnim(), trail.intoAnim())
        return copy
    }

    public func screen() -> LayoutAnim {
        var copy = self
        copy.travel = .screen
        return copy
    }

    public static let instant = LayoutAnim(x: .instant, y: .instant, lead: nil, travel: .parent)
}

extension Spring: LayoutAnimConvertible {
    @inline(__always)
    public func intoLayoutAnim() -> LayoutAnim {
        LayoutAnim(self)
    }
}

extension Anim: LayoutAnimConvertible {
    @inline(__always)
    public func intoLayoutAnim() -> LayoutAnim {
        LayoutAnim(self)
    }
}

extension SpringPair: LayoutAnimConvertible {
    @inline(__always)
    public func intoLayoutAnim() -> LayoutAnim {
        LayoutAnim(enter)
    }
}

extension Curve: LayoutAnimConvertible {
    @inline(__always)
    public func intoLayoutAnim() -> LayoutAnim {
        LayoutAnim(self)
    }
}

/// What the app side sends when a keyed node appears.
public struct NodeSpec: Sendable, Equatable {
    public var parent: NodeId?
    /// Layout frame in parent space, at the target state.
    public var frame: Rect
    public var opacity: Float
    public var radius: Corners
    public var fill: Color
    public var transition: Transition

    public init(_ frame: Rect) {
        self.parent = nil
        self.frame = frame
        self.opacity = 1.0
        self.radius = .zero
        self.fill = .transparent
        self.transition = .opacity()
    }

    public static func new(_ frame: Rect) -> NodeSpec {
        NodeSpec(frame)
    }

    public func parent(_ parent: NodeId) -> NodeSpec {
        var copy = self
        copy.parent = parent
        return copy
    }

    public func opacity(_ o: Float) -> NodeSpec {
        var copy = self
        copy.opacity = o
        return copy
    }

    public func radius(_ r: Corners) -> NodeSpec {
        var copy = self
        copy.radius = r
        return copy
    }

    public func radius(_ r: Float) -> NodeSpec {
        var copy = self
        copy.radius = .all(r)
        return copy
    }

    public func fill(_ c: Color) -> NodeSpec {
        var copy = self
        copy.fill = c
        return copy
    }

    public func transition(_ t: Transition) -> NodeSpec {
        var copy = self
        copy.transition = t
        return copy
    }
}

/// A soft clip in the node's own coordinates: how far each side is pulled in, and how wide the
/// gradient ramp on that side is. The renderer evaluates it as an SDF ramp (Kit rule 11).
public struct Mask: Sendable, Equatable, Hashable {
    public var inset: Sides
    public var feather: Sides

    public init(inset: Sides = .zero, feather: Sides = .zero) {
        self.inset = inset
        self.feather = feather
    }

    public func isNone() -> Bool {
        inset == .zero && feather == .zero
    }
}

/// Everything the renderer needs to draw one node this frame.
public struct Presented: Sendable, Equatable {
    public var node: NodeId
    public var parent: NodeId?
    /// Root-space rect including every ancestor's (and this node's) translation, both edges
    /// snapped to 1/64 device px. Shapes, borders and shadows are drawn at this size.
    public var rect: Rect
    /// This node's own opacity (presence × property). Ancestors apply theirs as group opacity.
    public var opacity: Float
    /// Scale and rotation about `anchor` (translation is already in `rect`). Ancestors' scale and
    /// rotation compose down the tree, like `CALayer`.
    public var transform: Transform
    /// Root-space pivot for `transform`.
    public var anchor: Vec2
    /// Own plus presence Gaussian blur sigma in points. Zero means "attach no filter".
    public var blur: Float
    public var radius: Corners
    public var fill: Color
    public var mask: Mask
    public var phase: Phase
    /// False while exiting with `popLayout`: the app's layout should no longer reserve space.
    public var inFlow: Bool
    /// motion-lint flags (animated, ancestorAnimated, clipped, filtered) and intent bits
    /// (own `<< 8`, ancestor `<< 16`).
    public var flags: UInt32
    /// How much of this node's own shape is drawn, 0 to 1 (``Transition/draw()``).
    public var draw: Float

    /// The 2×3 affine for `transform` about `anchor`.
    public func affine() -> [Float] {
        transform.toAffine(anchor)
    }
}

/// One frame's output.
public struct FrameOutput: Sendable {
    /// Nodes whose presented values changed, parents before children.
    public var changed: [Presented]
    /// Nodes whose exit settled this frame: draw nothing for them from now on.
    public var exited: [NodeId]
    public var events: [MotionEvent]
    /// Anything still moving? If not, the display link can pause.
    public var animating: Bool
}

struct ScenePath: Sendable {
    var start: Rect
    var endLocal: Rect
    /// Its parent's root-space target origin as the last frame drew it.
    var origin: Vec2
}

// Effect state lanes: opacity, scale, offset x/y, size-fraction offset x/y, blur, hidden reveal,
// drawn shape.
struct FxState9: Sendable {
    var f0: Float = 1.0
    var f1: Float = 1.0
    var f2: Float = 0.0
    var f3: Float = 0.0
    var f4: Float = 0.0
    var f5: Float = 0.0
    var f6: Float = 0.0
    var f7: Float = 0.0
    var f8: Float = 1.0

    static let identity = FxState9()

    @inline(__always)
    subscript(_ k: Int) -> Float {
        get {
            switch k {
            case 0: return f0
            case 1: return f1
            case 2: return f2
            case 3: return f3
            case 4: return f4
            case 5: return f5
            case 6: return f6
            case 7: return f7
            case 8: return f8
            default: preconditionFailure("FxState9 index out of bounds")
            }
        }
        set {
            switch k {
            case 0: f0 = newValue
            case 1: f1 = newValue
            case 2: f2 = newValue
            case 3: f3 = newValue
            case 4: f4 = newValue
            case 5: f5 = newValue
            case 6: f6 = newValue
            case 7: f7 = newValue
            case 8: f8 = newValue
            default: preconditionFailure("FxState9 index out of bounds")
            }
        }
    }
}

@inline(__always)
func fxOf(_ e: Effect) -> FxState9 {
    let hidden: Float = e.reveal != nil ? 1.0 : 0.0
    return FxState9(
        f0: e.opacity,
        f1: e.scale,
        f2: e.offset.x,
        f3: e.offset.y,
        f4: e.offsetFraction.x,
        f5: e.offsetFraction.y,
        f6: e.blur,
        f7: hidden,
        f8: e.draw
    )
}

/// Exact at both ends: `a` at p = 0, `b` at p = 1.
@inline(__always)
func lerpFx(_ a: FxState9, _ b: FxState9, _ p: Float) -> FxState9 {
    let q: Float = 1.0 - p
    return FxState9(
        f0: a.f0 * q + b.f0 * p,
        f1: a.f1 * q + b.f1 * p,
        f2: a.f2 * q + b.f2 * p,
        f3: a.f3 * q + b.f3 * p,
        f4: a.f4 * q + b.f4 * p,
        f5: a.f5 * q + b.f5 * p,
        f6: a.f6 * q + b.f6 * p,
        f7: a.f7 * q + b.f7 * p,
        f8: a.f8 * q + b.f8 * p
    )
}

struct BuiltinTracks: Sendable {
    var t0: TrackId? = nil
    var t1: TrackId? = nil
    var t2: TrackId? = nil
    var t3: TrackId? = nil
    var t4: TrackId? = nil
    var t5: TrackId? = nil
    var t6: TrackId? = nil
    var t7: TrackId? = nil
    var t8: TrackId? = nil
    var t9: TrackId? = nil
    var t10: TrackId? = nil
    var t11: TrackId? = nil

    @inline(__always)
    subscript(_ k: Int) -> TrackId? {
        get {
            switch k {
            case 0: return t0
            case 1: return t1
            case 2: return t2
            case 3: return t3
            case 4: return t4
            case 5: return t5
            case 6: return t6
            case 7: return t7
            case 8: return t8
            case 9: return t9
            case 10: return t10
            case 11: return t11
            default: return nil
            }
        }
        set {
            switch k {
            case 0: t0 = newValue
            case 1: t1 = newValue
            case 2: t2 = newValue
            case 3: t3 = newValue
            case 4: t4 = newValue
            case 5: t5 = newValue
            case 6: t6 = newValue
            case 7: t7 = newValue
            case 8: t8 = newValue
            case 9: t9 = newValue
            case 10: t10 = newValue
            case 11: t11 = newValue
            default: break
            }
        }
    }
}

struct SceneNode: Sendable {
    var id: NodeId
    var parent: UInt32
    var firstChild: UInt32
    var lastChild: UInt32
    var nextSibling: UInt32
    var prevSibling: UInt32
    var alive: Bool
    var frame: Rect
    var opacity: Float
    var radius: Corners
    var fill: Color
    var transition: Transition
    var phase: Phase
    var generation: UInt32
    /// Presence effect at p = 0 and p = 1 (normally the effect and identity; re-solved on a
    /// mid-flight reversal so nothing jumps).
    var fxA: FxState9
    var fxB: FxState9
    var anchor: Vec2
    var reveal: Reveal?
    var path: ScenePath?
    /// `setRideTrailing`: x is kept against the parent's trailing edge while its width moves.
    var rideTrailing: Bool
    var tracks: BuiltinTracks
    var dirty: Bool
    /// Root-space layout rect this frame (unsnapped) and the origin children ride (with offsets).
    var world: Rect
    var origin: Vec2
    var last: Presented?
}

/// Where a node comes to rest (see ``Scene/rest(_:)``), beside `Scene.nodes` so the nodes the
/// renderer reads every frame stay the same size.
struct Rest: Sendable {
    /// Root-space presented rect with every track at its target, and the origin children rest on.
    var rect: Rect
    var origin: Vec2
    /// `rect` differs from where the node is this frame.
    var moving: Bool

    static let zero = Rest(rect: .zero, origin: .zero, moving: false)
}

/// A small dual number: value and time derivative, for exact velocity of composed geometry.
struct Dual: Sendable {
    var x: Float = 0.0
    var v: Float = 0.0

    @inline(__always)
    static func c(_ x: Float) -> Dual {
        Dual(x: x, v: 0.0)
    }

    @inline(__always)
    func add(_ o: Dual) -> Dual {
        Dual(x: x + o.x, v: v + o.v)
    }

    @inline(__always)
    func sub(_ o: Dual) -> Dual {
        Dual(x: x - o.x, v: v - o.v)
    }

    @inline(__always)
    func mul(_ o: Dual) -> Dual {
        Dual(x: x * o.x, v: v * o.x + x * o.v)
    }
}

struct Dual4: Sendable {
    var d0: Dual
    var d1: Dual
    var d2: Dual
    var d3: Dual

    init(_ d0: Dual, _ d1: Dual, _ d2: Dual, _ d3: Dual) {
        self.d0 = d0
        self.d1 = d1
        self.d2 = d2
        self.d3 = d3
    }

    @inline(__always)
    subscript(_ k: Int) -> Dual {
        get {
            switch k {
            case 0: return d0
            case 1: return d1
            case 2: return d2
            case 3: return d3
            default: preconditionFailure("Dual4 index out of bounds")
            }
        }
        set {
            switch k {
            case 0: d0 = newValue
            case 1: d1 = newValue
            case 2: d2 = newValue
            case 3: d3 = newValue
            default: preconditionFailure("Dual4 index out of bounds")
            }
        }
    }
}

/// The render thread's animated tree.
// PORT NOTE: `Scene` is a stateful engine object owned and mutated on a single render thread
// (matching Rust's `&mut Scene`), so it is a `final class` marked `@unchecked Sendable`.
public final class Scene: @unchecked Sendable {
    let _store = AnimationStore()
    var nodes: [SceneNode] = []
    var rests: [Rest] = []
    var free: [UInt32] = []
    var index: [UInt64: UInt32] = [:]
    var rootHead: UInt32 = noneIndex
    var rootTail: UInt32 = noneIndex
    var order: [UInt32] = []
    var orderDirty: Bool = false
    var out: [Presented] = []
    /// What ``present()`` presented after the motion trace wrote its frame, for the next.
    var late: [Presented] = []
    var exited: [NodeId] = []
    var exitedSeen: Int = 0
    var toRemove: [UInt32] = []
    var travelling: [UInt32] = []
    var _trace: MotionTrace? = nil
    var intents: [(NodeId, UInt32, Float)] = []
    /// `keepFlights`: landings leave motion already on its way to the same value.
    var keep: Bool = false

    public init() {}

    public static func new() -> Scene {
        Scene()
    }

    /// While on, landing a property (``Scene/set(_:_:_:)``, or ``Scene/setFrame(_:_:_:)`` with
    /// ``LayoutAnim/instant``) on the value it's already moving to leaves that motion running:
    /// an instant change lands what it changes, not what an earlier change set going. Off, a
    /// landing ends any motion, as settling needs.
    public func keepFlights(_ on: Bool) {
        keep = on
    }

    /// `prop` is moving and its target is `value`, so a landing under `keepFlights` leaves it.
    func inFlightTo<T: Animatable>(_ id: NodeId, _ prop: Prop<T>, _ value: T) -> Bool {
        if !keep || !_store.isAnimating(id, prop) {
            return false
        }
        guard let to = _store.target(id, prop) else { return false }
        let a = lanes(to)
        let b = lanes(value)
        for k in 0..<T.lanes {
            if abs(a[k] - b[k]) > 1e-3 {
                return false
            }
        }
        return true
    }

    public func store() -> AnimationStore {
        _store
    }

    /// For choreography and custom properties. Tracks of scene nodes are picked up automatically.
    public func storeMut() -> AnimationStore {
        _store
    }

    public func setTime(_ t: Double) {
        _store.setTime(t)
    }

    /// Runs the node's animations at `scale` times the scene's speed; see
    /// ``AnimationStore/setNodeTimeScale(_:_:)``.
    public func setTimeScale(_ id: NodeId, _ scale: Float) {
        _store.setNodeTimeScale(id, scale)
    }

    public func now() -> Double {
        _store.now()
    }

    public func setPixelScale(_ s: Float) {
        let previous = _store.pixelScale()
        _store.setPixelScale(s)
        if _store.pixelScale() != previous {
            for idx in 0..<nodes.count where nodes[idx].alive {
                nodes[idx].dirty = true
            }
        }
    }

    public func setReducedMotion(_ on: Bool) {
        _store.setReducedMotion(on)
        for idx in 0..<nodes.count where nodes[idx].alive {
            nodes[idx].dirty = true
        }
    }

    /// Records every frame as motion-lint JSONL.
    public func setTrace(_ trace: MotionTrace?) {
        _trace = trace
        for idx in 0..<nodes.count where nodes[idx].alive {
            nodes[idx].dirty = true
        }
    }

    public func tracing() -> Bool {
        _trace != nil
    }

    public func traceMut() -> MotionTrace? {
        _trace
    }

    /// Updates metadata even if the node's geometry has not changed.
    public func traceName(_ id: NodeId, _ name: String?) {
        if let tr = _trace, tr.name(id, name) {
            if let i = slot(id) {
                nodes[i].dirty = true
            }
        }
    }

    public func traceNamespace(_ id: NodeId, _ namespace: (String, String)?) {
        if let tr = _trace, tr.namespace(id, namespace) {
            if let i = slot(id) {
                nodes[i].dirty = true
            }
        }
    }

    public func takeTrace() -> MotionTrace? {
        let taken = _trace
        _trace = nil
        return taken
    }

    public func contains(_ id: NodeId) -> Bool {
        index[id.rawValue] != nil
    }

    public func phase(_ id: NodeId) -> Phase? {
        slot(id).map { nodes[$0].phase }
    }

    /// The last presented snapshot (hit-test against what the user sees). Not tracked.
    public func presented(_ id: NodeId) -> Presented? {
        slot(id).flatMap { nodes[$0].last }
    }

    /// The rect the node comes to rest at once every track (its own and its ancestors') reaches
    /// its target, snapped like ``Presented/rect``, while that differs from where it is: the
    /// difference from ``presented(_:)`` is the motion still in flight. Only a
    /// node whose ``Presented/flags`` has `animated` or `ancestorAnimated` can be moving.
    public func rest(_ id: NodeId) -> Rect? {
        guard let s = slot(id) else { return nil }
        let r = rests[s]
        return r.moving ? snap.snapRect(r.rect, _store.pixelScale()) : nil
    }

    /// Root-space layout rect this frame (without this node's own offset or presence offset),
    /// snapped to the same 1/64 device-px grid as ``Presented/rect``.
    public func world(_ id: NodeId) -> Rect? {
        slot(id).map { snap.snapRect(nodes[$0].world, _store.pixelScale()) }
    }

    public func len() -> Int {
        index.count
    }

    public func isEmpty() -> Bool {
        index.isEmpty
    }

    @inline(__always)
    func slot(_ id: NodeId) -> Int? {
        index[id.rawValue].map { Int($0) }
    }

    /// Lane values and velocities of track `t`, sampled exactly at `now()`.
    func sample(_ t: TrackId) -> (LaneStorage, LaneStorage)? {
        var x = LaneStorage()
        var v = LaneStorage()
        return _store.sampleExact(t, &x, &v) ? (x, v) : nil
    }

    // ------------------------------------------------------------------------------------------
    // Layout

    /// The node's layout frame (parent space) changed. Each moving edge animates; a stationary
    /// edge gets no motion at all. With `Travel.screen` the node takes one straight root-space
    /// path instead, whatever its ancestors do.
    public func setFrame(_ id: NodeId, _ frame: Rect, _ anim: some LayoutAnimConvertible) {
        setFrameDrawn(id, frame, anim.intoLayoutAnim(), .zero, .zero)
    }

    /// ``setFrame(_:_:_:)`` for a node drawn `drawnOffset` away from its scene rect,
    /// moving `drawnVelocity` faster: a screen path starts there, at that speed.
    func setFrameDrawn(
        _ id: NodeId,
        _ frame: Rect,
        _ anim: LayoutAnim,
        _ drawnOffset: Vec2,
        _ drawnVelocity: Vec2
    ) {
        guard let i = slot(id) else { return }
        let old = nodes[i].frame
        if old == frame && nodes[i].path == nil && nodes[i].tracks[Int(prop.frame.id.rawValue)] == nil {
            return
        }
        if frame.w != old.w {
            rebaseTrailing(i, frame.w - old.w)
        }
        let hadPath = nodes[i].path != nil
        // An explicit landing also cancels motion toward an unchanged target. Comparing only
        // target frames here used to leave a spring running after Runtime::settle_all().
        if anim == .instant && !hadPath && inFlightTo(id, prop.frame, frame) {
            return
        }
        if anim == .instant && (hadPath || _store.isAnimating(id, prop.frame)) {
            endPath(i)
            nodes[i].frame = frame
            trackSet(i, prop.frame, frame)
            nodes[i].dirty = true
            return
        }
        if old == frame && !hadPath {
            return
        }
        let ms: Float
        if case .spring(let s) = anim.x.curve {
            ms = s.duration
        } else {
            ms = anim.x.curve.logicalDuration()
        }
        intent(id, Intent.position | Intent.size, ms)
        if anim.travel == .screen && !_store.reducedMotion() {
            // A path restarts from where it was drawn: under the origin the last frame drew it
            // against, which an ancestor laid out elsewhere in this commit has already moved.
            var (start, vel): ((Float, Float, Float, Float), (Float, Float, Float, Float))
            if let path = nodes[i].path {
                let e = pathDual(i, path, path.origin)
                start = (e[0].x, e[1].x, e[2].x, e[3].x)
                vel = (e[0].v, e[1].v, e[2].v, e[3].v)
            } else {
                (start, vel) = exactWorld(i)
            }
            start.0 += drawnOffset.x
            start.1 += drawnOffset.y
            start.2 += drawnOffset.x
            start.3 += drawnOffset.y
            vel.0 += drawnVelocity.x
            vel.1 += drawnVelocity.y
            vel.2 += drawnVelocity.x
            vel.3 += drawnVelocity.y
            nodes[i].frame = frame
            startPath(i, start, vel, anim)
            return
        }
        if hadPath {
            // Leave screen travel: continue in parent space from the exact current place.
            let (w, wv) = exactWorld(i)
            var (po, pv) = parentOriginExact(i)
            let trail = trailDual(i)
            po.x += trail.x
            pv.x += trail.v
            let local = Rect.fromEdges(w.0 - po.x, w.1 - po.y, w.2 - po.x, w.3 - po.y)
            var lv = LaneStorage()
            lv[0] = wv.0 - pv.x
            lv[1] = wv.1 - pv.y
            lv[2] = wv.2 - pv.x
            lv[3] = wv.3 - pv.y
            endPath(i)
            trackSet(i, prop.frame, local)
            let t = nodes[i].tracks[Int(prop.frame.id.rawValue)]!
            // Give the lanes their velocity, then retarget per axis.
            let tid = t.indexInt()
            let localLanes = lanes(local)
            localLanes.withBuffer(count: 4) { locBuf in
                lv.withBuffer(count: 4) { lvBuf in
                    _ = _store.animateRaw(tid, locBuf, Anim(curve: .spring(.smooth)), lvBuf)
                }
            }
        } else if nodes[i].tracks[Int(prop.frame.id.rawValue)] == nil {
            trackSet(i, prop.frame, old)
        }
        nodes[i].frame = frame
        let t = nodes[i].tracks[Int(prop.frame.id.rawValue)]!.indexInt()
        let curTuple = _store.laneTargets4(t)
        var cur = LaneStorage()
        cur[0] = curTuple.0
        cur[1] = curTuple.1
        cur[2] = curTuple.2
        cur[3] = curTuple.3
        let eTuple = frame.edgesTuple()
        var e = LaneStorage()
        e[0] = eTuple.0
        e[1] = eTuple.1
        e[2] = eTuple.2
        e[3] = eTuple.3
        if let (lead, trail) = anim.lead {
            for axis in 0..<2 {
                let a = axis
                let b = axis + 2
                let (sa, sb) = (e[a] + e[b] > cur[a] + cur[b]) ? (trail, lead) : (lead, trail)
                var tg = cur
                tg[a] = e[a]
                tg.withBuffer(count: 4) { _ = _store.animateRaw(t, $0, sa, nil) }
                cur[a] = e[a]
                tg = cur
                tg[b] = e[b]
                tg.withBuffer(count: 4) { _ = _store.animateRaw(t, $0, sb, nil) }
                cur[b] = e[b]
            }
        } else {
            // X edges on the X curve, Y edges on the Y curve; unchanged lanes are skipped.
            var xTargets = LaneStorage()
            xTargets[0] = e[0]
            xTargets[1] = cur[1]
            xTargets[2] = e[2]
            xTargets[3] = cur[3]
            xTargets.withBuffer(count: 4) { _ = _store.animateRaw(t, $0, anim.x, nil) }
            e.withBuffer(count: 4) { _ = _store.animateRaw(t, $0, anim.y, nil) }
        }
        nodes[i].dirty = true
    }

    func parentTargetOrigin(_ i: Int) -> Vec2 {
        var o = Vec2.zero
        var p = nodes[i].parent
        while p != noneIndex {
            let f = nodes[Int(p)].frame
            o.x += f.x
            o.y += f.y
            p = nodes[Int(p)].parent
        }
        return o
    }

    /// Root-space layout edges of node `i` at `now()`, with velocities, sampled exactly.
    func exactWorld(_ i: Int) -> ((Float, Float, Float, Float), (Float, Float, Float, Float)) {
        let e = worldDual(i)
        return ((e.d0.x, e.d1.x, e.d2.x, e.d3.x), (e.d0.v, e.d1.v, e.d2.v, e.d3.v))
    }

    /// Trace-only check of presented scene edges against unsnapped analytic tracks at `now`.
    /// Returns (edge samples, maximum device-pixel error). Renderer-owned growth/scroll and
    /// post-layout scale transforms are outside this metric.
    public func samplingError() -> (Int, Float) {
        var count = 0
        var error: Float = 0.0
        let pxScale = _store.pixelScale()
        for slotRaw in order {
            let i = Int(slotRaw)
            guard let p = nodes[i].last, nodes[i].alive else { continue }
            let w = worldDual(i)
            let o = originDual(i)
            let ideal = (o.0.x, o.1.x, o.0.x + w.d2.x - w.d0.x, o.1.x + w.d3.x - w.d1.x)
            let shown = p.rect.edgesTuple()
            error = max(error, abs(shown.0 - ideal.0) * pxScale)
            error = max(error, abs(shown.1 - ideal.1) * pxScale)
            error = max(error, abs(shown.2 - ideal.2) * pxScale)
            error = max(error, abs(shown.3 - ideal.3) * pxScale)
            count += 4
        }
        return (count, error)
    }

    func parentOriginExact(_ i: Int) -> (Vec2, Vec2) {
        let p = nodes[i].parent
        if p == noneIndex {
            return (.zero, .zero)
        }
        let o = originDual(Int(p))
        return (Vec2(o.0.x, o.1.x), Vec2(o.0.v, o.1.v))
    }

    func lanesDual1(_ i: Int, _ p: PropId, _ def0: Dual) -> Dual {
        guard let t = nodes[i].tracks[Int(p.rawValue)], let (x, v) = sample(t) else {
            return def0
        }
        return Dual(x: x[0], v: v[0])
    }

    func lanesDual2(_ i: Int, _ p: PropId, _ def0: Dual, _ def1: Dual) -> (Dual, Dual) {
        guard let t = nodes[i].tracks[Int(p.rawValue)], let (x, v) = sample(t) else {
            return (def0, def1)
        }
        return (Dual(x: x[0], v: v[0]), Dual(x: x[1], v: v[1]))
    }

    func lanesDual4(_ i: Int, _ p: PropId, _ def: Dual4) -> Dual4 {
        guard let t = nodes[i].tracks[Int(p.rawValue)], let (x, v) = sample(t) else {
            return def
        }
        return Dual4(
            Dual(x: x[0], v: v[0]),
            Dual(x: x[1], v: v[1]),
            Dual(x: x[2], v: v[2]),
            Dual(x: x[3], v: v[3])
        )
    }

    func worldDual(_ i: Int) -> Dual4 {
        if let path = nodes[i].path {
            return pathDual(i, path, parentTargetOrigin(i))
        }
        return laidDual(i)
    }

    /// Where node `i` is on its screen path, ending at its layout under parent origin `origin`.
    func pathDual(_ i: Int, _ path: ScenePath, _ origin: Vec2) -> Dual4 {
        let (px, py) = lanesDual2(i, prop.travel.id, .c(1.0), .c(1.0))
        let s = path.start.edgesTuple()
        let e = path.endLocal.translated(origin).edgesTuple()
        return Dual4(
            Dual.c(s.0).add(Dual.c(e.0 - s.0).mul(px)),
            Dual.c(s.1).add(Dual.c(e.1 - s.1).mul(py)),
            Dual.c(s.2).add(Dual.c(e.2 - s.2).mul(px)),
            Dual.c(s.3).add(Dual.c(e.3 - s.3).mul(py))
        )
    }

    /// The origin children of `i` ride: layout origin plus offsets (own and presence).
    func originDual(_ i: Int) -> (Dual, Dual) {
        let w = worldDual(i)
        let off = lanesDual2(i, prop.offset.id, .c(0.0), .c(0.0))
        let p = lanesDual1(i, prop.presence.id, .c(1.0))
        let fxA = nodes[i].fxA
        let fxB = nodes[i].fxB
        let fx = { (k: Int) -> Dual in
            Dual.c(fxA[k]).mul(Dual.c(1.0).sub(p)).add(Dual.c(fxB[k]).mul(p))
        }
        let sizeX = w.d2.sub(w.d0)
        let sizeY = w.d3.sub(w.d1)
        let reduced = _store.reducedMotion()
        var ox = w.d0.add(off.0)
        var oy = w.d1.add(off.1)
        if !reduced {
            ox = ox.add(fx(2)).add(fx(4).mul(sizeX))
            oy = oy.add(fx(3)).add(fx(5).mul(sizeY))
        }
        return (ox, oy)
    }

    // ------------------------------------------------------------------------------------------
    // The frame

    /// `setTime(t)`, then ``frame()``.
    @discardableResult
    public func frameAt(_ t: Double) -> FrameOutput {
        setTime(t)
        return frame()
    }

    /// Samples every active track at `now()`, finishes exits, and returns the presented values of
    /// every node that changed. Apply this frame's commits (insert/remove/setFrame/animate)
    /// between `setTime` and `frame`.
    @discardableResult
    public func frame() -> FrameOutput {
        _store.tick()
        // Keep removals made since the last frame (matched geometry), drop last frame's.
        if exitedSeen > 0 {
            if exitedSeen == exited.count {
                exited.removeAll(keepingCapacity: true)
            } else {
                exited.removeSubrange(0..<exitedSeen)
            }
        }
        toRemove.removeAll(keepingCapacity: true)

        // Presence settles: finish entrances, retire exits whose generation is current.
        for ev in _store._events {
            if case .settled(_, let node, let p) = ev {
                if p != prop.presence.id {
                    continue
                }
                guard let iRaw = index[node.rawValue] else { continue }
                let i = Int(iRaw)
                switch nodes[i].phase {
                case .entering:
                    nodes[i].phase = .present
                case .exiting(let generation) where generation == nodes[i].generation:
                    toRemove.append(iRaw)
                default:
                    break
                }
            }
        }

        // An exit nobody can see is over. Presence settles at 1e-5, ~40 frames after the node
        // fades below one 8-bit step; retire it there so whatever waits on the unmount (focus,
        // hit-testing, the next layer) doesn't wait on an invisible tail.
        _store.forEachTouchedTrack { t, node, p in
            if p != prop.presence.id {
                return
            }
            guard let iRaw = index[node.rawValue] else { return }
            let i = Int(iRaw)
            guard case .exiting(let generation) = nodes[i].phase else { return }
            if generation != nodes[i].generation || toRemove.contains(iRaw) {
                return
            }
            guard let presence = _store.withValuesOf(t, { $0[0] }) else { return }
            let fxA0 = nodes[i].fxA[0]
            let fxB0 = nodes[i].fxB[0]
            if fxA0 + (fxB0 - fxA0) * presence < 1.0 / 255.0 {
                toRemove.append(iRaw)
            }
        }

        // Mark what moved; refresh the track cache from the store.
        _store.forEachTouchedTrack { tid, node, p in
            if let iRaw = index[node.rawValue] {
                let i = Int(iRaw)
                nodes[i].dirty = true
                if Int(p.rawValue) < prop.builtinCount {
                    nodes[i].tracks[Int(p.rawValue)] = tid
                }
            }
        }

        // Screen travel ends once it has arrived and no ancestor is still moving or transitioning.
        var k = 0
        while k < travelling.count {
            let i = Int(travelling[k])
            let travelTrack = nodes[i].tracks[Int(prop.travel.id.rawValue)]
            let arrived = travelTrack.map { !_store.isActive($0) } ?? true
            if arrived && !ancestorMoving(i) {
                let endLocal = nodes[i].path?.endLocal ?? nodes[i].frame
                endPath(i)
                trackSet(i, prop.frame, endLocal)
                continue
            }
            let po = parentTargetOrigin(i)
            nodes[i].path?.origin = po
            k += 1
        }

        if orderDirty {
            rebuildOrder()
        }
        out.removeAll(keepingCapacity: true)
        // Written first, so this frame's own values for the same nodes win.
        if !late.isEmpty {
            out.append(contentsOf: late)
            late.removeAll(keepingCapacity: true)
        }
        presentDirty()
        for idx in 0..<toRemove.count {
            let i = Int(toRemove[idx])
            if nodes[i].alive {
                removeNow(i)
            }
        }
        exitedSeen = exited.count
        // A node still travelling waits on an active track of its own or an ancestor's, so this
        // covers it, and a frozen one doesn't keep the frames coming.
        let animating = _store.running()
        if let tr = _trace {
            tr.frame(_store.now(), out, exited, _store.events(), intents)
            intents.removeAll(keepingCapacity: true)
        }
        return FrameOutput(
            changed: out,
            exited: exited,
            events: _store.events(),
            animating: animating
        )
    }

    /// Presents what was set or animated since ``frame()``, without stepping time,
    /// so a value worked out from something that frame moved afterwards (a scroll offset)
    /// shows in the same frame. The motion trace, already written for that frame, records them
    /// with the next.
    public func present() {
        if orderDirty {
            rebuildOrder()
        }
        let from = out.count
        presentDirty()
        if _trace != nil && from < out.count {
            late.append(contentsOf: out[from...])
        }
    }

    /// Recomputes the presented values of dirty nodes and their subtrees, into `out`.
    private func presentDirty() {
        let scale = _store.pixelScale()
        let reduced = _store.reducedMotion()
        for k in 0..<order.count {
            let i = Int(order[k])
            let parent = nodes[i].parent
            let parentDirty = parent != noneIndex && nodes[Int(parent)].dirty
            let own = nodes[i].dirty
            if parentDirty {
                nodes[i].dirty = true
            }
            if nodes[i].dirty {
                let p = compute(i, scale, reduced, own, parentDirty)
                nodes[i].last = p
                out.append(p)
            }
        }
        for k in 0..<order.count {
            let i = Int(order[k])
            nodes[i].dirty = false
        }
    }

    /// An ancestor still moving or changing how it draws its subtree: a node ending screen travel
    /// under it would jump onto its mid-transition offset, scale, opacity or blur.
    private func ancestorMoving(_ i: Int) -> Bool {
        var p = nodes[i].parent
        let checkProps: [PropId] = [
            prop.frame.id,
            prop.travel.id,
            prop.offset.id,
            prop.presence.id,
            prop.scale.id,
            prop.opacity.id,
            prop.blur.id,
        ]
        while p != noneIndex {
            let pi = Int(p)
            for pid in checkProps {
                if let t = nodes[pi].tracks[Int(pid.rawValue)], _store.isActive(t) {
                    return true
                }
            }
            p = nodes[pi].parent
        }
        return false
    }

    @inline(__always)
    private func readValue<R>(
        _ i: Int,
        _ p: PropId,
        _ body: (UnsafeBufferPointer<Float>) -> R
    ) -> R? {
        guard let t = nodes[i].tracks[Int(p.rawValue)] else { return nil }
        return _store.withValuesOf(t, body)
    }

    @inline(__always)
    private func targets(_ i: Int, _ p: PropId) -> LaneStorage? {
        guard let t = nodes[i].tracks[Int(p.rawValue)] else { return nil }
        var out = LaneStorage()
        return _store.targetsOf(t, &out) ? out : nil
    }

    /// Where `compute` would put node `i` with every track at its target. It repeats the same
    /// arithmetic so that, at rest, the two rects are bit-identical.
    private func restOf(_ i: Int, _ reduced: Bool) -> Rect {
        let parent = nodes[i].parent
        let world: Rect
        if let path = nodes[i].path {
            let p = targets(i, prop.travel.id)
            let px = p?[0] ?? 1.0
            let py = p?[1] ?? 1.0
            let s = path.start.edgesTuple()
            let e = path.endLocal.translated(parentTargetOrigin(i)).edgesTuple()
            world = Rect.fromEdges(
                s.0 + (e.0 - s.0) * px,
                s.1 + (e.1 - s.1) * py,
                s.2 + (e.2 - s.2) * px,
                s.3 + (e.3 - s.3) * py
            )
        } else {
            let origin = parent == noneIndex ? .zero : rests[Int(parent)].origin
            let local: Rect
            if let v = targets(i, prop.frame.id) {
                local = v.withBuffer(count: 4) { Rect.readLanes($0) }
            } else {
                local = nodes[i].frame
            }
            world = local.translated(origin)
        }
        let p = targets(i, prop.presence.id)?[0] ?? 1.0
        var s = lerpFx(nodes[i].fxA, nodes[i].fxB, p)
        if reduced {
            s = FxState9(f0: s[0], f1: 1.0, f2: 0.0, f3: 0.0, f4: 0.0, f5: 0.0, f6: 0.0, f7: 0.0, f8: 1.0)
        }
        let own: Vec2
        if let v = targets(i, prop.offset.id) {
            own = v.withBuffer(count: 2) { Vec2.readLanes($0) }
        } else {
            own = .zero
        }
        return world.translated(Vec2(own.x + s[2] + s[4] * world.w, own.y + s[3] + s[5] * world.h))
    }

    private func compute(
        _ i: Int,
        _ scale: Float,
        _ reduced: Bool,
        _ ownDirty: Bool,
        _ parentDirty: Bool
    ) -> Presented {
        let parent = nodes[i].parent
        let parentOrigin = parent == noneIndex ? .zero : nodes[Int(parent)].origin
        let world: Rect
        if let path = nodes[i].path {
            let (px, py) = readValue(i, prop.travel.id) { ($0[0], $0[1]) } ?? (1.0, 1.0)
            let s = path.start.edgesTuple()
            let e = path.endLocal.translated(parentTargetOrigin(i)).edgesTuple()
            world = Rect.fromEdges(
                s.0 + (e.0 - s.0) * px,
                s.1 + (e.1 - s.1) * py,
                s.2 + (e.2 - s.2) * px,
                s.3 + (e.3 - s.3) * py
            )
        } else {
            let local = readValue(i, prop.frame.id) { Rect.readLanes($0) } ?? nodes[i].frame
            var w = local.translated(parentOrigin)
            if nodes[i].rideTrailing && parent != noneIndex {
                let pNode = nodes[Int(parent)]
                w.x += pNode.world.w - pNode.frame.w
            }
            world = w
        }
        let p = readValue(i, prop.presence.id) { $0[0] } ?? 1.0
        var s = lerpFx(nodes[i].fxA, nodes[i].fxB, p)
        if reduced {
            s = FxState9(f0: s[0], f1: 1.0, f2: 0.0, f3: 0.0, f4: 0.0, f5: 0.0, f6: 0.0, f7: 0.0, f8: 1.0)
        }
        let ownOpacity = readValue(i, prop.opacity.id) { $0[0] } ?? nodes[i].opacity
        let ownScale = readValue(i, prop.scale.id) { $0[0] } ?? 1.0
        let ownOffset = readValue(i, prop.offset.id) { Vec2.readLanes($0) } ?? .zero
        let rotation = readValue(i, prop.rotation.id) { $0[0] } ?? 0.0
        let ownBlur = readValue(i, prop.blur.id) { $0[0] } ?? 0.0
        let radius = readValue(i, prop.radius.id) { Corners.readLanes($0) } ?? nodes[i].radius
        let fill = readValue(i, prop.fill.id) { Color.readLanes($0) } ?? nodes[i].fill
        let ownMask = readValue(i, prop.mask.id) { Sides.readLanes($0) } ?? .zero

        let offset = Vec2(
            ownOffset.x + s[2] + s[4] * world.w,
            ownOffset.y + s[3] + s[5] * world.h
        )
        let shown = world.translated(offset)
        let sc = max(ownScale * s[1], 0.0)
        var blurVal = max(ownBlur + s[6], 0.0)
        if blurVal < 1.0 / 64.0 {
            blurVal = 0.0
        }
        var mask = Mask(inset: ownMask, feather: .zero)
        if let rv = nodes[i].reveal {
            let hidden = min(max(s[7], 0.0), 1.0)
            if hidden > 0.0 {
                let (side, lenVal): (Int, Float)
                switch rv.edge {
                case .leading: (side, lenVal) = (0, shown.w)
                case .top: (side, lenVal) = (1, shown.h)
                case .trailing: (side, lenVal) = (2, shown.w)
                case .bottom: (side, lenVal) = (3, shown.h)
                }
                // The content is hidden behind `edge`: the opposite side's inset grows.
                let opposite = (side + 2) % 4
                mask.inset[opposite] += hidden * lenVal
                // The ramp fades in with the wipe instead of popping (min(1, travel / feather)).
                mask.feather[opposite] = rv.feather * min(hidden * lenVal / max(rv.feather, 1e-3), 1.0)
            }
        }
        let anchorPt = Vec2(shown.x + nodes[i].anchor.x * shown.w, shown.y + nodes[i].anchor.y * shown.h)
        var fl: UInt32 = 0
        var ownBits: UInt32 = 0
        for k in 0..<prop.builtinCount {
            if let t = nodes[i].tracks[k], _store.isActive(t) {
                ownBits |= Intent.forProp(PropId(UInt16(k)))
            }
        }
        if nodes[i].path != nil {
            ownBits |= Intent.position | Intent.size
        }
        if ownBits != 0 || (ownDirty && !parentDirty) {
            fl |= flags.animated
        }
        if parentDirty {
            fl |= flags.ancestorAnimated
            let pb: UInt32
            if let lastP = nodes[Int(parent)].last {
                pb = ((lastP.flags >> 8) & 0xff) | ((lastP.flags >> 16) & 0xff)
            } else {
                pb = 0
            }
            fl |= pb << 16
        }
        fl |= ownBits << 8
        if !mask.isNone() {
            fl |= flags.clipped
        }
        if blurVal > 0.0 {
            fl |= flags.filtered
        }
        let isExiting: Bool
        if case .exiting = nodes[i].phase { isExiting = true } else { isExiting = false }
        let inFlow = !isExiting || !nodes[i].transition.popLayout
        let presentedOut = Presented(
            node: nodes[i].id,
            parent: parent != noneIndex ? nodes[Int(parent)].id : nil,
            rect: snap.snapRect(shown, scale),
            opacity: min(max(ownOpacity * s[0], 0.0), 1.0),
            transform: Transform(translate: .zero, scale: Vec2(sc, sc), rotate: rotation),
            anchor: anchorPt,
            blur: blurVal,
            radius: radius,
            fill: fill,
            mask: mask,
            phase: nodes[i].phase,
            inFlow: inFlow,
            flags: fl,
            draw: min(max(s[8], 0.0), 1.0)
        )
        // Where it is is where it rests while nothing that places it is in flight. A node riding
        // its parent's trailing edge also moves with the parent's width.
        let checkSettledProps: [PropId] = [
            prop.travel.id,
            prop.frame.id,
            prop.presence.id,
            prop.offset.id,
        ]
        var allPlacementSettled = true
        for pid in checkSettledProps {
            if let t = nodes[i].tracks[Int(pid.rawValue)], !_store.isSettled(t) {
                allPlacementSettled = false
                break
            }
        }
        let still = !nodes[i].rideTrailing
            && (parent == noneIndex || rests[Int(parent)].origin == nodes[Int(parent)].origin)
            && allPlacementSettled
        let restRect = still ? shown : restOf(i, reduced)
        nodes[i].world = world
        nodes[i].origin = Vec2(shown.x, shown.y)
        rests[i] = Rest(rect: restRect, origin: Vec2(restRect.x, restRect.y), moving: restRect != shown)
        return presentedOut
    }

    /// Unmounts a node and its subtree now (no exit), reporting them in `exited`.
    func removeNow(_ i: Int) {
        // Children first.
        var c = nodes[i].firstChild
        while c != noneIndex {
            let next = nodes[Int(c)].nextSibling
            removeNow(Int(c))
            c = next
        }
        let id = nodes[i].id
        // Unlink from the parent's (or root) child list.
        let parent = nodes[i].parent
        let next = nodes[i].nextSibling
        let prev = nodes[i].prevSibling
        if prev == noneIndex {
            if parent == noneIndex {
                rootHead = next
            } else {
                nodes[Int(parent)].firstChild = next
            }
        } else {
            nodes[Int(prev)].nextSibling = next
        }
        if next == noneIndex {
            if parent == noneIndex {
                rootTail = prev
            } else {
                nodes[Int(parent)].lastChild = prev
            }
        } else {
            nodes[Int(next)].prevSibling = prev
        }
        travelling.removeAll { Int($0) == i }
        _store.removeNode(id)
        index.removeValue(forKey: id.rawValue)
        nodes[i].alive = false
        nodes[i].dirty = false
        nodes[i].firstChild = noneIndex
        nodes[i].lastChild = noneIndex
        nodes[i].nextSibling = noneIndex
        nodes[i].prevSibling = noneIndex
        nodes[i].last = nil
        free.append(UInt32(i))
        exited.append(id)
        orderDirty = true
    }

    private func rebuildOrder() {
        order.removeAll(keepingCapacity: true)
        var r = rootHead
        while r != noneIndex {
            order.append(r)
            r = nodes[Int(r)].nextSibling
        }
        var k = 0
        while k < order.count {
            var c = nodes[Int(order[k])].firstChild
            while c != noneIndex {
                order.append(c)
                c = nodes[Int(c)].nextSibling
            }
            k += 1
        }
        orderDirty = false
    }
}
