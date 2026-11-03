// Ported from: crates/rune/src/text/hidden_axes.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Hidden variation axes (`fvar` flag `0x0001`, `HIDDEN_AXIS`).
//!
//! Some variable fonts split a design property across a public axis and a hidden companion axis,
//! using named instances in `fvar` to pair them (for example Geist's `wght` + hidden `YAXS`).
//! This module reads `fvar` directly and interpolates hidden axes along `wght` across named instances.

struct VariationAxisSetting: Sendable, Equatable {
    var tag: UInt32
    var tagString: String
    var value: Float

    init(tag: UInt32, value: Float) {
        self.tag = tag
        self.value = value
        let b0 = UInt8((tag >> 24) & 0xFF)
        let b1 = UInt8((tag >> 16) & 0xFF)
        let b2 = UInt8((tag >> 8) & 0xFF)
        let b3 = UInt8(tag & 0xFF)
        self.tagString = String(bytes: [b0, b1, b2, b3], encoding: .ascii) ?? "    "
    }
}

/// Push interpolated settings for any hidden axes on `sfnt` that vary with `wght` across its named instances,
/// skipping any axis already present in `explicitTags`.
func pushHiddenAxes(
    _ sfnt: SfntFont,
    weight: Float,
    explicitTags: Set<UInt32>,
    out: inout [VariationAxisSetting]
) {
    guard let fvar = sfnt.parseFvar(),
          let wghtIdx = fvar.axes.firstIndex(where: { $0.tag == SfntTag.wght })
    else {
        return
    }

    for (axisIdx, axis) in fvar.axes.enumerated() where axis.isHidden {
        if explicitTags.contains(axis.tag) {
            continue
        }
        var stops: [(Float, Float)] = []
        stops.reserveCapacity(fvar.instances.count)
        for inst in fvar.instances {
            guard wghtIdx < inst.coords.count, axisIdx < inst.coords.count else { continue }
            stops.append((inst.coords[wghtIdx], inst.coords[axisIdx]))
        }
        guard !stops.isEmpty else { continue }
        stops.sort { $0.0 < $1.0 }
        // Deduplicate equal weights, keeping first.
        var deduped: [(Float, Float)] = []
        for s in stops {
            if let last = deduped.last, last.0 == s.0 {
                continue
            }
            deduped.append(s)
        }
        let value = lerpHiddenStops(deduped, weight)
        if abs(value - axis.defaultValue) > 1e-4 {
            out.append(VariationAxisSetting(tag: axis.tag, value: value))
        }
    }
}

func lerpHiddenStops(_ stops: [(Float, Float)], _ x: Float) -> Float {
    guard let first = stops.first, let last = stops.last else { return 0.0 }
    if x <= first.0 { return first.1 }
    if x >= last.0 { return last.1 }
    for i in 0..<(stops.count - 1) {
        let a = stops[i]
        let b = stops[i + 1]
        if x <= b.0 {
            let span = b.0 - a.0
            if span <= 0.0 { return a.1 }
            return a.1 + ((x - a.0) / span) * (b.1 - a.1)
        }
    }
    return last.1
}
