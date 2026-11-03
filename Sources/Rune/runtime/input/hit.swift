// Ported from: crates/rune/src/runtime/input/hit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Hit-testing in reverse paint order, respecting `inert`, clip bounds, rounded corners, `Turn` inverse
//! rotation, overlay `aboveAnchor` z-layers, and transparent pick options.

import RuneMotion

func pointInClip(_ x: Float, _ y: Float, clip: [Float], radii: Corners = .zero) -> Bool {
    guard clip.count >= 4 else { return true }
    guard x >= clip[0] && x < clip[2] && y >= clip[1] && y < clip[3] else { return false }
    let w = clip[2] - clip[0]
    let h = clip[3] - clip[1]
    if w <= 0.0 || h <= 0.0 { return false }
    return pointInRoundedRect(x, y, rect: [clip[0], clip[1], w, h], corners: radii)
}

func pointInRoundedRect(_ x: Float, _ y: Float, rect: [Float], corners: Corners) -> Bool {
    guard rect.count >= 4 else { return false }
    let rx = rect[0]
    let ry = rect[1]
    let rw = rect[2]
    let rh = rect[3]
    guard rw > 0.0 && rh > 0.0 else { return false }
    guard x >= rx && x < rx + rw && y >= ry && y < ry + rh else { return false }

    let maxRadius = min(rw, rh) * 0.5
    let tl = min(abs(corners.c0), maxRadius)
    let tr = min(abs(corners.c1), maxRadius)
    let br = min(abs(corners.c2), maxRadius)
    let bl = min(abs(corners.c3), maxRadius)
    if tl <= 0.0 && tr <= 0.0 && br <= 0.0 && bl <= 0.0 {
        return true
    }

    let lx = x - rx
    let ly = y - ry
    if lx < tl && ly < tl {
        let dx = tl - lx
        let dy = tl - ly
        return dx * dx + dy * dy <= tl * tl
    }
    if lx > rw - tr && ly < tr {
        let dx = lx - (rw - tr)
        let dy = tr - ly
        return dx * dx + dy * dy <= tr * tr
    }
    if lx > rw - br && ly > rh - br {
        let dx = lx - (rw - br)
        let dy = ly - (rh - br)
        return dx * dx + dy * dy <= br * br
    }
    if lx < bl && ly > rh - bl {
        let dx = bl - lx
        let dy = ly - (rh - bl)
        return dx * dx + dy * dy <= bl * bl
    }
    return true
}

extension Runtime {
    /// Return paint-ordered node indices (normal flow first, anchored overlays on top).
    func paintOrderedNodeIndices() -> [Int] {
        guard !nodes.isEmpty else { return [] }
        var normal: [Int] = []
        var overlays: [Int] = []
        normal.reserveCapacity(nodes.count)

        func walk(_ idx: Int, inOverlay: Bool) {
            let isOverlay = inOverlay || (nodes[idx].aboveAnchor != nil)
            if isOverlay {
                overlays.append(idx)
            } else {
                normal.append(idx)
            }
            for c in nodes[idx].children {
                walk(c, inOverlay: isOverlay)
            }
        }
        walk(0, inOverlay: false)
        normal.append(contentsOf: overlays)
        return normal
    }

    func hitTestNode(
        _ x: Float,
        _ y: Float,
        includeTransparent: Bool = true,
        requireInteractive: Bool = false
    ) -> Int? {
        ensureClean()
        let order = paintOrderedNodeIndices()
        for idx in order.reversed() {
            let n = nodes[idx]
            if n.inert { continue }
            let p = scene.presented(n.nodeId)
            let op = (p?.opacity ?? n.vis.opacity) * n.groupOpacityAccum
            if !includeTransparent && op <= 1e-3 {
                continue
            }
            if !pointInClip(x, y, clip: n.clipBounds, radii: n.clipRadii) {
                continue
            }
            let (ux, uy) = n.turn.unturn((x, y))
            if !pointInRoundedRect(ux, uy, rect: n.presentedRect, corners: n.vis.corners) {
                continue
            }
            if requireInteractive {
                let interactive = n.onPressHandler != nil
                    || n.onSecondaryPressHandler != nil
                    || n.onDragHandler != nil
                    || n.onHoverHandler != nil
                    || n.input != nil
                    || n.focusSpec.enabled
                    || (n.textSpec?.selectable == true)
                    || !(n.textSpec?.links.isEmpty ?? true)
                if !interactive {
                    continue
                }
            }
            return idx
        }
        return nil
    }

    func hitTestScrollContainer(_ x: Float, _ y: Float) -> Int? {
        let order = paintOrderedNodeIndices()
        for idx in order.reversed() {
            let n = nodes[idx]
            guard n.scrollSpec != nil, !n.inert else { continue }
            if !pointInClip(x, y, clip: n.clipBounds, radii: n.clipRadii) { continue }
            if pointInRoundedRect(x, y, rect: n.presentedRect, corners: n.vis.corners) {
                return idx
            }
        }
        return nil
    }
}
