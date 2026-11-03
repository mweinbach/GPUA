// Ported from: crates/rune/src/el/child_exit.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.childExit`: children removed in a commit leave the way that commit says.

import RuneMotion

extension El {
    /// Children removed from this element leave with `t` instead of the transition from their
    /// last render.
    public func childExit(_ t: Transition) -> El {
        var copy = self
        copy.vis.cold.value.childExit = t
        return copy
    }
}
