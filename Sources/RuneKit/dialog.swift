// Ported from: crates/rune-kit/src/dialog.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Modal surface; focus, dismissal and background inertness belong to Rune.

import Rune

public struct Dialog {
    var key: String
    var titleText: String
    var descriptionText: String?
    var body: [El]
    var openFlag: Bool
    var outsideFlag: Bool
    var widthVal: Float
    var fitFlag: Bool
    var closeFn: ((El) -> El)?
    var buttonFn: ((El) -> El)?

    public init(_ key: String, _ title: String) {
        self.key = key
        self.titleText = title
        self.descriptionText = nil
        self.body = []
        self.openFlag = false
        self.outsideFlag = true
        self.widthVal = 480.0
        self.fitFlag = false
        self.closeFn = nil
        self.buttonFn = nil
    }

    public static func new(_ key: String, _ title: String) -> Dialog {
        Dialog(key, title)
    }

    public func open(_ open: Bool) -> Dialog {
        var copy = self
        copy.openFlag = open
        return copy
    }

    public func description(_ description: String) -> Dialog {
        var copy = self
        copy.descriptionText = description
        return copy
    }

    public func child(_ bodyEl: El) -> Dialog {
        var copy = self
        copy.body.append(bodyEl)
        return copy
    }

    public func width(_ width: Float) -> Dialog {
        var copy = self
        copy.widthVal = width
        return copy
    }

    /// Sizes the panel to its header and body instead of the standard 368 point height, for
    /// short dialogs such as a confirmation. Content taller than the window isn't scrolled, so
    /// put a scroll view in the body if it can grow.
    public func fit() -> Dialog {
        var copy = self
        copy.fitFlag = true
        return copy
    }

    public func clickOutside(_ close: Bool) -> Dialog {
        var copy = self
        copy.outsideFlag = close
        return copy
    }

    public func onClose<S>(_ f: @escaping (inout S) -> Void) -> Dialog {
        var copy = self
        copy.buttonFn = { e in e.onPress(f) }
        // The policy is applied at build time, regardless of builder call order.
        copy.closeFn = { e in e.modal(true, f) }
        return copy
    }

    public func build(_ k: Kit, _ layer: inout [El]) {
        if !openFlag {
            return
        }
        guard let close = closeFn else {
            return
        }
        var dismiss = IconButton.new(k.glyph.close)
            .variant(.ghost)
            .controlSize(.regular)
            .label("Close")
            .build(k)
            .key("close")
        if let button = buttonFn {
            dismiss = button(dismiss)
        }
        dismiss = dismiss.size(20.0, 20.0).mt(-2.0).mr(-2.0)

        var titleFont = k.ty.uiMedium
        if descriptionText != nil {
            titleFont.size = 15.0
            titleFont.tracking = -0.13
            titleFont = titleFont.lh(20.0)
        } else {
            titleFont = titleFont.lh(16.0)
        }
        var titleCol = Rune.col().grow(1.0).gap(4.0).child(
            Rune.text(titleText).font(titleFont).color(k.c.textBase)
        )
        if let description = descriptionText {
            titleCol = titleCol.child(
                Rune.text(description).font(k.ty.ui.lh(20.0)).color(k.c.textMuted)
            )
        }

        let rawBody = Rune.col().key("body").wFull().children(body)
        let (panelBase, panelBody): (El, El) = fitFlag
            ? (Rune.col(), rawBody)
            : (Rune.col().h(368.0), rawBody.grow(1.0))

        let shadowed = shadows(
            k,
            panelBase
                .key("\(key)-dialog")
                .role("dialog")
                .label(titleText)
                .wFull()
                .maxW(widthVal)
                .radius(6.0)
                .fill(k.c.layer01)
                .child(Rune.row().key("header").wFull().padding(16.0).itemsStart().child(titleCol).child(dismiss))
                .child(panelBody)
                .motion(k.motion.overlay),
            k.elevation.overlay
        )
        let panel = close(shadowed).modalClickOutside(outsideFlag)
        layer.append(
            Rune.el()
                .key("\(key)-scrim")
                .absolute(0.0, 0.0)
                .wFull()
                .hFull()
                .fill(k.c.scrim)
                .motion(k.motion.overlay)
        )
        layer.append(
            Rune.el()
                .key("\(key)-layer")
                .absolute(0.0, 0.0)
                .wFull()
                .hFull()
                .padding(16.0)
                .center()
                .child(panel)
        )
    }
}

/// Namespace mirroring `rune_kit::dialog` module exports.
public enum dialog {
    public typealias Dialog = RuneKit.Dialog
}
