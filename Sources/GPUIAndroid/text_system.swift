// Swift-only: Android NDK system font discovery and TrueType text metrics/shaping/rasterization per ADR-0012

import Foundation
import GPUI
#if os(Android)
import CAndroidSys
import GPUIWGPU
#endif

// MARK: - Discovered Android System Font Descriptor

/// Metadata for a system font file discovered via Android NDK `ASystemFontIterator` or `AFontMatcher`.
public struct AndroidSystemFontEntry: Sendable, Equatable, Hashable {
    public var filePath: String
    public var inferredFamily: String
    public var weight: UInt16
    public var isItalic: Bool
    public var collectionIndex: Int
    public var locale: String?

    public init(
        filePath: String,
        inferredFamily: String,
        weight: UInt16 = 400,
        isItalic: Bool = false,
        collectionIndex: Int = 0,
        locale: String? = nil
    ) {
        self.filePath = filePath
        self.inferredFamily = inferredFamily
        self.weight = weight
        self.isItalic = isItalic
        self.collectionIndex = collectionIndex
        self.locale = locale
    }
}

/// Infers a clean font family name from an Android `/system/fonts/<File>.ttf` path before loading the full file.
public func inferAndroidFontFamilyName(fromFilePath path: String) -> String {
    let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    guard !filename.isEmpty else { return "Roboto" }

    let base = filename.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first
        .map(String.init) ?? filename

    switch base {
    case "RobotoStatic":
        return "Roboto"
    case "DroidSansMono":
        return "Droid Sans Mono"
    case "NotoColorEmoji", "NotoColorEmojiFlags":
        return "Noto Color Emoji"
    case "NotoSerif":
        return "Noto Serif"
    case "NotoSans":
        return "Noto Sans"
    case "CutiveMono":
        return "Cutive Mono"
    case "CarroisGothicSC":
        return "Carrois Gothic SC"
    case "ComingSoon":
        return "Coming Soon"
    case "DancingScript":
        return "Dancing Script"
    default:
        return base
    }
}

// MARK: - Clean-Room TrueType (.ttf / .ttc) Binary Parser & Rasterizer

private struct BigEndianReader {
    let bytes: [UInt8]

    var count: Int { bytes.count }

    func u8(_ offset: Int) -> UInt8? {
        guard offset >= 0, offset < bytes.count else { return nil }
        return bytes[offset]
    }

    func u16(_ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    func i16(_ offset: Int) -> Int16? {
        guard let raw = u16(offset) else { return nil }
        return Int16(bitPattern: raw)
    }

    func u32(_ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    func tag(_ offset: Int) -> String? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return String(decoding: bytes[offset..<(offset + 4)], as: UTF8.self)
    }
}

internal final class ParsedTrueTypeFont: Sendable {
    struct ContourPoint: Sendable {
        var x: Float
        var y: Float
        var onCurve: Bool
    }

    let familyName: String
    let weight: Float
    let isItalic: Bool
    let isEmoji: Bool
    let metrics: FontMetrics
    private let reader: BigEndianReader
    private let numGlyphs: Int
    private let indexToLocFormat: Int16
    private let locaOffset: Int?
    private let locaLength: Int
    private let glyfOffset: Int?
    private let glyfLength: Int
    private let advanceWidths: [UInt16]
    private let leftSideBearings: [Int16]
    private let cmapMap: [UInt32: UInt32]

