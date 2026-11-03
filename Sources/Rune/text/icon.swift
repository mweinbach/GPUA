// Ported from: crates/rune/src/text/icon.rs
// Upstream commit: 5f6d53ddae78
// Port status: ported

//! Icons: a subset of SVG (path, rect, circle, ellipse, line; fill/stroke, caps, joins, evenodd,
//! and `opacity`, `fill-opacity`, `stroke-opacity` on each element) rasterized with a pure-Swift
//! analytic scanline coverage mask.

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

/// An SVG icon body as found in `@opencode/ui`'s catalog: elements inside a square viewBox.
public struct Icon: Sendable, Equatable, Hashable {
    public var name: String
    public var view: Float
    public var body: String

    public init(name: String, view: Float, body: String) {
        self.name = name
        self.view = view
        self.body = body
    }
}

/// Rasterize `icon` into a `px * px` single-channel coverage buffer without touching an atlas.
public func iconCoverage(_ icon: Icon, _ px: UInt32) -> [UInt8] {
    guard px > 0, icon.view > 0.0 else { return [] }
    var out = [UInt8](repeating: 0, count: Int(px * px))
    let scale = Float(px) / icon.view
    for (tag, attrs) in svgElements(icon.body) {
        let commands = elementPath(tag, attrs)
        if commands.isEmpty { continue }
        let elementAlpha = attrOpacity(attrs, "opacity")
        let fillNone = attr(attrs, "fill") == "none"
        let fillAlpha = elementAlpha * attrOpacity(attrs, "fill-opacity")
        if !fillNone && fillAlpha > 0.0 {
            let evenOdd = attr(attrs, "fill-rule") == "evenodd"
            let scratch = ScanlineMask.renderTopLeft(
                commands: commands,
                scale: Double(scale),
                width: Int(px),
                height: Int(px),
                fillRule: evenOdd ? .evenOdd : .nonZero
            )
            blendCoverage(&out, scratch, fillAlpha)
        }
        let strokeAlpha = elementAlpha * attrOpacity(attrs, "stroke-opacity")
        if let strokeVal = attr(attrs, "stroke"), strokeVal != "none", strokeAlpha > 0.0 {
            let s = parseStrokeSpec(attrs)
            if s.width > 0.0 {
                let stroked = expandStroke(commands: commands, scale: Double(scale), stroke: s)
                let scratch = ScanlineMask.renderTopLeftPolygons(
                    polygons: stroked,
                    width: Int(px),
                    height: Int(px),
                    positiveUnion: true
                )
                blendCoverage(&out, scratch, strokeAlpha)
            }
        }
    }
    return out
}

func rasterizeIcon(_ icon: Icon, _ px: UInt32, _ atlas: inout Atlas) -> PlacedMask {
    if px == 0 || icon.view <= 0.0 {
        return .empty
    }
    if px + 4 > ATLAS_SIZE {
        return .unplaced
    }
    let cov = iconCoverage(icon, px)
    if !cov.contains(where: { $0 != 0 }) {
        return .empty
    }
    // Pad by one transparent texel on every side so sub-pixel, scaled and turned quads can
    // expand by a texel and filter out to zero without clipping or sampling a neighbour.
    let stride = Int(px + 2)
    var padded = [UInt8](repeating: 0, count: stride * stride)
    let w = Int(px)
    for row in 0..<w {
        let srcBase = row * w
        let dstBase = (row + 1) * stride + 1
        for col in 0..<w {
            padded[dstBase + col] = cov[srcBase + col]
        }
    }
    if let g = atlas.put(px + 2, px + 2, padded, 0, 0) {
        return .placed(g)
    }
    return .unplaced
}

private func blendCoverage(_ dst: inout [UInt8], _ src: [UInt8], _ opacity: Float) {
    for i in 0..<min(dst.count, src.count) {
        let sa = (Float(src[i]) / 255.0) * opacity
        if sa <= 0.0 { continue }
        let da = Float(dst[i]) / 255.0
        dst[i] = UInt8(clamping: Int(((sa + da * (1.0 - sa)) * 255.0).rounded()))
    }
}

private enum SvgLineCap {
    case butt
    case round
    case square
}

private enum SvgLineJoin {
    case miter
    case round
    case bevel
}

private struct SvgStrokeSpec {
    var width: Float
    var cap: SvgLineCap
    var join: SvgLineJoin
}

