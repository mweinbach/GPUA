// Ported from: crates/rune/src/el/visuals.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Visual builders: fill, corners, borders, shadows, gradients, opacity, blur, transforms,
//! clips and hover groups.

import RuneMotion

extension El {
    public func fill(_ c: Color) -> El {
        var copy = self
        copy.vis.fill = c
        return copy
    }

    /// Spine compatibility alias for ``fill(_:)``.
    public func bg(_ color: Color) -> El {
        fill(color)
    }

    public func radius(_ r: Float) -> El {
        var copy = self
        copy.vis.radius = [r, r, r, r]
        return copy
    }

    /// Spine compatibility alias for ``radius(_:)``.
    public func rounded(_ r: Float) -> El {
        radius(r)
    }

    /// Round the corners with Apple's continuous curve (`CALayerCornerCurve.continuous`, SwiftUI's
    /// `.continuous` style).
    public func continuousCorners() -> El {
        var copy = self
        copy.vis.continuousCorners = true
        return copy
    }

    /// Per-corner radius: top-left, top-right, bottom-right, bottom-left.
    public func corners(_ r: [Float]) -> El {
        var copy = self
        if r.count >= 4 {
            copy.vis.radius = [r[0], r[1], r[2], r[3]]
        }
        return copy
    }

    /// Per-corner radius using a `RuneMotion.Corners` value.
    public func corners(_ corners: Corners) -> El {
        var copy = self
        copy.vis.corners = corners
        return copy
    }

    /// A ring `width` points wide just inside the border box, following the corner radii.
    public func border(_ width: Float, _ c: Color) -> El {
        var copy = self
        copy.vis.borderWidth = width
        copy.vis.border = c
        copy.vis.cold.modifyIfPresent { cold in
            cold.borderBottom = nil
        }
        return copy
    }

    /// A border whose colour runs from `top` at the top edge to `bottom` at the bottom edge.
    public func borderGradient(_ width: Float, _ top: Color, _ bottom: Color) -> El {
        var copy = self
        copy.vis.borderWidth = width
        copy.vis.border = top
        copy.vis.cold.value.borderBottom = bottom
        return copy
    }