    init?(
        data: Data,
        collectionIndex: Int = 0,
        fallbackFamily: String? = nil,
        overrideWeight: UInt16? = nil,
        overrideItalic: Bool? = nil
    ) {
        let rawBytes = [UInt8](data)
        let r = BigEndianReader(bytes: rawBytes)
        guard r.count >= 12, let headerTag = r.u32(0) else {
            return nil
        }

        let sfntOffset: Int
        if headerTag == 0x7474_6366 { // 'ttcf' TrueType Collection
            guard let numFonts = r.u32(8),
                  collectionIndex >= 0,
                  collectionIndex < Int(numFonts),
                  let tableDirOffset = r.u32(12 + collectionIndex * 4) else {
                return nil
            }
            sfntOffset = Int(tableDirOffset)
        } else if headerTag == 0x0001_0000 || headerTag == 0x7472_7565 || headerTag == 0x4F54_544F {
            sfntOffset = 0
        } else {
            return nil
        }

        guard let numTables = r.u16(sfntOffset + 4) else {
            return nil
        }

        var tables: [String: (offset: Int, length: Int)] = [:]
        for i in 0..<Int(numTables) {
            let rec = sfntOffset + 12 + i * 16
            guard let tag = r.tag(rec),
                  let off = r.u32(rec + 8),
                  let len = r.u32(rec + 12) else {
                continue
            }
            let ioff = Int(off)
            let ilen = Int(len)
            if ioff >= 0, ilen >= 0, ioff + ilen <= r.count {
                tables[tag] = (ioff, ilen)
            }
        }

        guard let head = tables["head"], head.length >= 54,
              let hhea = tables["hhea"], hhea.length >= 36,
              let maxp = tables["maxp"], maxp.length >= 6 else {
            return nil
        }

        let unitsPerEm = max(16, UInt32(r.u16(head.offset + 18) ?? 1000))
        let xMin = Float(r.i16(head.offset + 36) ?? -200)
        let yMin = Float(r.i16(head.offset + 38) ?? -250)
        let xMax = Float(r.i16(head.offset + 40) ?? 1200)
        let yMax = Float(r.i16(head.offset + 42) ?? 1050)
        let macStyle = r.u16(head.offset + 44) ?? 0
        let locFormat = r.i16(head.offset + 50) ?? 0

        let hheaAscent = Float(r.i16(hhea.offset + 4) ?? 800)
        let hheaDescent = Float(r.i16(hhea.offset + 6) ?? -200)
        let hheaLineGap = Float(r.i16(hhea.offset + 8) ?? 0)
        let numberOfHMetrics = max(1, Int(r.u16(hhea.offset + 34) ?? 1))
        let glyphCount = max(1, Int(r.u16(maxp.offset + 4) ?? 1))

        var weightVal: Float = (macStyle & 0x01) != 0 ? 700.0 : 400.0
        var italicVal: Bool = (macStyle & 0x02) != 0
        var capHeight: Float = hheaAscent * 0.72
        var xHeight: Float = hheaAscent * 0.52

        if let os2 = tables["OS/2"], os2.length >= 64 {
            if let usWeight = r.u16(os2.offset + 4), usWeight >= 100 && usWeight <= 1000 {
                weightVal = Float(usWeight)
            }
            if let fsSelection = r.u16(os2.offset + 62), (fsSelection & 0x01) != 0 {
                italicVal = true
            }
            if let version = r.u16(os2.offset), version >= 2, os2.length >= 90 {
                if let sx = r.i16(os2.offset + 86), sx > 0 {
                    xHeight = Float(sx)
                }
                if let sc = r.i16(os2.offset + 88), sc > 0 {
                    capHeight = Float(sc)
                }
            }
        }
        if let overrideWeight {
            weightVal = Float(overrideWeight)
        }
        if let overrideItalic {
            italicVal = overrideItalic
        }

        var underlinePos: Float = -Float(unitsPerEm) * 0.1
        var underlineThick: Float = max(1.0, Float(unitsPerEm) * 0.05)
        if let post = tables["post"], post.length >= 12 {
            if let up = r.i16(post.offset + 8) {
                underlinePos = Float(up)
            }
            if let ut = r.i16(post.offset + 10), ut > 0 {
                underlineThick = Float(ut)
            }
        }

        let parsedName = Self.parseFamilyName(reader: r, nameTable: tables["name"])
        let resolvedFamily = (parsedName?.isEmpty == false ? parsedName : nil) ?? fallbackFamily ?? "Roboto"

        // Parse hmtx
        var advances = [UInt16](repeating: UInt16(unitsPerEm * 6 / 10), count: glyphCount)
        var lsbs = [Int16](repeating: 0, count: glyphCount)
        if let hmtx = tables["hmtx"] {
            let hCount = min(numberOfHMetrics, glyphCount)
            var lastAdv: UInt16 = UInt16(unitsPerEm * 6 / 10)
            for i in 0..<hCount {
                let off = hmtx.offset + i * 4
                if let adv = r.u16(off), let lsb = r.i16(off + 2) {
                    advances[i] = adv
                    lsbs[i] = lsb
                    lastAdv = adv
                }
            }
            for i in hCount..<glyphCount {
                advances[i] = lastAdv
                let lsbOff = hmtx.offset + hCount * 4 + (i - hCount) * 2
                if let lsb = r.i16(lsbOff) {
                    lsbs[i] = lsb
                }
            }
        }

        // Parse cmap (prefer format 12 UCS-4, then format 4 BMP)
        let cmapEntries = Self.parseCmap(reader: r, cmapTable: tables["cmap"])

        self.reader = r
        self.familyName = resolvedFamily
        self.weight = weightVal
        self.isItalic = italicVal
        self.isEmoji = resolvedFamily.localizedCaseInsensitiveContains("Emoji") || tables["CBDT"] != nil || tables["COLR"] != nil
        self.numGlyphs = glyphCount
        self.indexToLocFormat = locFormat
        self.locaOffset = tables["loca"]?.offset
        self.locaLength = tables["loca"]?.length ?? 0
        self.glyfOffset = tables["glyf"]?.offset
        self.glyfLength = tables["glyf"]?.length ?? 0
        self.advanceWidths = advances
        self.leftSideBearings = lsbs
        self.cmapMap = cmapEntries
        self.metrics = FontMetrics(
            unitsPerEm: unitsPerEm,
            ascent: hheaAscent,
            descent: hheaDescent,
            lineGap: hheaLineGap,
            underlinePosition: underlinePos,
            underlineThickness: underlineThick,
            capHeight: capHeight,
            xHeight: xHeight,
            boundingBox: Bounds(
                origin: Point(x: xMin, y: yMin),
                size: Size(width: max(0.0, xMax - xMin), height: max(0.0, yMax - yMin))
            )
        )
    }

    func glyphId(for scalar: UnicodeScalar) -> GlyphId? {
        if let gid = cmapMap[scalar.value], gid > 0, Int(gid) < numGlyphs {
            return GlyphId(gid)
        }
        return nil
    }

    func advanceWidth(for glyphId: GlyphId) -> Float {
        let idx = Int(glyphId.value)
        guard idx >= 0, idx < advanceWidths.count else {
            return Float(metrics.unitsPerEm) * 0.6
        }
        return Float(advanceWidths[idx])
    }

    func typographicBounds(for glyphId: GlyphId) -> Bounds<Float> {
        if let (xMin, yMin, xMax, yMax) = rawGlyphBox(glyphIndex: Int(glyphId.value)) {
            return Bounds(
                origin: Point(x: Float(xMin), y: Float(yMin)),
                size: Size(width: Float(max(0, Int(xMax) - Int(xMin))), height: Float(max(0, Int(yMax) - Int(yMin))))
            )
        }
        let adv = advanceWidth(for: glyphId)
        return Bounds(
            origin: .zero,
            size: Size(width: adv, height: metrics.ascent - metrics.descent)
        )
    }

    func rasterBounds(params: RenderGlyphParams) -> Bounds<DevicePixels> {
        let scale = (params.fontSize.value * params.scaleFactor) / Float(max(1, metrics.unitsPerEm))
        let subpixelShiftX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX)
        guard let (xMin, yMin, xMax, yMax) = rawGlyphBox(glyphIndex: Int(params.glyphId.value)),
              xMax > xMin, yMax > yMin else {
            return .zero
        }
        let minX = Int32((Float(xMin) * scale + subpixelShiftX).rounded(.down))
        let maxX = Int32((Float(xMax) * scale + subpixelShiftX).rounded(.up))
        // Screen Y grows downward while TrueType Y grows upward.
        let minY = Int32((-Float(yMax) * scale).rounded(.down))
        let maxY = Int32((-Float(yMin) * scale).rounded(.up))
        return Bounds(
            origin: Point(x: DevicePixels(minX), y: DevicePixels(minY)),
            size: Size(width: DevicePixels(max(0, maxX - minX)), height: DevicePixels(max(0, maxY - minY)))
        )
    }