private func parseStrokeSpec(_ attrs: String) -> SvgStrokeSpec {
    let width = attrF32(attrs, "stroke-width") ?? 1.0
    let cap: SvgLineCap
    switch attr(attrs, "stroke-linecap") {
    case "round": cap = .round
    case "square": cap = .square
    default: cap = .butt
    }
    let join: SvgLineJoin
    switch attr(attrs, "stroke-linejoin") {
    case "round": join = .round
    case "bevel": join = .bevel
    default: join = .miter
    }
    return SvgStrokeSpec(width: width, cap: cap, join: join)
}

private func elementPath(_ tag: Substring, _ attrs: String) -> [PathCommand] {
    switch tag {
    case "path":
        guard let d = attr(attrs, "d") else { return [] }
        switch parseSvgPath(d) {
        case .success(let cmds): return cmds
        case .failure: return []
        }
    case "rect":
        let x = attrF32(attrs, "x") ?? 0.0
        let y = attrF32(attrs, "y") ?? 0.0
        let w = attrF32(attrs, "width") ?? 0.0
        let h = attrF32(attrs, "height") ?? 0.0
        if w <= 0.0 || h <= 0.0 { return [] }
        let r = min(max(attrF32(attrs, "rx") ?? 0.0, 0.0), min(w * 0.5, h * 0.5))
        var p: [PathCommand] = []
        if r == 0.0 {
            p.append(.moveTo(VectorPoint(x, y)))
            p.append(.lineTo(VectorPoint(x + w, y)))
            p.append(.lineTo(VectorPoint(x + w, y + h)))
            p.append(.lineTo(VectorPoint(x, y + h)))
            p.append(.close)
        } else {
            let k: Float = 0.5522848 * r
            p.append(.moveTo(VectorPoint(x + r, y)))
            p.append(.lineTo(VectorPoint(x + w - r, y)))
            p.append(.curveTo(VectorPoint(x + w - r + k, y), VectorPoint(x + w, y + r - k), VectorPoint(x + w, y + r)))
            p.append(.lineTo(VectorPoint(x + w, y + h - r)))
            p.append(.curveTo(VectorPoint(x + w, y + h - r + k), VectorPoint(x + w - r + k, y + h), VectorPoint(x + w - r, y + h)))
            p.append(.lineTo(VectorPoint(x + r, y + h)))
            p.append(.curveTo(VectorPoint(x + r - k, y + h), VectorPoint(x, y + h - r + k), VectorPoint(x, y + h - r)))
            p.append(.lineTo(VectorPoint(x, y + r)))
            p.append(.curveTo(VectorPoint(x, y + r - k), VectorPoint(x + r - k, y), VectorPoint(x + r, y)))
            p.append(.close)
        }
        return p
    case "circle":
        let cx = attrF32(attrs, "cx") ?? 0.0
        let cy = attrF32(attrs, "cy") ?? 0.0
        let r = attrF32(attrs, "r") ?? 0.0
        return ellipseCommands(cx, cy, r, r)
    case "ellipse":
        let cx = attrF32(attrs, "cx") ?? 0.0
        let cy = attrF32(attrs, "cy") ?? 0.0
        let rx = attrF32(attrs, "rx") ?? 0.0
        let ry = attrF32(attrs, "ry") ?? 0.0
        return ellipseCommands(cx, cy, rx, ry)
    case "line":
        let x1 = attrF32(attrs, "x1") ?? 0.0
        let y1 = attrF32(attrs, "y1") ?? 0.0
        let x2 = attrF32(attrs, "x2") ?? 0.0
        let y2 = attrF32(attrs, "y2") ?? 0.0
        return [.moveTo(VectorPoint(x1, y1)), .lineTo(VectorPoint(x2, y2))]
    default:
        return []
    }
}

private func ellipseCommands(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float) -> [PathCommand] {
    if rx <= 0.0 || ry <= 0.0 { return [] }
    let kx = 0.5522848 * rx
    let ky = 0.5522848 * ry
    return [
        .moveTo(VectorPoint(cx + rx, cy)),
        .curveTo(VectorPoint(cx + rx, cy + ky), VectorPoint(cx + kx, cy + ry), VectorPoint(cx, cy + ry)),
        .curveTo(VectorPoint(cx - kx, cy + ry), VectorPoint(cx - rx, cy + ky), VectorPoint(cx - rx, cy)),
        .curveTo(VectorPoint(cx - rx, cy - ky), VectorPoint(cx - kx, cy - ry), VectorPoint(cx, cy - ry)),
        .curveTo(VectorPoint(cx + kx, cy - ry), VectorPoint(cx + rx, cy - ky), VectorPoint(cx + rx, cy)),
        .close,
    ]
}

