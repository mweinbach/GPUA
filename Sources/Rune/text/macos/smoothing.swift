// Ported from: crates/rune/src/text/macos/smoothing.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! CoreGraphics' glyph rasterisation pipeline on macOS 15.3 (24D60), reproduced from unhinted
//! outlines: luminance-bucketed direction-sign dilation, small-size y autohinting, Bezier
//! flattening, and analytic coverage rasterisation.

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

/// Which stages of CoreGraphics' glyph pipeline `TextSystem` runs.
public struct ApplePipeline: Sendable, Equatable, Hashable {
    /// Grow outlines by `radiusForBucket` (`CGContextSetShouldSmoothFonts(true)`).
    public var dilate: Bool
    /// Flatten Beziers with CoreGraphics' second-difference test (`macosFlatten`).
    public var flatten: Bool
    /// Snap the x-height and cap height at integer 7-18 px (`macosAutohint`).
    public var hint: Bool

    /// Every stage on: CoreGraphics with font smoothing enabled (macOS's default).
    public static let SMOOTHED = ApplePipeline(dilate: true, flatten: true, hint: true)
    /// Hinting and flattening without dilation: CoreGraphics with font smoothing off.
    public static let UNSMOOTHED = ApplePipeline(dilate: false, flatten: true, hint: true)

    public init(dilate: Bool = true, flatten: Bool = true, hint: Bool = true) {
        self.dilate = dilate
        self.flatten = flatten
        self.hint = hint
    }

    // PORT NOTE: Preserves Spine backwards-compatible initializer and property alias.
    public init(dilation: Bool, subpixelQuantization: Bool) {
        _ = subpixelQuantization
        self.dilate = dilation
        self.flatten = true
        self.hint = true
    }

    public var dilation: Bool {
        get { dilate }
        set { dilate = newValue }
    }

    public var subpixelQuantization: Bool { true }

    func bits() -> UInt8 {
        (dilate ? 1 : 0) | ((flatten ? 1 : 0) << 1) | ((hint ? 1 : 0) << 2)
    }
}

/// Hint metrics kept per face before the cache restarts.
private let MAX_FACES: Int = 256

struct MacosPoint: Sendable, Equatable {
    var x: Double
    var y: Double

    init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    subscript(_ axis: Int) -> Double {
        get { axis == 0 ? x : y }
        set {
            if axis == 0 { x = newValue } else { y = newValue }
        }
    }
}

enum MacosCmd: Sendable, Equatable {
    case move(MacosPoint)
    case line(MacosPoint)
    case quad(MacosPoint, MacosPoint)
    case cubic(MacosPoint, MacosPoint, MacosPoint)
    case close

    func map(_ f: (MacosPoint) -> MacosPoint) -> MacosCmd {
        switch self {
        case .move(let a): return .move(f(a))
        case .line(let a): return .line(f(a))
        case .quad(let a, let b): return .quad(f(a), f(b))
        case .cubic(let a, let b, let c): return .cubic(f(a), f(b), f(c))
        case .close: return .close
        }
    }

    func end() -> MacosPoint? {
        switch self {
        case .move(let p), .line(let p), .quad(_, let p), .cubic(_, _, let p):
            return p
        case .close:
            return nil
        }
    }
}

typealias MacosPath = [MacosCmd]

struct FaceMetricsKey: Sendable, Equatable, Hashable {
    var font: UInt64
    var index: UInt32
    var coords: UInt64
}

/// The selected pipeline, per-ink dilation state and the autohinter's per-face metrics.
struct Smoothing: Sendable {
    var pipeline: ApplePipeline
    /// Luminance bucket per `Ink`: 0 is the element's colour, n is `spans[n - 1]`'s.
    var inks: [UInt8]
    var metrics: [FaceMetricsKey: HintMetrics?]

    init(pipeline: ApplePipeline = FontSmoothing.default.pipeline()) {
        self.pipeline = pipeline
        self.inks = []
        self.metrics = [:]
    }

    mutating func setPipeline(_ p: ApplePipeline) {
        pipeline = p
    }

    mutating func setInks(_ base: Color, _ spans: [Span]) {
        inks.removeAll(keepingCapacity: true)
        if !pipeline.dilate {
            return
        }
        let baseBucket = colorBucket(base)
        inks.append(baseBucket)
        inks.reserveCapacity(1 + spans.count)
        for sp in spans {
            inks.append(sp.color.map(colorBucket) ?? baseBucket)
        }
    }