    func rasterizeGlyph(params: RenderGlyphParams, rasterBounds: Bounds<DevicePixels>) -> (Size<DevicePixels>, Data) {
        let width = Int(max(0, rasterBounds.size.width.value))
        let height = Int(max(0, rasterBounds.size.height.value))
        let bytesPerPixel = (params.subpixelRendering || params.isEmoji) ? 4 : 1
        guard width > 0, height > 0 else {
            return (rasterBounds.size, Data())
        }

        let scale = (params.fontSize.value * params.scaleFactor) / Float(max(1, metrics.unitsPerEm))
        let shiftX = Float(params.subpixelVariant.x) / Float(subpixelVariantsX)
        let originX = Float(rasterBounds.origin.x.value)
        let originY = Float(rasterBounds.origin.y.value)

        let segments = flattenedOutlineSegments(glyphIndex: Int(params.glyphId.value), depth: 0)
        var coverage = [UInt8](repeating: 0, count: width * height)

        if !segments.isEmpty {
            // 4x vertical oversampling scanline winding-number rasterizer
            let subSamples = 4
            for py in 0..<height {
                var accum = [Int](repeating: 0, count: width)
                for sy in 0..<subSamples {
                    let screenY = originY + Float(py) + (Float(sy) + 0.5) / Float(subSamples)
                    let fontY = -screenY / max(scale, 1e-5)

                    var intersections: [Float] = []
                    for (p0, p1) in segments {
                        if (p0.y <= fontY && p1.y > fontY) || (p1.y <= fontY && p0.y > fontY) {
                            let t = (fontY - p0.y) / (p1.y - p0.y)
                            let ixFont = p0.x + t * (p1.x - p0.x)
                            let ixScreen = ixFont * scale + shiftX - originX
                            intersections.append(ixScreen)
                        }
                    }
                    guard intersections.count >= 2 else { continue }
                    intersections.sort()

                    var pairIdx = 0
                    while pairIdx + 1 < intersections.count {
                        let xStart = intersections[pairIdx]
                        let xEnd = intersections[pairIdx + 1]
                        let colStart = max(0, Int(xStart.rounded(.down)))
                        let colEnd = min(width - 1, Int(xEnd.rounded(.up)) - 1)
                        if colStart <= colEnd {
                            for pxCol in colStart...colEnd {
                                let pixelLeft = Float(pxCol)
                                let pixelRight = Float(pxCol + 1)
                                let overlap = max(0.0, min(xEnd, pixelRight) - max(xStart, pixelLeft))
                                accum[pxCol] += Int((overlap * 255.0).rounded())
                            }
                        }
                        pairIdx += 2
                    }
                }
                for pxCol in 0..<width {
                    coverage[py * width + pxCol] = UInt8(min(255, accum[pxCol] / subSamples))
                }
            }
        } else {
            // Bitmap/COLR fallback or synthetic glyph box fill
            for i in 0..<coverage.count {
                coverage[i] = 192
            }
        }

        if bytesPerPixel == 1 {
            return (rasterBounds.size, Data(coverage))
        } else {
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            for i in 0..<(width * height) {
                let a = coverage[i]
                rgba[i * 4] = a
                rgba[i * 4 + 1] = a
                rgba[i * 4 + 2] = a
                rgba[i * 4 + 3] = a
            }
            return (rasterBounds.size, Data(rgba))
        }
    }

    // MARK: - Private TrueType Table Helpers

    private func glyphSliceRange(glyphIndex: Int) -> (offset: Int, length: Int)? {
        guard glyphIndex >= 0, glyphIndex < numGlyphs,
              let locaOff = locaOffset,
              let glyfOff = glyfOffset else {
            return nil
        }
        let startRel: Int
        let endRel: Int
        if indexToLocFormat == 0 {
            guard (glyphIndex + 1) * 2 + 2 <= locaLength,
                  let s = reader.u16(locaOff + glyphIndex * 2),
                  let e = reader.u16(locaOff + (glyphIndex + 1) * 2) else {
                return nil
            }
            startRel = Int(s) * 2
            endRel = Int(e) * 2
        } else {
            guard (glyphIndex + 1) * 4 + 4 <= locaLength,
                  let s = reader.u32(locaOff + glyphIndex * 4),
                  let e = reader.u32(locaOff + (glyphIndex + 1) * 4) else {
                return nil
            }
            startRel = Int(s)
            endRel = Int(e)
        }
        guard endRel > startRel, endRel <= glyfLength else {
            return nil
        }
        return (glyfOff + startRel, endRel - startRel)
    }

    private func rawGlyphBox(glyphIndex: Int) -> (Int16, Int16, Int16, Int16)? {
        guard let slice = glyphSliceRange(glyphIndex: glyphIndex), slice.length >= 10,
              let xMin = reader.i16(slice.offset + 2),
              let yMin = reader.i16(slice.offset + 4),
              let xMax = reader.i16(slice.offset + 6),
              let yMax = reader.i16(slice.offset + 8) else {
            return nil
        }
        return (xMin, yMin, xMax, yMax)
    }

