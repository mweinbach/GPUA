// Ported from: crates/rune-motion/src/scene/presence.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

extension Scene {
    /// A keyed node appears. On ``Mount/animated`` it enters with its transition's insertion
    /// effect; on ``Mount/initial`` (or under an entering parent, which it rides) it just appears.
    /// If the key is still exiting, ``Mount/animated`` revives it from exactly where it is and
    /// ``Mount/initial`` lands it present, at rest on `spec.frame`.
    public func insert(_ id: NodeId, _ spec: NodeSpec, _ mount: Mount) {
        insertDelayed(id, spec, mount, 0.0)
    }

    /// ``insert(_:_:_:)``, with a new node's entrance held `delay` seconds of its own
    /// clock: it waits whole at its insertion effect (offset, scale, blur, opacity and reveal
    /// together), then plays the entrance on the transition's enter spring. A node that mounts
    /// at once, rides an entering parent or revives mid-exit ignores the delay, and
    /// ``landWaiting(_:)`` lands it. Removed while it waits, it unmounts at
    /// once if its insertion effect is invisible, or else leaves from that effect.
    public func insertDelayed(_ id: NodeId, _ spec: NodeSpec, _ mount: Mount, _ delay: Float) {
        if let i = slot(id) {
            nodes[i].transition = spec.transition
            let exiting: Bool
            if case .exiting = nodes[i].phase {
                exiting = true
            } else {
                exiting = false
            }
            if exiting && mount == .initial {
                presentNow(i)
                // Also lands motion toward an unchanged frame and ends screen travel.
                setFrame(id, spec.frame, LayoutAnim.instant)
                return
            }
            if exiting {
                revive(i)
            }
            if nodes[i].frame != spec.frame && nodes[i].path == nil {
                setFrame(id, spec.frame, LayoutAnim.new(tokens.reflow))
            }
            return
        }
        let parent: UInt32
        if let p = spec.parent {
            guard let pSlot = slot(p) else {
                preconditionFailure("insert \(id): parent \(p) isn't in the scene")
            }
            parent = UInt32(pSlot)
        } else {
            parent = noneIndex
        }
        // A child rides a parent that is still mostly to come. Past half its entrance (and in
        // the ~0.7 s presence tail after it has visibly arrived), riding would show the child at
        // once at most of its opacity, so it enters on its own instead of popping in.
        let ridesParent: Bool
        if parent != noneIndex {
            switch nodes[Int(parent)].phase {
            case .present:
                ridesParent = false
            case .entering:
                ridesParent = presenceNow(Int(parent)) < 0.5
            case .exiting:
                ridesParent = true
            }
        } else {
            ridesParent = false
        }
        let animate = mount == .animated && !ridesParent
        let ins = spec.transition.insertion.kitRules(false)
        let node = SceneNode(
            id: id,
            parent: parent,
            firstChild: noneIndex,
            lastChild: noneIndex,
            nextSibling: noneIndex,
            prevSibling: noneIndex,
            alive: true,
            frame: spec.frame,
            opacity: spec.opacity,
            radius: spec.radius,
            fill: spec.fill,
            transition: spec.transition,
            phase: animate ? .entering : .present,
            generation: 0,
            fxA: fxOf(ins),
            fxB: .identity,
            anchor: ins.anchor,
            reveal: ins.reveal,
            path: nil,
            rideTrailing: false,
            tracks: BuiltinTracks(),
            dirty: true,
            world: .zero,
            origin: .zero,
            last: nil
        )
        let i: UInt32
        if let reused = free.popLast() {
            nodes[Int(reused)] = node
            rests[Int(reused)] = .zero
            i = reused
        } else {
            nodes.append(node)
            rests.append(.zero)
            i = UInt32(nodes.count - 1)
        }
        // Link as the last child (siblings keep insertion order).
        let tail = parent == noneIndex ? rootTail : nodes[Int(parent)].lastChild
        nodes[Int(i)].prevSibling = tail
        if tail == noneIndex {
            if parent == noneIndex {
                rootHead = i
            } else {
                nodes[Int(parent)].firstChild = i
            }
        } else {
            nodes[Int(tail)].nextSibling = i
        }
        if parent == noneIndex {
            rootTail = i
        } else {
            nodes[Int(parent)].lastChild = i
        }
        index[id.rawValue] = i
        orderDirty = true
        let enter = spec.transition.springs.enter
        if animate {
            trackSet(Int(i), prop.presence, Float(0.0))
            let clampedDelay: Float = delay.isFinite ? max(delay, 0.0) : 0.0
            var anim = Anim(enter)
            anim.delay = clampedDelay
            trackAnimate(Int(i), prop.presence, Float(1.0), anim)
            intent(id, Intent.transition | Intent.opacity, enter.duration)
        } else if !atBase(Int(i), prop.presence, Float(1.0)) {
            trackSet(Int(i), prop.presence, Float(1.0))
        }
    }

