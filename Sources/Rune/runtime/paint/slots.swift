// Ported from: crates/rune/src/runtime/paint/slots.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Paint records that keep a place in the painter stream for pixels Rune doesn't paint itself:
//! effect slots a compositor fills (`El.effect`) and backdrop blurs (`El.backdropBlur`).

@inline(__always)
func clampCornerRadius(_ radii: [Float], _ w: Float, _ h: Float) -> Float {
    let half = max(min(w, h) * 0.5, 0.0)
    let r = radii.first.map { abs($0) } ?? 0.0
    return min(max(r, 0.0), half)
}

/// Pushes an effect slot tagged `mark` over `rect` with corner `radii`, clipped by `clip` and the
/// packed `fade`, at `kPx` device pixels per point and paint opacity `o`.
/// Returns the index of the slot instance when wrapped in a faded layer.
@discardableResult
func pushEffectSlot(
    _ instances: inout [Instance],
    mark: UInt32,
    backdrop: Bool = false,
    bleed: Float = 0.0,
    data: [Float] = [0.0, 0.0, 0.0, 0.0],
    rect: [Float],
    radii: [Float],
    clip: [Float],
    fade: [UInt32],
    kPx: Float,
    opacity o: Float
) -> Int? {
    let slot = Instance(
        rect: rect,
        radii: radii,
        fill: [0.0, 0.0, 0.0, 1.0],
        border: [Float(mark & 0xffff), Float(mark >> 16), 0.0, 0.0],
        params: [backdrop ? 1.0 : 0.0, KIND_EFFECT, bleed * kPx, kPx],
        uv: data,
        clip: clip,
        fade: fade
    )
    if o >= 1.0 {
        instances.append(slot)
        return nil
    }
    var marker = Instance.beginLayer(rect, clip, LayerSpec(opacity: o))
    marker.fade = fade
    instances.append(marker)
    var innerSlot = slot
    innerSlot.clip = NO_CLIP
    instances.append(innerSlot)
    instances.append(Instance.endLayer())
    return instances.count - 2
}

/// Pushes a backdrop blur record (`El.backdropBlur`) of `sigma` points over `rect` with corner
/// `radii` (continuous when `continuous`), cut by `clip`, soft edges `fade` from `fadeOrigin`
/// and an ancestor's rounded clip `rounded`, at `kPx` device pixels per point and opacity `o`.
/// Returns the signed corner radius an outer shadow leaves clear over the blur.
@discardableResult
func pushBackdropBlur(
    _ instances: inout [Instance],
    sigma: Float,
    rect: [Float],
    radii: [Float],
    continuous: Bool,
    clip: [Float],
    fade: [Float],
    fadeOrigin: [Float],
    rounded: ([Float], [Float])?,
    kPx: Float,
    opacity o: Float
) -> Float {
    let resolvedClip: [Float]
    let roundRadii: [Float]?
    if let (mask, rRadii) = rounded {
        let cut = intersectClips(clip, mask)
        if cut == mask {
            resolvedClip = mask
            roundRadii = rRadii
        } else {
            resolvedClip = cut
            roundRadii = nil
        }
    } else {
        resolvedClip = clip
        roundRadii = nil
    }

    var record = Instance(
        rect: rect,
        radii: continuous ? radii.map { -$0 } : radii,
        fill: [0.0, 0.0, 0.0, o],
        border: [0.0, 0.0, 0.0, 0.0],
        params: [sigma * kPx, KIND_BACKDROP_BLUR, 0.0, kPx],
        uv: [0.0, 0.0, 0.0, 0.0],
        clip: resolvedClip,
        fade: packFade(fade, fadeOrigin, resolvedClip)
    )
    if let rr = roundRadii {
        record.roundClipCorners(rr)
    }
    instances.append(record)
    let radius = clampCornerRadius(radii, rect[2], rect[3])
    return continuous ? -radius : radius
}
