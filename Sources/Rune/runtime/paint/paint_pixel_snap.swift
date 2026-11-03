// Ported from: crates/rune/src/runtime/paint/pixel_snap.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Paint-time edge pixel snapping (`El.pixelSnap`), parent centring, motion glide interpolation,
//! rigid scroll translation rounding, and scaled layer settle easing.

import RuneMotion

let PIXEL_SNAP_KEEP_FRAMES: UInt32 = 120
let PIXEL_SNAP_SETTLE_SEC: Double = 0.1

@inline(__always)
func roundHalfUp(_ v: Float) -> Float {
    (v + 0.5).rounded(.down)
}

@inline(__always)
func pixelSnapTextGlide(_ top: Float) -> Float {
    let g = top - top.rounded()
    return abs(g) < (1.0 / 64.0) ? 0.0 : g
}

/// Convenience helper snapping `[x, y, w, h]` in points to the device pixel grid when stationary,
/// leaving moving/scaled boxes sub-pixel smooth.
func pixelSnapRect(_ rect: [Float], scale: Float, moving: Bool) -> [Float] {
    guard rect.count >= 4 else { return [0, 0, 0, 0] }
    guard !moving, scale > 0.0 else { return rect }
    let x0 = rect[0] * scale
    let y0 = rect[1] * scale
    let x1 = (rect[0] + rect[2]) * scale
    let y1 = (rect[1] + rect[3]) * scale
    let sx0 = (x1 - x0 >= 0.5) ? roundHalfUp(x0) : x0
    let sy0 = (y1 - y0 >= 0.5) ? roundHalfUp(y0) : y0
    let sx1 = (x1 - x0 >= 0.5) ? max(roundHalfUp(x1), sx0 + 1.0) : x1
    let sy1 = (y1 - y0 >= 0.5) ? max(roundHalfUp(y1), sy0 + 1.0) : y1
    return [sx0 / scale, sy0 / scale, (sx1 - sx0) / scale, (sy1 - sy0) / scale]
}

struct PixelSnapMotion: Sendable, Equatable {
    var by: [Float]
    var rest: [Float]
    var k: Float
}

func pixelSnapMotion(
    _ p: Presented,
    _ rest: RuneMotion.Rect?,
    _ s: Float,
    anchored: Bool,
    growthRow: Bool
) -> PixelSnapMotion? {
    guard !anchored, let rest else { return nil }
    let a = p.rect.edges()
    let b = rest.edges()
    var by: [Float] = (0..<4).map { (a[$0] - b[$0]) * s }
    if growthRow {
        by[3] = by[1]
    }
    return PixelSnapMotion(by: by, rest: b, k: 1.0)
}

struct PixelSnapRest: Sendable, Equatable {
    var exact: [Float]
    var at: [Float]
}

struct PixelSnapParent: Sendable, Equatable {
    var rest: PixelSnapRest
    var now: PixelSnapRest
    var left: [Float]
}

struct PixelSnapInherit: Sendable, Equatable {
    var off: Bool = false
    var rigid: [Float] = [0.0, 0.0]
    var layer: UInt32 = 0
    var parent: PixelSnapParent? = nil
}

private struct PixelSnapGlide: Sendable {
    var rest: [Float]
    var k: Float
    var restPx: [Float]
    var from: [Float]
    var to: [Float]
    var span: [Float]
    var seen: UInt32
    var follow: [Float]
    var parent: [Float]

    func at(_ idx: Int, _ toVal: Float, _ m: Float, _ followVal: Float) -> Float {
        toVal + (from[idx] - toVal) * left(idx, m, followVal)
    }

    func left(_ idx: Int, _ m: Float, _ followVal: Float) -> Float {
        if abs(span[idx]) > (1.0 / 64.0) {
            return min(max(m / span[idx], -1.0), 1.0)
        }
        return followVal
    }
}