private func svgElements(_ s: String) -> [(Substring, String)] {
    var out: [(Substring, String)] = []
    var rest = s[...]
    while let openIdx = rest.firstIndex(of: "<") {
        rest = rest[rest.index(after: openIdx)...]
        guard let closeIdx = rest.firstIndex(of: ">") else { break }
        var inside = rest[..<closeIdx]
        rest = rest[rest.index(after: closeIdx)...]
        while let f = inside.first, f.isWhitespace { inside = inside.dropFirst() }
        while let l = inside.last, l.isWhitespace || l == "/" { inside = inside.dropLast() }
        guard let firstChar = inside.first, firstChar != "/", firstChar != "!", firstChar != "?" else {
            continue
        }
        let splitIdx = inside.firstIndex(where: { $0.isWhitespace }) ?? inside.endIndex
        let tag = inside[..<splitIdx]
        let attrs = String(inside[splitIdx...])
        out.append((tag, attrs))
    }
    return out
}

private func attr(_ attrs: String, _ name: String) -> String? {
    let bytes = Array(attrs.utf8)
    let needle = Array(name.utf8)
    let n = bytes.count
    let m = needle.count
    guard m > 0, n >= m else { return nil }
    var i = 0
    while i + m <= n {
        var match = true
        for k in 0..<m {
            if bytes[i + k] != needle[k] {
                match = false
                break
            }
        }
        if match {
            let boundaryOk: Bool
            if i == 0 {
                boundaryOk = true
            } else {
                let prev = bytes[i - 1]
                boundaryOk = prev == UInt8(ascii: " ") || prev == UInt8(ascii: "\t") ||
                             prev == UInt8(ascii: "\n") || prev == UInt8(ascii: "\r") ||
                             prev == UInt8(ascii: "\"") || prev == UInt8(ascii: "'")
            }
            if boundaryOk {
                var j = i + m
                while j < n && (bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t") || bytes[j] == UInt8(ascii: "\n") || bytes[j] == UInt8(ascii: "\r")) {
                    j += 1
                }
                if j < n && bytes[j] == UInt8(ascii: "=") {
                    j += 1
                    while j < n && (bytes[j] == UInt8(ascii: " ") || bytes[j] == UInt8(ascii: "\t") || bytes[j] == UInt8(ascii: "\n") || bytes[j] == UInt8(ascii: "\r")) {
                        j += 1
                    }
                    if j < n && (bytes[j] == UInt8(ascii: "\"") || bytes[j] == UInt8(ascii: "'")) {
                        let quote = bytes[j]
                        j += 1
                        let valStart = j
                        while j < n && bytes[j] != quote {
                            j += 1
                        }
                        if j < n {
                            return String(decoding: bytes[valStart..<j], as: UTF8.self)
                        }
                    }
                }
            }
        }
        i += 1
    }
    return nil
}

private func attrF32(_ attrs: String, _ name: String) -> Float? {
    guard let s = attr(attrs, name) else { return nil }
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let stripped = trimmed.hasSuffix("px") ? String(trimmed.dropLast(2)) : trimmed
    return Float(stripped)
}

private func attrOpacity(_ attrs: String, _ name: String) -> Float {
    guard let v = attrF32(attrs, name), v.isFinite else { return 1.0 }
    return min(max(v, 0.0), 1.0)
}

// MARK: - Stroke Expansion

