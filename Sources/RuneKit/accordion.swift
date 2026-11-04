// Ported from: crates/rune-kit/src/accordion.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Accordion (`@opencode/ui` data-display/accordion): bordered stacked triggers whose content
//! opens below, sharing borders, with rounded outer corners.

import Rune

public struct AccordionItem {
    var titleVal: String
    var expandedVal: Bool
    var contentVal: [El]
    var stateVal: State
    var actsVal: Acts

    public init(_ title: String) {
        self.titleVal = title
        self.expandedVal = false
        self.contentVal = []
        self.stateVal = .rest
        self.actsVal = Acts()
    }

    public static func new(_ title: String) -> AccordionItem {
        AccordionItem(title)
    }

    public func expanded(_ e: Bool) -> AccordionItem {
        var copy = self
        copy.expandedVal = e
        return copy
    }

    public func child(_ c: El) -> AccordionItem {
        var copy = self
        copy.contentVal.append(c)
        return copy
    }

    public func state(_ s: State) -> AccordionItem {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func disabled(_ d: Bool) -> AccordionItem {
        var copy = self
        if d {
            copy.stateVal = .disabled
        }
        return copy
    }

    public func onToggle<S>(_ f: @escaping (inout S) -> Void) -> AccordionItem {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onToggleTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> AccordionItem {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }
}

public struct Accordion {
    private var itemsVal: [AccordionItem]
    private var widthVal: Float?

    public init() {
        self.itemsVal = []
        self.widthVal = nil
    }

    public static func new() -> Accordion {
        Accordion()
    }

    public static var `default`: Accordion {
        Accordion()
    }

    public func item(_ i: AccordionItem) -> Accordion {
        var copy = self
        copy.itemsVal.append(i)
        return copy
    }

    public func width(_ w: Float) -> Accordion {
        var copy = self
        copy.widthVal = w
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let r = k.radius.lg
        let n = itemsVal.count
        var root = col().role("group").itemsStretch()
        if let w = widthVal {
            root = root.w(w)
        } else {
            root = root.wFull()
        }
        for (i, item) in itemsVal.enumerated() {
            let first = i == 0
            let last = i + 1 == n
            let bottom: Float = (last && !item.expandedVal) ? r : 0.0
            let top: Float = first ? r : 0.0
            var trigger = row()
                .key("trigger")
                .role("button")
                .label(item.titleVal)
                .h(32.0)
                .px(12.0)
                .py(8.0)
                .centerY()
                .justifyBetween()
                .corners([top, top, bottom, bottom])
                .fill(item.stateVal == .hover ? c.hover : c.bgBase)
                .border(1.0, c.borderBase)
                .motion(k.motion.control)
                .child(text(item.titleVal).key("title").font(k.ty.textSmall).color(c.textBase))
            if item.stateVal == .rest {
                trigger = trigger.hover(c.hover)
            }
            let enabled = item.stateVal != .disabled
            trigger = item.actsVal.apply(trigger, enabled)
            var e = col().key("item\(i)").itemsStretch().child(trigger)
            if i > 0 {
                e = e.mt(-1.0)
            }
            if item.expandedVal {
                let b: Float = last ? r : 0.0
                // The content's own top border would double the trigger's (both translucent):
                // draw it one point up and clip that row away, as CSS's `border-top: 0` does.
                e = e.child(
                    col().key("content-clip").clipSoft(0.0).child(
                        col()
                            .key("content")
                            .corners([0.0, 0.0, b, b])
                            .fill(c.layer01)
                            .border(1.0, c.borderBase)
                            .mt(-1.0)
                            .pt(1.0)
                            .children(item.contentVal)
                    )
                )
            }
            root = root.child(e)
        }
        return root
    }
}

/// Namespace mirroring `rune_kit::accordion` module exports.
public enum accordion {
    public typealias AccordionItem = RuneKit.AccordionItem
    public typealias Accordion = RuneKit.Accordion
}