    /// `(dilationKey, radiusPx)` for `ink` at `ppem` device px.
    func dilation(_ ink: UInt16, _ ppem: Float) -> (UInt16, Double) {
        if !pipeline.dilate {
            return (0, 0.0)
        }
        let idx = Int(ink)
        let bucket: UInt8
        if idx < inks.count {
            bucket = inks[idx]
        } else if let first = inks.first {
            bucket = first
        } else {
            bucket = 0
        }
        let r = radiusForBucket(Double(ppem), bucket)
        let key = UInt16(truncatingIfNeeded: Float(r).bitPattern >> 16)
        return (key, r)
    }

    mutating func clearInks() {
        inks.removeAll(keepingCapacity: true)
    }

    mutating func maskForOutline(
        outline: MacosPath,
        faceKey: FaceMetricsKey,
        metricsProvider: () -> HintMetrics?,
        ppem: Float,
        phaseX: Float,
        shiftY: Float,
        radius: Double,
        skewDegrees: UInt8
    ) -> ([UInt8], Rasterized)? {
        guard !outline.isEmpty else { return nil }
        let skewed: MacosPath
        if skewDegrees == 0 {
            skewed = outline
        } else {
            let t = tan(Double(skewDegrees) * (.pi / 180.0))
            skewed = outline.map { c in
                c.map { p in MacosPoint(macosMulAdd(p.y, t, p.x), p.y) }
            }
        }
        let m: HintMetrics?
        if pipeline.hint && skewDegrees == 0 && macosHintEligible(Double(ppem)) {
            if metrics.count >= MAX_FACES && metrics[faceKey] == nil {
                metrics.removeAll(keepingCapacity: true)
            }
            if let existing = metrics[faceKey] {
                m = existing
            } else {
                let computed = metricsProvider()
                metrics[faceKey] = .some(computed)
                m = computed
            }
        } else {
            m = nil
        }
        var prepared = prepareOutline(
            skewed,
            pipeline: pipeline,
            ppem: Double(ppem),
            radius: radius,
            phase: MacosPoint(Double(phaseX), 0.0),
            metrics: m
        )
        if shiftY != 0.0 {
            let dy = -Double(shiftY)
            prepared = prepared.map { c in c.map { v in MacosPoint(v.x, v.y + dy) } }
        }
        guard !prepared.isEmpty else { return nil }
        return macosMask(prepared)
    }
}

@inline(__always)
func macosMulAdd(_ x: Double, _ a: Double, _ b: Double) -> Double {
    b.addingProduct(x, a)
}

@inline(__always)
func macosF32p(_ p: MacosPoint) -> MacosPoint {
    MacosPoint(Double(Float(p.x)), Double(Float(p.y)))
}

@inline(__always)
func macosLerp(_ a: MacosPoint, _ b: MacosPoint, _ t: Double) -> MacosPoint {
    MacosPoint(macosMulAdd(b.x - a.x, t, a.x), macosMulAdd(b.y - a.y, t, a.y))
}

func macosSplitCubic(
    _ p0: MacosPoint,
    _ p1: MacosPoint,
    _ p2: MacosPoint,
    _ p3: MacosPoint,
    _ t: Double
) -> ((MacosPoint, MacosPoint, MacosPoint, MacosPoint), (MacosPoint, MacosPoint, MacosPoint, MacosPoint)) {
    let a = macosLerp(p0, p1, t)
    let b = macosLerp(p1, p2, t)
    let c = macosLerp(p2, p3, t)
    let d = macosLerp(a, b, t)
    let e = macosLerp(b, c, t)
    let f = macosLerp(d, e, t)
    return ((p0, a, d, f), (f, e, c, p3))
}

/// Encoded sRGB to linear; Rune's colours are already linear, so only reference captures need it.
func srgbToLinear(_ v: Double) -> Double {
    if v <= 0.04045 {
        return v / 12.92
    } else {
        return pow((v + 0.055) / 1.055, 2.4)
    }
}