private func expandStroke(commands: [PathCommand], scale: Double, stroke: SvgStrokeSpec) -> [[(Double, Double)]] {
    let halfW = Double(stroke.width) * 0.5 * scale
    guard halfW > 0.0 else { return [] }

    struct Subpath {
        var pts: [(Double, Double)]
        var closed: Bool
    }

    var subpaths: [Subpath] = []
    var current: [(Double, Double)] = []
    var startPt: (Double, Double) = (0, 0)
    var pen: (Double, Double) = (0, 0)

    func appendPt(_ p: (Double, Double)) {
        if let last = current.last {
            let dx = p.0 - last.0
            let dy = p.1 - last.1
            if dx * dx + dy * dy < 1e-10 { return }
        }
        current.append(p)
    }

    for cmd in commands {
        switch cmd {
        case .moveTo(let p):
            if !current.isEmpty {
                subpaths.append(Subpath(pts: current, closed: false))
                current.removeAll(keepingCapacity: true)
            }
            let sp = (Double(p.x) * scale, Double(p.y) * scale)
            startPt = sp
            pen = sp
            current.append(sp)
        case .lineTo(let p):
            let sp = (Double(p.x) * scale, Double(p.y) * scale)
            appendPt(sp)
            pen = sp
        case .quadTo(let c, let p):
            let sc = (Double(c.x) * scale, Double(c.y) * scale)
            let sp = (Double(p.x) * scale, Double(p.y) * scale)
            flattenQuadTo(pen, sc, sp, tol2: 0.0004, depth: 0, emit: appendPt)
            pen = sp
        case .curveTo(let c1, let c2, let p):
            let sc1 = (Double(c1.x) * scale, Double(c1.y) * scale)
            let sc2 = (Double(c2.x) * scale, Double(c2.y) * scale)
            let sp = (Double(p.x) * scale, Double(p.y) * scale)
            flattenCubicTo(pen, sc1, sc2, sp, tol2: 0.0004, depth: 0, emit: appendPt)
            pen = sp
        case .close:
            if !current.isEmpty {
                subpaths.append(Subpath(pts: current, closed: true))
                current.removeAll(keepingCapacity: true)
            }
            pen = startPt
        }
    }
    if !current.isEmpty {
        subpaths.append(Subpath(pts: current, closed: false))
    }

    var polys: [[(Double, Double)]] = []

    func emitPositive(_ raw: [(Double, Double)]) {
        guard raw.count >= 3 else { return }
        var area2 = 0.0
        for i in 0..<raw.count {
            let a = raw[i]
            let b = raw[(i + 1) % raw.count]
            area2 += a.0 * b.1 - b.0 * a.1
        }
        if abs(area2) < 1e-12 { return }
        if area2 < 0.0 {
            polys.append(raw)
        } else {
            polys.append(raw.reversed())
        }
    }

    func emitArcFan(center: (Double, Double), from n0: (Double, Double), to n1: (Double, Double), radius: Double) {
        let a0 = atan2(n0.1, n0.0)
        var da = atan2(n1.1, n1.0) - a0
        while da <= -.pi { da += 2.0 * .pi }
        while da > .pi { da -= 2.0 * .pi }
        if abs(da) < 1e-6 { return }
        let stepAngle = max(0.08, 2.0 * acos(max(0.0, 1.0 - 0.02 / max(radius, 0.05))))
        let steps = max(2, Int((abs(da) / stepAngle).rounded(.up)))
        var fan: [(Double, Double)] = [center]
        fan.reserveCapacity(steps + 2)
        for k in 0...steps {
            let ang = a0 + da * (Double(k) / Double(steps))
            fan.append((center.0 + cos(ang) * radius, center.1 + sin(ang) * radius))
        }
        emitPositive(fan)
    }

    func emitHalfDisk(center: (Double, Double), dir: (Double, Double), normal: (Double, Double), radius: Double) {
        let aStart = atan2(-normal.1, -normal.0)
        let aMid = atan2(dir.1, dir.0)
        var sweep = aMid - aStart
        while sweep <= -.pi { sweep += 2.0 * .pi }
        while sweep > .pi { sweep -= 2.0 * .pi }
        let total = sweep * 2.0
        let stepAngle = max(0.08, 2.0 * acos(max(0.0, 1.0 - 0.02 / max(radius, 0.05))))
        let steps = max(4, Int((abs(total) / stepAngle).rounded(.up)))
        var fan: [(Double, Double)] = [center]
        fan.reserveCapacity(steps + 2)
        for k in 0...steps {
            let ang = aStart + total * (Double(k) / Double(steps))
            fan.append((center.0 + cos(ang) * radius, center.1 + sin(ang) * radius))
        }
        emitPositive(fan)
    }

    for sub in subpaths {
        var pts = sub.pts
        if sub.closed && pts.count >= 2 {
            let dx = pts.last!.0 - pts.first!.0
            let dy = pts.last!.1 - pts.first!.1
            if dx * dx + dy * dy < 1e-10 {
                pts.removeLast()
            }
        }
        if pts.count < 2 {
            if let p = pts.first {
                switch stroke.cap {
                case .round:
                    let steps = max(12, Int((2.0 * .pi / 0.15).rounded(.up)))
                    var disk: [(Double, Double)] = []
                    for k in 0..<steps {
                        let ang = 2.0 * .pi * Double(k) / Double(steps)
                        disk.append((p.0 + cos(ang) * halfW, p.1 + sin(ang) * halfW))
                    }
                    emitPositive(disk)
                case .square:
                    emitPositive([
                        (p.0 - halfW, p.1 - halfW),
                        (p.0 - halfW, p.1 + halfW),
                        (p.0 + halfW, p.1 + halfW),
                        (p.0 + halfW, p.1 - halfW),
                    ])
                case .butt:
                    break
                }
            }
            continue
        }

        struct Seg {
            var a: (Double, Double)
            var b: (Double, Double)
            var t: (Double, Double)
            var n: (Double, Double)
        }

        var segs: [Seg] = []
        let segCount = sub.closed ? pts.count : (pts.count - 1)
        segs.reserveCapacity(segCount)
        for i in 0..<segCount {
            let a = pts[i]
            let b = pts[(i + 1) % pts.count]
            let dx = b.0 - a.0
            let dy = b.1 - a.1
            let len = (dx * dx + dy * dy).squareRoot()
            if len < 1e-9 { continue }
            let t = (dx / len, dy / len)
            let n = (-t.1, t.0)
            segs.append(Seg(a: a, b: b, t: t, n: n))
        }
        guard !segs.isEmpty else { continue }

        // Segment quads
        for s in segs {
            emitPositive([
                (s.a.0 - s.n.0 * halfW, s.a.1 - s.n.1 * halfW),
                (s.a.0 + s.n.0 * halfW, s.a.1 + s.n.1 * halfW),
                (s.b.0 + s.n.0 * halfW, s.b.1 + s.n.1 * halfW),
                (s.b.0 - s.n.0 * halfW, s.b.1 - s.n.1 * halfW),
            ])
        }

        // Joins
        let joinCount = sub.closed ? segs.count : (segs.count - 1)
        for i in 0..<joinCount {
            let s0 = segs[i]
            let s1 = segs[(i + 1) % segs.count]
            let p = s0.b
            let cross = s0.t.0 * s1.t.1 - s0.t.1 * s1.t.0
            if abs(cross) < 1e-8 && (s0.t.0 * s1.t.0 + s0.t.1 * s1.t.1) > 0.0 {
                continue
            }
            let out0: (Double, Double)
            let out1: (Double, Double)
            if cross >= 0.0 {
                out0 = (-s0.n.0, -s0.n.1)
                out1 = (-s1.n.0, -s1.n.1)
            } else {
                out0 = s0.n
                out1 = s1.n
            }
            let p0 = (p.0 + out0.0 * halfW, p.1 + out0.1 * halfW)
            let p1 = (p.0 + out1.0 * halfW, p.1 + out1.1 * halfW)

            switch stroke.join {
            case .bevel:
                emitPositive([p, p0, p1])
            case .round:
                if cross * cross < 1e-12 && (s0.t.0 * s1.t.0 + s0.t.1 * s1.t.1) < 0.0 {
                    emitHalfDisk(center: p, dir: s0.t, normal: s0.n, radius: halfW)
                } else {
                    emitArcFan(center: p, from: out0, to: out1, radius: halfW)
                }
            case .miter:
                let denom = 1.0 + (out0.0 * out1.0 + out0.1 * out1.1)
                // SVG default stroke-miterlimit = 4.0 -> 2 / (4^2) = 0.125
                if denom >= 0.125 {
                    let scaleM = halfW / denom
                    let m = (p.0 + (out0.0 + out1.0) * scaleM, p.1 + (out0.1 + out1.1) * scaleM)
                    emitPositive([p, p0, m, p1])
                } else {
                    emitPositive([p, p0, p1])
                }
            }
        }

        // Caps on open subpaths
        if !sub.closed {
            let first = segs.first!
            let last = segs.last!
            switch stroke.cap {
            case .butt:
                break
            case .square:
                let sa = first.a
                let back = (-first.t.0 * halfW, -first.t.1 * halfW)
                emitPositive([
                    (sa.0 - first.n.0 * halfW, sa.1 - first.n.1 * halfW),
                    (sa.0 + first.n.0 * halfW, sa.1 + first.n.1 * halfW),
                    (sa.0 + first.n.0 * halfW + back.0, sa.1 + first.n.1 * halfW + back.1),
                    (sa.0 - first.n.0 * halfW + back.0, sa.1 - first.n.1 * halfW + back.1),
                ])
                let eb = last.b
                let fwd = (last.t.0 * halfW, last.t.1 * halfW)
                emitPositive([
                    (eb.0 - last.n.0 * halfW, eb.1 - last.n.1 * halfW),
                    (eb.0 + last.n.0 * halfW, eb.1 + last.n.1 * halfW),
                    (eb.0 + last.n.0 * halfW + fwd.0, eb.1 + last.n.1 * halfW + fwd.1),
                    (eb.0 - last.n.0 * halfW + fwd.0, eb.1 - last.n.1 * halfW + fwd.1),
                ])
            case .round:
                emitHalfDisk(
                    center: first.a,
                    dir: (-first.t.0, -first.t.1),
                    normal: (-first.n.0, -first.n.1),
                    radius: halfW
                )
                emitHalfDisk(
                    center: last.b,
                    dir: last.t,
                    normal: last.n,
                    radius: halfW
                )
            }
        }
    }

    return polys
}

