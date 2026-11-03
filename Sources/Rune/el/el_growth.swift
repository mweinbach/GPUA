// Ported from: crates/rune/src/el/growth.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Growth stacks and their rows: `El.growth`, `El.streaming` and `El.arrivesWhole`.

import RuneMotion

extension El {
    /// Make this column a growth stack (see ``GrowthSpec``). Required alongside
    /// ``virtualize(_:file:line:)`` on the same element.
    public func growth(_ spec: GrowthSpec = GrowthSpec()) -> El {
        var copy = self
        copy.growthSpec = spec
        return copy
    }

    /// A growth-stack row that is streaming: slows near its target and reveals through the
    /// feathered edge.
    public func streaming(_ on: Bool) -> El {
        var copy = self
        copy.streamingFlag = on
        return copy
    }

    /// A growth-stack row whose content arrives complete, like a sent message: its height
    /// changes glide on the growth spring alone, without the speed limits that pace streaming text.
    public func arrivesWhole() -> El {
        var copy = self
        copy.wholeFlag = true
        return copy
    }

    /// A growth-stack row that folds open and shut, like a disclosure: its height changes glide
    /// on its own `spring`, in place of the stack's. Implies ``arrivesWhole()``.
    public func foldGlide(_ spring: Spring) -> El {
        var copy = self
        copy.wholeFlag = true
        copy.glideSpec = FoldGlide(spring: spring, feather: copy.glideSpec?.feather)
        return copy
    }

    /// How deep, in points, a ``foldGlide(_:)`` row's moving bottom edge feathers as it folds
    /// open or shut, in place of its stack's `StreamEdge.maskMax`. Call after `foldGlide`.
    public func foldFeather(_ pt: Float) -> El {
        assert(glideSpec != nil, "foldFeather without foldGlide")
        var copy = self
        if var g = copy.glideSpec {
            g.feather = max(pt, 0.0)
            copy.glideSpec = g
        }
        return copy
    }
}
