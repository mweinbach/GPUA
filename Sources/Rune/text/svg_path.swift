// Ported from: crates/rune/src/text/svg_path.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! SVG 2 path data (`M/L/H/V/C/S/Q/T/A/Z`, absolute and relative) into vector path commands.
//! Elliptical arcs follow SVG 2 section 9.5.1 / section B.2 and become at most four cubics.

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

struct VectorPoint: Sendable, Equatable {
    var x: Float
    var y: Float

    init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }
}

enum PathCommand: Sendable, Equatable {
    case moveTo(VectorPoint)
    case lineTo(VectorPoint)
    case quadTo(VectorPoint, VectorPoint)
    case curveTo(VectorPoint, VectorPoint, VectorPoint)
    case close
}

struct SvgPathError: Error, Sendable, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}

func parseSvgPath(_ d: String) -> Result<[PathCommand], SvgPathError> {
    var cur = SvgPathCursor(Array(d.utf8))
    var out: [PathCommand] = []
    var at = VectorPoint(0, 0)
    var subpath = VectorPoint(0, 0)
    var cubic: VectorPoint? = nil
    var quad: VectorPoint? = nil

    let fail: (String) -> Result<[PathCommand], SvgPathError> = { msg in
        out.isEmpty ? .failure(SvgPathError(msg)) : .success(out)
    }

    while let cmd = cur.command() {
        let rel = cmd >= UInt8(ascii: "a") && cmd <= UInt8(ascii: "z")
        let kind = rel ? (cmd - 32) : cmd
        if kind != UInt8(ascii: "M") && out.isEmpty {
            return .failure(SvgPathError("SVG path must start with moveto"))
        }
        var first = true
        commandArgs: while true {
            if !first && cur.end() {
                break commandArgs
            }
            let isFirst = first
            first = false
            let base = rel ? at : VectorPoint(0, 0)

            func readPt() -> VectorPoint? {
                guard let x = cur.number(), let y = cur.number() else { return nil }
                return VectorPoint(base.x + x, base.y + y)
            }

            switch kind {
            case UInt8(ascii: "Z"):
                out.append(.close)
                at = subpath
                cubic = nil
                quad = nil
                break commandArgs

            case UInt8(ascii: "M"):
                guard let p = readPt() else { return fail("expected number") }
                if isFirst {
                    subpath = p
                    out.append(.moveTo(p))
                } else {
                    out.append(.lineTo(p))
                }
                at = p
                cubic = nil
                quad = nil

            case UInt8(ascii: "L"):
                guard let p = readPt() else { return fail("expected number") }
                out.append(.lineTo(p))
                at = p
                cubic = nil
                quad = nil

            case UInt8(ascii: "H"):
                guard let x = cur.number() else { return fail("expected number") }
                let p = VectorPoint(base.x + x, at.y)
                out.append(.lineTo(p))
                at = p
                cubic = nil
                quad = nil

            case UInt8(ascii: "V"):
                guard let y = cur.number() else { return fail("expected number") }
                let p = VectorPoint(at.x, base.y + y)
                out.append(.lineTo(p))
                at = p
                cubic = nil
                quad = nil

            case UInt8(ascii: "C"):
                guard let c1 = readPt(), let c2 = readPt(), let p = readPt() else {
                    return fail("expected number")
                }
                out.append(.curveTo(c1, c2, p))
                cubic = c2
                quad = nil
                at = p

            case UInt8(ascii: "S"):
                let c1: VectorPoint
                if let prev = cubic {
                    c1 = VectorPoint(2.0 * at.x - prev.x, 2.0 * at.y - prev.y)
                } else {
                    c1 = at
                }
                guard let c2 = readPt(), let p = readPt() else {
                    return fail("expected number")
                }
                out.append(.curveTo(c1, c2, p))
                cubic = c2
                quad = nil
                at = p

            case UInt8(ascii: "Q"):
                guard let c = readPt(), let p = readPt() else {
                    return fail("expected number")
                }
                out.append(.quadTo(c, p))
                quad = c
                cubic = nil
                at = p

            case UInt8(ascii: "T"):
                let c: VectorPoint
                if let prev = quad {
                    c = VectorPoint(2.0 * at.x - prev.x, 2.0 * at.y - prev.y)
                } else {
                    c = at
                }
                guard let p = readPt() else {
                    return fail("expected number")
                }
                out.append(.quadTo(c, p))
                quad = c
                cubic = nil
                at = p

            case UInt8(ascii: "A"):
                guard let rx = cur.number(),
                      let ry = cur.number(),
                      let rot = cur.number(),
                      let large = cur.flag(),
                      let sweep = cur.flag(),
                      let p = readPt()
                else {
                    return fail("expected arc arguments")
                }
                emitSvgArc(from: at, rxIn: rx, ryIn: ry, degrees: rot, large: large, sweep: sweep, to: p, out: &out)
                at = p
                cubic = nil
                quad = nil

            default:
                return fail("unknown SVG path command '\( Character(UnicodeScalar(cmd)) )'")
            }
        }
    }
    return .success(out)
}

