// Ported from: crates/rune-kit/src/segmented.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! SegmentedControl (`@opencode/ui` navigation/segmented-control): equal segments over a layer
//! with a sliding raised indicator.

import Rune

/// How wide the control is.
private enum SegmentedWidth: Equatable {
    case points(Float)
    /// The parent's width.
    case fill
    /// Equal segments, each as wide as the widest label needs.
    case fit
}

private typealias SegmentedPick = (Int) -> (El) -> El

public struct SegmentedControl {
    private var labelsVal: [String]
    private var selectedVal: Int?
    private var widthVal: SegmentedWidth
    private var statesVal: [State]
    private var pickVal: SegmentedPick?

    public init<S: Swift.Sequence>(_ labels: S, _ selected: Int?) where S.Element == String {
        self.labelsVal = Array(labels)
        self.selectedVal = selected
        self.widthVal = .points(232.0)
        self.statesVal = []
        self.pickVal = nil
    }

    public init(_ labels: [Substring], _ selected: Int?) {
        self.init(labels.map(String.init), selected)
    }

    public static func new<S: Swift.Sequence>(_ labels: S, _ selected: Int?) -> SegmentedControl where S.Element == String {
        SegmentedControl(labels, selected)
    }

    public static func new(_ labels: [Substring], _ selected: Int?) -> SegmentedControl {
        SegmentedControl(labels, selected)
    }

    /// Width in points (default 232); `nil` fills the parent.
    public func width(_ w: Float?) -> SegmentedControl {
        var copy = self
        copy.widthVal = w.map(SegmentedWidth.points) ?? .fill
        return copy
    }

    /// Equal segments, each as wide as the widest label needs (any language, any font).
    public func fit() -> SegmentedControl {
        var copy = self
        copy.widthVal = .fit
        return copy
    }

    /// Force a segment's visual state (hover, focus, disabled).
    public func segmentState(_ i: Int, _ s: State) -> SegmentedControl {
        var copy = self
        if copy.statesVal.count <= i {
            copy.statesVal.append(contentsOf: repeatElement(.rest, count: i + 1 - copy.statesVal.count))
        }
        copy.statesVal[i] = s
        return copy
    }

    public func onPick<S>(_ f: @escaping (inout S, Int, inout Tx) -> Void) -> SegmentedControl {
        var copy = self
        copy.pickVal = { i in
            { e in
                e.onPressTx { (s: inout S, tx: inout Tx) in
                    f(&s, i, &tx)
                }
            }
        }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let n = max(labelsVal.count, 1)
        let font = k.ty.ui.lh(13.0)
        var root = row()
            .role("radiogroup")
            .focusGroup()
            .h(28.0)
            .centerY()
            .radius(6.0)
            .fill(c.layer01)
            .boxShadow(Shadow(spread: 0.5, color: c.borderBase))
        switch widthVal {
        case .points(let w):
            root = root.w(w)
        case .fill:
            root = root.wFull()
        case .fit:
            root = root.equalColumns(n)
        }
        func indicator() -> El {
            el()
                .key("indicator")
                .h(28.0)
                .radius(6.0)
                .fill(c.bgBase)
                .boxShadow(Shadow(spread: 0.5, color: c.borderStrong))
                .motion(k.motion.control)
        }
        switch (selectedVal, widthVal) {
        case (let sel?, .points(let w)):
            let seg = w / Float(n)
            root = root.child(indicator().w(seg).absolute(seg * Float(sel), 0.0))
        case (let sel?, .fit):
            // The indicator shares the selected segment's cell and slides between cells.
            root = root.child(indicator().gridCell(sel))
        default:
            break
        }
        for (i, l) in labelsVal.enumerated() {
            let st = i < statesVal.count ? statesVal[i] : .rest
            let on = selectedVal == i
            let ink = (on || st == .hover) ? c.textBase : c.textMuted
            // An unselected segment lights under the pointer on the first frame and fades as it
            // leaves (the runtime's default hover motion); the selected one already reads raised.
            let hovers = st == .rest && !on && pickVal != nil
            var label = text(l).key("label").font(font).color(ink).truncate()
            if hovers {
                label = label.groupColor(c.textBase)
            }
            var seg = row()
                .key("segment\(i)")
                .role("radio")
                .focusable(st != .disabled)
                .focusSelected(on)
                .focusRing(2.0, 1.0, c.borderFocus)
                .label(l)
                .grow(1.0)
                .shrink()
                .h(28.0)
                .px(12.0)
                .center()
                .radius(6.0)
                .child(label)
            if widthVal == .fit {
                seg = seg.gridCell(i)
            }
            if widthVal == .fill && on {
                seg = seg
                    .fill(c.bgBase)
                    .boxShadow(Shadow(spread: 0.5, color: c.borderStrong))
            }
            switch st {
            case .focus:
                seg = seg.outline(2.0, 1.0, c.borderFocus)
            case .disabled:
                seg = seg.dim(0.45)
            case .hover where !on:
                seg = seg.fill(c.hover)
            default:
                break
            }
            if hovers {
                seg = seg.hover(c.hover).press(pressOver(c.hover, c.pressed))
            }
            if st != .disabled, let p = pickVal {
                seg = p(i)(seg)
            }
            root = root.child(seg)
        }
        return root
    }
}

/// Namespace mirroring `rune_kit::segmented` module exports.
public enum segmented {
    public typealias SegmentedControl = RuneKit.SegmentedControl
}
