// Ported from: crates/rune-kit/src/card.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Card (`@opencode/ui` components/card): a left accent rule, a title with an icon, a
//! description and actions.

import Rune

public struct Card {
    private var accentVal: Color?
    private var titleVal: (String, Icon?)?
    private var descriptionVal: String?
    private var actionsVal: [El]
    private var childrenVal: [El]

    public init() {
        self.accentVal = nil
        self.titleVal = nil
        self.descriptionVal = nil
        self.actionsVal = []
        self.childrenVal = []
    }

    public static func new() -> Card {
        Card()
    }

    public static var `default`: Card {
        Card()
    }

    /// The accent rule and title icon colour (default `iconBase`); variants pass a state colour.
    public func accent(_ c: Color) -> Card {
        var copy = self
        copy.accentVal = c
        return copy
    }

    /// A title with a leading 14 point icon (`nil` draws a faint dash placeholder).
    public func title(_ t: String, _ i: Icon? = nil) -> Card {
        var copy = self
        copy.titleVal = (t, i)
        return copy
    }

    public func description(_ d: String) -> Card {
        var copy = self
        copy.descriptionVal = d
        return copy
    }

    public func action(_ a: El) -> Card {
        var copy = self
        copy.actionsVal.append(a)
        return copy
    }

    public func child(_ c: El) -> Card {
        var copy = self
        copy.childrenVal.append(c)
        return copy
    }

    /// The root is unkeyed. Its inner keys (`rule`, `body`, ...) are scoped under it, so sibling
    /// cards never collide; key the result (`.build(k).key(id)`) when cards can reorder.
    public func build(_ k: Kit) -> El {
        let c = k.c
        let accent = accentVal ?? c.iconBase
        let hasTitle = titleVal != nil
        // The 2 point accent rule runs 8 points in from the card's top and bottom edges; the
        // copy sits in the card's 10/12/10/10 padding beside it.
        let rule = el().key("rule").w(2.0).mt(8.0).mb(8.0).radius(2.0).fill(accent)
        var root = col().key("body").grow(1.0).shrink().pt(10.0).pb(10.0).pl(8.0).pr(12.0)
        if hasTitle {
            root = root.gap(8.0)
        }
        var indent: Float = 0.0
        var label: String? = nil
        if let (t, i) = titleVal {
            let glyph: Icon
            let color: Color
            if let i {
                glyph = i
                color = accent
            } else {
                glyph = k.glyph.dash
                color = c.textFaint
            }
            indent = 16.0 + 8.0
            label = t
            root = root.child(
                row()
                    .key("title")
                    .gap(8.0)
                    .centerY()
                    .child(el().size(16.0, 16.0).center().child(icon(glyph, 14.0).color(color)))
                    .child(text(t).font(k.ty.bodyMedium).color(c.textBase))
            )
        }
        if let d = descriptionVal {
            root = root.child(text(d).key("description").font(k.ty.body).color(c.textMuted).wrap().wFull())
        }
        root = root.children(childrenVal)
        if !actionsVal.isEmpty {
            root = root.child(row().key("actions").pl(indent).gap(8.0).children(actionsVal))
        }
        var card = row().role("group").wFull().itemsStretch().radius(k.radius.md).child(rule).child(root)
        if let l = label {
            card = card.label(l)
        }
        return card
    }
}

/// Namespace mirroring `rune_kit::card` module exports.
public enum card {
    public typealias Card = RuneKit.Card
}
