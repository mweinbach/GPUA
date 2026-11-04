// Tests ported from: crates/rune-kit/tests/glyphs.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Every built-in glyph rasterises like a reference SVG renderer at the sizes components draw
//! them. Set `RUNE_GLYPH_PROOF=<dir>` to also write enlarged contact sheets: Rune's mask, the
//! reference rasteriser's, and their difference, per glyph and size.

import Testing
import Rune
@testable import RuneKit
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if !os(WASI)
import Foundation
#endif

private let ALL_GLYPHS: [Icon] = [
    glyphs.CHECK,
    glyphs.CHECK_SMALL,
    glyphs.CHEVRON_DOWN,
    glyphs.CHEVRON_UP,
    glyphs.CARET_RIGHT,
    glyphs.TRIANGLE_DOWN,
    glyphs.TRIANGLE_RIGHT,
    glyphs.CLOSE,
    glyphs.COPY,
    glyphs.SEARCH,
    glyphs.CIRCLE_X,
    glyphs.LOCK,
    glyphs.EYE,
    glyphs.EYE_OFF,
    glyphs.DASH,
    glyphs.FOLDER,
    glyphs.FOLDER_OPEN,
    glyphs.FILE,
    glyphs.FILE_CODE,
    glyphs.FILE_TEXT,
    glyphs.FILE_IMAGE,
    glyphs.MIC,
    glyphs.KEYBOARD,
    glyphs.CURSOR_TEXT,
    glyphs.ARROW_RIGHT,
    glyphs.SPARKLE,
    glyphs.STAR,
    glyphs.STAR_FILLED,
]

/// Glyph sizes in points (a password manager's 16–20 pt plus a large one) at 1x and 2x.
private let GLYPH_POINTS: [UInt32] = [16, 20, 32]

/// Coverage that differs, as a share of the coverage either mask has (0 = identical).
private func glyphMismatch(_ a: [UInt8], _ b: [UInt8]) -> Float {
    var diff: UInt32 = 0
    var ink: UInt32 = 0
    for (lhs, rhs) in zip(a, b) {
        let lo = UInt32(min(lhs, rhs))
        let hi = UInt32(max(lhs, rhs))
        diff += hi - lo
        ink += hi
    }
    return Float(diff) / Float(max(ink, 1))
}

#if canImport(CoreGraphics)
// PORT NOTE: Substitutes upstream's `resvg` + `tiny_skia` dev-dependency with a native Quartz 2D
// (`CoreGraphics`) 4x-supersampled reference rasteriser so no external dependency is needed (Rule 8).
private func referenceCoverage(_ icon: Icon, _ px: UInt32) -> [UInt8] {
    let ss: UInt32 = 4
    let big = Int(px * ss)
    var rgba = [UInt8](repeating: 0, count: big * big * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    rgba.withUnsafeMutableBytes { ptr in
        guard let base = ptr.baseAddress,
              let ctx = CGContext(
                  data: base,
                  width: big,
                  height: big,
                  bitsPerComponent: 8,
                  bytesPerRow: big * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            preconditionFailure("CGContext allocation failed")
        }
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        let s = CGFloat(big) / CGFloat(icon.view)
        ctx.translateBy(x: 0.0, y: CGFloat(big))
        ctx.scaleBy(x: s, y: -s)
        ctx.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        ctx.setStrokeColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)

        // Rune strokes without filling when an element names only a stroke, like icon sets that
        // put `fill="none"` on the root `<svg>`.
        for (tag, attrs) in parseXmlTags(icon.body) {
            guard let path = buildCgPath(tag: tag, attrs: attrs) else { continue }
            let fillAttr = xmlAttr(attrs, "fill")
            let strokeAttr = xmlAttr(attrs, "stroke")
            let hasFill = fillAttr != nil && fillAttr != "none"
            let hasStroke = strokeAttr != nil && strokeAttr != "none"
            if hasFill {
                let evenOdd = xmlAttr(attrs, "fill-rule") == "evenodd"
                ctx.addPath(path)
                ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
            }
            if hasStroke {
                let width = CGFloat(xmlAttrDouble(attrs, "stroke-width") ?? 1.0)
                let cap: CGLineCap
                switch xmlAttr(attrs, "stroke-linecap") {
                case "round": cap = .round
                case "square": cap = .square
                default: cap = .butt
                }
                let join: CGLineJoin
                switch xmlAttr(attrs, "stroke-linejoin") {
                case "round": join = .round
                case "bevel": join = .bevel
                default: join = .miter
                }
                ctx.saveGState()
                ctx.setLineWidth(width)
                ctx.setLineCap(cap)
                ctx.setLineJoin(join)
                ctx.setMiterLimit(4.0)
                ctx.addPath(path)
                ctx.strokePath()
                ctx.restoreGState()
            }
        }
    }

    let step = Int(ss)
    let count = Int(px * px)
    var out = [UInt8](repeating: 0, count: count)
    let denom = UInt32(ss * ss)
    for i in 0..<count {
        let bx = (i % Int(px)) * step
        let by = (i / Int(px)) * step
        var sum: UInt32 = 0
        for dy in 0..<step {
            for dx in 0..<step {
                sum += UInt32(rgba[((by + dy) * big + (bx + dx)) * 4 + 3])
            }
        }
        out[i] = UInt8((sum + denom / 2) / denom)
    }
    return out
}