private struct PixelSnapLayer: Sendable {
    var rect: [Float]
    var t: Double
    var seen: UInt32
    var moving: Bool
    var since: Double
    var outs: [([Float], Float)]
}

private struct PixelSnapLayerNow: Sendable {
    var to: Float
    var near: Float
    var outs: [([Float], Float)]
    var rigid: [Float]
}

private let snapIdentityMap: [Float] = [1.0, 0.0, 1.0, 0.0]
private let snapNoLayer = PixelSnapLayerNow(
    to: 0.0,
    near: 0.0,
    outs: [(snapIdentityMap, 0.0), (snapIdentityMap, 0.0)],
    rigid: [0.0, 0.0]
)

@inline(__always)
private func maxEdgeDistance(_ a: [Float], _ b: [Float]) -> Float {
    (0..<4).reduce(Float(0.0)) { max($0, abs(a[$1] - b[$1])) }
}

private func affineMap(_ from: [Float], _ to: [Float]) -> [Float] {
    var map = snapIdentityMap
    for axis in 0..<2 {
        let w = from[axis + 2] - from[axis]
        let toW = to[axis + 2] - to[axis]
        let k: Float = abs(w) > 1e-3 ? (toW / w) : 1.0
        map[axis * 2] = k
        map[axis * 2 + 1] = to[axis] - from[axis] * k
    }
    return map
}

private func mapReach(_ map: [Float], _ size: [Float]) -> Float {
    (0..<2).reduce(Float(0.0)) { acc, a in
        let d0 = abs(map[a * 2 + 1])
        let d1 = abs((map[a * 2] - 1.0) * size[a] + map[a * 2 + 1])
        return max(acc, max(d0, d1))
    }
}

struct PixelSnapGlides: Sendable {
    private var glides: [RuneMotion.NodeId: PixelSnapGlide] = [:]
    private var layers: [RuneMotion.NodeId: PixelSnapLayer] = [:]
    private var nowLayers: [PixelSnapLayerNow] = []
    private var frame: UInt32 = 0
    private var t: Double = 0.0
    private var size: [Float] = [0.0, 0.0]
    private var isEasing: Bool = false

    mutating func beginFrame(_ nowT: Double, _ viewportPx: [Float]) {
        frame &+= 1
        t = nowT
        size = viewportPx
        nowLayers.removeAll(keepingCapacity: true)
        isEasing = false
        let curFrame = frame
        if !glides.isEmpty {
            glides = glides.filter { curFrame &- $0.value.seen < PIXEL_SNAP_KEEP_FRAMES }
        }
        if !layers.isEmpty {
            layers = layers.filter { curFrame &- $0.value.seen < PIXEL_SNAP_KEEP_FRAMES }
        }
    }

    func easing() -> Bool {
        isEasing
    }

    mutating func layer(
        _ id: RuneMotion.NodeId,
        _ rects: ([Float], [Float]),
        _ rigid: [Float],
        cached: Bool
    ) -> UInt32 {
        let (r, unscaled) = rects
        let cur: [Float] = (0..<4).map { r[$0] - rigid[$0 % 2] }
        let nowT = t
        let curFrame = frame
        let winSize = size

        var l = layers[id] ?? PixelSnapLayer(
            rect: cur,
            t: nowT,
            seen: curFrame,
            moving: false,
            since: -.infinity,
            outs: [(cur, 0.0), (cur, 0.0)]
        )
        func eased(_ since: Double) -> Float {
            let x: Float = cached ? 1.0 : Float(min(max((nowT - since) / PIXEL_SNAP_SETTLE_SEC, 0.0), 1.0))
            return x * x * (3.0 - 2.0 * x)
        }

        let to: Float
        if mapReach(affineMap(l.rect, cur), winSize) > (1.0 / 256.0) {
            if !l.moving {
                let f = eased(l.since)
                let a = (l.outs[0].0, l.outs[0].1 * (1.0 - f))
                let b = (l.outs[1].0, l.outs[1].1 * (1.0 - f))
                var candidates = [(l.rect, f), a, b]
                candidates.sort { $0.1 > $1.1 }
                l.outs = [candidates[0], candidates[1]]
                l.moving = true
            }
            l.rect = cur
            l.t = nowT
            to = 0.0
        } else {
            if l.moving {
                l.moving = false
                l.since = l.t
            }
            to = eased(l.since)
            if to == 1.0 {
                l.outs = [(cur, 0.0), (cur, 0.0)]
            }
        }
        l.seen = curFrame
        layers[id] = l

        let outs: [([Float], Float)] = l.outs.map { rest, w in
            w > 0.0 ? (affineMap(cur, rest), w * (1.0 - to)) : (snapIdentityMap, 0.0)
        }
        let near = min(max((1.0 - maxEdgeDistance(r, unscaled)) / (1.0 - 1.0 / 16.0), 0.0), 1.0)
        nowLayers.append(PixelSnapLayerNow(to: to, near: near, outs: outs, rigid: rigid))
        return UInt32(nowLayers.count)
    }

