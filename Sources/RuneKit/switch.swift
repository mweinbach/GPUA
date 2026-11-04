// Ported from: crates/rune-kit/src/switch.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Switch (`@opencode/ui` forms/switch): compact (default) and standard appearances.

import Rune

public struct Switch {
    private var labelVal: String?
    private var checkedVal: Bool
    private var standardVal: Bool
    private var sizeVal: ControlSize
    private var hideLabelVal: Bool
    private var descriptionVal: String?
    private var stateVal: State
    private var actsVal: Acts

    public init(_ checked: Bool) {
        self.labelVal = nil
        self.checkedVal = checked
        self.standardVal = false
        self.sizeVal = .mini
        self.hideLabelVal = false
        self.descriptionVal = nil
        self.stateVal = .rest
        self.actsVal = Acts()
    }

    public static func new(_ checked: Bool) -> Switch {
        Switch(checked)
    }

    public func label(_ l: String) -> Switch {
        var copy = self
        copy.labelVal = l
        return copy
    }

    /// The visible label stays for accessibility only.
    public func hideLabel() -> Switch {
        var copy = self
        copy.hideLabelVal = true
        return copy
    }

    public func description(_ d: String) -> Switch {
        var copy = self
        copy.descriptionVal = d
        return copy
    }

    /// The older, larger look (`appearance="standard"`).
    public func standard() -> Switch {
        var copy = self
        copy.standardVal = true
        return copy
    }

    /// The track and knob of an `NSSwitch` of this size on macOS 27: Mini (36 × 16, the size
    /// System Settings uses) unless set. The standard appearance keeps its own size.
    public func controlSize(_ s: ControlSize) -> Switch {
        var copy = self
        copy.sizeVal = s
        return copy
    }

    public func state(_ s: State) -> Switch {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> Switch {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    /// Called with the switch's press (flip your own state there).
    public func onToggle<S>(_ f: @escaping (inout S) -> Void) -> Switch {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onToggleTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> Switch {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let hover = stateVal == .hover
        let disabled = stateVal == .disabled
        var control = standardVal ? standardControl(k, hover) : compactControl(k)
        if disabled && !standardVal {
            control = control.dim(0.5)
        }
        if stateVal == .focus && !standardVal {
            control = control.outline(2.0, 1.0, c.borderFocus)
        }
        var root = row().role("switch").gap(8.0).centerY()
        if let l = labelVal {
            root = root.label(l)
            if !hideLabelVal {
                let font: TextStyle
                let color: Color
                if standardVal {
                    font = k.ty.textSmall.lh(16.0)
                    color = c.stdText
                } else {
                    font = k.ty.small.lh(16.0)
                    color = c.textFaint
                }
                root = root.child(text(l).key("label").font(font).color(color))
            }
        }
        if let d = descriptionVal {
            root = root.child(
                text(d).key("description").font(k.ty.textXsmall.lh(15.6)).color(c.stdText)
            )
        }
        root = root.child(control.key("control").focusRing(2.0, 1.0, c.borderFocus))
        return actsVal.apply(root.focusable(!disabled), !disabled)
    }

    private func compactControl(_ k: Kit) -> El {
        let c = k.c
        let hover = stateVal == .hover
        let base: Color
        let sheenBottom: Color
        let elevation: [Shadow]
        let knob: Color
        if checkedVal {
            base = c.bgAccent
            sheenBottom = k.lightOn(0.1, c.bgAccent)
            elevation = k.elevation.switchOn
            knob = c.knobOn
        } else {
            base = c.layer04
            sheenBottom = k.lightOn(0.2, c.layer04)
            elevation = k.elevation.switchOff
            knob = c.knob
        }
        let overlay = checkedVal ? k.on(c.contrastHover, c.bgAccent) : c.hover
        // NSSwitch's capsule track and pill knob, measured on macOS 27: (track w, h, knob w, h, inset).
        let tw: Float
        let th: Float
        let kw: Float
        let kh: Float
        let inset: Float
        switch sizeVal {
        case .mini: (tw, th, kw, kh, inset) = (36.0, 16.0, 21.0, 14.0, 1.0)
        case .small: (tw, th, kw, kh, inset) = (44.0, 20.0, 26.0, 16.0, 2.0)
        case .regular: (tw, th, kw, kh, inset) = (54.0, 24.0, 32.0, 20.0, 2.0)
        case .large: (tw, th, kw, kh, inset) = (64.0, 28.0, 38.0, 24.0, 2.0)
        case .extraLarge: (tw, th, kw, kh, inset) = (80.0, 36.0, 48.0, 30.0, 3.0)
        }
        // The knob stretches towards the middle on hover, and further while pressed.
        let stretch: Float
        switch stateVal {
        case .hover:
            stretch = (kh * 0.15).rounded(.toNearestOrAwayFromZero)
        case .pressed:
            stretch = (kh * 0.35).rounded(.toNearestOrAwayFromZero)
        default:
            stretch = 0.0
        }
        let w = kw + stretch
        let x = checkedVal ? (tw - inset - w) : inset
        let thumb = shadows(
            k,
            el()
                .key("thumb")
                .size(w, kh)
                .absolute(x, inset)
                .radius(kh / 2.0)
                .fill(knob)
                .gradient(k.on(c.depthTop, knob), k.on(c.depthBottom, knob))
                .border(0.5, k.on(c.depthTop, knob)),
            k.elevation.elements
        )
        .motion(k.motion.control)
        let fill = hover ? over(overlay, base) : base
        var track = el()
            .size(tw, th)
            .radius(th / 2.0)
            .fill(fill)
            .gradient(k.light(0.0), sheenBottom)
        if !hover && stateVal == .rest {
            track = track.hover(overlay)
        }
        return shadows(k, track, elevation).motion(k.motion.control).child(thumb)
    }

    private func standardControl(_ k: Kit, _ hover: Bool) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let fill: Color
        let border: Color
        if disabled {
            (fill, border) = (c.surfaceDisabled, c.borderDisabled)
        } else if hover {
            (fill, border) = (c.surfaceHover, c.borderHover)
        } else if checkedVal {
            (fill, border) = (c.stdIconStrong, c.stdIconStrong)
        } else {
            (fill, border) = (c.surfaceBase, c.borderWeak)
        }
        // A content-box thumb (14 + 1 px border each side) nudged 1 px left over the 1 px track
        // border; when on it loses its border and moves 12 px right. Pressed, it stretches
        // towards the middle.
        let thumbFill = disabled ? c.stdIcon : c.stdIconInvert
        let stretch: Float = stateVal == .pressed ? 4.0 : 0.0
        var thumb = el().key("thumb").fill(thumbFill)
        if checkedVal {
            thumb = thumb.size(14.0 + stretch, 14.0).absolute(13.0 - stretch, 1.0).radius(7.0)
        } else {
            thumb = thumb.size(16.0 + stretch, 16.0).absolute(0.0, 0.0).radius(8.0).border(1.0, c.stdBorder)
        }
        thumb = shadows(k, thumb, k.elevation.knob).motion(k.motion.control)
        return el()
            .size(28.0, 16.0)
            .radius(8.0)
            .fill(fill)
            .border(1.0, border)
            .motion(k.motion.control)
            .child(thumb)
    }
}

/// Namespace mirroring `rune_kit::switch` module exports.
public enum `switch` {
    public typealias Switch = RuneKit.Switch
}