    private func flattenedOutlineSegments(glyphIndex: Int, depth: Int) -> [(Point<Float>, Point<Float>)] {
        guard depth < 6,
              let slice = glyphSliceRange(glyphIndex: glyphIndex),
              slice.length >= 10,
              let numberOfContours = reader.i16(slice.offset) else {
            return []
        }

        if numberOfContours == 0 {
            return []
        }

        if numberOfContours < 0 {
            // Composite glyph (`ARG_1_AND_2_ARE_WORDS`, `MORE_COMPONENTS`, etc.)
            var pos = slice.offset + 10
            let limit = slice.offset + slice.length
            var allSegments: [(Point<Float>, Point<Float>)] = []
            while pos + 4 <= limit {
                guard let flags = reader.u16(pos),
                      let compGlyphIndex = reader.u16(pos + 2) else {
                    break
                }
                pos += 4
                let argWords = (flags & 0x0001) != 0
                let argsAreXY = (flags & 0x0002) != 0
                var dx: Float = 0
                var dy: Float = 0
                if argWords {
                    guard pos + 4 <= limit else { break }
                    if argsAreXY {
                        dx = Float(reader.i16(pos) ?? 0)
                        dy = Float(reader.i16(pos + 2) ?? 0)
                    }
                    pos += 4
                } else {
                    guard pos + 2 <= limit else { break }
                    if argsAreXY, let b0 = reader.u8(pos), let b1 = reader.u8(pos + 1) {
                        dx = Float(Int8(bitPattern: b0))
                        dy = Float(Int8(bitPattern: b1))
                    }
                    pos += 2
                }

                if (flags & 0x0008) != 0 { // WE_HAVE_A_SCALE
                    pos += 2
                } else if (flags & 0x0040) != 0 { // WE_HAVE_AN_X_AND_Y_SCALE
                    pos += 4
                } else if (flags & 0x0080) != 0 { // WE_HAVE_A_TWO_BY_TWO
                    pos += 8
                }

                let subSegments = flattenedOutlineSegments(glyphIndex: Int(compGlyphIndex), depth: depth + 1)
                for (a, b) in subSegments {
                    allSegments.append((
                        Point(x: a.x + dx, y: a.y + dy),
                        Point(x: b.x + dx, y: b.y + dy)
                    ))
                }

                if (flags & 0x0020) == 0 { // MORE_COMPONENTS
                    break
                }
            }
            return allSegments
        }

        // Simple contour glyph
        let contourCount = Int(numberOfContours)
        let endsBase = slice.offset + 10
        guard endsBase + contourCount * 2 + 2 <= slice.offset + slice.length else {
            return []
        }

        var endPts: [Int] = []
        endPts.reserveCapacity(contourCount)
        for c in 0..<contourCount {
            guard let ep = reader.u16(endsBase + c * 2) else { return [] }
            endPts.append(Int(ep))
        }
        guard let lastPt = endPts.last, lastPt >= 0 else { return [] }
        let numPoints = lastPt + 1
        guard numPoints <= 4096 else { return [] }

        let insnLenOffset = endsBase + contourCount * 2
        guard let insnLen = reader.u16(insnLenOffset) else { return [] }
        var pos = insnLenOffset + 2 + Int(insnLen)
        let limit = slice.offset + slice.length

        var flags = [UInt8]()
        flags.reserveCapacity(numPoints)
        while flags.count < numPoints && pos < limit {
            guard let f = reader.u8(pos) else { return [] }
            pos += 1
            flags.append(f)
            if (f & 0x08) != 0 { // REPEAT_FLAG
                guard let repeatCount = reader.u8(pos) else { return [] }
                pos += 1
                for _ in 0..<Int(repeatCount) where flags.count < numPoints {
                    flags.append(f)
                }
            }
        }
        guard flags.count == numPoints else { return [] }

        var xs = [Float](repeating: 0, count: numPoints)
        var curX: Int32 = 0
        for i in 0..<numPoints {
            let f = flags[i]
            if (f & 0x02) != 0 { // X_SHORT_VECTOR
                guard let b = reader.u8(pos) else { return [] }
                pos += 1
                let delta = Int32(b)
                curX += ((f & 0x10) != 0) ? delta : -delta
            } else if (f & 0x10) == 0 {
                guard let d = reader.i16(pos) else { return [] }
                pos += 2
                curX += Int32(d)
            }
            xs[i] = Float(curX)
        }

        var ys = [Float](repeating: 0, count: numPoints)
        var curY: Int32 = 0
        for i in 0..<numPoints {
            let f = flags[i]
            if (f & 0x04) != 0 { // Y_SHORT_VECTOR
                guard let b = reader.u8(pos) else { return [] }
                pos += 1
                let delta = Int32(b)
                curY += ((f & 0x20) != 0) ? delta : -delta
            } else if (f & 0x20) == 0 {
                guard let d = reader.i16(pos) else { return [] }
                pos += 2
                curY += Int32(d)
            }
            ys[i] = Float(curY)
        }

        var segments: [(Point<Float>, Point<Float>)] = []
        var contourStart = 0
        for contourEnd in endPts {
            if contourEnd >= contourStart && contourEnd < numPoints {
                var pts: [ContourPoint] = []
                pts.reserveCapacity(contourEnd - contourStart + 1)
                for idx in contourStart...contourEnd {
                    pts.append(ContourPoint(x: xs[idx], y: ys[idx], onCurve: (flags[idx] & 0x01) != 0))
                }
                Self.appendContourSegments(pts, into: &segments)
            }
            contourStart = contourEnd + 1
        }
        return segments
    }