    /// A present node's transition from its latest render: the removal effect and exit spring it
    /// leaves with, and how it enters if it revives. An entrance already running keeps its look;
    /// an exiting node keeps the transition it is leaving with.
    public func setTransition(_ id: NodeId, _ transition: Transition) {
        if let i = slot(id) {
            if case .exiting = nodes[i].phase {
                return
            }
            nodes[i].transition = transition
        }
    }

    /// The app removed a keyed node. It stays drawn, plays its removal effect on the exit spring,
    /// and is reported in `exited` only once its presence has settled at 0 (opacity 0).
    public func remove(_ id: NodeId) {
        guard let i = slot(id) else { return }
        if case .exiting = nodes[i].phase {
            return
        }
        let p = presenceNow(i)
        let unplayed = p < 1e-3
        if unplayed && lerpFx(nodes[i].fxA, nodes[i].fxB, p)[0] < 1.0 / 512.0 {
            // An entrance that hasn't shown anything yet (a delayed one still waiting) has no
            // exit to play.
            removeNow(i)
            return
        }
        let rem = nodes[i].transition.removal.kitRules(true)
        let target = fxOf(rem)
        nodes[i].generation &+= 1
        nodes[i].phase = .exiting(generation: nodes[i].generation)
        if p >= 0.999 {
            nodes[i].fxA = target
            nodes[i].fxB = .identity
        } else if unplayed {
            // None of the entrance has played, but its insertion effect shows (a slide that
            // doesn't fade): leave from there, as a whole exit from it.
            nodes[i].fxB = lerpFx(nodes[i].fxA, nodes[i].fxB, p)
            nodes[i].fxA = target
        } else {
            // Mid-entrance: keep the current look at p, land exactly on the removal effect at 0.
            let cur = lerpFx(nodes[i].fxA, nodes[i].fxB, p)
            nodes[i].fxA = target
            let denom = max(p, 1e-3)
            for k in 0..<8 {
                nodes[i].fxB[k] = target[k] + (cur[k] - target[k]) / denom
            }
        }
        if rem.scale != 1.0 {
            nodes[i].anchor = rem.anchor
        }
        if rem.reveal != nil {
            nodes[i].reveal = rem.reveal
        }
        nodes[i].dirty = true
        let exit = nodes[i].transition.springs.exit
        if unplayed {
            trackSet(i, prop.presence, Float(1.0))
        } else {
            ensureProp(i, prop.presence)
        }
        trackAnimate(i, prop.presence, Float(0.0), Anim(exit))
        intent(id, Intent.transition | Intent.opacity, exit.duration)
    }

    /// The app removed a keyed node with no exit: it and its subtree unmount now and are reported
    /// in the next frame's `exited`.
    public func unmount(_ id: NodeId) {
        if let i = slot(id) {
            removeNow(i)
        }
    }

    /// An entering node is present at once, its entrance landed: one nobody saw run.
    public func enterNow(_ id: NodeId) {
        if let i = slot(id), nodes[i].phase == .entering {
            presentNow(i)
        }
    }

    /// An entering node that hasn't started to show (a delayed entrance still waiting) is
    /// present at once. One already under way keeps going.
    public func landWaiting(_ id: NodeId) {
        if let i = slot(id), nodes[i].phase == .entering, presenceNow(i) < 1e-3 {
            presentNow(i)
        }
    }

    /// A present node enters again from nothing, as if just mounted: one nobody saw that a
    /// change brings into view.
    public func reenter(_ id: NodeId) {
        if let i = slot(id), nodes[i].phase == .present {
            trackSet(i, prop.presence, Float(0.0))
            revive(i)
        }
    }

    func revive(_ i: Int) {
        let p = presenceNow(i)
        nodes[i].generation &+= 1
        nodes[i].phase = .entering
        if p <= 0.001 {
            let ins = nodes[i].transition.insertion.kitRules(false)
            nodes[i].fxA = fxOf(ins)
        } else {
            // Keep the current look at p, land exactly on identity at 1.
            let cur = lerpFx(nodes[i].fxA, nodes[i].fxB, p)
            let q = max(1.0 - p, 1e-3)
            for k in 0..<8 {
                nodes[i].fxA[k] = (cur[k] - FxState9.identity[k] * p) / q
            }
        }
        nodes[i].fxB = .identity
        nodes[i].dirty = true
        let enter = nodes[i].transition.springs.enter
        let id = nodes[i].id
        trackAnimate(i, prop.presence, Float(1.0), Anim(enter))
        intent(id, Intent.transition | Intent.opacity, enter.duration)
    }

    /// An exiting node is present again at once: no presence effect, nothing left to settle.
    func presentNow(_ i: Int) {
        nodes[i].generation &+= 1
        nodes[i].phase = .present
        let ins = nodes[i].transition.insertion.kitRules(false)
        nodes[i].fxA = fxOf(ins)
        nodes[i].fxB = .identity
        nodes[i].anchor = ins.anchor
        nodes[i].reveal = ins.reveal
        trackSet(i, prop.presence, Float(1.0))
    }

    func presenceNow(_ i: Int) -> Float {
        guard let t = nodes[i].tracks[Int(prop.presence.id.rawValue)],
            let (x, _) = sample(t)
        else {
            return 1.0
        }
        return x[0]
    }
}