// MARK: - Shared Analytic Scanline Rasterizer

enum ScanlineFillRule: Sendable, Equatable {
    case nonZero
    case evenOdd
}

func flattenQuadTo(
    _ p0: (Double, Double),
    _ c: (Double, Double),
    _ p1: (Double, Double),
    tol2: Double,
    depth: Int,
    emit: ((Double, Double)) -> Void
) {
    let dx = c.0 - 0.5 * (p0.0 + p1.0)
    let dy = c.1 - 0.5 * (p0.1 + p1.1)
    if dx * dx + dy * dy <= tol2 || depth >= 16 {
        emit(p1)
        return
    }
    let q0 = (0.5 * (p0.0 + c.0), 0.5 * (p0.1 + c.1))
    let q1 = (0.5 * (c.0 + p1.0), 0.5 * (c.1 + p1.1))
    let m = (0.5 * (q0.0 + q1.0), 0.5 * (q0.1 + q1.1))
    flattenQuadTo(p0, q0, m, tol2: tol2, depth: depth + 1, emit: emit)
    flattenQuadTo(m, q1, p1, tol2: tol2, depth: depth + 1, emit: emit)
}

func flattenCubicTo(
    _ p0: (Double, Double),
    _ c1: (Double, Double),
    _ c2: (Double, Double),
    _ p1: (Double, Double),
    tol2: Double,
    depth: Int,
    emit: ((Double, Double)) -> Void
) {
    let ux = 3.0 * c1.0 - 2.0 * p0.0 - p1.0
    let uy = 3.0 * c1.1 - 2.0 * p0.1 - p1.1
    let vx = 3.0 * c2.0 - p0.0 - 2.0 * p1.0
    let vy = 3.0 * c2.1 - p0.1 - 2.0 * p1.1
    let err2 = max(ux * ux, vx * vx) + max(uy * uy, vy * vy)
    if err2 <= 16.0 * tol2 || depth >= 16 {
        emit(p1)
        return
    }
    let q0 = (0.5 * (p0.0 + c1.0), 0.5 * (p0.1 + c1.1))
    let q1 = (0.5 * (c1.0 + c2.0), 0.5 * (c1.1 + c2.1))
    let q2 = (0.5 * (c2.0 + p1.0), 0.5 * (c2.1 + p1.1))
    let r0 = (0.5 * (q0.0 + q1.0), 0.5 * (q0.1 + q1.1))
    let r1 = (0.5 * (q1.0 + q2.0), 0.5 * (q1.1 + q2.1))
    let m = (0.5 * (r0.0 + r1.0), 0.5 * (r0.1 + r1.1))
    flattenCubicTo(p0, q0, r0, m, tol2: tol2, depth: depth + 1, emit: emit)
    flattenCubicTo(m, r1, q2, p1, tol2: tol2, depth: depth + 1, emit: emit)
}

