// Ported from: crates/rune-motion/src/animated.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

// PORT NOTE: Inline 16-layer storage replaces `[Layer; MAX_LANES]` so `Animated<T>` and `LoopTrack`
// stay stack-allocated value types without heap allocations.
private struct LayerStorage16: Sendable, Equatable {
    var l0: Layer = .rest
    var l1: Layer = .rest
    var l2: Layer = .rest
    var l3: Layer = .rest
    var l4: Layer = .rest
    var l5: Layer = .rest
    var l6: Layer = .rest
    var l7: Layer = .rest
    var l8: Layer = .rest
    var l9: Layer = .rest
    var l10: Layer = .rest
    var l11: Layer = .rest
    var l12: Layer = .rest
    var l13: Layer = .rest
    var l14: Layer = .rest
    var l15: Layer = .rest

    @inline(__always)
    subscript(_ index: Int) -> Layer {
        get {
            switch index {
            case 0: return l0
            case 1: return l1
            case 2: return l2
            case 3: return l3
            case 4: return l4
            case 5: return l5
            case 6: return l6
            case 7: return l7
            case 8: return l8
            case 9: return l9
            case 10: return l10
            case 11: return l11
            case 12: return l12
            case 13: return l13
            case 14: return l14
            case 15: return l15
            default: preconditionFailure("Layer index \(index) out of range 0..<\(maxLanes)")
            }
        }
        set {
            switch index {
            case 0: l0 = newValue
            case 1: l1 = newValue
            case 2: l2 = newValue
            case 3: l3 = newValue
            case 4: l4 = newValue
            case 5: l5 = newValue
            case 6: l6 = newValue
            case 7: l7 = newValue
            case 8: l8 = newValue
            case 9: l9 = newValue
            case 10: l10 = newValue
            case 11: l11 = newValue
            case 12: l12 = newValue
            case 13: l13 = newValue
            case 14: l14 = newValue
            case 15: l15 = newValue
            default: preconditionFailure("Layer index \(index) out of range 0..<\(maxLanes)")
            }
        }
    }
}

/// One retargetable value of type `T`.
public struct Animated<T: Animatable>: Sendable {
    private var _target: LaneStorage
    private var _layers: LayerStorage16
    private var _curve: Curve
    private var _eps: Eps

    /// At rest at `value`. Settle thresholds default to `PropClass.other`.
    public init(_ value: T) {
        self._target = lanes(value)
        self._layers = LayerStorage16()
        self._curve = .instant
        self._eps = PropClass.other.eps(2.0)
    }

    public static func new(_ value: T) -> Animated<T> {
        Animated(value)
    }

    /// Uses `propClass`'s settle thresholds (at 2× pixel scale).
    public func withClass(_ propClass: PropClass) -> Animated<T> {
        var copy = self
        copy._eps = propClass.eps(2.0)
        return copy
    }

    /// Jumps to `value` (direct manipulation).
    public mutating func set(_ value: T) {
        _target = lanes(value)
        _layers = LayerStorage16()
        _curve = .instant
    }

    /// Animates to `target` from the exact state at `now`. An unchanged target is a no-op.
    /// Always merges; `anim.delay` and additive blending need the store.
    public mutating func animateTo(_ target: T, _ anim: some AnimExt, _ now: Double) {
        let a = anim.intoAnim()
        assert(a.delay == 0.0, "Animated doesn't schedule delays; use AnimationStore")
        let tg = lanes(target)
        let explicitVelocity: Float?
        switch a.velocity {
        case .inherit:
            explicitVelocity = nil
        case .zero:
            explicitVelocity = 0.0
        case .uniform(let u):
            explicitVelocity = u
        }
        if explicitVelocity == nil {
            var unchanged = true
            for i in 0..<T.lanes {
                if tg[i] != _target[i] {
                    unchanged = false
                    break
                }
            }
            if unchanged {
                return
            }
        }
        _curve = a.curve
        for i in 0..<T.lanes {
            let (o, v) = _layers[i].sample(now)
            restartLane(i, _target[i] + o, explicitVelocity ?? v, tg[i], a.curve, now)
        }
    }

    /// Restarts lane `i` at `x` with velocity `v`. One layer per lane here, so every curve
    /// merges from the exact (x, v); decay picks its own target.
    private mutating func restartLane(
        _ i: Int,
        _ x: Float,
        _ v: Float,
        _ target: Float,
        _ curve: Curve,
        _ now: Double
    ) {
        if case .decay(let d) = curve {
            _target[i] = x + v / d.k()
            _layers[i] = Layer.decay(d.k(), now, v, _eps)
        } else {
            _target[i] = target
            _layers[i] = Layer.start(curve, now, x - target, v, _eps)
        }
    }

    /// Moves the animation onto a clock reading `delta` more, at the same place.
    mutating func shift(_ delta: Double) {
        for i in 0..<maxLanes {
            _layers[i].t0 += delta
            _layers[i].end += delta
        }
    }

    /// Retargets on the curve last used.
    public mutating func retarget(_ target: T, _ now: Double) {
        let curve = _curve
        animateTo(target, curve, now)
    }

    /// Gesture handoff: continue from the current position with `velocity` on `curve`.
    public mutating func release(
        _ velocity: T,
        _ target: T,
        _ curve: some CurveConvertible,
        _ now: Double
    ) {
        let v = lanes(velocity)
        let tg = lanes(target)
        let c = curve.intoCurve()
        _curve = c
        for i in 0..<T.lanes {
            let x = _target[i] + _layers[i].sample(now).0
            restartLane(i, x, v[i], tg[i], c, now)
        }
    }

    /// Value at `now`.
    public func sample(_ now: Double) -> T {
        var out = LaneStorage()
        for i in 0..<T.lanes {
            out[i] = _target[i] + _layers[i].sample(now).0
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    /// Velocity at `now`, units per second.
    public func velocity(_ now: Double) -> T {
        var out = LaneStorage()
        for i in 0..<T.lanes {
            out[i] = _layers[i].sample(now).1
        }
        return out.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    public func target() -> T {
        _target.withBuffer(count: T.lanes) { T.readLanes($0) }
    }

    /// When every lane is within its settle thresholds for good.
    public func settleTime() -> Double {
        var best = -Double.infinity
        for i in 0..<T.lanes {
            let l = _layers[i]
            if l.kind != .rest && l.end > best {
                best = l.end
            }
        }
        return best
    }

    public func isSettled(_ now: Double) -> Bool {
        now >= settleTime()
    }
}
