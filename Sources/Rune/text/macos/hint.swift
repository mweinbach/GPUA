// Ported from: crates/rune/src/text/macos/hint.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! CoreGraphics' small-size y autohinter. It isn't TrueType bytecode: at integer ppem 7-18,
//! with an axis-aligned isotropic em matrix and zero vertical phase, it maps every control
//! point's y through a piecewise-linear transform that snaps the x-height ('o' top) and cap
//! height ('X' top) to whole pixels. It runs after dilation and before flattening.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#elseif os(Windows)
import CRT
#elseif os(WASI)
import WASILibc
#endif

/// Unscaled font-unit metrics. `xHeight` and `capHeight` are the bounding-box tops of 'o'
/// and 'X', not the OS/2 fields; `maxY` is the font bounding box's top; `stemHeight` is the
/// descriptor's stemH (0 for TrueType).
struct HintMetrics: Sendable, Equatable {
    var upem: Double
    var xHeight: Double
    var capHeight: Double
    var maxY: Double
    var stemHeight: Double
}

/// `[-d, a, b, B, c, C, e, E, l, m, u]` in the spec's names.
struct HintTransform: Sendable, Equatable {
    var values: [Double]

    @inline(__always)
    func apply(_ y: Double) -> Double {
        let v = values
        if y < v[1] {
            return y
        } else if y <= v[2] {
            return macosMulAdd(y - v[1], v[8], v[1])
        } else if y <= v[4] {
            return macosMulAdd(y - v[2], v[9], v[3])
        } else if y <= v[6] {
            return y + (v[5] - v[4])
        } else {
            return macosMulAdd(y - v[6], v[10], v[7])
        }
    }
}

/// Integer ppem 7 through 18.
func macosHintEligible(_ ppem: Double) -> Bool {
    ppem >= 7.0 && ppem <= 18.0 && ppem.truncatingRemainder(dividingBy: 1.0) == 0.0
}

private func evalHint(_ m: HintMetrics, _ scale: Double, _ d: Double, _ xTarget: Double, _ capTarget: Double) -> HintTransform {
    let baseStem = (m.stemHeight == 0.0) ? m.capHeight : m.stemHeight
    let stem = min(min(baseStem, m.xHeight * 0.333), (m.capHeight - m.xHeight) * 0.5) * scale
    let lo = stem + d
    let x = macosMulAdd(m.xHeight, scale, d)
    let xt = xTarget - d
    let cap = macosMulAdd(m.capHeight, scale, d)
    var ct = capTarget - d
    let middle = m.capHeight * scale - stem - d
    var mt = macosMulAdd(-2.0, d, ct - stem)
    let top = macosMulAdd(m.maxY, scale, d)
    let slope = { (a: Double, b: Double) -> Double in
        b == 0.0 ? 0.0 : (a / b)
    }
    let s1 = slope(xt - lo, x - lo)
    var s2 = slope(mt - xt, middle - x)
    var s3 = slope(top - ct, top - cap)
    // A cap height that would squash the middle band isn't snapped.
    if s2 < 0.75 || s2 - s1 > 0.3 {
        ct = cap
        mt = macosMulAdd(-2.0, d, cap - stem)
        s2 = slope(mt - xt, middle - x)
        s3 = 1.0
    }
    return HintTransform(values: [-d, lo, x, xt, middle, mt, cap, ct, s1, s2, s3])
}

/// The transform for radius `d` at `ppem`, or `nil` when the size or the metrics don't take it.
func macosAutohint(_ m: HintMetrics, _ ppem: Double, _ d: Double) -> HintTransform? {
    if !macosHintEligible(ppem) || m.xHeight == m.capHeight {
        return nil
    }
    let scale = ppem / m.upem
    // Targets are chosen at a reference radius that doesn't depend on the ink.
    let reference = min(ppem * 0.015125, 0.3)
    let r = { (v: Double) -> Double in (v + 0.5).rounded(.towardZero) }
    var xt = r(macosMulAdd(m.xHeight, scale, 2.0 * reference))
    var ct = r(macosMulAdd(m.capHeight, scale, 2.0 * reference))
    let plainX = r(m.xHeight * scale)
    let plainCap = r(m.capHeight * scale)
    if plainX != xt {
        let cost = { (xVal: Double, cVal: Double) -> Double in
            var sum = 0.0
            for rad in [reference, 0.0] {
                let t = evalHint(m, scale, rad, xVal, cVal)
                sum += abs(t.values[8] - 1.0) + abs(t.values[9] - 1.0)
            }
            return sum
        }
        if cost(xt, ct) > cost(plainX, plainCap) {
            xt = plainX
            ct = plainCap
        }
    }
    let t = evalHint(m, scale, d, xt, ct)
    if m.xHeight / m.capHeight > 0.85 && t.values[9] < 0.33 {
        return nil
    }
    return t
}

/// Metrics for a TrueType (`glyf`) face from its `'o'` and `'X'` outlines, `head`
/// and the known descriptor stemH. Other formats return `nil`, so they aren't hinted.
func truetypeMetrics(_ sfnt: SfntFont) -> HintMetrics? {
    guard sfnt.tableRange(SfntTag.glyf) != nil,
          let upemU16 = sfnt.unitsPerEm(),
          let headMaxY = sfnt.headYMax()
    else {
        return nil
    }
    let upem = Double(upemU16)
    let maxY = Double(headMaxY)
    guard let oGid = sfnt.glyphId(for: UnicodeScalar("o")), oGid != 0,
          let xGid = sfnt.glyphId(for: UnicodeScalar("X")), xGid != 0,
          let xHeight = sfnt.glyphMaxY(oGid),
          let capHeight = sfnt.glyphMaxY(xGid)
    else {
        return nil
    }
    let psName = sfnt.postScriptName() ?? ""
    let stemHeight = descriptorStemHeight(postScriptName: psName)
    return HintMetrics(
        upem: upem,
        xHeight: Double(xHeight),
        capHeight: Double(capHeight),
        maxY: maxY,
        stemHeight: stemHeight
    )
}

func descriptorStemHeight(postScriptName name: String) -> Double {
    if name.hasPrefix(".SFNS") {
        return 79.0
    } else if name == "Helvetica" {
        return 85.0
    } else {
        return 0.0
    }
}
