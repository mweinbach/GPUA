// Ported from: crates/rune-kit/src/shell/toolbar.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! A window's toolbar: leading, centre and trailing slots in a band the window drags by.

import Rune

/// The toolbar band's height, macOS 26's unified toolbar. The traffic lights centre in it when
/// the window places them at y = (48 - 14) / 2 = 17.
public let TOOLBAR_HEIGHT: Float = 48.0
/// Padding at the band's ends.
private let TOOLBAR_PAD: Float = 12.0

/// A toolbar: `Toolbar.new().leading(..).title("..").trailing(..).build(kit)`. The band is a
/// window drag region (buttons in it keep their presses) and its centre slot sits in the
/// middle of the band whatever the sides hold.
public struct Toolbar {
    private var leadingVal: [El]
    private var centerVal: El?
    private var titleVal: String?
    private var trailingVal: [El]
    private var insetVal: Float
    private var padVal: Float?
    private var materialVal: SystemMaterial?

    public init() {
        self.leadingVal = []
        self.centerVal = nil
        self.titleVal = nil
        self.trailingVal = []
        self.insetVal = 0.0
        self.padVal = nil
        self.materialVal = nil
    }

    public static func new() -> Toolbar {
        Toolbar()
    }

    public static var `default`: Toolbar {
        Toolbar()
    }

    public func leading(_ e: El) -> Toolbar {
        var copy = self
        copy.leadingVal.append(e)
        return copy
    }

    public func trailing(_ e: El) -> Toolbar {
        var copy = self
        copy.trailingVal.append(e)
        return copy
    }

    /// The centre slot. Replaces a ``Toolbar/title(_:)``.
    public func center(_ e: El) -> Toolbar {
        var copy = self
        copy.centerVal = e
        copy.titleVal = nil
        return copy
    }

    /// A centred title in the kit's medium UI type.
    public func title(_ t: String) -> Toolbar {
        var copy = self
        copy.titleVal = t
        copy.centerVal = nil
        return copy
    }

    /// Clears the traffic lights: pass `Cx.titlebarInset()`, which is 0 in full screen and off
    /// macOS. A toolbar given to a ``SplitView`` gets this from the split view instead.
    public func leadingInset(_ points: Float) -> Toolbar {
        var copy = self
        copy.insetVal = max(points, 0.0)
        return copy
    }

    /// Backs the band with a system material (macOS blurs what's behind a transparent
    /// window). Elsewhere, and headless, the kit's base background draws instead.
    public func material(_ m: SystemMaterial) -> Toolbar {
        var copy = self
        copy.materialVal = m
        return copy
    }

    /// The leading padding a `SplitView` works out (traffic lights and its sidebar toggle).
    func padding(_ points: Float) -> Toolbar {
        var copy = self
        copy.padVal = points
        return copy
    }

    public func build(_ k: Kit) -> El {
        let c = k.c
        let pl = padVal ?? (insetVal > 0.0 ? insetVal + TOOLBAR_PAD : TOOLBAR_PAD)
        var band = row()
            .key("toolbar")
            .role("toolbar")
            .wFull()
            .h(TOOLBAR_HEIGHT)
            .pl(pl)
            .pr(TOOLBAR_PAD)
            .gap(8.0)
            .centerY()
            .windowDrag()
        let centerEl: El?
        if let e = centerVal {
            centerEl = e
        } else if let t = titleVal {
            centerEl = text(t).key("title").font(k.ty.uiMedium).color(c.textBase).truncate()
        } else {
            centerEl = nil
        }
        if let centerEl {
            // Across the whole band and centred in it, so the sides can differ in width. First,
            // so the side slots draw and take presses above it.
            band = band.child(
                row().key("center").pin(0.0, 0.0, 0.0, 0.0).center().px(96.0).child(centerEl)
            )
        }
        band = band
            // The leading slot gives way first, so a long title truncates instead of pushing the
            // trailing controls off the band.
            .child(row().key("leading").gap(4.0).centerY().shrink().minW(0.0).children(leadingVal))
            .child(row().key("spacer").grow(1.0))
            .child(row().key("trailing").gap(4.0).centerY().children(trailingVal))
        if let m = materialVal {
            band = band.systemMaterial(m).fill(c.bgBase)
        }
        return band
    }
}