    /// Dashes the border (`border` or `borderGradient`): `dash` points on, `gap` points off,
    /// with butt ends, along the ring's centre line.
    public func borderDash(_ dash: Float, _ gap: Float) -> El {
        var copy = self
        let valid = dash.isFinite && gap.isFinite && dash > 0.0 && gap > 0.0
        let v: [Float]? = valid ? [dash, gap] : nil
        if v != nil || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.borderDash = v
        }
        return copy
    }

    /// Starts the dash pattern `phase` points into itself (SwiftUI's `dashPhase`).
    public func borderDashPhase(_ phase: Float) -> El {
        var copy = self
        let p = phase.isFinite ? phase : 0.0
        if p != 0.0 || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.borderDashPhase = p
        }
        return copy
    }

    /// An outer drop shadow offset by `(0, y)` with CSS `blur` radius (`blur = 2σ`).
    public func shadow(_ y: Float, _ blur: Float, _ color: Color) -> El {
        var copy = self
        copy.vis.cold.value.shadows.append(Shadow(x: 0.0, y: y, blur: blur, spread: 0.0, color: color, inset: false))
        return copy
    }

    /// A full box shadow (offset, spread, inset), e.g. one layer of a CSS elevation token.
    public func boxShadow(_ s: Shadow) -> El {
        var copy = self
        copy.vis.cold.value.shadows.append(s)
        return copy
    }

    /// A vertical gradient from `top` to `bottom` painted over the fill (`linear-gradient(180deg, ..)`).
    public func gradient(_ top: Color, _ bottom: Color) -> El {
        var copy = self
        copy.vis.cold.value.gradient = [top, bottom]
        return copy
    }

    /// A radial gradient painted over the fill and clipped to the element's rounded corners.
    public func radialGradient(
        _ center: [Float],
        _ radius: RadialRadius,
        _ stops: [(Float, Color)]
    ) -> El {
        var copy = self
        let rx = radius.values.count > 0 ? radius.values[0] : 0.0
        let ry = radius.values.count > 1 ? radius.values[1] : 0.0
        let valid = center.count >= 2
            && center[0].isFinite
            && center[1].isFinite
            && rx.isFinite
            && ry.isFinite
            && rx > 0.0
            && ry > 0.0
        let r: RadialGradient? = valid
            ? normalizeGradientStops(.radial(center: [center[0], center[1]], radius: [rx, ry]), stops)
            : nil
        if r != nil || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.radial = r
        }
        return copy
    }

    /// Convenience overload of ``radialGradient(_:_:_:)`` for circular radius `r`.
    public func radialGradient(
        _ center: [Float],
        _ radius: Float,
        _ stops: [(Float, Color)]
    ) -> El {
        radialGradient(center, RadialRadius(radius), stops)
    }

    /// A linear gradient at `angle` radians (CSS convention: `0.0` is bottom-to-top, `PI / 2` is
    /// left-to-right, `PI` is top-to-bottom like ``gradient(_:_:)``) with up to 8 stops, painted over
    /// the fill.
    public func linearGradient(_ angle: Float, _ stops: [(Float, Color)]) -> El {
        var copy = self
        let r: RadialGradient? = angle.isFinite ? normalizeGradientStops(.linear(angle: angle), stops) : nil
        if r != nil || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.radial = r
        }
        return copy
    }

    /// Paints `shape` (strokes and fills in this element's points, origin top-left) over the
    /// fill and under any text.
    public func shape(_ shape: Shape) -> El {
        var copy = self
        let sh: Shape? = shape.isEmpty ? nil : shape
        if sh != nil || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.shape = sh
        }
        return copy
    }

    /// Shows `pixels`, scaled into the element's rect and clipped to its corner radius.
    public func pixels(_ pixels: Pixels) -> El {
        var copy = self
        copy.vis.cold.modify { cold in
            cold.pixels = pixels
            cold.pixelsFit = nil
        }
        return copy
    }

    /// Shows `pixels` at its own aspect ratio, centred (`Fit` letterboxes, `Fill` covers and crops).
    public func pixelsFit(_ pixels: Pixels, _ fit: SurfaceFit) -> El {
        var copy = self
        copy.vis.cold.modify { cold in
            cold.pixels = pixels
            cold.pixelsFit = fit
        }
        return copy
    }

    /// A ring `offset` points outside the border box (CSS `outline` + `outline-offset`).
    public func outline(_ width: Float, _ offset: Float, _ color: Color) -> El {
        var copy = self
        copy.vis.cold.value.outline = Outline(width: width, offset: offset, color: color)
        return copy
    }

    public func opacity(_ o: Float) -> El {
        var copy = self
        copy.vis.opacity = o
        return copy
    }

    /// Gaussian blur of the completed subtree, in points (standard deviation).
    public func blur(_ sigma: Float) -> El {
        var copy = self
        let clamped = max(sigma, 0.0)
        copy.vis.blur = clamped
        if clamped != 0.0 || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.layerBlur = clamped
        }
        return copy
    }

    /// Override the blur target's curve. Ordinary changes use the element's motion spring.
    public func blurMotion(_ anim: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.blurMotion = anim.intoAnim()
        return copy
    }

    /// Dim each paint leaf in the currently built subtree, independently.
    public func dim(_ alpha: Float) -> El {
        func apply(_ e: inout El, _ alpha: Float) {
            e.expandMemo()
            e.vis.paintAlpha *= alpha
            for i in e.children.indices {
                apply(&e.children[i], alpha)
            }
        }
        var copy = self
        let clamped = min(max(alpha, 0.0), 1.0)
        apply(&copy, clamped)
        return copy
    }

    /// Add children's premultiplied colours while a direct child is between opacity 0 and 1.
    public func dissolve() -> El {
        var copy = self
        copy.vis.blend = .plusLighter
        return copy
    }

    /// Rasterize this subtree once into an offscreen texture when settled and composite that
    /// texture until the subtree's draw output changes.
    public func cache() -> El {
        var copy = self
        copy.vis.cache = true
        return copy
    }

    /// Cache this subtree like ``cache()``, also mixing `key` into its invalidation signature.
    public func cacheKey(_ key: UInt64) -> El {
        var copy = self
        copy.vis.cache = true
        copy.vis.cold.value.cacheKey = key
        return copy
    }

    /// Tags this element's instances (and its descendants', until one sets its own) for a compositor.
    public func mark(_ mark: UInt32) -> El {
        var copy = self
        copy.vis.mark = mark
        return copy
    }

    /// Overlay drawn over the fill while hovered.
    public func hover(_ c: Color) -> El {
        var copy = self
        copy.vis.hover = c
        return copy
    }

    /// Overlay drawn over the fill while pressed.
    public func press(_ c: Color) -> El {
        var copy = self
        copy.vis.press = c
        return copy
    }

    /// Shrink to `scale` about the centre while a press on this element is held.
    public func pressScale(_ scale: Float) -> El {
        var copy = self
        let s: Float? = (scale.isFinite && scale > 0.0 && scale != 1.0) ? scale : nil
        if s != nil || !copy.handlers.isEmpty {
            copy.handlers.value.pressScale = s
        }
        return copy
    }

    /// Draw this element and everything in it `k` times its size about its centre.
    public func scale(_ k: Float) -> El {
        var copy = self
        copy.scaleValue = (k.isFinite && k >= 0.0) ? k : 1.0
        return copy
    }

    /// The curve ``scale(_:)`` changes on.
    public func scaleMotion(_ anim: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.scaleMotion = anim.intoAnim()
        return copy
    }

    /// Draw this element and everything in it turned `radians` clockwise about its ``origin(_:_:)``.
    public func rotate(_ radians: Float) -> El {
        var copy = self
        copy.vis.rotate = radians.isFinite ? radians : 0.0
        return copy
    }

    /// The curve ``rotate(_:)`` changes on.
    public func rotateMotion(_ anim: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.rotateMotion = anim.intoAnim()
        return copy
    }

    /// The point this element scales and rotates about, in units of its own size (`(0.5, 0.5)` is centre).
    public func origin(_ x: Float, _ y: Float) -> El {
        var copy = self
        let o: [Float]? = (x.isFinite && y.isFinite && (x != 0.5 || y != 0.5)) ? [x, y] : nil
        if o != nil || !copy.vis.cold.isEmpty {
            copy.vis.cold.value.origin = o
        }
        return copy
    }

    /// Run the animations of this element and everything in it at `k` times normal speed.
    public func timeScale(_ k: Float) -> El {
        var copy = self
        copy.timeScaleValue = (k.isFinite && k >= 0.0) ? k : 1.0
        return copy
    }

    /// Spine compatibility rectangular clip flag.
    public func clip(_ enabled: Bool = true) -> El {
        var copy = self
        copy.vis.clip = enabled
        return copy
    }

    /// Clip children to this box with soft gradient edges (never a hard crop).
    public func clipSoft(_ fade: Float) -> El {
        var copy = self
        copy.vis.cold.value.clip = [fade, fade, fade, fade]
        return copy
    }

    /// Clip this element and its descendants to its presented rounded rectangle.
    public func clipRounded(_ radius: Float) -> El {
        var copy = self
        copy.vis.cold.modify { cold in
            cold.clipCorners = nil
            cold.clipRadius = max(radius, 0.0)
        }
        return copy
    }

    /// Clip this element and its descendants to its presented rectangle with per-corner radii
    /// `[topLeft, topRight, bottomRight, bottomLeft]` in points.
    public func clipCorners(_ radii: [Float]) -> El {
        var copy = self
        guard radii.count >= 4 else { return copy }
        let clamped = [max(radii[0], 0.0), max(radii[1], 0.0), max(radii[2], 0.0), max(radii[3], 0.0)]
        let maxR = clamped.reduce(Float(0.0), max)
        copy.vis.cold.modify { cold in
            cold.clipCorners = clamped
            cold.clipRadius = maxR
        }
        return copy
    }

    /// Soft clip with a fade width per side (`left`, `top`, `right`, `bottom`).
    public func clipFade(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> El {
        var copy = self
        copy.vis.cold.value.clip = [left, top, right, bottom]
        return copy
    }

    /// Track hover for descendants' `group_*` styles.
    public func hoverGroup() -> El {
        var copy = self
        copy.vis.hoverGroup = true
        return copy
    }

    /// Curves for this element's hover track: `enter` when the pointer arrives, `exit` when it leaves.
    public func hoverMotion(_ enter: some AnimExt, _ exit: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.hoverMotion = (enter.intoAnim(), exit.intoAnim())
        return copy
    }

    /// Default hover curves for this element and everything below it without its own ``hoverMotion(_:_:)``.
    public func hoverMotionWithin(_ enter: some AnimExt, _ exit: some AnimExt) -> El {
        var copy = self
        copy.vis.cold.value.hoverWithin = (enter.intoAnim(), exit.intoAnim())
        return copy
    }

    /// The pair set by ``hoverMotionWithin(_:_:)``.
    public func hoverWithinCurves() -> (Anim, Anim)? {
        vis.cold.getIfSome?.hoverWithin
    }

    /// Opacity factor `rest` normally and `hovered` while the nearest ancestor group is hovered.
    public func groupOpacity(_ rest: Float, _ hovered: Float) -> El {
        var copy = self
        copy.vis.cold.value.groupOpacity = [rest, hovered]
        return copy
    }

    /// Text or icon colour while the nearest ancestor group is hovered.
    public func groupColor(_ c: Color) -> El {
        var copy = self
        copy.vis.cold.value.groupColor = c
        return copy
    }

    /// Hovering this element shows only its own hover: ancestor hover overlays and `group_*` styles rest.
    public func hoverAlone() -> El {
        var copy = self
        copy.vis.cold.value.hoverAlone = true
        return copy
    }

    /// Wall-clock opacity loop, using the shared loop engine and host wake deadline.
    public func cycle(_ c: Cycle) -> El {
        looping(LoopSpec.cycle(c))
    }
}
