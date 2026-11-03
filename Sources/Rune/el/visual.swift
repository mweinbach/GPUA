// Ported from: crates/rune/src/el/visual.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `Visual`: hot inline paint fields on `El` and `Node`, with rarely set extras behind `Cold`.

import RuneMotion

/// Rarely set visual extras shared behind `Cold<VisualCold>` so common boxes and text stay compact.
public struct VisualCold {
    public var surface: (NativeSurface, SurfaceFit)? = nil
    /// Where a surface or `pixelsFit` image sits in the rect (`El.surfaceAnchor`, `El.surfaceUnscaled`).
    public var surfacePlace: SurfacePlace = SurfacePlace()
    /// Bottom colour of a vertical border gradient whose top is `border` (`El.borderGradient`).
    public var borderBottom: Color? = nil
    /// Dash and gap lengths of a dashed border, in points (`El.borderDash`).
    public var borderDash: [Float]? = nil
    /// Points into the dash pattern where it starts (`El.borderDashPhase`).
    public var borderDashPhase: Float = 0.0
    public var shadows: [Shadow] = []
    public var blurMotion: Anim? = nil
    /// Soft clip of children to this rect: fade widths left, top, right, bottom.
    public var clip: [Float]? = nil
    /// Rounded clip of this element and its subtree, applied after subtree filters.
    public var clipRadius: Float? = nil
    /// Per-corner clip radii override (`[tl, tr, br, bl]`, in points).
    var clipCorners: [Float]? = nil
    public var icon: (Icon, Color)? = nil
    /// Vertical linear gradient `[top, bottom]` painted over the fill, under hover/press overlays.
    public var gradient: [Color]? = nil
    /// Radial or angled linear gradient painted over the fill, under hover/press overlays.
    var radial: RadialGradient? = nil
    public var outline: Outline? = nil
    /// Vector strokes and fills in the element's own points, over the fill.
    public var shape: Shape? = nil
    /// An RGBA image scaled into the element's rect, over the fill and shape.
    public var pixels: Pixels? = nil
    /// How `pixels` keeps its aspect ratio; `nil` stretches it to the rect.
    public var pixelsFit: SurfaceFit? = nil
    /// An effect slot (`El.effect`).
    var effect: EffectSlot? = nil
    /// Spine compatibility alias for the effect mark when set via `El.effect`.
    public var effectMark: UInt32? = nil
    /// Backdrop blur standard deviation in points (`El.backdropBlur`); 0 is off.
    public var backdropBlur: Float = 0.0
    /// Spine compatibility alias for `Visual.blur`.
    public var layerBlur: Float = 0.0
    /// The hover track's enter and exit curves (default: snappy spring both ways).
    public var hoverMotion: (Anim, Anim)? = nil
    /// Hover curves for this element and the hover tracks below it without their own.
    var hoverWithin: (Anim, Anim)? = nil
    /// Opacity factor `[rest, hovered]` following the nearest ancestor group's hover.
    public var groupOpacity: [Float]? = nil
    /// Text or icon colour while the nearest ancestor group is hovered.
    public var groupColor: Color? = nil
    /// `El.hoverAlone`: while the pointer is on this element, the hover tracks of the
    /// elements it sits inside stay off.
    public var hoverAlone: Bool = false
    /// `El.iconRotation`: the icon's turn in radians, clockwise.
    public var iconTurn: Float = 0.0
    /// Optional app-supplied key mixed into the cached subtree's signature (`El.cacheKey`).
    var cacheKey: UInt64? = nil
    var offsetMotion: Anim? = nil
    /// The curve `El.scale` changes on.
    var scaleMotion: Anim? = nil
    /// `El.origin`: the unit point scale and rotation pivot about; `nil` is the centre.
    var origin: [Float]? = nil
    /// The curve `El.rotate` changes on.
    var rotateMotion: Anim? = nil
    /// `El.childExit`: how children removed in a commit leave, in place of their own.
    var childExit: Transition? = nil
    /// `El.enterDelay`: seconds a new element holds its insertion effect before entering.
    var enterDelay: Float = 0.0

    public init() {}
}

extension VisualCold: ColdEmpty {
    static var emptyValue: VisualCold { VisualCold() }
}

public struct Visual {
    public var fill: Color = .TRANSPARENT
    public var border: Color = .TRANSPARENT
    public var hover: Color = .TRANSPARENT
    public var press: Color = .TRANSPARENT
    public var borderBottom: Color? {
        get { cold.getIfSome?.borderBottom }
        set {
            if newValue != nil || !cold.isEmpty {
                cold.value.borderBottom = newValue
            }
        }
    }
    public var radius: [Float] = [0.0, 0.0, 0.0, 0.0]
    public var corners: Corners {
        get {
            Corners(
                radius.count > 0 ? radius[0] : 0.0,
                radius.count > 1 ? radius[1] : 0.0,
                radius.count > 2 ? radius[2] : 0.0,
                radius.count > 3 ? radius[3] : 0.0
            )
        }
        set {
            radius = [newValue.c0, newValue.c1, newValue.c2, newValue.c3]
        }
    }
    /// `El.offset`: a visual shift in points, and the curve it moves on.
    var offset: [Float] = [0.0, 0.0]
    public var borderWidth: Float = 0.0
    public var opacity: Float = 1.0
    /// Spine compatibility alias for group opacity override.
    public var groupOpacity: Float? = nil
    /// Static alpha of this element's own paint; never inherited or isolated.
    public var paintAlpha: Float = 1.0
    public var blur: Float = 0.0
    /// `El.rotate`, in radians clockwise.
    var rotate: Float = 0.0
    /// App-defined tag a compositor reads per instance (`Runtime.marks`); 0 inherits the parent's.
    public var mark: UInt32 = 0
    /// Rectangular native input region for overlays using `OverlayInput.regions`.
    public var hit: Bool = false
    /// Corners follow Apple's continuous curve instead of circular arcs (`El.continuousCorners`).
    public var continuousCorners: Bool = false
    public var blend: Rune.Blend = .sourceOver
    /// Tracks hover for its descendants' `group_*` styles even without a hover colour.
    public var hoverGroup: Bool = false
    /// Rasterize this subtree once into an offscreen texture when settled (`El.cache`).
    var cache: Bool = false
    /// `El.raise`: paints and takes input above the rest of the window.
    var raise: Bool = false
    /// `El.pixelSnap(false)`: this subtree paints at its exact fractional rects.
    var noPixelSnap: Bool = false
    /// `El.rideTrailing`: x holds against the parent's trailing edge while its width moves.
    var rideTrailing: Bool = false
    /// Spine compatibility rectangular clip flag.
    public var clip: Bool = false
    var cold: Cold<VisualCold> = Cold()

    public init() {}
}