    private static func appendContourSegments(
        _ rawPoints: [ContourPoint],
        into segments: inout [(Point<Float>, Point<Float>)]
    ) {
        guard rawPoints.count >= 2 else { return }

        // Expand implied on-curve midpoints between consecutive quadratic off-curve control points.
        var expanded: [ContourPoint] = []
        let n = rawPoints.count
        for i in 0..<n {
            let curr = rawPoints[i]
            let next = rawPoints[(i + 1) % n]
            expanded.append(curr)
            if !curr.onCurve && !next.onCurve {
                expanded.append(
                    ContourPoint(
                        x: (curr.x + next.x) * 0.5,
                        y: (curr.y + next.y) * 0.5,
                        onCurve: true
                    )
                )
            }
        }

        guard let firstOnIdx = expanded.firstIndex(where: { $0.onCurve }) else {
            return
        }

        let m = expanded.count
        var idx = 0
        var currentPos = Point(x: expanded[firstOnIdx].x, y: expanded[firstOnIdx].y)

        while idx < m {
            let nextPoint = expanded[(firstOnIdx + idx + 1) % m]
            if nextPoint.onCurve {
                let target = Point(x: nextPoint.x, y: nextPoint.y)
                segments.append((currentPos, target))
                currentPos = target
                idx += 1
            } else {
                let ctrl = Point(x: nextPoint.x, y: nextPoint.y)
                let endPtRaw = expanded[(firstOnIdx + idx + 2) % m]
                let endPt = Point(x: endPtRaw.x, y: endPtRaw.y)
                let steps = 4
                var prev = currentPos
                for s in 1...steps {
                    let t = Float(s) / Float(steps)
                    let omt = 1.0 - t
                    let qx = omt * omt * currentPos.x + 2.0 * omt * t * ctrl.x + t * t * endPt.x
                    let qy = omt * omt * currentPos.y + 2.0 * omt * t * ctrl.y + t * t * endPt.y
                    let nextSegPt = Point(x: qx, y: qy)
                    segments.append((prev, nextSegPt))
                    prev = nextSegPt
                }
                currentPos = endPt
                idx += 2
            }
        }
    }

    private static func parseFamilyName(
        reader: BigEndianReader,
        nameTable: (offset: Int, length: Int)?
    ) -> String? {
        guard let table = nameTable, table.length >= 6,
              let count = reader.u16(table.offset + 2),
              let stringOffset = reader.u16(table.offset + 4) else {
            return nil
        }
        let storageBase = table.offset + Int(stringOffset)
        var fallbackCandidate: String?

        for i in 0..<Int(count) {
            let rec = table.offset + 6 + i * 12
            guard rec + 12 <= table.offset + table.length,
                  let platformID = reader.u16(rec),
                  let nameID = reader.u16(rec + 6),
                  let length = reader.u16(rec + 8),
                  let strOff = reader.u16(rec + 10) else {
                continue
            }
            // Name ID 1 = Font Family, Name ID 16 = Typographic Family
            guard nameID == 16 || nameID == 1 else { continue }
            let start = storageBase + Int(strOff)
            let len = Int(length)
            guard start >= 0, len > 0, start + len <= reader.count else { continue }

            if platformID == 3 || platformID == 0 {
                // UTF-16BE
                var utf16Units: [UInt16] = []
                utf16Units.reserveCapacity(len / 2)
                var p = start
                while p + 2 <= start + len {
                    if let unit = reader.u16(p) {
                        utf16Units.append(unit)
                    }
                    p += 2
                }
                let decoded = String(decoding: utf16Units, as: UTF16.self)
                    .trimmingCharacters(in: .controlCharacters)
                if !decoded.isEmpty {
                    if nameID == 16 { return decoded }
                    fallbackCandidate = decoded
                }
            } else if platformID == 1 && fallbackCandidate == nil {
                let decoded = String(decoding: reader.bytes[start..<(start + len)], as: UTF8.self)
                    .trimmingCharacters(in: .controlCharacters)
                if !decoded.isEmpty {
                    fallbackCandidate = decoded
                }
            }
        }
        return fallbackCandidate
    }

    private static func parseCmap(
        reader: BigEndianReader,
        cmapTable: (offset: Int, length: Int)?
    ) -> [UInt32: UInt32] {
        guard let table = cmapTable, table.length >= 4,
              let numTables = reader.u16(table.offset + 2) else {
            return [:]
        }

        var format12Offset: Int?
        var format4Offset: Int?

        for i in 0..<Int(numTables) {
            let rec = table.offset + 4 + i * 8
            guard rec + 8 <= table.offset + table.length,
                  let platformID = reader.u16(rec),
                  let subOffset = reader.u32(rec + 4) else {
                continue
            }
            guard platformID == 0 || platformID == 3 else { continue }
            let absOff = table.offset + Int(subOffset)
            guard let fmt = reader.u16(absOff) else { continue }
            if fmt == 12 && format12Offset == nil {
                format12Offset = absOff
            } else if fmt == 4 && format4Offset == nil {
                format4Offset = absOff
            }
        }

        if let f12 = format12Offset {
            let map = parseCmapFormat12(reader: reader, offset: f12)
            if !map.isEmpty { return map }
        }
        if let f4 = format4Offset {
            return parseCmapFormat4(reader: reader, offset: f4)
        }
        return [:]
    }

    private static func parseCmapFormat12(reader: BigEndianReader, offset: Int) -> [UInt32: UInt32] {
        guard let numGroups = reader.u32(offset + 12) else { return [:] }
        var result: [UInt32: UInt32] = [:]
        let groupCount = min(Int(numGroups), 65_536)
        for i in 0..<groupCount {
            let g = offset + 16 + i * 12
            guard let startChar = reader.u32(g),
                  let endChar = reader.u32(g + 4),
                  let startGlyph = reader.u32(g + 8),
                  endChar >= startChar,
                  (endChar - startChar) <= 0x10FFFF else {
                continue
            }
            for cp in startChar...endChar {
                result[cp] = startGlyph + (cp - startChar)
            }
        }
        return result
    }

    private static func parseCmapFormat4(reader: BigEndianReader, offset: Int) -> [UInt32: UInt32] {
        guard let segCountX2 = reader.u16(offset + 6) else { return [:] }
        let segCount = Int(segCountX2) / 2
        guard segCount > 0 else { return [:] }

        let endCodeBase = offset + 14
        let startCodeBase = endCodeBase + segCount * 2 + 2
        let idDeltaBase = startCodeBase + segCount * 2
        let idRangeOffsetBase = idDeltaBase + segCount * 2

        var result: [UInt32: UInt32] = [:]
        for seg in 0..<segCount {
            guard let endCode = reader.u16(endCodeBase + seg * 2),
                  let startCode = reader.u16(startCodeBase + seg * 2),
                  let idDelta = reader.i16(idDeltaBase + seg * 2),
                  let idRangeOffset = reader.u16(idRangeOffsetBase + seg * 2) else {
                continue
            }
            if startCode == 0xFFFF && endCode == 0xFFFF {
                break
            }
            guard endCode >= startCode else { continue }
            for code in UInt32(startCode)...UInt32(endCode) {
                let glyphId: UInt32
                if idRangeOffset == 0 {
                    glyphId = UInt32((Int(code) + Int(idDelta)) & 0xFFFF)
                } else {
                    let glyphIndexOffset = idRangeOffsetBase
                        + seg * 2
                        + Int(idRangeOffset)
                        + Int(code - UInt32(startCode)) * 2
                    guard let rawGid = reader.u16(glyphIndexOffset), rawGid != 0 else {
                        continue
                    }
                    glyphId = UInt32((Int(rawGid) + Int(idDelta)) & 0xFFFF)
                }
                if glyphId != 0 {
                    result[code] = glyphId
                }
            }
        }
        return result
    }
}