    mutating func atRest(
        _ id: RuneMotion.NodeId,
        _ r: [Float],
        _ rigid: [Float],
        _ parent: PixelSnapParent?
    ) -> ([Float], PixelSnapParent?) {
        if let p = parent, p.left != [0.0, 0.0, 0.0, 0.0],
           (0..<2).contains(where: { axis in
               snapRestingCentred(p.rest, axis, (r[axis] - rigid[axis], r[axis + 2] - rigid[axis])) != nil
           })
        {
            let (out, nextParent) = glide(
                id,
                PixelSnapMotion(by: [0.0, 0.0, 0.0, 0.0], rest: r, k: 1.0),
                r,
                rigid,
                p
            )
            return (out, nextParent)
        }
        if !glides.isEmpty {
            glides.removeValue(forKey: id)
        }
        let (out, rest) = pixelSnapEdges(r, [0.0, 0.0, 0.0, 0.0], rigid, parent?.rest) { _, c in c }
        return (out, PixelSnapParent(rest: rest, now: rest, left: [0.0, 0.0, 0.0, 0.0]))
    }

    mutating func snapped(
        _ id: RuneMotion.NodeId,
        _ motion: PixelSnapMotion?,
        _ rects: ([Float], [Float]),
        _ rigid: [Float],
        _ layerAndScale: (UInt32, Float),
        _ parentIn: PixelSnapParent?
    ) -> ([Float], PixelSnapParent?) {
        let (r, unscaled) = rects
        let (layerIdx, sc) = layerAndScale
        let l = layerIdx > 0 ? nowLayers[Int(layerIdx - 1)] : snapNoLayer
        let weight: Float = (layerIdx == 0)
            ? min(max((1.0 - maxEdgeDistance(r, unscaled)) / (1.0 - 1.0 / 16.0), 0.0), 1.0)
            : l.near
        var out = r
        let plain = (layerIdx == 0 && weight >= 1.0)
        let parent = plain ? parentIn : nil
        var restOut: PixelSnapParent? = nil

        if weight > 0.0 && l.to < 1.0 {
            let snapped: [Float]
            let at: PixelSnapParent?
            if let m = motion {
                if l.to == 0.0 {
                    let (gOut, gAt) = glide(id, m, unscaled, rigid, parent)
                    snapped = gOut
                    at = gAt
                } else {
                    snapped = pixelSnapEdges(unscaled, m.by, rigid, nil) { _, c in c }.0
                    at = nil
                }
            } else {
                (snapped, at) = atRest(id, unscaled, rigid, parent)
            }
            restOut = plain ? at : nil
            for k in 0..<4 {
                out[k] += (snapped[k] - r[k]) * weight * (1.0 - l.to)
            }
        }
        if layerIdx == 0 {
            return (out, restOut)
        }

        let lr = l.rigid
        let scaledRigid: [Float] = [
            lr[0] + (rigid[0] - lr[0]) * sc,
            lr[1] + (rigid[1] - lr[1]) * sc,
        ]
        var left: Float = 0.0
        for (map, wRaw) in l.outs {
            if wRaw <= 0.0 || weight >= 1.0 { continue }
            let mapped: [Float] = (0..<4).map { k in
                let a = k % 2
                return (r[k] - lr[a]) * map[a * 2] + map[a * 2 + 1] + lr[a]
            }
            let w = wRaw * (1.0 - weight) * min(max(1.0 - maxEdgeDistance(r, mapped), 0.0), 1.0)
            let (at, _) = pixelSnapEdges(mapped, [0.0, 0.0, 0.0, 0.0], scaledRigid, nil) { _, c in c }
            for k in 0..<4 {
                let c = (at[k] - mapped[k]) * w
                out[k] += c
                left = max(left, abs(c))
            }
        }

        let at: [Float]
        if let m = motion, l.to > 0.0 {
            let scaledM = PixelSnapMotion(by: m.by.map { $0 * sc }, rest: m.rest, k: sc)
            at = glide(id, scaledM, r, scaledRigid, nil).0
        } else if l.to > 0.0 {
            at = atRest(id, r, scaledRigid, nil).0
        } else {
            at = pixelSnapEdges(r, [0.0, 0.0, 0.0, 0.0], scaledRigid, nil) { _, c in c }.0
        }

        if l.to == 1.0 {
            return (at, nil)
        }
        for k in 0..<4 {
            out[k] += (at[k] - r[k]) * l.to
            left = max(left, abs(at[k] - r[k]) * (1.0 - l.to))
        }
        if left > (1.0 / 128.0) {
            isEasing = true
        }
        return (out, nil)
    }