/// The bucket (`q * 4`) of a linear-sRGB colour: Rec. 709 luminance rounded to quarters, half
/// away from zero. Alpha and the background play no part.
func luminanceBucket(_ rgb: [Double]) -> UInt8 {
    let r = rgb[0], g = rgb[1], b = rgb[2]
    let y = macosMulAdd(b, 0.0722, macosMulAdd(r, 0.2126, g * 0.7152))
    let q = min(max((y * 4.0).rounded(.toNearestOrAwayFromZero), 0.0), 4.0)
    return UInt8(q)
}

func colorBucket(_ c: Color) -> UInt8 {
    luminanceBucket([Double(c.r), Double(c.g), Double(c.b)])
}

/// `min(ppem * (0.0058 + 0.01 q), 0.3f)`: a radius, not total growth. The cap is the `Float`
/// literal `0.3` widened to `Double`, and there is no ppem cutoff.
func radiusForBucket(_ ppem: Double, _ bucket: UInt8) -> Double {
    let slope = macosMulAdd(Double(min(bucket, 4)) * 0.25, 0.010000000000000002, 0.0058)
    return min(slope * ppem, Double(Float(0.3)))
}

/// Steps 2-5 of the recipe, each stage as `pipeline` selects: fractional origin first, then
/// dilation by `radius`, the autohinter (with the same radius, 0 undilated) when `metrics` is
/// given and the vertical phase is zero, and CoreGraphics' flattening into lines.
func prepareOutline(
    _ path: [MacosCmd],
    pipeline: ApplePipeline,
    ppem: Double,
    radius: Double,
    phase: MacosPoint,
    metrics: HintMetrics?
) -> MacosPath {
    let moved = path.map { c in c.map { v in MacosPoint(v.x + phase.x, v.y + phase.y) } }
    var out: MacosPath
    let effRadius: Double
    if pipeline.dilate {
        out = macosDilate(moved, dx: radius, dy: radius)
        effRadius = radius
    } else {
        out = moved
        effRadius = 0.0
    }
    if pipeline.hint && phase.y == 0.0, let m = metrics, let t = macosAutohint(m, ppem, effRadius) {
        out = out.map { c in c.map { v in MacosPoint(v.x, t.apply(v.y)) } }
    }
    if pipeline.flatten {
        return macosFlatten(out)
    } else {
        return out
    }
}

/// Coverage and `Origin.bottomLeft` placement of a prepared (y-up) outline.
func macosMask(_ path: [MacosCmd]) -> ([UInt8], Rasterized) {
    var polygons: [[(Double, Double)]] = []
    var cur: [(Double, Double)] = []
    var startPt: (Double, Double) = (0, 0)
    var pen: (Double, Double) = (0, 0)

    for cmd in path {
        switch cmd {
        case .move(let p):
            if cur.count >= 2 {
                polygons.append(cur)
            }
            cur.removeAll(keepingCapacity: true)
            let sp = (Double(Float(p.x)), Double(Float(p.y)))
            startPt = sp
            pen = sp
            cur.append(sp)
        case .line(let p):
            let sp = (Double(Float(p.x)), Double(Float(p.y)))
            cur.append(sp)
            pen = sp
        case .quad(let a, let p):
            let sa = (Double(Float(a.x)), Double(Float(a.y)))
            let sp = (Double(Float(p.x)), Double(Float(p.y)))
            flattenQuadTo(pen, sa, sp, tol2: 0.0004, depth: 0) { cur.append($0) }
            pen = sp
        case .cubic(let a, let b, let p):
            let sa = (Double(Float(a.x)), Double(Float(a.y)))
            let sb = (Double(Float(b.x)), Double(Float(b.y)))
            let sp = (Double(Float(p.x)), Double(Float(p.y)))
            flattenCubicTo(pen, sa, sb, sp, tol2: 0.0004, depth: 0) { cur.append($0) }
            pen = sp
        case .close:
            if cur.count >= 2 {
                polygons.append(cur)
            }
            cur.removeAll(keepingCapacity: true)
            pen = startPt
        }
    }
    if cur.count >= 2 {
        polygons.append(cur)
    }
    return ScanlineMask.renderBottomLeft(polygonsYUp: polygons, fillRule: .nonZero)
}