enum ScanlineMask {
    static func renderTopLeft(
        commands: [PathCommand],
        scale: Double,
        width: Int,
        height: Int,
        fillRule: ScanlineFillRule
    ) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var polygons: [[(Double, Double)]] = []
        var cur: [(Double, Double)] = []
        var startPt: (Double, Double) = (0, 0)
        var pen: (Double, Double) = (0, 0)

        for cmd in commands {
            switch cmd {
            case .moveTo(let p):
                if cur.count >= 2 {
                    polygons.append(cur)
                }
                cur.removeAll(keepingCapacity: true)
                let sp = (Double(p.x) * scale, Double(p.y) * scale)
                startPt = sp
                pen = sp
                cur.append(sp)
            case .lineTo(let p):
                let sp = (Double(p.x) * scale, Double(p.y) * scale)
                cur.append(sp)
                pen = sp
            case .quadTo(let c, let p):
                let sc = (Double(c.x) * scale, Double(c.y) * scale)
                let sp = (Double(p.x) * scale, Double(p.y) * scale)
                flattenQuadTo(pen, sc, sp, tol2: 0.0004, depth: 0) { cur.append($0) }
                pen = sp
            case .curveTo(let c1, let c2, let p):
                let sc1 = (Double(c1.x) * scale, Double(c1.y) * scale)
                let sc2 = (Double(c2.x) * scale, Double(c2.y) * scale)
                let sp = (Double(p.x) * scale, Double(p.y) * scale)
                flattenCubicTo(pen, sc1, sc2, sp, tol2: 0.0004, depth: 0) { cur.append($0) }
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
        return renderPolygons(polygons: polygons, width: width, height: height, fillRule: fillRule, positiveUnion: false)
    }

    static func renderTopLeftPolygons(
        polygons: [[(Double, Double)]],
        width: Int,
        height: Int,
        positiveUnion: Bool
    ) -> [UInt8] {
        renderPolygons(polygons: polygons, width: width, height: height, fillRule: .nonZero, positiveUnion: positiveUnion)
    }

    /// Render closed polygons in `Origin.bottomLeft` (y-up) coordinates into a tight cropped mask + `Rasterized` placement,
    /// matching `zeno::Mask::new(path).origin(Origin::BottomLeft).render()`.
    static func renderBottomLeft(
        polygonsYUp: [[(Double, Double)]],
        fillRule: ScanlineFillRule = .nonZero
    ) -> ([UInt8], Rasterized) {
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        for poly in polygonsYUp where poly.count >= 2 {
            for pt in poly {
                if pt.0 < minX { minX = pt.0 }
                if pt.0 > maxX { maxX = pt.0 }
                if pt.1 < minY { minY = pt.1 }
                if pt.1 > maxY { maxY = pt.1 }
            }
        }
        guard minX.isFinite, maxX > minX, maxY > minY else {
            return ([], Rasterized(left: 0, top: 0, w: 0, h: 0))
        }
        let ix0 = Int32(minX.rounded(.down))
        let ix1 = Int32(maxX.rounded(.up))
        let iy0 = Int32(minY.rounded(.down))
        let iy1 = Int32(maxY.rounded(.up))
        let w = Int(max(0, ix1 - ix0))
        let h = Int(max(0, iy1 - iy0))
        guard w > 0, h > 0 else {
            return ([], Rasterized(left: ix0, top: iy1, w: 0, h: 0))
        }
        let ox = Double(ix0)
        let oy = Double(iy1)
        var mapped: [[(Double, Double)]] = []
        mapped.reserveCapacity(polygonsYUp.count)
        for poly in polygonsYUp where poly.count >= 2 {
            mapped.append(poly.map { ($0.0 - ox, oy - $0.1) })
        }
        let data = renderPolygons(polygons: mapped, width: w, height: h, fillRule: fillRule, positiveUnion: false)
        return (data, Rasterized(left: ix0, top: iy1, w: UInt32(w), h: UInt32(h)))
    }

    private static func renderPolygons(
        polygons: [[(Double, Double)]],
        width: Int,
        height: Int,
        fillRule: ScanlineFillRule,
        positiveUnion: Bool
    ) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var area = [Double](repeating: 0.0, count: width * height)
        var delta = [Double](repeating: 0.0, count: (width + 1) * height)

        for poly in polygons {
            let n = poly.count
            guard n >= 2 else { continue }
            for i in 0..<n {
                let a = poly[i]
                let b = poly[(i + 1) % n]
                addEdge(x0: a.0, y0: a.1, x1: b.0, y1: b.1, width: width, height: height, area: &area, delta: &delta)
            }
        }

        var out = [UInt8](repeating: 0, count: width * height)
        for r in 0..<height {
            var winding = 0.0
            let areaBase = r * width
            let deltaBase = r * (width + 1)
            for c in 0..<width {
                winding += delta[deltaBase + c]
                let cov = winding + area[areaBase + c]
                let alpha: Double
                if positiveUnion {
                    alpha = min(max(cov, 0.0), 1.0)
                } else {
                    switch fillRule {
                    case .nonZero:
                        alpha = min(abs(cov), 1.0)
                    case .evenOdd:
                        let t = abs(cov).truncatingRemainder(dividingBy: 2.0)
                        alpha = t > 1.0 ? (2.0 - t) : t
                    }
                }
                if alpha > 0.0 {
                    out[areaBase + c] = UInt8(clamping: Int((alpha * 255.0 + 0.5).rounded(.down)))
                }
            }
        }
        return out
    }

