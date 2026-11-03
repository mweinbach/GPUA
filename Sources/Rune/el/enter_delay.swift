// Ported from: crates/rune/src/el/enter_delay.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! `El.enterDelay`: holding an entering element at its insertion effect before it begins.

extension El {
    /// Hold a newly mounted element at its ``transition(_:)`` insertion effect for `seconds`
    /// before its entrance starts (staggered lists, sequentially revealed chrome).
    public func enterDelay(_ seconds: Float) -> El {
        var copy = self
        let clamped = seconds.isFinite ? max(seconds, 0.0) : 0.0
        copy.vis.cold.value.enterDelay = clamped
        return copy
    }
}