// MARK: - AndroidTextSystem

/// Android implementation of `PlatformTextSystem`.
///
/// On Android API 29+, enumerates `/system/fonts` via `ASystemFontIterator` and matches
/// font families/styles via `AFontMatcher` (`CAndroidSys`), wraps `CosmicTextSystem` (`GPUIWGPU`),
/// and parses TrueType font metrics, `cmap`, `hmtx`, and `glyf` outlines for accurate layout
/// and grayscale glyph rasterization without requiring desktop `libfontconfig`.
// PORT NOTE: Synchronized via NSLock so concurrent background layout and main-thread rendering are safe.
public final class AndroidTextSystem: PlatformTextSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var parsedFaces: [ParsedTrueTypeFont] = []
    private var familyToFontIds: [String: [FontId]] = [:]
    private var systemCatalog: [AndroidSystemFontEntry] = []
    private var loadedSystemKeys: Set<String> = []
    public let systemFontFallback: String

    #if os(Android)
    private let cosmicFallback: CosmicTextSystem
    #endif

    public init(systemFontFallback: String = "Roboto", scanSystemFonts: Bool = true) {
        self.systemFontFallback = systemFontFallback
        #if os(Android)
        self.cosmicFallback = CosmicTextSystem.new(systemFontFallback)
        #endif

        if scanSystemFonts {
            discoverAndroidSystemFonts()
        }
    }

    public static func new(_ systemFontFallback: String = "Roboto") -> AndroidTextSystem {
        AndroidTextSystem(systemFontFallback: systemFontFallback)
    }

    /// Returns the system font entries discovered via NDK `ASystemFontIterator`.
    public func discoveredSystemFonts() -> [AndroidSystemFontEntry] {
        lock.lock()
        defer { lock.unlock() }
        return systemCatalog
    }

    // MARK: - PlatformTextSystem Conformance

    public func addFonts(_ fonts: [Data]) throws {
        #if os(Android)
        try? cosmicFallback.addFonts(fonts)
        #endif

        lock.lock()
        defer { lock.unlock() }

        for data in fonts {
            guard let parsed = ParsedTrueTypeFont(data: data) else {
                throw AndroidError("Failed to parse TrueType/OpenType font data")
            }
            let id = FontId(parsedFaces.count)
            parsedFaces.append(parsed)
            familyToFontIds[parsed.familyName.lowercased(), default: []].append(id)
        }
    }

    public func allFontNames() -> [String] {
        lock.lock()
        var names = Set<String>()
        for face in parsedFaces {
            names.insert(face.familyName)
        }
        for entry in systemCatalog {
            names.insert(entry.inferredFamily)
        }
        names.insert(systemFontFallback)
        lock.unlock()

        #if os(Android)
        for name in cosmicFallback.allFontNames() {
            names.insert(name)
        }
        #endif

        return names.sorted()
    }

    public func fontId(descriptor: Font) throws -> FontId {
        let resolvedName = fontNameWithFallbacks(descriptor.family.asString, system: systemFontFallback)
        let targetKey = resolvedName.lowercased()

        lock.lock()
        if let match = bestLoadedMatchLocked(familyKey: targetKey, descriptor: descriptor) {
            lock.unlock()
            return match
        }
        lock.unlock()

        // Attempt lazy load from discovered NDK system font catalog or AFontMatcher.
        if let loadedId = tryLoadSystemFamily(familyName: resolvedName, descriptor: descriptor) {
            return loadedId
        }

        if targetKey != systemFontFallback.lowercased(),
           let fallbackId = tryLoadSystemFamily(familyName: systemFontFallback, descriptor: descriptor) {
            return fallbackId
        }

        lock.lock()
        if let firstLoaded = parsedFaces.indices.first {
            lock.unlock()
            return FontId(firstLoaded)
        }
        lock.unlock()

        #if os(Android)
        return try cosmicFallback.fontId(descriptor: descriptor)
        #else
        return FontId(0)
        #endif
    }

    public func fontMetrics(fontId: FontId) -> FontMetrics {
        if let face = faceForId(fontId) {
            return face.metrics
        }
        #if os(Android)
        return cosmicFallback.fontMetrics(fontId: fontId)
        #else
        return FontMetrics(
            unitsPerEm: 1000,
            ascent: 928.0,
            descent: -244.0,
            lineGap: 0.0,
            underlinePosition: -100.0,
            underlineThickness: 50.0,
            capHeight: 710.0,
            xHeight: 528.0,
            boundingBox: Bounds(origin: Point(x: -200.0, y: -244.0), size: Size(width: 1400.0, height: 1172.0))
        )
        #endif
    }

    public func typographicBounds(fontId: FontId, glyphId: GlyphId) throws -> Bounds<Float> {
        if let face = faceForId(fontId) {
            return face.typographicBounds(for: glyphId)
        }
        #if os(Android)
        return try cosmicFallback.typographicBounds(fontId: fontId, glyphId: glyphId)
        #else
        return Bounds(origin: .zero, size: Size(width: 600.0, height: 1000.0))
        #endif
    }

    public func advance(fontId: FontId, glyphId: GlyphId) throws -> Size<Float> {
        if let face = faceForId(fontId) {
            return Size(width: face.advanceWidth(for: glyphId), height: 0.0)
        }
        #if os(Android)
        return try cosmicFallback.advance(fontId: fontId, glyphId: glyphId)
        #else
        return Size(width: 600.0, height: 0.0)
        #endif
    }

    public func glyphForChar(fontId: FontId, ch: Character) -> GlyphId? {
        if let face = faceForId(fontId) {
            if let scalar = ch.unicodeScalars.first, let gid = face.glyphId(for: scalar) {
                return gid
            }
            return nil
        }
        #if os(Android)
        return cosmicFallback.glyphForChar(fontId: fontId, ch: ch)
        #else
        guard let scalar = ch.unicodeScalars.first else { return nil }
        return GlyphId(scalar.value)
        #endif
    }

    public func glyphRasterBounds(params: RenderGlyphParams) throws -> Bounds<DevicePixels> {
        if let face = faceForId(params.fontId) {
            return face.rasterBounds(params: params)
        }
        #if os(Android)
        return try cosmicFallback.glyphRasterBounds(params: params)
        #else
        let w = max(1, Int32((params.fontSize.value * params.scaleFactor * 0.6).rounded(.up)))
        let h = max(1, Int32((params.fontSize.value * params.scaleFactor).rounded(.up)))
        return Bounds(
            origin: Point(x: DevicePixels(0), y: DevicePixels(-h)),
            size: Size(width: DevicePixels(w), height: DevicePixels(h))
        )
        #endif
    }

    public func rasterizeGlyph(
        params: RenderGlyphParams,
        rasterBounds: Bounds<DevicePixels>
    ) throws -> (Size<DevicePixels>, Data) {
        if let face = faceForId(params.fontId) {
            return face.rasterizeGlyph(params: params, rasterBounds: rasterBounds)
        }
        #if os(Android)
        return try cosmicFallback.rasterizeGlyph(params: params, rasterBounds: rasterBounds)
        #else
        let w = Int(max(0, rasterBounds.size.width.value))
        let h = Int(max(0, rasterBounds.size.height.value))
        let channels = (params.subpixelRendering || params.isEmoji) ? 4 : 1
        return (rasterBounds.size, Data(repeating: 200, count: w * h * channels))
        #endif
    }

    public func layoutLine(text: String, fontSize: Pixels, runs: [FontRun]) -> LineLayout {
        guard !text.isEmpty else {
            return LineLayout(
                fontSize: fontSize,
                width: .zero,
                ascent: .zero,
                descent: .zero,
                runs: [],
                len: 0
            )
        }

        let effectiveRuns: [FontRun]
        if runs.isEmpty {
            effectiveRuns = [FontRun(len: text.utf8.count, fontId: FontId(0))]
        } else {
            effectiveRuns = runs
        }

        let utf8Count = text.utf8.count
        var shapedRuns: [ShapedRun] = []
        var cursorX: Float = 0.0
        var maxAscent: Float = 0.0
        var maxDescent: Float = 0.0
        var consumedUtf8 = 0

        // Build UTF-8 byte offset -> Character list once for accurate cluster indexing.
        var charactersWithByteOffsets: [(offset: Int, length: Int, char: Character)] = []
        charactersWithByteOffsets.reserveCapacity(text.count)
        var runningByteOffset = 0
        for ch in text {
            let len = ch.utf8.count
            charactersWithByteOffsets.append((runningByteOffset, len, ch))
            runningByteOffset += len
        }

        var charCursor = 0
        for run in effectiveRuns {
            let runEnd = min(utf8Count, consumedUtf8 + max(0, run.len))
            guard runEnd > consumedUtf8 else { continue }

            let metrics = fontMetrics(fontId: run.fontId)
            let scale = fontSize.value / Float(max(1, metrics.unitsPerEm))
            let runAscent = metrics.ascent * scale
            let runDescent = abs(metrics.descent) * scale
            if runAscent > maxAscent { maxAscent = runAscent }
            if runDescent > maxDescent { maxDescent = runDescent }

            let face = faceForId(run.fontId)
            var glyphs: [ShapedGlyph] = []

            while charCursor < charactersWithByteOffsets.count {
                let item = charactersWithByteOffsets[charCursor]
                if item.offset >= runEnd {
                    break
                }
                charCursor += 1

                let scalar = item.char.unicodeScalars.first
                let isEmojiChar = (face?.isEmoji == true)
                    || (scalar?.properties.isEmojiPresentation == true)
                let gid: GlyphId
                let advancePx: Float

                if let face, let s = scalar, let matchedGid = face.glyphId(for: s) {
                    gid = matchedGid
                    advancePx = face.advanceWidth(for: matchedGid) * scale
                } else if let fallbackGid = glyphForChar(fontId: run.fontId, ch: item.char) {
                    gid = fallbackGid
                    let advUnits = (try? advance(fontId: run.fontId, glyphId: fallbackGid).width) ?? 600.0
                    advancePx = advUnits * scale
                } else {
                    gid = GlyphId(scalar?.value ?? 0)
                    advancePx = fontSize.value * (isEmojiChar ? 1.0 : 0.6)
                }

                glyphs.append(
                    ShapedGlyph(
                        id: gid,
                        position: Point(x: px(cursorX), y: .zero),
                        index: item.offset,
                        isEmoji: isEmojiChar
                    )
                )
                cursorX += advancePx
            }

            shapedRuns.append(ShapedRun(fontId: run.fontId, glyphs: glyphs))
            consumedUtf8 = runEnd
        }

        return LineLayout(
            fontSize: fontSize,
            width: px(cursorX),
            ascent: px(maxAscent),
            descent: px(maxDescent),
            runs: shapedRuns,
            len: utf8Count
        )
    }

    public func recommendedRenderingMode(fontId: FontId, fontSize: Pixels) -> TextRenderingMode {
        _ = fontId
        _ = fontSize
        // Mobile OLED/AMOLED panels use PenTile/Diamond subpixel geometry and dynamic orientation,
        // so grayscale anti-aliasing avoids color fringing across portrait and landscape rotations.
        return .grayscale
    }

    // MARK: - NDK System Font Enumeration & On-Demand Loading

    private func faceForId(_ id: FontId) -> ParsedTrueTypeFont? {
        lock.lock()
        defer { lock.unlock() }
        guard id.value >= 0, id.value < parsedFaces.count else {
            return nil
        }
        return parsedFaces[id.value]
    }

    private func bestLoadedMatchLocked(familyKey: String, descriptor: Font) -> FontId? {
        guard let ids = familyToFontIds[familyKey], !ids.isEmpty else {
            return nil
        }
        let wantItalic = descriptor.style != .normal
        let wantWeight = descriptor.weight.value

        var bestId = ids[0]
        var bestScore = Float.greatestFiniteMagnitude
        for id in ids where id.value >= 0 && id.value < parsedFaces.count {
            let candidate = parsedFaces[id.value]
            let italicPenalty: Float = (candidate.isItalic == wantItalic) ? 0.0 : 500.0
            let weightPenalty = abs(candidate.weight - wantWeight)
            let score = italicPenalty + weightPenalty
            if score < bestScore {
                bestScore = score
                bestId = id
            }
        }
        return bestId
    }

    private func discoverAndroidSystemFonts() {
        #if os(Android)
        guard let iterator = candroid_system_font_iterator_open() else {
            return
        }
        defer {
            candroid_system_font_iterator_close(iterator)
        }

        var discovered: [AndroidSystemFontEntry] = []
        while let font = candroid_system_font_iterator_next(iterator) {
            let path = String(cString: candroid_font_get_file_path(font))
            let weight = candroid_font_get_weight(font)
            let isItalic = candroid_font_is_italic(font)
            let collectionIdx = Int(candroid_font_get_collection_index(font))
            let locale = candroid_font_get_locale(font).map { String(cString: $0) }
            candroid_font_close(font)

            let family = inferAndroidFontFamilyName(fromFilePath: path)
            discovered.append(
                AndroidSystemFontEntry(
                    filePath: path,
                    inferredFamily: family,
                    weight: weight,
                    isItalic: isItalic,
                    collectionIndex: collectionIdx,
                    locale: locale
                )
            )
        }

        lock.lock()
        self.systemCatalog = discovered
        lock.unlock()

        // Eagerly load primary Roboto Regular face if available so default UI metrics are immediate.
        _ = tryLoadSystemFamily(
            familyName: systemFontFallback,
            descriptor: Font(family: SharedString(systemFontFallback), weight: .normal, style: .normal)
        )
        #endif
    }

    private func tryLoadSystemFamily(familyName: String, descriptor: Font) -> FontId? {
        #if os(Android)
        let wantItalic = descriptor.style != .normal
        let wantWeight = UInt16(min(max(Int(descriptor.weight.value.rounded()), 100), 900))

        // First try NDK AFontMatcher for exact OS family alias resolution ("sans-serif", "Roboto", etc.)
        if let matcher = candroid_font_matcher_create() {
            defer { candroid_font_matcher_destroy(matcher) }
            candroid_font_matcher_set_style(matcher, wantWeight, wantItalic)
            var sampleUnit: UInt16 = 0x0041 // 'A'
            let matchedFont: OpaquePointer? = familyName.withCString { cFamily in
                withUnsafePointer(to: &sampleUnit) { textPtr in
                    candroid_font_matcher_match(matcher, cFamily, textPtr, 1, nil)
                }
            }
            if let font = matchedFont {
                let path = String(cString: candroid_font_get_file_path(font))
                let weight = candroid_font_get_weight(font)
                let italic = candroid_font_is_italic(font)
                let colIdx = Int(candroid_font_get_collection_index(font))
                candroid_font_close(font)

                let entry = AndroidSystemFontEntry(
                    filePath: path,
                    inferredFamily: familyName,
                    weight: weight,
                    isItalic: italic,
                    collectionIndex: colIdx
                )
                if let id = loadFontEntryIfNeeded(entry, aliasFamily: familyName) {
                    return id
                }
            }
        }
        #endif

        lock.lock()
        let matches = systemCatalog.filter {
            $0.inferredFamily.caseInsensitiveCompare(familyName) == .orderedSame
        }
        lock.unlock()

        guard !matches.isEmpty else { return nil }
        for entry in matches {
            _ = loadFontEntryIfNeeded(entry, aliasFamily: familyName)
        }

        lock.lock()
        defer { lock.unlock() }
        return bestLoadedMatchLocked(familyKey: familyName.lowercased(), descriptor: descriptor)
    }

    private func loadFontEntryIfNeeded(_ entry: AndroidSystemFontEntry, aliasFamily: String) -> FontId? {
        let cacheKey = "\(entry.filePath)#\(entry.collectionIndex)#\(entry.weight)#\(entry.isItalic)"
        lock.lock()
        if loadedSystemKeys.contains(cacheKey),
           let existing = familyToFontIds[aliasFamily.lowercased()]?.first {
            lock.unlock()
            return existing
        }
        lock.unlock()

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: entry.filePath), options: .mappedIfSafe),
              let parsed = ParsedTrueTypeFont(
                  data: data,
                  collectionIndex: entry.collectionIndex,
                  fallbackFamily: entry.inferredFamily,
                  overrideWeight: entry.weight,
                  overrideItalic: entry.isItalic
              ) else {
            return nil
        }

        #if os(Android)
        if entry.collectionIndex == 0 {
            try? cosmicFallback.addFonts([data])
        }
        #endif

        lock.lock()
        defer { lock.unlock() }
        loadedSystemKeys.insert(cacheKey)
        let id = FontId(parsedFaces.count)
        parsedFaces.append(parsed)
        familyToFontIds[parsed.familyName.lowercased(), default: []].append(id)
        familyToFontIds[aliasFamily.lowercased(), default: []].append(id)
        return id
    }
}