    private mutating func glide(
        _ id: RuneMotion.NodeId,
        _ m: PixelSnapMotion,
        _ r: [Float],
        _ rigid: [Float],
        _ parent: PixelSnapParent?
    ) -> ([Float], PixelSnapParent) {
        let free: [Float] = (0..<4).map { r[$0] - rigid[$0 % 2] }
        let follow = parent?.left ?? [0.0, 0.0, 0.0, 0.0]
        let parentRest = parent?.rest.exact ?? [0.0, 0.0, 0.0, 0.0]

        var g: PixelSnapGlide
        if let existing = glides[id], existing.rest == m.rest && existing.k == m.k {
            g = existing
            if g.parent != parentRest {
                for k in 0..<4 where abs(g.span[k]) <= (1.0 / 64.0) {
                    g.from[k] = g.at(k, g.to[k], 0.0, g.follow[k])
                }
            }
        } else {
            let from: [Float]
            if let prev = glides[id] {
                from = (0..<4).map { k in prev.at(k, prev.to[k], free[k] - prev.restPx[k], prev.follow[k]) }
            } else {
                from = snapStartCorrection(r, rigid, parent?.now)
            }
            let restPx: [Float] = (0..<4).map { free[$0] - m.by[$0] }
            g = PixelSnapGlide(
                rest: m.rest,
                k: m.k,
                restPx: restPx,
                from: from,
                to: from,
                span: m.by,
                seen: 0,
                follow: follow,
                parent: parentRest
            )
        }

        let (out, rest) = pixelSnapEdges(r, m.by, rigid, parent?.rest) { k, c in
            g.to[k] = c
            return g.at(k, c, m.by[k], follow[k])
        }
        g.seen = frame
        g.follow = follow
        g.parent = parentRest
        glides[id] = g

        let now = PixelSnapRest(
            exact: free,
            at: (0..<4).map { out[$0] - roundHalfUp(rigid[$0 % 2]) }
        )
        let leftArr: [Float] = (0..<4).map { g.left($0, m.by[$0], follow[$0]) }
        return (out, PixelSnapParent(rest: rest, now: now, left: leftArr))
    }
}

