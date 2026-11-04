// Ported from: crates/rune-kit/src/lib.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! rune-kit: generic, themable components for Rune.
//!
//! Components mirror `@opencode/ui`'s names, variants, sizes and states so screens port from
//! the Solid app by name, but they read only semantic tokens from a ``Kit``. The OpenCode
//! look is one theme (`RuneThemeOpenCode`), supplied as data; ``Kit/neutral(_:)`` renders the
//! same components on Rune's core neutral tokens.
//!
//! Each component is a builder that ends in `.build(kit) -> El`. Handlers attach through the
//! builder (`.onPress { (s: inout S) in ... }`) so disabled components drop them. `.state(.hover)`
//! forces a visual state for galleries and stories; live hover and press come from the runtime.
//!
//! Overlays (popover, menu, select, tooltip, hover card, toast) return their trigger in place
//! and their content as a separate `El` that the view mounts at the root with ``root(_:_:)``, so it
//! draws above later siblings and escapes clipping ancestors.

import Rune

/// A forced visual state (Storybook's `data-state`). `.rest` lets the runtime drive hover/press.
public enum State: Sendable, Equatable, Hashable {
    case rest
    case hover
    case pressed
    case focus
    case disabled

    public init() {
        self = .rest
    }

    public static let `default`: State = .rest
}

/// A control's size, named and measured as AppKit's `NSControl.ControlSize` on macOS 27. A
/// push button is 16, 20, 24, 28 or 36 points tall; a switch's track 16, 20, 24, 28 or 36.
public enum ControlSize: Sendable, Equatable, Hashable {
    case mini
    case small
    case regular
    case large
    case extraLarge

    public init() {
        self = .regular
    }

    public static let `default`: ControlSize = .regular
}

/// Handlers collected by a builder and attached to its root once built (unless disabled).
struct Acts {
    private var handlers: [(El) -> El] = []

    init() {}

    mutating func press<S>(_ f: @escaping (inout S) -> Void) {
        handlers.append { e in e.onPress(f) }
    }

    mutating func pressTx<S>(_ f: @escaping (inout S, inout Tx) -> Void) {
        handlers.append { e in e.onPressTx(f) }
    }

    func apply(_ e: El, _ enabled: Bool) -> El {
        guard enabled else { return e }
        var out = e
        for f in handlers {
            out = f(out)
        }
        return out
    }
}

/// Paints a list of box-shadow layers on `e`.
func shadows(_ k: Kit, _ e: El, _ list: [Shadow]) -> El {
    var out = e
    for s in k.shadowLayers(list) {
        out = out.boxShadow(s)
    }
    return out
}

/// The press overlay that, composited over the hover overlay the runtime already shows, gives
/// `pressed` over the fill (the web swaps hover for pressed rather than stacking them).
func pressOver(_ hover: Color, _ pressed: Color) -> Color {
    if hover.a >= 0.999 {
        return pressed
    }
    let a = min(max((pressed.a - hover.a) / (1.0 - hover.a), 0.0), 1.0)
    // Same hue overlays (black or white ramps) composite exactly; mixed hues come out close.
    return pressed.alpha(a)
}

/// Source-over of straight-alpha colours (for forced states and static layering).
func over(_ top: Color, _ bottom: Color) -> Color {
    let a = top.a + bottom.a * (1.0 - top.a)
    if a <= 0.0 {
        return Color.TRANSPARENT
    }
    @inline(__always)
    func mix(_ t: Float, _ b: Float) -> Float {
        (t * top.a + b * bottom.a * (1.0 - top.a)) / a
    }
    return Color(r: mix(top.r, bottom.r), g: mix(top.g, bottom.g), b: mix(top.b, bottom.b), a: a)
}

/// Mounts overlays above `base`: `base` fills the window and each overlay follows it in paint
/// and hit order. Place popover/menu/select/tooltip contents and toast regions here.
public func root<Overlays: Swift.Sequence>(_ base: El, _ overlays: Overlays) -> El where Overlays.Element == El {
    let within = base.hoverWithinCurves()
    let rootEl = Rune.el()
        .key("kit-root")
        .wFull()
        .hFull()
        .child(base.wFull().hFull())
        .children(overlays)
    if let (enter, exit) = within {
        return rootEl.hoverMotionWithin(enter, exit)
    }
    return rootEl
}
