// Ported from: crates/rune/src/runtime/anchor.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Anchored overlay placement (`El.anchored`, `El.anchoredFit`, `El.anchoredUnscaled`, `El.above`),
//! including scale compensation and viewport clamping.

struct ResolvedAnchor: Sendable, Equatable {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
    var side: Side
    var scale: Float
}

/// Resolve an anchored overlay's target rect `[x, y, w, h]`, chosen `Side`, and effective scale.
func resolveAnchoredOverlay(
    _ anchor: Anchor,
    triggerBounds: [Float],
    triggerScale: Float,
    measuredSize: (Float, Float),
    viewport: (Float, Float),
    margin: Float = 8.0
) -> ResolvedAnchor {
    let (ww, wh) = viewport
    let effectiveScale: Float = anchor.unscaled ? 1.0 : max(triggerScale, 0.001)
    let rawW = measuredSize.0
    let rawH = measuredSize.1
    let scaledW = rawW * effectiveScale
    let scaledH = rawH * effectiveScale

    let tx0 = triggerBounds[0]
    let ty0 = triggerBounds[1]
    let tx1 = triggerBounds[2]
    let ty1 = triggerBounds[3]
    let gap = anchor.gap

    var side = anchor.side
    switch side {
    case .bottom:
        let spaceBelow = (wh - margin) - (ty1 + gap)
        let spaceAbove = (ty0 - gap) - margin
        if scaledH > spaceBelow && spaceAbove > spaceBelow {
            side = .top
        }
    case .top:
        let spaceAbove = (ty0 - gap) - margin
        let spaceBelow = (wh - margin) - (ty1 + gap)
        if scaledH > spaceAbove && spaceBelow > spaceAbove {
            side = .bottom
        }
    case .right:
        let spaceRight = (ww - margin) - (tx1 + gap)
        let spaceLeft = (tx0 - gap) - margin
        if scaledW > spaceRight && spaceLeft > spaceRight {
            side = .left
        }
    case .left:
        let spaceLeft = (tx0 - gap) - margin
        let spaceRight = (ww - margin) - (tx1 + gap)
        if scaledW > spaceLeft && spaceRight > spaceLeft {
            side = .right
        }
    }

    var finalScaledW = scaledW
    var finalScaledH = scaledH
    if anchor.fit {
        let maxAvailW: Float
        let maxAvailH: Float
        switch side {
        case .bottom:
            maxAvailW = max(0.0, ww - 2.0 * margin)
            maxAvailH = max(0.0, (wh - margin) - (ty1 + gap))
        case .top:
            maxAvailW = max(0.0, ww - 2.0 * margin)
            maxAvailH = max(0.0, (ty0 - gap) - margin)
        case .right:
            maxAvailW = max(0.0, (ww - margin) - (tx1 + gap))
            maxAvailH = max(0.0, wh - 2.0 * margin)
        case .left:
            maxAvailW = max(0.0, (tx0 - gap) - margin)
            maxAvailH = max(0.0, wh - 2.0 * margin)
        }
        finalScaledW = min(finalScaledW, maxAvailW)
        finalScaledH = min(finalScaledH, maxAvailH)
    }

    var sx: Float
    var sy: Float
    switch side {
    case .top, .bottom:
        sy = (side == .top) ? (ty0 - gap - finalScaledH) : (ty1 + gap)
        switch anchor.align {
        case .start: sx = tx0
        case .center: sx = (tx0 + tx1 - finalScaledW) * 0.5
        case .end: sx = tx1 - finalScaledW
        }
    case .left, .right:
        sx = (side == .left) ? (tx0 - gap - finalScaledW) : (tx1 + gap)
        switch anchor.align {
        case .start: sy = ty0
        case .center: sy = (ty0 + ty1 - finalScaledH) * 0.5
        case .end: sy = ty1 - finalScaledH
        }
    }

    let maxX = max(margin, ww - margin - finalScaledW)
    let maxY = max(margin, wh - margin - finalScaledH)
    sx = min(max(sx, margin), maxX)
    sy = min(max(sy, margin), maxY)

    let unscaledW = finalScaledW / effectiveScale
    let unscaledH = finalScaledH / effectiveScale
    // Since scaling happens around the node's center, adjust unscaled top-left so visual scaled box starts at `(sx, sy)`.
    let cx = sx + finalScaledW * 0.5
    let cy = sy + finalScaledH * 0.5
    let ux = cx - unscaledW * 0.5
    let uy = cy - unscaledH * 0.5

    return ResolvedAnchor(
        x: ux,
        y: uy,
        w: unscaledW,
        h: unscaledH,
        side: side,
        scale: effectiveScale
    )
}