func pixelSnapEdges(
    _ r: [Float],
    _ motion: [Float],
    _ rigid: [Float],
    _ parent: PixelSnapRest?,
    _ ease: (Int, Float) -> Float
) -> ([Float], PixelSnapRest) {
    var out = r
    var rest = PixelSnapRest(exact: [0, 0, 0, 0], at: [0, 0, 0, 0])
    for axis in 0..<2 {
        let a = axis
        let b = axis + 2
        let restA = r[a] - motion[a] - rigid[axis]
        let restB = r[b] - motion[b] - rigid[axis]
        rest.exact[a] = restA
        rest.exact[b] = restB
        rest.at[a] = restA
        rest.at[b] = restB
        if restB - restA < 0.5 {
            continue
        }
        let shift = roundHalfUp(rigid[axis])
        let (lo, hi): (Float, Float)
        if let p = parent, let centred = snapRestingCentred(p, axis, (restA, restB)) {
            (lo, hi) = centred
        } else {
            let l = roundHalfUp(restA)
            (lo, hi) = (l, max(roundHalfUp(restB), l + 1.0))
        }
        rest.at[a] = lo
        rest.at[b] = hi
        for (k, restVal, atVal) in [(a, restA, lo), (b, restB, hi)] {
            let c = atVal - restVal
            let eased = ease(k, c)
            out[k] = (eased == c ? atVal : (restVal + eased)) + shift + motion[k]
        }
    }
    return (out, rest)
}

func pixelSnapFrames(_ v: Visual) -> Bool {
    let border = v.borderWidth > 0.0 && (v.border.a > 0.0 || v.borderBottom != nil)
    return v.fill.a > 0.0 || v.hover.a > 0.0 || v.press.a > 0.0 || border
}

private func snapStartCorrection(_ r: [Float], _ rigid: [Float], _ parent: PixelSnapRest?) -> [Float] {
    var now: [Float] = [0, 0, 0, 0]
    _ = pixelSnapEdges(r, [0, 0, 0, 0], rigid, nil) { k, c in
        now[k] = c
        return c
    }
    guard let p = parent else { return now }
    for axis in 0..<2 {
        let a = axis
        let b = axis + 2
        let ra = r[a] - rigid[axis]
        let rb = r[b] - rigid[axis]
        if rb - ra < 0.5 { continue }
        if let (lo, hi) = snapCentred(p, (a, b), (ra, rb), slack: 1.0) {
            let w = 1.0 - abs((ra - p.exact[a]) - (p.exact[b] - rb))
            now[a] += (lo - ra - now[a]) * w
            now[b] += (hi - rb - now[b]) * w
        }
    }
    return now
}

private func snapRestingCentred(_ parent: PixelSnapRest, _ axis: Int, _ span: (Float, Float)) -> (Float, Float)? {
    let a = axis
    let b = axis + 2
    if parent.at[a] != parent.at[a].rounded(.towardZero) || parent.at[b] != parent.at[b].rounded(.towardZero) {
        return nil
    }
    return snapCentred(parent, (a, b), span, slack: 1.0 / 16.0)
}

private func snapCentred(
    _ parent: PixelSnapRest,
    _ edges: (Int, Int),
    _ span: (Float, Float),
    slack: Float
) -> (Float, Float)? {
    let (a, b) = edges
    let (ra, rb) = span
    let pa = parent.exact[a], pb = parent.exact[b]
    let qa = parent.at[a], qb = parent.at[b]
    if abs((ra - pa) - (pb - rb)) >= slack {
        return nil
    }
    let gap = roundHalfUp((qb - qa - (rb - ra)) * 0.5)
    guard qb - qa - 2.0 * gap >= 1.0 else { return nil }
    return (qa + gap, qb - gap)
}
