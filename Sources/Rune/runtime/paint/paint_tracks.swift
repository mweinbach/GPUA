// Ported from: crates/rune/src/runtime/paint/tracks.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Node paint property sampling and lazy track allocation for colors, shadows, hover, and press.

import RuneMotion

/// Finds nodes in the previous build in linear order, building a hash map only when out of step.
struct LastBuild {
    private var next: Int = 0
    private var map: [RuneMotion.NodeId: Int]? = nil

    mutating func find(_ old: [Node], _ id: RuneMotion.NodeId) -> Int? {
        let at: Int?
        if old.indices.contains(next) && old[next].nodeId == id {
            at = next
        } else {
            if map == nil {
                var built: [RuneMotion.NodeId: Int] = [:]
                built.reserveCapacity(old.count)
                for (i, n) in old.enumerated() {
                    built[n.nodeId] = i
                }
                map = built
            }
            at = map?[id]
        }
        guard let idx = at else { return nil }
        next = idx + 1
        return idx
    }

    mutating func advance(_ nextIdx: Int) {
        next = nextIdx
    }
}

/// The colour a node's text or icon draws in.
@inline(__always)
func nodeTextColor(_ n: Node) -> Color? {
    if let tc = n.textSpec?.color {
        return tc
    }
    return n.vis.cold.getIfSome?.icon?.1
}

/// Readies `p` (hover, press, press scale), which reads `rest` without a track, to move to `to`.
func readyFromRest(
    _ scene: Scene,
    _ id: RuneMotion.NodeId,
    _ p: Prop<Float>,
    _ rest: Float,
    _ to: Float
) -> Bool {
    if scene.store().has(id, p) {
        return true
    }
    if to == rest {
        return false
    }
    scene.set(id, p, rest)
    return true
}

/// A shadow's geometry as its track holds it (`x, y, blur, spread`).
@inline(__always)
func shadowGeo(_ sh: Shadow) -> RuneMotion.Rect {
    RuneMotion.Rect(sh.x, sh.y, sh.blur, sh.spread)
}

extension Runtime {
    @inline(__always)
    func sampledColor(_ id: RuneMotion.NodeId, _ p: Prop<Color>, _ fallback: Color) -> Color {
        if scene.store().isAnimating(id, p), let sampled = scene.get(id, p) {
            return sampled
        }
        return fallback
    }

    func sampledShadow(_ id: RuneMotion.NodeId, _ index: Int, _ fallback: Shadow) -> Shadow {
        guard index >= 0 && index < 4 else { return fallback }
        var out = fallback
        let base = index * 4
        if scene.store().has(id, P_SHADOW_GEO),
           let g = scene.get(id, P_SHADOW_GEO)
        {
            out.x = g.lanesValue[base]
            out.y = g.lanesValue[base + 1]
            out.blur = g.lanesValue[base + 2]
            out.spread = g.lanesValue[base + 3]
        }
        if scene.store().has(id, P_SHADOWS),
           let c = scene.get(id, P_SHADOWS)
        {
            out.color = Color(
                r: c.lanesValue[base],
                g: c.lanesValue[base + 1],
                b: c.lanesValue[base + 2],
                a: c.lanesValue[base + 3]
            )
        }
        return out
    }

    func commitPaintTrack<T: Animatable & Equatable>(
        _ id: RuneMotion.NodeId,
        _ p: Prop<T>,
        from: T?,
        to: T,
        spring s: Spring,
        instant: Bool
    ) {
        let tracked = scene.store().has(id, p)
        if from == to && !(instant && tracked) {
            return
        }
        if !tracked {
            guard let fromVal = from, !instant else {
                return
            }
            scene.set(id, p, fromVal)
        }
        if instant || reducedMotion {
            scene.set(id, p, to)
        } else {
            scene.animate(id, p, to, s)
        }
    }
}
