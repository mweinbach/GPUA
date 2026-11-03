// Ported from: crates/rune/src/el/effect.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Effect slots (`El.effect`): places in the painter stream a compositor paints into.

/// An effect slot's settings (`El.effect` and its builders).
struct EffectSlot: Sendable, Equatable {
    /// Points past the rect the compositor may paint (`El.effectBleed`).
    var bleed: Float = 0.0
    /// Asks for a backdrop copy (`El.effectBackdrop`).
    var backdrop: Bool = false
    /// The app's payload (`El.effectData`).
    var data: [Float] = [0.0, 0.0, 0.0, 0.0]

    init(bleed: Float = 0.0, backdrop: Bool = false, data: [Float] = [0.0, 0.0, 0.0, 0.0]) {
        self.bleed = bleed
        self.backdrop = backdrop
        self.data = data.count >= 4 ? [data[0], data[1], data[2], data[3]] : [0.0, 0.0, 0.0, 0.0]
    }

    static func == (lhs: EffectSlot, rhs: EffectSlot) -> Bool {
        // Bitwise on `data`, so a NaN-packed payload still lets a memoized row be reused.
        guard lhs.bleed == rhs.bleed, lhs.backdrop == rhs.backdrop, lhs.data.count == rhs.data.count else {
            return false
        }
        for (a, b) in zip(lhs.data, rhs.data) where a.bitPattern != b.bitPattern {
            return false
        }
        return true
    }
}

extension El {
    /// Makes this element an effect slot for a compositor, tagged `mark`. It draws nothing
    /// itself but keeps its place in the painter stream with its rect, clip, rounded clip and
    /// enclosing isolated layer (opacity, blur, dissolve), so a compositor can paint its own
    /// pass there.
    public func effect(_ mark: UInt32) -> El {
        var copy = self
        copy.vis.mark = mark
        copy.vis.cold.modify { cold in
            cold.effectMark = mark
            if cold.effect == nil {
                cold.effect = EffectSlot()
            }
        }
        return copy
    }

    /// Points past the rect an effect slot may paint (a glow's reach). Grows the bounds of an
    /// enclosing isolated layer; the clip still applies.
    public func effectBleed(_ pt: Float) -> El {
        var copy = self
        copy.vis.cold.modify { cold in
            var slot = cold.effect ?? EffectSlot()
            slot.bleed = max(pt, 0.0)
            cold.effect = slot
        }
        return copy
    }

    /// Request a backdrop copy up to this effect slot (`EffectSite.backdrop`).
    /// Ordinary slots (`false`, the default) stay inside the open render pass with no copy.
    public func effectBackdrop(_ on: Bool) -> El {
        var copy = self
        copy.vis.cold.modify { cold in
            var slot = cold.effect ?? EffectSlot()
            slot.backdrop = on
            cold.effect = slot
        }
        return copy
    }

    /// Four floats this effect slot hands its compositor as `EffectSite.data`, such as which
    /// snapshot of data to draw, a seed or a phase. They travel bit for bit in the slot's
    /// record, so `Float(bitPattern:)` round-trips a 32-bit id.
    public func effectData(_ data: [Float]) -> El {
        var copy = self
        let payload = data.count >= 4 ? [data[0], data[1], data[2], data[3]] : [0.0, 0.0, 0.0, 0.0]
        copy.vis.cold.modify { cold in
            var slot = cold.effect ?? EffectSlot()
            slot.data = payload
            cold.effect = slot
        }
        return copy
    }
}
