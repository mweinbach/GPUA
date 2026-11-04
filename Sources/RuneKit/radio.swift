// Ported from: crates/rune-kit/src/radio.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! RadioGroup and RadioItem (`@opencode/ui` forms/radio).

import Rune

public struct RadioItem {
    private var labelVal: String
    private var descriptionVal: String?
    private var checkedVal: Bool
    private var stateVal: State
    var invalidVal: Bool
    private var actsVal: Acts

    public init(_ label: String, _ checked: Bool) {
        self.labelVal = label
        self.descriptionVal = nil
        self.checkedVal = checked
        self.stateVal = .rest
        self.invalidVal = false
        self.actsVal = Acts()
    }

    public static func new(_ label: String, _ checked: Bool) -> RadioItem {
        RadioItem(label, checked)
    }

    public func description(_ d: String) -> RadioItem {
        var copy = self
        copy.descriptionVal = d
        return copy
    }

    public func state(_ s: State) -> RadioItem {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> RadioItem {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onSelect<S>(_ f: @escaping (inout S) -> Void) -> RadioItem {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onSelectTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> RadioItem {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let disabled = stateVal == .disabled
        let hover = stateVal == .hover
        let base: Color
        let sheen: Color
        if checkedVal {
            (base, sheen) = (c.bgAccent, k.lightOn(0.2, c.bgAccent))
        } else if invalidVal {
            (base, sheen) = (c.danger.bg, k.light(0.0))
        } else {
            (base, sheen) = (c.bgBase, k.light(0.06))
        }
        let overlay = checkedVal ? k.on(c.contrastHover, c.bgAccent) : c.hover
        let ring = (invalidVal && !checkedVal) ? c.danger.border : c.borderStrong
        var control = el()
            .key("control")
            .size(16.0, 16.0)
            .absolute(0.0, 2.0)
            .radius(8.0)
            .fill(hover ? over(overlay, base) : base)
            .gradient(sheen, k.light(0.0))
            .boxShadow(Shadow(spread: 0.5, color: ring, inset: true))
            .motion(k.motion.control)
        control = control.focusRing(2.0, 1.0, c.borderFocus)
        if checkedVal {
            let dot = c.knobOn
            control = control.child(
                el()
                    .key("dot")
                    .size(6.0, 6.0)
                    .absolute(5.0, 5.0)
                    .radius(3.0)
                    .fill(dot)
                    .boxShadow(Shadow(spread: 0.5, color: k.on(c.depthTop, dot), inset: true))
                    .boxShadow(Shadow(y: 0.5, blur: 0.5, color: k.darkA(0.4)))
            )
        }
        if stateVal == .rest && !checkedVal {
            control = control.hover(c.hover)
        }
        if disabled {
            control = control.dim(0.5)
        }
        if stateVal == .focus {
            control = control.outline(2.0, 1.0, c.borderFocus)
        }
        let labelColor = disabled ? c.textMuted : c.textBase
        var words = col().key("text").gap(6.0).child(
            text(labelVal).key("label").font(k.ty.ui.lh(20.0)).color(labelColor)
        )
        if let d = descriptionVal {
            let color = disabled ? c.textFaint : c.textMuted
            words = words.child(text(d).key("description").font(k.ty.small.lh(11.0)).color(color))
        }
        let root = row()
            .role("radio")
            .label(labelVal)
            .gap(8.0)
            .itemsStart()
            .child(el().key("stack").size(16.0, 20.0).child(control))
            .child(words)
        return actsVal.apply(root.focusable(!disabled).focusSelected(checkedVal), !disabled)
    }
}

public struct RadioGroup {
    private var labelVal: String?
    private var descriptionVal: String?
    private var itemsVal: [RadioItem]
    private var disabledVal: Bool
    private var invalidVal: Bool

    public init() {
        self.labelVal = nil
        self.descriptionVal = nil
        self.itemsVal = []
        self.disabledVal = false
        self.invalidVal = false
    }

    public static func new() -> RadioGroup {
        RadioGroup()
    }

    public static var `default`: RadioGroup {
        RadioGroup()
    }

    public func label(_ l: String) -> RadioGroup {
        var copy = self
        copy.labelVal = l
        return copy
    }

    public func description(_ d: String) -> RadioGroup {
        var copy = self
        copy.descriptionVal = d
        return copy
    }

    public func item(_ i: RadioItem) -> RadioGroup {
        var copy = self
        copy.itemsVal.append(i)
        return copy
    }

    public func disabled(_ d: Bool) -> RadioGroup {
        var copy = self
        copy.disabledVal = d
        return copy
    }

    public func invalid(_ i: Bool) -> RadioGroup {
        var copy = self
        copy.invalidVal = i
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        var root = col().role("radiogroup").focusGroup().gap(8.0)
        if let l = labelVal {
            root = root.label(l).child(
                text(l).key("label").font(k.ty.small.lh(11.0)).color(c.textFaint)
            )
        }
        if let d = descriptionVal {
            root = root.child(
                text(d).key("description").font(k.ty.small.lh(13.2)).color(c.textFaint)
            )
        }
        var items = col().key("items").gap(12.0)
        for (i, var item) in itemsVal.enumerated() {
            if disabledVal {
                item = item.disabled(true)
            }
            item.invalidVal = invalidVal
            items = items.child(item.build(k).key("item\(i)"))
        }
        return root.child(items)
    }
}

/// Namespace mirroring `rune_kit::radio` module exports.
public enum radio {
    public typealias RadioItem = RuneKit.RadioItem
    public typealias RadioGroup = RuneKit.RadioGroup
}