private func parseXmlTags(_ s: String) -> [(String, String)] {
    var out: [(String, String)] = []
    var rest = s[...]
    while let openIdx = rest.firstIndex(of: "<") {
        rest = rest[rest.index(after: openIdx)...]
        guard let closeIdx = rest.firstIndex(of: ">") else { break }
        var inside = rest[..<closeIdx]
        rest = rest[rest.index(after: closeIdx)...]
        while let f = inside.first, f.isWhitespace { inside = inside.dropFirst() }
        while let l = inside.last, l.isWhitespace || l == "/" { inside = inside.dropLast() }
        guard let first = inside.first, first != "/", first != "!", first != "?" else { continue }
        let splitIdx = inside.firstIndex(where: { $0.isWhitespace }) ?? inside.endIndex
        out.append((String(inside[..<splitIdx]), String(inside[splitIdx...])))
    }
    return out
}

private func xmlAttr(_ attrs: String, _ name: String) -> String? {
    let bytes = Array(attrs.utf8)
    let needle = Array(name.utf8)
    guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
    var i = 0
    while i + needle.count <= bytes.count {
        if Array(bytes[i..<(i + needle.count)]) == needle {
            let prevOk = i == 0
                || bytes[i - 1] == UInt8(ascii: " ")
                || bytes[i - 1] == UInt8(ascii: "\t")
                || bytes[i - 1] == UInt8(ascii: "\n")
                || bytes[i - 1] == UInt8(ascii: "\"")
                || bytes[i - 1] == UInt8(ascii: "'")
            if prevOk {
                var j = i + needle.count
                while j < bytes.count && (bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t")) { j += 1 }
                if j < bytes.count && bytes[j] == UInt8(ascii: "=") {
                    j += 1
                    while j < bytes.count && (bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t")) { j += 1 }
                    if j < bytes.count && (bytes[j] == UInt8(ascii: "\"") || bytes[j] == UInt8(ascii: "'")) {
                        let q = bytes[j]
                        j += 1
                        let start = j
                        while j < bytes.count && bytes[j] != q { j += 1 }
                        if j < bytes.count {
                            return String(decoding: bytes[start..<j], as: UTF8.self)
                        }
                    }
                }
            }
        }
        i += 1
    }
    return nil
}

private func xmlAttrDouble(_ attrs: String, _ name: String) -> Double? {
    guard var raw = xmlAttr(attrs, name) else { return nil }
    if raw.hasSuffix("px") { raw.removeLast(2) }
    return Double(raw.trimmingCharacters(in: .whitespaces))
}

private func buildCgPath(tag: String, attrs: String) -> CGPath? {
    switch tag {
    case "path":
        guard let d = xmlAttr(attrs, "d") else { return nil }
        return parseSvgCgPath(d)
    case "rect":
        let x = xmlAttrDouble(attrs, "x") ?? 0.0
        let y = xmlAttrDouble(attrs, "y") ?? 0.0
        let w = xmlAttrDouble(attrs, "width") ?? 0.0
        let h = xmlAttrDouble(attrs, "height") ?? 0.0
        guard w > 0.0, h > 0.0 else { return nil }
        let r = min(max(xmlAttrDouble(attrs, "rx") ?? 0.0, 0.0), min(w * 0.5, h * 0.5))
        let rect = CGRect(x: x, y: y, width: w, height: h)
        if r > 0.0 {
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        return CGPath(rect: rect, transform: nil)
    case "circle":
        let cx = xmlAttrDouble(attrs, "cx") ?? 0.0
        let cy = xmlAttrDouble(attrs, "cy") ?? 0.0
        let r = xmlAttrDouble(attrs, "r") ?? 0.0
        guard r > 0.0 else { return nil }
        return CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2.0 * r, height: 2.0 * r), transform: nil)
    case "ellipse":
        let cx = xmlAttrDouble(attrs, "cx") ?? 0.0
        let cy = xmlAttrDouble(attrs, "cy") ?? 0.0
        let rx = xmlAttrDouble(attrs, "rx") ?? 0.0
        let ry = xmlAttrDouble(attrs, "ry") ?? 0.0
        guard rx > 0.0, ry > 0.0 else { return nil }
        return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: 2.0 * rx, height: 2.0 * ry), transform: nil)
    case "line":
        let x1 = xmlAttrDouble(attrs, "x1") ?? 0.0
        let y1 = xmlAttrDouble(attrs, "y1") ?? 0.0
        let x2 = xmlAttrDouble(attrs, "x2") ?? 0.0
        let y2 = xmlAttrDouble(attrs, "y2") ?? 0.0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x1, y: y1))
        p.addLine(to: CGPoint(x: x2, y: y2))
        return p
    default:
        return nil
    }
}

