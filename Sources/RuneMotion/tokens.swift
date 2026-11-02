// Ported from: crates/rune-motion/src/tokens.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

/// The shared motion tokens, from the motion presets (generated as
/// `presets/generated/kit_motion.rs`). Every spring is duration + bounce, bounce 0 by default.
///
/// Plain names are the enter springs; `*Exit` the exit springs; ``tokens/pair`` holds both.
/// Aliases follow the JSON's `aka` lists (old palette names).
public enum tokens {
    /// Pointer-tied. Barely a spring: takes the edge off a jump without lagging the hand.
    public static let instant = Spring(0.1, 0.0)
    public static let instantExit = Spring(0.1, 0.0)
    /// Small controls answering a click: indicators, widths that lead, exits.
    public static let snap = Spring(0.25, 0.0)
    public static let snapExit = Spring(0.2, 0.0)
    /// The default state change. Arrives and stops, no drama.
    public static let settle = Spring(0.3, 0.0)
    public static let settleExit = Spring(0.24, 0.0)
    /// Layout moving out of the way: siblings sliding into a gap, containers resizing.
    public static let reflow = Spring(0.4, 0.0)
    public static let reflowExit = Spring(0.32, 0.0)
    /// Big surfaces travelling: drawers, sheets, pages.
    public static let glide = Spring(0.32, 0.0)
    public static let glideExit = Spring(0.26, 0.0)
    /// One shape becoming another: a chip opening into its panel, a menu out of its button.
    public static let morph = Spring(0.3, 0.16)
    public static let morphExit = Spring(0.27, 0.08)
    /// A release with a little life in it. Keep it to presses and confirmations.
    public static let pop = Spring(0.25, 0.15)
    public static let popExit = Spring(0.2, 0.05)
    /// Slow reveals and wipes the eye should follow, never utility UI.
    public static let drift = Spring(0.85, 0.0)
    public static let driftExit = Spring(0.6, 0.0)
    /// Explainer camera moves (motion palette: 1.0–1.8 / 0).
    public static let camera = Spring(1.2, 0.0)

    // Old palette names (the JSON's `aka`).
    public static let snappy = snap
    public static let quick = snap
    public static let `default` = settle
    public static let calm = reflow
    public static let smooth = glide
    public static let playful = pop
    public static let slow = drift

    /// The fade that replaces travel under Reduce Motion.
    public static let reducedFade: Curve = RuneMotion.reducedFade
    /// Kit's CSS enter: 150 ms `cubic-bezier(.2,.8,.2,1)`.
    public static let cssEnter: Curve = .tween(duration: 0.15, easing: .enter)
    /// Kit's CSS exit: 110 ms `cubic-bezier(.4,0,1,1)`.
    public static let cssExit: Curve = .tween(duration: 0.11, easing: .exit)

    /// Drag-follow lead (ω 34, ζ .86): only for opt-in follow, never the user's own hand.
    public static func followLead() -> Spring {
        Spring.fromOmegaZeta(34.0, 0.86)
    }

    /// Drag-follow trail (ω 25, ζ 1).
    public static func followTrail() -> Spring {
        Spring.fromOmegaZeta(25.0, 1.0)
    }

    /// Enter/exit pairs.
    public enum pair {
        public static let instant = SpringPair(tokens.instant, tokens.instantExit)
        public static let snap = SpringPair(tokens.snap, tokens.snapExit)
        public static let settle = SpringPair(tokens.settle, tokens.settleExit)
        public static let reflow = SpringPair(tokens.reflow, tokens.reflowExit)
        public static let glide = SpringPair(tokens.glide, tokens.glideExit)
        public static let morph = SpringPair(tokens.morph, tokens.morphExit)
        public static let pop = SpringPair(tokens.pop, tokens.popExit)
        public static let drift = SpringPair(tokens.drift, tokens.driftExit)
    }

    /// SwiftUI's named springs.
    public enum swiftui {
        public static let smooth: Spring = Spring.smooth
        public static let snappy: Spring = Spring.snappy
        public static let bouncy: Spring = Spring.bouncy
        public static let spring: Spring = Spring.`default`
    }

    /// Every token by name, for tuning panels, traces and tests.
    public static let all: [(String, SpringPair)] = [
        ("instant", pair.instant),
        ("snap", pair.snap),
        ("settle", pair.settle),
        ("reflow", pair.reflow),
        ("glide", pair.glide),
        ("morph", pair.morph),
        ("pop", pair.pop),
        ("drift", pair.drift),
    ]
}
