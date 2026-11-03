// Ported from: crates/rune/src/tooling/eased_input.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Script inputs a hand eases over a duration, one step a frame.

/// `{"type": "scroll"}`: a trackpad swipe, deltas eased over `dur`, then (with `"fling"`) the
/// release velocity.
func toolingSwipe(out: inout [ToolingEv], e: ToolingJson, t: Double, pos: ToolingPos) {
    let dx = Float(e["dx"].doubleValue ?? 0.0)
    let dy = Float(e["dy"].doubleValue ?? 0.0)
    let dur = max(e["dur"].doubleValue ?? 0.2, 0.01)
    out.append(ToolingEv(t: t, kind: .move, pos: pos))
    let steps = max(1, Int((dur * 120.0).rounded(.up)))
    var prev: (Float, Float) = (0.0, 0.0)
    for s in 1...steps {
        let u = Float(s) / Float(steps)
        let f = u * (2.0 - u)
        out.append(
            ToolingEv(
                t: t + dur * Double(s) / Double(steps),
                kind: .wheel(dx * f - prev.0, dy * f - prev.1),
                pos: pos
            )
        )
        prev = (dx * f, dy * f)
    }
    if e["fling"].boolValue == true {
        let durF = Float(dur)
        let vx = 2.0 * dx / durF * 0.25
        let vy = 2.0 * dy / durF * 0.25
        out.append(ToolingEv(t: t + dur + 1e-4, kind: .fling(vx, vy), pos: pos))
    }
}

/// `{"type": "resize", "dw": ..., "dh": ..., "dur": ...}`: a person dragging the window's corner,
/// one viewport step a frame on a smoothstep hand, as a live resize delivers it.
func toolingResize(out: inout [ToolingEv], e: ToolingJson, t: Double) {
    let dw = Float(e["dw"].doubleValue ?? 0.0)
    let dh = Float(e["dh"].doubleValue ?? 0.0)
    let dur = max(e["dur"].doubleValue ?? 0.3, 0.01)
    let steps = max(1, Int((dur * 120.0).rounded(.up)))
    for s in 0...steps {
        let u = Float(s) / Float(steps)
        let f = u * u * (3.0 - 2.0 * u)
        out.append(
            ToolingEv(
                t: t + dur * Double(s) / Double(steps),
                kind: .resize(dw * f, dh * f),
                pos: .rel(0.0, 0.0)
            )
        )
    }
}

/// One step of a scripted resize: `(0, 0)` marks where it starts, and content follows at once.
func toolingStepResize<S>(
    rt: Runtime<S>,
    from: inout (Float, Float),
    delta: (Float, Float),
    scale: Float
) {
    if delta.0 == 0.0 && delta.1 == 0.0 {
        from = rt.viewport
    }
    rt.hostSetScale(scale)
    rt.hostSetViewport(max(from.0 + delta.0, 1.0), max(from.1 + delta.1, 1.0))
}