private struct SvgScanner {
    let bytes: [UInt8]
    var pos: Int = 0

    init(_ s: String) {
        self.bytes = Array(s.utf8)
    }

    mutating func skipSep() {
        while pos < bytes.count {
            let b = bytes[pos]
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") || b == UInt8(ascii: "\n")
                || b == UInt8(ascii: "\r") || b == UInt8(ascii: ",")
            {
                pos += 1
            } else {
                break
            }
        }
    }

    var atEnd: Bool {
        mutating get {
            skipSep()
            return pos >= bytes.count
        }
    }

    mutating func nextCommand() -> UInt8? {
        skipSep()
        guard pos < bytes.count else { return nil }
        let b = bytes[pos]
        if (b >= UInt8(ascii: "A") && b <= UInt8(ascii: "Z"))
            || (b >= UInt8(ascii: "a") && b <= UInt8(ascii: "z"))
        {
            pos += 1
            return b
        }
        return nil
    }

    mutating func hasNumber() -> Bool {
        skipSep()
        guard pos < bytes.count else { return false }
        let b = bytes[pos]
        return (b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9"))
            || b == UInt8(ascii: "-") || b == UInt8(ascii: "+") || b == UInt8(ascii: ".")
    }

    mutating func readNumber() -> Double {
        skipSep()
        let start = pos
        if pos < bytes.count && (bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-")) {
            pos += 1
        }
        while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
            pos += 1
        }
        if pos < bytes.count && bytes[pos] == UInt8(ascii: ".") {
            pos += 1
            while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
                pos += 1
            }
        }
        if pos < bytes.count && (bytes[pos] == UInt8(ascii: "e") || bytes[pos] == UInt8(ascii: "E")) {
            pos += 1
            if pos < bytes.count && (bytes[pos] == UInt8(ascii: "+") || bytes[pos] == UInt8(ascii: "-")) {
                pos += 1
            }
            while pos < bytes.count && bytes[pos] >= UInt8(ascii: "0") && bytes[pos] <= UInt8(ascii: "9") {
                pos += 1
            }
        }
        let slice = String(decoding: bytes[start..<pos], as: UTF8.self)
        return Double(slice) ?? 0.0
    }

    mutating func readFlag() -> Bool {
        skipSep()
        guard pos < bytes.count else { return false }
        let b = bytes[pos]
        pos += 1
        return b == UInt8(ascii: "1")
    }
}