    @inline(__always)
    private static func addEdge(
        x0: Double,
        y0: Double,
        x1: Double,
        y1: Double,
        width: Int,
        height: Int,
        area: inout [Double],
        delta: inout [Double]
    ) {
        if abs(y1 - y0) < 1e-12 { return }
        let dir: Double
        let xa: Double, ya: Double, xb: Double, yb: Double
        if y1 > y0 {
            dir = 1.0
            (xa, ya, xb, yb) = (x0, y0, x1, y1)
        } else {
            dir = -1.0
            (xa, ya, xb, yb) = (x1, y1, x0, y0)
        }
        let hD = Double(height)
        if yb <= 0.0 || ya >= hD { return }
        let wD = Double(width)
        let invDy = (xb - xa) / (yb - ya)
        let cy0 = max(ya, 0.0)
        let cy1 = min(yb, hD)
        let cx0 = (ya < 0.0) ? (xa + (0.0 - ya) * invDy) : xa
        let cx1 = (yb > hD) ? (xa + (hD - ya) * invDy) : xb

        let rStart = max(0, Int(cy0.rounded(.down)))
        let rEnd = min(height - 1, Int(cy1.rounded(.up)) - 1)
        if rStart > rEnd { return }

        for r in rStart...rEnd {
            let ry0 = max(cy0, Double(r))
            let ry1 = min(cy1, Double(r + 1))
            if ry1 <= ry0 { continue }
            let rx0 = (ry0 == cy0) ? cx0 : (xa + (ry0 - ya) * invDy)
            let rx1 = (ry1 == cy1) ? cx1 : (xa + (ry1 - ya) * invDy)
            let dyTotal = (ry1 - ry0) * dir

            let rowAreaBase = r * width
            let rowDeltaBase = r * (width + 1)

            if rx0 <= 0.0 && rx1 <= 0.0 {
                delta[rowDeltaBase] += dyTotal
                continue
            }
            if rx0 >= wD && rx1 >= wD {
                continue
            }

            let xLo = min(rx0, rx1)
            let xHi = max(rx0, rx1)
            let dyIn: Double
            if xLo < 0.0 || xHi > wD {
                let span = xHi - xLo
                if xLo < 0.0 && span > 0.0 {
                    delta[rowDeltaBase] += dyTotal * ((0.0 - xLo) / span)
                }
                let ix0 = min(max(rx0, 0.0), wD)
                let ix1 = min(max(rx1, 0.0), wD)
                dyIn = span > 0.0 ? (dyTotal * (abs(ix1 - ix0) / span)) : 0.0
                if abs(dyIn) < 1e-15 { continue }
                accumulateRowInterior(
                    sx0: min(ix0, ix1),
                    sx1: max(ix0, ix1),
                    dy: dyIn,
                    width: width,
                    rowAreaBase: rowAreaBase,
                    rowDeltaBase: rowDeltaBase,
                    area: &area,
                    delta: &delta
                )
            } else {
                accumulateRowInterior(
                    sx0: xLo,
                    sx1: xHi,
                    dy: dyTotal,
                    width: width,
                    rowAreaBase: rowAreaBase,
                    rowDeltaBase: rowDeltaBase,
                    area: &area,
                    delta: &delta
                )
            }
        }
    }