/// Derivative roots of a cubic along `axis` inside `1e-10...0.9999999999`.
private func cubicRoots(
    _ p0: MacosPoint,
    _ p1: MacosPoint,
    _ p2: MacosPoint,
    _ p3: MacosPoint,
    axis: Int
) -> [Double] {
    let v0 = p0[axis], v1 = p1[axis], v2 = p2[axis], v3 = p3[axis]
    let a = macosMulAdd(v1 - v2, 3.0, v3 - v0)
    let b = macosMulAdd(v1, -2.0, v0 + v2)
    let disc = macosMulAdd(v0 - v1, v3, macosMulAdd(v2, v2 - v0, (v1 - v2) * v1))
    if disc < 0.0 {
        return []
    }
    var ts: [Double]
    if a == 0.0 {
        ts = (b == 0.0) ? [] : [(v0 - v1) * 0.5 / b]
    } else if b == 0.0 && disc == 0.0 {
        ts = []
    } else {
        let signB = (b < 0.0) ? -1.0 : 1.0
        let q = -macosMulAdd(signB, disc.squareRoot(), b)
        // CoreGraphics' second root divides the y delta p1.y - p0.y for both axes; the
        // x-split stage inherits that quirk, which the reference reproduces.
        ts = [q / a, (p1.y - p0.y) / q]
    }
    ts = ts.filter { $0.isFinite && $0 >= 1e-10 && $0 <= 0.9999999999 }
    ts.sort()
    var dedup: [Double] = []
    for t in ts {
        if let last = dedup.last, abs(t - last) < 1e-12 {
            continue
        }
        dedup.append(t)
    }
    return dedup
}

private func monotonicParts(
    _ p0: MacosPoint,
    _ p1: MacosPoint,
    _ p2: MacosPoint,
    _ p3: MacosPoint,
    axis: Int
) -> [(MacosPoint, MacosPoint, MacosPoint, MacosPoint)] {
    var prev = 0.0
    var rem = (p0, p1, p2, p3)
    var out: [(MacosPoint, MacosPoint, MacosPoint, MacosPoint)] = []
    for t in cubicRoots(p0, p1, p2, p3, axis: axis) {
        let (a, b) = macosSplitCubic(rem.0, rem.1, rem.2, rem.3, (t - prev) / (1.0 - prev))
        out.append(a)
        rem = b
        prev = t
    }
    out.append(rem)
    return out
}

/// Signed area integral of a cubic Bezier, exact in its polynomial form.
private func cubicCurveArea(_ p0: MacosPoint, _ p1: MacosPoint, _ p2: MacosPoint, _ p3: MacosPoint) -> Double {
    let a0 = MacosPoint(p0.x, p0.y)
    let a1 = MacosPoint(3.0 * (p1.x - p0.x), 3.0 * (p1.y - p0.y))
    let a2 = MacosPoint(3.0 * (p0.x - 2.0 * p1.x + p2.x), 3.0 * (p0.y - 2.0 * p1.y + p2.y))
    let a3 = MacosPoint(-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x, -p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y)
    let coeffs = [a0, a1, a2, a3]
    var area = 0.0
    for i in 0..<4 {
        let ai = coeffs[i]
        for j in 1..<4 {
            let aj = coeffs[j]
            area += (ai.x * aj.y - ai.y * aj.x) * Double(j) / Double(i + j)
        }
    }
    return area
}

/// The whole glyph turned to positive signed area: all contours reverse together, so holes
/// keep winding against the outer contours.
func macosNormalize(_ path: [MacosCmd]) -> MacosPath {
    var area = 0.0
    var prev = MacosPoint(0, 0)
    var first = prev
    for c in path {
        switch c {
        case .move(let p):
            prev = p
            first = p
        case .line(let p):
            area += prev.x * p.y - p.x * prev.y
            prev = p
        case .quad(let q, let p):
            area += cubicCurveArea(prev, macosLerp(prev, q, 2.0 / 3.0), macosLerp(p, q, 2.0 / 3.0), p)
            prev = p
        case .cubic(let a, let b, let p):
            area += cubicCurveArea(prev, a, b, p)
            prev = p
        case .close:
            area += prev.x * first.y - first.x * prev.y
            prev = first
        }
    }
    if area >= 0.0 {
        return path
    }
    func flush(_ segs: inout [(MacosPoint, MacosCmd)], _ out: inout MacosPath, _ cur: MacosPoint) {
        if segs.isEmpty { return }
        out.append(.move(cur))
        for (p, c) in segs.reversed() {
            switch c {
            case .quad(let a, _):
                out.append(.quad(a, p))
            case .cubic(let a, let b, _):
                out.append(.cubic(b, a, p))
            default:
                out.append(.line(p))
            }
        }
        segs.removeAll(keepingCapacity: true)
        out.append(.close)
    }
    var out: MacosPath = []
    var segs: [(MacosPoint, MacosCmd)] = []
    var start = MacosPoint(0, 0)
    var cur = start
    for c in path {
        switch c {
        case .move(let p):
            flush(&segs, &out, cur)
            start = p
            cur = p
        case .close:
            flush(&segs, &out, cur)
            cur = start
        default:
            segs.append((cur, c))
            if let endPt = c.end() {
                cur = endPt
            }
        }
    }
    flush(&segs, &out, cur)
    return out
}

