// Ported from: crates/rune-kit/src/collapsible.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Collapsible (`@opencode/ui` components/collapsible): a 32 point trigger row with a
//! disclosure arrow that shows on hover or when open, and content below.

import Rune

public struct Collapsible {
    private var titleVal: String
    private var openVal: Bool
    private var ghostVal: Bool
    private var contentVal: [El]
    private var stateVal: State
    private var actsVal: Acts

    public init(_ title: String, _ open: Bool) {
        self.titleVal = title
        self.openVal = open
        self.ghostVal = false
        self.contentVal = []
        self.stateVal = .rest
        self.actsVal = Acts()
    }

    public static func new(_ title: String, _ open: Bool) -> Collapsible {
        Collapsible(title, open)
    }

    public func ghost() -> Collapsible {
        var copy = self
        copy.ghostVal = true
        return copy
    }

    public func child(_ c: El) -> Collapsible {
        var copy = self
        copy.contentVal.append(c)
        return copy
    }

    public func state(_ s: State) -> Collapsible {
        var copy = self
        copy.stateVal = s
        return copy
    }

    public func onToggle<S>(_ f: @escaping (inout S) -> Void) -> Collapsible {
        var copy = self
        copy.actsVal.press(f)
        return copy
    }

    public func onToggleTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) -> Collapsible {
        var copy = self
        copy.actsVal.pressTx(f)
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let show = openVal || stateVal == .hover
        let glyph = openVal ? k.glyph.triangleDown : k.glyph.triangleRight
        let arrow = el()
            .key("arrow")
            .size(24.0, 24.0)
            .center()
            .opacity(show ? 1.0 : 0.0)
            .child(icon(glyph, 14.0).color(c.iconWeaker))
        let trigger = actsVal.apply(
            row()
                .key("trigger")
                .role("button")
                .label(titleVal)
                .wFull()
                .h(32.0)
                .centerY()
                .child(
                    row()
                        .gap(8.0)
                        .centerY()
                        .child(text(titleVal).key("title").font(k.ty.textSmallMedium).color(c.stdText))
                        .child(arrow)
                ),
            stateVal != .disabled
        )
        var root = col().role("group").wFull().radius(k.radius.md).child(trigger)
        if openVal {
            root = root.child(col().key("content").wFull().children(contentVal))
        }
        return root
    }
}

/// Namespace mirroring `rune_kit::collapsible` module exports.
public enum collapsible {
    public typealias Collapsible = RuneKit.Collapsible
}