    @inline(__always)
    private static func accumulateRowInterior(
        sx0: Double,
        sx1: Double,
        dy: Double,
        width: Int,
        rowAreaBase: Int,
        rowDeltaBase: Int,
        area: inout [Double],
        delta: inout [Double]
    ) {
        let c0 = min(Int(sx0.rounded(.down)), width - 1)
        let c1 = min(Int(sx1.rounded(.down)), width - 1)
        if c0 == c1 {
            let xm = 0.5 * (sx0 + sx1) - Double(c0)
            area[rowAreaBase + c0] += (1.0 - xm) * dy
            delta[rowDeltaBase + c0 + 1] += dy
        } else {
            let invDx = dy / (sx1 - sx0)
            let w0 = Double(c0 + 1) - sx0
            let dy0 = w0 * invDx
            let xm0 = 0.5 * (sx0 + Double(c0 + 1)) - Double(c0)
            area[rowAreaBase + c0] += (1.0 - xm0) * dy0
            delta[rowDeltaBase + c0 + 1] += dy0

            if c0 + 1 < c1 {
                for c in (c0 + 1)..<c1 {
                    area[rowAreaBase + c] += 0.5 * invDx
                    delta[rowDeltaBase + c + 1] += invDx
                }
            }

            let w1 = sx1 - Double(c1)
            if w1 > 0.0 {
                let dy1 = w1 * invDx
                let xm1 = 0.5 * w1
                area[rowAreaBase + c1] += (1.0 - xm1) * dy1
                delta[rowDeltaBase + c1 + 1] += dy1
            }
        }
    }
}
