// Ported from: crates/rune/src/el/ride_trailing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.rideTrailing`: an element that keeps its place against its parent's trailing edge.

extension El {
    /// While its parent's width animates, this element keeps its place against the parent's
    /// trailing (right) edge instead of riding its leading one.
    public func rideTrailing() -> El {
        var copy = self
        copy.vis.rideTrailing = true
        return copy
    }
}