private func emitSvgArc(
    from: VectorPoint,
    rxIn: Float,
    ryIn: Float,
    degrees: Float,
    large: Bool,
    sweep: Bool,
    to: VectorPoint,
    out: inout [PathCommand]
) {
    if from == to {
        return
    }
    var rx = abs(Double(rxIn))
    var ry = abs(Double(ryIn))
    if rx == 0.0 || ry == 0.0 {
        out.append(.lineTo(to))
        return
    }
    let phi = Double(degrees) * (.pi / 180.0)
    let sinPhi = sin(phi)
    let cosPhi = cos(phi)
    let dx = (Double(from.x) - Double(to.x)) * 0.5
    let dy = (Double(from.y) - Double(to.y)) * 0.5
    let x1p = cosPhi * dx + sinPhi * dy
    let y1p = -sinPhi * dx + cosPhi * dy

    let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lambda > 1.0 {
        let s = lambda.squareRoot()
        rx *= s
        ry *= s
    }
    let rx2 = rx * rx
    let ry2 = ry * ry
    let x1p2 = x1p * x1p
    let y1p2 = y1p * y1p
    let denom = rx2 * y1p2 + ry2 * x1p2
    let numer = max(rx2 * ry2 - denom, 0.0)
    let sign: Double = (large == sweep) ? -1.0 : 1.0
    let k = sign * (denom > 0.0 ? (numer / denom).squareRoot() : 0.0)
    let cxp = k * rx * y1p / ry
    let cyp = -k * ry * x1p / rx
    let cx = cosPhi * cxp - sinPhi * cyp + (Double(from.x) + Double(to.x)) * 0.5
    let cy = sinPhi * cxp + cosPhi * cyp + (Double(from.y) + Double(to.y)) * 0.5

    func angle(_ u: (Double, Double), _ v: (Double, Double)) -> Double {
        let dot = u.0 * v.0 + u.1 * v.1
        let len = ((u.0 * u.0 + u.1 * u.1) * (v.0 * v.0 + v.1 * v.1)).squareRoot()
        let c = len > 0.0 ? min(max(dot / len, -1.0), 1.0) : 1.0
        let a = acos(c)
        return (u.0 * v.1 - u.1 * v.0 < 0.0) ? -a : a
    }

    let u = ((x1p - cxp) / rx, (y1p - cyp) / ry)
    let v = ((-x1p - cxp) / rx, (-y1p - cyp) / ry)
    let theta1 = angle((1.0, 0.0), u)
    var dtheta = angle(u, v)
    if !sweep && dtheta > 0.0 {
        dtheta -= 2.0 * .pi
    }
    if sweep && dtheta < 0.0 {
        dtheta += 2.0 * .pi
    }

    let n = max(Int((abs(dtheta) / (.pi * 0.5)).rounded(.up)), 1)
    let step = dtheta / Double(n)
    let mapPt = { (x: Double, y: Double) -> VectorPoint in
        VectorPoint(
            Float(cosPhi * rx * x - sinPhi * ry * y + cx),
            Float(sinPhi * rx * x + cosPhi * ry * y + cy)
        )
    }
    for i in 0..<n {
        let a0 = theta1 + Double(i) * step
        let a1 = a0 + step
        let (c1, c2, p) = cubicUnitArc(a0, a1)
        let endPt = (i + 1 == n) ? to : mapPt(p.0, p.1)
        out.append(.curveTo(mapPt(c1.0, c1.1), mapPt(c2.0, c2.1), endPt))
    }
}

private func cubicUnitArc(_ a0: Double, _ a1: Double) -> ((Double, Double), (Double, Double), (Double, Double)) {
    let alpha = (4.0 / 3.0) * tan((a1 - a0) * 0.25)
    let s0 = sin(a0), c0 = cos(a0)
    let s1 = sin(a1), c1 = cos(a1)
    return (
        (c0 - alpha * s0, s0 + alpha * c0),
        (c1 + alpha * s1, s1 - alpha * c1),
        (c1, s1)
    )
}

private extension UInt8 {
    var isAsciiLowercase: Bool { self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z") }
    var asciiUppercased: UInt8 { isAsciiLowercase ? (self - 32) : self }
    var isAsciiAlphabetic: Bool {
        (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")) ||
        (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z"))
    }
    var isAsciiDigit: Bool { self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9") }
}

private struct SvgPathCursor {
    let s: [UInt8]
    var i: Int = 0

    init(_ s: [UInt8]) {
        self.s = s
    }

    mutating func skip() {
        while i < s.count {
            let b = s[i]
            if b == UInt8(ascii: ",") || b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") ||
               b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") || b == 0x0C {
                i += 1
            } else {
                break
            }
        }
    }

    mutating func command() -> UInt8? {
        skip()
        guard i < s.count, s[i].isAsciiAlphabetic else { return nil }
        let b = s[i]
        i += 1
        return b
    }

    mutating func end() -> Bool {
        skip()
        return i >= s.count || s[i].isAsciiAlphabetic
    }

    mutating func number() -> Float? {
        skip()
        let start = i
        if i < s.count && (s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-")) {
            i += 1
        }
        var digits = false
        while i < s.count && s[i].isAsciiDigit {
            i += 1
            digits = true
        }
        if i < s.count && s[i] == UInt8(ascii: ".") {
            i += 1
            while i < s.count && s[i].isAsciiDigit {
                i += 1
                digits = true
            }
        }
        guard digits else { return nil }
        if i < s.count && (s[i] == UInt8(ascii: "e") || s[i] == UInt8(ascii: "E")) {
            let save = i
            i += 1
            if i < s.count && (s[i] == UInt8(ascii: "+") || s[i] == UInt8(ascii: "-")) {
                i += 1
            }
            let expStart = i
            while i < s.count && s[i].isAsciiDigit {
                i += 1
            }
            if i == expStart {
                i = save
            }
        }
        let str = String(decoding: s[start..<i], as: UTF8.self)
        guard let v = Float(str), v.isFinite else { return nil }
        return v
    }

    mutating func flag() -> Bool? {
        skip()
        guard i < s.count else { return nil }
        let b = s[i]
        if b == UInt8(ascii: "0") {
            i += 1
            return false
        } else if b == UInt8(ascii: "1") {
            i += 1
            return true
        }
        return nil
    }
}
