// Ported from: crates/rune-kit/src/toast.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Toast and ToastRegion (`@opencode/ui` feedback/toast).

import Rune

public struct Toast {
    var titleText: String
    var descriptionText: String?
    var iconEl: El?
    var actions: [El]
    var closeActs: Acts?
    var key: String

    public init(_ key: String, _ title: String) {
        self.key = key
        self.titleText = title
        self.descriptionText = nil
        self.iconEl = nil
        self.actions = []
        self.closeActs = nil
    }

    public static func new(_ key: String, _ title: String) -> Toast {
        Toast(key, title)
    }

    public func description(_ d: String) -> Toast {
        var copy = self
        copy.descriptionText = d
        return copy
    }

    /// A 16 point icon in the theme's base icon colour.
    public func icon(_ k: Kit, _ i: Icon) -> Toast {
        var copy = self
        copy.iconEl = Rune.icon(i, 16.0).color(k.c.iconBase)
        return copy
    }

    /// Any 16 point leading element (coloured icons, a loader).
    public func lead(_ e: El) -> Toast {
        var copy = self
        copy.iconEl = e
        return copy
    }

    /// A primary (neutral) or secondary (ghost) small action button.
    public func action<S>(
        _ k: Kit,
        _ label: String,
        _ primary: Bool,
        _ f: @escaping (inout S, inout Tx) -> Void
    ) -> Toast {
        var copy = self
        let v: ButtonVariant = primary ? .neutral : .ghost
        copy.actions.append(
            Button.new(label)
                .variant(v)
                .controlSize(.regular)
                .onPressTx(f)
                .build(k)
        )
        return copy
    }

    /// Shows the close button; `f` dismisses.
    public func onClose<S>(_ f: @escaping (inout S) -> Void) -> Toast {
        var copy = self
        var a = Acts()
        a.press(f)
        copy.closeActs = a
        return copy
    }

    /// Shows the close button without a handler (galleries).
    public func closable() -> Toast {
        var copy = self
        if copy.closeActs == nil {
            copy.closeActs = Acts()
        }
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        var content = Rune.col().key("content").grow(1.0).shrink().gap(4.0).child(
            Rune.text(titleText)
                .key("title")
                .font(k.ty.uiMedium.lh(20.0))
                .color(c.textBase)
                .truncate()
        )
        if let d = descriptionText {
            content = content.child(
                Rune.text(d).key("description").font(k.ty.ui).color(c.textMuted).wrap().wFull()
            )
        }
        var top = Rune.row().key("top").wFull().gap(12.0).itemsStart()
        if let i = iconEl {
            top = top.child(Rune.el().key("icon").size(16.0, 20.0).center().child(i))
        }
        top = top.child(content)
        if let a = closeActs {
            let b = Rune.row()
                .key("close")
                .role("button")
                .label("Close")
                .size(20.0, 20.0)
                .center()
                .radius(4.0)
                .hover(c.hover)
                .press(pressOver(c.hover, c.pressed))
                .child(Rune.icon(k.glyph.close, 16.0).color(c.iconMuted))
            top = top.child(a.apply(b, true))
        }
        var root = Rune.col()
            .key(key)
            .role("status")
            .label(titleText)
            .w(320.0)
            .padding(12.0)
            .gap(12.0)
            .radius(8.0)
            .fill(c.layer01)
        root = shadows(k, root, k.elevation.floating).child(top)
        if !actions.isEmpty {
            let indent: Float = 16.0 + 12.0
            root = root.child(Rune.row().key("actions").pl(indent).gap(8.0).flexWrap().children(actions))
        }
        return root.transition(Transition.moveEdge(.bottom)).motion(Spring(0.28, 0.0))
    }
}

/// The bottom-right stack toasts live in (32 points from the right, 48 from the bottom,
/// 12 apart). Mount it with ``root(_:_:)`` as an overlay.
public struct ToastRegion {
    var toasts: [El]

    public init() {
        self.toasts = []
    }

    public static func new() -> ToastRegion {
        ToastRegion()
    }

    public static var `default`: ToastRegion {
        ToastRegion()
    }

    public func toast(_ t: El) -> ToastRegion {
        var copy = self
        copy.toasts.append(t)
        return copy
    }

    public func build(_ k: Kit) -> El {
        _ = k
        return Rune.col()
            .key("toast-region")
            .role("region")
            .label("Notifications")
            .pin(nil, nil, 32.0, 48.0)
            .gap(12.0)
            .children(toasts)
    }
}

/// Namespace mirroring `rune_kit::toast` module exports.
public enum toast {
    public typealias Toast = RuneKit.Toast
    public typealias ToastRegion = RuneKit.ToastRegion
}