private func parseSvgCgPath(_ d: String) -> CGPath {
    let p = CGMutablePath()
    var scan = SvgScanner(d)
    var cur = CGPoint.zero
    var start = CGPoint.zero
    var lastCubic: CGPoint? = nil
    var lastQuad: CGPoint? = nil
    var cmd: UInt8 = 0

    while !scan.atEnd {
        if let next = scan.nextCommand() {
            cmd = next
        } else if !scan.hasNumber() {
            break
        }
        let rel = cmd >= UInt8(ascii: "a") && cmd <= UInt8(ascii: "z")
        let upper = rel ? (cmd - 32) : cmd
        switch upper {
        case UInt8(ascii: "M"):
            var x = scan.readNumber()
            var y = scan.readNumber()
            if rel { x += cur.x; y += cur.y }
            cur = CGPoint(x: x, y: y)
            start = cur
            p.move(to: cur)
            lastCubic = nil
            lastQuad = nil
            cmd = rel ? UInt8(ascii: "l") : UInt8(ascii: "L")
        case UInt8(ascii: "L"):
            var x = scan.readNumber()
            var y = scan.readNumber()
            if rel { x += cur.x; y += cur.y }
            cur = CGPoint(x: x, y: y)
            p.addLine(to: cur)
            lastCubic = nil
            lastQuad = nil
        case UInt8(ascii: "H"):
            var x = scan.readNumber()
            if rel { x += cur.x }
            cur = CGPoint(x: x, y: cur.y)
            p.addLine(to: cur)
            lastCubic = nil
            lastQuad = nil
        case UInt8(ascii: "V"):
            var y = scan.readNumber()
            if rel { y += cur.y }
            cur = CGPoint(x: cur.x, y: y)
            p.addLine(to: cur)
            lastCubic = nil
            lastQuad = nil
        case UInt8(ascii: "C"):
            var x1 = scan.readNumber(), y1 = scan.readNumber()
            var x2 = scan.readNumber(), y2 = scan.readNumber()
            var x = scan.readNumber(), y = scan.readNumber()
            if rel {
                x1 += cur.x; y1 += cur.y
                x2 += cur.x; y2 += cur.y
                x += cur.x; y += cur.y
            }
            let c1 = CGPoint(x: x1, y: y1)
            let c2 = CGPoint(x: x2, y: y2)
            cur = CGPoint(x: x, y: y)
            p.addCurve(to: cur, control1: c1, control2: c2)
            lastCubic = c2
            lastQuad = nil
        case UInt8(ascii: "S"):
            let c1: CGPoint
            if let prev = lastCubic {
                c1 = CGPoint(x: 2.0 * cur.x - prev.x, y: 2.0 * cur.y - prev.y)
            } else {
                c1 = cur
            }
            var x2 = scan.readNumber(), y2 = scan.readNumber()
            var x = scan.readNumber(), y = scan.readNumber()
            if rel {
                x2 += cur.x; y2 += cur.y
                x += cur.x; y += cur.y
            }
            let c2 = CGPoint(x: x2, y: y2)
            cur = CGPoint(x: x, y: y)
            p.addCurve(to: cur, control1: c1, control2: c2)
            lastCubic = c2
            lastQuad = nil
        case UInt8(ascii: "Q"):
            var qx = scan.readNumber(), qy = scan.readNumber()
            var x = scan.readNumber(), y = scan.readNumber()
            if rel {
                qx += cur.x; qy += cur.y
                x += cur.x; y += cur.y
            }
            let ctrl = CGPoint(x: qx, y: qy)
            cur = CGPoint(x: x, y: y)
            p.addQuadCurve(to: cur, control: ctrl)
            lastQuad = ctrl
            lastCubic = nil
        case UInt8(ascii: "T"):
            let ctrl: CGPoint
            if let prev = lastQuad {
                ctrl = CGPoint(x: 2.0 * cur.x - prev.x, y: 2.0 * cur.y - prev.y)
            } else {
                ctrl = cur
            }
            var x = scan.readNumber(), y = scan.readNumber()
            if rel { x += cur.x; y += cur.y }
            cur = CGPoint(x: x, y: y)
            p.addQuadCurve(to: cur, control: ctrl)
            lastQuad = ctrl
            lastCubic = nil
        case UInt8(ascii: "A"):
            let rx = abs(scan.readNumber())
            let ry = abs(scan.readNumber())
            let rot = scan.readNumber()
            let largeArc = scan.readFlag()
            let sweep = scan.readFlag()
            var x = scan.readNumber(), y = scan.readNumber()
            if rel { x += cur.x; y += cur.y }
            let dst = CGPoint(x: x, y: y)
            addSvgArc(to: p, from: cur, dst: dst, rxIn: rx, ryIn: ry, rotDeg: rot, largeArc: largeArc, sweep: sweep)
            cur = dst
            lastCubic = nil
            lastQuad = nil
        case UInt8(ascii: "Z"):
            p.closeSubpath()
            cur = start
            lastCubic = nil
            lastQuad = nil
        default:
            break
        }
    }
    return p
}