private struct Dilator {
    var out: MacosPath = []
    var cur = MacosPoint(0, 0)
    var first = MacosPoint(0, 0)
    var started: Bool = false
    var dx: Float
    var dy: Float

    mutating func emit(_ to: MacosPoint, _ controls: (MacosPoint, MacosPoint)?) {
        let signF = { (v: Float) -> Float in v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0) }
        let deltaX = Float(to.x - cur.x)
        let deltaY = Float(to.y - cur.y)
        let sx = signF(deltaY) * dx
        let sy = -signF(deltaX) * dy
        let dyF = dy
        let start = MacosPoint(
            Double((Float(cur.x) + sx) + 0.0),
            Double((Float(cur.y) + sy) + dyF)
        )
        out.append(started ? .line(start) : .move(start))
        started = true
        let shift = { (p: MacosPoint) -> MacosPoint in
            MacosPoint((Double(sx) + p.x) + 0.0, (Double(sy) + p.y) + Double(dyF))
        }
        if let (a, b) = controls {
            out.append(.cubic(shift(a), shift(b), shift(to)))
        } else {
            out.append(.line(shift(to)))
        }
        cur = macosF32p(to)
    }

    mutating func close() {
        if started {
            emit(first, nil)
            out.append(.close)
            started = false
        }
    }

    mutating func cubic(_ p0: MacosPoint, _ p1: MacosPoint, _ p2: MacosPoint, _ p3: MacosPoint) {
        for xpart in monotonicParts(p0, p1, p2, p3, axis: 0) {
            for part in monotonicParts(xpart.0, xpart.1, xpart.2, xpart.3, axis: 1) {
                emit(part.3, (part.1, part.2))
            }
        }
    }
}

/// CoreGraphics' direction-sign dilation by radii `dx`, `dy` (y also gains `+dy`). Quadratics
/// become cubics; cubics split at x then y extrema; pieces join with bevel lines.
func macosDilate(_ path: [MacosCmd], dx: Double, dy: Double) -> MacosPath {
    var d = Dilator(dx: Float(dx), dy: Float(dy))
    for c in macosNormalize(path) {
        switch c {
        case .move(let p):
            d.close()
            d.cur = macosF32p(p)
            d.first = d.cur
        case .line(let p):
            d.emit(p, nil)
        case .quad(let q, let p):
            let qcx = Float(2.0 * q.x / 3.0)
            let qcy = Float(2.0 * q.y / 3.0)
            let a = MacosPoint(
                Double(Float(d.cur.x) / 3.0 + qcx),
                Double(Float(d.cur.y) / 3.0 + qcy)
            )
            let b = MacosPoint(
                p.x / 3.0 + Double(qcx),
                p.y / 3.0 + Double(qcy)
            )
            d.cubic(d.cur, a, b, p)
        case .cubic(let a, let b, let p):
            d.cubic(d.cur, a, b, p)
        case .close:
            d.close()
        }
    }
    d.close()
    return d.out
}

/// `glyph`'s unhinted outline at `ppem` from a TrueType (`glyf`) `SfntFont`, extracted in design units and scaled in `Double`.
func designOutline(_ sfnt: SfntFont, glyph: UInt16, ppem: Double) -> MacosPath? {
    sfnt.glyphOutline(glyph, ppem: ppem)
}
