// Ported from: crates/rune/src/text/macos/flatten.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! CoreGraphics' curve flattening (`aa_create`'s tolerances): coordinates are cast to `Float`,
//! then Beziers are halved in `Double` until their squared second differences are within the
//! tolerance on both axes, and each accepted piece's endpoint is emitted as a line.

private let QUAD_FLATNESS: Double = 0.6400000000000001
private let CUBIC_FLATNESS: Double = 0.07111111111111111
/// Subdivision stops beyond this depth.
private let MAX_DEPTH: UInt32 = 22

private func flattenCubicMacos(_ p0: MacosPoint, _ p1: MacosPoint, _ p2: MacosPoint, _ p3: MacosPoint, _ depth: UInt32, _ out: inout MacosPath) {
    let ax = (p0.x + p2.x) - 2.0 * p1.x
    let bx = (p1.x + p3.x) - 2.0 * p2.x
    let ay = (p0.y + p2.y) - 2.0 * p1.y
    let by = (p1.y + p3.y) - 2.0 * p2.y
    let flat = (ax * ax <= CUBIC_FLATNESS && bx * bx <= CUBIC_FLATNESS) &&
               (ay * ay <= CUBIC_FLATNESS && by * by <= CUBIC_FLATNESS)
    if flat || depth > MAX_DEPTH {
        out.append(.line(p3))
    } else {
        let (a, b) = macosSplitCubic(p0, p1, p2, p3, 0.5)
        flattenCubicMacos(a.0, a.1, a.2, a.3, depth + 1, &out)
        flattenCubicMacos(b.0, b.1, b.2, b.3, depth + 1, &out)
    }
}

private func flattenQuadMacos(_ p0: MacosPoint, _ p1: MacosPoint, _ p2: MacosPoint, _ depth: UInt32, _ out: inout MacosPath) {
    let ax = p0.x + p2.x - 2.0 * p1.x
    let ay = p0.y + p2.y - 2.0 * p1.y
    let flat = (ax * ax <= QUAD_FLATNESS) && (ay * ay <= QUAD_FLATNESS)
    if flat || depth > MAX_DEPTH {
        out.append(.line(p2))
    } else {
        let a = macosLerp(p0, p1, 0.5)
        let b = macosLerp(p1, p2, 0.5)
        let m = macosLerp(a, b, 0.5)
        flattenQuadMacos(p0, a, m, depth + 1, &out)
        flattenQuadMacos(m, b, p2, depth + 1, &out)
    }
}

/// `path` as moves, lines and closes only.
func macosFlatten(_ path: [MacosCmd]) -> MacosPath {
    var out: MacosPath = []
    out.reserveCapacity(path.count * 4)
    var cur = MacosPoint(0.0, 0.0)
    var first = cur
    for c in path {
        switch c {
        case .move(let p):
            cur = macosF32p(p)
            first = cur
            out.append(.move(cur))
        case .line(let p):
            cur = macosF32p(p)
            out.append(.line(cur))
        case .cubic(let a, let b, let p):
            let ep = macosF32p(p)
            flattenCubicMacos(cur, macosF32p(a), macosF32p(b), ep, 0, &out)
            cur = ep
        case .quad(let a, let p):
            let ep = macosF32p(p)
            flattenQuadMacos(cur, macosF32p(a), ep, 0, &out)
            cur = ep
        case .close:
            out.append(.close)
            cur = first
        }
    }
    return out
}