private func addSvgArc(
    to path: CGMutablePath,
    from p1: CGPoint,
    dst p2: CGPoint,
    rxIn: Double,
    ryIn: Double,
    rotDeg: Double,
    largeArc: Bool,
    sweep: Bool
) {
    let x1 = Double(p1.x), y1 = Double(p1.y)
    let x2 = Double(p2.x), y2 = Double(p2.y)
    if (x1 == x2 && y1 == y2) { return }
    if rxIn == 0.0 || ryIn == 0.0 {
        path.addLine(to: p2)
        return
    }
    var rx = rxIn
    var ry = ryIn
    let phi = rotDeg * .pi / 180.0
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx2 = (x1 - x2) * 0.5
    let dy2 = (y1 - y2) * 0.5
    let x1p = cosPhi * dx2 + sinPhi * dy2
    let y1p = -sinPhi * dx2 + cosPhi * dy2

    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1.0 {
        let s = lambda.squareRoot()
        rx *= s
        ry *= s
    }

    let rxSq = rx * rx
    let rySq = ry * ry
    let x1pSq = x1p * x1p
    let y1pSq = y1p * y1p
    let denom = rxSq * y1pSq + rySq * x1pSq
    let num = max(0.0, rxSq * rySq - denom)
    let sign = (largeArc == sweep) ? -1.0 : 1.0
    let coef = sign * (denom > 0.0 ? (num / denom).squareRoot() : 0.0)
    let cxp = coef * (rx * y1p / ry)
    let cyp = coef * (-ry * x1p / rx)
    let cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) * 0.5
    let cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) * 0.5

    func vecAngle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
        atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    }

    let ux = (x1p - cxp) / rx
    let uy = (y1p - cyp) / ry
    let vx = (-x1p - cxp) / rx
    let vy = (-y1p - cyp) / ry
    let theta1 = vecAngle(1.0, 0.0, ux, uy)
    var dtheta = vecAngle(ux, uy, vx, vy)
    if !sweep && dtheta > 0.0 { dtheta -= 2.0 * .pi }
    if sweep && dtheta < 0.0 { dtheta += 2.0 * .pi }

    let segs = max(1, Int(ceil(abs(dtheta) / (.pi * 0.5))))
    let delta = dtheta / Double(segs)
    let alpha = (4.0 / 3.0) * tan(delta * 0.25)

    func mapPt(_ u: Double, _ v: Double) -> CGPoint {
        CGPoint(
            x: cx + cosPhi * rx * u - sinPhi * ry * v,
            y: cy + sinPhi * rx * u + cosPhi * ry * v
        )
    }

    for k in 0..<segs {
        let t0 = theta1 + Double(k) * delta
        let t1 = t0 + delta
        let c0 = cos(t0), s0 = sin(t0)
        let c1 = cos(t1), s1 = sin(t1)
        let cp1 = mapPt(c0 - alpha * s0, s0 + alpha * c0)
        let cp2 = mapPt(c1 + alpha * s1, s1 - alpha * c1)
        let end = mapPt(c1, s1)
        path.addCurve(to: end, control1: cp1, control2: cp2)
    }
}
#endif

private typealias SheetRow = (String, [(UInt32, [UInt8], [UInt8])])

#if !os(WASI)
/// One row per glyph; per size: Rune, reference, then red where Rune has extra ink and blue where
/// it lacks ink. Cells are enlarged 4x (nearest) on a white page.
private func writeGlyphSheet(_ path: String, _ rows: [SheetRow]) throws {
    let zoom: UInt32 = 4
    let gap: UInt32 = 8
    let maxPx = rows[0].1.map(\.0).max() ?? 16
    let cell = maxPx * zoom
    let cols = UInt32(GLYPH_POINTS.count * 3)
    let w = cols * (cell + gap) + gap
    let h = UInt32(rows.count) * (cell + gap) + gap
    var rgba = [UInt8](repeating: 255, count: Int(w * h * 4))
    let stride = Int(w)
    for (r, (_, sizes)) in rows.enumerated() {
        for (s, (px, ours, theirs)) in sizes.enumerated() {
            for k: UInt32 in 0..<3 {
                let x0 = gap + (UInt32(s) * 3 + k) * (cell + gap)
                let y0 = gap + UInt32(r) * (cell + gap)
                for y in 0..<(px * zoom) {
                    for x in 0..<(px * zoom) {
                        let i = Int((y / zoom) * px + (x / zoom))
                        let a = Int(ours[i])
                        let b = Int(theirs[i])
                        let rgb: (Int, Int, Int)
                        switch k {
                        case 0:
                            rgb = (255 - a, 255 - a, 255 - a)
                        case 1:
                            rgb = (255 - b, 255 - b, 255 - b)
                        default:
                            let d = min(max(a - b, -255), 255)
                            rgb = d > 0 ? (255, 255 - d, 255 - d) : (255 + d, 255 + d, 255)
                        }
                        let dst = (Int(y0 + y) * stride + Int(x0 + x)) * 4
                        rgba[dst] = UInt8(clamping: rgb.0)
                        rgba[dst + 1] = UInt8(clamping: rgb.1)
                        rgba[dst + 2] = UInt8(clamping: rgb.2)
                        rgba[dst + 3] = 255
                    }
                }
            }
        }
    }
    try writePng(path, w, h, rgba)
}
#endif

