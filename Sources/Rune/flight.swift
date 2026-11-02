// Ported from: crates/rune/src/flight.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Tx.flyText` and `Tx.launch` requests, and the text handoff in screen coordinates.

import RuneMotion

struct TextFlight: Sendable {
    var sourceKey: String
    var targetKey: String
    var source: RuneMotion.Rect
    var sourceClip: [Float]
    var glyphs: [Instance]
    var scale: Float
    var destination: RuneMotion.Rect
    var progress: Animated<Float>
    var born: Double
    var presented: RuneMotion.Rect
    var clip: [Float]
    var sourceAlpha: Float
    var targetAlpha: Float

    init(
        sourceKey: String,
        targetKey: String,
        source: RuneMotion.Rect,
        sourceClip: [Float],
        glyphs: [Instance],
        scale: Float,
        now: Double
    ) {
        var prog = Animated<Float>.new(0.0).withClass(.opacity)
        prog.animateTo(1.0, GROWTH, now)
        self.sourceKey = sourceKey
        self.targetKey = targetKey
        self.source = source
        self.sourceClip = sourceClip
        self.glyphs = glyphs
        self.scale = scale
        self.destination = source
        self.progress = prog
        self.born = now
        self.presented = source
        self.clip = sourceClip
        self.sourceAlpha = 1.0
        self.targetAlpha = 0.0
    }

    func progressAt(_ now: Double, _ reduced: Bool) -> Float {
        if reduced {
            return Float(min(max((now - born) / 0.15, 0.0), 1.0))
        } else {
            return min(max(progress.sample(now), 0.0), 1.0)
        }
    }

    mutating func measure(_ target: RuneMotion.Rect, _ now: Double, _ reduced: Bool) -> Bool {
        destination = target
        let p: Float = reduced ? 1.0 : progressAt(now, false)
        let from = source
        presented = RuneMotion.Rect(
            from.x + (target.x - from.x) * p,
            from.y + (target.y - from.y) * p,
            from.w + (target.w - from.w) * p,
            from.h + (target.h - from.h) * p
        )
        return reduced ? (progressAt(now, true) >= 1.0) : progress.isSettled(now)
    }

    func departs(_ path: String, _ key: String?) -> Bool {
        selectsKeyPath(sourceKey, path, key)
    }

    func lands(_ path: String, _ key: String?) -> Bool {
        selectsKeyPath(targetKey, path, key)
    }

    func alphas(_ target: RuneMotion.Rect, _ now: Double, _ reduced: Bool) -> (Float, Float) {
        let p = progressAt(now, reduced)
        if reduced {
            return (1.0 - p, p)
        }
        let rewrap = abs(target.h - source.h) > 2.0
        let (out, end): (Float, Float) = rewrap ? (0.25, 0.4) : (0.4, 0.5)
        let srcA = min(max(1.0 - p / out, 0.0), 1.0)
        let dstA: Float = rewrap
            ? min(max((p - 0.1) / (end - 0.1), 0.0), 1.0)
            : min(max(p / end, 0.0), 1.0)
        return (srcA, dstA)
    }
}

/// Whether `selector` names the node at `path` keyed `key`: either its key, or a key path such as `msg-42/body`.
func selectsKeyPath(_ selector: String, _ path: String, _ key: String?) -> Bool {
    guard let key else { return false }
    if selector == key { return true }
    let suffix = "/" + key
    guard selector.hasSuffix(suffix), path.hasSuffix(suffix) else { return false }
    let scope = selector.dropLast(suffix.count)
    let above = path.dropLast(suffix.count)
    let keyedAncestors = above.split(separator: "/", omittingEmptySubsequences: false)
        .reversed()
        .filter { !$0.hasPrefix("#") }
    let scopeSegs = scope.split(separator: "/", omittingEmptySubsequences: false).reversed()
    var iter = keyedAncestors.makeIterator()
    for seg in scopeSegs {
        guard let next = iter.next(), next == seg else { return false }
    }
    return true
}

func selectsUnderKeyPath(_ selector: String, _ path: String, _ key: String) -> Bool {
    if selector == key { return true }
    let suffix = "/" + key
    guard selector.hasSuffix(suffix) else { return false }
    let scope = selector.dropLast(suffix.count)
    let keyedAncestors = path.split(separator: "/", omittingEmptySubsequences: false)
        .reversed()
        .filter { !$0.hasPrefix("#") }
    let scopeSegs = scope.split(separator: "/", omittingEmptySubsequences: false).reversed()
    var iter = keyedAncestors.makeIterator()
    for seg in scopeSegs {
        guard let next = iter.next(), next == seg else { return false }
    }
    return true
}

func transformedFlightInstance(
    _ qIn: Instance,
    _ from: RuneMotion.Rect,
    _ to: RuneMotion.Rect,
    _ scale: Float,
    _ alpha: Float,
    _ clip: [Float],
    _ fade: [Float]
) -> Instance {
    var q = qIn
    let zoom = to.w / max(from.w, 0.01)
    q.uv[2] = q.rect[2]
    q.uv[3] = q.rect[3]
    q.rect = [
        (to.x + (q.rect[0] / scale - from.x) * zoom) * scale,
        (to.y + (q.rect[1] / scale - from.y) * zoom) * scale,
        q.rect[2] * zoom,
        q.rect[3] * zoom,
    ]
    q.fill = q.fill.map { $0 * alpha }
    q.clip = clip.map { $0 * scale }
    q.fade = packFade(fade.map { $0 * scale }, q.clip, q.clip)
    return q
}
