// Ported from: crates/rune-kit/src/checkbox.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Checkbox (`@opencode/ui` forms/checkbox).

import Rune

public struct Checkbox {
    private var labelVal: String?
    private var checkedVal: Bool
    private var indeterminateVal: Bool
    private var hideLabelVal: Bool
    private var descriptionVal: String?
    private var glyphVal: Icon?
    private var stateVal: State
    private var actsVal: Acts

    public init(_ checked: Bool) {
        self.labelVal = nil
        self.checkedVal = checked
        self.indeterminateVal = false
        self.hideLabelVal = false
        self.descriptionVal = nil
        self.glyphVal = nil
        self.stateVal = .rest
        self.actsVal = Acts()
    }

    public static func new(_ checked: Bool) -> Checkbox {
        Checkbox(checked)
    }

    public func label(_ l: String) -> Checkbox {
        var copy = self
        copy.labelVal = l
        return copy
    }

    public func hideLabel() -> Checkbox {
        var copy = self
        copy.hideLabelVal = true
        return copy
    }

    public func description(_ d: String) -> Checkbox {
        var copy = self
        copy.descriptionVal = d
        return copy
    }

    public func indeterminate(_ on: Bool) -> Checkbox {
        var copy = self
        copy.indeterminateVal = on
        return copy
    }

    /// Replace the check mark (the web's `icon` prop), drawn at 14 points.
    public func icon(_ i: Icon) -> Checkbox {
        var copy = self
        copy.glyphVal = i
        return copy
    }

    public func state(_ s: State) -> Checkbox {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> Checkbox {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onToggle<S>(_ f: @escaping (inout S) -> Void) -> Checkbox {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onToggleTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> Checkbox {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let on = checkedVal || indeterminateVal
        let fill: Color
        let border: Color
        switch stateVal {
        case .disabled:
            (fill, border) = (c.surfaceDisabled, c.borderDisabled)
        case .hover:
            (fill, border) = (c.surfaceHover, c.borderHover)
        case .focus:
            (fill, border) = (on ? c.surfaceWeak : Color.TRANSPARENT, c.borderActive)
        default:
            if on {
                (fill, border) = (c.surfaceWeak, c.stdBorder)
            } else {
                (fill, border) = (Color.TRANSPARENT, c.borderWeak)
            }
        }
        let mark: El
        if let g = glyphVal {
            mark = Rune.icon(g, 14.0)
        } else {
            mark = Rune.icon(k.glyph.check, 10.0)
        }
        var control = el()
            .key("control")
            .size(16.0, 16.0)
            .center()
            .radius(k.radius.sm)
            .fill(fill)
            .border(1.0, border)
            .motion(k.motion.control)
            .child(mark.key("mark").color(c.stdIcon).opacity(on ? 1.0 : 0.0))
        if stateVal == .rest {
            control = control.hover(c.surfaceHover)
        }
        var root = row()
            .role("checkbox")
            .gap(12.0)
            .centerY()
            .child(control.focusRing(1.0, 0.0, c.borderActive))
        if let l = labelVal {
            root = root.label(l)
            var content = col().key("content")
            if !hideLabelVal {
                content = content.child(
                    text(l).key("label").font(k.ty.textSmall.lh(24.0)).color(c.stdText)
                )
            }
            if let d = descriptionVal {
                content = content.child(
                    text(d).key("description").font(k.ty.textXsmall.lh(15.6)).color(c.stdText)
                )
            }
            root = root.child(content)
        }
        let enabled = stateVal != .disabled
        return actsVal.apply(root.focusable(enabled), enabled)
    }
}

/// Namespace mirroring `rune_kit::checkbox` module exports.
public enum checkbox {
    public typealias Checkbox = RuneKit.Checkbox
}