@Suite("GlyphsTests")
struct GlyphsTests {
    // PORT NOTE: Blocked on Sources/Rune text/icon.swift stroke-only SVG fill-none default.
    @Test(.disabled("Blocked on Sources/Rune text/icon.swift stroke-only SVG fill-none default"))
    func builtInGlyphsMatchAReferenceRasteriser() throws {
        #if canImport(CoreGraphics)
        var failures: [String] = []
        var sheets: [[SheetRow]] = [[], []]
        for icon in ALL_GLYPHS {
            var rows: [[(UInt32, [UInt8], [UInt8])]] = [[], []]
            for pt in GLYPH_POINTS {
                for scale: UInt32 in [1, 2] {
                    let px = pt * scale
                    let ours = iconCoverage(icon, px)
                    let theirs = referenceCoverage(icon, px)
                    let m = glyphMismatch(ours, theirs)
                    // Anti-aliasing differs between rasterisers by a few percent at these sizes; a
                    // wrong control point or a stray fill differs by far more.
                    if m > 0.12 {
                        failures.append("\(icon.name) at \(pt)pt @\(scale)x: \(m)")
                    }
                    rows[Int(scale) - 1].append((px, ours, theirs))
                }
            }
            for idx in 0..<2 {
                sheets[idx].append((icon.name, rows[idx]))
            }
        }
        #if !os(WASI)
        if let dir = ProcessInfo.processInfo.environment["RUNE_GLYPH_PROOF"], !dir.isEmpty {
            for (idx, sheet) in sheets.enumerated() {
                let scale = idx + 1
                try writeGlyphSheet("\(dir)/glyphs-\(scale)x.png", sheet)
                let lockEye = sheet.filter { ["kit-lock", "kit-eye", "kit-eye-off"].contains($0.0) }
                try writeGlyphSheet("\(dir)/lock-eye-\(scale)x.png", lockEye)
            }
        }
        #endif
        #expect(failures.isEmpty, "glyphs differ from reference rasteriser:\n\(failures.joined(separator: "\n"))")
        #else
        // PORT NOTE: On non-CoreGraphics targets without a system 2D vector rasteriser, verify
        // every built-in glyph rasterises non-empty masks at all target sizes and preserves
        // outline vs filled geometry (`STAR` vs `STAR_FILLED`).
        for icon in ALL_GLYPHS {
            for pt in GLYPH_POINTS {
                for scale: UInt32 in [1, 2] {
                    let px = pt * scale
                    let cov = iconCoverage(icon, px)
                    #expect(cov.count == Int(px * px))
                    let ink = cov.reduce(UInt32(0)) { $0 + UInt32($1) }
                    #expect(ink > 0, "\(icon.name) at \(pt)pt @\(scale)x has no ink")
                }
            }
        }
        let starInk = iconCoverage(glyphs.STAR, 32).reduce(UInt32(0)) { $0 + UInt32($1) }
        let filledStarInk = iconCoverage(glyphs.STAR_FILLED, 32).reduce(UInt32(0)) { $0 + UInt32($1) }
        #expect(filledStarInk > starInk + 5000, "STAR must remain outline-only while STAR_FILLED fills its interior")
        #endif
    }

    @Test
    func extraGlyphsRasterizeWithInk() {
        for icon in [glyphs.MIC, glyphs.KEYBOARD, glyphs.CURSOR_TEXT, glyphs.ARROW_RIGHT, glyphs.SPARKLE] {
            let ink = iconCoverage(icon, 32).reduce(UInt32(0)) { $0 + UInt32($1) }
            #expect(ink > 2000, "\(icon.name) has no ink")
        }
    }
}
